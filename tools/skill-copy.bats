#!/usr/bin/env bats
# Contract of tools/skill-copy.sh (#23).
#
# Each test sets up a throwaway skill repository and a throwaway project, each
# with its bare origin, side by side in $WORK: nothing touches the real
# repositories, the real ~/.claude or the claude processes of the machine.
# Session start times and the clock are faked with SKILL_COPY_STARTS and
# SKILL_COPY_NOW.
#
# The skill has three commits, A, B and C; at each, SKILL.md is named
# demo-skill and agents/probe.md holds the commit's letter.

bats_require_minimum_version 1.5.0

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/skill-copy.sh"
  TMP="$(realpath "$(mktemp -d)")"
  REMOTES="$TMP/remotes"
  WORK="$TMP/work"
  SKILL="$WORK/demo-skill"
  PROJ="$WORK/proj"
  mkdir -p "$REMOTES" "$WORK"

  git init -q --bare -b main "$REMOTES/demo-skill.git"
  repo "$SKILL"
  printf '/.worktrees/\n' > .gitignore
  mkdir agents
  for x in A B C; do
    skill_md demo-skill "$x"
    echo "$x" > agents/probe.md
    git add .gitignore SKILL.md agents
    git commit -qm "$x"
    printf -v "$x" '%s' "$(sha12 HEAD)"
  done
  git remote add origin "$REMOTES/demo-skill.git"
  git push -q -u origin main

  new_project "$PROJ"
  # A session started at 0 keeps every copy, unless a test says otherwise.
  export SKILL_COPY_STARTS=0
  export SKILL_COPY_NOW=1000
}

teardown() {
  rm -rf "$TMP"
}

# repo <dir>: a new repository with a test identity; leaves the shell in it.
repo() {
  git init -q -b main "$1"
  cd "$1"
  git config user.email test@example.invalid
  git config user.name test
}

# new_project <dir>: a project with one commit and a bare origin; leaves the
# shell in it.
new_project() {
  local bare
  bare="$REMOTES/$(basename "$1").git"
  git init -q --bare -b main "$bare"
  repo "$1"
  printf '/.worktrees/\n' > .gitignore
  echo project > README.md
  git add .gitignore README.md
  git commit -qm init
  git remote add origin "$bare"
  git push -q -u origin main
}

# skill_md <name> <body>: writes a SKILL.md; an empty name means no name: field.
skill_md() {
  {
    echo ---
    [ -n "$1" ] && echo "name: $1"
    echo "description: test skill"
    echo ---
    echo "$2"
  } > SKILL.md
}

sha12() {
  git rev-parse "$1" | cut -c1-12
}

# commit_hook <body>: commits tools/skill-copy-hook.sh (not executable) in the
# skill, with /settings.json ignored, and sets H to the new commit.
commit_hook() {
  (
    cd "$SKILL"
    mkdir -p tools
    printf '%s\n' "$1" > tools/skill-copy-hook.sh
    printf '/.worktrees/\n/settings.json\n' > .gitignore
    git add tools .gitignore
    git commit -qm hook
  )
  H=$(git -C "$SKILL" rev-parse HEAD | cut -c1-12)
}

# Everything a refused command must leave unchanged, in the project and in the
# skill repository: their files, their excludes and their worktree lists.
snapshot() {
  local d
  for d in "$PROJ" "$SKILL"; do
    echo "== $d"
    (cd "$d" && find . -path ./.git -prune -o -print | sort)
    cat "$d/.git/info/exclude" 2>/dev/null
    git -C "$d" worktree list --porcelain
  done
}

log() {
  cat "$SKILL/.worktrees/skill-copies.log"
}

# --- general contract ------------------------------------------------------
#
# Exit codes: 0 success; 1 failure; 2 usage; 3 refused for safety. Refusals
# are tested on code 3, so that a missing script — which exits with 127 — can
# never pass them.

# REVIEW PLACEHOLDER: the script exists and is executable -> the script exists and is executable
# (tools/agents.bats, removed with tools/agents.*; converted in place.)
@test "the script exists and is executable" {
  [ -x "$SCRIPT" ]
}

# --- use -------------------------------------------------------------------

