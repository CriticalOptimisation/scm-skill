---
name: scm-skill
description: Guide for software configuration management processes. Use this skill for all software development workflow tasks, including issue management, branching, testing, reviewing, and implementing changes. Triggers on any request related to SCM processes, such as creating issues, starting branches, running tests, reviewing code, or updating code.
---

# Software Configuration Management

## Overview

This skill keeps the surface area small: it helps you decide whether you are managing a GitHub issue (creating, updating, triaging, or tagging) or actually implementing an approved change. The detailed workflow — six numbered tasks, each made of named steps — lives in the companion reference files so the top-level document can stay focused on task selection and guardrails.

**Critical Rule: Never commit directly to the main branch.** All changes to git-tracked files, including .vscode configurations, must be developed on feature branches and merged via pull requests. Direct commits to main will fail on protected branches and violate the SCM process. Each feature branch is developed in its own worktree — see *Worktrees and Parallel Sessions*.

## Task Selection

1. **Meta-task path** – Use this skill (and the `github-issues` skill) for issue creation, triage, labeling, or other housekeeping that does _not_ touch git-managed configuration items. Keep the local clone synchronized with `origin/main`, maintain a read-only copy of `main` for reference, and avoid committing until an Issue Assessment is approved. A new issue must reach the board in *Backlog* (see *Kanban Board*). **A new issue is a problem statement**: a solution described in its body or its first comment is a hint for the assessment, not a decision. Issues are never reopened: write a new issue that references the old one.
2. **Shared Issue Understanding** – Trigger this task when a GitHub issue is identified for implementation. Precondition: Issue exists and is assigned. Perform the Issue Assessment & Approval step to identify blockers. **Post the assessment result as a comment on the issue** — this is the mandatory deliverable of this task — then obtain explicit reviewer approval before touching any git-tracked file. When the assessment is approved, move the issue to *Ready*. Do not proceed to other tasks without approval. *Engineer*: writes and posts the assessment. *Conductor*: starts the engineer, assesses approval, moves the card.
3. **Implementation Planning** – Trigger this task on an issue after approval in Task 2. Precondition: Task 2 completed with approval. Perform Detailed Planning and record the plan in the issue. No branch is created and no git-tracked file changes in this task. Do not proceed to other tasks without approval of the detailed plan. *Engineer*: writes and posts the plan. *Conductor*: assesses approval.
4. **Test Driven Development** – Trigger this task after detailed plan validation in Task 3. Precondition: Task 3 completed with validated plan. Start by creating the branch and its worktree and moving the issue to *In progress*. Perform Documentation, Preliminary Tests Definition steps, commit the preliminary tests on their own and record that they fail against the unchanged code, then confirm that the documentation builds properly and is in strict adherence to the detailed plan. Confirm that the preliminary tests are a straightforward illustration of the documented behavior and correct if needed, post the branch compare link in the issue, then **stop**. Do not proceed without approval on the documentation and the preliminary tests. *Conductor*: creates the branch and worktree, moves the card, assesses approval. *Engineer*: everything else.
5. **Implementation** – Trigger this task after documentation and preliminary tests in Task 4 have been approved. Perform Source code Implementation, Edge-cases Tests Expansion, Testing, and Prepare for Review steps **in that order**. Finally, when the first version is ready for review, create the PR (`Closes #N`), push the change-history commit with its number, then enable auto-merge and request review, and update the source code until the PR automated tests pass or until you discover an inconsistency in the tests. Ask permission to return to Task 4 if needed. Follow the formal review process of the PR and make updates as directed by the maintainers. *Engineer*: code, tests, PR, change history, the sync with `main` before the review request, review replies. *Conductor*: auto-merge, the check that the branch is not behind `main`, review request, forwarding the ids of review comments.
6. **Integration** – Trigger this task after review approval in Task 5. Precondition: Task 5 completed with maintainer review approval, on a branch based on the tip of `main`. If another change reaches `main` during this task, it aborts and the issue returns to Task 5 (see *Sync with `main`*). Perform Final Integration and Validation until GitHub automatically merges the branch into `main` and deletes the remote branch. Evaluate new commits to main that must be integrated via rebase, final testing using the whole test suite, checking the tests status on the GitHub PR, local repository resynchronization after the merge (squash and merge). Verify that the issue reached *Done* and is closed. All edits must be minimal and justified at this stage. *Conductor*: everything, including the notices to the other issues in progress after the merge. The engineer has no part in it: a sync sends the issue back to Task 5.

