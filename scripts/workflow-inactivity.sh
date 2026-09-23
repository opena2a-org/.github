#!/usr/bin/env bash
# Detect GitHub Actions workflows that are no longer active across every unarchived repository
# of the listed organizations, and track each one as an open issue in this repository.
#
# GitHub disables every trigger of a workflow (not only its schedule) once a repository has seen
# no activity for 60 days, state `disabled_inactivity`, and sends no notification. A workflow can
# also be switched off by hand, state `disabled_manually`. Either way the repository is public,
# unarchived and unscanned, which is never an acceptable end state: the workflow is re-enabled,
# or the repository is archived with a pointer to its successor.
#
# Alerting is fail-closed and issue-tracked:
#   1. every repository readable, no finding                      -> success
#   2. a finding not tracked by an OPEN issue in this repository that is authored by
#      github-actions[bot] AND labeled $LABEL AND titled for that workflow -> a new issue, run FAILS
#      (authorship plus label is the anti-suppression predicate: this repository is public and
#      anyone can open a look-alike issue)
#   3. every finding tracked and younger than $MAX_TRACKED_AGE_DAYS -> success, and the run
#      summary lists each finding with its issue URL
#   4. issue filing fails                                          -> run FAILS (no `|| true`)
#   5. one open issue per finding, updated on every run, never duplicated; a closed issue with a
#      persisting finding is untracked -> new issue, run FAILS
#   6. a tracked finding older than $MAX_TRACKED_AGE_DAYS         -> run FAILS again (age ratchet)
#   7. a repository whose workflows cannot be read                -> run FAILS (the population is
#      incomplete; a healthy verdict over an unread population would be a lie)
# A finding that is no longer present closes its tracking issue with a comment, but only when
# the repository was read successfully in the same run.
#
# Environment:
#   GH_TOKEN          token that reads Actions metadata of every repository (private ones need a
#                     token with Actions: read on both organizations; the workflow's own token
#                     reads public repositories only)
#   ISSUES_TOKEN      token that files issues in $ISSUE_REPO (defaults to GH_TOKEN)
#   ORGS              space-separated organizations (default: opena2a-org opena2a-standards)
#   ISSUE_REPO        where tracking issues live (default: opena2a-org/.github)
#   LABEL             tracking label (default: workflow-inactivity)
#   MAX_TRACKED_AGE_DAYS  grace period before a tracked finding fails the run again (default 30)
#   DRY_RUN=1         read everything, write nothing (no issues, labels, comments); the summary
#                     says what would have been written
#   GITHUB_STEP_SUMMARY  when set, the run summary is appended there as well as printed
set -euo pipefail

ORGS="${ORGS:-opena2a-org opena2a-standards}"
ISSUE_REPO="${ISSUE_REPO:-opena2a-org/.github}"
LABEL="${LABEL:-workflow-inactivity}"
MAX_TRACKED_AGE_DAYS="${MAX_TRACKED_AGE_DAYS:-30}"
DRY_RUN="${DRY_RUN:-0}"
ISSUES_TOKEN="${ISSUES_TOKEN:-${GH_TOKEN:-}}"
BOT_LOGIN="github-actions[bot]"
TITLE_PREFIX="workflow not active:"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FINDINGS="$WORK/findings.tsv"      # repo \t path \t state \t workflow id
UNREADABLE="$WORK/unreadable.tsv"  # repo \t private \t reason
TRACKED="$WORK/tracked.tsv"        # title \t number \t url \t created_at
REPOS="$WORK/repos.tsv"            # repo \t private
SUMMARY="$WORK/summary.md"
: > "$FINDINGS"; : > "$UNREADABLE"; : > "$TRACKED"; : > "$REPOS"; : > "$SUMMARY"

now_epoch="$(date -u +%s)"
today="$(date -u +%F)"
red=0
reasons=()

say() { printf '%s\n' "$*"; }
fail_reason() { red=1; reasons+=("$1"); }

