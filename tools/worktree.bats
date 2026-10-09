#!/usr/bin/env bats
# Contract of tools/worktree.sh (#126).
#
# Each test sets up a throwaway repository with its bare remote: nothing touches
# the real repository. The script reads the link list of the worktree it runs in.

bats_require_minimum_version 1.5.0

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/worktree.sh"
  TMP="$(mktemp -d)"
  ORIGIN="$TMP/origin.git"
  MAIN="$TMP/main"
  git init -q --bare -b main "$ORIGIN"
  git init -q -b main "$MAIN"
  cd "$MAIN"
  git config user.email test@example.invalid
  git config user.name test
  mkdir tools
  printf 'data\n' > tools/worktree.links
  printf '/data\n/.worktrees/\n' > .gitignore
  git add .gitignore tools/worktree.links
  git commit -qm init
  git remote add origin "$ORIGIN"
  git push -q -u origin main
  mkdir data
  echo secret > data/f
}

teardown() {
  rm -rf "$TMP"
}

# --- general contract ------------------------------------------------------
#
# Exit codes: 0 success; 1 check failed or git error; 2 usage; 3 refused for
# safety. Refusals are tested on code 3, so that a missing script — which exits
# with 127 — can never pass them.

@test "the script exists and is executable" {
  [ -x "$SCRIPT" ]
}

@test "an unknown subcommand exits with the usage code" {
  run --separate-stderr "$SCRIPT" unknown
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"usage: worktree.sh new <type> <number> <description> [base]"* ]]
}

# --- new -------------------------------------------------------------------

@test "new creates the branch and its worktree under .worktrees, links in place" {
  run --separate-stderr "$SCRIPT" new feature 7 trial
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"created: $MAIN/.worktrees/7-trial, branch feature/7-trial"* ]]
  [[ "$stderr" == *"linked: data"* ]]
  [ -d .worktrees/7-trial ]
  [ "$(git -C .worktrees/7-trial branch --show-current)" = "feature/7-trial" ]
  [ -L .worktrees/7-trial/data ]
  [ "$(readlink -f .worktrees/7-trial/data)" = "$(readlink -f "$MAIN/data")" ]
}

@test "new leaves a clean worktree: the link is ignored by git" {
  "$SCRIPT" new feature 7 trial
  [ -z "$(git -C .worktrees/7-trial status --porcelain)" ]
}

# --- link ------------------------------------------------------------------

@test "link is idempotent in a worktree" {
  "$SCRIPT" new feature 7 trial
  cd .worktrees/7-trial
  run --separate-stderr "$SCRIPT" link
  [ "$status" -eq 0 ]
  [ "$stderr" = "worktree: link list: tools/worktree.links" ]
  run --separate-stderr "$SCRIPT" link
  [ "$status" -eq 0 ]
  [ "$stderr" = "worktree: link list: tools/worktree.links" ]
  [ "$(readlink -f data)" = "$(readlink -f "$MAIN/data")" ]
}

@test "link repairs a deleted link" {
  "$SCRIPT" new feature 7 trial
  cd .worktrees/7-trial
  rm data
  run --separate-stderr "$SCRIPT" link
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"linked: data"* ]]
  [ -L data ]
}

@test "link refuses the main worktree and touches nothing there" {
  run --separate-stderr "$SCRIPT" link
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"link refuses the main worktree: it would replace data with links there"* ]]
  [ -d data ]
  [ ! -L data ]
  [ "$(cat data/f)" = secret ]
}

@test "link refuses the main worktree even when reached through a symbolic link" {
  ln -s "$MAIN" "$TMP/alias-main"
  cd "$TMP/alias-main"
  run --separate-stderr "$SCRIPT" link
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"link refuses the main worktree"* ]]
  [ ! -L "$MAIN/data" ]
}

@test "link recognises a worktree reached through a symbolic link" {
  "$SCRIPT" new feature 7 trial
  ln -s "$MAIN/.worktrees/7-trial" "$TMP/alias-wt"
  cd "$TMP/alias-wt"
  run --separate-stderr "$SCRIPT" link
  [ "$status" -eq 0 ]
  [ "$stderr" = "worktree: link list: tools/worktree.links" ]
}

