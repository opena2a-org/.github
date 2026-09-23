#!/usr/bin/env bash
# Check that every public, unarchived repository of the listed organizations classifies
# Apache-2.0 on GitHub, or is carried in LICENSE-ALLOWLIST.tsv with its allowed SPDX id and a
# reason, and track each finding as one open issue in this repository.
#
# GitHub classifies a repository's LICENSE text; a rewritten text reads NOASSERTION and a
# missing file reads NONE. Either is a finding, as is any other id not explained by the
# allowlist, so a licence regression cannot accrue silently.
#
# Alerting is fail-closed and issue-tracked, the same rules as scripts/workflow-inactivity.sh:
#   1. every organization enumerated, no finding                  -> success
#   2. a finding not tracked by an OPEN issue in this repository that is authored by
#      github-actions[bot] AND labeled $LABEL AND titled for that repository -> a new issue,
#      run FAILS (authorship plus label is the anti-suppression predicate: this repository is
#      public and anyone can open a look-alike issue)
#   3. every finding tracked and younger than $MAX_TRACKED_AGE_DAYS -> success, and the run
#      summary lists each finding with its issue URL
#   4. issue filing fails                                          -> run FAILS (no `|| true`)
#   5. one open issue per finding, updated on every run, never duplicated; a closed issue with a
#      persisting finding is untracked -> new issue, run FAILS
#   6. a tracked finding older than $MAX_TRACKED_AGE_DAYS         -> run FAILS again (age ratchet)
#   7. an organization that cannot be enumerated                  -> run FAILS (the population is
#      incomplete; a clean verdict over an unread population would be a lie)
# A finding that is no longer present closes its tracking issue with a comment, but only when
# its organization was enumerated successfully in the same run.
#
# Environment:
#   GH_TOKEN          token that lists the organizations' public repositories
#   ISSUES_TOKEN      token that files issues in $ISSUE_REPO (defaults to GH_TOKEN)
#   ORGS              space-separated organizations (default: opena2a-org opena2a-standards)
#   ISSUE_REPO        where tracking issues live (default: opena2a-org/.github)
#   LABEL             tracking label (default: license-integrity)
#   ALLOWLIST         path of the allowlist TSV (default: LICENSE-ALLOWLIST.tsv), columns
#                     full_name, allowed SPDX id, reason
#   MAX_TRACKED_AGE_DAYS  grace period before a tracked finding fails the run again (default 30)
#   DRY_RUN=1         read everything, write nothing (no issues, labels, comments); the summary
#                     says what would have been written
#   GITHUB_STEP_SUMMARY  when set, the run summary is appended there as well as printed
set -euo pipefail

ORGS="${ORGS:-opena2a-org opena2a-standards}"
ISSUE_REPO="${ISSUE_REPO:-opena2a-org/.github}"
LABEL="${LABEL:-license-integrity}"
ALLOWLIST="${ALLOWLIST:-LICENSE-ALLOWLIST.tsv}"
MAX_TRACKED_AGE_DAYS="${MAX_TRACKED_AGE_DAYS:-30}"
DRY_RUN="${DRY_RUN:-0}"
ISSUES_TOKEN="${ISSUES_TOKEN:-${GH_TOKEN:-}}"
BOT_LOGIN="github-actions[bot]"
TITLE_PREFIX="license integrity:"
REQUIRED_SPDX="Apache-2.0"

