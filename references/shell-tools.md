# Shell Tools: threads and board

`<skill>/tools/thread.sh` reads and writes the conversations of issues and PRs; `<skill>/tools/board.sh` reads and moves the cards of the project board. They replace the raw `gh` sequences the sessions used to run: each prints only what the session needs, so verbose `gh` output never enters a session's context. Both are tested by `<skill>/tools/thread.bats` and `<skill>/tools/board.bats`.

Common rules:

- **The repository** is `GH_REPO` when it is set, else the repository of the current directory (`gh repo view`). `GH_CONFIG_DIR` is inherited from the environment and never set by the scripts.
- **No raw JSON** on stdout or stderr. A diagnostic is one line, starting with the script's name (`thread.sh: …`, `board.sh: …`).
- **Exit codes**: `0` success; `1` error (a failed `gh` call, a refused move, a check that found violations); `2` usage error; `3` (`thread.sh` only) the output was written to the overflow file.
- Every call to GitHub goes through `gh api`: GraphQL for reading and for the board, REST for posting.

## `thread.sh`

**Messages and ids.** A thread is the issue or the PR with all its messages: the body, the conversation comments, and for a PR its reviews and its inline review threads. Each message is named by its exact GraphQL node id, which every other command takes as a parameter: `I_…` / `PR_…` the body, `IC_…` a conversation comment, `PRR_…` a review, `PRRC_…` an inline review comment. `get` also takes the numeric id of a conversation comment, the `NNN` of a `#issuecomment-NNN` link.

**Nothing is truncated.** Every list is paginated to its end. A page that cannot be fetched fails the command (exit `1`): it never prints a partial result, and it writes no overflow file.

**The overflow file.** The reading commands (`index`, `read`, `last`, `get`) print their output on stdout, exit `0`, and write no file, as long as it is no longer than 200 lines and 16 KiB (`--max-lines <n>` replaces the 200). A longer output would flood the caller's context, so it is written in full to the **overflow file** instead, and stdout gets a short report, exit `3`:

```
overflow <lines> lines <bytes> bytes -> <absolute path>
read it in parts with your Read tool (offset/limit), using the index below; delete it when done (rm -- <absolute path>)
if the file is missing, stop and report BLOCKED: do not retry
index:
<start>-<end> <id>
...
```

- **The index** has one line per message, in the order of the file: the first and last line of its block in the file (from `1`) and its node id. For `read`, `last` and `get`, a block is the message's index line, its body and the empty line after it; for `index`, it is the message's line and, for an inline comment, its indented body.
- **The default overflow file**: without `-o`, the script creates it with `mktemp "${TMPDIR:-/tmp}/thread.sh.XXXXXX.txt"`, outside the project. If it cannot: exit `1`, one line on stderr.
- **Cleaning**: every run of a reading command first deletes the default overflow files (`thread.sh.*.txt` in `${TMPDIR:-/tmp}`) last modified more than 60 minutes ago. No caller needs one for longer. A file named by `-o` is never cleaned.
- **`-o <file>`** names the overflow file instead. It is checked before any call to GitHub; it is refused, exit `2`, with one line on stderr, when it is
  - an existing file that is not a regular file, such as `/dev/stdout`: `thread.sh: -o needs a regular file; omit -o to read the output on stdout`;
  - inside a git work tree and not ignored by git: `thread.sh: -o <file> is not ignored by git; omit -o or use a path outside the project`.
  When the output is short, a regular file left at that path by an earlier run is removed.
- **A missing overflow file** after exit `3` is a process failure, likely to repeat: the caller stops and reports `BLOCKED`, and does not retry.

| Command | Output |
|---|---|
| `index <N> [-o <file>]` | The table of contents of issue or PR `#N`, one line per message (see below). |
| `read <N> <range> [-o <file>]` | The messages of a slice of the index, in full. `<range>`: `5` (one message), `5-9`, `5-` (to the end), `-3` (the last three). A position past the end: exit `1`. |
| `last <N> [-o <file>]` | The last message of the index, in full: `read <N> -1`. |
| `get <id> [-o <file>]` | One message in full, of any kind, by its node id or numeric comment id. |
| `post <N>` | Posts the body read from stdin as a comment on issue or PR `#N`, and prints only the comment's URL. An empty body is refused (exit `2`), and nothing is posted. |
| `reply <id>` | Replies, with the body read from stdin, to the inline review thread of comment `<id>` (`PRRC_…`), and prints only the reply's URL. Empty body: as `post`. |

