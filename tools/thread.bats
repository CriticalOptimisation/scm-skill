#!/usr/bin/env bats
# tools/thread.sh: issue and PR threads with minimal output (#27).
# Contract: references/shell-tools.md. gh is replaced by tools/fixtures/gh,
# which answers from the fixtures under tools/fixtures/thread/ (GitHub's
# GraphQL and REST answers) and logs every call. The stub tells the calls
# apart by what they must contain: issueOrPullRequest (a thread, every page
# by the same path, the cursor passed as after=<cursor>), the node id (get,
# reply), issues/comments/<id> (a numeric id), issues/<N>/comments (post,
# body=@-) and pulls/<PR>/comments/<id>/replies (reply, body=@-).

bats_require_minimum_version 1.5.0

setup() {
  THREAD="$BATS_TEST_DIRNAME/thread.sh"
  BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$BIN"
  ln -s "$BATS_TEST_DIRNAME/fixtures/gh" "$BIN/gh"
  export PATH="$BIN:$PATH"
  export GH_REPO=acme/widgets
  export GH_STUB_DIR="$BATS_TEST_DIRNAME/fixtures/thread"
  export GH_STUB_LOG="$BATS_TEST_TMPDIR/gh.log"
  export GH_STUB_RULES="$BATS_TEST_TMPDIR/gh.rules"
  : > "$GH_STUB_LOG"
  OUT="$BATS_TEST_TMPDIR/overflow.txt"
  # The default overflow files go to TMPDIR: one per test, outside any repo.
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"
  mkdir -p "$TMPDIR"
}