# REVIEW PLACEHOLDER: link keeps the project clean: the link is excluded from git -> use creates a detached copy in the skill repository, links it relatively, excludes the link and logs the move
# @test "link keeps the project clean: the link is excluded from git" {
#   "$SCRIPT" link
#   grep -qxF '/.claude/agents/probe.md' .git/info/exclude
#   [ -z "$(git status --porcelain)" ]
# }
@test "use creates a detached copy in the skill repository, links it relatively, excludes the link and logs the move" {
  run --separate-stderr "$SCRIPT" use "$SKILL" "$A"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: demo-skill -> skill-$A ($A)"* ]]
  [ -d "$SKILL/.worktrees/skill-$A" ]
  [ "$(git -C "$SKILL/.worktrees/skill-$A" rev-parse HEAD | cut -c1-12)" = "$A" ]
  [ -z "$(git -C "$SKILL/.worktrees/skill-$A" branch --show-current)" ]
  [ -L .claude/skills/demo-skill ]
  [ "$(readlink .claude/skills/demo-skill)" = "../../../demo-skill/.worktrees/skill-$A" ]
  [ "$(readlink -f .claude/skills/demo-skill)" = "$SKILL/.worktrees/skill-$A" ]
  grep -qxF /.claude/skills/demo-skill .git/info/exclude
  [ "$(log)" = "1000 skill-$A $PROJ" ]
  [ -z "$(git status --porcelain)" ]
  [ -z "$(git -C "$SKILL" status --porcelain)" ]
}

# REVIEW PLACEHOLDER: link is idempotent -> use run twice changes nothing: files, excludes, worktrees and log
# @test "link is idempotent" {
#   "$SCRIPT" link
#   run --separate-stderr "$SCRIPT" link
#   [ "$status" -eq 0 ]
#   [ -z "$stderr" ]
#   [ "$(grep -cxF '/.claude/agents/probe.md' .git/info/exclude)" -eq 1 ]
#   [ "$(readlink .claude/agents/probe.md)" = "$(realpath "$SKILL/agents/probe.md")" ]
# }
@test "use run twice changes nothing: files, excludes, worktrees and log" {
  "$SCRIPT" use "$SKILL" "$A" 2>/dev/null
  before=$(snapshot; log)
  SKILL_COPY_NOW=2000 run --separate-stderr "$SCRIPT" use "$SKILL" "$A"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: demo-skill -> skill-$A ($A)"* ]]
  [ "$(snapshot; log)" = "$before" ]
}

# REVIEW PLACEHOLDER: link links each agent definition into the project's .claude/agents -> use gives each agent of the copy its own relative link and leaves the project's own agents alone
# @test "link links each agent definition into the project's .claude/agents" {
#   run --separate-stderr "$SCRIPT" link
#   [ "$status" -eq 0 ]
#   [ "$stderr" = "agents: linked: $MAIN/.claude/agents/probe.md" ]
#   [ -L .claude/agents/probe.md ]
#   [ "$(readlink .claude/agents/probe.md)" = "$(realpath "$SKILL/agents/probe.md")" ]
# }
@test "use gives each agent of the copy its own relative link and leaves the project's own agents alone" {
  mkdir -p .claude/agents
  echo mine > .claude/agents/mine.md
  git add .claude/agents/mine.md
  git commit -qm "own agent"
  run --separate-stderr "$SCRIPT" use "$SKILL" "$A"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: demo-skill -> skill-$A ($A)"* ]]
  [ ! -L .claude/agents ]
  [ -L .claude/agents/probe.md ]
  [ "$(readlink .claude/agents/probe.md)" = "../../../demo-skill/.worktrees/skill-$A/agents/probe.md" ]
  [ "$(cat .claude/agents/probe.md)" = A ]
  grep -qxF /.claude/agents/probe.md .git/info/exclude
  [ ! -L .claude/agents/mine.md ]
  [ "$(cat .claude/agents/mine.md)" = mine ]
  [ "$(grep -cF mine.md .git/info/exclude || true)" -eq 0 ]
  [ -z "$(git status --porcelain)" ]
}

