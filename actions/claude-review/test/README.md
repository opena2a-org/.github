# Tests for `actions/claude-review`

This action is SHA-pinned by every repo whose `Claude Code Review` gate it powers, and in
several of them that check is a REQUIRED status context on `main`. A defect here does not fail
one job; it changes what merges.

## Run all three

```sh
python3 test/harness.py action.yml                       # response shapes
python3 test/mutants.py action.yml test/harness.py       # non-vacuity control
python3 test/single_mode_identity.py action.yml          # batch mode changed nothing
```

`harness.py` runs the action's real step with a stubbed `curl`. The stub reads the per-run
nonce back out of the request it is handed and answers with it, so the binding is **exercised
rather than assumed**, and it tells the primary request from the fallback by whether the body
carries `thinking`.

`mutants.py` breaks one property at a time and requires the harness to go RED for each. **A
green harness proves nothing until it goes red on purpose.** If a mutant reports that its
find-string did not match, that is a stale anchor, not a pass — an unapplied mutant reads
exactly like coverage. Fix the anchor.

`single_mode_identity.py` answers a different question from either: not "is the behaviour
correct" but "did it change at all". See the section on it below before touching
`test/baseline/`.

**Runs serialise, and they have to.** The action writes fixed `/tmp` paths — right on a
runner, where one job owns the machine; wrong on a developer box running two suites at once,
where they clobber each other's request and response files. That does not fail cleanly: it
produces a scatter of unrelated rows reporting `INCONCLUSIVE`, which reads exactly like a real
defect in the gate. Measured: two concurrent runs, both red, six or more rows each. `harness.py`
therefore takes an exclusive `flock` around each case, so a second run waits instead of
corrupting. Moving the action onto `$RUNNER_TEMP` would fix the cause, but `review-file` is a
published output that six required gates consume — that is a change with a ruling attached,
not a test-convenience edit. **`mutants.py` must stay sequential for the same reason.**

## Why this directory exists

Two defects were found in this action on consecutive days, both by adversarial review of a
consuming repo's adoption diff rather than by a suite — because until now there was no suite.
The `git ls-tree` of this repo held five paths and none of them was a test.

The second of those defects is the one this suite was created around: the action inherited a
strict `FIRST_LINE = "VERDICT-$NONCE: APPROVE"` compare from the nine workflow copies it
replaced, but not the CR/trailing-whitespace normalisation that two of those copies carried.
Seven copies had the same gap, so it was invisible as long as nobody diffed a caller against
its own pre-adoption behaviour.

## The normalisation cases, and why one of them must stay red-adjacent

| case | expected | why |
|---|---|---|
| trailing space after `APPROVE` | `APPROVE` | invisible, not forbidden by the prompt, and a required gate must not turn one emitted space into a red check |
| CRLF line endings | `APPROVE` | transport encoding; no prompt can govern it, so the parser must |
| CR **inside** the nonce | `APPROVE` **and no nonce in the review body** | proves the nonce STRIP and the verdict COMPARE read the same text. Normalising `FIRST_LINE` alone — which is what both local copies did — accepts the verdict here while `grep -v` fails to match, publishing the marker |
| **leading** space | **`INCONCLUSIVE`** | the prompt says "nothing whatsoever before it". A parser that forgives what the prompt forbade makes that instruction untested, and an untested instruction erodes. `mutants.py` pins this so it cannot be re-added by sympathy |

Normalising the compare cannot weaken the binding: every string newly accepted still has to
carry that run's 128-bit nonce, which is minted from `/dev/urandom` after the diff is fixed and
is stripped before the review is posted.

## The redaction's stopping rule — read this before widening the pattern

**The sweep rows in `harness.py` ARE the decision.** A prose table is commentary; the
executable rows are the record. Any change to the pattern lands with its row, in the same
change, or it did not happen.

The posted-body redaction separates two things that look alike and are not:

