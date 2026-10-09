#!/usr/bin/env bash
# One worktree per branch (#126).
#
# The main worktree stays on main; each branch lives under .worktrees/.
# The untracked paths listed in the project's link list (tools/worktree.links,
# else .worktree-links) are linked there from the main worktree. Contract and
# safeguards: the skill's references/test-driven-development.md.
#
# Exit codes: 0 success; 1 check failed or git error; 2 usage;
# 3 refused for safety.
set -uo pipefail

readonly E_FAIL=1 E_USAGE=2 E_REFUSED=3
readonly TYPES="feature bug test doc"
SELF=$(realpath "${BASH_SOURCE[0]}")
readonly SELF

say() { printf 'worktree: %s\n' "$*" >&2; }
die() { local code=$1; shift; say "$@"; exit "$code"; }
usage() {
  die "$E_USAGE" "usage: worktree.sh new <type> <number> <description> [base]
       worktree.sh link | check | reclaim
       worktree.sh drop <number>-<description>"
}

toplevel() {
  git rev-parse --show-toplevel 2>/dev/null || die "$E_FAIL" "not in a git repository"
}

# "main" or "linked". Two tests internal to git, never a path: symbolic links
# make paths lie. If the two disagree, stop.
checkout_kind() {
  local top gitdir common dotgit
  top=$(toplevel) || exit
  gitdir=$(cd "$top" && realpath "$(git rev-parse --git-dir)") || die "$E_FAIL" "git rev-parse failed"
  common=$(cd "$top" && realpath "$(git rev-parse --git-common-dir)") || die "$E_FAIL" "git rev-parse failed"
  if [[ -f $top/.git ]]; then dotgit=file
  elif [[ -d $top/.git ]]; then dotgit=directory
  else dotgit=missing
  fi
  if [[ $gitdir != "$common" && $dotgit == file ]]; then
    echo linked
  elif [[ $gitdir == "$common" && $dotgit == directory ]]; then
    echo main
  else
    die "$E_REFUSED" "inconsistent detection (git-dir $gitdir, common-dir $common, .git $dotgit) — stopping"
  fi
}

# Root of the main worktree: the parent of the common git directory.
main_root() {
  local common
  common=$(git rev-parse --git-common-dir) || die "$E_FAIL" "git rev-parse failed"
  dirname "$(realpath "$common")"
}

# Name of the link list in the given checkout: tools/worktree.links, else
# .worktree-links; nothing if neither exists. Warns when both do.
list_file() {
  if [[ -f $1/tools/worktree.links ]]; then
    [[ -f $1/.worktree-links ]] &&
      say "warning: both tools/worktree.links and .worktree-links exist; using tools/worktree.links — remove one"
    echo tools/worktree.links
  elif [[ -f $1/.worktree-links ]]; then
    echo .worktree-links
  fi
}

# Paths to link, read in the given checkout: one per line, without comments
# or trailing slash. No list: nothing to link.
link_list() {
  local name file line
  name=$(list_file "$1")
  if [[ -z $name ]]; then
    say "no link list: nothing to link"
    return 0
  fi
  say "link list: $name"
  file=$1/$name
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%%#*}
    line=$(sed 's/^[[:space:]]*//; s/[[:space:]]*$//' <<< "$line")
    line=${line%/}
    if [[ -n $line ]]; then printf '%s\n' "$line"; fi
  done < "$file"
}

