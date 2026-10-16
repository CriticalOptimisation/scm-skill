#!/usr/bin/env bats
# Structural tests for SKILL.md content (#13, #16, #20, #21, #23).

bats_require_minimum_version 1.5.0

setup() {
  SKILL_MD="$BATS_TEST_DIRNAME/../SKILL.md"
}

# REVIEW PLACEHOLDER (#27): the board query left SKILL.md for tools/board.sh.
# board query uses filteredCount for the REOPENED_EVENT filter -> board.bats: board.sh query uses filteredCount for the REOPENED_EVENT filter
# board query does not use totalCount for the REOPENED_EVENT filter -> board.bats: board.sh query does not use totalCount for the REOPENED_EVENT filter
# @test "board query uses filteredCount for the REOPENED_EVENT filter" {
#   # totalCount ignores itemTypes (GitHub API quirk): every open PR appears
#   # reopened. filteredCount counts only matching events.
#   run --separate-stderr grep -cF 'filteredCount' "$SKILL_MD"
#   [[ -z "$stderr" ]]
#   [[ "$output" -ge 1 ]]
# }
#
# @test "board query does not use totalCount for the REOPENED_EVENT filter" {
#   run --separate-stderr grep -cF 'timelineItems(itemTypes:[REOPENED_EVENT]){totalCount}' "$SKILL_MD"
#   [[ -z "$stderr" ]]
#   [[ "$output" -eq 0 ]]
# }

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

# --- Skill name and resolved base directory (#21) ---------------------------
# The skill's name comes from name:, not from the link. Claude Code announces
# the base directory as the link path, which may move to another copy while a
# session runs: <skill> is resolved once, and the resolved path is handed on.

# Prints the "## " section of a file whose heading starts with $1, up to the
# next "## " heading.
section() {
  awk -v h="## $1" '
    index($0, h) == 1 { on = 1; print; next }
    on && /^## / { exit }
    on { print }
  ' "$2"
}

@test "SKILL.md frontmatter names the skill scm-skill" {
  run --separate-stderr frontmatter "$SKILL_MD" name
  [[ -z "$stderr" ]]
  [[ "$output" == scm-skill ]]
}

@test "SKILL.md Paths: resolve <skill> once with readlink -f, use only the resolved path" {
  run --separate-stderr section Paths "$SKILL_MD"
  [[ -z "$stderr" ]]
  [[ "$output" == *'readlink -f'* ]]
  [[ "$output" == *'only the resolved path'* ]]
}

@test "SKILL.md: an order passes the resolved <skill>" {
  run --separate-stderr grep -m1 '^\*\*An order\*\* gives' "$SKILL_MD"
  [[ -z "$stderr" ]]
  [[ "$output" == *"the skill's resolved directory \`<skill>\`"* ]]
}

@test "scm-engineer: an order gives the resolved <skill>, never resolved again" {
  run --separate-stderr grep -m1 '^An order gives:' "$BATS_TEST_DIRNAME/../agents/scm-engineer.md"
  [[ -z "$stderr" ]]
  [[ "$output" == *"the skill's resolved directory \`<skill>\`"* ]]
  [[ "$output" == *'never resolve the link again'* ]]
}

# --- Installation by skill-copy.sh (#23) -------------------------------------
# A project installs the skill as a fixed copy with tools/skill-copy.sh, which
# also links the agents; agents.sh is gone. The two README tests of #21's first
# scope (an ln -s named scm-skill; a Developing the skill section) never reached
# main: they are replaced by the tests below.

README_MD="$BATS_TEST_DIRNAME/../README.md"

@test "README.md Using it in a project installs with skill-copy.sh use, with no ln -s" {
  run --separate-stderr section 'Using it in a project' "$README_MD"
  [[ -z "$stderr" ]]
  [[ "$output" == '## Using it in a project'* ]]
  [[ "$output" == *'tools/skill-copy.sh use '* ]]
  [[ "$output" != *'ln -s'* ]]
}