## Meta-task Guidance

- Confirm you are operating on a clean baseline (`git fetch origin && git status`) before performing any meta-task.
- Route lightweight branch/tag housekeeping through this skill's meta-task guidance; only enter the implementation path when configuration work is both scoped and approved.

## Paths: the skill and the project

Projects install this skill as a **fixed copy** of one commit, reached through a link (`<skill>/tools/skill-copy.sh use`, see `README.md`), so it may sit anywhere. In this skill, `<skill>/…` is a path inside the skill's own directory: the *Base directory for this skill* that Claude Code announces when it loads the skill. Claude Code announces the **link path, not its target**, and the link may move to another copy of the skill while a session runs. So, when the skill loads, resolve the announced directory once (`readlink -f <base directory>`) and use only the resolved path for the rest of the session. The one exception is the conductor's update at session start (see *Updating the skill at session start*): when it moves the link, the conductor resolves the announced directory a second time, right away and before it hands `<skill>` on. Whenever you hand `<skill>` on, as in an order to the engineer, hand on the resolved path. Never look for these files at the project root. Every other path is relative to the root of the project you work on. Project-specific configuration lives in the project, never in the skill.

## Conductor and Engineer

Two roles share the work of an issue, each on the model that suits it. Every step of the reference files says who does it on its `By` line.

- **The conductor** is the main session, started on Sonnet (`claude --model sonnet`). It runs the process: the checks at the start of each task, the board moves no workflow makes, worktree creation and removal, syncing the main worktree with `main`, auto-merge, review requests. It starts and stops the engineers. It reads the maintainer's comments and assesses approval. It does not read what the engineer writes, except once, when it writes the subject index of a brief (see *The brief*). A conductor that finds itself on another model says so once to the maintainer and carries on.
- **The engineer** is the `scm-engineer` agent, on Opus (`<skill>/agents/scm-engineer.md`, installed by `<skill>/tools/skill-copy.sh use` with the skill, one link per agent). It does the work that needs judgement: assessment, plan, documentation, tests, code, PR, review replies, rebase. It posts on GitHub itself, with `<skill>/tools/thread.sh` (see *Posting*), and commits in the worktree itself.

**Updating the skill at session start.** Once per conductor session, right after the skill loads and `<skill>` is resolved, and **before** the checks at the start of the first task and before the engineer starts, the conductor runs, from the project root, `<skill>/tools/skill-copy.sh update <skill>`. It brings the project's copy up to `origin/main` of the skill's repository (see `README.md`, *Updating*), and prints one line:
- `updated <old> <new> <copy>`: the links moved. The conductor resolves `<skill>` again (`readlink -f <base directory>`, see *Paths*), re-reads `SKILL.md` from the new `<skill>`, and tells the maintainer in one line: `scm-skill updated <old> → <new>`. No restart is needed: so far the conductor has read only `SKILL.md`, so reading it again brings its context up to date. The engineer started afterwards gets the new `<skill>` in its order. Claude Code loads agent definitions when a session starts, so that engineer keeps the old `scm-engineer` definition until the next session. This matters little: the definition only states its role, and the engineer reads the process from the new `<skill>`.
- `current <sha>` or `kept <sha> ahead|diverged`: nothing moved; the conductor carries on.
- A non-zero exit (offline, refused, failed): the conductor gives the maintainer the one-line warning and carries on with the current copy. **The update never blocks the work.**

The update is for the whole project: the sessions started later get the new copy, and a session already running keeps the copy it resolved.

**Starting the engineer.** The conductor starts an engineer in the background (`Agent` with `subagent_type: scm-engineer`), with the title `issue #N engineer #n` as its `description`. One conductor may drive several engineers, for one issue or for several, and the maintainer must tell their sessions apart, in the mobile app too. `n` counts the engineers of issue `#N` across conductor sessions: every engineer ends each comment it posts with the line `— issue #N engineer #n`, `thread.sh index` lists that signature in its tags, and a conductor takes the highest `n` it finds plus one. An engineer started at Task 2 reads the issue in full; an engineer started later gets a brief (see *The brief*). Later orders go to the same engineer with `SendMessage`, as long as its cache is not cold.

