"""Mutate one property of the composite action at a time and require the harness to catch it."""
import os
import shutil
import subprocess
import sys
import tempfile

SRC = sys.argv[1]
HARNESS = sys.argv[2]
base = open(SRC).read()

MUTANTS = [
    (
        # The defect this action shipped with: it inherited the strict compare from
        # nine workflow copies and left behind the normalisation two of them had.
        "CR normalisation removed from extract()",
        "| tr -d '\\r' || echo \"\"",
        "|| echo \"\"",
    ),
    (
        "trailing-whitespace strip removed from the verdict line",
        """FIRST_LINE=$(printf '%s\\n' "$REVIEW_TEXT" | sed -n '1p' | sed 's/[[:space:]]*$//')""",
        """FIRST_LINE=$(printf '%s\\n' "$REVIEW_TEXT" | sed -n '1p')""",
    ),
    (
        # Ruling 3 pinned: the prompt forbids leading content, so the parser must
        # NOT forgive it. Without this mutant nothing stops a future contributor
        # re-adding hackmyagent's superset out of sympathy.
        "leading-whitespace strip added back",
        """| sed -n '1p' | sed 's/[[:space:]]*$//')""",
        """| sed -n '1p' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')""",
    ),
    (
        "parse-failure write reverts from append to truncate",
        'so no verdict was recorded." >> "$REVIEW_FILE"',
        'so no verdict was recorded." > "$REVIEW_FILE"',
    ),
    (
        "count_tokens HTTP guard no longer stops the send",
        'inconclusive "The review could not measure this pull request\'s size (count_tokens HTTP $CT_CODE: $CT_ERR), so it did not send it."',
        'echo "mutant: swallowed"',
    ),
    (
        "extraction reverts to content[0].text",
        """jq -r '[(.content // [])[] | select(.type == "text") | .text] | join("\\n")' /tmp/response.json 2>/dev/null | tr -d '\\r' || echo \"\"""",
        """jq -r '.content[0].text // ""' /tmp/response.json 2>/dev/null || echo \"\"""",
    ),
    (
        "budget check removed",
        'inconclusive "This pull request is ${INPUT_TOKENS} input tokens, over the ${TOKEN_BUDGET} token review budget. It genuinely does not fit in the model\'s context window, so an automated verdict would describe only part of the change."',
        'echo "mutant: over budget ignored"',
    ),
    (
        "verdict match loosened to 'contains APPROVE'",
        'if [ "$FIRST_LINE" = "VERDICT-$NONCE: APPROVE" ]; then',
        'if case "$FIRST_LINE" in *APPROVE*) true;; *) false;; esac; then',
    ),
    (
        "nonce placeholder check removed",
        'inconclusive "The review could not run: the system prompt does not contain the nonce placeholder, so the verdict could not be bound to this run. Add it to the prompt\'s verdict instruction."',
        'echo "mutant: missing placeholder ignored"',
    ),
    (
        "placeholder metacharacter guard removed",
        "''|*[!A-Za-z0-9_]*)",
        "'THIS_WILL_NEVER_MATCH')",
    ),
    (
        "fallback mints a FRESH nonce instead of reusing it",
        "          REVIEW_PATH=fallback",
        "          REVIEW_PATH=fallback\n          NONCE=$(head -c 16 /dev/urandom | xxd -p)",
    ),
    (
        "fallback fires even when thinking was never on",
        'if [ -z "$REVIEW_TEXT" ] && [ "$THINKING_BUDGET" -gt 0 ]; then',
        'if [ -z "$REVIEW_TEXT" ]; then',
    ),
    (
        "max-tokens vs thinking-budget guard removed",
        'if [ "$THINKING_BUDGET" -gt 0 ] && [ "$MAX_TOKENS" -le "$THINKING_BUDGET" ]; then',
        'if false; then',
    ),
    (
        "thinking never added to the request",
        '          if [ "$1" -gt 0 ]; then',
        '          if false; then',
    ),
    (
        "messages non-200 no longer stops",
        'inconclusive "The automated review could not be completed (HTTP $HTTP_CODE: $ERROR)."',
        'echo "mutant: api error swallowed"',
    ),
]

print(f"{'mutant':<52} {'caught?'}")
all_caught = True
for name, old, new in MUTANTS:
    if old not in base:
        print(f"{name:<52} HARNESS ARTIFACT (anchor not found)")
        all_caught = False
        continue
    d = tempfile.mkdtemp()
    p = os.path.join(d, "action.yml")
    open(p, "w").write(base.replace(old, new, 1))
    r = subprocess.run([sys.executable, HARNESS, p], capture_output=True, text=True)
    caught = r.returncode != 0
    if not caught:
        all_caught = False
    print(f"{name:<52} {'CAUGHT' if caught else '*** SURVIVED ***'}")
    shutil.rmtree(d, ignore_errors=True)

print("\nEVERY MUTANT CAUGHT" if all_caught else "\nA MUTANT SURVIVED - the harness does not prove that property")
sys.exit(0 if all_caught else 1)