@test "README.md has no Developing the skill section" {
  run --separate-stderr grep -c '^## Developing the skill' "$README_MD"
  [[ -z "$stderr" ]]
  [[ "$output" -eq 0 ]]
}

@test "README.md has a section on the hook: its file, its arguments, --frozen and the trust note" {
  run --separate-stderr section 'The skill-copy hook' "$README_MD"
  [[ -z "$stderr" ]]
  [[ "$output" == '## The skill-copy hook'* ]]
  [[ "$output" == *'tools/skill-copy-hook.sh'* ]]
  [[ "$output" == *'skill_copy_link'* ]]
  [[ "$output" == *'--frozen'* ]]
  [[ "$output" == *"with your rights"* ]]
}

@test "README.md has sections on add-ons and on requirements" {
  run --separate-stderr section 'Add-ons' "$README_MD"
  [[ -z "$stderr" ]]
  [[ "$output" == '## Add-ons'* ]]
  run --separate-stderr section 'Requirements' "$README_MD"
  [[ -z "$stderr" ]]
  [[ "$output" == '## Requirements'* ]]
  for r in flock 'mv -T' procps 'bats'; do
    [[ "$output" == *"$r"* ]]
  done
}

@test "SKILL.md: the engineer is installed by skill-copy.sh" {
  run --separate-stderr grep -m1 '^- \*\*The engineer\*\*' "$SKILL_MD"
  [[ -z "$stderr" ]]
  [[ "$output" == *'installed by `<skill>/tools/skill-copy.sh use`'* ]]
}

# Prints "file:line" for each mention of agents.sh in a tracked file, except
# history.md, which records the past, and comment lines of the bats files,
# where REVIEW PLACEHOLDER keeps the old tests.
agents_sh_mentions() {
  local root="$BATS_TEST_DIRNAME/.."
  git -C "$root" ls-files -z | while IFS= read -r -d '' f; do
    [[ $f == history.md ]] && continue
    if [[ $f == *.bats ]]; then
      grep -nE 'agents[.]sh' "$root/$f" | grep -vE '^[0-9]+:[[:space:]]*#' | sed "s|^|$f:|"
    else
      grep -nE 'agents[.]sh' "$root/$f" | sed "s|^|$f:|"
    fi
  done
  return 0
}

@test "no tracked file mentions the removed agents script, apart from history.md and bats comments" {
  run --separate-stderr agents_sh_mentions
  [[ -z "$stderr" ]]
  [[ -z "$output" ]]
}

# --- Updating the skill at session start (#26) -----------------------------
# The conductor runs skill-copy.sh update once, before the engineer starts; on
# updated, it resolves <skill> a second time and re-reads SKILL.md. The update
# never blocks the work.

@test "SKILL.md Conductor and Engineer: update at session start, before the engineer, then re-read SKILL.md" {
  run --separate-stderr section 'Conductor and Engineer' "$SKILL_MD"
  [[ -z "$stderr" ]]
  [[ "$output" == *'**Updating the skill at session start.**'* ]]
  [[ "$output" == *'`<skill>/tools/skill-copy.sh update <skill>`'* ]]
  [[ "$output" == *'re-reads `SKILL.md`'* ]]
  [[ "$output" == *'never blocks the work'* ]]
  up=$(line_of '**Updating the skill at session start.**' "$SKILL_MD")
  start=$(line_of '**Starting the engineer.**' "$SKILL_MD")
  [[ -n "$up" && -n "$start" ]]
  (( up < start ))
}

@test "SKILL.md Paths: the conductor resolves <skill> a second time after its update" {
  run --separate-stderr section Paths "$SKILL_MD"
  [[ -z "$stderr" ]]
  [[ "$output" == *'*Updating the skill at session start*'* ]]
  [[ "$output" == *'a second time'* ]]
}