@test "link never overwrites a real directory" {
  "$SCRIPT" new feature 7 trial
  cd .worktrees/7-trial
  rm data
  mkdir data
  echo local > data/g
  run --separate-stderr "$SCRIPT" link
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"data exists in the worktree and is not a link: nothing is overwritten"* ]]
  [ ! -L data ]
  [ "$(cat data/g)" = local ]
}

@test "link refuses a path that git does not ignore" {
  "$SCRIPT" new feature 7 trial
  cd .worktrees/7-trial
  printf 'data\ntracked\n' > tools/worktree.links
  mkdir "$MAIN/tracked"
  run --separate-stderr "$SCRIPT" link
  [ "$status" -eq 3 ]
  [[ "$stderr" == *'tracked is not ignored by git as a link: write "/tracked" in .gitignore, without a trailing slash'* ]]
  [ ! -e tracked ]
}

@test "link refuses a pattern with a trailing slash, which does not ignore a link" {
  printf 'data/\n/.worktrees/\n' > .gitignore
  git commit -qam "pattern with a trailing slash"
  git push -q
  run --separate-stderr "$SCRIPT" new feature 7 trial
  [ "$status" -eq 3 ]
  [[ "$stderr" == *'data is not ignored by git as a link: write "/data" in .gitignore, without a trailing slash'* ]]
  [ ! -L .worktrees/7-trial/data ]
}

# --- check -----------------------------------------------------------------

@test "check succeeds on healthy links and fails on a broken link" {
  "$SCRIPT" new feature 7 trial
  cd .worktrees/7-trial
  run --separate-stderr "$SCRIPT" check
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"links healthy"* ]]
  rm data
  ln -s "$TMP/nowhere" data
  run --separate-stderr "$SCRIPT" check
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"broken or misdirected link: data"* ]]
}

@test "check changes nothing" {
  "$SCRIPT" new feature 7 trial
  cd .worktrees/7-trial
  rm data
  run --separate-stderr "$SCRIPT" check
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"missing link: data"* ]]
  [ ! -e data ]
}

# --- reclaim ---------------------------------------------------------------

@test "reclaim brings the main worktree back to main when its branch is gone from the remote" {
  git switch -q -c feature/8-merged
  git commit -q --allow-empty -m work
  git push -q -u origin feature/8-merged
  git push -q origin --delete feature/8-merged
  run --separate-stderr "$SCRIPT" reclaim
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"feature/8-merged is gone from origin: back on main"* ]]
  [ "$(git branch --show-current)" = main ]
}

@test "reclaim leaves a branch still present on the remote" {
  git switch -q -c feature/9-ongoing
  git push -q -u origin feature/9-ongoing
  run --separate-stderr "$SCRIPT" reclaim
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"feature/9-ongoing still exists on origin: the main worktree stays on it"* ]]
  [ "$(git branch --show-current)" = feature/9-ongoing ]
}

@test "reclaim refuses to switch a modified main worktree" {
  git switch -q -c feature/8-merged
  git push -q -u origin feature/8-merged
  git push -q origin --delete feature/8-merged
  echo change >> .gitignore
  run --separate-stderr "$SCRIPT" reclaim
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"the main worktree has changes: feature/8-merged is not left"* ]]
  [ "$(git branch --show-current)" = feature/8-merged ]
}

@test "reclaim refuses to run in a linked worktree" {
  "$SCRIPT" new feature 7 trial
  cd .worktrees/7-trial
  run --separate-stderr "$SCRIPT" reclaim
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"reclaim runs only in the main worktree"* ]]
}

# --- drop ------------------------------------------------------------------

@test "drop removes a clean worktree and prunes" {
  "$SCRIPT" new feature 7 trial
  run --separate-stderr "$SCRIPT" drop 7-trial
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"removed: 7-trial"* ]]
  [ ! -e .worktrees/7-trial ]
  [ -z "$(git worktree list | grep 7-trial)" ]
}

@test "drop refuses a worktree that carries changes" {
  "$SCRIPT" new feature 7 trial
  echo x > .worktrees/7-trial/new.txt
  run --separate-stderr "$SCRIPT" drop 7-trial
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"7-trial has changes: nothing is removed"* ]]
  [ -d .worktrees/7-trial ]
}

