---
name: scm-skill
description: Guide for software configuration management processes. Use this skill for all software development workflow tasks, including issue management, branching, testing, reviewing, and implementing changes. Triggers on any request related to SCM processes, such as creating issues, starting branches, running tests, reviewing code, or updating code.
---

# Software Configuration Management

## Overview

This skill keeps the surface area small: it helps you decide whether you are managing a GitHub issue (creating, updating, triaging, or tagging) or actually implementing an approved change. The detailed workflow — six numbered tasks, each made of named steps — lives in the companion reference files so the top-level document can stay focused on task selection and guardrails.

**Critical Rule: Never commit directly to the main branch.** All changes to git-tracked files, including .vscode configurations, must be developed on feature branches and merged via pull requests. Direct commits to main will fail on protected branches and violate the SCM process. Each feature branch is developed in its own worktree — see *Worktrees and Parallel Sessions*.

## Task Selection

1. **Meta-task path** – Use this skill (and the `github-issues` skill) for issue creation, triage, labeling, or other housekeeping that does _not_ touch git-managed configuration items. Keep the local clone synchronized with `origin/main`, maintain a read-only copy of `main` for reference, and avoid committing until an Issue Assessment is approved. A new issue must reach the board in *Backlog* (see *Kanban Board*). Issues are never reopened: write a new issue that references the old one.
2. **Shared Issue Understanding** – Trigger this task when a GitHub issue is identified for implementation. Precondition: Issue exists and is assigned. Perform the Issue Assessment & Approval step to identify blockers. **Post the assessment result as a comment on the issue** — this is the mandatory deliverable of this task — then obtain explicit reviewer approval before touching any git-tracked file. When the assessment is approved, move the issue to *Ready*. Do not proceed to other tasks without approval. *Engineer*: writes and posts the assessment. *Conductor*: starts the engineer, assesses approval, moves the card.
3. **Implementation Planning** – Trigger this task on an issue after approval in Task 2. Precondition: Task 2 completed with approval. Perform Detailed Planning and record the plan in the issue. No branch is created and no git-tracked file changes in this task. Do not proceed to other tasks without approval of the detailed plan. *Engineer*: writes and posts the plan. *Conductor*: assesses approval.
4. **Test Driven Development** – Trigger this task after detailed plan validation in Task 3. Precondition: Task 3 completed with validated plan. Start by creating the branch and its worktree and moving the issue to *In progress*. Perform Documentation, Preliminary Tests Definition steps, commit the preliminary tests on their own and record that they fail against the unchanged code, then confirm that the documentation builds properly and is in strict adherence to the detailed plan. Confirm that the preliminary tests are a straightforward illustration of the documented behavior and correct if needed, post the branch compare link in the issue, then **stop**. Do not proceed without approval on the documentation and the preliminary tests. *Conductor*: creates the branch and worktree, moves the card, assesses approval. *Engineer*: everything else.
5. **Implementation** – Trigger this task after documentation and preliminary tests in Task 4 have been approved. Perform Source code Implementation, Edge-cases Tests Expansion, Testing, and Prepare for Review steps **in that order**. Finally, when the first version is ready for review, create the PR (`Closes #N`), push the change-history commit with its number, then enable auto-merge and request review, and update the source code until the PR automated tests pass or until you discover an inconsistency in the tests. Ask permission to return to Task 4 if needed. Follow the formal review process of the PR and make updates as directed by the maintainers. *Engineer*: code, tests, PR, change history, review replies. *Conductor*: auto-merge, review request, board check, forwarding review comments.
6. **Integration** – Trigger this task after review approval in Task 5. Precondition: Task 5 completed with maintainer review approval. Perform Final Integration and Validation until GitHub automatically merges the branch into `main` and deletes the remote branch. Evaluate new commits to main that must be integrated via rebase, final testing using the whole test suite, checking the tests status on the GitHub PR, local repository resynchronization after the merge (squash and merge). Verify that the issue reached *Done* and is closed. All edits must be minimal and justified at this stage. *Engineer*: the rebase, if `main` moved. *Conductor*: everything else.

## Meta-task Guidance

