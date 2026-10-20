#!/usr/bin/env bats
# tools/board.sh: the project board with minimal output (#27).
# Contract: references/shell-tools.md. gh is replaced by tools/fixtures/gh,
# which answers from the fixtures under tools/fixtures/board/ (GitHub's
# GraphQL answers) and logs every call, in order. The stub tells the queries
# apart by the GraphQL names they must contain: projectItems (the card),
# ProjectV2SingleSelectField (the Status field and its options, in a query of
# its own), updateProjectV2ItemFieldValue and addProjectV2ItemById (the
# mutations), pullRequests (the repository's open issues and PRs) and
# closingIssuesReferences (the issue a PR closes).

bats_require_minimum_version 1.5.0

setup() {
  BOARD="$BATS_TEST_DIRNAME/board.sh"
  BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$BIN"
  ln -s "$BATS_TEST_DIRNAME/fixtures/gh" "$BIN/gh"
  export PATH="$BIN:$PATH"
  export GH_REPO=acme/widgets
  export GH_STUB_DIR="$BATS_TEST_DIRNAME/fixtures/board"
  export GH_STUB_LOG="$BATS_TEST_TMPDIR/gh.log"
  export GH_STUB_RULES="$BATS_TEST_TMPDIR/gh.rules"
  : > "$GH_STUB_LOG"
}

# Writes the stub's rules: each argument is "<glob>|<answer>".
rules() {
  local r
  for r in "$@"; do printf '%s\t%s\n' "${r%%|*}" "${r#*|}"; done > "$GH_STUB_RULES"
}

# The card of #27 (In progress), the Status field and its options, and the
# answer to the mutation.
move_rules() {
  rules "*updateProjectV2ItemFieldValue*|${1:-moved-review.json}" \
        '*ProjectV2SingleSelectField*|field.json' \
        '*projectItems*|item-27.json'
}

# Prints the number of the last log line matching a fixed string, or nothing.
last_line_of() {
  grep -nF "$1" "$GH_STUB_LOG" | tail -1 | cut -d: -f1
}

# --- status ------------------------------------------------------------------

@test "status: the column of the issue's card" {
  rules '*projectItems*|item-27.json'
  run --separate-stderr "$BOARD" status 27
  [[ -z "$stderr" ]]
  [[ "$status" -eq 0 ]]
  [[ "$output" == 'In progress' ]]
}

@test "status: none when the issue has no card" {
  rules '*projectItems*|item-27-none.json'
  run --separate-stderr "$BOARD" status 27
  [[ -z "$stderr" ]]
  [[ "$status" -eq 0 ]]
  [[ "$output" == none ]]
}

@test "an issue on several boards: refused, ask the maintainer" {
  rules '*projectItems*|item-27-two.json'
  run --separate-stderr "$BOARD" status 27
  [[ "$status" -eq 1 ]]
  [[ -z "$output" ]]
  [[ "$stderr" == 'board.sh: #27 is on 2 boards (#3, #5): ask the maintainer' ]]
}

# --- move <N> <from> <to> -----------------------------------------------------

@test "move: from the expected column to the new one" {
  move_rules
  run --separate-stderr "$BOARD" move 27 'In progress' 'In review'
  [[ -z "$stderr" ]]
  [[ "$status" -eq 0 ]]
  [[ "$output" == '#27 In progress -> In review' ]]
  grep 'updateProjectV2ItemFieldValue' "$GH_STUB_LOG" | grep -q 'o_review'
}

@test "move: every lookup first, then the status read, then the mutation at once" {
  move_rules
  run --separate-stderr "$BOARD" move 27 'In progress' 'In review'
  [[ -z "$stderr" ]]
  [[ "$status" -eq 0 ]]
  total=$(wc -l < "$GH_STUB_LOG")
  mutation=$(last_line_of updateProjectV2ItemFieldValue)
  read=$(last_line_of projectItems)
  field=$(last_line_of ProjectV2SingleSelectField)
  [[ -n "$mutation" && -n "$read" && -n "$field" ]]
  (( mutation == total ))     # nothing after the mutation
  (( read == mutation - 1 ))  # the status read right before it
  (( field < read ))          # the lookups before the status read
}