@test "a second use with another ref moves the links and leaves the first copy unchanged" {
  "$SCRIPT" use "$SKILL" "$A" 2>/dev/null
  SKILL_COPY_NOW=2000 run --separate-stderr "$SCRIPT" use "$SKILL" "$B"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: demo-skill -> skill-$B ($B)"* ]]
  [ "$(readlink .claude/skills/demo-skill)" = "../../../demo-skill/.worktrees/skill-$B" ]
  [ "$(readlink .claude/agents/probe.md)" = "../../../demo-skill/.worktrees/skill-$B/agents/probe.md" ]
  [ "$(cat .claude/agents/probe.md)" = B ]
  [ "$(git -C "$SKILL/.worktrees/skill-$A" rev-parse HEAD | cut -c1-12)" = "$A" ]
  [ "$(tail -n 1 "$SKILL/.worktrees/skill-$A/SKILL.md")" = A ]
  [ -z "$(git -C "$SKILL/.worktrees/skill-$A" status --porcelain)" ]
  [ "$(log)" = "$(printf '1000 skill-%s %s\n2000 skill-%s %s' "$A" "$PROJ" "$B" "$PROJ")" ]
}

@test "with the skill repository as the project, the copy and the links are in it, and find -L terminates" {
  cd "$SKILL"
  run --separate-stderr "$SCRIPT" use . "$A"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: demo-skill -> skill-$A ($A)"* ]]
  [ "$(readlink .claude/skills/demo-skill)" = "../../.worktrees/skill-$A" ]
  [ "$(readlink .claude/agents/probe.md)" = "../../.worktrees/skill-$A/agents/probe.md" ]
  [ "$(log)" = "1000 skill-$A $SKILL" ]
  [ -z "$(git status --porcelain)" ]
  run --separate-stderr timeout 10 find -L . -name SKILL.md
  [ "$status" -eq 0 ]
  [[ -z "$stderr" ]]
  [[ "$output" == *"./.claude/skills/demo-skill/SKILL.md"* ]]
}

# REVIEW PLACEHOLDER: link run through a symbolic link to the skill targets the real definition -> use given a symbolic link to the skill repository links the real copy
# @test "link run through a symbolic link to the skill targets the real definition" {
#   ln -s "$SKILL" "$TMP/skill-link"
#   run --separate-stderr "$TMP/skill-link/tools/agents.sh" link
#   [ "$status" -eq 0 ]
#   [ "$stderr" = "agents: linked: $MAIN/.claude/agents/probe.md" ]
#   [ "$(readlink .claude/agents/probe.md)" = "$(realpath "$SKILL/agents/probe.md")" ]
# }
@test "use given a symbolic link to the skill repository links the real copy" {
  ln -s "$SKILL" "$TMP/skill-link"
  run --separate-stderr "$SCRIPT" use "$TMP/skill-link" "$A"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: demo-skill -> skill-$A ($A)"* ]]
  [ "$(readlink .claude/skills/demo-skill)" = "../../../demo-skill/.worktrees/skill-$A" ]
  [ "$(readlink .claude/agents/probe.md)" = "../../../demo-skill/.worktrees/skill-$A/agents/probe.md" ]
  [ "$(log)" = "1000 skill-$A $PROJ" ]
}

# REVIEW PLACEHOLDER: link adds no exclude entry for a path git already ignores -> use adds no exclude entry for a link git already ignores
# @test "link adds no exclude entry for a path git already ignores" {
#   printf '/.worktrees/\n/.claude/\n' > .gitignore
#   git commit -qam "ignore .claude"
#   run --separate-stderr "$SCRIPT" link
#   [ "$status" -eq 0 ]
#   [ "$stderr" = "agents: linked: $MAIN/.claude/agents/probe.md" ]
#   [ "$(grep -cF '/.claude/agents/probe.md' .git/info/exclude || true)" -eq 0 ]
#   [ -z "$(git status --porcelain)" ]
# }
@test "use adds no exclude entry for a link git already ignores" {
  printf '/.worktrees/\n/.claude/\n' > .gitignore
  git commit -qam "ignore .claude"
  run --separate-stderr "$SCRIPT" use "$SKILL" "$A"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: demo-skill -> skill-$A ($A)"* ]]
  [ -L .claude/skills/demo-skill ]
  [ "$(grep -cF /.claude/ .git/info/exclude || true)" -eq 0 ]
  [ -z "$(git status --porcelain)" ]
}