- Confirm you are operating on a clean baseline (`git fetch origin && git status`) before performing any meta-task.
- Route lightweight branch/tag housekeeping through this skill's meta-task guidance; only enter the implementation path when configuration work is both scoped and approved.

## Paths: the skill and the project

Projects install this skill as a **fixed copy** of one commit, reached through a link (`<skill>/tools/skill-copy.sh use`, see `README.md`), so it may sit anywhere. In this skill, `<skill>/…` is a path inside the skill's own directory: the *Base directory for this skill* that Claude Code announces when it loads the skill. Claude Code announces the **link path, not its target**, and the link may move to another copy of the skill while a session runs. So, when the skill loads, resolve the announced directory once (`readlink -f <base directory>`) and use only the resolved path for the rest of the session. The one exception is the conductor's update at session start (see *Updating the skill at session start*): when it moves the link, the conductor resolves the announced directory a second time, right away and before it hands `<skill>` on. Whenever you hand `<skill>` on, as in an order to the engineer, hand on the resolved path. Never look for these files at the project root. Every other path is relative to the root of the project you work on. Project-specific configuration lives in the project, never in the skill.

## Conductor and Engineer

Two roles share the work of an issue, each on the model that suits it. Every step of the reference files says who does it on its `By` line.

- **The conductor** is the main session, started on Sonnet (`claude --model sonnet`). It runs the process: the checks at the start of each task, board moves, worktree creation and removal, syncing `main`, auto-merge, review requests. It reads the maintainer's comments and assesses approval. It does not read what the engineer writes. A conductor that finds itself on another model says so once to the maintainer and carries on.
- **The engineer** is the `scm-engineer` agent, on Opus (`<skill>/agents/scm-engineer.md`, installed by `<skill>/tools/skill-copy.sh use` with the skill, one link per agent). It does the work that needs judgement: assessment, plan, documentation, tests, code, PR, review replies, rebase. It posts on GitHub and commits in the worktree itself.

**Updating the skill at session start.** Once per conductor session, right after the skill loads and `<skill>` is resolved, and **before** the checks at the start of the first task and before the engineer starts, the conductor runs, from the project root, `<skill>/tools/skill-copy.sh update <skill>`. It brings the project's copy up to `origin/main` of the skill's repository (see `README.md`, *Updating*), and prints one line:
- `updated <old> <new> <copy>`: the links moved. The conductor resolves `<skill>` again (`readlink -f <base directory>`, see *Paths*), re-reads `SKILL.md` from the new `<skill>`, and tells the maintainer in one line: `scm-skill updated <old> → <new>`. No restart is needed: so far the conductor has read only `SKILL.md`, so reading it again brings its context up to date. The engineer started afterwards gets the new `<skill>` in its order.
- `current <sha>` or `kept <sha> ahead|diverged`: nothing moved; the conductor carries on.
- A non-zero exit (offline, refused, failed): the conductor gives the maintainer the one-line warning and carries on with the current copy. **The update never blocks the work.**

The update is for the whole project: the sessions started later get the new copy, and a session already running keeps the copy it resolved.

**Starting the engineer.** The conductor starts one engineer per issue per session, in the background (`Agent` with `subagent_type: scm-engineer`), and gives every later order to the same engineer with `SendMessage`, so the engineer keeps its context from task to task. A new conductor session starts a new engineer, which catches up from the issue thread: the issue thread is the durable memory of the work.

**An order** gives the issue number, the task, the worktree path (from Task 4), the skill's resolved directory `<skill>` (see *Paths*), the `GH_CONFIG_DIR` to use, and the maintainer's comment, forwarded verbatim, when there is one. After a deliverable, the conductor orders either:
- *iterate*, with the comment, when the comment does not approve. A dubious approval is not an approval: the conductor orders *iterate*. Real approvals are explicit.
- *move on to Task N*, when the comment approves, after moving the card.

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

The maintainer steers from the project board. Workflows of the board make most moves; the conductor makes only the moves no workflow can make, and verifies the others. **Only issues have cards**: a PR shows on its issue's card through the `Closes #N` link. The one exception is a reopened PR (see *Events outside the task sequence*).

