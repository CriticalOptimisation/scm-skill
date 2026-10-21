#!/usr/bin/env bash
# Issue and PR threads with minimal output (#27).
#
# index: the table of contents of a thread, one line per message, with its
# exact GraphQL id and its tags; read, last, get: messages in full; post,
# reply: a body from stdin (a here-doc), printing only the URL. Contract:
# the skill's references/shell-tools.md. Replaces references/pr-threads.sh.
#
# Exit codes: 0 success; 1 error; 2 usage; 3 output written to the overflow
# file, with a report and its line index on stdout (#33).
set -uo pipefail

readonly E_FAIL=1 E_USAGE=2 E_OVERFLOW=3
readonly MAX_BYTES=16384

say() { printf 'thread.sh: %s\n' "$*" >&2; }
die() { local code=$1; shift; say "$@"; exit "$code"; }
usage() {
  die "$E_USAGE" "usage: thread.sh index <N> [-o <file>] [--max-lines <n>]
       thread.sh read <N> <range> [-o <file>] [--max-lines <n>]   range: 5, 5-9, 5-, -3
       thread.sh last <N> [-o <file>] [--max-lines <n>]
       thread.sh get <id> [-o <file>] [--max-lines <n>]
       thread.sh post <N> <<'SCM_BODY' ... SCM_BODY
       thread.sh reply <id> <<'SCM_BODY' ... SCM_BODY"
}

TMP=$(mktemp -d 2> /dev/null) || die "$E_FAIL" "cannot create a temporary directory in ${TMPDIR:-/tmp}"
trap 'rm -rf "$TMP"' EXIT

# Runs gh; prints its stdout. On failure, dies with gh's first stderr line.
# A GraphQL answer carrying errors is a failure too.
gh_call() {
  local out rc
  out=$(gh "$@" 2> "$TMP/err")
  rc=$?
  if (( rc != 0 )); then
    local msg
    msg=$(head -n 1 "$TMP/err")
    die "$E_FAIL" "gh: ${msg:-failed with exit code $rc}"
  fi
  if [[ $out == '{'* ]] && jq -e 'has("errors")' <<< "$out" > /dev/null 2>&1; then
    die "$E_FAIL" "gh: $(jq -r '.errors[0].message' <<< "$out")"
  fi
  printf '%s\n' "$out"
}

# Sets OWNER and NAME: GH_REPO ([HOST/]OWNER/NAME), else the current repo.
repo() {
  local r=${GH_REPO:-}
  if [[ -z $r ]]; then
    r=$(gh_call repo view --json nameWithOwner | jq -r .nameWithOwner) || exit "$E_FAIL"
  fi
  NAME=${r##*/}
  r=${r%/*}
  OWNER=${r##*/}
  [[ -n $OWNER && -n $NAME ]] || die "$E_FAIL" "cannot tell the repository from '$r'"
}

PAGE='pageInfo { hasNextPage endCursor }'
COMMENT='id databaseId author { login } createdAt body'
CONNECTIONS="comments(first: 100) { $PAGE nodes { $COMMENT } }"
PR_CONNECTIONS="reviews(first: 100) { $PAGE nodes { id author { login } submittedAt createdAt state body } }
      reviewThreads(first: 100) { $PAGE nodes { id isResolved isOutdated path line originalLine
        comments(first: 100) { $PAGE nodes { $COMMENT } } } }"

# The first page of every connection of thread $1.
query_thread() {
  gh_call api graphql -F number="$1" -f owner="$OWNER" -f name="$NAME" -f query="
query(\$owner: String!, \$name: String!, \$number: Int!) {
  repository(owner: \$owner, name: \$name) {
    issueOrPullRequest(number: \$number) {
      __typename
      ... on Issue { id number author { login } createdAt body $CONNECTIONS }
      ... on PullRequest { id number author { login } createdAt body $CONNECTIONS $PR_CONNECTIONS }
    }
  }
}"
}

# The next page of connection $2 (comments, reviews, reviewThreads) of
# thread $1, after cursor $3, by the same path as the first page.
query_more() {
  local sel
  case $2 in
    comments) sel="comments(first: 100, after: \$after) { $PAGE nodes { $COMMENT } }" ;;
    reviews) sel="reviews(first: 100, after: \$after) { $PAGE nodes { id author { login } submittedAt createdAt state body } }" ;;
    reviewThreads) sel="reviewThreads(first: 100, after: \$after) { $PAGE nodes { id isResolved isOutdated path line originalLine
        comments(first: 100) { $PAGE nodes { $COMMENT } } } }" ;;
  esac
  local frag="... on PullRequest { $sel }"
  [[ $2 == comments ]] && frag="... on Issue { $sel } $frag"
  gh_call api graphql -F number="$1" -f owner="$OWNER" -f name="$NAME" -f after="$3" -f query="
