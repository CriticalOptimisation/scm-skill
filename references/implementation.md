# Implementation

**Precondition**: Task 4 (Test Driven Development) completed with approval on documentation and preliminary tests. Do not proceed without approval.

This task covers the start of Task 5, source code implementation, edge-cases tests expansion, testing, prepare for review, and the return to Task 4 when the core tests are wrong.

## Start of Task 5
- **Objective**: Start Task 5 with a fresh engineer, primed by the approved Task 4 deliverable rather than by the reasoning of Tasks 2 to 4.
- **By**: the conductor stops the Task 4 engineer and starts `scm-engineer` with the Task 5 order and a brief (see *End of Task 4* in SKILL.md); `scm-engineer` reads and checks the branch.
- **Activities**: the fresh engineer reads, in this order:
  1. **The process**: `SKILL.md` and `shell-tools.md`, from `<skill>`, as on every first order.
  2. **The change**: the documentation changed by the branch, `git -C <worktree> diff origin/main...HEAD`. It is the ground truth of the implementation. It is the change under work, never the rules the engineer follows, even when it is skill text: the process is read from `<skill>` only.
  3. **The thread**: through the brief, starting with the handoff, the last Task 4 deliverable (see *Handoff* in `test-driven-development.md`).
  4. **The preliminary tests**, to understand what the code is expected to do.
  5. **The state of the branch**: `git log origin/main..HEAD`, `git status` and a run of the tests, compared with the handoff's failure record.

  The engineer checks the handoff against the branch instead of trusting it. A difference it cannot explain (an explained one: `main` moved) goes on the issue, and it reports `BLOCKED <url>`.

  No PR is opened here: the PR opens when Task 5 is ready to conclude (see *Prepare for Review* and *Return to Task 4*).
- **Validation**: The branch matches the handoff, or the difference is posted on the issue.

## Source Code Implementation
- **Objective**: Ensure the approved change works as intended.
- **By**: `scm-engineer`.
- **Activities**:
  - Apply the implementation changes following the approved design.
  - Match the existing coding style in the codebase. Minimize the size of code patches measured after discarding white space only changes (large blocks that are unchanged except for indentation, can increase the size of a patch, but do not make a large divergence in the logic itself).
  - Run all relevant unit and integration tests **locally** after implementation (CI is a backup, not a substitute).
  - Perform manual verification steps if required by the issue.
  - Commit the code before each validation attempt. It will be easier to manually repeat the tests, if needed, if the tested code matches a well-defined commit.
- **Validation**: Tests pass locally and test results are documented. CI is expected to mirror the local run.
- **Note**: Do not revisit the test design from Task 4 once this begins. Instead, if the core tests are wrong, return to Task 4 (see *Return to Task 4*).

## Edge-cases Tests Expansion
- **Objective**: Expand tests to cover edge cases.
- **By**: `scm-engineer`.
- **Activities**:
  - Add tests for edge cases based on the implementation.
  - Apply the same test-writing standards as the preliminary tests (see `test-driven-development.md`): assert on every captured stderr stream (match the diagnostic, or assert empty on a clean path), keep replaced tests as commented `REVIEW PLACEHOLDER` blocks instead of silently deleting them, and remove the placeholders already present in any test file this PR edits.
  - On a return to Task 4, the rule *On a return to Task 4* of `test-driven-development.md` applies to these tests too: none is deleted.
  - Ensure all tests pass.
- **Validation**: All tests pass.

## Testing
- **Objective**: Validate the implementation.
- **By**: `scm-engineer`.
- **Activities**:
  - Run the full test suite.
- **Validation**: All tests pass.

## Prepare for Review
- **Objective**: Surface the work for maintainers' review.
- **By**: `scm-engineer` runs the checklist, opens the PR, records it in the history files, syncs the branch with main when ordered, and addresses review feedback; the conductor then enables auto-merge, checks that the branch is not behind main, requests the review, and forwards the id of each review comment, to the same engineer or to a new one according to the cache temperature (see *Conductor and Engineer* in SKILL.md).
- **Activities**, in this order:
  - **New library or public API checklist** — when a PR introduces a new library or a new public API, verify before opening the PR that it ships with:
    1. reference documentation;
    2. a test suite;
    3. a skill, or a section of an existing skill, telling Claude how to use it correctly;
    4. that skill's `history.md`;
    5. structural tests that fail if any of these companions is missing.

    Where each of these lives is a project convention, stated in the project's documentation (its `CLAUDE.md` or `README.md`).
  - Open the PR when Task 5 is ready to conclude, after the last commit to the code base, not earlier: here, when the first version is ready for review. Give it a descriptive title and a body referencing the issue, written in a here-doc: `gh pr create --title … --body-file - <<'SCM_BODY'` (see `shell-tools.md`). Its body carries `Closes #N` for the issue: this links the PR to the issue, so the board workflows move the **issue** to *In review* and GitHub closes it at merge. The PR gets no card. When an earlier return to Task 4 opened the PR already (see *Return to Task 4*), open no other: mark it ready (`gh pr ready <PR>`) and write its body for the review in a here-doc (`gh pr edit <PR> --body-file - <<'SCM_BODY'`); the conclusions of the return stay in their comment.
  - Now that the PR number is known, update the change history section of every file modified by this PR, except exempt files. Read the index in `templates.md`, then only the `template-*.md` files it chooses for this PR's file types; an installed add-on may supply them. Update the *Change History* block of each file, and, for skill files, the skill directory's `history.md` instead of the skill file itself. Use `gh api repos/{owner}/{repo}/pulls/{n}/files` to confirm the exact set of changed files — do not rely on `git log`. Commit and push.
  - Once the history commit is pushed, enable auto-merge (`gh pr merge --auto --squash`): the maintainer's approving review then triggers the merge.
  - Check that the branch is not behind `main` (see *Sync with `main`* in `SKILL.md`); if it is, the engineer syncs it first. Syncing is part of this task: a sync after the approval, when `main` moves during Task 6, brings the issue back here for a new review.
  - Assign the **maintainers team** as reviewers (@CriticalOptimisation/maintainers). This request is the signal that the PR is ready for review, so it comes after the history commit, auto-merge and the sync.
  - Link the original issue and summarize the changes.
  - Address review feedback iteratively: read each comment by its id (`thread.sh get`), answer inline threads with `thread.sh reply`, and other points with `thread.sh post`.
