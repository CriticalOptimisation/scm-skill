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

# --- Conductor and engineer (#20) -----------------------------------------
# Every step of the task files says who does it on a "- **By**:" line. On that
# line, backquotes hold agent names only, and each must have agents/<name>.md.

TASK_FILES="shared-issue-understanding.md implementation-planning.md
  test-driven-development.md implementation.md implementation-execution.md
  integration.md"

# Prints "file: heading" for each "## " step that has no "- **By**:" line
# before the next heading.
steps_without_by() {
  local f
  for f in $TASK_FILES; do
    awk -v f="$f" '
      /^## / { if (h != "" && !by) print f ": " h; h = substr($0, 4); by = 0; next }
      /^- \*\*By\*\*: / { by = 1 }
      END { if (h != "" && !by) print f ": " h }
    ' "$BATS_TEST_DIRNAME/../references/$f"
  done
}

@test "every step of the task files has a By line" {
  run --separate-stderr steps_without_by
  [[ -z "$stderr" ]]
  [[ -z "$output" ]]
}

# Prints each agent named on a By line that has no definition in agents/.
unknown_agents() {
  local name
  grep -h '^- \*\*By\*\*: ' "$BATS_TEST_DIRNAME"/../references/*.md |
    grep -o '`[^`]*`' | tr -d '`' | sort -u |
    while read -r name; do
      [[ -f $BATS_TEST_DIRNAME/../agents/$name.md ]] || echo "$name"
    done
}

@test "every agent named on a By line has a definition in agents/" {
  run --separate-stderr unknown_agents
  [[ -z "$stderr" ]]
  [[ -z "$output" ]]
}

@test "every By line names the conductor or an agent" {
  run --separate-stderr grep -h '^- \*\*By\*\*: ' "$BATS_TEST_DIRNAME"/../references/*.md
  [[ -z "$stderr" ]]
  [[ -n "$output" ]]
  while IFS= read -r line; do
    [[ $line == *conductor* || $line == *'`'* ]]
  done <<< "$output"
}

# Prints the value of a frontmatter field of an agent definition.
frontmatter() {
  awk -v k="$2" '
    NR == 1 && $0 == "---" { fm = 1; next }
    fm && $0 == "---" { exit }
    fm && index($0, k ": ") == 1 { print substr($0, length(k) + 3) }
  ' "$1"
}

@test "agents/ ships scm-engineer, and each definition has its name and a model" {
  [[ -f $BATS_TEST_DIRNAME/../agents/scm-engineer.md ]]
  for f in "$BATS_TEST_DIRNAME"/../agents/*.md; do
    run --separate-stderr frontmatter "$f" name
    [[ -z "$stderr" ]]
    [[ "$output" == "$(basename "$f" .md)" ]]
    run --separate-stderr frontmatter "$f" model
    [[ -z "$stderr" ]]
    [[ -n "$output" ]]
  done
}

@test "SKILL.md has the Conductor and Engineer section with the four status lines" {
  run --separate-stderr grep -c '^## Conductor and Engineer$' "$SKILL_MD"
  [[ -z "$stderr" ]]
  [[ "$output" -eq 1 ]]
  for s in 'AWAITING-APPROVAL <url>' 'REGRESS-TO-TASK-4 <url>' 'BLOCKED <url>' 'DONE'; do
    grep -qF "\`$s\`" "$SKILL_MD"
  done
}

# --- Change History -------------------------------------------------------
# | PR     | Summary                                                       |
# |--------|---------------------------------------------------------------|
# | #14    | board query uses filteredCount (structural tests)             |
# | #18    | Prepare for Review order: PR, history, auto-merge, review (#16)|
