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
        # Named on the LEFT-HAND SIDE, because batch mode added a second first-line
        # parse with the same tail. An anchor that matches both would silently test
        # whichever one happens to come first in the file.
        "leading-whitespace strip added back (single mode)",
        """FIRST_LINE=$(printf '%s\\n' "$REVIEW_TEXT" | sed -n '1p' | sed 's/[[:space:]]*$//')""",
        """FIRST_LINE=$(printf '%s\\n' "$REVIEW_TEXT" | sed -n '1p' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')""",
    ),
    (
        "parse-failure write reverts from append to truncate",
        'so no verdict was recorded." >> "$REVIEW_FILE"',
        'so no verdict was recorded." > "$REVIEW_FILE"',
    ),
    (
        # Anchored on the CONDITION, not on the message. The message moved once
        # already, when the per-request core was factored out for batch mode, and
        # a mutant whose find-string has drifted is an unapplied mutant -- which
        # reads exactly like coverage.
        "count_tokens HTTP guard no longer stops the send",
        'if [ "$CT_CODE" != "200" ]; then',
        'if false; then',
    ),
    (
        "extraction reverts to content[0].text",
        """jq -r '[(.content // [])[] | select(.type == "text") | .text] | join("\\n")' /tmp/response.json 2>/dev/null | tr -d '\\r' || echo \"\"""",
        """jq -r '.content[0].text // ""' /tmp/response.json 2>/dev/null || echo \"\"""",
    ),
    (
        "budget check removed",
        'if [ "$INPUT_TOKENS" -gt "$TOKEN_BUDGET" ]; then',
        'if false; then',
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
        "            RO_PATH=fallback",
        "            RO_PATH=fallback\n            NONCE=$(head -c 16 /dev/urandom | xxd -p)",
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
        'if [ -z "$REVIEW_TEXT" ]; then',
        'if false; then',
    ),
]

# The redaction's properties, each pinned by the sweep rows and their
# over-strip controls. See test/README.md for the stopping rule that bounds
# what this denylist is for.
MUTANTS += [
    ("redaction narrowed to hackmyagent's literal",
     '^[[:punct:][:space:][:digit:]]*VERDICT(-[0-9A-Za-z]+)?[[:punct:][:space:]]*:', '^[[:space:]]*VERDICT:'),
    ("nonce-SHAPE branch removed from the anchored family",
     "VERDICT(-[0-9A-Za-z]+)?[[:punct:][:space:]]*:", "VERDICT[[:punct:][:space:]]*:"),
    ("redaction case-sensitivity restored",
     "grep -qEi -e", "grep -qE -e"),
    ("digit leader dropped (ordered-list bypass)",
     "[[:punct:][:space:][:digit:]]*VERDICT", "[[:punct:][:space:]]*VERDICT"),
    ("disclosure footer removed",
     'if [ "$REDACTED" -gt 0 ]; then', 'if false; then'),
    ("locale pin removed from the redaction",
     "LC_ALL=C.UTF-8 grep -qEi", "grep -qEi"),
    ("redaction reverts from placeholder to deletion",
     """printf '%s\\n' "$PLACEHOLDER" >> "$REVIEW_FILE\"""", ":"),
    ("forged-family statement removed from the redaction",
     '-e "$FMT" -e "$FORGED"', '-e "$FMT"'),
    ("forged token class narrowed to alphanumerics",
     "[0-9A-Za-z_-]{8,}", "[0-9A-Za-z]{8,}"),
    ("locale degradation probe removed",
     "LOCALE_DEGRADED=1", "LOCALE_DEGRADED=0"),
]