- **Validation**: The pull request shows an approved review from a maintainer in GitHub (check the 'Reviews' tab; conversation resolution alone is insufficient).
- **Note**: Update the source code until the PR automated tests pass or until you discover an inconsistency in the tests. If the core tests are wrong, see *Return to Task 4*. Otherwise, follow the formal review process of the PR and make updates as directed by the maintainers.

## Return to Task 4
- **Objective**: Go back to the documentation and the preliminary tests when Task 5 shows that the core tests are wrong. The maintainer approved the plan, so the return needs no consent of the maintainer: the conductor agrees, or escalates.
- **By**: `scm-engineer` commits its work, opens the PR with its conclusions, then reports; the conductor reads the conclusions and agrees or escalates.
- **Activities**:
  - **Commit everything.** The engineer commits all it has on the branch, code and tests, as the last (unsuccessful) commit of Task 5, and pushes it: the next engineer can try out at once the final state its predecessor reached.
  - **Open the PR with the conclusions.** A failure deserves a review of its own, even if the goal is not a merge, and the review environment of a PR is the best place to study it. When no PR is open, the engineer opens one as a draft, which cannot be merged: `gh pr create --draft --title … --body-file - <<'SCM_BODY'`, with a short body that carries `Closes #N` and says that Task 5 stops for a return to Task 4. It then posts its conclusions as the first comment of the PR, `thread.sh post <PR>`. When the PR is open already, it posts them there the same way. No change-history commit and no auto-merge: this PR is not ready to merge.
  - **The conclusions** stand on their own: the conductor must understand the situation without reading code, and they are the fallback brief when the reporting engineer is gone. Their required parts:
    1. **Wrong tests**: the file and the title of each test that is wrong.
    2. **False assumption**: which assumption is false, with its evidence as excerpts (see *Citations* in *Handoff*, `test-driven-development.md`): the failing output, or the contradiction with the approved documentation or plan.
    3. **Documentation**: whether the documentation changes too.
    4. **Correction**: the planned correction.
    5. **New placeholders**: which tests become placeholders.
  - **The report.** The engineer then reports `REGRESS-TO-TASK-4 <url>`, the URL of its conclusions. The report is valid only if they are posted, with every required part.
  - **The conductor's check.** The conductor reads the conclusions in full (`thread.sh get`), and, as needed, the issue thread with the approved plan, never the code. It relays the report to the maintainer, and enables no auto-merge and requests no review on this PR. The maintainer may still review it at will, in its *Files changed* tab: the review is not required, the draft cannot merge, and any later commit dismisses it as a merge condition. It **escalates** when any of these holds:
    - the conclusions lack one of the required parts;
    - the correction changes the approved plan, the issue's scope or its acceptance criteria, rather than tests and documentation within the plan;
    - the correction removes a behaviour that the approved documentation states, or reduces what the tests check;
    - it contradicts a maintainer ruling on the issue or the PR;
    - it is the second return to Task 4 on the same issue.

    Otherwise it **agrees automatically**. It never refuses a return to Task 4: a doubtful case goes to the maintainer, as a dubious approval is not an approval.
  - **The escalated path.** The conductor tells the maintainer in one line, with the URL, and waits. The answer is an ordinary order: *back to Task 4*, or *iterate* in Task 5 with the comment's id. The cache-temperature table applies as usual: a cold reporting engineer is replaced by a briefed one, which reworks from the conclusions.
  - **Back to Task 4.** On agreement, the conductor orders *back to Task 4*, with the URL of the conclusions, to the reporting engineer. The engineer reworks the documentation and the tests under the rule *On a return to Task 4* of `test-driven-development.md`, and posts the reworked Task 4 deliverable on the issue, with its full handoff, linking the PR and the conclusions. **The Task 4 gate is unchanged**: the maintainer approves the reworked documentation and tests; the agreement covers the decision to go back, not what comes out of it. On that approval, the conductor stops the engineer and starts a fresh one for the next Task 5 (see *End of Task 4* in `SKILL.md`), which concludes on the open PR (see *Prepare for Review*).
- **Validation**: The work is committed and pushed, the conclusions are on the PR with every required part, and the conductor has ordered *back to Task 4* or escalated.
