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
#
# A copy belongs to one project: the copy of commit X for the project at path
# P is skill-<sha12 of X>-<pid P>, and its USER_PROJECT file holds P. $PP is
# the pid of $PROJ.

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
  PP=$(pid "$PROJ")
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

# pid <project path>: the project's part of a copy's name, the first 8 hex
# digits of the SHA-1 of its absolute path.
pid() {
  printf '%s' "$1" | sha1sum | cut -c1-8
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

@test "the script exists and is executable" {
  [ -x "$SCRIPT" ]
}

# --- use -------------------------------------------------------------------

@test "use creates the project's own detached copy in the skill repository, links it relatively, excludes the link and logs the move" {
  run --separate-stderr "$SCRIPT" use "$SKILL" "$A"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: demo-skill -> skill-$A-$PP ($A)"* ]]
  [ -d "$SKILL/.worktrees/skill-$A-$PP" ]
  [ "$(git -C "$SKILL/.worktrees/skill-$A-$PP" rev-parse HEAD | cut -c1-12)" = "$A" ]
  [ -z "$(git -C "$SKILL/.worktrees/skill-$A-$PP" branch --show-current)" ]
  [ -L .claude/skills/demo-skill ]
  [ "$(readlink .claude/skills/demo-skill)" = "../../../demo-skill/.worktrees/skill-$A-$PP" ]
  [ "$(readlink -f .claude/skills/demo-skill)" = "$SKILL/.worktrees/skill-$A-$PP" ]
  grep -qxF /.claude/skills/demo-skill .git/info/exclude
  [ "$(cat "$SKILL/.worktrees/skill-$A-$PP/USER_PROJECT")" = "$PROJ" ]
  [ ! -L "$SKILL/.worktrees/skill-$A-$PP/USER_PROJECT" ]
  # The skill's .gitignore does not ignore USER_PROJECT: the skill repository's
  # exclude does, so that a copy of any commit stays clean.
  grep -qxF /USER_PROJECT "$SKILL/.git/info/exclude"
  [ -z "$(git -C "$SKILL/.worktrees/skill-$A-$PP" status --porcelain)" ]
  [ "$(log)" = "1000 skill-$A-$PP $PROJ" ]
  [ -z "$(git status --porcelain)" ]
  [ -z "$(git -C "$SKILL" status --porcelain)" ]
}

@test "use run twice changes nothing: files, excludes, worktrees and log" {
  "$SCRIPT" use "$SKILL" "$A" 2>/dev/null
  before=$(snapshot; log)
  SKILL_COPY_NOW=2000 run --separate-stderr "$SCRIPT" use "$SKILL" "$A"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: demo-skill -> skill-$A-$PP ($A)"* ]]
  [ "$(snapshot; log)" = "$before" ]
}

@test "use gives each agent of the copy its own relative link and leaves the project's own agents alone" {
  mkdir -p .claude/agents
  echo mine > .claude/agents/mine.md
  git add .claude/agents/mine.md
  git commit -qm "own agent"
  run --separate-stderr "$SCRIPT" use "$SKILL" "$A"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: demo-skill -> skill-$A-$PP ($A)"* ]]
  [ ! -L .claude/agents ]
  [ -L .claude/agents/probe.md ]
  [ "$(readlink .claude/agents/probe.md)" = "../../../demo-skill/.worktrees/skill-$A-$PP/agents/probe.md" ]
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
  [[ "$stderr" == *"skill-copy: demo-skill -> skill-$B-$PP ($B)"* ]]
  [ "$(readlink .claude/skills/demo-skill)" = "../../../demo-skill/.worktrees/skill-$B-$PP" ]
  [ "$(readlink .claude/agents/probe.md)" = "../../../demo-skill/.worktrees/skill-$B-$PP/agents/probe.md" ]
  [ "$(cat .claude/agents/probe.md)" = B ]
  [ "$(git -C "$SKILL/.worktrees/skill-$A-$PP" rev-parse HEAD | cut -c1-12)" = "$A" ]
  [ "$(tail -n 1 "$SKILL/.worktrees/skill-$A-$PP/SKILL.md")" = A ]
  [ -z "$(git -C "$SKILL/.worktrees/skill-$A-$PP" status --porcelain)" ]
  [ "$(log)" = "$(printf '1000 skill-%s-%s %s\n2000 skill-%s-%s %s' "$A" "$PP" "$PROJ" "$B" "$PP" "$PROJ")" ]
}

@test "with the skill repository as the project, the copy and the links are in it, and find -L terminates" {
  cd "$SKILL"
  SP=$(pid "$SKILL")
  run --separate-stderr "$SCRIPT" use . "$A"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: demo-skill -> skill-$A-$SP ($A)"* ]]
  [ "$(readlink .claude/skills/demo-skill)" = "../../.worktrees/skill-$A-$SP" ]
  [ "$(readlink .claude/agents/probe.md)" = "../../.worktrees/skill-$A-$SP/agents/probe.md" ]
  [ "$(cat ".worktrees/skill-$A-$SP/USER_PROJECT")" = "$SKILL" ]
  [ "$(log)" = "1000 skill-$A-$SP $SKILL" ]
  [ -z "$(git status --porcelain)" ]
  run --separate-stderr timeout 10 find -L . -name SKILL.md
  [ "$status" -eq 0 ]
  [[ -z "$stderr" ]]
  [[ "$output" == *"./.claude/skills/demo-skill/SKILL.md"* ]]
}

@test "use given a symbolic link to the skill repository links the real copy" {
  ln -s "$SKILL" "$TMP/skill-link"
  run --separate-stderr "$SCRIPT" use "$TMP/skill-link" "$A"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: demo-skill -> skill-$A-$PP ($A)"* ]]
  [ "$(readlink .claude/skills/demo-skill)" = "../../../demo-skill/.worktrees/skill-$A-$PP" ]
  [ "$(readlink .claude/agents/probe.md)" = "../../../demo-skill/.worktrees/skill-$A-$PP/agents/probe.md" ]
  [ "$(log)" = "1000 skill-$A-$PP $PROJ" ]
}

@test "use adds no exclude entry for a link git already ignores" {
  printf '/.worktrees/\n/.claude/\n' > .gitignore
  git commit -qam "ignore .claude"
  run --separate-stderr "$SCRIPT" use "$SKILL" "$A"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: demo-skill -> skill-$A-$PP ($A)"* ]]
  [ -L .claude/skills/demo-skill ]
  [ "$(grep -cF /.claude/ .git/info/exclude || true)" -eq 0 ]
  [ -z "$(git status --porcelain)" ]
}

# --- a skill repository missing locally ------------------------------------

@test "use clones a missing skill repository next to the project" {
  new_project "$TMP/elsewhere/proj2"
  P2=$(pid "$TMP/elsewhere/proj2")
  url="file://$REMOTES/demo-skill.git"
  run --separate-stderr "$SCRIPT" use "$url" origin/main
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: cloned $url into $TMP/elsewhere/demo-skill"* ]]
  [[ "$stderr" == *"skill-copy: demo-skill -> skill-$C-$P2 (origin/main)"* ]]
  [ -d "$TMP/elsewhere/demo-skill/.git" ]
  [ "$(readlink .claude/skills/demo-skill)" = "../../../demo-skill/.worktrees/skill-$C-$P2" ]
  [ "$(readlink -f .claude/skills/demo-skill)" = "$TMP/elsewhere/demo-skill/.worktrees/skill-$C-$P2" ]
  [ -z "$(git status --porcelain)" ]
}

@test "use clones a missing skill repository where --clone-to says" {
  new_project "$TMP/elsewhere/proj2"
  P2=$(pid "$TMP/elsewhere/proj2")
  url="file://$REMOTES/demo-skill.git"
  run --separate-stderr "$SCRIPT" use "$url" origin/main --clone-to "$TMP/clones/my-skill"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: cloned $url into $TMP/clones/my-skill"* ]]
  [[ "$stderr" == *"skill-copy: demo-skill -> skill-$C-$P2 (origin/main)"* ]]
  [ ! -e "$TMP/elsewhere/demo-skill" ]
  [ "$(readlink .claude/skills/demo-skill)" = "../../../../clones/my-skill/.worktrees/skill-$C-$P2" ]
  [ "$(readlink -f .claude/skills/demo-skill)" = "$TMP/clones/my-skill/.worktrees/skill-$C-$P2" ]
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
  [[ "$stderr" == *"skill-copy: demo-skill -> skill-$H-$PP ($H)"* ]]
  [ "$(cat "$TMP/hook.args")" = "$(printf '%s\n' "$SKILL/.worktrees/skill-$H-$PP/tools/skill-copy-hook.sh" "$SKILL/.worktrees/skill-$H-$PP" "$PROJ")" ]
  [ "$(readlink .claude/skills/demo-skill)" = "../../../demo-skill/.worktrees/skill-$H-$PP" ]
  grep -qxF /.claude/skills/demo-skill .git/info/exclude
  [ "$(log)" = "1000 skill-$H-$PP $PROJ" ]
}

@test "when the hook fails, use exits 1 and the links do not move" {
  "$SCRIPT" use "$SKILL" "$A" 2>/dev/null
  commit_hook "return 1"
  SKILL_COPY_NOW=2000 run --separate-stderr "$SCRIPT" use "$SKILL" "$H"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"skill-copy: the hook of skill-$H-$PP failed; links not moved"* ]]
  [ "$(readlink .claude/skills/demo-skill)" = "../../../demo-skill/.worktrees/skill-$A-$PP" ]
  [ "$(readlink .claude/agents/probe.md)" = "../../../demo-skill/.worktrees/skill-$A-$PP/agents/probe.md" ]
  [ "$(log)" = "1000 skill-$A-$PP $PROJ" ]
}

