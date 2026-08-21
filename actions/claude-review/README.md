# `claude-review` — the shared half of the PR review gate

One implementation of the model call that every repo's `pr-review.yml` was
copy-pasting. Three defects have been found in that call, and each one existed in
up to nine copies at once:

| defect | what it did |
|---|---|
| `anthropic-version: 2025-04-15` | rejected by the API, so **every review ever produced came from the fallback**, at 8192 tokens with no extended thinking |
| `.content[0].text` | truncated multi-block replies, and would have blocked **every PR in the repo** the day a model pin emitted thinking blocks |
| a 120,000-**byte** cap | stood in for a token budget and refused at roughly **a fifth of the window** |

## Why an action and not a reusable workflow

`Claude Code Review` is a **required status context** on `main` in six repos. A
reusable workflow called at the job level renames its check to
`<caller-job> / <called-job>`, so that required context would never appear again
and every PR in all six would block until branch protection was edited in each —
a coordinated six-repo change where any slip is an outage.

A composite action is a **step inside the caller's existing job**, so the job name,
and therefore the check name, is untouched.

## What it does not own

The **system prompt** stays in the calling repo: each repo's tech stack and review
focus are legitimately its own. So do diff gathering and review posting, which
depend on per-repo permissions and formatting. Share what drifted; keep local what
should vary.

## The verdict is bound to the run — your prompt must cooperate

The action mints a per-run nonce and substitutes it into your system prompt
wherever `__NONCE__` appears. The reply's **first line must then equal**
`VERDICT-<nonce>: APPROVE` or `VERDICT-<nonce>: REQUEST_CHANGES` exactly.

That binding is the point: the diff is attacker-authored text, and a model can be
pushed to echo a verdict-shaped line. A marker that did not exist until this run
started cannot be pre-placed in a pull request. A first line that merely *contains*
`APPROVE` is not accepted.

So your system prompt must carry the placeholder in its verdict instruction:

```
Your reply MUST BEGIN with exactly one of these two lines:
VERDICT-__NONCE__: APPROVE
VERDICT-__NONCE__: REQUEST_CHANGES
```

A prompt without `__NONCE__` is `INCONCLUSIVE` **with that stated as the reason** —
not silently unverified. The nonce is stripped from the posted body, because
echoing it into a comment would let a later run read it back, which is the attack
it exists to prevent.

## Usage

The caller renders two files, calls this action, then posts and enforces.

```yaml
jobs:
  review:
    name: Claude Code Review     # <- this string IS the required context. Do not change it.
    runs-on: ubuntu-latest
    steps:
      # ... build /tmp/system_prompt.txt and /tmp/user_msg.txt ...

      - id: review
        uses: opena2a-org/.github/actions/claude-review@PIN_A_SHA  # see below
        with:
          anthropic-api-key: SECRET_REFERENCE   # your repo's Anthropic key secret
          system-prompt-file: /tmp/system_prompt.txt
          user-message-file: /tmp/user_msg.txt

      - name: Enforce verdict
        if: steps.review.outputs.verdict != 'APPROVE'
        run: exit 1
```

Replace `SECRET_REFERENCE` with your repo's secret expression — a composite action
cannot read `secrets` itself, so the caller passes it in.

## Extended thinking and the fallback

`thinking-budget` (default `0`, off) puts the primary request in extended-thinking
mode. Eight of the nine gates this action replaces used `10000` with
`max-tokens: 16000`. **`max-tokens` must exceed `thinking-budget`** — the API
requires it, and this action refuses with that as the reason rather than letting
you discover it as a 400 at review time.

When thinking is on and the primary request fails or returns no text, the action
**retries once without thinking** at `fallback-max-tokens` (default `8192`),
**reusing the same nonce**. A fresh nonce there would mean the model was told a
different marker than the one being checked, so every fallback review would come
back inconclusive.

With thinking off there is no retry: it would be byte-identical to the request that
just failed.

`review-path` reports which request answered. **Surface it.** A fallback that runs
on every PR is indistinguishable from a primary that works — which is exactly how an
invalid `anthropic-version` went unnoticed across nine repos while every review
silently came from the fallback.

## Outputs

- `verdict` — `APPROVE`, `REQUEST_CHANGES` or `INCONCLUSIVE`. Never empty.
- `review-file` — path to the review body, written for **every** verdict.
- `input-tokens` — measured input tokens, empty only if the measurement itself failed.
- `review-path` — `primary` or `fallback`.

**`INCONCLUSIVE` is a third state, not a pass.** The caller must fail the job on it.
Every failure path in the action resolves to `INCONCLUSIVE`: no key, missing prompt
files, `count_tokens` non-200 or unparseable, over budget, API non-200, no text
blocks, or a reply with no verdict on its first line. Nothing resolves a failure
into `APPROVE`.

## Pin a SHA, not `@main`

`@main` moves every consuming repo the instant this file changes — a bad edit here
would reach every merge gate in the org before anyone reviewed it.

Resolve the current SHA when you adopt or bump:

```bash
gh api repos/opena2a-org/.github/commits/main --jq '.sha[0:7]'
```

and pin that. A SHA is stronger than a tag, not a substitute for one: a tag can be
moved to point at different code, a SHA cannot.

**This file deliberately does not hardcode the SHA.** An earlier version did, and it
was stale within hours — pointing adopters at the revision before the nonce binding
landed, i.e. at the version missing a security property. A pin that names the wrong
revision is worse than no pin, because it looks deliberate. Resolve it at adoption
time instead.

Bumping a consumer is then a visible one-line change in that repo's own PR, which is
the point: no repo's gate moves without someone approving it there.


## Changing the model

Read the extraction note in `action.yml` first. The `token-budget` default assumes a
200,000-token window; a model with a different window needs the budget moved with it.

## Tests

`action.yml` is exercised by a harness that stubs `curl` and runs the whole step
across **20 response shapes**, plus **11 mutants** that each remove one guard. All
20 correct; all 11 caught.

The stub reads the nonce out of the request it is handed and answers with it, so the
binding is exercised rather than assumed. It tells the primary request from the
fallback by whether the body carries `thinking`, which is what makes the retry path
testable at all — including the mutant where the fallback mints a **fresh** nonce.

Several guards only became testable once a **discriminating** case existed:

- A non-200 whose body still carries a usable payload. With an ordinary error body,
  the HTTP guard and the guard after it are indistinguishable — delete the first and
  nothing changes.
- The placeholder check, the metacharacter guard and the API-failure guard do **not**
  change the verdict; later guards already force `INCONCLUSIVE`. What they change is
  whether the operator is told *why*, so they are asserted on their reason text.
  Claiming them as independent defences would have been false.

A redundant defence no test can tell from its absence is not a defence.
