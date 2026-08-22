# Tests for `actions/claude-review`

This action is SHA-pinned by every repo whose `Claude Code Review` gate it powers, and in
several of them that check is a REQUIRED status context on `main`. A defect here does not fail
one job; it changes what merges.

## Run both

```sh
python3 test/harness.py action.yml                       # response shapes
python3 test/mutants.py action.yml test/harness.py       # non-vacuity control
```

`harness.py` runs the action's real step with a stubbed `curl`. The stub reads the per-run
nonce back out of the request it is handed and answers with it, so the binding is **exercised
rather than assumed**, and it tells the primary request from the fallback by whether the body
carries `thinking`.

`mutants.py` breaks one property at a time and requires the harness to go RED for each. **A
green harness proves nothing until it goes red on purpose.** If a mutant reports that its
find-string did not match, that is a stale anchor, not a pass — an unapplied mutant reads
exactly like coverage. Fix the anchor.

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
