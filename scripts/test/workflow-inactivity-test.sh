#!/usr/bin/env bash
# Offline cells for scripts/workflow-inactivity.sh: a fake `gh` on PATH serves JSON fixtures
# (piped through the real jq, so the script's --jq expressions are exercised) and records every
# write. One cell per alerting rule; each is keyed on the exit status and the recorded writes,
# never on printed prose.
#
#   bash scripts/test/workflow-inactivity-test.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../workflow-inactivity.sh"
command -v jq >/dev/null || { echo "jq is required"; exit 2; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
FIX="$T/fix"; BIN="$T/bin"; mkdir -p "$FIX" "$BIN"
WRITES="$T/writes.log"

cat > "$BIN/gh" <<'FAKE'
#!/usr/bin/env bash
# fake gh: `api <endpoint> [--paginate] [--jq expr]` reads $FIX/<endpoint with / ? & = -> _>.json;
# a sibling .status file holding a non-zero code makes the call fail. Every write is appended to
# $WRITES as one line. FAIL_CREATE=1 makes `issue create` fail, FAIL_EDIT=1 makes `issue edit` fail.
set -u
cmd="${1:-}"; shift || true
key() { printf '%s' "$1" | tr '/?&=' '____'; }
if [ "$cmd" = "api" ]; then
  method="GET"; endpoint=""; jqexpr=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -X) method="$2"; shift 2;;
      --paginate|-i) shift;;
      --jq) jqexpr="$2"; shift 2;;
      -f) shift 2;;
      *) endpoint="$1"; shift;;
    esac
  done
  if [ "$method" = "POST" ]; then echo "POST $endpoint" >> "$WRITES"; exit 0; fi
  f="$FIX/$(key "$endpoint").json"; s="$FIX/$(key "$endpoint").status"
  if [ -f "$s" ]; then echo "gh: HTTP $(cat "$s") for $endpoint" >&2; exit 1; fi
  [ -f "$f" ] || { echo "gh: no fixture for $endpoint" >&2; exit 1; }
  if [ -n "$jqexpr" ]; then jq -r "$jqexpr" "$f"; else cat "$f"; fi
  exit 0
fi
if [ "$cmd" = "issue" ]; then
  sub="$1"; shift
  case "$sub" in
    create)
      [ "${FAIL_CREATE:-0}" = "1" ] && { echo "gh: HTTP 403 creating issue" >&2; exit 1; }
      title=""; label=""
      while [ $# -gt 0 ]; do case "$1" in --title) title="$2"; shift 2;; --label) label="$2"; shift 2;; --body|-R) shift 2;; *) shift;; esac; done
      echo "create label=$label title=$title" >> "$WRITES"; echo "https://github.com/x/y/issues/900";;
    edit)  [ "${FAIL_EDIT:-0}" = "1" ] && { echo "gh: HTTP 403 editing issue" >&2; exit 1; }
           echo "edit #$1" >> "$WRITES";;
    close) echo "close #$1" >> "$WRITES";;
  esac
  exit 0
fi
if [ "$cmd" = "label" ]; then echo "label $*" >> "$WRITES"; exit 0; fi
echo "fake gh: unhandled $cmd $*" >&2; exit 1
FAKE
chmod +x "$BIN/gh"

iso_days_ago() {  # N -> ISO-8601 N days ago
  local s=$(( $(date -u +%s) - $1 * 86400 ))
  date -u -d "@$s" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "$s" +%Y-%m-%dT%H:%M:%SZ
}
key() { printf '%s' "$1" | tr '/?&=' '____'; }

reset() {
  rm -rf "$FIX"; mkdir -p "$FIX"; : > "$WRITES"
  echo '[{"full_name":"org/r1","archived":false,"private":false},{"full_name":"org/r2","archived":false,"private":true},{"full_name":"org/old","archived":true,"private":false}]' \
    > "$FIX/$(key 'orgs/org/repos?type=all&per_page=100').json"
  workflows org/r1 active; workflows org/r2 active
  issues '[]'
  echo '{"name":"workflow-inactivity"}' > "$FIX/$(key 'repos/x/y/labels/workflow-inactivity').json"
}
workflows() {  # repo state   (one workflow, .github/workflows/ci.yml)
  echo "{\"total_count\":1,\"workflows\":[{\"id\":7,\"path\":\".github/workflows/ci.yml\",\"state\":\"$2\"}]}" \
    > "$FIX/$(key "repos/$1/actions/workflows?per_page=100").json"
}
unreadable() { echo 404 > "$FIX/$(key "repos/$1/actions/workflows?per_page=100").status"; }
issues() { printf '%s' "$1" > "$FIX/$(key 'repos/x/y/issues?state=open&labels=workflow-inactivity&per_page=100').json"; }
issue_json() {  # login created_at [title]
  printf '{"number":41,"html_url":"https://github.com/x/y/issues/41","title":"%s","created_at":"%s","user":{"login":"%s"},"pull_request":null}' \
    "${3:-workflow not active: org/r1 .github/workflows/ci.yml}" "$2" "$1"
}