# BATCH MODE. Each of these breaks one property the placement ruling or a CISO
# invariant names, and the notable thing about most of them is that the VERDICT
# alone does not catch them: an aggregator that forgets to stop the loop still
# reports INCONCLUSIVE, and a ceiling that refuses after the first call still
# refuses. What catches them is the call counts in `BATCH_CASES`, which is why
# those assertions are not optional decoration.
MUTANTS += [
    # CA ruling: "any batch that errors ... -> INCONCLUSIVE and the loop stops
    # there". Removing the stop still yields INCONCLUSIVE; it just pays for the
    # rest of the ceiling first.
    ("batch: loop no longer stops on a failed batch",
     '. $RO_REASON"\n              break',
     '. $RO_REASON"\n              :'),
    ("batch: loop no longer stops on an unparseable batch verdict",
     'this pull request was not reviewed in full."\n              break',
     'this pull request was not reviewed in full."\n              :'),
    # CISO invariant I: N verdicts for N batches, verified by COUNTING.
    ("batch: all-APPROVE upgrade guard removed",
     'if [ "$ANSWERED" -eq "$BATCH_COUNT" ]; then', 'if true; then'),
    ("batch: count verification weakened to 'at least one answered'",
     '"$ANSWERED" -eq "$BATCH_COUNT"', '"$ANSWERED" -ge 1'),
    # CA ruling: "batch count above max-batches -> refuse before the first call".
    ("batch: max-batches ceiling removed",
     'if [ "$BATCH_COUNT" -gt "$MAX_BATCHES" ]; then', 'if false; then'),
    ("batch: max-batches ceiling off by one",
     '"$BATCH_COUNT" -gt "$MAX_BATCHES"', '"$BATCH_COUNT" -ge "$MAX_BATCHES"'),
    # CA ruling: "aggregate verdict initialized INCONCLUSIVE and upgraded only
    # by a completed all-batch pass".
    ("batch: aggregate no longer starts INCONCLUSIVE",
     "AGG_VERDICT=INCONCLUSIVE", "AGG_VERDICT=APPROVE"),
    # CISO invariant II: nonce discipline scales PER BATCH. Only the
    # cross-batch replay row can see this one -- with a shared nonce, a reply
    # addressed to batch 1 satisfies batch 2's check exactly as intended.
    ("batch: one nonce reused across every batch",
     '            mint_nonce\n            review_once "$BATCH_ENTRY"',
     '            if [ -z "$NONCE" ]; then mint_nonce; fi\n            review_once "$BATCH_ENTRY"'),
    # The batch parse must be exactly as strict as the single-mode one. Two
    # first-line parsers is two places for the prompt's "nothing whatsoever
    # before it" to be quietly forgiven.
    ("batch: leading-whitespace strip added back (batch mode)",
     """BATCH_FIRST_LINE=$(printf '%s\\n' "$RO_TEXT" | sed -n '1p' | sed 's/[[:space:]]*$//')""",
     """BATCH_FIRST_LINE=$(printf '%s\\n' "$RO_TEXT" | sed -n '1p' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"""),
    ("batch: trailing-whitespace strip removed (batch mode)",
     """BATCH_FIRST_LINE=$(printf '%s\\n' "$RO_TEXT" | sed -n '1p' | sed 's/[[:space:]]*$//')""",
     """BATCH_FIRST_LINE=$(printf '%s\\n' "$RO_TEXT" | sed -n '1p')"""),
    ("batch: verdict binding loosened to 'contains APPROVE'",
     'if [ "$BATCH_FIRST_LINE" = "VERDICT-$NONCE: APPROVE" ]; then',
     'if case "$BATCH_FIRST_LINE" in *APPROVE*) true;; *) false;; esac; then'),
    # CA supplementary, batch-mode note: the exact-nonce deletion runs per batch,
    # with that batch's nonce, BEFORE concatenation.
    ("batch: per-batch exact-nonce strip removed",
     'printf \'%s\\n\' "$RO_TEXT" | grep -v -- "VERDICT-$NONCE:" >> "$RAW_FILE" || true',
     'printf \'%s\\n\' "$RO_TEXT" >> "$RAW_FILE" || true'),
    # CA ruling: outputs extend the caller contract.
    ("batch: input-tokens reports the last batch instead of the sum",
     "TOTAL_TOKENS=$((TOTAL_TOKENS + RO_TOKENS))", "TOTAL_TOKENS=$RO_TOKENS"),
    ("batch: review-path claims primary despite a batch that fell back",
     'elif [ "$SAW_FALLBACK" = "1" ]; then', 'elif false; then'),
    # THE PAYLOAD. `build_request` takes the user-message file as an argument
    # now, so the call sites decide what gets reviewed. Sending the system
    # prompt instead of the diff is a gate reviewing its own instructions and
    # approving -- and before the `users` assertion existed, this passed every
    # row and the identity suite alike.
    ("single mode sends the system prompt instead of the diff",
     'review_once "$USER_MESSAGE_FILE"', 'review_once "$SYSTEM_PROMPT_FILE"'),
    ("batch mode sends the system prompt instead of the batch",
     'review_once "$BATCH_ENTRY"', 'review_once "$SYSTEM_PROMPT_FILE"'),
    # The bolded aggregation rule: REQUEST_CHANGES is a finding, not a completed
    # review. Assigning it eagerly inside the loop is the obvious literal reading
    # of "any REQUEST_CHANGES -> REQUEST_CHANGES" and it publishes a verdict for
    # a pull request that was never fully reviewed.
    ("batch: REQUEST_CHANGES assigned eagerly inside the loop",
     "              SAW_REQUEST_CHANGES=1",
     "              SAW_REQUEST_CHANGES=1\n              AGG_VERDICT=REQUEST_CHANGES"),
    # The two output guards. Both only matter when the FIRST batch fails, which
    # is why they went uncontrolled until a row existed for that shape.
    ("batch: input-tokens reported as 0 when nothing was measured",
     'if [ "$MEASURED_ANY" = "1" ]; then', 'if true; then'),
    ("batch: review-path claims `none` when no request was ever sent",
     'if [ "$SENT_ANY" = "1" ]; then', 'if true; then'),
    # The measurement is recorded the instant it exists, as the pinned revision
    # did. Hoisting it to the caller loses it whenever the step dies mid-request.
    ("single mode records input-tokens only after the request returns",
     '          if [ "$BATCH_MODE" = "0" ]; then\n            echo "input_tokens=$INPUT_TOKENS" >> "$GITHUB_OUTPUT"\n          fi',
     '          :'),
    # A malformed batch directory is refused rather than partially reviewed.
    # A dot-named batch that the glob cannot see is missing from the pinned
    # count and the loop together, so counting cannot detect it.
    ("batch: dotfile batches become invisible to the glob",
     "shopt -s nullglob dotglob", "shopt -s nullglob"),
    ("batch: non-regular entries no longer refused",
     '[ -f "$BATCH_ENTRY" ] || inconclusive', 'true || inconclusive'),
    ("batch: empty batch files no longer refused",
     '[ -s "$BATCH_ENTRY" ] || inconclusive', 'true || inconclusive'),
]