@test "drop never deletes the target of a link" {
  "$SCRIPT" new feature 7 trial
  "$SCRIPT" drop 7-trial
  [ "$(cat "$MAIN/data/f")" = secret ]
}

# --- edge cases ------------------------------------------------------------

@test "link skips a target missing from the main worktree" {
  printf '/data\n/missing\n/.worktrees/\n' > .gitignore
  printf 'data\nmissing\n' > tools/worktree.links
  git commit -qam "missing target"
  git push -q
  run --separate-stderr "$SCRIPT" new feature 7 trial
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"target missing from the main worktree, skipped: missing"* ]]
  [[ "$stderr" == *"linked: data"* ]]
  [ ! -e .worktrees/7-trial/missing ]
  [ -L .worktrees/7-trial/data ]
}

@test "link links a path nested under a tracked directory" {
  mkdir -p site
  echo tracked > site/page
  printf '/data\n/site/cache\n/.worktrees/\n' > .gitignore
  printf 'data\nsite/cache\n' > tools/worktree.links
  git add site/page .gitignore tools/worktree.links
  git commit -qm "nested path"
  git push -q
  mkdir site/cache
  run --separate-stderr "$SCRIPT" new feature 7 trial
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"linked: site/cache"* ]]
  [ "$(readlink -f .worktrees/7-trial/site/cache)" = "$(readlink -f "$MAIN/site/cache")" ]
  [ -z "$(git -C .worktrees/7-trial status --porcelain)" ]
}

@test "new refuses an existing worktree" {
  "$SCRIPT" new feature 7 trial
  run --separate-stderr "$SCRIPT" new bug 7 trial
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"worktree already exists: $MAIN/.worktrees/7-trial"* ]]
}

@test "new rejects an invalid type or description" {
  run --separate-stderr "$SCRIPT" new project 7 trial
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"unknown type: project (expected: feature bug test doc)"* ]]
  run --separate-stderr "$SCRIPT" new feature 7 "Accented Trïal"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"invalid description: Accented Trïal (lowercase, digits, hyphens)"* ]]
}

@test "new does not track origin/main: the branch has no upstream before its push" {
  "$SCRIPT" new feature 7 trial
  run git -C .worktrees/7-trial config --get branch.feature/7-trial.remote
  [ "$status" -ne 0 ]
}

@test "new rejects a non-numeric issue number" {
  run --separate-stderr "$SCRIPT" new feature x7 trial
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"invalid number: x7"* ]]
}

@test "check in the main worktree has nothing to check" {
  run --separate-stderr "$SCRIPT" check
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"main worktree: no links to check"* ]]
}

@test "reclaim on main does nothing" {
  run --separate-stderr "$SCRIPT" reclaim
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"already on main"* ]]
}

@test "reclaim leaves a branch without upstream" {
  git switch -q -c feature/10-local
  run --separate-stderr "$SCRIPT" reclaim
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"feature/10-local has no upstream: the main worktree stays on it"* ]]
  [ "$(git branch --show-current)" = feature/10-local ]
}

@test "drop rejects an invalid name" {
  run --separate-stderr "$SCRIPT" drop trial
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"invalid name: trial"* ]]
}

@test "drop fails on a worktree that does not exist" {
  run --separate-stderr "$SCRIPT" drop 7-trial
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"worktree not found: $MAIN/.worktrees/7-trial"* ]]
}

@test "drop refuses to remove the worktree it runs in" {
  "$SCRIPT" new feature 7 trial
  cd .worktrees/7-trial
  run --separate-stderr "$SCRIPT" drop 7-trial
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"drop does not remove the worktree it runs in"* ]]
  [ -d "$MAIN/.worktrees/7-trial" ]
}

@test "new refuses when .worktrees is not ignored by git" {
  printf '/data\n' > .gitignore
  git commit -qam "no .worktrees entry"
  run --separate-stderr "$SCRIPT" new feature 7 trial
  [ "$status" -eq 3 ]
  [[ "$stderr" == *".worktrees/ is not ignored by git in the main worktree"* ]]
  [ ! -e .worktrees/7-trial ]
}

# --- Change History -------------------------------------------------------
# | PR     | Summary                                                       |
# |--------|---------------------------------------------------------------|
# | #6     | English names; stderr asserted on every run; edge cases (#3)  |
# | (this PR) | clean link runs print exactly the list line (#4)          |