[ -f "$ALLOWLIST" ] || { echo "FAIL allowlist $ALLOWLIST is not a file"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
REPOS="$WORK/repos.tsv"            # repo \t spdx
FINDINGS="$WORK/findings.tsv"      # repo \t spdx \t reason
UNREAD="$WORK/unread.tsv"          # org \t reason
TRACKED="$WORK/tracked.tsv"        # title \t number \t url \t created_at
SUMMARY="$WORK/summary.md"
: > "$REPOS"; : > "$FINDINGS"; : > "$UNREAD"; : > "$TRACKED"; : > "$SUMMARY"

now_epoch="$(date -u +%s)"
today="$(date -u +%F)"
red=0
reasons=()

say() { printf '%s\n' "$*"; }
fail_reason() { red=1; reasons+=("$1"); }

# ---- population ---------------------------------------------------------------------------------
for ORG in $ORGS; do
  if ! gh api "orgs/$ORG/repos?type=public&per_page=100" --paginate \
        --jq '.[] | select(.archived|not) | [.full_name, (.license.spdx_id // "NONE")] | @tsv' \
        >> "$REPOS" 2>"$WORK/err"; then
    reason="$(head -c 160 "$WORK/err" | tr '\n\t' '  ')"
    printf '%s\t%s\n' "$ORG" "${reason:-unreadable}" >> "$UNREAD"
  fi
done
sort -u -o "$REPOS" "$REPOS"
repo_count="$(wc -l < "$REPOS" | tr -d ' ')"
unread_count="$(wc -l < "$UNREAD" | tr -d ' ')"

# ---- classification ---------------------------------------------------------------------------
allowlist_row() {  # repo -> "allowed\treason" or empty
  awk -F'\t' -v r="$1" '$1==r {print $2 "\t" $3; exit}' "$ALLOWLIST"
}
while IFS=$'\t' read -r REPO SPDX; do
  [ -n "$REPO" ] || continue
  if [ "$SPDX" = "$REQUIRED_SPDX" ]; then continue; fi
  row="$(allowlist_row "$REPO")"
  if [ -z "$row" ]; then
    printf '%s\t%s\t%s\n' "$REPO" "$SPDX" "classifies $SPDX and is not allowlisted" >> "$FINDINGS"
    continue
  fi
  allowed="${row%%$'\t'*}"; reason="${row#*$'\t'}"
  if [ "$SPDX" != "$allowed" ] || [ -z "$reason" ]; then
    printf '%s\t%s\t%s\n' "$REPO" "$SPDX" \
      "classifies $SPDX; allowlist says '$allowed' (reason: '${reason:-MISSING}')" >> "$FINDINGS"
  fi
done < "$REPOS"
finding_count="$(wc -l < "$FINDINGS" | tr -d ' ')"

# ---- tracking issues (open, bot-authored, labeled) ----------------------------------------------
GH_TOKEN="$ISSUES_TOKEN" gh api "repos/$ISSUE_REPO/issues?state=open&labels=$LABEL&per_page=100" --paginate \
  --jq ".[] | select(.pull_request == null) | select(.user.login == \"$BOT_LOGIN\") | [.title, (.number|tostring), .html_url, .created_at] | @tsv" \
  > "$TRACKED"

lookup_tracked() {  # title -> "number\turl\tcreated_at" or empty
  awk -F'\t' -v t="$1" '$1==t {print $2 "\t" $3 "\t" $4; exit}' "$TRACKED"
}

age_days() {  # ISO-8601 -> whole days since
  local t="$1" e
  if e="$(date -u -d "$t" +%s 2>/dev/null)"; then :; else e="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$t" +%s)"; fi
  echo $(( (now_epoch - e) / 86400 ))
}

