# Implementation

**Precondition**: Task 4 (Test Driven Development) completed with approval on documentation and preliminary tests. Do not proceed without approval.

This task covers source code implementation, edge-cases tests expansion, testing, and prepare for review.

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
- **Note**: Do not revisit the test design from Task 4 once this begins. Instead return to Task 4 after human approval of an adequate justification if the core tests are wrong.

## Edge-cases Tests Expansion
- **Objective**: Expand tests to cover edge cases.
- **By**: `scm-engineer`.
- **Activities**:
  - Add tests for edge cases based on the implementation.
  - Apply the same test-writing standards as the preliminary tests (see `test-driven-development.md`): assert on every captured stderr stream (match the diagnostic, or assert empty on a clean path), keep replaced tests as commented `REVIEW PLACEHOLDER` blocks instead of silently deleting them, and remove the placeholders already present in any test file this PR edits.
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
  - Open the PR when the first version is ready for review, not earlier, with a descriptive title and a body referencing the issue, written in a here-doc: `gh pr create --title … --body-file - <<'SCM_BODY'` (see `shell-tools.md`). Its body carries `Closes #N` for the issue: this links the PR to the issue, so the board workflows move the **issue** to *In review* and GitHub closes it at merge. The PR gets no card.
  - Now that the PR number is known, update the change history section of every file modified by this PR, except exempt files. Read the index in `templates.md`, then only the `template-*.md` files it chooses for this PR's file types; an installed add-on may supply them. Update the *Change History* block of each file, and, for skill files, the skill directory's `history.md` instead of the skill file itself. Use `gh api repos/{owner}/{repo}/pulls/{n}/files` to confirm the exact set of changed files — do not rely on `git log`. Commit and push.
  - Once the history commit is pushed, enable auto-merge (`gh pr merge --auto --squash`): the maintainer's approving review then triggers the merge.
  - Check that the branch is not behind `main` (see *Sync with `main`* in `SKILL.md`); if it is, the engineer syncs it first. Syncing is part of this task: a sync after the approval, when `main` moves during Task 6, brings the issue back here for a new review.
  - Assign the **maintainers team** as reviewers (@CriticalOptimisation/maintainers). This request is the signal that the PR is ready for review, so it comes after the history commit, auto-merge and the sync.
  - Link the original issue and summarize the changes.
  - Address review feedback iteratively: read each comment by its id (`thread.sh get`), answer inline threads with `thread.sh reply`, and other points with `thread.sh post`.
- **Validation**: The pull request shows an approved review from a maintainer in GitHub (check the 'Reviews' tab; conversation resolution alone is insufficient).
- **Note**: Update the source code until the PR automated tests pass or until you discover an inconsistency in the tests. Ask permission to return to Task 4 if needed, and explain why you need to do that. Otherwise, follow the formal review process of the PR and make updates as directed by the maintainers.