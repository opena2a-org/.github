#!/usr/bin/env bash
# Offline cells for scripts/license-integrity.sh: a fake `gh` on PATH serves JSON fixtures
# (piped through the real jq, so the script's --jq expressions are exercised) and records every
# write. One cell per alerting rule; each is keyed on the exit status and the recorded writes,
# never on printed prose. Same harness as scripts/test/workflow-inactivity-test.sh.
#
#   bash scripts/test/license-integrity-test.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../license-integrity.sh"
command -v jq >/dev/null || { echo "jq is required"; exit 2; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
FIX="$T/fix"; BIN="$T/bin"; mkdir -p "$FIX" "$BIN"
WRITES="$T/writes.log"
ALLOW="$T/allowlist.tsv"

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

repos() {  # JSON array of {full_name, archived, license.spdx_id} for org
  printf '%s' "$1" > "$FIX/$(key 'orgs/org/repos?type=public&per_page=100').json"
}
repo_json() {  # full_name spdx|null [archived]
  local lic; if [ "$2" = "null" ]; then lic='null'; else lic="{\"spdx_id\":\"$2\"}"; fi
  printf '{"full_name":"%s","archived":%s,"license":%s}' "$1" "${3:-false}" "$lic"
}
unreadable() { echo 403 > "$FIX/$(key 'orgs/org/repos?type=public&per_page=100').status"; }
issues() { printf '%s' "$1" > "$FIX/$(key 'repos/x/y/issues?state=open&labels=license-integrity&per_page=100').json"; }
issue_json() {  # login created_at [title]
  printf '{"number":41,"html_url":"https://github.com/x/y/issues/41","title":"%s","created_at":"%s","user":{"login":"%s"},"pull_request":null}' \
    "${3:-license integrity: org/r1}" "$2" "$1"
}

reset() {
  rm -rf "$FIX"; mkdir -p "$FIX"; : > "$WRITES"
  repos "[$(repo_json org/r1 Apache-2.0),$(repo_json org/r2 Apache-2.0),$(repo_json org/old MIT true)]"
  issues '[]'
  printf 'org/mit\tMIT\tupstream fork keeps its licence\n' > "$ALLOW"
  echo '{"name":"license-integrity"}' > "$FIX/$(key 'repos/x/y/labels/license-integrity').json"
}

run() {  # -> exit status in $rc, output in $OUT
  set +e
  OUT="$(PATH="$BIN:$PATH" FIX="$FIX" WRITES="$WRITES" ORGS=org ISSUE_REPO=x/y GH_TOKEN=t ALLOWLIST="$ALLOW" "$@" bash "$SCRIPT" 2>"$T/err")"
  rc=$?
  set -e
}

pass=0; failn=0
cell() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else failn=$((failn+1)); echo "FAIL $1"; echo "     writes: $(tr '\n' ';' < "$WRITES")"; echo "     rc=$rc"; sed 's/^/     | /' <<< "$OUT" | tail -12; fi; }

# 1 clean pass: every repository Apache-2.0, nothing written
reset; run env
cell "clean population passes and writes nothing" '[ $rc = 0 ] && [ ! -s "$WRITES" ] && grep -q "| pass | 0 | 0 | 0 | 0 | 0 |" <<< "$OUT"'

# 2 untracked finding: one issue filed with the label, run fails
reset; repos "[$(repo_json org/r1 MIT),$(repo_json org/r2 Apache-2.0)]"; run env
cell "untracked finding files one labeled issue and fails" '[ $rc = 1 ] && [ "$(grep -c "^create label=license-integrity title=license integrity: org/r1$" "$WRITES")" = 1 ] && grep -q "NEW (untracked): RED" <<< "$OUT"'

# 3 tracked, young: pass, issue updated not duplicated, summary carries the URL
reset; repos "[$(repo_json org/r1 MIT)]"; issues "[$(issue_json 'github-actions[bot]' "$(iso_days_ago 3)")]"; run env
cell "tracked finding within grace passes, updates, never duplicates" '[ $rc = 0 ] && grep -q "^edit #41$" "$WRITES" && ! grep -q "^create" "$WRITES" && grep -q "issues/41" <<< "$OUT"'

# 4 age ratchet: tracked 45 days -> red again
reset; repos "[$(repo_json org/r1 NOASSERTION)]"; issues "[$(issue_json 'github-actions[bot]' "$(iso_days_ago 45)")]"; run env
cell "tracked finding past the grace fails again" '[ $rc = 1 ] && grep -q "over the 30-day grace" <<< "$OUT" && ! grep -q "^create" "$WRITES"'