@test "README.md Using it in a project documents update and its three lines" {
  run --separate-stderr section 'Using it in a project' "$README_MD"
  [[ -z "$stderr" ]]
  [[ "$output" == *'**Updating.**'* ]]
  [[ "$output" == *'skill-copy.sh update <copy>'* ]]
  for l in '`updated <old sha12> <new sha12> <new copy dir>`' '`current <sha12>`' '`kept <sha12> ahead`' '`kept <sha12> diverged`' '<copy>.frozen'; do
    [[ "$output" == *"$l"* ]]
  done
}

# --- Engineer lifetime, briefs and shell tools (#27) ------------------------
# Engineers are titled and signed, kept or replaced by cache temperature, and
# primed with a brief; they post through thread.sh with a here-doc; the
# conductor passes comment ids, checks the sync with main, moves cards with
# board.sh. No raw gh sequence the scripts cover is left in the process.

AGENT_MD="$BATS_TEST_DIRNAME/../agents/scm-engineer.md"
TOOLS_MD="$BATS_TEST_DIRNAME/../references/shell-tools.md"

@test "SKILL.md Conductor and Engineer: titled engineers, signature, stop" {
  run --separate-stderr section 'Conductor and Engineer' "$SKILL_MD"
  [[ -z "$stderr" ]]
  [[ "$output" == *'`issue #N engineer #n`'* ]]
  [[ "$output" == *'`— issue #N engineer #n`'* ]]
  [[ "$output" == *'`TaskStop`'* ]]
  [[ "$output" == *'`archive session "issue #N engineer #n"`'* ]]
}

@test "SKILL.md Conductor and Engineer: hot, warm, cold decide whether the engineer is kept" {
  run --separate-stderr section 'Conductor and Engineer' "$SKILL_MD"
  [[ -z "$stderr" ]]
  [[ "$output" == *'**Cache temperature**'* ]]
  for s in '| hot | under 5 minutes |' '| warm | under 1 hour |' '| cold | 1 hour or more |' 'warm counts as cold'; do
    [[ "$output" == *"$s"* ]]
  done
  [[ "$output" != *'new engineer per PR-review iteration'* ]]
}

@test "SKILL.md Conductor and Engineer: the brief, with the subject index and the safe side" {
  run --separate-stderr section 'Conductor and Engineer' "$SKILL_MD"
  [[ -z "$stderr" ]]
  [[ "$output" == *'**The brief**'* ]]
  [[ "$output" == *'**table of contents**'* ]]
  [[ "$output" == *'thread.sh index <N>'* ]]
  [[ "$output" == *'**subject index**'* ]]
  [[ "$output" == *'**err on the safe side**'* ]]
}

@test "SKILL.md: an order passes the id of the maintainer's comment, never the comment" {
  run --separate-stderr grep -m1 '^\*\*An order\*\* gives' "$SKILL_MD"
  [[ -z "$stderr" ]]
  [[ "$output" == *"the id of the maintainer's comment"* ]]
  [[ "$output" == *'thread.sh get'* ]]
}

@test "SKILL.md: the engineer posts through thread.sh with a here-doc; sync with main" {
  run --separate-stderr section 'Conductor and Engineer' "$SKILL_MD"
  [[ -z "$stderr" ]]
  [[ "$output" == *'**Posting.**'* ]]
  [[ "$output" == *'`thread.sh post <N>`'* ]]
  [[ "$output" == *'here-doc'* ]]
  [[ "$output" == *'**Sync with `main`.**'* ]]
  [[ "$output" == *'rev-list --count HEAD..origin/main'* ]]
  [[ "$output" == *'*sync*'* ]]
}

