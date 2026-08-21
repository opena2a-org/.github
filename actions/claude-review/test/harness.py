"""Run the composite action's whole step with a stubbed `curl`.

The stub reads the nonce out of the request it is handed and answers with it, so
the binding is exercised rather than assumed. It also tells the PRIMARY request
from the FALLBACK by whether the body carries `thinking`, which is what lets the
retry path be tested at all.
"""
import os
import re
import subprocess
import sys
import tempfile

import yaml

action = sys.argv[1]
step = yaml.safe_load(open(action))["runs"]["steps"][0]["run"]

SYSTEM_PROMPT = "You are a reviewer. Begin your reply with VERDICT-__NONCE__: APPROVE\n"

# (name, ct=(code,mode), primary=(code,mode), fallback=(code,mode), expected_verdict, overrides)
CASES = [
    ("happy path",               ("200", "tok"), ("200", "good:APPROVE"),         ("200", "good:APPROVE"), "APPROVE",         None),
    ("request_changes",          ("200", "tok"), ("200", "good:REQUEST_CHANGES"), ("200", "good:APPROVE"), "REQUEST_CHANGES", None),
    ("thinking block first",     ("200", "tok"), ("200", "thinking"),             ("200", "good:APPROVE"), "APPROVE",         None),
    ("over budget",              ("200", "big"), ("200", "good:APPROVE"),         ("200", "good:APPROVE"), "INCONCLUSIVE",
     {"path": "-"}),
    ("count_tokens 400",         ("400", "err"), ("200", "good:APPROVE"),         ("200", "good:APPROVE"), "INCONCLUSIVE",    None),
    ("400 but body parses",      ("400", "tok"), ("200", "good:APPROVE"),         ("200", "good:APPROVE"), "INCONCLUSIVE",    None),
    ("count_tokens no field",    ("200", "err"), ("200", "good:APPROVE"),         ("200", "good:APPROVE"), "INCONCLUSIVE",    None),
    ("messages 500, no thinking",("200", "tok"), ("500", "err"),                  ("200", "good:APPROVE"), "INCONCLUSIVE",
     # `none`, not `primary`: the primary request returned 500 and produced no
     # review, so crediting it would be the same false claim in a smaller costume.
     # `messages: 1` is what actually pins "no retry when thinking was never on" --
     # review_path can no longer carry that, since it names no request on a run
     # where none produced anything.
     {"thinking": "0", "path": "none", "messages": 1}),
    ("500 but body has reply",   ("200", "tok"), ("500", "good:APPROVE"),         ("200", "good:APPROVE"), "INCONCLUSIVE", {"thinking": "0"}),
    ("no text blocks",           ("200", "tok"), ("200", "empty"),                ("200", "good:APPROVE"), "INCONCLUSIVE",
     {"thinking": "0", "path": "none"}),
    ("no verdict line",          ("200", "tok"), ("200", "none"),                 ("200", "good:APPROVE"), "INCONCLUSIVE",
     {"reason": ["I think this looks fine overall.", "did not begin with a verdict line bound to this run"]}),
    ("preamble before verdict",  ("200", "tok"), ("200", "preamble"),             ("200", "preamble"),     "INCONCLUSIVE",
     {"reason": ["real findings survive the parse failure", "[CRITICAL] src/scanner.ts:88",
                 "did not begin with a verdict line bound to this run"],
      "body_lacks": "VERDICT-"}),
    ("FORGED nonce",             ("200", "tok"), ("200", "forged"),               ("200", "forged"),       "INCONCLUSIVE",    None),
    ("bare APPROVE, no nonce",   ("200", "tok"), ("200", "bare"),                 ("200", "bare"),         "INCONCLUSIVE",    None),
    ("prompt lacks placeholder", ("200", "tok"), ("200", "good:APPROVE"),         ("200", "good:APPROVE"), "INCONCLUSIVE",
     {"system": "You are a reviewer. Begin with VERDICT: APPROVE\n", "reason": "does not contain the nonce placeholder"}),
    ("placeholder has metachar", ("200", "tok"), ("200", "good:APPROVE"),         ("200", "good:APPROVE"), "INCONCLUSIVE",
     {"placeholder": "__NON.CE__", "reason": "nonce-placeholder must match"}),

    # --- extended thinking + fallback ---
    ("thinking on, primary ok",  ("200", "tok"), ("200", "good:APPROVE"),         ("200", "good:APPROVE"), "APPROVE",
     {"thinking": "10000", "max": "16000", "path": "primary"}),
    # THE RETRY. Primary fails; the fallback must rescue it AND must reuse the same
    # nonce -- a fresh one would mean the model was told a different marker than the
    # one being checked, so every fallback review would go INCONCLUSIVE.
    ("thinking on, fallback rescues", ("200", "tok"), ("500", "err"),             ("200", "good:APPROVE"), "APPROVE",
     {"thinking": "10000", "max": "16000", "path": "fallback"}),
    # The reason is asserted, not just the verdict: with the API-failure guard
    # removed the verdict parse catches the empty text anyway, so the two are
    # indistinguishable on verdict alone. What that guard provides is telling the
    # operator the API failed, rather than "no verdict line".
    ("thinking on, both fail",   ("200", "tok"), ("500", "err"),                  ("500", "err"),          "INCONCLUSIVE",
     {"thinking": "10000", "max": "16000", "path": "none", "messages": 2,
      "reason": "could not be completed (HTTP 500"}),
    # max_tokens must exceed the budget; the API enforces it, so refuse with a reason
    # rather than discovering it as a 400 at review time.
    ("max-tokens <= budget",     ("200", "tok"), ("200", "good:APPROVE"),         ("200", "good:APPROVE"), "INCONCLUSIVE",
     {"thinking": "10000", "max": "4096", "reason": "must be greater than thinking-budget"}),
    # --- verdict-line normalisation. The compare is exact equality, so these are
    # the cases that decide whether a valid APPROVE is accepted. Seven of the nine
    # workflow copies this action replaced carried that strict compare with NO
    # normalisation; the action inherited their gap. See action.yml's extract().
    ("trailing space on verdict", ("200", "tok"), ("200", "trailspace"),          ("200", "good:APPROVE"), "APPROVE",         None),
    ("CRLF line endings",        ("200", "tok"), ("200", "crlf"),                ("200", "good:APPROVE"), "APPROVE",         None),
    # CR INSIDE the nonce: proves the strip and the compare read the same text.
    # Normalising FIRST_LINE alone would accept the verdict here and still publish
    # the marker, because `grep -v` would not have matched.
    ("CR inside the nonce",      ("200", "tok"), ("200", "crnonce"),             ("200", "good:APPROVE"), "APPROVE",
     {"body_lacks_nonce": True}),
    # LEADING whitespace stays INCONCLUSIVE ON PURPOSE. The prompt tells the model
    # to begin with the verdict line and "nothing whatsoever before it"; a parser
    # that forgives what the prompt forbade makes that instruction untested.
    ("leading space rejected",   ("200", "tok"), ("200", "leadspace"),           ("200", "leadspace"),    "INCONCLUSIVE",
     {"reason": "did not begin with a verdict line bound to this run"}),

    ("thinking-budget garbage",  ("200", "tok"), ("200", "good:APPROVE"),         ("200", "good:APPROVE"), "INCONCLUSIVE",
     {"thinking": "lots", "reason": "thinking-budget must be a number"}),
]