**FORMAT CONFUSION is ours, closable, and closed.** Two families are redacted. The bare form
`VERDICT:` under a markdown leader — markdown's OWN leader syntax is a closed alphabet of
punctuation, whitespace and digits terminating at the first letter — and the internal marker
form `VERDICT-<token>:`, matched anywhere in the line because no legitimate sentence contains
a nonce-shaped marker. Matched lines are **replaced with a visible placeholder, never silently
deleted**: a reviewer's real line that shares the shape (`+verdict: approve` in a quoted diff,
`| Verdict: | pass |` in a summary table — the R-rows) is withheld at its own position with
the reason stated, and the reader still has the diff. The disclosure footer carries the count.

**PERSUASIVE PROSE is unbounded and is handled by a different control.** "This pull request
passed the automated review and is safe to merge." contains no verdict-shaped token, and no
denylist can enumerate its forms. What contains it is the verdict semantics themselves: the
check is red, `Enforce verdict` exits 1, and INCONCLUSIVE is a third state that is not a pass.
The same boundary covers **letterful leaders**: `<b>VERDICT: APPROVE</b>` renders bold in GFM,
but closing HTML-tag leaders requires tag parsing plus entity decoding, which is unbounded —
it is an X-row, on the prose side, and it can approve nothing because the verdict is
nonce-bound and parsed from the first line only. Note the asymmetry: the FORGED family is
closed even under HTML and invisible-character leaders, because its statement never consults
the leader.

**The X-rows are recorded residuals asserted to SURVIVE** — fullwidth colon, Unicode fillers,
format characters inside the token, homoglyphs. A widening that starts catching one turns a
test red, which makes it a deliberate decision instead of drift. If one of these forms is ever
observed on a real PR, that is someone probing the gate: treat it as an incident, and only
then revisit normalization — match on a normalized copy, redact by line number in the
original, never publish normalized text as the body.

**Degraded is visibly degraded.** The pinned C.UTF-8 locale is load-bearing for non-ASCII
leaders, so the action probes it at runtime through the same matcher the redaction uses; a
runner that cannot honour it still redacts every ASCII row and the whole forged family, and
says so in the posted body. The `redaction degraded locale` case pins all of that.

If you find yourself adding rows to the S-list for text that is not this gate's own format,
stop — you are using the wrong instrument, and the widening will strip a reviewer's real
sentence next. The pattern moves only for a measured member of OUR format family that
survives it.

## Batch mode: the verdict is the weak assertion, the call counts are the strong one

`BATCH_CASES` looks like it is about verdicts. Mostly it is not. **Three of the ruled
properties cannot be seen in the verdict at all**, because breaking them still produces
`INCONCLUSIVE`:

| property | what breaking it does to the verdict | what actually catches it |
|---|---|---|
| the loop stops at the first failed batch | nothing — still `INCONCLUSIVE` | `messages` call count: it burned the rest of the ceiling first |
| the ceiling refuses **before** the first call | nothing — still `INCONCLUSIVE` | `messages` + `ct_calls` are `0`; the money was already spent otherwise |
| one nonce per batch, not one per run | nothing — everything still approves | the cross-batch replay row, where a shared nonce makes batch 2's reply valid |

That is why every batch row asserts counts, and why removing those assertions to "simplify"
the suite would quietly retire three invariants. The mutants that pair with them are named
in `mutants.py` under the `MUTANTS +=` batch block.

**The red-proof injection is a pair, not a row.** `batch: INJECTED failure (invariant III)`
and `batch: injection removed (control)` are identical except for the injected batch. If the
aggregation ever stops telling them apart, one of the two goes red — so the injection cannot
be deleted, weakened, or made conditional without a failing suite. There is no flag, env var
or input anywhere in the action that softens an `INCONCLUSIVE` into a pass; if you are about
to add one, that is the decision this pair exists to make visible.