**The index line**: `<n> <id> <YYYY-MM-DD> <author> <kind> <chars> <tags>`, fields separated by one space.

- `<n>`: the position of the message, from `1`, used by `read`. Messages are in chronological order; the replies of an inline thread follow their root.
- `<kind>`: `body`, `comment`, `review:<STATE>` (`APPROVED`, `CHANGES_REQUESTED`, `COMMENTED`, …), `inline` (the root of an inline thread) or `reply` (a reply in it).
- `<chars>`: the length of the body in characters (Unicode code points).
- `<tags>`, in place of the first line, which says little: the tags found in the body, separated by `, `, each once, in this order: its markdown headings (text without the `#` marks); its item labels (a capital letter and one or two digits, such as `A1`, `D4`); its `#N` references; the file paths in backquotes (with an extension, such as `` `SKILL.md` `` or `` `tools/thread.sh` ``); and the engineer's signature, `engineer #n` (see *Conductor and Engineer* in `SKILL.md`). The `#N` of the signature line itself is not a reference. No tag: `-`.
- **Inline comments are short and given in full.** For `inline` and `reply`, `<tags>` is `<path>:<line>`, then ` resolved` and ` outdated` when they apply, and the body follows on the next lines, each indented by four spaces.

`read`, `last` and `get` print each message as a block: its index line, its body as it is, and an empty line. `get` puts `-` in place of `<n>`, and gives an inline comment its `<path>:<line>` without the thread's state.

Posting reads the body from stdin, so it is written in the command itself, with a here-doc: no file is written, none is left behind.

```sh
<skill>/tools/thread.sh post 27 <<'SCM_BODY'
...
SCM_BODY
```

The delimiter is quoted, so nothing in the body is expanded, and it is `SCM_BODY`, so a body line `EOF` cannot end it early. A PR body takes the same path: `gh pr create --title … --body-file - <<'SCM_BODY'`, which prints only the PR's URL.

## `board.sh`

**The board of an issue** is the one its `projectItems` name; the board's auto-add workflow puts every new issue there. If an issue is on several boards, every command that needs its card refuses (exit `1`, `board.sh: #N is on 2 boards (#3, #5): ask the maintainer`) and changes nothing. Field and option IDs are looked up by name on every call, never hard-coded.

| Command | Output |
|---|---|
| `status <N>` | The column of issue `#N`, or `none` when it has no card. |
| `move <N> <from> <to>` | Moves the card of `#N` from column `<from>` to column `<to>`, and prints `#N <from> -> <to>`. |
| `check` | The checks at the start of every task (*Kanban Board* in `SKILL.md`), on every open issue and PR of the repository: one violation per line, nothing when all is well. Exit `1` when there is a violation. |
| `list <column>` | The numbers of the open issues in that column, one per line. |
| `add-pr <PR>` | Gives reopened PR `#PR` a card on the board of the issue it closes, in *In review*, and prints `PR #PR -> In review`. |

**`move` is as close to atomic as GitHub allows.** GitHub Projects has no compare-and-swap, and one GraphQL request cannot hold both a query and a mutation. So `move` first looks up everything it needs (the card, the board, the field and both options), then reads the card's column and, if it is `<from>`, sends the mutation at once, with nothing in between: the window is one round trip. Then:
- the column was not `<from>`: exit `1`, `board.sh: #N is <actual>, not <from>`, nothing moved;
- `<from>` or `<to>` is not a column of the board: exit `1`, `board.sh: unknown column: <name> (valid: <columns, separated by ", ">)`, nothing moved;
- `#N` has no card: exit `1`, `board.sh: #N has no card`;
- the mutation's answer gives a column other than `<to>`: exit `1`, `board.sh: #N is <actual> after the move, not <to>`.

**The violations `check` prints**, issues first, then PRs, each in ascending number:

| Line | Meaning |
|---|---|
| `#N has open PR #P but is <column>, not In review` | an issue with an open linked PR must be *In review* |
| `#N is In review without an open PR` | an issue is *In review* only while it has an open linked PR |
| `#N is open in Done: ask the maintainer why` | the maintainer stopped the work: stop and ask |
| `PR #P has a card but was never reopened` | only a reopened PR has a card |
| `PR #P was reopened; its card is <column>, not In review` | an open reopened PR's card is *In review* |

`check` reads the reopen count with `filteredCount`: `totalCount` ignores the `itemTypes` filter, which would make every PR look reopened.
