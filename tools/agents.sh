#!/usr/bin/env bash
# Links the skill's agent definitions where Claude Code loads them (#20).
#
# The skill is linked into projects, not copied (#4); its agents are linked
# the same way. Project mode targets .claude/agents/ of the main worktree and
# excludes each link from git; --user targets ~/.claude/agents/.
#
# Exit codes: 0 success; 1 failure; 2 usage; 3 refused for safety.
set -uo pipefail

readonly E_FAIL=1 E_USAGE=2 E_REFUSED=3
SELF=$(realpath "${BASH_SOURCE[0]}")
readonly SELF
AGENTS=$(dirname "$(dirname "$SELF")")/agents
readonly AGENTS

say() { printf 'agents: %s\n' "$*" >&2; }
die() { local code=$1; shift; say "$@"; exit "$code"; }
usage() {
  die "$E_USAGE" "usage: agents.sh link [--user]"
}

# Root of the main worktree: the parent of the common git directory.
main_root() {
  local common
  common=$(git rev-parse --git-common-dir 2>/dev/null) || die "$E_FAIL" "not in a git repository"
  dirname "$(realpath "$common")"
}

cmd_link() {
  local scope=$1 dest root="" exclude="" src name here entry
  local -a srcs=()
  if [[ $scope == user ]]; then
    dest=$HOME/.claude/agents
  else
    root=$(main_root) || exit
    dest=$root/.claude/agents
    exclude=$(realpath "$(git rev-parse --git-common-dir)")/info/exclude
  fi
  shopt -s nullglob
  srcs=("$AGENTS"/*.md)
  shopt -u nullglob
  (( ${#srcs[@]} )) || die "$E_FAIL" "no agent definitions in $AGENTS"

  # Validate everything before writing anything.
  for src in "${srcs[@]}"; do
    here=$dest/$(basename -- "$src")
    if [[ -e $here || -L $here ]] && [[ ! -L $here || $(readlink -- "$here") != "$src" ]]; then
      die "$E_REFUSED" "$here exists and is not a link to $src: nothing is overwritten"
    fi
  done

  mkdir -p -- "$dest" || die "$E_FAIL" "cannot create $dest"
  for src in "${srcs[@]}"; do
    name=$(basename -- "$src")
    here=$dest/$name
    if [[ ! -L $here ]]; then
      ln -s -- "$src" "$here" || die "$E_FAIL" "cannot link: $here"
      say "linked: $here"
    fi
    [[ -n $root ]] || continue
    entry=/.claude/agents/$name
    git -C "$root" check-ignore -q -- "${entry#/}" && continue
    mkdir -p -- "$(dirname -- "$exclude")" || die "$E_FAIL" "cannot create $(dirname -- "$exclude")"
    printf '%s\n' "$entry" >> "$exclude" || die "$E_FAIL" "cannot write $exclude"
  done
}

dispatch() {
  (( $# >= 1 )) || usage
  local cmd=$1
  shift
  case $cmd in
    link)
      case $# in
        0) cmd_link project ;;
        1) [[ $1 == --user ]] || usage; cmd_link user ;;
        *) usage ;;
      esac ;;
    *) usage ;;
  esac
}

dispatch "$@"

# --- Change History -------------------------------------------------------
# | PR     | Summary                                                       |
# |--------|---------------------------------------------------------------|