# PRE-FLIGHT, BEFORE ANY MUTANT RUNS. Three ways an entry in this list can be
# decoration rather than a control, all of them invisible in a green run and all
# of them cheap to detect statically:
#
#   stale      the anchor no longer appears -- the mutant was never applied, and
#              an unapplied mutant reads exactly like coverage. This has now
#              happened twice, both times because action.yml was refactored and
#              a message string moved.
#   ambiguous  the anchor appears more than once. `.replace(old, new, 1)` takes
#              the first, so the mutant silently tests whichever came first in
#              the file -- and a later reorder changes what it tests without
#              changing this file. Batch mode added a second first-line parser,
#              which is exactly how an anchor becomes ambiguous.
#   no-op      the replacement leaves the source unchanged, so the "mutant" is
#              the original action and cannot possibly be caught.
#
# Reporting these one 10-minute run at a time is how they survive. They fail the
# suite here instead, in under a second.
problems = []
for name, old, new in MUTANTS:
    n = base.count(old)
    if n == 0:
        problems.append((name, "STALE ANCHOR: find-string not found in the action"))
    elif n > 1:
        problems.append((name, f"AMBIGUOUS ANCHOR: matches {n} places, only the first is mutated"))
    elif base.replace(old, new, 1) == base:
        problems.append((name, "NO-OP: the replacement leaves the action unchanged"))
if problems:
    print("MUTANT LIST IS NOT A CONTROL -- fix these before trusting any run:\n")
    for name, why in problems:
        print(f"  {name}\n      {why}")
    sys.exit(1)

print(f"{len(MUTANTS)} mutants, every anchor unique and applied\n")
print(f"{'mutant':<52} {'caught?'}")
all_caught = True
for name, old, new in MUTANTS:
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