@test "move: the card is not in <from>: refused, nothing moved" {
  move_rules
  run --separate-stderr "$BOARD" move 27 Ready 'In review'
  [[ "$status" -eq 1 ]]
  [[ -z "$output" ]]
  [[ "$stderr" == 'board.sh: #27 is In progress, not Ready' ]]
  run ! grep -q updateProjectV2ItemFieldValue "$GH_STUB_LOG"
}

@test "move: an unknown column is refused with the valid ones, nothing moved" {
  move_rules
  run --separate-stderr "$BOARD" move 27 'In progress' Doing
  [[ "$status" -eq 1 ]]
  [[ -z "$output" ]]
  [[ "$stderr" == 'board.sh: unknown column: Doing (valid: Backlog, Ready, In progress, In review, Done)' ]]
  run ! grep -q updateProjectV2ItemFieldValue "$GH_STUB_LOG"
}

@test "move: the mutation's answer is checked against <to>" {
  move_rules moved-done.json
  run --separate-stderr "$BOARD" move 27 'In progress' 'In review'
  [[ "$status" -eq 1 ]]
  [[ -z "$output" ]]
  [[ "$stderr" == 'board.sh: #27 is Done after the move, not In review' ]]
}

@test "move: an issue with no card is refused" {
  rules '*ProjectV2SingleSelectField*|field.json' '*projectItems*|item-27-none.json'
  run --separate-stderr "$BOARD" move 27 Backlog Ready
  [[ "$status" -eq 1 ]]
  [[ -z "$output" ]]
  [[ "$stderr" == 'board.sh: #27 has no card' ]]
  run ! grep -q updateProjectV2ItemFieldValue "$GH_STUB_LOG"
}

# --- check -------------------------------------------------------------------

@test "check: a clean board prints nothing" {
  rules '*pullRequests*|repo-clean.json'
  run --separate-stderr "$BOARD" check
  [[ -z "$stderr" ]]
  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]
}