# 5 look-alike issue by a human is not tracking: new issue, red
reset; repos "[$(repo_json org/r1 MIT)]"; issues "[$(issue_json 'someone' "$(iso_days_ago 1)")]"; run env
cell "an issue not authored by the bot does not track" '[ $rc = 1 ] && grep -q "^create" "$WRITES"'

# 6 filing failure fails the run: it aborts at the filing step, before any verdict is rendered
reset; repos "[$(repo_json org/r1 MIT)]"; run env FAIL_CREATE=1
cell "issue filing failure aborts the run before a verdict" '[ $rc != 0 ] && ! grep -q "^create" "$WRITES" && ! grep -q "| verdict |" <<< "$OUT" && grep -q "HTTP 403" "$T/err"'

# 6b an update failure on a tracked finding fails a run that would otherwise pass
reset; repos "[$(repo_json org/r1 MIT)]"; issues "[$(issue_json 'github-actions[bot]' "$(iso_days_ago 3)")]"; run env FAIL_EDIT=1
cell "issue update failure fails an otherwise passing run" '[ $rc != 0 ] && ! grep -q "| verdict |" <<< "$OUT"'

# 7 an organization that cannot be enumerated fails the run even with no finding
reset; unreadable; run env
cell "an unread organization fails the run" '[ $rc = 1 ] && grep -q "| org | " <<< "$OUT" && grep -q "could not be enumerated" <<< "$OUT"'

# 8 resolved: tracked issue, repository Apache-2.0 again -> closed, pass
reset; issues "[$(issue_json 'github-actions[bot]' "$(iso_days_ago 10)")]"; run env
cell "a resolved finding closes its issue" '[ $rc = 0 ] && grep -q "^close #41$" "$WRITES" && grep -q "resolved: license integrity: org/r1" <<< "$OUT"'

# 9 not resolved when the organization could not be enumerated this run
reset; unreadable; issues "[$(issue_json 'github-actions[bot]' "$(iso_days_ago 10)")]"; run env
cell "an unread organization never resolves its issue" '[ $rc = 1 ] && ! grep -q "^close" "$WRITES"'

# 10 dry run: same verdict, nothing written
reset; repos "[$(repo_json org/r1 MIT)]"; run env DRY_RUN=1
cell "dry run keeps the verdict and writes nothing" '[ $rc = 1 ] && [ ! -s "$WRITES" ] && grep -q "dry run: nothing was written" <<< "$OUT"'

# 11 archived repositories are not part of the population
reset; run env
cell "archived repositories are excluded from the population" 'grep -q "| public unarchived repositories enumerated | 2 |" <<< "$OUT"'

# 12 an allowlisted repository with a reason and the matching id is clean
reset; repos "[$(repo_json org/mit MIT)]"; run env
cell "allowlisted repository with the matching id and a reason is clean" '[ $rc = 0 ] && [ ! -s "$WRITES" ]'

# 13 an allowlisted repository whose classification differs from the allowlist is a finding
reset; repos "[$(repo_json org/mit BSD-3-Clause)]"; run env
cell "allowlist id mismatch is a finding" '[ $rc = 1 ] && grep -q "^create label=license-integrity title=license integrity: org/mit$" "$WRITES" && grep -q "allowlist says .MIT." <<< "$OUT"'

# 14 an allowlist row without a reason does not clear the repository
reset; repos "[$(repo_json org/mit MIT)]"; printf 'org/mit\tMIT\t\n' > "$ALLOW"; run env
cell "allowlist row without a reason is a finding" '[ $rc = 1 ] && grep -q "^create" "$WRITES" && grep -q "reason: .MISSING." <<< "$OUT"'

# 15 NONE (no licence file) and NOASSERTION (rewritten text) are findings, one issue each
reset; repos "[$(repo_json org/r1 null),$(repo_json org/r2 NOASSERTION)]"; run env
cell "NONE and NOASSERTION are findings with one issue each" '[ $rc = 1 ] && [ "$(grep -c "^create" "$WRITES")" = 2 ] && grep -q "| org/r1 | NONE |" <<< "$OUT" && grep -q "| org/r2 | NOASSERTION |" <<< "$OUT"'

# 16 a closed-then-reopened finding: no open bot issue -> new issue, red (closing without fixing re-alarms)
reset; repos "[$(repo_json org/r1 MIT)]"; issues '[]'; run env
cell "a persisting finding with no open issue is untracked again" '[ $rc = 1 ] && grep -q "^create" "$WRITES"'

# 17 a missing allowlist file fails before any network read
reset; run env ALLOWLIST="$T/absent.tsv"
cell "a missing allowlist fails the run" '[ $rc = 1 ] && [ ! -s "$WRITES" ]'

echo "$pass passed, $failn failed"
[ "$failn" = 0 ]
