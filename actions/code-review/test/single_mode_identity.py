"""Prove that with `batch-dir` unset, this action still behaves BYTE FOR BYTE as
it did before batch mode existed.

Eight repos consume this action, six of them through a REQUIRED status context,
and none of them sets `batch-dir`. So the question batch mode has to answer is
not "do the tests still pass" -- they would pass against a rewritten single mode
that merely happened to agree on the verdict. The question is whether anything
an adopting repo can observe changed at all.

So every SINGLE-mode row in `harness.py` is replayed against two actions: the one
in this working tree, and a frozen copy of the action as it shipped at
`025b1897886f261c12ccc79da3f75d345842c897` -- the commit every adopter is pinned
to. Then their GITHUB_OUTPUT, their posted review body, their stdout, their
stderr, their exit code and their `/v1/messages` call count are compared
literally.

Two things are normalised, and only two, because they are the only inputs that
are not a function of the action's own logic: the per-run nonce (minted from
/dev/urandom, so it differs between any two runs of the SAME action) and the
temporary directory each run is given. Everything else has to match exactly.

    python3 test/single_mode_identity.py action.yml [baseline.yml]

THE BASELINE IS FROZEN ON PURPOSE. If this goes red, the fix is not to
regenerate `test/baseline/`. Single-mode behaviour is what six required gates
depend on; changing it is a decision that needs a ruling, and this file exists so
that decision cannot be made by accident.
"""
import os
import re
import shutil
import sys
import tempfile

import harness

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_BASELINE = os.path.join(HERE, "baseline", "action-025b1897.yml")

# The nonce is 128 bits of /dev/urandom rendered as 32 hex characters. It is the
# one thing that cannot repeat across two runs, so it is normalised on both
# sides. The forged `deadbeef...` markers in the sweep rows have the same shape
# and are normalised too -- harmlessly, since both sides see the same text.
NONCE_RE = re.compile(r"[0-9a-f]{32}")

# `users` is the payload actually handed to the model, and it belongs here for a
# reason that was found the hard way: batch mode turned "which file becomes the
# user message" into a call-site argument, and without this field a one-token
# change sending the SYSTEM PROMPT instead of the diff -- a gate reviewing its
# own instructions -- compared as byte-identical across all 27 rows, because the
# verdict, body, stdout and call count are all unaffected. A suite whose green
# means "nothing an adopter can observe changed" has to include the request.
COMPARED = ("outputs", "body", "stdout", "stderr", "rc", "msg_calls", "users", "ct_calls")


def _norm(value, tmpdir):
    if isinstance(value, str):
        return NONCE_RE.sub("<NONCE>", value.replace(tmpdir, "<TMP>"))
    if isinstance(value, list):
        return [_norm(v, tmpdir) for v in value]
    return value


def _run(step, case):
    d = tempfile.mkdtemp()
    try:
        res = harness.run_case(step, case, tmpdir=d)
        return {k: _norm(res[k], d) for k in COMPARED}
    finally:
        shutil.rmtree(d, ignore_errors=True)


def compare(new_step, old_step, quiet=False):
    """Returns the list of (case name, field) pairs that differ."""
    drift = []
    for case in harness.CASES:
        name = case[0]
        new, old = _run(new_step, case), _run(old_step, case)
        bad = [f for f in COMPARED if new[f] != old[f]]
        drift.extend((name, f) for f in bad)
        if not quiet:
            status = "identical" if not bad else "*** DIFFERS: " + ", ".join(bad) + " ***"
            print(f"{name:<32} {status}")
            for f in bad:
                print(f"     baseline: {str(old[f])[:220]!r}")
                print(f"     current:  {str(new[f])[:220]!r}")
    return drift


def main():
    action = sys.argv[1]
    baseline = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_BASELINE
    if not os.path.exists(baseline):
        print(f"baseline missing: {baseline}")
        sys.exit(2)

    new_step = harness.load_step(action)
    old_step = harness.load_step(baseline)

    print(f"single-mode identity: {os.path.basename(action)} vs "
          f"{os.path.basename(baseline)}  ({len(harness.CASES)} cases)\n")
    drift = compare(new_step, old_step)

    # NON-VACUITY. A comparison that cannot go red proves nothing, and this one
    # is the only test in the directory whose green means "nothing changed" --
    # exactly the shape that rots into a tautology unnoticed. So the instrument
    # is pointed at an action that IS different, in one line of single-mode
    # behaviour, and required to see it.
    print("\nnon-vacuity control: perturbing one line of single-mode behaviour")
    perturbed = open(action).read().replace(
        """FIRST_LINE=$(printf '%s\\n' "$REVIEW_TEXT" | sed -n '1p' | sed 's/[[:space:]]*$//')""",
        """FIRST_LINE=$(printf '%s\\n' "$REVIEW_TEXT" | sed -n '1p')""", 1)
    if perturbed == open(action).read():
        print("  *** the control's anchor no longer matches -- it proved nothing ***")
        sys.exit(1)
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, "perturbed.yml")
        open(p, "w").write(perturbed)
        seen = compare(harness.load_step(p), old_step, quiet=True)
    if seen:
        print(f"  control seen: {len(seen)} field(s) differ, e.g. {seen[0]}")
    else:
        print("  *** the control was NOT seen -- this comparison proves nothing ***")
        sys.exit(1)

    if drift:
        print(f"\nSINGLE MODE DRIFTED from {os.path.basename(baseline)} "
              f"in {len(drift)} field(s)")
        sys.exit(1)
    print("\nSINGLE MODE BYTE-IDENTICAL to the pinned baseline")
    sys.exit(0)


if __name__ == "__main__":
    main()