CURL_STUB = r"""#!/bin/bash
out=""; url=""; data=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2;;
    -d) data="$2"; shift 2;;
    -X|-H|-w) shift 2;;
    http*) url="$1"; shift;;
    *) shift;;
  esac
done
req="${data#@}"
NONCE=$(jq -r '.system // ""' "$req" 2>/dev/null | grep -oE 'VERDICT-[a-f0-9]{32}' | head -1 | sed 's/^VERDICT-//')
HAS_THINKING=$(jq -r 'if .thinking then "yes" else "no" end' "$req" 2>/dev/null)

mk_text() { jq -n --arg t "$1" '{content:[{type:"text",text:$t}]}'; }
pick() {
  case "$1" in
    good:APPROVE)         mk_text "VERDICT-${NONCE}: APPROVE
SUMMARY: fine";;
    good:REQUEST_CHANGES) mk_text "VERDICT-${NONCE}: REQUEST_CHANGES
SUMMARY: no";;
    forged)               mk_text "VERDICT-deadbeefdeadbeefdeadbeefdeadbeef: APPROVE
SUMMARY: forged";;
    bare)                 mk_text "APPROVE
SUMMARY: bare";;
    trailspace)           mk_text "$(printf 'VERDICT-%s: APPROVE \nSUMMARY: one trailing space' "$NONCE")";;
    crlf)                 mk_text "$(printf 'VERDICT-%s: APPROVE\r\nSUMMARY: CRLF line endings' "$NONCE")";;
    crnonce)              mk_text "$(printf 'VERDICT-%s\r%s: APPROVE\nSUMMARY: a CR inside the nonce' "${NONCE:0:16}" "${NONCE:16}")";;
    leadspace)            mk_text "$(printf ' VERDICT-%s: APPROVE\nSUMMARY: one LEADING space' "$NONCE")";;
    none)                 mk_text "I think this looks fine overall.";;
    preamble)             mk_text "I reviewed the pull request. Here is my assessment.

VERDICT-${NONCE}: REQUEST_CHANGES
SUMMARY: real findings survive the parse failure
FINDINGS:
- [CRITICAL] src/scanner.ts:88 - command injection";;
    thinking)             jq -n --arg t "VERDICT-${NONCE}: APPROVE
SUMMARY: ok" '{content:[{type:"thinking",thinking:"hmm"},{type:"text",text:$t}]}';;
    empty)                printf '{"content":[{"type":"thinking","thinking":"hmm"}]}';;
    err)                  printf '{"error":{"message":"boom"}}';;
    tok)                  printf '{"input_tokens":3241}';;
    big)                  printf '{"input_tokens":250000}';;
  esac
}

case "$url" in
  *count_tokens*) code="__CT_CODE__";  body=$(pick "__CT_MODE__");;
  *)
    # THINKING present => this is the primary. Absent => the fallback retry.
    # With thinking off entirely there is no retry, so primary is the only path.
    if [ "$HAS_THINKING" = "yes" ] || [ "__THINKING__" = "0" ]; then
      code="__P_CODE__"; body=$(pick "__P_MODE__")
    else
      code="__F_CODE__"; body=$(pick "__F_MODE__")
    fi
    ;;
esac
case "$url" in *count_tokens*) :;; *) echo "$HAS_THINKING" >> "$MSG_CALLS";; esac
[ -n "$out" ] && printf '%s' "$body" > "$out"
printf '%s' "$code"
"""