**Cache temperature** decides whether an engineer is kept. The conductor records the time of each report of the engineer (`date +%s`). When an order is due (a gate answered, an *iterate*, a *sync*, any later order), it compares the time since that report with the lifetimes of the prompt cache:

| Temperature | Time since the last report | The order goes to |
|---|---|---|
| hot | under 5 minutes | the same engineer, with its full context |
| warm | under 1 hour | the same engineer, with its full context |
| cold | 1 hour or more | a new engineer `#n+1`, primed with a brief; then the old one is stopped |

The thresholds are the two lifetimes of the prompt cache, 5 minutes and 1 hour: after its lifetime, a resumed engineer writes its whole context to the cache again. The engineer's requests use the 5-minute lifetime (the transcripts of #27 show cache writes of the 5-minute kind only for the engineer, and of the 1-hour kind only for the conductor), so a warm engineer pays that rewrite once. **Warm counts as hot**: an engineer is kept for up to 1 hour after its last report, because one rewrite of its context costs less than priming a new engineer, which must read the process and the threads again. Only a cold engineer is replaced.

**Stopping an engineer**: the conductor stops its session (`TaskStop`) when it can, and in every case tells the maintainer in one line: `archive session "issue #N engineer #n"`. An engineer is stopped when a new one replaces it, and when its issue is done.

**The brief** primes a new engineer. The conductor gives:
- the **table of contents** of the issue and, once it exists, of the PR: the output of `<skill>/tools/thread.sh index <N>` (see `<skill>/references/shell-tools.md`), with the exact id of every message;
- the **subject index**: each key point discussed in the threads, with the ids of the messages that deal with it. The conductor writes it, and it is the only time it reads the threads: once, in full (`thread.sh read`), when it is about to prime its first new engineer for the issue. It keeps the index in its context and, each time another engineer is about to start, extends it with the messages that arrived since (`thread.sh read <N> <k>-`), without re-reading the rest. A new conductor session writes it again from scratch;
- the id of the maintainer's comment the order answers, and the conductor's short summary of the points it raises;
- the instruction to **err on the safe side**: in doubt, read the full message or the slice, rather than save tokens.

The engineer reads any message in full, by its id, with `thread.sh get`.

**An order** gives the issue number, the task, the engineer's name (`issue #N engineer #n`), the worktree path (from Task 4), the skill's resolved directory `<skill>` (see *Paths*), the `GH_CONFIG_DIR` to use, and, when there is one, the id of the maintainer's comment, which the engineer reads itself with `thread.sh get`: the comment is never copied into the order. After a deliverable, the conductor orders either:
- *iterate*, with the comment's id, when the comment does not approve. A dubious approval is not an approval: the conductor orders *iterate*. Real approvals are explicit.
- *move on to Task N*, when the comment approves, after moving the card.

**Posting.** The engineer posts what it writes for the maintainer itself: `thread.sh post <N>` for a comment, `thread.sh reply <id>` in an inline review thread, `gh pr create --body-file -` for the PR, each with the text in a here-doc, so that no file is written (see `<skill>/references/shell-tools.md`). Each prints only a URL: the text never passes through the conductor, which would pay for it a second time as input.

**Sync with `main`.** Bringing `main` into the branch is a Task 5 activity, concluded by a Task 5 review: the maintainer approves the branch as it will merge. The engineer owns every rebase of its branch. The conductor checks whether the branch is behind `main`, while the engineer is idle, with one command that prints a number: `git -C <worktree> fetch -q origin && git -C <worktree> rev-list --count HEAD..origin/main` (`0`: the branch is based on the tip of `main`).
- **In Task 5**, when the engineer reports the PR ready and before the conductor requests the review: when the branch is behind, the conductor orders *sync*. The engineer rebases, runs the whole suite, pushes (`--force-with-lease`) and reports `DONE`, or `BLOCKED <url>` on a conflict it cannot resolve alone. Then the conductor requests the review.
- **In Task 6**, when another change reaches `main` after the approval: **Task 6 aborts and the issue returns to Task 5.** The conductor orders *sync*; the engineer merges the changes in, checks everything again and reports; the conductor requests the review again, and the maintainer approves again before Task 6 starts over. The earlier approval does not cover the synced branch.