# Checks the overflow report in $output for the file $1 (#33): the four
# instruction lines, then one index line per message, "<start>-<end> <id>",
# whose blocks follow each other and cover the file; line <start> of the
# file names the message's id.
check_report() {
  local file=$1 bytes lines next=1 range id start end
  bytes=$(wc -c < "$file")
  lines=$(wc -l < "$file")
  [[ "$(sed -n 1p <<< "$output")" == "overflow $lines lines $bytes bytes -> $file" ]]
  [[ "$(sed -n 2p <<< "$output")" == "read it in parts with your Read tool (offset/limit), using the index below; delete it when done (rm -- $file)" ]]
  [[ "$(sed -n 3p <<< "$output")" == 'if the file is missing, stop and report BLOCKED: do not retry' ]]
  [[ "$(sed -n 4p <<< "$output")" == 'index:' ]]
  [[ "$(sed -n '5,$p' <<< "$output" | wc -l)" -ge 1 ]]
  while read -r range id; do
    start=${range%-*} end=${range#*-}
    [[ "$start" -eq "$next" ]]
    [[ "$end" -ge "$start" ]]
    [[ "$(sed -n "${start}p" "$file")" == *" $id "* ]]
    next=$((end + 1))
  done < <(sed -n '5,$p' <<< "$output")
  [[ "$next" -eq $((lines + 1)) ]]
}

# Writes the stub's rules: each argument is "<glob>|<answer>".
rules() {
  local r
  for r in "$@"; do printf '%s\t%s\n' "${r%%|*}" "${r#*|}"; done > "$GH_STUB_RULES"
}

issue_rules() {
  # The continuation rule comes first: a call with the cursor gets page 2.
  rules '*after=C1*|issue-p2.json' '*issueOrPullRequest*|issue-p1.json'
}

ISSUE_INDEX='1 I_27 2026-10-14 lepeuvedic body 51 Feature Request, #20, #21
2 IC_1 2026-10-15 engineer comment 131 Issue Assessment (Task 2), A1, #22, SKILL.md, tools/thread.sh, engineer #1
3 IC_2 2026-10-15 lepeuvedic comment 8 -
4 IC_3 2026-10-16 lepeuvedic comment 40 Plan review, D1, D2'

PR_INDEX='1 PR_5 2026-10-16 engineer body 10 #27
2 PRR_1 2026-10-16 lepeuvedic review:CHANGES_REQUESTED 7 D4
3 PRRC_1 2026-10-16 lepeuvedic inline 16 tools/thread.sh:12 resolved
    Why not jq here?
4 PRRC_2 2026-10-16 engineer reply 15 tools/thread.sh:12 resolved
    Done in abc123.
5 IC_9 2026-10-16 lepeuvedic comment 19 -'

# --- index: the table of contents ------------------------------------------

@test "index of an issue: one line per message, tags instead of the first line, every page" {
  issue_rules
  run --separate-stderr "$THREAD" index 27 -o "$OUT"
  [[ -z "$stderr" ]]
  [[ "$status" -eq 0 ]]
  [[ "$output" == "$ISSUE_INDEX" ]]
  [[ ! -e "$OUT" ]]
  # Page 2 was fetched with the cursor of page 1: nothing is truncated.
  grep -q 'after=C1' "$GH_STUB_LOG"
}

@test "index of a PR: reviews, and inline threads given in full" {
  rules '*issueOrPullRequest*|pr-5.json'
  run --separate-stderr "$THREAD" index 5 -o "$OUT"
  [[ -z "$stderr" ]]
  [[ "$status" -eq 0 ]]
  [[ "$output" == "$PR_INDEX" ]]
}

@test "index: no output line is raw JSON" {
  rules '*issueOrPullRequest*|pr-5.json'
  run --separate-stderr "$THREAD" index 5 -o "$OUT"
  [[ -z "$stderr" ]]
  [[ "$status" -eq 0 ]]
  while IFS= read -r line; do
    [[ $line != '{'* && $line != '['* ]]
  done <<< "$output"
}

# --- read, last, get: messages in full ---------------------------------------

@test "read a slice: each message headed by its index line, body in full" {
  issue_rules
  run --separate-stderr "$THREAD" read 27 2-3 -o "$OUT"
  [[ -z "$stderr" ]]
  [[ "$status" -eq 0 ]]
  [[ "$output" == "2 IC_1 2026-10-15 engineer comment 131 Issue Assessment (Task 2), A1, #22, SKILL.md, tools/thread.sh, engineer #1
## Issue Assessment (Task 2)

**A1. Point 3 is replaced.** Edit \`SKILL.md\` and \`tools/thread.sh\`, see #22.

— issue #27 engineer #1

3 IC_2 2026-10-15 lepeuvedic comment 8 -
Approved" ]]
}

@test "read: the four forms of range" {
  issue_rules
  run --separate-stderr "$THREAD" read 27 3 -o "$OUT"
  [[ -z "$stderr" ]]
  [[ "$output" == '3 IC_2 2026-10-15 lepeuvedic comment 8 -
Approved' ]]
  run --separate-stderr "$THREAD" read 27 4- -o "$OUT"
  [[ -z "$stderr" ]]
  [[ "$output" == '4 IC_3 2026-10-16 lepeuvedic comment 40 Plan review, D1, D2
### Plan review

D1 accepted. D2 agreed.' ]]
  run --separate-stderr "$THREAD" read 27 -1 -o "$OUT"
  [[ -z "$stderr" ]]
  [[ "$output" == '4 IC_3 2026-10-16 lepeuvedic comment 40 Plan review, D1, D2
### Plan review

D1 accepted. D2 agreed.' ]]
  run --separate-stderr "$THREAD" read 27 1-1 -o "$OUT"
  [[ -z "$stderr" ]]
  [[ "$output" == '1 I_27 2026-10-14 lepeuvedic body 51 Feature Request, #20, #21
## Feature Request

Follows #20 and its pilot #21.' ]]
}

@test "last: the last message of the index, in full" {
  issue_rules
  run --separate-stderr "$THREAD" last 27 -o "$OUT"
  [[ -z "$stderr" ]]
  [[ "$status" -eq 0 ]]
  [[ "$output" == '4 IC_3 2026-10-16 lepeuvedic comment 40 Plan review, D1, D2
### Plan review

D1 accepted. D2 agreed.' ]]
}

@test "get by node id: one message in full, - in place of the position" {
  rules '*IC_1*|node-IC_1.json'
  run --separate-stderr "$THREAD" get IC_1 -o "$OUT"
  [[ -z "$stderr" ]]
  [[ "$status" -eq 0 ]]
  [[ "$output" == "- IC_1 2026-10-15 engineer comment 131 Issue Assessment (Task 2), A1, #22, SKILL.md, tools/thread.sh, engineer #1
## Issue Assessment (Task 2)

**A1. Point 3 is replaced.** Edit \`SKILL.md\` and \`tools/thread.sh\`, see #22.

— issue #27 engineer #1" ]]
}

@test "get an inline comment: its path and line" {
  rules '*PRRC_1*|node-PRRC_1.json'
  run --separate-stderr "$THREAD" get PRRC_1 -o "$OUT"
  [[ -z "$stderr" ]]
  [[ "$status" -eq 0 ]]
  [[ "$output" == '- PRRC_1 2026-10-16 lepeuvedic inline 16 tools/thread.sh:12
Why not jq here?' ]]
}

@test "get by the numeric id of a #issuecomment link" {
  rules '*issues/comments/1002*|rest-comment-1002.json'
  run --separate-stderr "$THREAD" get 1002 -o "$OUT"
  [[ -z "$stderr" ]]
  [[ "$status" -eq 0 ]]
  [[ "$output" == '- IC_2 2026-10-15 lepeuvedic comment 8 -
Approved' ]]
}

# --- the overflow file -------------------------------------------------------

@test "overflow: a long output goes in full to the file, the report on stdout, exit 3" {
  issue_rules
  run --separate-stderr "$THREAD" index 27 -o "$OUT" --max-lines 2
  [[ -z "$stderr" ]]
  [[ "$status" -eq 3 ]]
  [[ "$(cat "$OUT")" == "$ISSUE_INDEX" ]]
  check_report "$OUT"
  [[ "$(sed -n '5,$p' <<< "$output")" == '1-1 I_27
2-2 IC_1
3-3 IC_2
4-4 IC_3' ]]
}

@test "overflow: a short output removes a file left by an earlier run" {
  issue_rules
  echo stale > "$OUT"
  run --separate-stderr "$THREAD" index 27 -o "$OUT"
  [[ -z "$stderr" ]]
  [[ "$status" -eq 0 ]]
  [[ "$output" == "$ISSUE_INDEX" ]]
  [[ ! -e "$OUT" ]]
}

# REVIEW PLACEHOLDER (#33): the reading commands require -o: usage error, exit 2 -> without -o, a short output goes to stdout and no file is written
# @test "the reading commands require -o: usage error, exit 2" {
#   issue_rules
#   for cmd in "index 27" "read 27 1" "last 27" "get IC_1"; do
#     # shellcheck disable=SC2086 # split on purpose: one word per argument
#     run --separate-stderr "$THREAD" $cmd
#     [[ "$status" -eq 2 ]]
#     [[ "$stderr" == *usage* ]]
#     [[ -z "$output" ]]
#   done
# }

# --- without -o, -o checked, cleaning (#33) ------------------------------------

@test "without -o, a short output goes to stdout and no file is written" {
  rules '*after=C1*|issue-p2.json' '*IC_1*|node-IC_1.json' '*issueOrPullRequest*|issue-p1.json'
  for cmd in "index 27" "read 27 1" "last 27" "get IC_1"; do
    # shellcheck disable=SC2086 # split on purpose: one word per argument
    run --separate-stderr "$THREAD" $cmd
    [[ -z "$stderr" ]]
    [[ "$status" -eq 0 ]]
    [[ -n "$output" ]]
  done
  run --separate-stderr "$THREAD" index 27
  [[ "$output" == "$ISSUE_INDEX" ]]
  [[ -z "$(ls -A "$TMPDIR")" ]]
}

@test "without -o, an overflow goes to a new file in TMPDIR, with the report and its index" {
  issue_rules
  run --separate-stderr "$THREAD" index 27 --max-lines 2
  [[ -z "$stderr" ]]
  [[ "$status" -eq 3 ]]
  file=$(sed -n '1s/.* -> //p' <<< "$output")
  [[ "$file" == "$TMPDIR"/thread.sh.*.txt ]]
  [[ "$(cat "$file")" == "$ISSUE_INDEX" ]]
  check_report "$file"
}

@test "read overflow: the index gives the block of every message in the file" {
  issue_rules
  run --separate-stderr "$THREAD" read 27 1- --max-lines 2
  [[ -z "$stderr" ]]
  [[ "$status" -eq 3 ]]
  file=$(sed -n '1s/.* -> //p' <<< "$output")
  check_report "$file"
  [[ "$(sed -n '5,$p' <<< "$output" | cut -d' ' -f2)" == 'I_27
IC_1
IC_2
IC_3' ]]
}

@test "index overflow: an inline comment's body is in the block of its message" {
  pr6_rules
  run --separate-stderr "$THREAD" index 6 --max-lines 2
  [[ -z "$stderr" ]]
  [[ "$status" -eq 3 ]]
  file=$(sed -n '1s/.* -> //p' <<< "$output")
  check_report "$file"
  [[ "$(sed -n 5,9p <<< "$output")" == '1-1 PR_6
2-2 PRR_1
3-6 PRRC_5
7-8 PRRC_6
9-9 PRR_2' ]]
}

@test "-o /dev/stdout is refused before any call to GitHub, exit 2" {
  issue_rules
  run --separate-stderr "$THREAD" index 27 -o /dev/stdout
  [[ "$status" -eq 2 ]]
  [[ -z "$output" ]]
  [[ "$stderr" == 'thread.sh: -o needs a regular file; omit -o to read the output on stdout' ]]
  [[ ! -s "$GH_STUB_LOG" ]]
}

@test "-o inside a git work tree: refused unless git ignores it" {
  issue_rules
  repo="$BATS_TEST_TMPDIR/repo"
  git init -q "$repo"
  printf '/scratch/\n' > "$repo/.gitignore"
  mkdir "$repo/scratch"
  run --separate-stderr "$THREAD" index 27 -o "$repo/out.txt"
  [[ "$status" -eq 2 ]]
  [[ -z "$output" ]]
  [[ "$stderr" == "thread.sh: -o $repo/out.txt is not ignored by git; omit -o or use a path outside the project" ]]
  [[ ! -s "$GH_STUB_LOG" ]]
  run --separate-stderr "$THREAD" index 27 -o "$repo/scratch/out.txt"
  [[ -z "$stderr" ]]
  [[ "$status" -eq 0 ]]
  [[ "$output" == "$ISSUE_INDEX" ]]
}

@test "cleaning: default overflow files older than 1 h are deleted; others are kept" {
  issue_rules
  touch -d '-61 minutes' "$TMPDIR/thread.sh.old111.txt" "$TMPDIR/other.txt" "$OUT"
  touch -d '-30 minutes' "$TMPDIR/thread.sh.new222.txt"
  run --separate-stderr "$THREAD" index 27 -o "$BATS_TEST_TMPDIR/elsewhere.txt"
  [[ -z "$stderr" ]]
  [[ "$status" -eq 0 ]]
  [[ ! -e "$TMPDIR/thread.sh.old111.txt" ]]
  [[ -e "$TMPDIR/thread.sh.new222.txt" ]]
  [[ -e "$TMPDIR/other.txt" ]]
  [[ -e "$OUT" ]]
}

# --- -o, the overflow file and cleaning: edge cases (#33) ----------------------

@test "-o /dev/stdout is refused even when stdout is a regular file" {
  issue_rules
  # shellcheck disable=SC2016 # $1 and $2 are for the inner bash, not this shell
  run --separate-stderr bash -c '"$1" index 27 -o /dev/stdout > "$2"' _ "$THREAD" "$BATS_TEST_TMPDIR/redirected.txt"
  [[ "$status" -eq 2 ]]
  [[ -z "$output" ]]
  [[ "$stderr" == 'thread.sh: -o needs a regular file; omit -o to read the output on stdout' ]]
  [[ ! -s "$BATS_TEST_TMPDIR/redirected.txt" ]]
  [[ ! -s "$GH_STUB_LOG" ]]
}

@test "-o naming a directory is refused, exit 2, and the directory is kept" {
  issue_rules
  mkdir "$BATS_TEST_TMPDIR/dir"
  run --separate-stderr "$THREAD" get IC_1 -o "$BATS_TEST_TMPDIR/dir"
  [[ "$status" -eq 2 ]]
  [[ -z "$output" ]]
  [[ "$stderr" == 'thread.sh: -o needs a regular file; omit -o to read the output on stdout' ]]
  [[ -d "$BATS_TEST_TMPDIR/dir" ]]
  [[ ! -s "$GH_STUB_LOG" ]]
}

@test "-o naming a file tracked by git is refused, even if a pattern ignores it" {
  issue_rules
  repo="$BATS_TEST_TMPDIR/repo"
  git init -q "$repo"
  : > "$repo/out.txt"
  git -C "$repo" add out.txt
  printf '/out.txt\n' > "$repo/.gitignore"
  run --separate-stderr "$THREAD" index 27 -o "$repo/out.txt"
  [[ "$status" -eq 2 ]]
  [[ -z "$output" ]]
  [[ "$stderr" == "thread.sh: -o $repo/out.txt is not ignored by git; omit -o or use a path outside the project" ]]
  [[ -e "$repo/out.txt" ]]
  [[ ! -s "$GH_STUB_LOG" ]]
}

@test "-o in a directory still to create, inside a git work tree: refused unless ignored" {
  issue_rules
  repo="$BATS_TEST_TMPDIR/repo"
  git init -q "$repo"
  printf '/scratch/\n' > "$repo/.gitignore"
  run --separate-stderr "$THREAD" index 27 -o "$repo/new/out.txt"
  [[ "$status" -eq 2 ]]
  [[ "$stderr" == "thread.sh: -o $repo/new/out.txt is not ignored by git; omit -o or use a path outside the project" ]]
  [[ -z "$output" ]]
  run --separate-stderr "$THREAD" index 27 -o "$repo/scratch/sub/out.txt"
  [[ -z "$stderr" ]]
  [[ "$status" -eq 0 ]]
  [[ "$output" == "$ISSUE_INDEX" ]]
}

@test "a relative -o: the report names the file by its absolute path" {
  issue_rules
  cd "$BATS_TEST_TMPDIR"
  run --separate-stderr "$THREAD" index 27 -o rel.txt --max-lines 2
  [[ -z "$stderr" ]]
  [[ "$status" -eq 3 ]]
  check_report "$BATS_TEST_TMPDIR/rel.txt"
}

@test "an overflow with -o overwrites a longer file left by an earlier run" {
  issue_rules
  seq 1 500 > "$OUT"
  run --separate-stderr "$THREAD" index 27 -o "$OUT" --max-lines 2
  [[ -z "$stderr" ]]
  [[ "$status" -eq 3 ]]
  [[ "$(cat "$OUT")" == "$ISSUE_INDEX" ]]
  check_report "$OUT"
}

@test "without -o, each overflow gets a file of its own" {
  issue_rules
  run --separate-stderr "$THREAD" index 27 --max-lines 2
  [[ "$status" -eq 3 ]]
  first=$(sed -n '1s/.* -> //p' <<< "$output")
  run --separate-stderr "$THREAD" index 27 --max-lines 2
  [[ -z "$stderr" ]]
  [[ "$status" -eq 3 ]]
  second=$(sed -n '1s/.* -> //p' <<< "$output")
  [[ "$first" != "$second" ]]
  [[ -f "$first" && -f "$second" ]]
}

@test "last and get overflow: one block, the whole file" {
  issue_rules
  run --separate-stderr "$THREAD" last 27 --max-lines 1
  [[ -z "$stderr" ]]
  [[ "$status" -eq 3 ]]
  file=$(sed -n '1s/.* -> //p' <<< "$output")
  check_report "$file"
  [[ "$(sed -n '5,$p' <<< "$output" | wc -l)" -eq 1 ]]
  [[ "$(sed -n 5p <<< "$output")" == *" IC_3" ]]
}

@test "an unusable TMPDIR: exit 1, one line on stderr, nothing on stdout" {
  issue_rules
  TMPDIR="$BATS_TEST_TMPDIR/missing" run --separate-stderr "$THREAD" index 27 --max-lines 2
  [[ "$status" -eq 1 ]]
  [[ -z "$output" ]]
  [[ "$stderr" == "thread.sh: cannot create "*"$BATS_TEST_TMPDIR/missing"* ]]
  [[ "$(wc -l <<< "$stderr")" -eq 1 ]]
}

@test "cleaning runs without -o too, and leaves subdirectories alone" {
  issue_rules
  mkdir "$TMPDIR/sub"
  touch -d '-61 minutes' "$TMPDIR/thread.sh.old111.txt" "$TMPDIR/sub/thread.sh.deep333.txt"
  run --separate-stderr "$THREAD" index 27
  [[ -z "$stderr" ]]
  [[ "$status" -eq 0 ]]
  [[ ! -e "$TMPDIR/thread.sh.old111.txt" ]]
  [[ -e "$TMPDIR/sub/thread.sh.deep333.txt" ]]
}

@test "a failed page fails the command: one line on stderr, no partial output" {
  rules '*after=C1*|!1 HTTP 502: Bad Gateway' '*issueOrPullRequest*|issue-p1.json'
  run --separate-stderr "$THREAD" index 27 -o "$OUT"
  [[ "$status" -eq 1 ]]
  [[ -z "$output" ]]
  [[ "$stderr" == 'thread.sh: '* ]]
  [[ "$(printf '%s\n' "$stderr" | wc -l)" -eq 1 ]]
  [[ ! -e "$OUT" ]]
}

# --- post and reply: the body from a here-doc --------------------------------

@test "post: the body from stdin, sent unchanged; only the URL is printed" {
  rules '*issues/27/comments*|posted.json'
  run --separate-stderr "$THREAD" post 27 <<'SCM_BODY'
## Plan

`SKILL.md` and $HOME stay as written.
SCM_BODY
  [[ -z "$stderr" ]]
  [[ "$status" -eq 0 ]]
  [[ "$output" == 'https://github.com/acme/widgets/issues/27#issuecomment-1010' ]]
  # shellcheck disable=SC2016 # literal text of the posted body
  [[ "$(cat "$GH_STUB_LOG.stdin")" == '## Plan

`SKILL.md` and $HOME stay as written.' ]]
}

@test "post: an empty body is refused, nothing is posted" {
  rules '*issues/27/comments*|posted.json'
  run --separate-stderr "$THREAD" post 27 < /dev/null
  [[ "$status" -eq 2 ]]
  [[ -z "$output" ]]
  [[ "$stderr" == 'thread.sh: empty body: nothing posted' ]]
  run ! grep -q 'comments' "$GH_STUB_LOG"
}

@test "reply: answers the inline thread of a comment; only the URL is printed" {
  rules '*pulls/5/comments/2001/replies*|replied.json' '*PRRC_1*|node-PRRC_1.json'
  run --separate-stderr "$THREAD" reply PRRC_1 <<'SCM_BODY'
Fixed in def456.
SCM_BODY
  [[ -z "$stderr" ]]
  [[ "$status" -eq 0 ]]
  [[ "$output" == 'https://github.com/acme/widgets/pull/5#discussion_r2003' ]]
  [[ "$(cat "$GH_STUB_LOG.stdin")" == 'Fixed in def456.' ]]
}

@test "an unknown subcommand: usage error, exit 2" {
  rules
  run --separate-stderr "$THREAD" frobnicate 27
  [[ "$status" -eq 2 ]]
  [[ -z "$output" ]]
  [[ "$stderr" == *usage* ]]
}

# --- edge cases ----------------------------------------------------------------

pr6_rules() {
  rules '*after=R1*|pr-6-reviews-p2.json' '*after=T1*|pr-6-thread-p2.json' '*issueOrPullRequest*|pr-6-p1.json'
}

@test "index: every page of the reviews and of an inline thread; outdated, no line, ghost author" {
  pr6_rules
  run --separate-stderr "$THREAD" index 6 -o "$OUT"
  [[ -z "$stderr" ]]
  [[ "$status" -eq 0 ]]
  [[ "$output" == '1 PR_6 2026-10-16 ghost body 18 -
2 PRR_1 2026-10-16 lepeuvedic review:COMMENTED 0 -
3 PRRC_5 2026-10-16 lepeuvedic inline 22 SKILL.md:40 outdated
    Say why.

    In one line.
4 PRRC_6 2026-10-16 engineer reply 5 SKILL.md:40 outdated
    Done.
5 PRR_2 2026-10-16 lepeuvedic review:APPROVED 8 -' ]]
}

@test "read: CRLF line ends are normalised" {
  pr6_rules
  run --separate-stderr "$THREAD" read 6 1 -o "$OUT"
  [[ -z "$stderr" ]]
  [[ "$status" -eq 0 ]]
  [[ "$output" == '1 PR_6 2026-10-16 ghost body 18 -
Line one
Line two' ]]
}

@test "read: a position past the end is an error; a malformed range a usage error" {
  issue_rules
  run --separate-stderr "$THREAD" read 27 5 -o "$OUT"
  [[ "$status" -eq 1 ]]
  [[ -z "$output" ]]
  [[ "$stderr" == 'thread.sh: no message 5 (4 in #27)' ]]
  for r in 0 3-2 a 1-2-3 -0; do
    run --separate-stderr "$THREAD" read 27 "$r" -o "$OUT"
    [[ "$status" -eq 2 ]]
    [[ -z "$output" ]]
    [[ "$stderr" == *usage* ]]
  done
}

@test "read -9 on a thread of 4 messages gives all of it" {
  issue_rules
  run --separate-stderr "$THREAD" read 27 -9 -o "$OUT"
  [[ -z "$stderr" ]]
  [[ "$status" -eq 0 ]]
  [[ "$output" == '1 I_27 '* ]]
  [[ "$(grep -c '^[0-9] ' <<< "$output")" -eq 4 ]]
}

@test "overflow: the 16 KiB limit applies with few lines" {
  long=$(head -c 17000 /dev/zero | tr '\0' x)
  mkdir "$BATS_TEST_TMPDIR/fix"
  jq --arg b "$long" '.data.node.body = $b' "$GH_STUB_DIR/node-IC_1.json" > "$BATS_TEST_TMPDIR/fix/long.json"
  export GH_STUB_DIR="$BATS_TEST_TMPDIR/fix"
  rules '*IC_1*|long.json'
  run --separate-stderr "$THREAD" get IC_1 -o "$OUT"
  [[ -z "$stderr" ]]
  [[ "$status" -eq 3 ]]
  check_report "$OUT"
  [[ "$(sed -n 2p "$OUT")" == "$long" ]]
}

@test "get: an unknown id is an error" {
  rules '*IC_404*|node-null.json'
  run --separate-stderr "$THREAD" get IC_404 -o "$OUT"
  [[ "$status" -eq 1 ]]
  [[ -z "$output" ]]
  [[ "$stderr" == 'thread.sh: no message IC_404' ]]
}

@test "a GraphQL answer with errors is a failure, even with exit 0" {
  rules '*issueOrPullRequest*|graphql-errors.json'
  run --separate-stderr "$THREAD" index 99 -o "$OUT"
  [[ "$status" -eq 1 ]]
  [[ -z "$output" ]]
  [[ "$stderr" == 'thread.sh: gh: Could not resolve to an issue or pull request with the number of 99.' ]]
}

@test "post: a failed call is one line on stderr" {
  rules '*issues/27/comments*|!1 HTTP 403: Resource not accessible'
  run --separate-stderr "$THREAD" post 27 <<< 'Hello'
  [[ "$status" -eq 1 ]]
  [[ -z "$output" ]]
  [[ "$stderr" == 'thread.sh: gh: HTTP 403: Resource not accessible' ]]
}

@test "post: a body of blanks only is empty" {
  rules '*issues/27/comments*|posted.json'
  run --separate-stderr "$THREAD" post 27 <<< $'  \n\t'
  [[ "$status" -eq 2 ]]
  [[ -z "$output" ]]
  [[ "$stderr" == 'thread.sh: empty body: nothing posted' ]]
  [[ ! -s "$GH_STUB_LOG" ]]
}

@test "reply: an id that is not an inline review comment is refused" {
  rules '*IC_1*|node-IC_1.json'
  run --separate-stderr "$THREAD" reply IC_1 <<< 'Fixed.'
  [[ "$status" -eq 1 ]]
  [[ -z "$output" ]]
  [[ "$stderr" == 'thread.sh: IC_1 is not an inline review comment' ]]
  run ! grep -q replies "$GH_STUB_LOG"
}

@test "post and reply take no -o; post takes a number" {
  rules
  run --separate-stderr "$THREAD" post 27 -o "$OUT" <<< 'x'
  [[ "$status" -eq 2 ]]
  [[ "$stderr" == *usage* ]]
  run --separate-stderr "$THREAD" post abc <<< 'x'
  [[ "$status" -eq 2 ]]
  [[ "$stderr" == *usage* ]]
  [[ ! -s "$GH_STUB_LOG" ]]
}

@test "GH_REPO in the HOST/OWNER/NAME form" {
  rules '*issues/27/comments*|posted.json'
  GH_REPO=github.com/acme/widgets run --separate-stderr "$THREAD" post 27 <<< 'Hi'
  [[ -z "$stderr" ]]
  [[ "$status" -eq 0 ]]
  grep -q 'repos/acme/widgets/issues/27/comments' "$GH_STUB_LOG"
}

return 0

# --- Change History -------------------------------------------------------
# | PR     | Summary                                                       |
# |--------|---------------------------------------------------------------|
# | #30    | new: thread.sh contract, gh stubbed (#27)                     |
# | #36    | run ! grep -q; directives with their reason (#29)             |