@test "the hook's skill_copy_link links a project file into the copy, relatively" {
  echo '{"k": 1}' > settings.json
  commit_hook "printf '%s\n' \"\${SKILL_COPY_FROZEN:-}\" > '$TMP/hook.frozen'
skill_copy_link \"\$2/settings.json\" \"\$1/settings.json\""
  run --separate-stderr "$SCRIPT" use "$SKILL" "$H"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: demo-skill -> skill-$H-$PP ($H)"* ]]
  [ -z "$(cat "$TMP/hook.frozen")" ]
  copy="$SKILL/.worktrees/skill-$H-$PP"
  [ -L "$copy/settings.json" ]
  [[ "$(readlink "$copy/settings.json")" != /* ]]
  [ "$(readlink -f "$copy/settings.json")" = "$PROJ/settings.json" ]
  [ -z "$(git -C "$copy" status --porcelain)" ]
}

@test "two projects on the same commit: each copy's hook links to its own project's file" {
  echo one > settings.json
  commit_hook "skill_copy_link \"\$2/settings.json\" \"\$1/settings.json\""
  "$SCRIPT" use "$SKILL" "$H" 2>/dev/null
  new_project "$WORK/proj2"
  P2=$(pid "$WORK/proj2")
  echo two > settings.json
  run --separate-stderr "$SCRIPT" use "$SKILL" "$H"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: demo-skill -> skill-$H-$P2 ($H)"* ]]
  [ "$(cat "$SKILL/.worktrees/skill-$H-$PP/settings.json")" = one ]
  [ "$(cat "$SKILL/.worktrees/skill-$H-$P2/settings.json")" = two ]
}

@test "with --frozen, the hook's skill_copy_link copies the project file instead" {
  echo '{"k": 1}' > settings.json
  commit_hook "printf '%s\n' \"\${SKILL_COPY_FROZEN:-}\" > '$TMP/hook.frozen'
skill_copy_link \"\$2/settings.json\" \"\$1/settings.json\""
  run --separate-stderr "$SCRIPT" use "$SKILL" "$H" --frozen
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: demo-skill -> skill-$H-$PP ($H)"* ]]
  [ "$(cat "$TMP/hook.frozen")" = 1 ]
  copy="$SKILL/.worktrees/skill-$H-$PP"
  [ ! -L "$copy/settings.json" ]
  [ "$(cat "$copy/settings.json")" = '{"k": 1}' ]
  echo changed > settings.json
  [ "$(cat "$copy/settings.json")" = '{"k": 1}' ]
}

# --- pruning ---------------------------------------------------------------
#
# A copy belongs to the one project named in its USER_PROJECT file. It is kept
# while that project still has a link into it, or while a running session may
# use it: when it stopped being current later than the oldest session start
# minus the margin (120 s by default).
# With SKILL_COPY_STARTS empty, no session runs.

# A current from 1000 to 2000, B from 2000 to 3000, C from 3000 on.
use_a_b_c() {
  SKILL_COPY_NOW=1000 "$SCRIPT" use "$SKILL" "$A" 2>/dev/null
  SKILL_COPY_NOW=2000 "$SCRIPT" use "$SKILL" "$B" 2>/dev/null
  SKILL_COPY_NOW=3000 "$SCRIPT" use "$SKILL" "$C" 2>/dev/null
}

# Project proj2 uses A at 1000; this project uses A at 1100. Each has its own
# copy of A.
two_projects() {
  new_project "$WORK/proj2"
  P2=$(pid "$WORK/proj2")
  SKILL_COPY_NOW=1000 "$SCRIPT" use "$SKILL" "$A" 2>/dev/null
  cd "$PROJ"
  SKILL_COPY_NOW=1100 "$SCRIPT" use "$SKILL" "$A" 2>/dev/null
}

@test "two projects on the same commit get two copies, each pointing back to its own project" {
  two_projects
  [ "$P2" != "$PP" ]
  [ "$(readlink -f "$WORK/proj2/.claude/skills/demo-skill")" = "$SKILL/.worktrees/skill-$A-$P2" ]
  [ "$(readlink -f .claude/skills/demo-skill)" = "$SKILL/.worktrees/skill-$A-$PP" ]
  [ "$(cat "$SKILL/.worktrees/skill-$A-$P2/USER_PROJECT")" = "$WORK/proj2" ]
  [ "$(cat "$SKILL/.worktrees/skill-$A-$PP/USER_PROJECT")" = "$PROJ" ]
  [ "$(log)" = "$(printf '1000 skill-%s-%s %s\n1100 skill-%s-%s %s' \
    "$A" "$P2" "$WORK/proj2" "$A" "$PP" "$PROJ")" ]
}

@test "when this project moves on, its old copy goes and the other project's copy of the same commit stays" {
  export SKILL_COPY_STARTS=""
  two_projects
  SKILL_COPY_NOW=2000 run --separate-stderr "$SCRIPT" use "$SKILL" "$B"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: demo-skill -> skill-$B-$PP ($B)"* ]]
  [[ "$stderr" == *"skill-copy: removed skill-$A-$PP"* ]]
  [[ "$stderr" != *"removed skill-$A-$P2"* ]]
  [ ! -e "$SKILL/.worktrees/skill-$A-$PP" ]
  [ -d "$SKILL/.worktrees/skill-$A-$P2" ]
  [ "$(readlink -f "$WORK/proj2/.claude/skills/demo-skill")" = "$SKILL/.worktrees/skill-$A-$P2" ]
}

@test "once its project's links are gone, prune removes the copy" {
  export SKILL_COPY_STARTS=""
  two_projects
  rm "$WORK/proj2/.claude/skills/demo-skill" "$WORK/proj2/.claude/agents/probe.md"
  SKILL_COPY_NOW=3000 run --separate-stderr "$SCRIPT" prune "$SKILL"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: removed skill-$A-$P2"* ]]
  [[ "$stderr" != *"removed skill-$A-$PP"* ]]
  [ ! -e "$SKILL/.worktrees/skill-$A-$P2" ]
  [[ "$(git -C "$SKILL" worktree list)" != *"skill-$A-$P2"* ]]
  [ -d "$SKILL/.worktrees/skill-$A-$PP" ]
}

@test "once its project is gone, prune removes the copy" {
  export SKILL_COPY_STARTS=""
  two_projects
  rm -rf "$WORK/proj2"
  SKILL_COPY_NOW=3000 run --separate-stderr "$SCRIPT" prune "$SKILL"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: removed skill-$A-$P2"* ]]
  [ ! -e "$SKILL/.worktrees/skill-$A-$P2" ]
  [ -d "$SKILL/.worktrees/skill-$A-$PP" ]
}

@test "prune keeps a copy that stopped being current within the margin before the oldest session" {
  use_a_b_c
  # Oldest session at 3050, minus 120 s: A (ended 2000) goes, B (ended 3000) stays.
  SKILL_COPY_NOW=4000 SKILL_COPY_STARTS="3500 3050" run --separate-stderr "$SCRIPT" prune "$SKILL"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: removed skill-$A-$PP"* ]]
  [[ "$stderr" != *"removed skill-$B-$PP"* ]]
  [ ! -e "$SKILL/.worktrees/skill-$A-$PP" ]
  [ -d "$SKILL/.worktrees/skill-$B-$PP" ]
  [ -d "$SKILL/.worktrees/skill-$C-$PP" ]
}

@test "with no session and no other project, only the current copy is kept" {
  use_a_b_c
  SKILL_COPY_NOW=4000 SKILL_COPY_STARTS="" run --separate-stderr "$SCRIPT" prune "$SKILL"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: removed skill-$A-$PP"* ]]
  [[ "$stderr" == *"skill-copy: removed skill-$B-$PP"* ]]
  [ ! -e "$SKILL/.worktrees/skill-$A-$PP" ]
  [ ! -e "$SKILL/.worktrees/skill-$B-$PP" ]
  [ "$(readlink -f .claude/skills/demo-skill)" = "$SKILL/.worktrees/skill-$C-$PP" ]
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
  [[ "$stderr" == *"skill-copy: demo-skill -> skill-$A-$PP ($A)"* ]]
  [ "$(readlink ext/skills/demo-skill)" = "../../../demo-skill/.worktrees/skill-$A-$PP" ]
  [ "$(readlink ext/agents/probe.md)" = "../../../demo-skill/.worktrees/skill-$A-$PP/agents/probe.md" ]
  grep -qxF /ext/skills/demo-skill .git/info/exclude
  grep -qxF /ext/agents/probe.md .git/info/exclude
  [ ! -e .claude ]
  [ ! -e "$SKILL/.claude" ]
  [ -z "$(ls -A "$TMP/empty-home")" ]
  [ -z "$(git status --porcelain)" ]
}

# --- refusals: exit 3, nothing changed ---------------------------------------

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

# --- edge cases --------------------------------------------------------------

USAGE="usage: skill-copy.sh use <skill repo> <ref> [--skills-dir <dir>] [--agents-dir <dir>] [--clone-to <path>] [--frozen] | update <copy> | prune <skill repo> | status <skill repo>"

@test "an unknown subcommand, a missing argument or an extra argument exit with the usage code" {
  before=$(snapshot)
  for args in "" "unknown" "use" "use x" "use x y --bogus" "use x y --skills-dir" \
              "update" "update x y" "prune" "prune x y" "status" "status x y"; do
    run --separate-stderr "$SCRIPT" $args
    [ "$status" -eq 2 ]
    [[ "$stderr" == *"skill-copy: $USAGE"* ]]
  done
  [ "$(snapshot)" = "$before" ]
}

@test "a link directory must be relative to the project root, inside it" {
  for dir in /abs/skills ../outside; do
    run --separate-stderr "$SCRIPT" use "$SKILL" "$A" --skills-dir "$dir"
    [ "$status" -eq 2 ]
    [[ "$stderr" == *"skill-copy: link directories are relative to the project root: $dir"* ]]
  done
  [ ! -e .claude ]
}

@test "outside a git repository, use exits 1" {
  mkdir "$TMP/plain"
  cd "$TMP/plain"
  run --separate-stderr "$SCRIPT" use "$SKILL" "$A"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"skill-copy: not in a git repository"* ]]
  [ ! -e .claude ]
}

@test "use with a skill repository that is neither a repository nor a URL exits 1" {
  run --separate-stderr "$SCRIPT" use "$TMP/no-such-skill" "$A"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"skill-copy: no skill repository at $TMP/no-such-skill"* ]]
  [ ! -e .claude ]
}

@test "use with an unknown ref exits 1 and changes nothing" {
  before=$(snapshot)
  run --separate-stderr "$SCRIPT" use "$SKILL" no-such-ref
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"skill-copy: unknown ref: no-such-ref"* ]]
  [ "$(snapshot)" = "$before" ]
}

@test "use warns when the fetch fails and uses the local refs" {
  git -C "$SKILL" remote set-url origin "$TMP/missing.git"
  run --separate-stderr "$SCRIPT" use "$SKILL" "$A"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: warning: fetch from origin failed; using local refs"* ]]
  [[ "$stderr" == *"skill-copy: demo-skill -> skill-$A-$PP ($A)"* ]]
  [ -d "$SKILL/.worktrees/skill-$A-$PP" ]
}

@test "use given a GitHub URL clones it next to the project, then reuses the clone" {
  # The URL is redirected to the local bare repository.
  export GIT_CONFIG_COUNT=1
  export GIT_CONFIG_KEY_0="url.file://$REMOTES/.insteadOf"
  export GIT_CONFIG_VALUE_0="https://github.com/CriticalOptimisation/"
  new_project "$TMP/elsewhere/proj2"
  P2=$(pid "$TMP/elsewhere/proj2")
  url=https://github.com/CriticalOptimisation/demo-skill.git
  run --separate-stderr "$SCRIPT" use "$url" origin/main
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: cloned $url into $TMP/elsewhere/demo-skill"* ]]
  [ "$(readlink -f .claude/skills/demo-skill)" = "$TMP/elsewhere/demo-skill/.worktrees/skill-$C-$P2" ]
  SKILL_COPY_NOW=2000 run --separate-stderr "$SCRIPT" use "$url" "$B"
  [ "$status" -eq 0 ]
  [[ "$stderr" != *"cloned"* ]]
  [[ "$stderr" == *"skill-copy: demo-skill -> skill-$B-$P2 ($B)"* ]]
}

@test "use removes the link of the old name when the name: field changed" {
  "$SCRIPT" use "$SKILL" "$A" 2>/dev/null
  (cd "$SKILL" && skill_md renamed-skill R && git commit -qam renamed)
  R=$(git -C "$SKILL" rev-parse HEAD | cut -c1-12)
  SKILL_COPY_NOW=2000 run --separate-stderr "$SCRIPT" use "$SKILL" "$R"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: removed link: .claude/skills/demo-skill"* ]]
  [[ "$stderr" == *"skill-copy: renamed-skill -> skill-$R-$PP ($R)"* ]]
  [ ! -e .claude/skills/demo-skill ] && [ ! -L .claude/skills/demo-skill ]
  [ "$(readlink .claude/skills/renamed-skill)" = "../../../demo-skill/.worktrees/skill-$R-$PP" ]
}

@test "use leaves alone the links of another skill, even into that skill's copies" {
  mkdir -p .claude/skills "$WORK/other/.worktrees/skill-0123456789ab-$PP"
  ln -s ../../../other-skill .claude/skills/plain-skill
  ln -s "../../../other/.worktrees/skill-0123456789ab-$PP" .claude/skills/other-skill
  run --separate-stderr "$SCRIPT" use "$SKILL" "$A"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: demo-skill -> skill-$A-$PP ($A)"* ]]
  [[ "$stderr" != *"removed link"* ]]
  [ "$(readlink .claude/skills/plain-skill)" = ../../../other-skill ]
  [ "$(readlink .claude/skills/other-skill)" = "../../../other/.worktrees/skill-0123456789ab-$PP" ]
}

@test "use removes the link of an agent dropped between copies" {
  "$SCRIPT" use "$SKILL" "$A" 2>/dev/null
  (cd "$SKILL" && git rm -q agents/probe.md && mkdir -p agents && echo kept > agents/kept.md && git add agents && git commit -qm drop)
  D=$(git -C "$SKILL" rev-parse HEAD | cut -c1-12)
  SKILL_COPY_NOW=2000 run --separate-stderr "$SCRIPT" use "$SKILL" "$D"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: removed link: .claude/agents/probe.md"* ]]
  [ ! -L .claude/agents/probe.md ]
  [ "$(readlink .claude/agents/kept.md)" = "../../../demo-skill/.worktrees/skill-$D-$PP/agents/kept.md" ]
}

@test "a skill with no agents/ and no hook gets only its skill link" {
  (cd "$SKILL" && git rm -rq agents && git commit -qm "no agents")
  N=$(git -C "$SKILL" rev-parse HEAD | cut -c1-12)
  run --separate-stderr "$SCRIPT" use "$SKILL" "$N"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: demo-skill -> skill-$N-$PP ($N)"* ]]
  [ -L .claude/skills/demo-skill ]
  [ ! -e .claude/agents ]
}

@test "prune keeps a copy with changes in it, warns and exits 1" {
  use_a_b_c
  echo edit >> "$SKILL/.worktrees/skill-$A-$PP/SKILL.md"
  SKILL_COPY_NOW=4000 SKILL_COPY_STARTS="" run --separate-stderr "$SCRIPT" prune "$SKILL"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"skill-copy: warning: skill-$A-$PP could not be removed (changes in it?); kept"* ]]
  [[ "$stderr" == *"skill-copy: removed skill-$B-$PP"* ]]
  [ -d "$SKILL/.worktrees/skill-$A-$PP" ]
}

@test "SKILL_COPY_MARGIN changes the margin" {
  use_a_b_c
  # B ended at 3000; the oldest session started at 3100: kept with 120 s, removed with 50 s.
  SKILL_COPY_NOW=4000 SKILL_COPY_STARTS="3100" run --separate-stderr "$SCRIPT" prune "$SKILL"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: removed skill-$A-$PP"* ]]
  [[ "$stderr" != *"removed skill-$B-$PP"* ]]
  SKILL_COPY_MARGIN=50 SKILL_COPY_NOW=4000 SKILL_COPY_STARTS="3100" run --separate-stderr "$SCRIPT" prune "$SKILL"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: removed skill-$B-$PP"* ]]
  [ ! -e "$SKILL/.worktrees/skill-$B-$PP" ]
}

@test "a copy missing from the log and from the links counts as ended at 0" {
  "$SCRIPT" use "$SKILL" "$A" 2>/dev/null
  git -C "$SKILL" worktree add -q --detach "$SKILL/.worktrees/skill-$B-$PP" "$B"
  SKILL_COPY_NOW=4000 SKILL_COPY_STARTS="1000" run --separate-stderr "$SCRIPT" prune "$SKILL"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: removed skill-$B-$PP"* ]]
  [ -d "$SKILL/.worktrees/skill-$A-$PP" ]
}

@test "prune never touches branch worktrees under .worktrees" {
  git -C "$SKILL" worktree add -q -b feature/9-x "$SKILL/.worktrees/9-x"
  use_a_b_c
  SKILL_COPY_NOW=4000 SKILL_COPY_STARTS="" run --separate-stderr "$SCRIPT" prune "$SKILL"
  [ "$status" -eq 0 ]
  [[ "$stderr" != *"9-x"* ]]
  [ -d "$SKILL/.worktrees/9-x" ]
}

@test "prune with no copy and no log does nothing" {
  run --separate-stderr "$SCRIPT" prune "$SKILL"
  [ "$status" -eq 0 ]
  [[ -z "$stderr" ]]
}

@test "use waits for the lock held by another run" {
  mkdir -p "$SKILL/.worktrees"
  flock "$SKILL/.worktrees/skill-copies.lock" -c "touch '$TMP/held'; sleep 3" &
  while [ ! -e "$TMP/held" ]; do sleep 0.1; done
  run --separate-stderr timeout 1 "$SCRIPT" use "$SKILL" "$A"
  [ "$status" -eq 124 ]
  [ ! -e "$SKILL/.worktrees/skill-$A-$PP" ]
  [ ! -e .claude ]
  wait
  run --separate-stderr "$SCRIPT" use "$SKILL" "$A"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: demo-skill -> skill-$A-$PP ($A)"* ]]
}

@test "status prints each copy with its project, linked or with its end time" {
  new_project "$WORK/proj2"
  P2=$(pid "$WORK/proj2")
  SKILL_COPY_NOW=1000 "$SCRIPT" use "$SKILL" "$A" 2>/dev/null
  cd "$PROJ"
  SKILL_COPY_NOW=1100 "$SCRIPT" use "$SKILL" "$A" 2>/dev/null
  SKILL_COPY_NOW=2000 "$SCRIPT" use "$SKILL" "$B" 2>/dev/null
  run --separate-stderr "$SCRIPT" status "$SKILL"
  [ "$status" -eq 0 ]
  [[ -z "$stderr" ]]
  [[ "$output" == *"copy: skill-$A-$P2 linked by $WORK/proj2"* ]]
  [[ "$output" == *"copy: skill-$B-$PP linked by $PROJ"* ]]
  [[ "$output" == *"copy: skill-$A-$PP of $PROJ ended 2000 ("* ]]
}

@test "status with no copy prints nothing" {
  run --separate-stderr "$SCRIPT" status "$SKILL"
  [ "$status" -eq 0 ]
  [[ -z "$stderr" ]]
  [[ -z "$output" ]]
}

# A fake pgrep and ps: one claude session that has run for $1 seconds.
fake_session() {
  mkdir -p "$TMP/bin"
  printf '#!/bin/sh\necho 4242\n' > "$TMP/bin/pgrep"
  printf '#!/bin/sh\necho "  %s"\n' "$1" > "$TMP/bin/ps"
  chmod +x "$TMP/bin/pgrep" "$TMP/bin/ps"
}

@test "without SKILL_COPY_STARTS, a real session keeps the copy it may use" {
  use_a_b_c
  fake_session 400
  # Now 3300: the session started at 2900; A ended at 2000, B at 3000, after 2780.
  unset SKILL_COPY_STARTS
  PATH="$TMP/bin:$PATH" SKILL_COPY_NOW=3300 run --separate-stderr "$SCRIPT" prune "$SKILL"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: removed skill-$A-$PP"* ]]
  [[ "$stderr" != *"removed skill-$B-$PP"* ]]
  [ -d "$SKILL/.worktrees/skill-$B-$PP" ]
}

@test "with --frozen run again, a linked file in the copy becomes a copy" {
  echo '{"k": 1}' > settings.json
  commit_hook "skill_copy_link \"\$2/settings.json\" \"\$1/settings.json\""
  "$SCRIPT" use "$SKILL" "$H" 2>/dev/null
  [ -L "$SKILL/.worktrees/skill-$H-$PP/settings.json" ]
  run --separate-stderr "$SCRIPT" use "$SKILL" "$H" --frozen
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: demo-skill -> skill-$H-$PP ($H)"* ]]
  [ ! -L "$SKILL/.worktrees/skill-$H-$PP/settings.json" ]
  [ "$(cat "$SKILL/.worktrees/skill-$H-$PP/settings.json")" = '{"k": 1}' ]
}

# --- tests of tools/agents.bats with no core replacement ---------------------
#
# tools/agents.sh and tools/agents.bats are removed (#23): skill-copy.sh makes
# the agent links. The old tests below are replaced by the edge cases above
# (named after the arrow), or dropped with --user.

# --- update (#26) ------------------------------------------------------------
#
# update <copy> brings the project's copy up to origin/main of the skill's
# repository, finding the repository, the project, the link directories and
# --frozen from the copy. It prints one line on stdout: updated, current or
# kept. Offline or refused, it warns and the links do not move.
# In setup, origin/main is at C.

copy_of() {
  echo "$SKILL/.worktrees/skill-$1-$PP"
}

@test "update moves a copy behind origin/main to origin/main and says updated" {
  "$SCRIPT" use "$SKILL" "$A" 2>/dev/null
  SKILL_COPY_NOW=2000 run --separate-stderr "$SCRIPT" update "$(copy_of "$A")"
  [ "$status" -eq 0 ]
  [ "$output" = "updated $A $C $(copy_of "$C")" ]
  [[ "$stderr" == *"skill-copy: demo-skill -> skill-$C-$PP (origin/main)"* ]]
  [ "$(readlink -f .claude/skills/demo-skill)" = "$(copy_of "$C")" ]
  [ "$(readlink -f .claude/agents/probe.md)" = "$(copy_of "$C")/agents/probe.md" ]
  [ "$(log)" = "$(printf '1000 skill-%s-%s %s\n2000 skill-%s-%s %s' "$A" "$PP" "$PROJ" "$C" "$PP" "$PROJ")" ]
}

@test "update of a copy at origin/main says current and changes nothing" {
  "$SCRIPT" use "$SKILL" "$C" 2>/dev/null
  before=$(snapshot; log)
  SKILL_COPY_NOW=2000 run --separate-stderr "$SCRIPT" update "$(copy_of "$C")"
  [ "$status" -eq 0 ]
  [ "$output" = "current $C" ]
  [ -z "$stderr" ]
  [ "$(snapshot; log)" = "$before" ]
}

@test "update of a copy ahead of origin/main says kept ahead and changes nothing" {
  (cd "$SKILL" && echo D > agents/probe.md && git commit -qam D)
  D=$(git -C "$SKILL" rev-parse HEAD | cut -c1-12)
  "$SCRIPT" use "$SKILL" "$D" 2>/dev/null
  before=$(snapshot; log)
  SKILL_COPY_NOW=2000 run --separate-stderr "$SCRIPT" update "$(copy_of "$D")"
  [ "$status" -eq 0 ]
  [ "$output" = "kept $D ahead" ]
  [ -z "$stderr" ]
  [ "$(snapshot; log)" = "$before" ]
}

@test "update of a copy diverged from origin/main says kept diverged and changes nothing" {
  (cd "$SKILL" && git checkout -q -b side "$A" && echo E > agents/probe.md && git commit -qam E && git checkout -q main)
  E=$(git -C "$SKILL" rev-parse side | cut -c1-12)
  "$SCRIPT" use "$SKILL" "$E" 2>/dev/null
  before=$(snapshot; log)
  SKILL_COPY_NOW=2000 run --separate-stderr "$SCRIPT" update "$(copy_of "$E")"
  [ "$status" -eq 0 ]
  [ "$output" = "kept $E diverged" ]
  [ -z "$stderr" ]
  [ "$(snapshot; log)" = "$before" ]
}

@test "offline, update warns, exits 1 and the links do not move, even with a newer local origin/main" {
  "$SCRIPT" use "$SKILL" "$A" 2>/dev/null
  git -C "$SKILL" remote set-url origin "$TMP/missing.git"
  before=$(snapshot; log)
  SKILL_COPY_NOW=2000 run --separate-stderr "$SCRIPT" update "$(copy_of "$A")"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [[ "$stderr" == *"skill-copy: warning: fetch from origin failed; links not moved"* ]]
  [ "$(snapshot; log)" = "$before" ]
}

@test "when use refuses origin/main, update passes the refusal on and the links do not move" {
  "$SCRIPT" use "$SKILL" "$A" 2>/dev/null
  (cd "$SKILL" && skill_md "" nameless && git commit -qam nameless && git push -q origin main)
  N=$(git -C "$SKILL" rev-parse HEAD | cut -c1-12)
  before=$(snapshot; log)
  SKILL_COPY_NOW=2000 run --separate-stderr "$SCRIPT" update "$(copy_of "$A")"
  [ "$status" -eq 3 ]
  [ -z "$output" ]
  [[ "$stderr" == *"skill-copy: SKILL.md at origin/main has no name: field"* ]]
  [[ "$stderr" == *"skill-copy: warning: update to $N failed; links not moved"* ]]
  [ "$(snapshot; log)" = "$before" ]
}

@test "update keeps the link directories the copy was installed with" {
  "$SCRIPT" use "$SKILL" "$A" --skills-dir ext/skills --agents-dir ext/agents 2>/dev/null
  SKILL_COPY_NOW=2000 run --separate-stderr "$SCRIPT" update "$(copy_of "$A")"
  [ "$status" -eq 0 ]
  [ "$output" = "updated $A $C $(copy_of "$C")" ]
  [[ "$stderr" == *"skill-copy: demo-skill -> skill-$C-$PP (origin/main)"* ]]
  [ "$(readlink ext/skills/demo-skill)" = "../../../demo-skill/.worktrees/skill-$C-$PP" ]
  [ "$(readlink ext/agents/probe.md)" = "../../../demo-skill/.worktrees/skill-$C-$PP/agents/probe.md" ]
  [ ! -e .claude ]
}

@test "use --frozen records a marker that update repeats, and use without --frozen removes it" {
  echo '{"k": 1}' > settings.json
  commit_hook "printf '%s\n' \"\${SKILL_COPY_FROZEN:-}\" > '$TMP/hook.frozen'
skill_copy_link \"\$2/settings.json\" \"\$1/settings.json\""
  "$SCRIPT" use "$SKILL" "$H" --frozen 2>/dev/null
  [ -f "$SKILL/.worktrees/skill-$H-$PP.frozen" ]
  (cd "$SKILL" && echo J > agents/probe.md && git commit -qam J && git push -q origin main)
  J=$(git -C "$SKILL" rev-parse HEAD | cut -c1-12)
  SKILL_COPY_NOW=2000 run --separate-stderr "$SCRIPT" update "$(copy_of "$H")"
  [ "$status" -eq 0 ]
  [ "$output" = "updated $H $J $(copy_of "$J")" ]
  [[ "$stderr" == *"skill-copy: demo-skill -> skill-$J-$PP (origin/main)"* ]]
  [ "$(cat "$TMP/hook.frozen")" = 1 ]
  [ ! -L "$(copy_of "$J")/settings.json" ]
  [ -f "$SKILL/.worktrees/skill-$J-$PP.frozen" ]
  SKILL_COPY_NOW=3000 "$SCRIPT" use "$SKILL" "$A" --frozen 2>/dev/null
  [ -f "$SKILL/.worktrees/skill-$A-$PP.frozen" ]
  SKILL_COPY_NOW=4000 "$SCRIPT" use "$SKILL" "$A" 2>/dev/null
  [ ! -e "$SKILL/.worktrees/skill-$A-$PP.frozen" ]
}

# --- update: edge cases (#26) ------------------------------------------------

@test "update refuses the copy of another project" {
  "$SCRIPT" use "$SKILL" "$A" 2>/dev/null
  new_project "$WORK/proj2"
  before=$(snapshot; log)
  run --separate-stderr "$SCRIPT" update "$(copy_of "$A")"
  [ "$status" -eq 3 ]
  [ -z "$output" ]
  [[ "$stderr" == *"skill-copy: skill-$A-$PP belongs to another project: $PROJ"* ]]
  [ "$(snapshot; log)" = "$before" ]
}

@test "update refuses to run outside the main worktree of the project" {
  "$SCRIPT" use "$SKILL" "$A" 2>/dev/null
  git worktree add -q -b feature/9-x .worktrees/9-x
  before=$(snapshot; log)
  cd .worktrees/9-x
  run --separate-stderr "$SCRIPT" update "$(copy_of "$A")"
  [ "$status" -eq 3 ]
  [ -z "$output" ]
  [[ "$stderr" == *"skill-copy: run from the main worktree of the project"* ]]
  [ "$(snapshot; log)" = "$before" ]
}

@test "update of a path that is not a copy exits 1" {
  "$SCRIPT" use "$SKILL" "$A" 2>/dev/null
  before=$(snapshot; log)
  for p in "$SKILL" "$TMP/missing" "$PROJ"; do
    run --separate-stderr "$SCRIPT" update "$p"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
    [[ "$stderr" == *"skill-copy: not a copy of a skill: $p"* ]]
  done
  [ "$(snapshot; log)" = "$before" ]
}

@test "when the hook of origin/main fails, update exits 1 and the links do not move" {
  "$SCRIPT" use "$SKILL" "$A" 2>/dev/null
  commit_hook "return 1"
  git -C "$SKILL" push -q origin main
  SKILL_COPY_NOW=2000 run --separate-stderr "$SCRIPT" update "$(copy_of "$A")"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [[ "$stderr" == *"skill-copy: the hook of skill-$H-$PP failed; links not moved"* ]]
  [[ "$stderr" == *"skill-copy: warning: update to $H failed; links not moved"* ]]
  [ "$(readlink -f .claude/skills/demo-skill)" = "$(copy_of "$A")" ]
  [ "$(readlink -f .claude/agents/probe.md)" = "$(copy_of "$A")/agents/probe.md" ]
  [ "$(log)" = "1000 skill-$A-$PP $PROJ" ]
}

@test "update keeps the old copy while the session that resolved it runs" {
  "$SCRIPT" use "$SKILL" "$A" 2>/dev/null
  SKILL_COPY_STARTS=1500 SKILL_COPY_NOW=2000 run --separate-stderr "$SCRIPT" update "$(copy_of "$A")"
  [ "$status" -eq 0 ]
  [ "$output" = "updated $A $C $(copy_of "$C")" ]
  [[ "$stderr" == *"skill-copy: demo-skill -> skill-$C-$PP (origin/main)"* ]]
  [ -d "$(copy_of "$A")" ]
}

@test "update of a copy with no record of its links uses the default link directories" {
  "$SCRIPT" use "$SKILL" "$A" 2>/dev/null
  rm "$SKILL/.worktrees/skill-$A-$PP.links"
  SKILL_COPY_NOW=2000 run --separate-stderr "$SCRIPT" update "$(copy_of "$A")"
  [ "$status" -eq 0 ]
  [ "$output" = "updated $A $C $(copy_of "$C")" ]
  [[ "$stderr" == *"skill-copy: demo-skill -> skill-$C-$PP (origin/main)"* ]]
  [ "$(readlink -f .claude/skills/demo-skill)" = "$(copy_of "$C")" ]
}

@test "prune removes the frozen marker with the copy" {
  "$SCRIPT" use "$SKILL" "$A" --frozen 2>/dev/null
  [ -f "$SKILL/.worktrees/skill-$A-$PP.frozen" ]
  SKILL_COPY_STARTS="" SKILL_COPY_NOW=2000 run --separate-stderr "$SCRIPT" use "$SKILL" "$C"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: removed skill-$A-$PP"* ]]
  [ ! -e "$SKILL/.worktrees/skill-$A-$PP.frozen" ]
  [ ! -e "$SKILL/.worktrees/skill-$A-$PP" ]
}

# --- Change History -------------------------------------------------------
# | PR     | Summary                                                       |
# |--------|---------------------------------------------------------------|
# | #25    | contract, refusals and edge cases; agents.bats converted (#23) |
