#!/usr/bin/env bats
# Where tools/worktree.sh finds the project's link list (#4).
#
# The list is a project file: tools/worktree.links, or else .worktree-links at
# the project root. Both present: the first is used, with a warning on every
# run. Neither: nothing to link, and no error. The core cases of worktree.bats
# run here once per location.
#
# Each test builds a throwaway repository and its bare remote, with NO list
# committed: each test writes its own with write_list, which checks that the
# file landed where intended, so a misplaced fixture fails instead of leaving
# the script nothing to do.
#
# Messages are matched as whole stderr lines, never as substrings: the two
# list names overlap (`worktree.links` is in both).

bats_require_minimum_version 1.5.0

readonly TOOLS_LIST=tools/worktree.links
readonly ROOT_LIST=.worktree-links
readonly BOTH_WARNING="worktree: warning: both tools/worktree.links and .worktree-links exist; using tools/worktree.links — remove one"
readonly NO_LIST="worktree: no link list: nothing to link"

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/worktree.sh"
  TMP="$(mktemp -d)"
  ORIGIN="$TMP/origin.git"
  MAIN="$TMP/main"
  WT="$MAIN/.worktrees/7-try"
  git init -q --bare -b main "$ORIGIN"
  git init -q -b main "$MAIN"
  cd "$MAIN"
  git config user.email test@example.invalid
  git config user.name test
  printf '/data\n/other\n/.worktrees/\n' > .gitignore
  git add .gitignore
  git commit -qm init
  git remote add origin "$ORIGIN"
  git push -q -u origin main
  mkdir data other
  echo secret > data/f
  echo other > other/f
}

teardown() {
  rm -rf "$TMP"
}

# write_list <location> <path>... — commits a link list at <location>.
write_list() {
  local location=$1
  shift
  mkdir -p "$(dirname "$location")"
  printf '%s\n' "$@" > "$location"
  git add "$location"
  git commit -qm "link list at $location"
  git push -q
  [ -f "$MAIN/$location" ]
}

# has_line <text> <line> — <line> is one whole line of <text>.
has_line() {
  grep -qFx -- "$2" <<< "$1"
}

# The line naming the list read, for <location>.
list_line() {
  printf 'worktree: link list: %s' "$1"
}

# --- core cases, once per location -------------------------------------------

core_new_links() {
  write_list "$1" data
  run --separate-stderr "$SCRIPT" new feature 7 try
  [ "$status" -eq 0 ]
  [ -f "$WT/$1" ]
  [ -L "$WT/data" ]
  [ "$(readlink -f "$WT/data")" = "$(readlink -f "$MAIN/data")" ]
  has_line "$stderr" "$(list_line "$1")"
  ! has_line "$stderr" "$BOTH_WARNING" || false
  [ -z "$(git -C "$WT" status --porcelain)" ]
}

core_link_idempotent() {
  write_list "$1" data
  "$SCRIPT" new feature 7 try
  cd "$WT"
  run --separate-stderr "$SCRIPT" link
  [ "$status" -eq 0 ]
  has_line "$stderr" "$(list_line "$1")"
  run --separate-stderr "$SCRIPT" link
  [ "$status" -eq 0 ]
  has_line "$stderr" "$(list_line "$1")"
  [ "$(readlink -f data)" = "$(readlink -f "$MAIN/data")" ]
}

core_link_repairs() {
  write_list "$1" data
  "$SCRIPT" new feature 7 try
  cd "$WT"
  rm data
  run --separate-stderr "$SCRIPT" link
  [ "$status" -eq 0 ]
  has_line "$stderr" "$(list_line "$1")"
  [ "$(readlink -f data)" = "$(readlink -f "$MAIN/data")" ]
}

core_check() {
  write_list "$1" data
  "$SCRIPT" new feature 7 try
  cd "$WT"
  run --separate-stderr "$SCRIPT" check
  [ "$status" -eq 0 ]
  has_line "$stderr" "$(list_line "$1")"
  rm data
  ln -s "$TMP/nowhere" data
  run --separate-stderr "$SCRIPT" check
  [ "$status" -eq 1 ]
  has_line "$stderr" "$(list_line "$1")"
}

core_drop_keeps_targets() {
  write_list "$1" data
  run --separate-stderr "$SCRIPT" new feature 7 try
  [ "$status" -eq 0 ]
  has_line "$stderr" "$(list_line "$1")"
  run "$SCRIPT" drop 7-try
  [ "$status" -eq 0 ]
  [ ! -e "$WT" ]
  [ "$(cat "$MAIN/data/f")" = secret ]
}

@test "tools/worktree.links: new links the listed paths and names the list" { core_new_links "$TOOLS_LIST"; }
@test ".worktree-links: new links the listed paths and names the list" { core_new_links "$ROOT_LIST"; }

