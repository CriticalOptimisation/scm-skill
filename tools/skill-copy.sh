#!/usr/bin/env bash
# Fixed copies of a skill repository, one per using project (#23).
#
# Ported from skill-repo-development tools/skill-copy.sh at 74caa22 (its #1,
# PR #2), and extended: run from the main worktree of the using project, which
# may be the skill's own repository; one copy per project, pointing back to it
# through USER_PROJECT; one link per agent; the skill's hook; frozen copies;
# configurable link directories; pruning across projects; update of a copy to
# origin/main (#26). Contract: README.md, "Using it in a project" and "The
# skill-copy hook".
#
# Exit codes: 0 success; 1 failure; 2 usage; 3 refused for safety.
set -uo pipefail

readonly E_FAIL=1 E_USAGE=2 E_REFUSED=3
readonly MARGIN=${SKILL_COPY_MARGIN:-120}

say() { printf 'skill-copy: %s\n' "$*" >&2; }
die() { local code=$1; shift; say "$@"; exit "$code"; }
usage() {
  die "$E_USAGE" "usage: skill-copy.sh use <skill repo> <ref> [--skills-dir <dir>] [--agents-dir <dir>] [--clone-to <path>] [--frozen] | update <copy> | prune <skill repo> | status <skill repo>"
}

now() { echo "${SKILL_COPY_NOW:-$(date +%s)}"; }

# The skill repository (its main worktree), its log, lock and copies.
S="" LOG="" LOCK=""

# True for a git URL rather than a local path.
is_url() { [[ $1 =~ ^[A-Za-z][A-Za-z0-9+.-]*:// || $1 =~ ^[^/:]+@[^/:]+: ]]; }

# Sets S to the main worktree of the repository at a local path.
set_skill_repo() {
  local common
  common=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) ||
    die "$E_FAIL" "not a git repository: $1"
  S=$(dirname "$(realpath "$common")")
  LOG=$S/.worktrees/skill-copies.log
  LOCK=$S/.worktrees/skill-copies.lock
}

# The absolute path of the project's main worktree, from the current directory,
# or a refusal. Two tests internal to git, never a path, as in worktree.sh:
# symbolic links make paths lie.
project_root() {
  local top gitdir common
  top=$(git rev-parse --show-toplevel 2>/dev/null) || die "$E_FAIL" "not in a git repository"
  gitdir=$(realpath "$(git rev-parse --git-dir)") || die "$E_FAIL" "git rev-parse failed"
  common=$(realpath "$(git rev-parse --git-common-dir)") || die "$E_FAIL" "git rev-parse failed"
  [[ $gitdir == "$common" && -d $top/.git ]] || die "$E_REFUSED" "run from the main worktree of the project"
  realpath "$top"
}

require_worktrees_ignored() {
  git -C "$S" check-ignore -q .worktrees/skill-copies.log ||
    die "$E_REFUSED" "/.worktrees/ is not ignored by git in $S"
}

lock() {
  mkdir -p "$S/.worktrees" || die "$E_FAIL" "cannot create $S/.worktrees"
  exec 9> "$LOCK" || die "$E_FAIL" "cannot open $LOCK"
  flock 9 || die "$E_FAIL" "cannot lock $LOCK"
}

# A project's part of a copy's name: 8 hex digits of the SHA-1 of its path.
pid() { printf '%s' "$1" | sha1sum | cut -c1-8; }

# The log: "<epoch> <copy> <project>", the project being the rest of the line.
# current_of <project>: the copy last logged for the project.
current_of() {
  [[ -f $LOG ]] || return 0
  awk -v p="$1" '{ if (substr($0, length($1) + length($2) + 3) == p) c = $2 } END { print c }' "$LOG"
}

# Prints "<copy> <end time>" for each copy that its project moved away from:
# the time of the project's next log line after the copy's last one.
end_times() {
  [[ -f $LOG ]] || return 0
  awk '{ p = substr($0, length($1) + length($2) + 3)
         if (p in last) end[last[p]] = $1
         last[p] = $2 }
       END { for (p in last) delete end[last[p]]
             for (c in end) print c, end[c] }' "$LOG"
}

# Start times (epoch seconds) of the running sessions, one per line.
session_starts() {
  if [[ -v SKILL_COPY_STARTS ]]; then
    # shellcheck disable=SC2086 # one start time per word
    printf '%s\n' $SKILL_COPY_STARTS
    return
  fi
  local t pid et
  t=$(now)
  for pid in $(pgrep -x claude); do
    et=$(ps -o etimes= -p "$pid" 2>/dev/null) && echo $((t - et))
  done
}

# The name: field of SKILL.md at a commit.
skill_name() {
  git -C "$S" show "$1:SKILL.md" 2>/dev/null |
    awk '/^---[[:space:]]*$/ { n++; next }
         n == 1 && /^name:/ { sub(/^name:[[:space:]]*/, ""); sub(/[[:space:]]+$/, ""); print; exit }'
}

# The agent definitions (agents/*.md) at a commit, one file name per line.
agent_files() {
  git -C "$S" ls-tree "$1:agents" 2>/dev/null |
    awk -F'\t' '$1 ~ / blob / && $2 ~ /\.md$/ { print $2 }'
}

# exclude <repository dir> <path relative to it>: excludes the path in the
# repository's .git/info/exclude, unless git already ignores it.
exclude() {
  local file
  git -C "$1" check-ignore -q -- "$2" && return 0
  file=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir)/info/exclude
  mkdir -p "${file%/*}"
  grep -qxF -- "/$2" "$file" 2>/dev/null || echo "/$2" >> "$file" || die "$E_FAIL" "cannot write $file"
}

