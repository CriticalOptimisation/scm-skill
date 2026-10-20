#!/usr/bin/env bats
# Structural tests for SKILL.md content (#13, #16, #20, #21, #23, #24, #32).

bats_require_minimum_version 1.5.0

setup() {
  SKILL_MD="$BATS_TEST_DIRNAME/../SKILL.md"
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
  for s in '| hot | under 5 minutes |' '| warm | under 1 hour |' '| cold | 1 hour or more |' 'Warm counts as hot'; do
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

@test "a sync is a Task 5 activity: when main moves in Task 6, Task 6 aborts back to Task 5" {
  run --separate-stderr section 'Conductor and Engineer' "$SKILL_MD"
  [[ -z "$stderr" ]]
  [[ "$output" == *'is a Task 5 activity, concluded by a Task 5 review'* ]]
  [[ "$output" == *'**Task 6 aborts and the issue returns to Task 5.**'* ]]
  [[ "$output" == *'the maintainer approves again'* ]]
  INTEG_MD="$BATS_TEST_DIRNAME/../references/integration.md"
  run --separate-stderr grep -m1 '^- \*\*By\*\*: ' "$INTEG_MD"
  [[ -z "$stderr" ]]
  [[ "$output" == '- **By**: the conductor'* ]]
  grep -qF '**abort Task 6 and return to Task 5**' "$INTEG_MD"
}

# --- Change-history templates (#24) -----------------------------------------
# templates.md is the index of the change-history templates; each language has
# its own references/template-<language>.md, with a Covers: line and its block.
# Installed add-ons may ship more templates, declared in their description.

REFS="$BATS_TEST_DIRNAME/../references"
TEMPLATES_MD="$REFS/templates.md"
TEMPLATE_FILES="shell rst skill-history markdown go javascript yaml sql python config"
INDEX='Change History Section Templates'

@test "templates: each built-in template file exists and has a Covers: line" {
  for t in $TEMPLATE_FILES; do
    run --separate-stderr grep -c '^Covers: ' "$REFS/template-$t.md"
    [[ -z "$stderr" ]]
    [[ "$output" -ge 1 ]]
  done
}

# Prints the fenced code blocks of a file, without their fences.
fenced() {
  awk '/^```/ { on = !on; next } on { print }' "$1"
}

@test "templates: each template file holds a block with its comment prefix" {
  for p in 'shell:# --- Change History' 'yaml:# --- Change History' \
           'python:# --- Change History' 'config:# --- Change History' \
           'go:// --- Change History' 'javascript:// --- Change History' \
           'sql:-- --- Change History' 'markdown:<!--' 'rst:..'; do
    run --separate-stderr fenced "$REFS/template-${p%%:*}.md"
    [[ -z "$stderr" ]]
    [[ "$output" == *"${p#*:}"* ]]
  done
  run --separate-stderr fenced "$REFS/template-markdown.md"
  [[ -z "$stderr" ]]
  [[ "$output" == *'-->'* ]]
}

@test "templates: only the shell template has return 0" {
  run --separate-stderr fenced "$REFS/template-shell.md"
  [[ -z "$stderr" ]]
  [[ "$output" == *'return 0'* ]]
  for t in yaml python config go javascript sql; do
    run --separate-stderr fenced "$REFS/template-$t.md"
    [[ -z "$stderr" ]]
    [[ "$output" != *'return 0'* ]]
  done
}

# Prints the template files named in the rows of the index table, sorted.
indexed_templates() {
  section "$INDEX" "$TEMPLATES_MD" | grep -o '^| `template-[a-z-]*\.md`' |
    grep -o 'template-[a-z-]*\.md' | sort -u
}

@test "templates: the index table and the template files match" {
  run --separate-stderr indexed_templates
  [[ -z "$stderr" ]]
  expected=$(cd "$REFS" && ls template-*.md 2>/dev/null | sort)
  [[ -n "$output" ]]
  [[ "$output" == "$expected" ]]
}

@test "templates: the index states exemptions, declarations and the fallback rule" {
  run --separate-stderr section "$INDEX" "$TEMPLATES_MD"
  [[ -z "$stderr" ]]
  for s in 'Generated files' 'CLAUDE.md' '.github/' 'history.md' \
           'Change-history templates for file types:' \
           'Change-history templates for project:' \
           'template-fallback.md' 'Covers:' 'no comment syntax' \
           'skill-copy.sh use' 'installed' 'available' 'conductor' 'BLOCKED'; do
    [[ "$output" == *"$s"* ]]
  done
}

@test "templates: the index orders the six sources of a template" {
  local f=$TEMPLATES_MD prev=0 n
  for s in '1. **Installed project-specific add-on**' \
           '2. **Other installed add-on**' \
           '3. **Built-in template**' \
           '4. **Project-specific fallback rule**' \
           '5. **Available add-on**' \
           '6. **Built-in fallback rule**'; do
    run --separate-stderr line_of "$s" "$f"
    [[ -z "$stderr" ]]
    n=$output
    [[ -n "$n" ]]
    (( n > prev ))
    prev=$n
  done
}

@test "implementation.md: the change-history step skips exempt files and reads the index" {
  run --separate-stderr grep -m1 'update the change history section' "$REFS/implementation.md"
  [[ -z "$stderr" ]]
  [[ "$output" == *'exempt'* ]]
  [[ "$output" == *'templates.md'* ]]
  [[ "$output" == *'template-'* ]]
}

@test "templates: the index holds no change-history block; each template has one source" {
  run --separate-stderr section "$INDEX" "$TEMPLATES_MD"
  [[ -z "$stderr" ]]
  [[ "$output" != *'```'* ]]
  [[ "$output" != *'--- Change History ---'* ]]
}

@test "templates: each Covers: line names at least one file type" {
  for f in "$REFS"/template-*.md; do
    run --separate-stderr grep -m1 '^Covers: ' "$f"
    [[ -z "$stderr" ]]
    [[ "$output" =~ ^Covers:\ .*[^[:space:]] ]]
    [[ "$output" == *'`'* ]]
  done
}

@test "SKILL.md names templates.md as the index of the template-*.md files" {
  run --separate-stderr grep -m1 '^- `templates.md` — ' "$SKILL_MD"
  [[ -z "$stderr" ]]
  [[ "$output" == *'template-*.md'* ]]
}

@test "integration.md: the history check skips exempt files" {
  run --separate-stderr grep -m1 'change history entries are present' "$REFS/integration.md"
  [[ -z "$stderr" ]]
  [[ "$output" == *'except exempt files'* ]]
}

@test "templates: no reference to a session bootstrap issue or an Add-ons: line" {
  run --separate-stderr grep -il -e 'bootstrap' -e 'Add-ons:' "$TEMPLATES_MD" "$REFS"/template-*.md
  [[ -z "$stderr" ]]
  [[ -z "$output" ]]
  run --separate-stderr section 'Add-ons' "$BATS_TEST_DIRNAME/../README.md"
  [[ -z "$stderr" ]]
  [[ "$output" != *'ootstrap'* ]]
}

@test "README.md Add-ons: an add-on may ship change-history templates" {
  run --separate-stderr section 'Add-ons' "$BATS_TEST_DIRNAME/../README.md"
  [[ -z "$stderr" ]]
  for s in 'Change-history templates for file types:' \
           'Change-history templates for project:' \
           'template-' 'Covers:' 'precedence'; do
    [[ "$output" == *"$s"* ]]
  done
}

# --- Engineer replaced at the end of Task 4 (#32) ---------------------------
# When the maintainer approves a Task 4 deliverable, the conductor stops the
# engineer, whatever the temperature, and a fresh one takes Task 5, primed by
# the handoff. The PR is created when Task 5 is ready to conclude, after the
# last commit to the code base. A return to Task 4 opens the PR with the
# engineer's conclusions; the conductor agrees or escalates.

TDD_MD="$REFS/test-driven-development.md"
IMPL_MD="$REFS/implementation.md"
EXEC_MD="$REFS/implementation-execution.md"

@test "SKILL.md: the engineer is replaced when the maintainer approves a Task 4 deliverable, whatever the temperature" {
  run --separate-stderr section 'Conductor and Engineer' "$SKILL_MD"
  [[ -z "$stderr" ]]
  [[ "$output" == *'**End of Task 4.**'* ]]
  [[ "$output" == *'whatever the temperature'* ]]
  run --separate-stderr grep -m1 '^\*\*Stopping an engineer\*\*' "$SKILL_MD"
  [[ -z "$stderr" ]]
  [[ "$output" == *'in three cases'* ]]
  [[ "$output" == *'approves its Task 4 deliverable'* ]]
}

@test "SKILL.md Tasks 4 and 5: the handoff, the stop, the fresh engineer, the PR at the end of Task 5" {
  run --separate-stderr grep -m1 '^4\. \*\*Test Driven Development\*\*' "$SKILL_MD"
  [[ -z "$stderr" ]]
  [[ "$output" == *'handoff'* ]]
  [[ "$output" == *'stops the engineer'* ]]
  run --separate-stderr grep -m1 '^5\. \*\*Implementation\*\*' "$SKILL_MD"
  [[ -z "$stderr" ]]
  [[ "$output" == *'fresh engineer'* ]]
  [[ "$output" == *'after the last commit to the code base'* ]]
  [[ "$output" == *'`REGRESS-TO-TASK-4`'* ]]
  [[ "$output" != *'Ask permission'* ]]
}

@test "test-driven-development.md has a Handoff step with its seven items" {
  run --separate-stderr section 'Handoff' "$TDD_MD"
  [[ -z "$stderr" ]]
  [[ "$output" == '## Handoff'* ]]
  for s in '**Decisions and rulings**' '**Internal structures**' '**Departures from the plan**' \
           '**Test commands**' '**Failure record**' '**What Task 5 still has to do**' \
           '**Patches of the questioned update**' '<details>' 'restates it in full' 'never replaces'; do
    [[ "$output" == *"$s"* ]]
  done
  handoff=$(line_of '## Handoff' "$TDD_MD")
  prelim=$(line_of '## Preliminary Tests Definition' "$TDD_MD")
  [[ -n "$handoff" && -n "$prelim" ]]
  (( prelim < handoff ))
}

@test "implementation.md: Start of Task 5 is the first step and opens no PR" {
  run --separate-stderr grep -m1 '^## ' "$IMPL_MD"
  [[ -z "$stderr" ]]
  [[ "$output" == '## Start of Task 5' ]]
  run --separate-stderr section 'Start of Task 5' "$IMPL_MD"
  [[ -z "$stderr" ]]
  [[ "$output" == *'No PR is opened here'* ]]
  [[ "$output" != *'gh pr create'* ]]
}

@test "implementation.md Start of Task 5: the reading list in order, process from <skill>, change from the diff" {
  run --separate-stderr section 'Start of Task 5' "$IMPL_MD"
  [[ -z "$stderr" ]]
  [[ "$output" == *'git -C <worktree> diff origin/main...HEAD'* ]]
  [[ "$output" == *'from `<skill>`'* ]]
  local prev=0 n
  for s in '**The process**' '**The change**' '**The thread**' '**The preliminary tests**' '**The state of the branch**'; do
    n=$(line_of "$s" "$IMPL_MD")
    [[ -n "$n" ]]
    (( n > prev ))
    prev=$n
  done
}

@test "scm-engineer: Task 4 is the last task; the Task 5 reading list; back to Task 4" {
  grep -qF '**Task 4 is your last task.**' "$AGENT_MD"
  grep -qF '**Back to Task 4** means' "$AGENT_MD"
  local prev=0 n
  for s in '**The process**' '**The change**' '**The thread**' '**The preliminary tests**' '**The state of the branch**'; do
    n=$(line_of "$s" "$AGENT_MD")
    [[ -n "$n" ]]
    (( n > prev ))
    prev=$n
  done
  run --separate-stderr frontmatter "$AGENT_MD" description
  [[ -z "$stderr" ]]
  [[ "$output" == *'approves its Task 4 deliverable'* ]]
}

@test "implementation.md Return to Task 4: last commit, PR with the conclusions, required parts, agree or escalate" {
  run --separate-stderr section 'Return to Task 4' "$IMPL_MD"
  [[ -z "$stderr" ]]
  [[ "$output" == '## Return to Task 4'* ]]
  for s in 'last (unsuccessful) commit of Task 5' 'gh pr create --draft' 'thread.sh post <PR>' \
           'No change-history commit and no auto-merge' \
           '**Wrong tests**' '**False assumption**' '**Documentation**' '**Correction**' '**New placeholders**' \
           '**agrees automatically**' '**escalates**' 'never refuses' 'second return to Task 4' \
           'Task 4 gate is unchanged' 'cache-temperature'; do
    [[ "$output" == *"$s"* ]]
  done
}

@test "SKILL.md: the conductor agrees to or escalates a return to Task 4, and orders back to Task 4" {
  run --separate-stderr grep -m1 '^- `REGRESS-TO-TASK-4 <url>`' "$SKILL_MD"
  [[ -z "$stderr" ]]
  [[ "$output" == *'agrees or escalates'* ]]
  run --separate-stderr section 'Conductor and Engineer' "$SKILL_MD"
  [[ -z "$stderr" ]]
  [[ "$output" == *'*back to Task 4*'* ]]
  run --separate-stderr grep -m1 '^\*\*Escalation\.\*\*' "$SKILL_MD"
  [[ -z "$stderr" ]]
  [[ "$output" == *'never refuses one'* ]]
  [[ "$output" != *'or a return to Task 4'* ]]
}

@test "scm-engineer: REGRESS-TO-TASK-4 is valid only after the conclusions are posted on the PR" {
  run --separate-stderr grep -m1 '^- `REGRESS-TO-TASK-4 <url>`' "$AGENT_MD"
  [[ -z "$stderr" ]]
  [[ "$output" == *'**only if**'* ]]
  [[ "$output" == *'on the PR'* ]]
}

@test "a return to Task 4 deletes no test and wipes the previous placeholders" {
  for s in '**On a return to Task 4**' 'never deletes a test' 'wipes the placeholders'; do
    grep -qF -- "$s" "$TDD_MD"
  done
  run --separate-stderr section 'Edge-cases Tests Expansion' "$IMPL_MD"
  [[ -z "$stderr" ]]
  [[ "$output" == *'*On a return to Task 4*'* ]]
}

@test "no process file asks the maintainer's leave to return to Task 4" {
  run --separate-stderr grep -rnE 'Ask permission to return to Task 4|after human approval' "$SKILL_MD" "$BATS_TEST_DIRNAME/../agents" "$REFS"
  [[ -z "$stderr" ]]
  [[ -z "$output" ]]
}

@test "the PR opens when Task 5 is ready to conclude, after the last commit to the code base" {
  run --separate-stderr section 'Prepare for Review' "$IMPL_MD"
  [[ -z "$stderr" ]]
  [[ "$output" == *'after the last commit to the code base'* ]]
  [[ "$output" == *'gh pr ready <PR>'* ]]
  run --separate-stderr section 'Code Review Request' "$EXEC_MD"
  [[ -z "$stderr" ]]
  [[ "$output" == *'after the last commit to the code base'* ]]
  run --separate-stderr section 'Kanban Board' "$SKILL_MD"
  [[ -z "$stderr" ]]
  [[ "$output" == *'after the last commit to the code base'* ]]
  [[ "$output" == *'**a return to Task 4**'* ]]
}

@test "SKILL.md brief: the Task 5 subject index points at the handoff" {
  run --separate-stderr section 'Conductor and Engineer' "$SKILL_MD"
  [[ -z "$stderr" ]]
  [[ "$output" == *'points at the handoff'* ]]
}

# Edge cases (#32, Task 5).

@test "implementation.md: Start of Task 5 names none of the PR steps the ordering test finds by first match" {
  run --separate-stderr section 'Start of Task 5' "$IMPL_MD"
  [[ -z "$stderr" ]]
  [[ -n "$output" ]]
  for s in 'Open the PR' 'change history' 'gh pr merge --auto --squash' 'Assign the **maintainers team**'; do
    [[ "$output" != *"$s"* ]]
  done
}

@test "implementation.md: Return to Task 4 is the last step, after Prepare for Review" {
  run --separate-stderr grep '^## ' "$IMPL_MD"
  [[ -z "$stderr" ]]
  [[ "${lines[-1]}" == '## Return to Task 4' ]]
  [[ "${lines[-2]}" == '## Prepare for Review' ]]
}

@test "implementation.md Return to Task 4: the body carries Closes #N, the conclusions go in a comment, no review is requested" {
  run --separate-stderr section 'Return to Task 4' "$IMPL_MD"
  [[ -z "$stderr" ]]
  for s in 'as a draft' '`Closes #N`' 'first comment of the PR' 'When the PR is open already' \
           'requests no review on this PR' 'review it at will' 'dismisses it'; do
    [[ "$output" == *"$s"* ]]
  done
  [[ "$output" != *'gh pr merge --auto'* ]]
}

@test "Prepare for Review: a PR opened by a return to Task 4 is marked ready, not opened again" {
  run --separate-stderr section 'Prepare for Review' "$IMPL_MD"
  [[ -z "$stderr" ]]
  for s in 'open no other' 'gh pr ready <PR>' 'gh pr edit <PR> --body-file -' 'stay in their comment'; do
    [[ "$output" == *"$s"* ]]
  done
  run --separate-stderr section 'Code Review Request' "$EXEC_MD"
  [[ -z "$stderr" ]]
  [[ "$output" == *'as a draft'* ]]
  [[ "$output" == *'gh pr ready <PR>'* ]]
}

@test "SKILL.md Kanban Task 5 row: the failure PR is a draft; auto-merge and review request for review only" {
  run --separate-stderr grep -m1 '^  | 5\. Implementation |' "$SKILL_MD"
  [[ -z "$stderr" ]]
  [[ "$output" == *'as a draft, with its conclusions'* ]]
  [[ "$output" == *'for review only'* ]]
  [[ "$output" == *'stops the Task 4 engineer'* ]]
}

# --- Change History -------------------------------------------------------
# | PR     | Summary                                                       |
# |--------|---------------------------------------------------------------|
# | #14    | board query uses filteredCount (structural tests)             |
# | #18    | Prepare for Review order: PR, history, auto-merge, review (#16)|
# | #22    | By line on every step; agents exist; Conductor section (#20)  |
# | #25    | name:, resolved <skill>; install by skill-copy.sh; no agents.sh (#23)|
# | #28    | update at session start: SKILL.md and README.md text (#26)    |
# | #30    | engineer lifetime, brief, posting, board.sh, no bootstrap (#27)|
# | #30    | a sync is a Task 5 activity; Task 6 aborts when main moves (#27)|
# | #31    | change-history templates per language; add-on templates (#24)|
# | #34    | engineer stops at end of Task 4; Start of/Return to Task 4 (#32)|