**After the merge**, the conductor never touches the other branches. It notifies the conductors in charge of the other issues *In progress* or *In review* (`board.sh list`): a one-line comment on each, `main moved: #N merged as <sha>; sync this branch before its review or merge.`, and one line to the maintainer naming them. A conductor assesses approval from the maintainer's comments only, so a notice is never taken for one.

**The engineer's report** is one status line, which the conductor relays to the maintainer and acts on:
- `AWAITING-APPROVAL <url>`: a deliverable awaits the maintainer.
- `REGRESS-TO-TASK-4 <url>`: Task 5 found the core tests wrong; the maintainer decides.
- `BLOCKED <url>`: the engineer needs the maintainer.
- `DONE`: the ordered work is finished; the conductor goes on with its own steps.

**Escalation.** The conductor never decides on test failures, rebase conflicts, the content of review comments or a return to Task 4. These go to the engineer, and from the engineer to the maintainer.

**One writer per worktree.** From Task 4, the worktree is the engineer's. The conductor runs git there only while the engineer is idle, and never commits there.

## Worktrees and Parallel Sessions

Several sessions may work on the same clone at the same time. A branch switch in a shared tree changes files under every other session, so branches never share a tree.

- **The main worktree stays on `main`, and switching its branch is the maintainer's prerogative.** No session ever checks out another branch there. The maintainer may open a branch in the main worktree to look at it; Task 6 brings it back to `main` after the merge.
- **Every branch lives in its own worktree**, under `.worktrees/{number}-{short-description}` at the root of the main worktree. The directory is ignored by git. Create it with `<skill>/tools/worktree.sh new` (Task 4), never by hand. The project's `.gitignore` must ignore `/.worktrees/`.
- **Untracked data does not follow a worktree.** Client data, local analyses and generated files exist only in the main worktree. `<skill>/tools/worktree.sh` links the paths listed in the project's **link list** into each worktree; never copy them. Run `<skill>/tools/worktree.sh check` before any step that reads them.
- **The link list** is a project file: `tools/worktree.links`, or else `.worktree-links` at the project root. If both exist, the script uses `tools/worktree.links` and warns on every run until one is removed. If neither exists, there is nothing to link, and that is not an error. Each run names the list it read.
- **One session per worktree.** `git fetch` works from anywhere; commit, rebase and push only from your own worktree.
- **In VS Code**, worktrees appear as separate repositories in the *Source Control Repositories* view (`git.detectWorktrees` is set in `.vscode/settings.json`). *Open Worktree in New Window* gives a simultaneous view of the project; *in Current Window* switches as a branch would.
- **VS Code does not see the session's git commands.** It detects a new worktree when the command runs in one of its own terminals, but the session's shell is not one: it is a process of the Claude Code extension. So `worktree.sh new` opens the new worktree's `.git` file in the session's window (`code -r`), which makes VS Code add the worktree to *Source Control Repositories*; a one-line tab stays open. VS Code notices a removed worktree by itself, so `drop` does nothing for it. Outside VS Code — a plain terminal, a cloud session — the step is skipped: the script runs it only when `VSCODE_IPC_HOOK_CLI` is set and `code` is on the `PATH`, so it reaches the session's own window and never starts VS Code or picks another window.

## Kanban Board

The maintainer steers from the project board. Workflows of the board make most moves; the conductor makes only the moves no workflow can make, with `<skill>/tools/board.sh` (see `<skill>/references/shell-tools.md`). The engineer never moves a card. The conductor reads the moves of the workflows only where its next action depends on them: the checks at the start of every task, and the end of Task 6. **Only issues have cards**: a PR shows on its issue's card through the `Closes #N` link. The one exception is a reopened PR (see *Events outside the task sequence*).