# rel <from dir> <to>: the relative path from a directory to a path.
rel() { realpath -m --relative-to="$1" -- "$2"; }

# relink <link> <target>: replaces a symbolic link atomically.
relink() {
  [[ -L $1 && $(readlink -- "$1") == "$2" ]] && return 0
  if ! ln -s -- "$2" "$1.new.$$" || ! mv -T -- "$1.new.$$" "$1"; then
    die "$E_FAIL" "cannot link $1"
  fi
}

# True if a link points into some copy of a skill.
links_to_a_copy() { [[ -L $1 && $(readlink -- "$1") == *.worktrees/skill-* ]]; }

# True if a link points into a copy of this skill repository.
links_to_our_copy() {
  links_to_a_copy "$1" && [[ $(realpath -m -- "$1") == "$S"/.worktrees/skill-* ]]
}

# Refuses anything in the way of a link: a file, a directory, or a link that
# does not point into a copy. $1 is relative to the project root.
check_link_path() {
  if [[ -L $1 ]]; then
    links_to_a_copy "$1" || die "$E_REFUSED" "$1 is a link that does not point into a copy"
  elif [[ -e $1 ]]; then
    die "$E_REFUSED" "$1 exists and is not a link"
  fi
}

# Normalizes a link directory: relative to the project root, no ./ or trailing /.
link_dir() {
  local d=${1%/}
  d=${d#./}
  [[ -n $d && $d != /* && $d != *..* ]] || die "$E_USAGE" "link directories are relative to the project root: $1"
  echo "$d"
}

# The hook's helper: links <dest> to <source> relatively, or copies <source>
# to <dest> with --frozen.
skill_copy_link() {
  local src=$1 dest=$2
  if [[ ${SKILL_COPY_FROZEN:-} == 1 ]]; then
    rm -rf -- "$dest" && cp -a -- "$src" "$dest"
  else
    if [[ -e $dest && ! -L $dest ]]; then
      say "$dest exists and is not a link"
      return 1
    fi
    ln -sfn -- "$(rel "$(dirname -- "$dest")" "$src")" "$dest"
  fi
}

# Sources the copy's hook, if any, in a subshell from the project root.
run_hook() {
  local copydir=$1 project=$2 frozen=$3
  [[ -f $copydir/tools/skill-copy-hook.sh ]] || return 0
  (
    set +u
    cd "$project" || exit 1
    export SKILL_COPY_FROZEN=$frozen
    # shellcheck source=/dev/null
    . "$copydir/tools/skill-copy-hook.sh" "$copydir" "$project"
  )
}

cmd_use() {
  local repo=$1 ref=$2 skills_dir=.claude/skills agents_dir=.claude/agents
  local clone_to="" frozen="" project full sha copy copydir name f l dest
  local -a agents=()
  shift 2
  while (( $# )); do
    case $1 in
      --skills-dir) (( $# >= 2 )) || usage; skills_dir=$(link_dir "$2") || exit; shift 2 ;;
      --agents-dir) (( $# >= 2 )) || usage; agents_dir=$(link_dir "$2") || exit; shift 2 ;;
      --clone-to)   (( $# >= 2 )) || usage; clone_to=$2; shift 2 ;;
      --frozen)     frozen=1; shift ;;
      *)            usage ;;
    esac
  done
  is_url "$repo" || repo=$(realpath -m -- "$repo")
  [[ -z $clone_to ]] || clone_to=$(realpath -m -- "$clone_to")

  project=$(project_root) || exit
  cd "$project" || die "$E_FAIL" "cannot enter $project"

  if is_url "$repo"; then
    dest=${clone_to:-$(dirname "$project")/$(basename "${repo%/}" .git)}
    if [[ ! -e $dest ]]; then
      git clone -q -- "$repo" "$dest" || die "$E_FAIL" "cannot clone $repo into $dest"
      say "cloned $repo into $dest"
    fi
    repo=$dest
  fi
  [[ -d $repo ]] || die "$E_FAIL" "no skill repository at $repo"
  set_skill_repo "$repo"
  require_worktrees_ignored

  git -C "$S" fetch -q origin 2>/dev/null || say "warning: fetch from origin failed; using local refs"
  full=$(git -C "$S" rev-parse -q --verify "$ref^{commit}") || die "$E_FAIL" "unknown ref: $ref"
  sha=${full:0:12}
  copy=skill-$sha-$(pid "$project")
  copydir=$S/.worktrees/$copy
  name=$(skill_name "$full")
  [[ -n $name ]] || die "$E_REFUSED" "SKILL.md at $ref has no name: field"
  mapfile -t agents < <(agent_files "$full")

  # Validate every link path before writing anything.
  check_link_path "$skills_dir/$name"
  for f in "${agents[@]}"; do check_link_path "$agents_dir/$f"; done

  lock
  if [[ ! -d $copydir ]]; then
    git -C "$S" worktree add -q --detach "$copydir" "$full" || die "$E_FAIL" "git worktree add failed"
  fi
  [[ -f $copydir/USER_PROJECT && $(< "$copydir/USER_PROJECT") == "$project" ]] ||
    printf '%s\n' "$project" > "$copydir/USER_PROJECT" || die "$E_FAIL" "cannot write $copydir/USER_PROJECT"
  exclude "$copydir" USER_PROJECT

  run_hook "$copydir" "$project" "$frozen" || die "$E_FAIL" "the hook of $copy failed; links not moved"

  # The skill link, and the links of this skill to other names.
  mkdir -p -- "$skills_dir" || die "$E_FAIL" "cannot create $skills_dir"
  exclude "$project" "$skills_dir/$name"
  relink "$skills_dir/$name" "$(rel "$project/$skills_dir" "$copydir")"
  for l in "$skills_dir"/*; do
    [[ $l != "$skills_dir/$name" ]] && links_to_our_copy "$l" && rm -- "$l" && say "removed link: $l"
  done

  # One link per agent; the links of agents the copy no longer has go.
  if (( ${#agents[@]} )); then
    mkdir -p -- "$agents_dir" || die "$E_FAIL" "cannot create $agents_dir"
    for f in "${agents[@]}"; do
      exclude "$project" "$agents_dir/$f"
      relink "$agents_dir/$f" "$(rel "$project/$agents_dir" "$copydir/agents/$f")"
    done
  fi
  for l in "$agents_dir"/*; do
    links_to_our_copy "$l" || continue
    [[ " ${agents[*]} " == *" ${l##*/} "* ]] && continue
    rm -- "$l" && say "removed link: $l"
  done

  # The links of the copy, which pruning checks.
  {
    echo "$project/$skills_dir/$name"
    for f in "${agents[@]}"; do echo "$project/$agents_dir/$f"; done
  } > "$S/.worktrees/$copy.links.new" && mv -f "$S/.worktrees/$copy.links.new" "$S/.worktrees/$copy.links"
  # The marker of a frozen copy, which update repeats.
  if [[ -n $frozen ]]; then
    : > "$S/.worktrees/$copy.frozen" || die "$E_FAIL" "cannot write $S/.worktrees/$copy.frozen"
  else
    rm -f -- "$S/.worktrees/$copy.frozen"
  fi

  [[ $(current_of "$project") == "$copy" ]] || echo "$(now) $copy $project" >> "$LOG"
  say "$name -> $copy ($ref)"
  prune_copies
}

# True if the copy's project is still there and one of its links points into
# the copy.
linked() {
  local copy=$1 copydir=$S/.worktrees/$1 project l t
  [[ -f $copydir/USER_PROJECT ]] || return 1
  project=$(< "$copydir/USER_PROJECT")
  [[ -d $project && -f $S/.worktrees/$copy.links ]] || return 1
  while IFS= read -r l; do
    [[ -L $l ]] || continue
    t=$(realpath -m -- "$l")
    [[ $t == "$copydir" || $t == "$copydir"/* ]] && return 0
  done < "$S/.worktrees/$copy.links"
  return 1
}

# Removes each copy that its project no longer links and that stopped being
# current earlier than the oldest session start minus the margin; with no
# session, all of them.
prune_copies() {
  local starts oldest dir copy end rc=0
  local -A ends=()
  starts=$(session_starts | grep -E '^[0-9]+$' | sort -n)
  oldest=${starts%%$'\n'*}
  while read -r copy end; do [[ -n $copy ]] && ends[$copy]=$end; done < <(end_times)
  for dir in "$S"/.worktrees/skill-*/; do
    [[ -d $dir ]] || continue
    copy=$(basename "$dir")
    linked "$copy" && continue
    end=${ends[$copy]:-0}
    [[ -n $oldest ]] && (( end >= oldest - MARGIN )) && continue
    if git -C "$S" worktree remove "$dir" 2>/dev/null; then
      rm -f -- "$S/.worktrees/$copy.links" "$S/.worktrees/$copy.frozen"
      say "removed $copy"
    else
      say "warning: $copy could not be removed (changes in it?); kept"
      rc=$E_FAIL
    fi
  done
  git -C "$S" worktree prune
  return "$rc"
}

cmd_prune() {
  set_skill_repo "$1"
  require_worktrees_ignored
  lock
  prune_copies
}

cmd_status() {
  local dir copy end project
  local -A ends=()
  set_skill_repo "$1"
  require_worktrees_ignored
  while read -r copy end; do [[ -n $copy ]] && ends[$copy]=$end; done < <(end_times)
  for dir in "$S"/.worktrees/skill-*/; do
    [[ -d $dir ]] || continue
    copy=$(basename "$dir")
    project=$(cat "$dir/USER_PROJECT" 2>/dev/null) || project="(no USER_PROJECT)"
    if linked "$copy"; then
      echo "copy: $copy linked by $project"
    else
      end=${ends[$copy]:-0}
      echo "copy: $copy of $project ended $end ($(date -d "@$end" '+%F %T'))"
    fi
  done
  return 0
}

# Brings the project's copy up to origin/main: the skill repository, the
# project, the link directories and --frozen all come from the copy. Prints
# "updated <old> <new> <copy dir>", "current <sha>" or "kept <sha> ahead|diverged".
# Offline or refused, the links do not move.
cmd_update() {
  local copydir copy project head target old new l rc
  local -a opts=()
  copydir=$(realpath -e -- "$1" 2>/dev/null) || die "$E_FAIL" "not a copy of a skill: $1"
  copy=${copydir##*/}
  [[ $copy == skill-* && -f $copydir/USER_PROJECT ]] || die "$E_FAIL" "not a copy of a skill: $1"
  set_skill_repo "$copydir"
  [[ $copydir == "$S/.worktrees/$copy" ]] || die "$E_FAIL" "not a copy of a skill: $1"
  project=$(project_root) || exit
  [[ $(< "$copydir/USER_PROJECT") == "$project" ]] ||
    die "$E_REFUSED" "$copy belongs to another project: $(< "$copydir/USER_PROJECT")"

  # The link directories: the skill link first, then the agent links.
  if [[ -f $S/.worktrees/$copy.links ]]; then
    {
      IFS= read -r l && opts+=(--skills-dir "$(dirname -- "${l#"$project"/}")")
      IFS= read -r l && opts+=(--agents-dir "$(dirname -- "${l#"$project"/}")")
    } < "$S/.worktrees/$copy.links"
  fi
  [[ -f $S/.worktrees/$copy.frozen ]] && opts+=(--frozen)

  git -C "$S" fetch -q origin 2>/dev/null || die "$E_FAIL" "warning: fetch from origin failed; links not moved"
  head=$(git -C "$copydir" rev-parse HEAD) || die "$E_FAIL" "git rev-parse failed in $copydir"
  target=$(git -C "$S" rev-parse -q --verify 'origin/main^{commit}') || die "$E_FAIL" "no origin/main in $S"
  old=${head:0:12} new=${target:0:12}
  if [[ $head == "$target" ]]; then
    echo "current $old"
    return 0
  elif git -C "$S" merge-base --is-ancestor "$target" "$head"; then
    echo "kept $old ahead"
    return 0
  elif ! git -C "$S" merge-base --is-ancestor "$head" "$target"; then
    echo "kept $old diverged"
    return 0
  fi

  ( cmd_use "$S" origin/main "${opts[@]}" ) >&2
  rc=$?
  # A copy that pruning could not remove fails use after the links moved.
  if (( rc )) && [[ $(current_of "$project") != "skill-$new-$(pid "$project")" ]]; then
    die "$rc" "warning: update to $new failed; links not moved"
  fi
  echo "updated $old $new $S/.worktrees/skill-$new-$(pid "$project")"
}

dispatch() {
  (( $# >= 1 )) || usage
  local cmd=$1
  shift
  case $cmd in
    use)    (( $# >= 2 )) || usage; cmd_use "$@" ;;
    update) (( $# == 1 )) || usage; cmd_update "$1" ;;
    prune)  (( $# == 1 )) || usage; cmd_prune "$1" ;;
    status) (( $# == 1 )) || usage; cmd_status "$1" ;;
    *)      usage ;;
  esac
}

dispatch "$@"

# --- Change History -------------------------------------------------------
# | PR     | Summary                                                       |
# |--------|---------------------------------------------------------------|
# | #25    | port of skill-repo-development 74caa22: one copy per project (#23)|