@test "tools/worktree.links: link is idempotent" { core_link_idempotent "$TOOLS_LIST"; }
@test ".worktree-links: link is idempotent" { core_link_idempotent "$ROOT_LIST"; }

@test "tools/worktree.links: link repairs a removed link" { core_link_repairs "$TOOLS_LIST"; }
@test ".worktree-links: link repairs a removed link" { core_link_repairs "$ROOT_LIST"; }

@test "tools/worktree.links: check passes on healthy links, fails on a broken one" { core_check "$TOOLS_LIST"; }
@test ".worktree-links: check passes on healthy links, fails on a broken one" { core_check "$ROOT_LIST"; }

@test "tools/worktree.links: drop never deletes a link target" { core_drop_keeps_targets "$TOOLS_LIST"; }
@test ".worktree-links: drop never deletes a link target" { core_drop_keeps_targets "$ROOT_LIST"; }

# --- both lists present ------------------------------------------------------

@test "both lists: tools/worktree.links wins, and new, link and check warn" {
  write_list "$TOOLS_LIST" data
  write_list "$ROOT_LIST" other
  run --separate-stderr "$SCRIPT" new feature 7 try
  [ "$status" -eq 0 ]
  has_line "$stderr" "$BOTH_WARNING"
  has_line "$stderr" "$(list_line "$TOOLS_LIST")"
  [ -L "$WT/data" ]
  [ ! -e "$WT/other" ]
  cd "$WT"
  run --separate-stderr "$SCRIPT" link
  [ "$status" -eq 0 ]
  has_line "$stderr" "$BOTH_WARNING"
  run --separate-stderr "$SCRIPT" check
  [ "$status" -eq 0 ]
  has_line "$stderr" "$BOTH_WARNING"
  [ ! -e other ]
}

# --- no list -----------------------------------------------------------------

@test "no list: new, link and check succeed, say so, and link nothing" {
  [ ! -e "$MAIN/$TOOLS_LIST" ]
  [ ! -e "$MAIN/$ROOT_LIST" ]
  run --separate-stderr "$SCRIPT" new feature 7 try
  [ "$status" -eq 0 ]
  has_line "$stderr" "$NO_LIST"
  [ -d "$WT" ]
  cd "$WT"
  run --separate-stderr "$SCRIPT" link
  [ "$status" -eq 0 ]
  has_line "$stderr" "$NO_LIST"
  run --separate-stderr "$SCRIPT" check
  [ "$status" -eq 0 ]
  has_line "$stderr" "$NO_LIST"
  [ -z "$(find "$WT" -path "$WT/.git" -prune -o -type l -print)" ]
}

# --- edge cases --------------------------------------------------------------

@test "no list: drop removes the worktree and says only that" {
  "$SCRIPT" new feature 7 try
  run --separate-stderr "$SCRIPT" drop 7-try
  [ "$status" -eq 0 ]
  [ "$stderr" = "worktree: removed: 7-try" ]
  [ ! -e "$WT" ]
}

@test "both lists: drop does not warn, and keeps the targets" {
  write_list "$TOOLS_LIST" data
  write_list "$ROOT_LIST" other
  "$SCRIPT" new feature 7 try
  run --separate-stderr "$SCRIPT" drop 7-try
  [ "$status" -eq 0 ]
  [ "$stderr" = "worktree: removed: 7-try" ]
  [ "$(cat "$MAIN/data/f")" = secret ]
  [ "$(cat "$MAIN/other/f")" = other ]
}

@test ".worktree-links: comments and trailing slashes are read as in tools/worktree.links" {
  write_list "$ROOT_LIST" "# untracked data" "data/   # with a comment" ""
  run --separate-stderr "$SCRIPT" new feature 7 try
  [ "$status" -eq 0 ]
  has_line "$stderr" "$(list_line "$ROOT_LIST")"
  has_line "$stderr" "worktree: linked: data"
  [ "$(readlink -f "$WT/data")" = "$(readlink -f "$MAIN/data")" ]
}

@test ".worktree-links with only comments: named, nothing linked, no error" {
  write_list "$ROOT_LIST" "# nothing yet"
  run --separate-stderr "$SCRIPT" new feature 7 try
  [ "$status" -eq 0 ]
  has_line "$stderr" "$(list_line "$ROOT_LIST")"
  ! has_line "$stderr" "$NO_LIST" || false
  [ -z "$(find "$WT" -path "$WT/.git" -prune -o -type l -print)" ]
}

# --- Change History -------------------------------------------------------
# | PR     | Summary                                                       |
# |--------|---------------------------------------------------------------|
# | #9     | where the project's link list is found (#4)                   |