query(\$owner: String!, \$name: String!, \$number: Int!, \$after: String!) {
  repository(owner: \$owner, name: \$name) {
    issueOrPullRequest(number: \$number) { __typename $frag }
  }
}"
}

# The next page of the comments of review thread $1, after cursor $2.
query_thread_comments() {
  gh_call api graphql -f id="$1" -f after="$2" -f query="
query(\$id: ID!, \$after: String!) {
  node(id: \$id) { ... on PullRequestReviewThread { comments(first: 100, after: \$after) { $PAGE nodes { $COMMENT } } } }
}"
}

# Prints thread $1 as one JSON document, every connection complete.
fetch_thread() {
  local n=$1 doc conn cursor more i tid
  doc=$(query_thread "$n") || exit "$E_FAIL"
  doc=$(jq '.data.repository.issueOrPullRequest' <<< "$doc")
  [[ $doc != null ]] || die "$E_FAIL" "no issue or PR #$n"
  for conn in comments reviews reviewThreads; do
    while [[ $(jq -r --arg c "$conn" '.[$c].pageInfo.hasNextPage // false' <<< "$doc") == true ]]; do
      cursor=$(jq -r --arg c "$conn" '.[$c].pageInfo.endCursor' <<< "$doc")
      more=$(query_more "$n" "$conn" "$cursor") || exit "$E_FAIL"
      doc=$(jq --arg c "$conn" --argjson m "$more" '
        $m.data.repository.issueOrPullRequest[$c] as $p
        | .[$c].nodes += $p.nodes | .[$c].pageInfo = $p.pageInfo' <<< "$doc") || exit "$E_FAIL"
    done
  done
  local count
  count=$(jq '.reviewThreads.nodes // [] | length' <<< "$doc")
  for (( i = 0; i < count; i++ )); do
    while [[ $(jq -r --argjson i "$i" '.reviewThreads.nodes[$i].comments.pageInfo.hasNextPage' <<< "$doc") == true ]]; do
      tid=$(jq -r --argjson i "$i" '.reviewThreads.nodes[$i].id' <<< "$doc")
      cursor=$(jq -r --argjson i "$i" '.reviewThreads.nodes[$i].comments.pageInfo.endCursor' <<< "$doc")
      more=$(query_thread_comments "$tid" "$cursor") || exit "$E_FAIL"
      doc=$(jq --argjson i "$i" --argjson m "$more" '
        $m.data.node.comments as $p
        | .reviewThreads.nodes[$i].comments.nodes += $p.nodes
        | .reviewThreads.nodes[$i].comments.pageInfo = $p.pageInfo' <<< "$doc") || exit "$E_FAIL"
    done
  done
  printf '%s\n' "$doc"
}

# jq definitions shared by the formatters.
# shellcheck disable=SC2016 # $vars of the jq program, for jq, not the shell
readonly JQ_LIB='
def text: (. // "") | gsub("\r\n"; "\n");
def who: if . == null then "ghost" else .login end;
def uniq: reduce .[] as $x ([]; if any(.[]; . == $x) then . else . + [$x] end);
def sigre: "^— issue #[0-9]+ engineer #([0-9]+)[ \t]*$";
def tags:
  text as $b
  | ($b | split("\n")) as $lines
  | [ $lines[] | select(test("^#{1,6}[ \t]")) | sub("^#+[ \t]+"; "") | sub("[ \t#]*$"; "") ] as $heads
  | [ $b | match("\\b[A-Z][0-9]{1,2}\\b"; "g") | .string ] as $labels
  | [ $lines[] | select(test(sigre) | not) ] | join("\n")
  | [ match("(?<![\\w/&#])#[0-9]+\\b"; "g") | .string ] as $refs
  | [ $b | match("`([A-Za-z_.<][^`\\s]*\\.[A-Za-z0-9]+)`"; "g") | .captures[0].string ] as $paths
  | [ $lines[] | match(sigre) | "engineer #\(.captures[0].string)" ] as $sig
  | ($heads + $labels + $refs + $paths + $sig | uniq)
  | if length == 0 then "-" else join(", ") end;
def clean: text | sub("\n+$"; "");
def place: "\(.path):\(.line)" + (if .resolved then " resolved" else "" end) + (if .outdated then " outdated" else "" end);
def header: "\(.n) \(.id) \(.date[0:10]) \(.author) \(.kind) \(.body | text | length) "
  + (if .kind == "inline" or .kind == "reply" then place else (.body | tags) end);
def block: header + "\n" + (.body | clean) + "\n";
def items:
  . as $t
  | [ { key: $t.createdAt, list: [ { id: $t.id, date: $t.createdAt, author: ($t.author | who), kind: "body", body: $t.body } ] } ]
  + [ ($t.comments.nodes // [])[] | { key: .createdAt, list: [ { id, date: .createdAt, author: (.author | who), kind: "comment", body } ] } ]
  + [ ($t.reviews.nodes // [])[] | (.submittedAt // .createdAt) as $d
      | { key: $d, list: [ { id, date: $d, author: (.author | who), kind: "review:\(.state)", body } ] } ]
  + [ ($t.reviewThreads.nodes // [])[] | . as $th | select((.comments.nodes | length) > 0)
      | { key: .comments.nodes[0].createdAt,
          list: [ .comments.nodes | to_entries[] | .value as $c
                  | { id: $c.id, date: $c.createdAt, author: ($c.author | who),
                      kind: (if .key == 0 then "inline" else "reply" end), body: $c.body,
                      path: $th.path, line: ($th.line // $th.originalLine),
                      resolved: $th.isResolved, outdated: $th.isOutdated } ] } ]
  | sort_by(.key) | [ .[].list[] ] | to_entries | map(.value + { n: (.key + 1) });
'

# The blocks $1, a JSON array of {id, text}: the output is each text followed
# by a newline. Prints it on stdout, or, past the limits, writes it to the
# overflow file (OUT, else a new file in TMPDIR), prints the report with the
# line range of every block, and exits 3 (#33).
emit() {
  local blocks=$1 content lines bytes file
  content=$(jq -j '.[] | .text + "\n"' <<< "$blocks" && printf x) || die "$E_FAIL" "cannot format the output"
  content=${content%x}
  lines=$(printf '%s' "$content" | wc -l)
  bytes=$(printf '%s' "$content" | wc -c)
  if (( lines > MAX_LINES || bytes > MAX_BYTES )); then
    file=$OUT
    if [[ -z $file ]]; then
      file=$(mktemp "${TMPDIR:-/tmp}/thread.sh.XXXXXX.txt" 2> /dev/null) \
        || die "$E_FAIL" "cannot create an overflow file in ${TMPDIR:-/tmp}"
    fi
    printf '%s' "$content" > "$file" || die "$E_FAIL" "cannot write $file"
    file=$(realpath -ms -- "$file")
    printf 'overflow %d lines %d bytes -> %s\n' "$lines" "$bytes" "$file"
    printf 'read it in parts with your Read tool (offset/limit), using the index below; delete it when done (rm -- %s)\n' "$file"
    printf 'if the file is missing, stop and report BLOCKED: do not retry\n'
    printf 'index:\n'
    jq -r 'foreach .[] as $b ({end: 0}; (.start = .end + 1) | (.end += ($b.text | split("\n") | length)); "\(.start)-\(.end) \($b.id)")' <<< "$blocks"
    exit "$E_OVERFLOW"
  fi
  if [[ -n $OUT && -f $OUT ]]; then
    rm -f -- "$OUT" || die "$E_FAIL" "cannot remove $OUT"
  fi
  printf '%s' "$content"
}

# Refuses, exit 2, an -o file that is not a regular file (a device such as
# /dev/stdout, even when it leads to a regular file), or that lies in a git
# work tree and is not ignored by git (#33).
check_out() {
  [[ -n $OUT ]] || return 0
  local abs dir
  abs=$(realpath -ms -- "$OUT")
  if [[ -e $OUT && ! -f $OUT ]] || [[ $abs == /dev/* || $abs == /proc/* ]]; then
    die "$E_USAGE" "-o needs a regular file; omit -o to read the output on stdout"
  fi
  dir=${abs%/*}
  while [[ -n $dir && ! -d $dir ]]; do dir=${dir%/*}; done
  if [[ $(git -C "${dir:-/}" rev-parse --is-inside-work-tree 2> /dev/null) == true ]]; then
    git -C "${dir:-/}" check-ignore -q -- "$abs" \
      || die "$E_USAGE" "-o $OUT is not ignored by git; omit -o or use a path outside the project"
  fi
}

# Deletes the default overflow files older than 60 minutes (#33).
clean() {
  find "${TMPDIR:-/tmp}" -maxdepth 1 -type f -name 'thread.sh.*.txt' -mmin +60 -delete 2> /dev/null || true
}

cmd_index() {
  local doc out
  doc=$(fetch_thread "$1") || exit "$E_FAIL"
  out=$(jq "$JQ_LIB"'
    [ items[] | { id, text: (header + (if .kind == "inline" or .kind == "reply"
      then "\n" + (.body | clean | split("\n") | map(if . == "" then "" else "    " + . end) | join("\n"))
      else "" end)) } ]' <<< "$doc") || die "$E_FAIL" "cannot format thread #$1"
  emit "$out"
}

# Prints the blocks of the messages $2..$3 (positions) of thread $1; $3 = 0
# means to the end, and $2 < 0 the last -$2 messages.
read_slice() {
  local doc out count from=$2 to=$3
  doc=$(fetch_thread "$1") || exit "$E_FAIL"
  count=$(jq "$JQ_LIB"'items | length' <<< "$doc") || die "$E_FAIL" "cannot format thread #$1"
  if (( from < 0 )); then
    from=$(( count + from + 1 )); (( from < 1 )) && from=1
    to=$count
  fi
  (( to == 0 )) && to=$count
  (( from <= count )) || die "$E_FAIL" "no message $from ($count in #$1)"
  (( to <= count )) || die "$E_FAIL" "no message $to ($count in #$1)"
  out=$(jq --argjson a "$from" --argjson b "$to" "$JQ_LIB"'
    [ items[] | select(.n >= $a and .n <= $b) | { id, text: block } ]' <<< "$doc") || die "$E_FAIL" "cannot format thread #$1"
  emit "$out"
}

cmd_read() {
  local r=$2
  case $r in
    *[!0-9-]* | '' | - | *-*-*) usage ;;
    -*) (( 10#${r#-} >= 1 )) || usage; read_slice "$1" "-$(( 10#${r#-} ))" 0 ;;
    *-) (( 10#${r%-} >= 1 )) || usage; read_slice "$1" "$(( 10#${r%-} ))" 0 ;;
    *-*)
      (( 10#${r%-*} >= 1 && 10#${r%-*} <= 10#${r#*-} )) || usage
      read_slice "$1" "$(( 10#${r%-*} ))" "$(( 10#${r#*-} ))" ;;
    *) (( 10#$r >= 1 )) || usage; read_slice "$1" "$(( 10#$r ))" "$(( 10#$r ))" ;;
  esac
}

cmd_get() {
  local id=$1 doc out
  if [[ $id =~ ^[0-9]+$ ]]; then
    doc=$(gh_call api "repos/$OWNER/$NAME/issues/comments/$id") || exit "$E_FAIL"
    out=$(jq "$JQ_LIB"'
      { n: "-", id: .node_id, date: .created_at, author: (.user | who), kind: "comment", body }
      | [ { id, text: block } ]' <<< "$doc")
  else
    # shellcheck disable=SC2016 # $vars of the GraphQL query, for gh, not the shell
    doc=$(gh_call api graphql -f id="$id" -f query='
query($id: ID!) {
  node(id: $id) {
    __typename
    ... on IssueComment { id author { login } createdAt body }
    ... on Issue { id author { login } createdAt body }
    ... on PullRequest { id author { login } createdAt body }
    ... on PullRequestReview { id author { login } submittedAt createdAt state body }
    ... on PullRequestReviewComment { id author { login } createdAt body path line originalLine replyTo { id } }
  }
}') || exit "$E_FAIL"
    [[ $(jq -r '.data.node // empty | .id' <<< "$doc") != '' ]] || die "$E_FAIL" "no message $id"
    out=$(jq "$JQ_LIB"'
      .data.node | . as $m
      | { n: "-", id, author: (.author | who), body,
          date: (.submittedAt // .createdAt),
          kind: (if .__typename == "IssueComment" then "comment"
                 elif .__typename == "PullRequestReview" then "review:\(.state)"
                 elif .__typename == "PullRequestReviewComment" then (if .replyTo then "reply" else "inline" end)
                 else "body" end),
          path, line: (.line // .originalLine) }
      | [ { id, text: (if .kind == "inline" or .kind == "reply"
        then "\(.n) \(.id) \(.date[0:10]) \(.author) \(.kind) \(.body | text | length) \(.path):\(.line)\n\(.body | clean)\n"
        else block end) } ]' <<< "$doc")
  fi
  [[ -n $out ]] || die "$E_FAIL" "cannot format message $id"
  emit "$out"
}

# Reads the body from stdin into BODY; refuses an empty one.
read_body() {
  BODY=$(cat)
  [[ -n ${BODY//[[:space:]]/} ]] || die "$E_USAGE" "empty body: nothing posted"
}

cmd_post() {
  local out
  read_body
  out=$(printf '%s\n' "$BODY" | gh_call api "repos/$OWNER/$NAME/issues/$1/comments" -F body=@-) || exit "$E_FAIL"
  jq -r '.html_url' <<< "$out"
}

cmd_reply() {
  local doc pr dbid out
  read_body
  # shellcheck disable=SC2016 # $vars of the GraphQL query, for gh, not the shell
  doc=$(gh_call api graphql -f id="$1" -f query='
query($id: ID!) {
  node(id: $id) { __typename ... on PullRequestReviewComment { databaseId pullRequest { number } } }
}') || exit "$E_FAIL"
  dbid=$(jq -r '.data.node.databaseId // empty' <<< "$doc")
  pr=$(jq -r '.data.node.pullRequest.number // empty' <<< "$doc")
  [[ -n $dbid && -n $pr ]] || die "$E_FAIL" "$1 is not an inline review comment"
  out=$(printf '%s\n' "$BODY" | gh_call api "repos/$OWNER/$NAME/pulls/$pr/comments/$dbid/replies" -F body=@-) || exit "$E_FAIL"
  jq -r '.html_url' <<< "$out"
}

main() {
  local cmd=${1:-} args=()
  [[ -n $cmd ]] || usage
  shift
  OUT='' MAX_LINES=200
  while (( $# )); do
    case $1 in
      -o) (( $# >= 2 )) || usage; OUT=$2; shift 2 ;;
      --max-lines) [[ ${2:-} =~ ^[0-9]+$ ]] || usage; MAX_LINES=$2; shift 2 ;;
      -*) [[ $cmd == read && $1 =~ ^-[0-9]+$ ]] || usage; args+=("$1"); shift ;;
      *) args+=("$1"); shift ;;
    esac
  done
  local n=${#args[@]}
  # shellcheck disable=SC2015 # usage exits: it runs only when a check fails
  case $cmd in
    index | last) (( n == 1 )) && [[ ${args[0]} =~ ^[0-9]+$ ]] || usage ;;
    read) (( n == 2 )) && [[ ${args[0]} =~ ^[0-9]+$ ]] || usage ;;
    get) (( n == 1 )) || usage ;;
    post) (( n == 1 )) && [[ ${args[0]} =~ ^[0-9]+$ ]] || usage ;;
    reply) (( n == 1 )) || usage ;;
    *) usage ;;
  esac
  case $cmd in
    index | read | last | get) clean; check_out ;;
    *) [[ -z $OUT ]] || usage ;;
  esac
  repo
  case $cmd in
    index) cmd_index "${args[0]}" ;;
    read) cmd_read "${args[0]}" "${args[1]}" ;;
    last) read_slice "${args[0]}" -1 0 ;;
    get) cmd_get "${args[0]}" ;;
    post) cmd_post "${args[0]}" ;;
    reply) cmd_reply "${args[0]}" ;;
  esac
}

main "$@"
exit $?

# shellcheck disable=SC2317 # the guard of template-shell.md before the change history, never reached
return 0

# --- Change History -------------------------------------------------------
# | PR     | Summary                                                       |
# |--------|---------------------------------------------------------------|
# | #30    | new: index, read, last, get, post, reply (#27)                |
# | #36    | shellcheck directives with their reason (#29)                 |