# ---- population ---------------------------------------------------------------------------------
for ORG in $ORGS; do
  if ! gh api "orgs/$ORG/repos?type=all&per_page=100" --paginate \
        --jq '.[] | select(.archived|not) | [.full_name, (.private|tostring)] | @tsv' >> "$REPOS"; then
    say "FAIL cannot enumerate repositories of $ORG"
    fail_reason "population: organization $ORG could not be enumerated"
  fi
done
sort -u -o "$REPOS" "$REPOS"
repo_count="$(wc -l < "$REPOS" | tr -d ' ')"
private_count="$(awk -F'\t' '$2=="true"' "$REPOS" | wc -l | tr -d ' ')"

# ---- workflows ----------------------------------------------------------------------------------
while IFS=$'\t' read -r REPO PRIVATE; do
  [ -n "$REPO" ] || continue
  if ! out="$(gh api "repos/$REPO/actions/workflows?per_page=100" --paginate \
        --jq '.workflows[] | select(.state != "active") | [.path, .state, (.id|tostring)] | @tsv' 2>"$WORK/err")"; then
    reason="$(head -c 160 "$WORK/err" | tr '\n\t' '  ')"
    printf '%s\t%s\t%s\n' "$REPO" "$PRIVATE" "${reason:-unreadable}" >> "$UNREADABLE"
    continue
  fi
  while IFS=$'\t' read -r WPATH WSTATE WID; do
    [ -n "$WPATH" ] || continue
    printf '%s\t%s\t%s\t%s\n' "$REPO" "$WPATH" "$WSTATE" "$WID" >> "$FINDINGS"
  done <<< "$out"
done < "$REPOS"
finding_count="$(wc -l < "$FINDINGS" | tr -d ' ')"
unreadable_count="$(wc -l < "$UNREADABLE" | tr -d ' ')"

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

