#!/usr/bin/env bash
# The project board with minimal output (#27).
#
# status: the column of an issue's card; move <N> <from> <to>: moves it,
# refusing when the card is not in <from>; check: the checks at the start of
# every task, printing only the violations; list: the open issues in a
# column; add-pr: a card in In review for a reopened PR. Field and option
# IDs are looked up by name on every call. Contract: the skill's
# references/shell-tools.md.
#
# Exit codes: 0 success; 1 error, refusal or violations found; 2 usage.
set -uo pipefail

readonly E_FAIL=1 E_USAGE=2
readonly IN_REVIEW='In review' DONE='Done'

say() { printf 'board.sh: %s\n' "$*" >&2; }
die() { local code=$1; shift; say "$@"; exit "$code"; }
usage() {
  die "$E_USAGE" "usage: board.sh status <N>
       board.sh move <N> <from> <to>
       board.sh check
       board.sh list <column>
       board.sh add-pr <PR>"
}

TMP=$(mktemp -d) || exit "$E_FAIL"
trap 'rm -rf "$TMP"' EXIT

# Runs gh; prints its stdout. On failure, dies with gh's first stderr line.
# A GraphQL answer carrying errors is a failure too.
gh_call() {
  local out rc
  out=$(gh "$@" 2> "$TMP/err")
  rc=$?
  if (( rc != 0 )); then
    local msg
    msg=$(head -n 1 "$TMP/err")
    die "$E_FAIL" "gh: ${msg:-failed with exit code $rc}"
  fi
  if [[ $out == '{'* ]] && jq -e 'has("errors")' <<< "$out" > /dev/null 2>&1; then
    die "$E_FAIL" "gh: $(jq -r '.errors[0].message' <<< "$out")"
  fi
  printf '%s\n' "$out"
}