# --- a skill repository missing locally ------------------------------------

@test "use clones a missing skill repository next to the project" {
  new_project "$TMP/elsewhere/proj2"
  url="file://$REMOTES/demo-skill.git"
  run --separate-stderr "$SCRIPT" use "$url" origin/main
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: cloned $url into $TMP/elsewhere/demo-skill"* ]]
  [[ "$stderr" == *"skill-copy: demo-skill -> skill-$C (origin/main)"* ]]
  [ -d "$TMP/elsewhere/demo-skill/.git" ]
  [ "$(readlink .claude/skills/demo-skill)" = "../../../demo-skill/.worktrees/skill-$C" ]
  [ "$(readlink -f .claude/skills/demo-skill)" = "$TMP/elsewhere/demo-skill/.worktrees/skill-$C" ]
  [ -z "$(git status --porcelain)" ]
}

@test "use clones a missing skill repository where --clone-to says" {
  new_project "$TMP/elsewhere/proj2"
  url="file://$REMOTES/demo-skill.git"
  run --separate-stderr "$SCRIPT" use "$url" origin/main --clone-to "$TMP/clones/my-skill"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: cloned $url into $TMP/clones/my-skill"* ]]
  [[ "$stderr" == *"skill-copy: demo-skill -> skill-$C (origin/main)"* ]]
  [ ! -e "$TMP/elsewhere/demo-skill" ]
  [ "$(readlink .claude/skills/demo-skill)" = "../../../../clones/my-skill/.worktrees/skill-$C" ]
  [ "$(readlink -f .claude/skills/demo-skill)" = "$TMP/clones/my-skill/.worktrees/skill-$C" ]
}

# --- the hook: tools/skill-copy-hook.sh of the copy --------------------------

@test "use sources the copy's hook in a subshell with the copy's and the project's directories; nothing it sets leaks" {
  commit_hook "printf '%s\n' \"\${BASH_SOURCE[0]}\" \"\$1\" \"\$2\" > '$TMP/hook.args'
name=hijacked
copy=hijacked
say() { :; }
cd /"
  run --separate-stderr "$SCRIPT" use "$SKILL" "$H"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: demo-skill -> skill-$H ($H)"* ]]
  [ "$(cat "$TMP/hook.args")" = "$(printf '%s\n' "$SKILL/.worktrees/skill-$H/tools/skill-copy-hook.sh" "$SKILL/.worktrees/skill-$H" "$PROJ")" ]
  [ "$(readlink .claude/skills/demo-skill)" = "../../../demo-skill/.worktrees/skill-$H" ]
  grep -qxF /.claude/skills/demo-skill .git/info/exclude
  [ "$(log)" = "1000 skill-$H $PROJ" ]
}

@test "when the hook fails, use exits 1 and the links do not move" {
  "$SCRIPT" use "$SKILL" "$A" 2>/dev/null
  commit_hook "return 1"
  SKILL_COPY_NOW=2000 run --separate-stderr "$SCRIPT" use "$SKILL" "$H"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"skill-copy: the hook of skill-$H failed; links not moved"* ]]
  [ "$(readlink .claude/skills/demo-skill)" = "../../../demo-skill/.worktrees/skill-$A" ]
  [ "$(readlink .claude/agents/probe.md)" = "../../../demo-skill/.worktrees/skill-$A/agents/probe.md" ]
  [ "$(log)" = "1000 skill-$A $PROJ" ]
}