issue_body() {  # repo path state id
  cat <<EOF
Workflow \`$2\` in \`$1\` has state \`$3\` (workflow id $4), so none of its triggers run.

Verify:

    gh api repos/$1/actions/workflows/$4 --jq .state

Fix, one of:

    gh workflow enable $4 -R $1          # the workflow is still wanted
    gh repo archive $1                   # the repository is superseded; add a README pointer to its successor

This issue is updated by every weekly run while the finding persists and closed by the run that
finds the workflow active again. The run goes red again once this issue is $MAX_TRACKED_AGE_DAYS days old.

Last seen: $today
EOF
}

ensure_label() {
  if GH_TOKEN="$ISSUES_TOKEN" gh api "repos/$ISSUE_REPO/labels/$LABEL" >/dev/null 2>&1; then return 0; fi
  if [ "$DRY_RUN" = "1" ]; then say "DRY-RUN would create label $LABEL in $ISSUE_REPO"; return 0; fi
  GH_TOKEN="$ISSUES_TOKEN" gh api -X POST "repos/$ISSUE_REPO/labels" \
    -f name="$LABEL" -f color="b60205" \
    -f description="A workflow in an organization repository is not active (disabled by inactivity or by hand)" >/dev/null
}

# ---- reconcile ----------------------------------------------------------------------------------
{
  say "## Workflow inactivity: $today"
  say ""
  say "| population | count |"
  say "|---|---|"
  say "| organizations | $ORGS |"
  say "| unarchived repositories enumerated | $repo_count ($private_count private) |"
  say "| repositories whose workflows could not be read | $unreadable_count |"
  say "| workflows not active | $finding_count |"
  say ""
} >> "$SUMMARY"

if [ "$unreadable_count" -gt 0 ]; then
  fail_reason "$unreadable_count repositories could not be read; the population is incomplete"
  {
    say "### Unreadable repositories (the run fails: an unread repository is not a clean one)"
    say ""
    say "Fix: give the workflow a token with Actions: read on every repository of both organizations"
    say "(secret \`ORG_READ_TOKEN\` in \`$ISSUE_REPO\`); its own token reads public repositories only."
    say ""
    say "| repository | private | reason |"
    say "|---|---|---|"
    while IFS=$'\t' read -r R P REASON; do say "| $R | $P | $REASON |"; done < "$UNREADABLE"
    say ""
  } >> "$SUMMARY"
fi

new_count=0; tracked_count=0; aged_count=0
if [ "$finding_count" -gt 0 ]; then
  ensure_label
  {
    say "### Findings"
    say ""
    say "| repository | workflow | state | tracking | issue |"
    say "|---|---|---|---|---|"
  } >> "$SUMMARY"
  while IFS=$'\t' read -r REPO WPATH WSTATE WID; do
    title="$TITLE_PREFIX $REPO $WPATH"
    hit="$(lookup_tracked "$title")"
    if [ -n "$hit" ]; then
      number="${hit%%$'\t'*}"; rest="${hit#*$'\t'}"; url="${rest%%$'\t'*}"; created="${rest#*$'\t'}"
      age="$(age_days "$created")"
      if [ "$DRY_RUN" = "1" ]; then
        say "DRY-RUN would update #$number ($title)"
      else
        GH_TOKEN="$ISSUES_TOKEN" gh issue edit "$number" -R "$ISSUE_REPO" --body "$(issue_body "$REPO" "$WPATH" "$WSTATE" "$WID")" >/dev/null
      fi
      if [ "$age" -gt "$MAX_TRACKED_AGE_DAYS" ]; then
        aged_count=$((aged_count+1)); status="tracked $age days, over the $MAX_TRACKED_AGE_DAYS-day grace: RED"
        fail_reason "$REPO $WPATH tracked for $age days (#$number)"
      else
        tracked_count=$((tracked_count+1)); status="tracked $age days"
      fi
      say "| $REPO | $WPATH | $WSTATE | $status | $url |" >> "$SUMMARY"
    else
      new_count=$((new_count+1))
      fail_reason "$REPO $WPATH is $WSTATE and was not tracked"
      if [ "$DRY_RUN" = "1" ]; then
        say "DRY-RUN would create issue: $title"
        say "| $REPO | $WPATH | $WSTATE | NEW (untracked): RED | would be filed |" >> "$SUMMARY"
      else
        url="$(GH_TOKEN="$ISSUES_TOKEN" gh issue create -R "$ISSUE_REPO" --title "$title" --label "$LABEL" \
                 --body "$(issue_body "$REPO" "$WPATH" "$WSTATE" "$WID")")"
        say "| $REPO | $WPATH | $WSTATE | NEW (untracked): RED | $url |" >> "$SUMMARY"
      fi
    fi
  done < "$FINDINGS"
  say "" >> "$SUMMARY"
fi

# ---- resolved: tracked issues whose finding is gone from a repository that was read ------------
resolved_count=0
while IFS=$'\t' read -r TITLE NUMBER URL CREATED; do
  [ -n "$TITLE" ] || continue
  rest="${TITLE#"$TITLE_PREFIX" }"; repo="${rest%% *}"; wpath="${rest#* }"
  if grep -qF "$(printf '%s\t%s\t' "$repo" "$wpath")" "$FINDINGS"; then continue; fi          # still a finding
  if ! grep -qF "$(printf '%s\t' "$repo")" "$REPOS"; then continue; fi                        # repo not enumerated (archived/gone): leave it
  if grep -qF "$(printf '%s\t' "$repo")" "$UNREADABLE"; then continue; fi                     # not read this run: not proven resolved
  resolved_count=$((resolved_count+1))
  if [ "$DRY_RUN" = "1" ]; then
    say "DRY-RUN would close #$NUMBER ($TITLE)"
  else
    GH_TOKEN="$ISSUES_TOKEN" gh issue close "$NUMBER" -R "$ISSUE_REPO" \
      --comment "Resolved: \`$wpath\` in \`$repo\` is no longer reported as inactive (active again, or removed) as of the $today run." >/dev/null
  fi
  say "- resolved: $TITLE ($URL)" >> "$SUMMARY"
done < "$TRACKED"

{
  say ""
  say "| verdict | new | tracked | aged | resolved | unreadable |"
  say "|---|---|---|---|---|---|"
  if [ "$red" = 1 ]; then v="FAIL"; else v="pass"; fi
  say "| $v | $new_count | $tracked_count | $aged_count | $resolved_count | $unreadable_count |"
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