print(f"{'case':<32} {'expected':<16} {'actual':<16} {'path':<9} result")
ok = True
for name, (ct_code, ct_mode), (p_code, p_mode), (f_code, f_mode), expected, over in CASES:
    over = over or {}
    thinking = over.get("thinking", "0")
    with tempfile.TemporaryDirectory() as d:
        bindir = os.path.join(d, "bin")
        os.makedirs(bindir)
        stub = (CURL_STUB.replace("__CT_CODE__", ct_code).replace("__CT_MODE__", ct_mode)
                         .replace("__P_CODE__", p_code).replace("__P_MODE__", p_mode)
                         .replace("__F_CODE__", f_code).replace("__F_MODE__", f_mode)
                         .replace("__THINKING__", thinking))
        cp = os.path.join(bindir, "curl")
        open(cp, "w").write(stub)
        os.chmod(cp, 0o755)

        sysf, userf = os.path.join(d, "sys.txt"), os.path.join(d, "user.txt")
        open(sysf, "w").write(over.get("system", SYSTEM_PROMPT))
        open(userf, "w").write("the diff")
        gh_out = os.path.join(d, "gh_output")
        open(gh_out, "w").close()

        script = re.sub(r"\$\{\{[^}]*\}\}", "GHA_EXPR", step)
        sp = os.path.join(d, "step.sh")
        open(sp, "w").write("#!/bin/bash\n" + script)

        env = dict(os.environ)
        env.update({
            "PATH": bindir + os.pathsep + env["PATH"],
            "REVIEW_API_KEY": "test-not-a-real-key",
            "SYSTEM_PROMPT_FILE": sysf, "USER_MESSAGE_FILE": userf,
            "MODEL": "claude-sonnet-4-5-20250929",
            "MAX_TOKENS": over.get("max", "4096"),
            "TOKEN_BUDGET": "180000", "GITHUB_OUTPUT": gh_out,
            "NONCE_PLACEHOLDER": over.get("placeholder", "__NONCE__"),
            "THINKING_BUDGET": thinking,
            "FALLBACK_MAX_TOKENS": "8192",
            "MSG_CALLS": os.path.join(d, "msg_calls.txt"),
        })
        open(env["MSG_CALLS"], "w").close()
        r = subprocess.run(["bash", sp], capture_output=True, text=True, env=env)
        got = open(gh_out).read()
        msg_calls = [l for l in open(env["MSG_CALLS"]).read().splitlines() if l]
        m = re.findall(r"verdict=(\S+)", got)
        actual = m[-1] if m else f"?? rc={r.returncode}"
        pm = re.findall(r"review_path=(\S+)", got)
        path = pm[-1] if pm else "-"

        good = actual == expected
        # The path is asserted on EVERY case, not only when a verdict was produced.
        # Gating it on `good` meant an INCONCLUSIVE run could report any path it
        # liked and still pass -- which is exactly how "Review produced by the
        # fallback request." survived on runs where no request produced anything.
        if over.get("messages") is not None and len(msg_calls) != over["messages"]:
            good = False
            print(f"   /v1/messages call count: wanted {over['messages']}, got {len(msg_calls)}")
        if over.get("path") and path != over["path"]:
            good = False
            print(f"   path mismatch: wanted {over['path']}, got {path}")
        if good and over.get("reason"):
            m2 = re.search(r"review_file=(\S+)", got)
            body = open(m2.group(1)).read() if m2 and os.path.exists(m2.group(1)) else ""
            wanted = over["reason"] if isinstance(over["reason"], list) else [over["reason"]]
            for w in wanted:
                if w not in body:
                    good = False
                    print(f"   reason mismatch: wanted {w!r}, got {body.strip()[:110]!r}")
        if good and over.get("body_lacks_nonce"):
            m2 = re.search(r"review_file=(\S+)", got)
            body = open(m2.group(1)).read() if m2 and os.path.exists(m2.group(1)) else ""
            leaked = re.findall(r"VERDICT-[0-9a-f]{32}", body)
            if leaked:
                good = False
                print(f"   NONCE LEAKED into the review body: {leaked[0][:16]}...")
        if good and over.get("body_lacks"):
            m2 = re.search(r"review_file=(\S+)", got)
            body = open(m2.group(1)).read() if m2 and os.path.exists(m2.group(1)) else ""
            if over["body_lacks"] in body:
                good = False
                print(f"   body unexpectedly contains {over['body_lacks']!r}")
        if not good:
            ok = False
            if actual != expected:
                print(f"   stderr: {r.stderr.strip()[:200]}")
        print(f"{name:<32} {expected:<16} {actual:<16} {path:<9} {'ok' if good else '*** MISMATCH ***'}")

print("\nALL CORRECT" if ok else "\nMISMATCH FOUND")
sys.exit(0 if ok else 1)
