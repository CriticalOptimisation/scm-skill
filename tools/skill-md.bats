#!/usr/bin/env bats
# Structural tests for SKILL.md content (#13, #16).

bats_require_minimum_version 1.5.0

setup() {
  SKILL_MD="$BATS_TEST_DIRNAME/../SKILL.md"
}

@test "board query uses filteredCount for the REOPENED_EVENT filter" {
  # totalCount ignores itemTypes (GitHub API quirk): every open PR appears
  # reopened. filteredCount counts only matching events.
  run --separate-stderr grep -cF 'filteredCount' "$SKILL_MD"
  [[ -z "$stderr" ]]
  [[ "$output" -ge 1 ]]
}

@test "board query does not use totalCount for the REOPENED_EVENT filter" {
  run --separate-stderr grep -cF 'timelineItems(itemTypes:[REOPENED_EVENT]){totalCount}' "$SKILL_MD"
  [[ -z "$stderr" ]]
  [[ "$output" -eq 0 ]]
}

# --- Prepare for Review order (#16) -----------------------------------------
# The change history needs the PR number, so it is committed after the PR
# opens, and before auto-merge and the review request.

# Prints the first line number of a fixed string in a file.
line_of() {
  grep -nF -m1 "$1" "$2" | cut -d: -f1
}

@test "implementation.md: open PR, then change history, then auto-merge, then review request" {
  IMPL_MD="$BATS_TEST_DIRNAME/../references/implementation.md"
  run --separate-stderr line_of 'Open the PR' "$IMPL_MD"
  [[ -z "$stderr" ]]
  open=$output
  run --separate-stderr line_of 'change history' "$IMPL_MD"
  [[ -z "$stderr" ]]
  hist=$output
  run --separate-stderr line_of 'gh pr merge --auto --squash' "$IMPL_MD"
  [[ -z "$stderr" ]]
  auto=$output
  run --separate-stderr line_of 'Assign the **maintainers team**' "$IMPL_MD"
  [[ -z "$stderr" ]]
  review=$output
  [[ -n "$open" && -n "$hist" && -n "$auto" && -n "$review" ]]
  (( open < hist && hist < auto && auto < review ))
}

@test "SKILL.md Task 5: PR, then change-history commit, then auto-merge" {
  run --separate-stderr grep -m1 '^5\. \*\*Implementation\*\*' "$SKILL_MD"
  [[ -z "$stderr" ]]
  [[ "$output" =~ create\ the\ PR.*change-history\ commit.*auto-merge ]]
}


# --- Change History -------------------------------------------------------
# | PR     | Summary                                                       |
# |--------|---------------------------------------------------------------|
# | #14    | board query uses filteredCount (structural tests)             |