safe_path() { [[ $1 != /* && /$1/ != */../* ]]; }

same_target() { [[ $(realpath -q -- "$1") == "$(realpath -- "$2")" ]]; }

cmd_link() {
  local kind top root list p target here rel
  local -a paths=()
  kind=$(checkout_kind) || exit
  [[ $kind == linked ]] || die "$E_REFUSED" "link refuses the main worktree: it would replace data with links there"
  top=$(toplevel) || exit
  root=$(main_root) || exit
  list=$(link_list "$top") || exit
  [[ -n $list ]] && mapfile -t paths <<< "$list"

  # Validate everything before writing anything.
  for p in "${paths[@]}"; do
    safe_path "$p" || die "$E_REFUSED" "path refused: $p"
    git -C "$top" check-ignore -q -- "$p"
    case $? in
      0) ;;
      1) die "$E_REFUSED" "$p is not ignored by git as a link: write \"/$p\" in .gitignore, without a trailing slash" ;;
      *) die "$E_FAIL" "git check-ignore failed on $p" ;;
    esac
    if [[ -e $top/$p && ! -L $top/$p ]]; then
      die "$E_REFUSED" "$p exists in the worktree and is not a link: nothing is overwritten"
    fi
  done

  for p in "${paths[@]}"; do
    target=$root/$p
    here=$top/$p
    if [[ ! -e $target ]]; then
      say "target missing from the main worktree, skipped: $p"
      continue
    fi
    if [[ -L $here ]]; then
      same_target "$here" "$target" && continue
      rm -- "$here" || die "$E_FAIL" "cannot remove broken link: $p"
    fi
    mkdir -p -- "$(dirname -- "$here")" || die "$E_FAIL" "cannot create directory for $p"
    rel=$(realpath --relative-to="$(realpath -- "$(dirname -- "$here")")" -- "$(realpath -- "$target")") ||
      die "$E_FAIL" "cannot compute relative path for $p"
    ln -s -- "$rel" "$here" || die "$E_FAIL" "cannot link: $p"
    say "linked: $p"
  done
}

cmd_check() {
  local kind top root list p target here bad=0
  local -a paths=()
  kind=$(checkout_kind) || exit
  if [[ $kind == main ]]; then
    say "main worktree: no links to check"
    return 0
  fi
  top=$(toplevel) || exit
  root=$(main_root) || exit
  list=$(link_list "$top") || exit
  [[ -n $list ]] && mapfile -t paths <<< "$list"
  for p in "${paths[@]}"; do
    target=$root/$p
    here=$top/$p
    if [[ ! -e $target ]]; then
      say "target missing from the main worktree: $p"
    elif ! git -C "$top" check-ignore -q -- "$p"; then
      say "not ignored by git: $p"; bad=1
    elif [[ ! -L $here ]]; then
      say "missing link: $p"; bad=1
    elif ! same_target "$here" "$target"; then
      say "broken or misdirected link: $p"; bad=1
    fi
  done
  (( bad == 0 )) || exit "$E_FAIL"
  say "links healthy"
}

cmd_new() {
  (( $# == 3 || $# == 4 )) || usage
  local type=$1 num=$2 slug=$3 base=${4:-origin/main} root name dir branch
  [[ " $TYPES " == *" $type "* ]] || die "$E_USAGE" "unknown type: $type (expected: $TYPES)"
  [[ $num =~ ^[0-9]+$ ]] || die "$E_USAGE" "invalid number: $num"
  [[ $slug =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || die "$E_USAGE" "invalid description: $slug (lowercase, digits, hyphens)"
  root=$(main_root) || exit
  name=$num-$slug
  dir=$root/.worktrees/$name
  branch=$type/$name
  [[ -e $dir ]] && die "$E_REFUSED" "worktree already exists: $dir"
  mkdir -p -- "$root/.worktrees" || die "$E_FAIL" "cannot create $root/.worktrees"
  git -C "$root" check-ignore -q -- ".worktrees/$name" ||
    die "$E_REFUSED" ".worktrees/ is not ignored by git in the main worktree"
  if git -C "$root" remote get-url origin >/dev/null 2>&1; then
    git -C "$root" fetch -q origin || die "$E_FAIL" "git fetch origin failed"
  fi
  git -C "$root" worktree add -q --no-track -b "$branch" "$dir" "$base" ||
    die "$E_FAIL" "git worktree add failed"
  say "created: $dir, branch $branch"
  (cd "$dir" && "$SELF" link)
}

cmd_reclaim() {
  local kind branch remote merge
  kind=$(checkout_kind) || exit
  [[ $kind == main ]] || die "$E_REFUSED" "reclaim runs only in the main worktree"
  if ! branch=$(git symbolic-ref --short -q HEAD); then
    say "detached HEAD: nothing to do"; return 0
  fi
  if [[ $branch == main ]]; then
    say "already on main"; return 0
  fi
  # The configuration, not @{u}: when the upstream is gone, @{u} fails.
  if ! remote=$(git config --get "branch.$branch.remote") ||
     ! merge=$(git config --get "branch.$branch.merge"); then
    say "$branch has no upstream: the main worktree stays on it"; return 0
  fi
  git fetch -q --prune "$remote" || die "$E_FAIL" "git fetch $remote failed"
  if git show-ref --verify -q "refs/remotes/$remote/${merge#refs/heads/}"; then
    say "$branch still exists on $remote: the main worktree stays on it"; return 0
  fi
  [[ -z $(git status --porcelain) ]] ||
    die "$E_REFUSED" "the main worktree has changes: $branch is not left"
  git switch -q main || die "$E_FAIL" "git switch main failed"
  if git show-ref --verify -q "refs/remotes/$remote/main"; then
    git merge -q --ff-only "$remote/main" || die "$E_FAIL" "main cannot fast-forward"
  fi
  say "$branch is gone from $remote: back on main"
}

cmd_drop() {
  (( $# == 1 )) || usage
  local name=$1 root dir top list p
  local -a paths=()
  [[ $name =~ ^[0-9]+-[a-z0-9]+(-[a-z0-9]+)*$ ]] || die "$E_USAGE" "invalid name: $name"
  root=$(main_root) || exit
  dir=$root/.worktrees/$name
  [[ -d $dir ]] || die "$E_FAIL" "worktree not found: $dir"
  top=$(toplevel) || exit
  [[ $(realpath -- "$top") == "$(realpath -- "$dir")" ]] &&
    die "$E_REFUSED" "drop does not remove the worktree it runs in"
  [[ -z $(git -C "$dir" status --porcelain) ]] ||
    die "$E_REFUSED" "$name has changes: nothing is removed"
  # The links first, and only them: their targets live in the main worktree.
  list=$(link_list "$dir" 2>/dev/null) || list=
  [[ -n $list ]] && mapfile -t paths <<< "$list"
  for p in "${paths[@]}"; do
    if [[ -L $dir/$p ]]; then rm -- "$dir/$p"; fi
  done
  git -C "$root" worktree remove "$dir" || die "$E_FAIL" "git worktree remove failed"
  git -C "$root" worktree prune
  say "removed: $name"
}

dispatch() {
  (( $# >= 1 )) || usage
  local cmd=$1
  shift
  case $cmd in
    new)     cmd_new "$@" ;;
    link)    (( $# == 0 )) || usage; cmd_link ;;
    check)   (( $# == 0 )) || usage; cmd_check ;;
    reclaim) (( $# == 0 )) || usage; cmd_reclaim ;;
    drop)    cmd_drop "$@" ;;
    *)       usage ;;
  esac
}

dispatch "$@"

# --- Change History -------------------------------------------------------
# | PR     | Summary                                                       |
# |--------|---------------------------------------------------------------|
# | #6     | messages and comments in English (#3)                         |
# | (this PR) | link list in tools/worktree.links or .worktree-links (#4)   |
# | (this PR) | a list ending in a comment or blank line no longer fails (#4) |
