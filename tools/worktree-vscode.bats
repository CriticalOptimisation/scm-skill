#!/usr/bin/env bats
# tools/worktree.sh new shows the new worktree in VS Code (#7).
#
# The session's shell is not a VS Code terminal, so VS Code does not see the
# worktrees it creates. In a session started from VS Code (VSCODE_IPC_HOOK_CLI
# set, code on the PATH), new runs `code -r <worktree>/.git`; elsewhere the step
# is skipped without a message. A failing code only warns.
#
# The real code is never reached: every test runs with a PATH that holds no
# directory providing `code`, plus, where a test wants one, a stub that records
# every call: its argument count, then its arguments, one per line. Arguments
# and stderr are compared as whole lines, never as substrings. Stderr goes to a
# file rather than through `run --separate-stderr`, whose $stderr loses
# trailing blanks.

bats_require_minimum_version 1.5.0

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/worktree.sh"
  TMP="$(mktemp -d)"
  ORIGIN="$TMP/origin.git"
  MAIN="$TMP/main"
  WT="$MAIN/.worktrees/7-trial"
  STUB_DIR="$TMP/stub"
  CODE_LOG="$TMP/code.log"
  ERR="$TMP/stderr"
  export CODE_LOG ERR

  # A PATH without the real code.
  local dir clean=
  local -a dirs
  IFS=: read -ra dirs <<< "$PATH"
  for dir in "${dirs[@]}"; do
    [[ -n $dir && ! -x $dir/code ]] && clean+=${clean:+:}$dir
  done
  PATH=$clean
  [ -z "$(command -v code)" ]

  mkdir "$STUB_DIR"
  cat > "$STUB_DIR/code" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$#" "$@" >> "$CODE_LOG"
exit "${CODE_STATUS:-0}"
STUB
  chmod +x "$STUB_DIR/code"

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

  CREATED=(
    "worktree: created: $WT, branch feature/7-trial"
    "worktree: link list: tools/worktree.links"
    "worktree: linked: data"
  )
}

teardown() {
  rm -rf "$TMP"
}

in_vscode() {
  export VSCODE_IPC_HOOK_CLI="$TMP/vscode-ipc.sock"
}

outside_vscode() {
  unset VSCODE_IPC_HOOK_CLI
}

with_stub() {
  PATH="$STUB_DIR:$PATH"
}

# Runs the script with its stderr in $ERR.
run_script() {
  run bash -c '"$0" "$@" 2>"$ERR"' "$SCRIPT" "$@"
}

# Lines of stderr, compared whole with the expected lines.
stderr_is() {
  local -a got=()
  mapfile -t got < "$ERR"
  [ "${#got[@]}" -eq "$#" ] || { printf 'stderr: %s\n' "${got[@]}"; return 1; }
  local i=0 line
  for line in "$@"; do
    [ "${got[i]}" = "$line" ] || { printf 'line %d: %s\n' "$i" "${got[i]}"; return 1; }
    i=$((i + 1))
  done
}

# One call of the stub, with exactly these arguments, compared whole.
code_called_with() {
  [ -f "$CODE_LOG" ] || { echo "code was not called"; return 1; }
  local -a got
  mapfile -t got < "$CODE_LOG"
  [ "${#got[@]}" -eq $(($# + 1)) ] || { printf 'log: %s\n' "${got[@]}"; return 1; }
  [ "${got[0]}" = "$#" ] || { echo "argument count: ${got[0]}"; return 1; }
  got=("${got[@]:1}")
  local i=0 arg
  for arg in "$@"; do
    [ "${got[i]}" = "$arg" ] || { printf 'arg %d: %s\n' "$i" "${got[i]}"; return 1; }
    i=$((i + 1))
  done
}

code_not_called() {
  [ ! -e "$CODE_LOG" ]
}

@test "the fixture's PATH reaches the stub only when a test adds it" {
  [ -z "$(command -v code)" ]
  with_stub
  [ "$(command -v code)" = "$STUB_DIR/code" ]
}

@test "in VS Code, new opens the worktree's .git file once" {
  in_vscode
  with_stub
  run_script new feature 7 trial
  [ "$status" -eq 0 ]
  code_called_with -r "$WT/.git"
  stderr_is "${CREATED[@]}" "worktree: opened in VS Code: $WT/.git"
  [ -f "$WT/.git" ]
  [ -L "$WT/data" ]
}

@test "outside VS Code, new does not call code and says nothing about it" {
  outside_vscode
  with_stub
  run_script new feature 7 trial
  [ "$status" -eq 0 ]
  code_not_called
  stderr_is "${CREATED[@]}"
}

@test "in VS Code without code on the PATH, new succeeds silently" {
  in_vscode
  run_script new feature 7 trial
  [ "$status" -eq 0 ]
  stderr_is "${CREATED[@]}"
  [ -d "$WT" ]
  [ -L "$WT/data" ]
}

@test "a failing code only warns: new succeeds and keeps the worktree" {
  in_vscode
  with_stub
  export CODE_STATUS=1
  run_script new feature 7 trial
  [ "$status" -eq 0 ]
  code_called_with -r "$WT/.git"
  stderr_is "${CREATED[@]}" \
    "worktree: warning: VS Code could not open $WT/.git; reload the window to list the worktree in Source Control Repositories"
  [ -d "$WT" ]
  [ -L "$WT/data" ]
}

@test "a refused new does not call code" {
  in_vscode
  with_stub
  run_script new project 7 trial
  [ "$status" -eq 2 ]
  stderr_is "worktree: unknown type: project (expected: feature bug test doc)"
  code_not_called
  mkdir -p "$WT"
  run_script new feature 7 trial
  [ "$status" -eq 3 ]
  stderr_is "worktree: worktree already exists: $WT"
  code_not_called
}

@test "drop does not call code" {
  outside_vscode
  "$SCRIPT" new feature 7 trial 2>/dev/null
  in_vscode
  with_stub
  run_script drop 7-trial
  [ "$status" -eq 0 ]
  stderr_is "worktree: removed: 7-trial"
  code_not_called
  [ ! -e "$WT" ]
}
