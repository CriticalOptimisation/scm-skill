#!/usr/bin/env bats
# Structural tests for SKILL.md content (#13).

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