@test "check: one line per violation, issues then PRs, exit 1" {
  rules '*pullRequests*|repo-violations.json'
  run --separate-stderr "$BOARD" check
  [[ -z "$stderr" ]]
  [[ "$status" -eq 1 ]]
  [[ "$output" == '#10 has open PR #20 but is Ready, not In review
#11 is In review without an open PR
#12 is open in Done: ask the maintainer why
PR #21 has a card but was never reopened
PR #22 was reopened; its card is In progress, not In review' ]]
}

# Moved from skill-md.bats, where they read the query in SKILL.md: the query
# now lives in board.sh. totalCount ignores itemTypes (GitHub API quirk):
# every open PR would appear reopened. filteredCount counts only matching
# events.
@test "board.sh query uses filteredCount for the REOPENED_EVENT filter" {
  run --separate-stderr grep -cF 'filteredCount' "$BOARD"
  [[ -z "$stderr" ]]
  [[ "$output" -ge 1 ]]
}

@test "board.sh query does not use totalCount for the REOPENED_EVENT filter" {
  [[ -f "$BOARD" ]]
  run --separate-stderr grep -cE 'REOPENED_EVENT[^}]*\{ *totalCount' "$BOARD"
  [[ -z "$stderr" ]]
  [[ "$output" -eq 0 ]]
}

# --- list and add-pr ---------------------------------------------------------

@test "list: the open issues in a column, one number per line" {
  rules '*pullRequests*|repo-violations.json'
  run --separate-stderr "$BOARD" list 'In review'
  [[ -z "$stderr" ]]
  [[ "$status" -eq 0 ]]
  [[ "$output" == '11
13' ]]
}

@test "add-pr: a reopened PR gets a card in In review on its issue's board" {
  rules '*updateProjectV2ItemFieldValue*|moved-review.json' \
        '*addProjectV2ItemById*|added.json' \
        '*ProjectV2SingleSelectField*|field.json' \
        '*closingIssuesReferences*|pr-22.json'
  run --separate-stderr "$BOARD" add-pr 22
  [[ -z "$stderr" ]]
  [[ "$status" -eq 0 ]]
  [[ "$output" == 'PR #22 -> In review' ]]
  grep 'addProjectV2ItemById' "$GH_STUB_LOG" | grep -q 'PVT_3'
  grep 'updateProjectV2ItemFieldValue' "$GH_STUB_LOG" | grep -q 'o_review'
}

@test "an unknown subcommand: usage error, exit 2" {
  rules
  run --separate-stderr "$BOARD" frobnicate
  [[ "$status" -eq 2 ]]
  [[ -z "$output" ]]
  [[ "$stderr" == *usage* ]]
}

# --- edge cases ----------------------------------------------------------------

@test "check and list read every page of the open issues" {
  rules '*after=I1*|issues-p2.json' '*pullRequests*|repo-p1.json'
  run --separate-stderr "$BOARD" check
  [[ -z "$stderr" ]]
  [[ "$status" -eq 1 ]]
  [[ "$output" == '#11 is open in Done: ask the maintainer why' ]]
  run --separate-stderr "$BOARD" list Done
  [[ -z "$stderr" ]]
  [[ "$status" -eq 0 ]]
  [[ "$output" == 11 ]]
}

@test "list: a column with no issue prints nothing" {
  rules '*pullRequests*|repo-clean.json'
  run --separate-stderr "$BOARD" list Ready
  [[ -z "$stderr" ]]
  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]
}

@test "move: an unknown <from> is refused too" {
  move_rules
  run --separate-stderr "$BOARD" move 27 Doing 'In review'
  [[ "$status" -eq 1 ]]
  [[ -z "$output" ]]
  [[ "$stderr" == 'board.sh: unknown column: Doing (valid: Backlog, Ready, In progress, In review, Done)' ]]
  run ! grep -q updateProjectV2ItemFieldValue "$GH_STUB_LOG"
}

@test "move: an issue on several boards is refused before any lookup of the field" {
  rules '*ProjectV2SingleSelectField*|field.json' '*projectItems*|item-27-two.json'
  run --separate-stderr "$BOARD" move 27 'In progress' 'In review'
  [[ "$status" -eq 1 ]]
  [[ -z "$output" ]]
  [[ "$stderr" == 'board.sh: #27 is on 2 boards (#3, #5): ask the maintainer' ]]
  run ! grep -q ProjectV2SingleSelectField "$GH_STUB_LOG"
}

@test "add-pr: a PR that closes no issue with a card is refused" {
  rules '*closingIssuesReferences*|pr-30-noissue.json'
  run --separate-stderr "$BOARD" add-pr 30
  [[ "$status" -eq 1 ]]
  [[ -z "$output" ]]
  [[ "$stderr" == 'board.sh: PR #30 closes no issue with a card' ]]
  run ! grep -q addProjectV2ItemById "$GH_STUB_LOG"
}

@test "a failed gh call is one line on stderr" {
  rules '*projectItems*|!1 HTTP 401: Bad credentials'
  run --separate-stderr "$BOARD" status 27
  [[ "$status" -eq 1 ]]
  [[ -z "$output" ]]
  [[ "$stderr" == 'board.sh: gh: HTTP 401: Bad credentials' ]]
}

@test "usage errors: wrong arguments exit 2 without calling gh" {
  rules
  for args in "status" "status x" "move 27 Ready" "check now" "list" "add-pr x"; do
    # shellcheck disable=SC2086 # split on purpose: one word per argument
    run --separate-stderr "$BOARD" $args
    [[ "$status" -eq 2 ]]
    [[ -z "$output" ]]
    [[ "$stderr" == *usage* ]]
  done
  [[ ! -s "$GH_STUB_LOG" ]]
}

return 0

# --- Change History -------------------------------------------------------
# | PR     | Summary                                                       |
# |--------|---------------------------------------------------------------|
# | #30    | new: board.sh contract; filteredCount tests moved here (#27)  |
# | #36    | run ! grep -q: 8 assertions now run; reasons (#29)            |
