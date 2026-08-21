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