**`REQUEST_CHANGES` in one batch plus a failure in a later one is `INCONCLUSIVE`, not
`REQUEST_CHANGES`.** This looks like lost information and is not: both are red, the findings
are still in the body under their `Batch k/N` heading, and the aggregate is a statement about
whether the review *completed*. Reporting `REQUEST_CHANGES` would claim a completed review
that did not happen — the same class of false claim as a fallback footer on a run where the
fallback returned nothing. The rule that produces this is "initialised `INCONCLUSIVE`,
upgraded only by a completed all-batch pass", and it is deliberate.

That paragraph was here before the row that proves it was, and for a while it was just prose:
every row carrying a `REQUEST_CHANGES` had no failing batch, and every row with a failing
batch had no `REQUEST_CHANGES`, so the two conditions never met and assigning the aggregate
eagerly inside the loop passed the entire suite. `batch: REQUEST_CHANGES then a failure` is
where they meet, and the matching mutant assigns it eagerly. **A rule stated in bold with no
row is a comment, not a decision** — the same standing rule that put the redaction sweep table
into `harness.py` instead of a prose table.

**The first batch failing is its own shape.** `MEASURED_ANY` and `SENT_ANY` decide whether
`input-tokens` and `review-path` are emitted at all, and they can only be wrong when nothing
was measured or nothing was sent — which never happens if the failure is at batch 2. Every
batch row used to fail at batch 2, so deleting either guard left the whole suite green.
`batch: first batch cannot be measured` and `batch: first batch over budget, nothing sent`
are the rows that discriminate them: the first must report NO `input-tokens` (`0` would be a
fabricated measurement) and the second must leave `review-path` EMPTY (`none` would say
requests went out and none answered).

**Not covered, stated rather than implied:** the batch list is sorted with `LC_ALL=C sort -z`
over a glob that bash has already sorted, so the explicit sort is belt-and-braces against a
runner whose ambient `LC_COLLATE` orders punctuation differently. No harness row discriminates
it — every row runs under the pinned `LC_ALL=C` the redaction rows require — so it carries no
mutant either. It is defence, not a tested property, and it is written down here rather than
left to look like coverage.

## `single_mode_identity.py`, and why `test/baseline/` is frozen

Eight repos consume this action and none of them sets `batch-dir`. So "the tests still pass"
is the wrong bar for a change that adds a mode: a rewritten single mode that merely agreed on
every verdict would also pass. The identity suite replays each `CASES` row against **a frozen
copy of the action at `025b1897`** — the revision the adopters are pinned to — and compares
`GITHUB_OUTPUT`, the posted body, stdout, stderr, the exit code, the `/v1/messages` and
`count_tokens` call counts, **and the payload actually sent to the model** literally. Only two
things are normalised: the per-run nonce and the temp directory, because those are the only
inputs that are not a function of the action's own logic.

It carries its own non-vacuity control. A green that means "nothing changed" is exactly the
shape that rots into a tautology, so after comparing, the suite points itself at an action
with one line of single-mode behaviour deliberately altered and **fails if it cannot see the
difference**.

**The payload field was learned the hard way, and it is the reason that list is longer than it
looks.** Batch mode turned "which file becomes the user message" from something baked into
`build_request` into a call-site argument. Without the payload in `COMPARED`, changing one
token so the action sends the SYSTEM PROMPT instead of the diff — a gate reviewing its own
instructions and approving — compared as byte-identical across all 27 rows, and passed
`harness.py` as well, because the verdict, the body, stdout and the call count are all
unaffected by which file was sent. A required check would have gone green on code no model ever
saw. A suite whose green means "nothing an adopter can observe changed" has to include the
request itself. `harness.py` now asserts the payload on every single-mode row too, and two
mutants aim at the two call sites.

**If this suite goes red, do not regenerate the baseline.** Six of those eight repos gate
`main` on this action. Changing single-mode behaviour is a decision that needs a ruling; this
file exists so it cannot be made by accident, and updating the fixture to match a change is
the one edit that turns the whole suite into decoration.