- **Finding the board**: the board of an issue is in the issue's own `projectItems`, since the board's auto-add workflow puts every new issue there. Cross-check it with the *Kanban* line of the repository's *Session bootstrap* issue. If there is no board, more than one, or the two disagree: **stop and ask the maintainer**.
- **Moves along the tasks** (the end of a task is the start of the next one):

  | Task | At start | During | At end |
  |---|---|---|---|
  | 1. Meta-task: issue creation | — | — | *Workflows*: issue added → **Backlog**. *Conductor*: verifies the card. |
  | 2. Shared Issue Understanding | — | — | *Conductor*: assessment approved, issue → **Ready**. |
  | 3. Implementation Planning | — | — | — |
  | 4. Test Driven Development | *Conductor*: creates the branch and worktree, issue → **In progress**. | — | — |
  | 5. Implementation | — | First version ready for review. *Engineer*: opens the PR with `Closes #N`, pushes the change-history commit with its number. *Conductor*: runs `gh pr merge --auto --squash`, then requests review. *Workflows*: PR linked to the issue → issue **In review**. *Conductor*: verifies the issue is *In review* and that no PR card was added. | *Maintainer*: approves. *GitHub*: auto-merges. |
  | 6. Integration | *Workflows*: PR merged and issue closed → issue **Done**. *Conductor*: verifies the card and that the issue is closed. | — | — |

- **Events outside the task sequence**:
  - *Conductor*: **a reopened PR** — a PR is reopened when its issue has not changed but the implementation needs rework. The conductor that reopens it adds it to the board (`gh project item-add`) and sets it to **In review** (`gh project item-edit`); no workflow is relied on. It is the only kind of PR card allowed. At merge it goes to **Done**: if no workflow moved it, the conductor moves it in Task 6.
  - *Workflows*: old **Done** items are archived.
  - An issue is never reopened.
- **Checks at the start of every task**: an issue is *In review* only while it has an open linked PR; an issue with an open linked PR is *In review*; a PR card exists only for a reopened PR, *In review* while open, then *Done*; an **open issue in *Done*** means the maintainer stopped the work — stop, ask for the reason, record it on the issue, and close it (`completed` or `not planned`) once confirmed. Meta-tasks run the same checks on every open issue and PR of the repository. If a workflow did not fire, report it rather than move the card by hand.
- **Commands** (IDs are looked up by name each time, never hard-coded):
  ```sh
  # Every open issue with its open linked PRs and its card; every open PR with its reopen count and its card (expected: none, unless reopened)
  gh api graphql -F o=OWNER -F r=REPO -f query='query($o:String!,$r:String!){repository(owner:$o,name:$r){
    issues(states:OPEN,first:100){nodes{number closedByPullRequestsReferences(first:5,includeClosedPrs:false){nodes{number}} projectItems(first:5){nodes{id project{id number} fieldValueByName(name:"Status"){... on ProjectV2ItemFieldSingleSelectValue{name}}}}}}
    pullRequests(states:OPEN,first:100){nodes{number timelineItems(first:1,itemTypes:[REOPENED_EVENT]){filteredCount} projectItems(first:5){nodes{id project{id number} fieldValueByName(name:"Status"){... on ProjectV2ItemFieldSingleSelectValue{name}}}}}}}}'
  # Status field and option IDs of board P
  gh project field-list P --owner OWNER --format json --jq '.fields[]|select(.name=="Status")|.id as $f|.options[]|"\($f) \(.id) \(.name)"'
  # Add a reopened PR to board P (prints the new item ID)
  gh project item-add P --owner OWNER --url PR_URL --format json --jq .id
  # Move a card
  gh project item-edit --id ITEM_ID --project-id PROJECT_ID --field-id FIELD_ID --single-select-option-id OPTION_ID
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

Every implementation status update should cite the relevant assessment in the issue comments so reviewers understand that the change followed this documented process.

**Note**: Conversations in pull requests are resolved by the maintainer, not by the implementer. The implementer provides summaries of changes made in response to each conversation but does not mark them as resolved.
