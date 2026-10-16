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

@test "overflow: a long output goes in full to the file, one line on stdout, exit 3" {
  issue_rules
  run --separate-stderr "$THREAD" index 27 -o "$OUT" --max-lines 2
  [[ -z "$stderr" ]]
  [[ "$status" -eq 3 ]]
  [[ "$(cat "$OUT")" == "$ISSUE_INDEX" ]]
  bytes=$(wc -c < "$OUT")
  [[ "$output" == "overflow 4 lines $bytes bytes -> $OUT" ]]
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

@test "the reading commands require -o: usage error, exit 2" {
  issue_rules
  for cmd in "index 27" "read 27 1" "last 27" "get IC_1"; do
    # shellcheck disable=SC2086
    run --separate-stderr "$THREAD" $cmd
    [[ "$status" -eq 2 ]]
    [[ "$stderr" == *usage* ]]
    [[ -z "$output" ]]
  done
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
  [[ "$(cat "$GH_STUB_LOG.stdin")" == '## Plan

`SKILL.md` and $HOME stay as written.' ]]
}

@test "post: an empty body is refused, nothing is posted" {
  rules '*issues/27/comments*|posted.json'
  run --separate-stderr "$THREAD" post 27 < /dev/null
  [[ "$status" -eq 2 ]]
  [[ -z "$output" ]]
  [[ "$stderr" == 'thread.sh: empty body: nothing posted' ]]
  ! grep -q 'comments' "$GH_STUB_LOG"
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