run() {  # -> exit status in $rc, output in $OUT
  set +e
  OUT="$(PATH="$BIN:$PATH" FIX="$FIX" WRITES="$WRITES" ORGS=org ISSUE_REPO=x/y GH_TOKEN=t "$@" bash "$SCRIPT" 2>"$T/err")"
  rc=$?
  set -e
}

pass=0; failn=0
cell() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else failn=$((failn+1)); echo "FAIL $1"; echo "     writes: $(tr '\n' ';' < "$WRITES")"; echo "     rc=$rc"; sed 's/^/     | /' <<< "$OUT" | tail -12; fi; }

# 1 clean pass: no finding, every repo read, nothing written
reset; run env
cell "clean population passes and writes nothing" '[ $rc = 0 ] && [ ! -s "$WRITES" ] && grep -q "| pass | 0 | 0 | 0 | 0 | 0 |" <<< "$OUT"'

# 2 untracked finding: one issue filed with the label, run fails
reset; workflows org/r1 disabled_inactivity; run env
cell "untracked finding files one labeled issue and fails" '[ $rc = 1 ] && [ "$(grep -c "^create label=workflow-inactivity title=workflow not active: org/r1 .github/workflows/ci.yml$" "$WRITES")" = 1 ] && grep -q "NEW (untracked): RED" <<< "$OUT"'

# 3 tracked, young: pass, issue updated not duplicated, summary carries the URL
reset; workflows org/r1 disabled_inactivity; issues "[$(issue_json 'github-actions[bot]' "$(iso_days_ago 3)")]"; run env
cell "tracked finding within grace passes, updates, never duplicates" '[ $rc = 0 ] && grep -q "^edit #41$" "$WRITES" && ! grep -q "^create" "$WRITES" && grep -q "issues/41" <<< "$OUT"'

# 4 age ratchet: tracked 45 days -> red again
reset; workflows org/r1 disabled_manually; issues "[$(issue_json 'github-actions[bot]' "$(iso_days_ago 45)")]"; run env
cell "tracked finding past the grace fails again" '[ $rc = 1 ] && grep -q "over the 30-day grace" <<< "$OUT" && ! grep -q "^create" "$WRITES"'

# 5 look-alike issue by a human is not tracking: new issue, red
reset; workflows org/r1 disabled_inactivity; issues "[$(issue_json 'someone' "$(iso_days_ago 1)")]"; run env
cell "an issue not authored by the bot does not track" '[ $rc = 1 ] && grep -q "^create" "$WRITES"'

# 6 filing failure fails the run: it aborts at the filing step, before any verdict is rendered
reset; workflows org/r1 disabled_inactivity; run env FAIL_CREATE=1
cell "issue filing failure aborts the run before a verdict" '[ $rc != 0 ] && ! grep -q "^create" "$WRITES" && ! grep -q "| verdict |" <<< "$OUT" && grep -q "HTTP 403" "$T/err"'

# 6b an update failure on a tracked finding fails a run that would otherwise pass
reset; workflows org/r1 disabled_inactivity; issues "[$(issue_json 'github-actions[bot]' "$(iso_days_ago 3)")]"; run env FAIL_EDIT=1
cell "issue update failure fails an otherwise passing run" '[ $rc != 0 ] && ! grep -q "| verdict |" <<< "$OUT"'

# 7 unreadable repository fails the run even with no finding
reset; unreadable org/r2; run env
cell "an unreadable repository fails the run" '[ $rc = 1 ] && grep -q "| org/r2 | true |" <<< "$OUT" && grep -q "ORG_READ_TOKEN" <<< "$OUT"'

# 8 resolved: tracked issue, workflow active again -> closed, pass
reset; issues "[$(issue_json 'github-actions[bot]' "$(iso_days_ago 10)")]"; run env
cell "a resolved finding closes its issue" '[ $rc = 0 ] && grep -q "^close #41$" "$WRITES" && grep -q "resolved: workflow not active: org/r1" <<< "$OUT"'

# 9 not resolved when the repository could not be read this run
reset; unreadable org/r1; issues "[$(issue_json 'github-actions[bot]' "$(iso_days_ago 10)")]"; run env
cell "an unread repository never resolves its issue" '[ $rc = 1 ] && ! grep -q "^close" "$WRITES"'

# 10 dry run: same verdict, nothing written
reset; workflows org/r1 disabled_inactivity; run env DRY_RUN=1
cell "dry run keeps the verdict and writes nothing" '[ $rc = 1 ] && [ ! -s "$WRITES" ] && grep -q "dry run: nothing was written" <<< "$OUT"'

# 11 archived repositories are not part of the population
reset; run env
cell "archived repositories are excluded from the population" 'grep -q "| unarchived repositories enumerated | 2 (1 private) |" <<< "$OUT"'

echo "$pass passed, $failn failed"
[ "$failn" = 0 ]