issue_body() {  # repo spdx reason
  cat <<EOF
Public repository \`$1\` $3. Every public repository of the organization must classify
\`$REQUIRED_SPDX\` on GitHub, or be carried in \`LICENSE-ALLOWLIST.tsv\` with its allowed SPDX id and a
reason. \`NOASSERTION\` means the LICENSE text was rewritten and GitHub no longer recognises it;
\`NONE\` means there is no LICENSE file.

Verify:

    gh api repos/$1 --jq '.license.spdx_id // "NONE"'

Fix, one of:

    # restore the verbatim licence text in the repository
    curl -sSL https://www.apache.org/licenses/LICENSE-2.0.txt -o LICENSE
    # or, when the licence is intentional, allowlist it with a reason
    printf '%s\t%s\t%s\n' "$1" "<spdx id>" "<why>" >> LICENSE-ALLOWLIST.tsv

This issue is updated by every weekly run while the finding persists and closed by the run that
finds the repository compliant again. The run goes red again once this issue is $MAX_TRACKED_AGE_DAYS days old.

Last seen: $today
EOF
}

ensure_label() {
  if GH_TOKEN="$ISSUES_TOKEN" gh api "repos/$ISSUE_REPO/labels/$LABEL" >/dev/null 2>&1; then return 0; fi
  if [ "$DRY_RUN" = "1" ]; then say "DRY-RUN would create label $LABEL in $ISSUE_REPO"; return 0; fi
  GH_TOKEN="$ISSUES_TOKEN" gh api -X POST "repos/$ISSUE_REPO/labels" \
    -f name="$LABEL" -f color="b60205" \
    -f description="A public organization repository does not classify Apache-2.0 and is not allowlisted with a reason" >/dev/null
}

# ---- reconcile ----------------------------------------------------------------------------------
{
  say "## License integrity: $today"
  say ""
  say "| population | count |"
  say "|---|---|"
  say "| organizations | $ORGS |"
  say "| public unarchived repositories enumerated | $repo_count |"
  say "| organizations that could not be enumerated | $unread_count |"
  say "| repositories not $REQUIRED_SPDX and not allowlisted | $finding_count |"
  say ""
} >> "$SUMMARY"

if [ "$unread_count" -gt 0 ]; then
  fail_reason "$unread_count organizations could not be enumerated; the population is incomplete"
  {
    say "### Organizations not enumerated (the run fails: an unread population is not a clean one)"
    say ""
    say "| organization | reason |"
    say "|---|---|"
    while IFS=$'\t' read -r O REASON; do say "| $O | $REASON |"; done < "$UNREAD"
    say ""
  } >> "$SUMMARY"
fi

new_count=0; tracked_count=0; aged_count=0
if [ "$finding_count" -gt 0 ]; then
  ensure_label
  {
    say "### Findings"
    say ""
    say "| repository | classifies | finding | tracking | issue |"
    say "|---|---|---|---|---|"
  } >> "$SUMMARY"
  while IFS=$'\t' read -r REPO SPDX REASON; do
    title="$TITLE_PREFIX $REPO"
    hit="$(lookup_tracked "$title")"
    if [ -n "$hit" ]; then
      number="${hit%%$'\t'*}"; rest="${hit#*$'\t'}"; url="${rest%%$'\t'*}"; created="${rest#*$'\t'}"
      age="$(age_days "$created")"
      if [ "$DRY_RUN" = "1" ]; then
        say "DRY-RUN would update #$number ($title)"
      else
        GH_TOKEN="$ISSUES_TOKEN" gh issue edit "$number" -R "$ISSUE_REPO" --body "$(issue_body "$REPO" "$SPDX" "$REASON")" >/dev/null
      fi
      if [ "$age" -gt "$MAX_TRACKED_AGE_DAYS" ]; then
        aged_count=$((aged_count+1)); status="tracked $age days, over the $MAX_TRACKED_AGE_DAYS-day grace: RED"
        fail_reason "$REPO tracked for $age days (#$number)"
      else
        tracked_count=$((tracked_count+1)); status="tracked $age days"
      fi
      say "| $REPO | $SPDX | $REASON | $status | $url |" >> "$SUMMARY"
    else
      new_count=$((new_count+1))
      fail_reason "$REPO $REASON and was not tracked"
      if [ "$DRY_RUN" = "1" ]; then
        say "DRY-RUN would create issue: $title"
        say "| $REPO | $SPDX | $REASON | NEW (untracked): RED | would be filed |" >> "$SUMMARY"
      else
        url="$(GH_TOKEN="$ISSUES_TOKEN" gh issue create -R "$ISSUE_REPO" --title "$title" --label "$LABEL" \
                 --body "$(issue_body "$REPO" "$SPDX" "$REASON")")"
        say "| $REPO | $SPDX | $REASON | NEW (untracked): RED | $url |" >> "$SUMMARY"
      fi
    fi
  done < "$FINDINGS"
  say "" >> "$SUMMARY"
fi

# ---- resolved: tracked issues whose finding is gone from an organization that was enumerated ---
resolved_count=0
while IFS=$'\t' read -r TITLE NUMBER URL CREATED; do
  [ -n "$TITLE" ] || continue
  repo="${TITLE#"$TITLE_PREFIX" }"
  if grep -qF "$(printf '%s\t' "$repo")" "$FINDINGS"; then continue; fi                 # still a finding
  org="${repo%%/*}"
  if grep -qF "$(printf '%s\t' "$org")" "$UNREAD"; then continue; fi                    # not read this run: not proven resolved
  if ! grep -qF "$(printf '%s\t' "$repo")" "$REPOS"; then continue; fi                  # not public/unarchived any more: leave it to a person
  resolved_count=$((resolved_count+1))
  if [ "$DRY_RUN" = "1" ]; then
    say "DRY-RUN would close #$NUMBER ($TITLE)"
  else
    GH_TOKEN="$ISSUES_TOKEN" gh issue close "$NUMBER" -R "$ISSUE_REPO" \
      --comment "Resolved: \`$repo\` classifies $REQUIRED_SPDX or is allowlisted with a reason as of the $today run." >/dev/null
  fi
  say "- resolved: $TITLE ($URL)" >> "$SUMMARY"
done < "$TRACKED"

{
  say ""
  say "| verdict | new | tracked | aged | resolved | unread organizations |"
  say "|---|---|---|---|---|---|"
  if [ "$red" = 1 ]; then v="FAIL"; else v="pass"; fi
  say "| $v | $new_count | $tracked_count | $aged_count | $resolved_count | $unread_count |"
  if [ "$red" = 1 ]; then
    say ""
    say "Failing because:"
    for r in "${reasons[@]}"; do say "- $r"; done
  fi
  if [ "$DRY_RUN" = "1" ]; then say ""; say "_dry run: nothing was written_"; fi
} >> "$SUMMARY"

cat "$SUMMARY"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then cat "$SUMMARY" >> "$GITHUB_STEP_SUMMARY"; fi
exit "$red"