@test "the hook's skill_copy_link links a project file into the copy, relatively" {
  echo '{"k": 1}' > settings.json
  commit_hook "printf '%s\n' \"\${SKILL_COPY_FROZEN:-}\" > '$TMP/hook.frozen'
skill_copy_link \"\$2/settings.json\" \"\$1/settings.json\""
  run --separate-stderr "$SCRIPT" use "$SKILL" "$H"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: demo-skill -> skill-$H ($H)"* ]]
  [ -z "$(cat "$TMP/hook.frozen")" ]
  copy="$SKILL/.worktrees/skill-$H"
  [ -L "$copy/settings.json" ]
  [[ "$(readlink "$copy/settings.json")" != /* ]]
  [ "$(readlink -f "$copy/settings.json")" = "$PROJ/settings.json" ]
  [ -z "$(git -C "$copy" status --porcelain)" ]
}

@test "with --frozen, the hook's skill_copy_link copies the project file instead" {
  echo '{"k": 1}' > settings.json
  commit_hook "printf '%s\n' \"\${SKILL_COPY_FROZEN:-}\" > '$TMP/hook.frozen'
skill_copy_link \"\$2/settings.json\" \"\$1/settings.json\""
  run --separate-stderr "$SCRIPT" use "$SKILL" "$H" --frozen
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: demo-skill -> skill-$H ($H)"* ]]
  [ "$(cat "$TMP/hook.frozen")" = 1 ]
  copy="$SKILL/.worktrees/skill-$H"
  [ ! -L "$copy/settings.json" ]
  [ "$(cat "$copy/settings.json")" = '{"k": 1}' ]
  echo changed > settings.json
  [ "$(cat "$copy/settings.json")" = '{"k": 1}' ]
}

# --- pruning ---------------------------------------------------------------
#
# A copy is kept while any project recorded in the log still has a link into
# it, or while a running session may use it: when it stopped being current
# later than the oldest session start minus the margin (120 s by default).
# With SKILL_COPY_STARTS empty, no session runs.

# A current from 1000 to 2000, B from 2000 to 3000, C from 3000 on.
use_a_b_c() {
  SKILL_COPY_NOW=1000 "$SCRIPT" use "$SKILL" "$A" 2>/dev/null
  SKILL_COPY_NOW=2000 "$SCRIPT" use "$SKILL" "$B" 2>/dev/null
  SKILL_COPY_NOW=3000 "$SCRIPT" use "$SKILL" "$C" 2>/dev/null
}

# Project proj2 uses A at 1000; this project uses A at 1100, then B at 2000.
two_projects() {
  new_project "$WORK/proj2"
  SKILL_COPY_NOW=1000 "$SCRIPT" use "$SKILL" "$A" 2>/dev/null
  cd "$PROJ"
  SKILL_COPY_NOW=1100 "$SCRIPT" use "$SKILL" "$A" 2>/dev/null
}

@test "a copy still linked by another project is kept when this project moves on" {
  export SKILL_COPY_STARTS=""
  two_projects
  SKILL_COPY_NOW=2000 run --separate-stderr "$SCRIPT" use "$SKILL" "$B"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: demo-skill -> skill-$B ($B)"* ]]
  [[ "$stderr" != *"removed skill-$A"* ]]
  [ -d "$SKILL/.worktrees/skill-$A" ]
  [ "$(readlink -f "$WORK/proj2/.claude/skills/demo-skill")" = "$SKILL/.worktrees/skill-$A" ]
  [ "$(log)" = "$(printf '1000 skill-%s %s\n1100 skill-%s %s\n2000 skill-%s %s' \
    "$A" "$WORK/proj2" "$A" "$PROJ" "$B" "$PROJ")" ]
}

@test "once the other project's links are gone, prune removes the copy" {
  export SKILL_COPY_STARTS=""
  two_projects
  SKILL_COPY_NOW=2000 "$SCRIPT" use "$SKILL" "$B" 2>/dev/null
  rm "$WORK/proj2/.claude/skills/demo-skill" "$WORK/proj2/.claude/agents/probe.md"
  SKILL_COPY_NOW=3000 run --separate-stderr "$SCRIPT" prune "$SKILL"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: removed skill-$A"* ]]
  [ ! -e "$SKILL/.worktrees/skill-$A" ]
  [[ "$(git -C "$SKILL" worktree list)" != *"skill-$A"* ]]
  [ -d "$SKILL/.worktrees/skill-$B" ]
}

@test "prune keeps a copy that stopped being current within the margin before the oldest session" {
  use_a_b_c
  # Oldest session at 3050, minus 120 s: A (ended 2000) goes, B (ended 3000) stays.
  SKILL_COPY_NOW=4000 SKILL_COPY_STARTS="3500 3050" run --separate-stderr "$SCRIPT" prune "$SKILL"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: removed skill-$A"* ]]
  [[ "$stderr" != *"removed skill-$B"* ]]
  [ ! -e "$SKILL/.worktrees/skill-$A" ]
  [ -d "$SKILL/.worktrees/skill-$B" ]
  [ -d "$SKILL/.worktrees/skill-$C" ]
}

@test "with no session and no other project, only the current copy is kept" {
  use_a_b_c
  SKILL_COPY_NOW=4000 SKILL_COPY_STARTS="" run --separate-stderr "$SCRIPT" prune "$SKILL"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: removed skill-$A"* ]]
  [[ "$stderr" == *"skill-copy: removed skill-$B"* ]]
  [ ! -e "$SKILL/.worktrees/skill-$A" ]
  [ ! -e "$SKILL/.worktrees/skill-$B" ]
  [ "$(readlink -f .claude/skills/demo-skill)" = "$SKILL/.worktrees/skill-$C" ]
}

# --- no dependency on Claude -------------------------------------------------

@test "with no claude process, an empty HOME and link directories outside .claude, use succeeds and creates no .claude" {
  mkdir -p "$TMP/bin" "$TMP/empty-home"
  printf '#!/bin/sh\nexit 1\n' > "$TMP/bin/pgrep"
  chmod +x "$TMP/bin/pgrep"
  unset SKILL_COPY_STARTS
  HOME="$TMP/empty-home" PATH="$TMP/bin:$PATH" run --separate-stderr \
    "$SCRIPT" use "$SKILL" "$A" --skills-dir ext/skills --agents-dir ext/agents
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: demo-skill -> skill-$A ($A)"* ]]
  [ "$(readlink ext/skills/demo-skill)" = "../../../demo-skill/.worktrees/skill-$A" ]
  [ "$(readlink ext/agents/probe.md)" = "../../../demo-skill/.worktrees/skill-$A/agents/probe.md" ]
  grep -qxF /ext/skills/demo-skill .git/info/exclude
  grep -qxF /ext/agents/probe.md .git/info/exclude
  [ ! -e .claude ]
  [ ! -e "$SKILL/.claude" ]
  [ -z "$(ls -A "$TMP/empty-home")" ]
  [ -z "$(git status --porcelain)" ]
}

# --- refusals: exit 3, nothing changed ---------------------------------------

# REVIEW PLACEHOLDER: link run from a branch worktree links into the main worktree -> use refuses to run outside the main worktree of the project
# @test "link run from a branch worktree links into the main worktree" {
#   git worktree add -q -b feature/7-trial .worktrees/7-trial
#   cd .worktrees/7-trial
#   run --separate-stderr "$SCRIPT" link
#   [ "$status" -eq 0 ]
#   [ "$stderr" = "agents: linked: $MAIN/.claude/agents/probe.md" ]
#   [ -L "$MAIN/.claude/agents/probe.md" ]
#   [ ! -e .claude/agents/probe.md ]
# }
@test "use refuses to run outside the main worktree of the project" {
  git worktree add -q -b feature/9-x .worktrees/9-x
  before=$(snapshot)
  cd .worktrees/9-x
  run --separate-stderr "$SCRIPT" use "$SKILL" "$A"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"skill-copy: run from the main worktree of the project"* ]]
  [ "$(snapshot)" = "$before" ]
}

@test "use refuses when /.worktrees/ is not ignored in the skill repository" {
  (cd "$SKILL" && : > .gitignore && git commit -qam "no .worktrees entry")
  before=$(snapshot)
  run --separate-stderr "$SCRIPT" use "$SKILL" "$A"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"skill-copy: /.worktrees/ is not ignored by git in $SKILL"* ]]
  [ "$(snapshot)" = "$before" ]
}

@test "use refuses a commit whose SKILL.md has no name: field" {
  (cd "$SKILL" && skill_md "" nameless && git commit -qam nameless)
  N=$(git -C "$SKILL" rev-parse HEAD | cut -c1-12)
  before=$(snapshot)
  run --separate-stderr "$SCRIPT" use "$SKILL" "$N"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"skill-copy: SKILL.md at $N has no name: field"* ]]
  [ "$(snapshot)" = "$before" ]
}

@test "use refuses a non-link at the skill link" {
  mkdir -p .claude/skills/demo-skill
  before=$(snapshot)
  run --separate-stderr "$SCRIPT" use "$SKILL" "$A"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"skill-copy: .claude/skills/demo-skill exists and is not a link"* ]]
  [ "$(snapshot)" = "$before" ]
}

# REVIEW PLACEHOLDER: link never overwrites a regular file -> use refuses a regular file with the name of an agent link
# @test "link never overwrites a regular file" {
#   mkdir -p .claude/agents
#   echo mine > .claude/agents/probe.md
#   run --separate-stderr "$SCRIPT" link
#   [ "$status" -eq 3 ]
#   [[ "$stderr" == *".claude/agents/probe.md exists and is not a link to $(realpath "$SKILL/agents/probe.md"): nothing is overwritten"* ]]
#   [ ! -L .claude/agents/probe.md ]
#   [ "$(cat .claude/agents/probe.md)" = mine ]
# }
# REVIEW PLACEHOLDER: link validates every definition before writing anything -> use refuses a regular file with the name of an agent link
# @test "link validates every definition before writing anything" {
#   printf -- '---\nname: second\nmodel: opus\n---\nsecond\n' > "$SKILL/agents/second.md"
#   mkdir -p .claude/agents
#   echo mine > .claude/agents/second.md
#   run --separate-stderr "$SCRIPT" link
#   [ "$status" -eq 3 ]
#   [[ "$stderr" == *".claude/agents/second.md exists and is not a link to"* ]]
#   [[ "$stderr" != *"linked:"* ]]
#   [ ! -e .claude/agents/probe.md ]
#   [ "$(grep -cF '/.claude/agents/' .git/info/exclude || true)" -eq 0 ]
# }
@test "use refuses a regular file with the name of an agent link" {
  # Two agents; the second clashes: nothing at all is written, not even the
  # skill link or the first agent's link.
  (cd "$SKILL" && echo second > agents/second.md && git add agents && git commit -qm second)
  S=$(git -C "$SKILL" rev-parse HEAD | cut -c1-12)
  mkdir -p .claude/agents
  echo mine > .claude/agents/second.md
  before=$(snapshot)
  run --separate-stderr "$SCRIPT" use "$SKILL" "$S"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"skill-copy: .claude/agents/second.md exists and is not a link"* ]]
  [ "$(cat .claude/agents/second.md)" = mine ]
  [ "$(snapshot)" = "$before" ]
}

@test "use refuses a skill link that does not point into a copy" {
  mkdir -p .claude/skills "$WORK/other-skill"
  ln -s ../../../other-skill .claude/skills/demo-skill
  before=$(snapshot)
  run --separate-stderr "$SCRIPT" use "$SKILL" "$A"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"skill-copy: .claude/skills/demo-skill is a link that does not point into a copy"* ]]
  [ "$(readlink .claude/skills/demo-skill)" = ../../../other-skill ]
  [ "$(snapshot)" = "$before" ]
}

# REVIEW PLACEHOLDER: link never replaces a link to another file -> use refuses an agent link that does not point into a copy
# @test "link never replaces a link to another file" {
#   mkdir -p .claude/agents
#   echo other > "$TMP/other.md"
#   ln -s "$TMP/other.md" .claude/agents/probe.md
#   run --separate-stderr "$SCRIPT" link
#   [ "$status" -eq 3 ]
#   [[ "$stderr" == *".claude/agents/probe.md exists and is not a link to $(realpath "$SKILL/agents/probe.md"): nothing is overwritten"* ]]
#   [ "$(readlink .claude/agents/probe.md)" = "$TMP/other.md" ]
# }
# REVIEW PLACEHOLDER: link never replaces a dangling link -> use refuses an agent link that does not point into a copy
# @test "link never replaces a dangling link" {
#   mkdir -p .claude/agents
#   ln -s "$TMP/gone.md" .claude/agents/probe.md
#   run --separate-stderr "$SCRIPT" link
#   [ "$status" -eq 3 ]
#   [[ "$stderr" == *".claude/agents/probe.md exists and is not a link to"* ]]
#   [ "$(readlink .claude/agents/probe.md)" = "$TMP/gone.md" ]
# }
@test "use refuses an agent link that does not point into a copy" {
  mkdir -p .claude/agents
  echo other > "$TMP/other.md"
  for target in "$TMP/other.md" "$TMP/gone.md"; do
    ln -sfn "$target" .claude/agents/probe.md
    before=$(snapshot)
    run --separate-stderr "$SCRIPT" use "$SKILL" "$A"
    [ "$status" -eq 3 ]
    [[ "$stderr" == *"skill-copy: .claude/agents/probe.md is a link that does not point into a copy"* ]]
    [ "$(readlink .claude/agents/probe.md)" = "$target" ]
    [ "$(snapshot)" = "$before" ]
  done
}

# --- tests of tools/agents.bats with no core replacement ---------------------
#
# tools/agents.sh and tools/agents.bats are removed (#23): skill-copy.sh makes
# the agent links. The old tests below are replaced by edge cases of Task 5
# (named after the arrow), or dropped with --user.

# REVIEW PLACEHOLDER: an unknown subcommand exits with the usage code -> an unknown subcommand, a missing argument or an extra argument exit with the usage code (edge case, Task 5)
# @test "an unknown subcommand exits with the usage code" {
#   run --separate-stderr "$SCRIPT" unknown
#   [ "$status" -eq 2 ]
#   [[ "$stderr" == *"usage: agents.sh link [--user]"* ]]
# }
# REVIEW PLACEHOLDER: link refuses extra or unknown arguments -> an unknown subcommand, a missing argument or an extra argument exit with the usage code (edge case, Task 5)
# @test "link refuses extra or unknown arguments" {
#   run --separate-stderr "$SCRIPT" link --bogus
#   [ "$status" -eq 2 ]
#   [[ "$stderr" == *"usage: agents.sh link [--user]"* ]]
#   run --separate-stderr "$SCRIPT" link --user extra
#   [ "$status" -eq 2 ]
#   [[ "$stderr" == *"usage: agents.sh link [--user]"* ]]
#   [ ! -e .claude ]
# }
# REVIEW PLACEHOLDER: link outside a git repository fails in project mode -> outside a git repository, use exits 1 (edge case, Task 5)
# @test "link outside a git repository fails in project mode" {
#   mkdir "$TMP/plain"
#   cd "$TMP/plain"
#   run --separate-stderr "$SCRIPT" link
#   [ "$status" -eq 1 ]
#   [[ "$stderr" == *"not in a git repository"* ]]
#   [ ! -e .claude ]
# }
# REVIEW PLACEHOLDER: link fails when the skill ships no agent definitions -> use removes the link of an agent dropped between copies (edge case, Task 5); a skill with no agents/ is no longer an error
# @test "link fails when the skill ships no agent definitions" {
#   rm "$SKILL/agents/probe.md"
#   run --separate-stderr "$SCRIPT" link
#   [ "$status" -eq 1 ]
#   [[ "$stderr" == *"no agent definitions in $(realpath "$SKILL")/agents"* ]]
#   [ ! -e .claude ]
# }
# REVIEW PLACEHOLDER: link --user links into ~/.claude/agents and leaves the project alone -> none: --user is dropped (#23, principle 5)
# @test "link --user links into ~/.claude/agents and leaves the project alone" {
#   run --separate-stderr "$SCRIPT" link --user
#   [ "$status" -eq 0 ]
#   [ "$stderr" = "agents: linked: $HOME/.claude/agents/probe.md" ]
#   [ "$(readlink "$HOME/.claude/agents/probe.md")" = "$(realpath "$SKILL/agents/probe.md")" ]
#   [ ! -e .claude ]
# }
# REVIEW PLACEHOLDER: link --user works outside a git repository -> none: --user is dropped (#23, principle 5)
# @test "link --user works outside a git repository" {
#   mkdir "$TMP/plain"
#   cd "$TMP/plain"
#   run --separate-stderr "$SCRIPT" link --user
#   [ "$status" -eq 0 ]
#   [ "$stderr" = "agents: linked: $HOME/.claude/agents/probe.md" ]
#   [ -L "$HOME/.claude/agents/probe.md" ]
# }

# --- Change History -------------------------------------------------------
# | PR     | Summary                                                       |
# |--------|---------------------------------------------------------------|