- **Finding the board**: the board of an issue is in the issue's own `projectItems`, since the board's auto-add workflow puts every new issue there. If there is no board or more than one: **stop and ask the maintainer**; `board.sh` refuses in that case.
- **Moves along the tasks** (the end of a task is the start of the next one):

  | Task | At start | During | At end |
  |---|---|---|---|
  | 1. Meta-task: issue creation | — | — | *Workflows*: issue added → **Backlog**. |
  | 2. Shared Issue Understanding | — | — | *Conductor*: assessment approved, `board.sh move <N> Backlog Ready`. |
  | 3. Implementation Planning | — | — | — |
  | 4. Test Driven Development | *Conductor*: creates the branch and worktree, `board.sh move <N> Ready "In progress"`. | — | — |
  | 5. Implementation | — | First version ready for review. *Engineer*: opens the PR with `Closes #N`, pushes the change-history commit with its number. *Conductor*: runs `gh pr merge --auto --squash`, checks that the branch is not behind `main` (see *Sync with `main`*), then requests review. *Workflows*: PR linked to the issue → issue **In review**. | *Maintainer*: approves. *GitHub*: auto-merges. |
  | 6. Integration | *Workflows*: PR merged and issue closed → issue **Done**. *Conductor*: verifies the card and that the issue is closed. | — | — |

- **Events outside the task sequence**:
  - *Conductor*: **a reopened PR** — a PR is reopened when its issue has not changed but the implementation needs rework. The conductor that reopens it gives it a card in **In review** with `board.sh add-pr <PR>`; no workflow is relied on. It is the only kind of PR card allowed. At merge it goes to **Done**: if no workflow moved it, the conductor moves it in Task 6 (`board.sh move`).
  - *Workflows*: old **Done** items are archived.
  - An issue is never reopened.
- **Checks at the start of every task** (`board.sh check` prints the violations, nothing when all is well): an issue is *In review* only while it has an open linked PR; an issue with an open linked PR is *In review*; a PR card exists only for a reopened PR, *In review* while open, then *Done*; an **open issue in *Done*** means the maintainer stopped the work — stop, ask for the reason, record it on the issue, and close it (`completed` or `not planned`) once confirmed. Meta-tasks run the same checks on every open issue and PR of the repository. If a workflow did not fire, report it rather than move the card by hand.
- **Commands** (`<skill>/tools/board.sh`; IDs are looked up by name each time, never hard-coded; contract in `<skill>/references/shell-tools.md`):
  ```sh
  board.sh status <N>              # the column of issue #N, or none
  board.sh move <N> <from> <to>    # refuses if the card is not in <from>
  board.sh check                   # the checks at the start of every task
  board.sh list <column>           # the open issues in a column
  board.sh add-pr <PR>             # card for a reopened PR, in In review
  ```

## Issue Management Guidance

When handling issues, use the `github-issues` skill for execution but follow SCM principles:

1. **Determine action**: Decide if the task is issue creation, update, query, or other housekeeping.
2. **Gather context**: Review repo details, existing labels/milestones, and any related issues.
3. **Structure content**: Always use the custom templates from `<skill>/references/templates.md`, which are tailored for this repository and override any generic templates in the `github-issues` skill.
4. **Execute**: Call the appropriate MCP tool or `gh` command via the `github-issues` skill.
5. **Confirm**: Verify the result on GitHub and ensure the action aligns with meta-task rules.

## Implementation Workflow Summary

Companion reference files under `<skill>/references/` contain full details:

- `shared-issue-understanding.md` — Task 2: Issue Assessment & Approval
- `implementation-planning.md` — Task 3: Detailed Planning
- `test-driven-development.md` — Task 4: Branch Creation, Documentation and Preliminary Tests
- `implementation.md` — Task 5: Source Code, Edge-cases, Testing, and PR
- `implementation-workflow.md` — overview of the six tasks and their steps
- `implementation-execution.md` — Task 5 & 6 execution details
- `integration.md` — Task 6: Final Integration and Validation
- `shell-tools.md` — `tools/thread.sh` and `tools/board.sh`: threads and board
- `templates.md` — issue and PR templates, and the index of the change-history templates `template-*.md`, one file per language

Every implementation status update should cite the relevant assessment in the issue comments so reviewers understand that the change followed this documented process.

**Note**: Conversations in pull requests are resolved by the maintainer, not by the implementer. The implementer provides summaries of changes made in response to each conversation but does not mark them as resolved.