# Sets OWNER and NAME: GH_REPO ([HOST/]OWNER/NAME), else the current repo.
repo() {
  local r=${GH_REPO:-}
  if [[ -z $r ]]; then
    r=$(gh_call repo view --json nameWithOwner | jq -r .nameWithOwner) || exit "$E_FAIL"
  fi
  NAME=${r##*/}
  r=${r%/*}
  OWNER=${r##*/}
  [[ -n $OWNER && -n $NAME ]] || die "$E_FAIL" "cannot tell the repository from '$r'"
}

STATUS='fieldValueByName(name: "Status") { ... on ProjectV2ItemFieldSingleSelectValue { name } }'

# Sets ITEM, PROJECT and COLUMN for the card of issue $1; COLUMN is "none"
# when there is no card. Dies when the issue is on several boards.
card() {
  local doc n
  doc=$(gh_call api graphql -F number="$1" -f owner="$OWNER" -f name="$NAME" -f query="
query(\$owner: String!, \$name: String!, \$number: Int!) {
  repository(owner: \$owner, name: \$name) {
    issue(number: \$number) { id number projectItems(first: 20) { nodes { id project { id number title } $STATUS } } }
  }
}") || exit "$E_FAIL"
  [[ $(jq -r '.data.repository.issue // empty | .id' <<< "$doc") != '' ]] || die "$E_FAIL" "no issue #$1"
  n=$(jq '.data.repository.issue.projectItems.nodes | length' <<< "$doc")
  if (( n > 1 )); then
    die "$E_FAIL" "#$1 is on $n boards ($(jq -r '[.data.repository.issue.projectItems.nodes[].project.number | "#\(.)"] | join(", ")' <<< "$doc")): ask the maintainer"
  fi
  if (( n == 0 )); then
    ITEM='' PROJECT='' COLUMN=none
    return
  fi
  ITEM=$(jq -r '.data.repository.issue.projectItems.nodes[0].id' <<< "$doc")
  PROJECT=$(jq -r '.data.repository.issue.projectItems.nodes[0].project.id' <<< "$doc")
  COLUMN=$(jq -r '.data.repository.issue.projectItems.nodes[0].fieldValueByName.name // "(no status)"' <<< "$doc")
}

# Sets FIELD and OPTIONS (one "id<TAB>name" per line) for the Status field
# of board $1.
status_field() {
  local doc
  # shellcheck disable=SC2016 # $vars of the GraphQL query, for gh, not the shell
  doc=$(gh_call api graphql -f project="$1" -f query='
query($project: ID!) {
  node(id: $project) { ... on ProjectV2 { field(name: "Status") { ... on ProjectV2SingleSelectField { id name options { id name } } } } }
}') || exit "$E_FAIL"
  FIELD=$(jq -r '.data.node.field.id // empty' <<< "$doc")
  [[ -n $FIELD ]] || die "$E_FAIL" "the board has no Status field"
  OPTIONS=$(jq -r '.data.node.field.options[] | "\(.id)\t\(.name)"' <<< "$doc")
}

# Prints the option id of column $1, or dies with the valid columns.
option_of() {
  local id name
  while IFS=$'\t' read -r id name; do
    [[ $name == "$1" ]] && { printf '%s\n' "$id"; return 0; }
  done <<< "$OPTIONS"
  die "$E_FAIL" "unknown column: $1 (valid: $(cut -f2 <<< "$OPTIONS" | paste -sd, - | sed 's/,/, /g'))"
}

# Sets item $1 of board $2 to option $3; prints the column of the answer.
set_column() {
  local doc
  doc=$(gh_call api graphql -f project="$2" -f item="$1" -f field="$FIELD" -f option="$3" -f query="
mutation(\$project: ID!, \$item: ID!, \$field: ID!, \$option: String!) {
  updateProjectV2ItemFieldValue(input: { projectId: \$project, itemId: \$item, fieldId: \$field, value: { singleSelectOptionId: \$option } }) {
    projectV2Item { id $STATUS }
  }
}") || exit "$E_FAIL"
  jq -r '.data.updateProjectV2ItemFieldValue.projectV2Item.fieldValueByName.name // "(no status)"' <<< "$doc"
}

cmd_status() {
  card "$1"
  printf '%s\n' "$COLUMN"
}

cmd_move() {
  local n=$1 from=$2 to=$3 opt now
  # Every lookup first...
  card "$n"
  [[ -n $ITEM ]] || die "$E_FAIL" "#$n has no card"
  status_field "$PROJECT"
  option_of "$from" > /dev/null || exit "$E_FAIL"
  opt=$(option_of "$to") || exit "$E_FAIL"
  # ...then the status read and, at once, the mutation: one round trip.
  card "$n"
  [[ $COLUMN == "$from" ]] || die "$E_FAIL" "#$n is $COLUMN, not $from"
  now=$(set_column "$ITEM" "$PROJECT" "$opt") || exit "$E_FAIL"
  [[ $now == "$to" ]] || die "$E_FAIL" "#$n is $now after the move, not $to"
  printf '#%s %s -> %s\n' "$n" "$from" "$to"
}

ITEMS='projectItems(first: 5) { nodes { id project { id number } '"$STATUS"' } }'
PAGE='pageInfo { hasNextPage endCursor }'
ISSUE_NODE="number closedByPullRequestsReferences(first: 5, includeClosedPrs: false) { nodes { number } } $ITEMS"
PULL_NODE="number timelineItems(first: 1, itemTypes: [REOPENED_EVENT]) { filteredCount } $ITEMS"

# Prints the open issues and PRs of the repository, every page, as one JSON
# document { issues: [...], pullRequests: [...] }. The first pages of both
# come in one query; the next ones, connection by connection.
open_items() {
  local doc all c node after more
  doc=$(gh_call api graphql -f owner="$OWNER" -f name="$NAME" -f query="
query(\$owner: String!, \$name: String!) {
  repository(owner: \$owner, name: \$name) {
    issues(states: OPEN, first: 100) { $PAGE nodes { $ISSUE_NODE } }
    pullRequests(states: OPEN, first: 100) { $PAGE nodes { $PULL_NODE } }
  }
}") || exit "$E_FAIL"
  all=$(jq '.data.repository | { issues: .issues.nodes, pullRequests: .pullRequests.nodes }' <<< "$doc") || exit "$E_FAIL"
  for c in issues pullRequests; do
    node=$ISSUE_NODE
    [[ $c == pullRequests ]] && node=$PULL_NODE
    more=$(jq -r --arg c "$c" '.data.repository[$c].pageInfo.hasNextPage' <<< "$doc")
    after=$(jq -r --arg c "$c" '.data.repository[$c].pageInfo.endCursor // empty' <<< "$doc")
    while [[ $more == true ]]; do
      local page
      page=$(gh_call api graphql -f owner="$OWNER" -f name="$NAME" -f after="$after" -f query="
query(\$owner: String!, \$name: String!, \$after: String!) {
  repository(owner: \$owner, name: \$name) { $c(states: OPEN, first: 100, after: \$after) { $PAGE nodes { $node } } }
}") || exit "$E_FAIL"
      all=$(jq --arg c "$c" --argjson more "$(jq --arg c "$c" '.data.repository[$c].nodes' <<< "$page")" \
        '.[$c] += $more' <<< "$all") || exit "$E_FAIL"
      more=$(jq -r --arg c "$c" '.data.repository[$c].pageInfo.hasNextPage' <<< "$page")
      after=$(jq -r --arg c "$c" '.data.repository[$c].pageInfo.endCursor // empty' <<< "$page")
    done
  done
  printf '%s\n' "$all"
}

cmd_check() {
  local all out
  all=$(open_items) || exit "$E_FAIL"
  out=$(jq -r --arg r "$IN_REVIEW" --arg d "$DONE" '
    .issues as $i | .pullRequests as $p |
    def col: .projectItems.nodes[0].fieldValueByName.name // null;
    ($i | sort_by(.number)[] | select((.projectItems.nodes | length) > 0)
      | [.closedByPullRequestsReferences.nodes[].number] as $prs | col as $c
      | (if ($prs | length) > 0 and $c != $r then "#\(.number) has open PR #\($prs[0]) but is \($c // "(no status)"), not \($r)" else empty end),
        (if ($prs | length) == 0 and $c == $r then "#\(.number) is \($r) without an open PR" else empty end),
        (if $c == $d then "#\(.number) is open in \($d): ask the maintainer why" else empty end)),
    ($p | sort_by(.number)[] | select((.projectItems.nodes | length) > 0) | col as $c
      | if .timelineItems.filteredCount == 0 then "PR #\(.number) has a card but was never reopened"
        elif $c != $r then "PR #\(.number) was reopened; its card is \($c // "(no status)"), not \($r)"
        else empty end)' <<< "$all") || die "$E_FAIL" "cannot read the board"
  [[ -z $out ]] && return 0
  printf '%s\n' "$out"
  return "$E_FAIL"
}

cmd_list() {
  local all
  all=$(open_items) || exit "$E_FAIL"
  jq -r --arg c "$1" '.issues | sort_by(.number)[] | select(.projectItems.nodes[0].fieldValueByName.name == $c) | .number' <<< "$all"
}

cmd_add_pr() {
  local n=$1 doc boards pr item opt now
  # shellcheck disable=SC2016 # $vars of the GraphQL query, for gh, not the shell
  doc=$(gh_call api graphql -F number="$n" -f owner="$OWNER" -f name="$NAME" -f query='
query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) { id number
      closingIssuesReferences(first: 10) { nodes { number projectItems(first: 5) { nodes { id project { id number title } } } } } }
  }
}') || exit "$E_FAIL"
  pr=$(jq -r '.data.repository.pullRequest.id // empty' <<< "$doc")
  [[ -n $pr ]] || die "$E_FAIL" "no PR #$n"
  boards=$(jq -r '[.data.repository.pullRequest.closingIssuesReferences.nodes[].projectItems.nodes[].project] | unique_by(.id)' <<< "$doc")
  case $(jq length <<< "$boards") in
    0) die "$E_FAIL" "PR #$n closes no issue with a card" ;;
    1) PROJECT=$(jq -r '.[0].id' <<< "$boards") ;;
    *) die "$E_FAIL" "PR #$n is linked to $(jq length <<< "$boards") boards ($(jq -r 'map("#\(.number)") | join(", ")' <<< "$boards")): ask the maintainer" ;;
  esac
  status_field "$PROJECT"
  opt=$(option_of "$IN_REVIEW") || exit "$E_FAIL"
  # shellcheck disable=SC2016 # $vars of the GraphQL query, for gh, not the shell
  doc=$(gh_call api graphql -f project="$PROJECT" -f content="$pr" -f query='
mutation($project: ID!, $content: ID!) {
  addProjectV2ItemById(input: { projectId: $project, contentId: $content }) { item { id } }
}') || exit "$E_FAIL"
  item=$(jq -r '.data.addProjectV2ItemById.item.id // empty' <<< "$doc")
  [[ -n $item ]] || die "$E_FAIL" "PR #$n: no card was added"
  now=$(set_column "$item" "$PROJECT" "$opt") || exit "$E_FAIL"
  [[ $now == "$IN_REVIEW" ]] || die "$E_FAIL" "PR #$n is $now after the move, not $IN_REVIEW"
  printf 'PR #%s -> %s\n' "$n" "$IN_REVIEW"
}

main() {
  local cmd=${1:-}
  (( $# )) && shift
  # shellcheck disable=SC2015 # usage exits: it runs only when a check fails
  case $cmd in
    status) (( $# == 1 )) && [[ $1 =~ ^[0-9]+$ ]] || usage ;;
    move) (( $# == 3 )) && [[ $1 =~ ^[0-9]+$ && -n $2 && -n $3 ]] || usage ;;
    check) (( $# == 0 )) || usage ;;
    list) (( $# == 1 )) && [[ -n $1 ]] || usage ;;
    add-pr) (( $# == 1 )) && [[ $1 =~ ^[0-9]+$ ]] || usage ;;
    *) usage ;;
  esac
  repo
  case $cmd in
    status) cmd_status "$@" ;;
    move) cmd_move "$@" ;;
    check) cmd_check ;;
    list) cmd_list "$@" ;;
    add-pr) cmd_add_pr "$@" ;;
  esac
}

main "$@"
exit $?

# --- Change History -------------------------------------------------------
# | PR     | Summary                                                       |
# |--------|---------------------------------------------------------------|
# | #30    | new: status, move, check, list, add-pr (#27)                  |
