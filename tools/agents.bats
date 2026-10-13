#!/usr/bin/env bats
# Contract of tools/agents.sh (#20).
#
# Each test sets up a throwaway skill (its own copy of the script and a fake
# agent definition) and a throwaway project: nothing touches the real
# repository or the real ~/.claude.

bats_require_minimum_version 1.5.0

setup() {
  TMP="$(mktemp -d)"
  SKILL="$TMP/skill"
  mkdir -p "$SKILL/tools" "$SKILL/agents"
  cp "$BATS_TEST_DIRNAME/agents.sh" "$SKILL/tools/" 2>/dev/null || true
  SCRIPT="$SKILL/tools/agents.sh"
  printf -- '---\nname: probe\nmodel: opus\n---\nprobe\n' > "$SKILL/agents/probe.md"
  export HOME="$TMP/home"
  mkdir -p "$HOME"
  MAIN="$TMP/main"
  git init -q -b main "$MAIN"
  cd "$MAIN"
  git config user.email test@example.invalid
  git config user.name test
  printf '/.worktrees/\n' > .gitignore
  git add .gitignore
  git commit -qm init
}

teardown() {
  rm -rf "$TMP"
}

# --- general contract ------------------------------------------------------
#
# Exit codes: 0 success; 1 failure; 2 usage; 3 refused for safety. Refusals
# are tested on code 3, so that a missing script — which exits with 127 — can
# never pass them.

@test "the script exists and is executable" {
  [ -x "$SCRIPT" ]
}

@test "an unknown subcommand exits with the usage code" {
  run --separate-stderr "$SCRIPT" unknown
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"usage: agents.sh link [--user]"* ]]
}

# --- link: project ---------------------------------------------------------

@test "link links each agent definition into the project's .claude/agents" {
  run --separate-stderr "$SCRIPT" link
  [ "$status" -eq 0 ]
  [ "$stderr" = "agents: linked: $MAIN/.claude/agents/probe.md" ]
  [ -L .claude/agents/probe.md ]
  [ "$(readlink .claude/agents/probe.md)" = "$(realpath "$SKILL/agents/probe.md")" ]
}

@test "link keeps the project clean: the link is excluded from git" {
  "$SCRIPT" link
  grep -qxF '/.claude/agents/probe.md' .git/info/exclude
  [ -z "$(git status --porcelain)" ]
}

@test "link is idempotent" {
  "$SCRIPT" link
  run --separate-stderr "$SCRIPT" link
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ "$(grep -cxF '/.claude/agents/probe.md' .git/info/exclude)" -eq 1 ]
  [ "$(readlink .claude/agents/probe.md)" = "$(realpath "$SKILL/agents/probe.md")" ]
}

@test "link run from a branch worktree links into the main worktree" {
  git worktree add -q -b feature/7-trial .worktrees/7-trial
  cd .worktrees/7-trial
  run --separate-stderr "$SCRIPT" link
  [ "$status" -eq 0 ]
  [ "$stderr" = "agents: linked: $MAIN/.claude/agents/probe.md" ]
  [ -L "$MAIN/.claude/agents/probe.md" ]
  [ ! -e .claude/agents/probe.md ]
}

# --- link: user ------------------------------------------------------------

@test "link --user links into ~/.claude/agents and leaves the project alone" {
  run --separate-stderr "$SCRIPT" link --user
  [ "$status" -eq 0 ]
  [ "$stderr" = "agents: linked: $HOME/.claude/agents/probe.md" ]
  [ "$(readlink "$HOME/.claude/agents/probe.md")" = "$(realpath "$SKILL/agents/probe.md")" ]
  [ ! -e .claude ]
}

# --- refusals --------------------------------------------------------------

@test "link never overwrites a regular file" {
  mkdir -p .claude/agents
  echo mine > .claude/agents/probe.md
  run --separate-stderr "$SCRIPT" link
  [ "$status" -eq 3 ]
  [[ "$stderr" == *".claude/agents/probe.md exists and is not a link to $(realpath "$SKILL/agents/probe.md"): nothing is overwritten"* ]]
  [ ! -L .claude/agents/probe.md ]
  [ "$(cat .claude/agents/probe.md)" = mine ]
}

@test "link never replaces a link to another file" {
  mkdir -p .claude/agents
  echo other > "$TMP/other.md"
  ln -s "$TMP/other.md" .claude/agents/probe.md
  run --separate-stderr "$SCRIPT" link
  [ "$status" -eq 3 ]
  [[ "$stderr" == *".claude/agents/probe.md exists and is not a link to $(realpath "$SKILL/agents/probe.md"): nothing is overwritten"* ]]
  [ "$(readlink .claude/agents/probe.md)" = "$TMP/other.md" ]
}

# --- Change History -------------------------------------------------------
# | PR     | Summary                                                       |
# |--------|---------------------------------------------------------------|