@test "scm-engineer: its name, the comment by id, the brief, sync, here-doc posting" {
  run --separate-stderr grep -m1 '^An order gives:' "$AGENT_MD"
  [[ -z "$stderr" ]]
  [[ "$output" == *'your name (`issue #N engineer #n`)'* ]]
  [[ "$output" == *"the id of the maintainer's comment"* ]]
  for s in 'thread.sh get' '**brief**' '**Err on the safe side**' '**Sync** means' "thread.sh post <N> <<'SCM_BODY'" 'thread.sh reply <id>' '`— issue #N engineer #n`'; do
    grep -qF -- "$s" "$AGENT_MD"
  done
  # The engineer never moves a card.
  run --separate-stderr section 'What you never do' "$AGENT_MD"
  [[ -z "$stderr" ]]
  [[ "$output" == *'moving cards on the board'* ]]
}

@test "SKILL.md, agents and references: nothing forwarded verbatim, no bootstrap issue" {
  run --separate-stderr grep -rniE 'verbatim|bootstrap issue|session bootstrap' "$SKILL_MD" "$BATS_TEST_DIRNAME/../agents" "$BATS_TEST_DIRNAME/../references"
  [[ -z "$stderr" ]]
  [[ -z "$output" ]]
}

@test "SKILL.md, agents and references: no raw gh sequence the scripts cover" {
  run --separate-stderr grep -rnE 'gh api graphql|gh project item-|gh project field-list' "$SKILL_MD" "$BATS_TEST_DIRNAME/../agents" "$BATS_TEST_DIRNAME/../references"
  [[ -z "$stderr" ]]
  [[ -z "$output" ]]
}

@test "references/pr-threads.sh is absorbed into thread.sh and removed" {
  [[ -f "$BATS_TEST_DIRNAME/thread.sh" ]]
  [[ ! -e "$BATS_TEST_DIRNAME/../references/pr-threads.sh" ]]
}

@test "SKILL.md Kanban Board: board.sh commands, move with from and to" {
  run --separate-stderr section 'Kanban Board' "$SKILL_MD"
  [[ -z "$stderr" ]]
  for s in 'board.sh status <N>' 'board.sh move <N> <from> <to>' 'board.sh check' 'board.sh list <column>' 'board.sh add-pr <PR>' 'The engineer never moves a card.'; do
    [[ "$output" == *"$s"* ]]
  done
}

@test "references/shell-tools.md documents every subcommand of thread.sh and board.sh" {
  [[ -f "$TOOLS_MD" ]]
  for s in '`index <N> -o <file>`' '`read <N> <range> -o <file>`' '`last <N> -o <file>`' '`get <id> -o <file>`' '`post <N>`' '`reply <id>`' \
           '`status <N>`' '`move <N> <from> <to>`' '`check`' '`list <column>`' '`add-pr <PR>`' '**The overflow file.**' '**Nothing is truncated.**'; do
    grep -qF -- "$s" "$TOOLS_MD"
  done
}

@test "a new issue is a problem statement; a solution in it is a hint" {
  run --separate-stderr grep -m1 '^1\. \*\*Meta-task path\*\*' "$SKILL_MD"
  [[ -z "$stderr" ]]
  [[ "$output" == *'**A new issue is a problem statement**'* ]]
  [[ "$output" == *'is a hint'* ]]
  grep -qF 'is a hint' "$BATS_TEST_DIRNAME/../references/shared-issue-understanding.md"
}

@test "README.md requirements name jq and gh" {
  run --separate-stderr section 'Requirements' "$README_MD"
  [[ -z "$stderr" ]]
  [[ "$output" == *'`jq`'* ]]
  [[ "$output" == *'`gh`'* ]]
}

# --- Change History -------------------------------------------------------
# | PR     | Summary                                                       |
# |--------|---------------------------------------------------------------|
# | #14    | board query uses filteredCount (structural tests)             |
# | #18    | Prepare for Review order: PR, history, auto-merge, review (#16)|
# | #22    | By line on every step; agents exist; Conductor section (#20)  |
# | #25    | name:, resolved <skill>; install by skill-copy.sh; no agents.sh (#23)|
# | #28    | update at session start: SKILL.md and README.md text (#26)    |
