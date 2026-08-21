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
        uses: opena2a-org/.github/actions/claude-review@6940df1
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

## Outputs

- `verdict` — `APPROVE`, `REQUEST_CHANGES` or `INCONCLUSIVE`. Never empty.
- `review-file` — path to the review body, written for **every** verdict.
- `input-tokens` — measured input tokens, empty only if the measurement itself failed.

**`INCONCLUSIVE` is a third state, not a pass.** The caller must fail the job on it.
Every failure path in the action resolves to `INCONCLUSIVE`: no key, missing prompt
files, `count_tokens` non-200 or unparseable, over budget, API non-200, no text
blocks, or a reply with no verdict on its first line. Nothing resolves a failure
into `APPROVE`.

## Pin the SHA, not `@main`

`@main` moves every consuming repo the instant this file changes — a bad edit here
would reach every merge gate in the org before anyone reviewed it.

Pin the commit SHA: `@6940df1`. That is stronger than a tag, not a workaround for
the absence of one — a tag can be moved to point at different code, a SHA cannot,
which is why SHA pinning is the standard advice for actions.

Bumping a consumer is then a visible one-line change in that repo's own PR, which
is the point: no repo's gate changes without someone approving it there.

## Changing the model

Read the extraction note in `action.yml` first. The `token-budget` default assumes a
200,000-token window; a model with a different window needs the budget moved with it.

## Tests

`action.yml` is exercised by a harness that stubs `curl` and runs the whole step
across 11 response shapes, plus five mutants that each remove one guard. Two of
those mutants only fail with a **discriminating** case present — a non-200 whose
body still carries a usable payload — because with an ordinary error body the
guard under test and the one after it are indistinguishable. A redundant defence
no test can tell from its absence is not a defence.
