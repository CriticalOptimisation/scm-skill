# Integration

**Precondition**: Task 5 (Implementation) completed with maintainer review approval. Do not proceed without review approval.

This segment covers final integration and post-implementation validation.

## Final Integration
- **Objective**: Let GitHub integrate the approved change after all protections pass.
- **By**: the conductor: checks, merge watch, local resynchronization, and the notices to the other issues in progress. When main moved, the step aborts and the issue returns to Task 5, where `scm-engineer` syncs the branch.
- **Activities**:
  - Check that the branch is not behind `main` (see *Sync with `main`* in `SKILL.md`). If it is, **abort Task 6 and return to Task 5**: order *sync* to the engineer (the same one or a new one, according to the cache temperature), wait for its `DONE`, request the review again, and start Task 6 over only after the maintainer approves again. Syncing is a Task 5 activity, concluded by a Task 5 review; the other branches are never touched.
  - Ensure CI/CD checks are green.
  - Confirm the PR satisfies branch protection requirements.
  - Allow GitHub to auto-merge once everything is ready (manual merging is not required): auto-merge was enabled when the PR was opened, and the approving review triggers it. GitHub will squash all the commits in one.
  - Update dependent issues or TODOs if applicable.
  - After GitHub merges and deletes the remote branch, from the main worktree:
    1. `git fetch --prune origin`;
    2. `<skill>/tools/worktree.sh reclaim` (`<skill>` is this skill's own directory, see *Paths* in `SKILL.md`) — brings the main worktree back to `main` if the maintainer had left it on the merged branch, and does nothing otherwise;
    3. `<skill>/tools/worktree.sh drop {number}-{short-description}` — removes the branch worktree; VS Code drops it from *Source Control Repositories* by itself. The `.git` tab that `new` opened then shows a deleted file: close it, or let the optional `workbench.editor.closeOnFileDelete` setting close it (see the README);
    4. delete the local branch (`git branch -D`), since a squash merge leaves it unmerged in git's eyes.
  - Notify the conductors in charge of the other issues *In progress* or *In review* (`board.sh list`): a one-line comment on each, `main moved: #N merged as <sha>; sync this branch before its review or merge.`, and one line to the maintainer naming them (see *After the merge* in `SKILL.md`).
  - Stop the engineers of the issue (see *Stopping an engineer* in `SKILL.md`).
  - If the PR addressed multiple issues, manually close any additional referenced issues after confirming tests pass (GitHub closes at most one issue per PR).
- **Validation**: The change merges automatically after meeting the protected branch checks, and local repo is synchronized.

## Post-Implementation Validation
- **Objective**: Confirm the change stabilizes in the repository.
- **By**: the conductor.
- **Activities**:
  - Monitor for regressions or failures triggered by the merge.
  - Confirm that change history entries are present and accurate in all files modified by the PR, except exempt files (see `templates.md`), and that `history.md` files are present in all skill directories touched by the PR.
  - Update release notes or communication channels if required.
  - Confirm that `git worktree list` no longer shows the branch worktree and that the main worktree is on `main`.
  - Confirm on the board that the issue is *Done* and closed; if the PR was a reopened one, its card is *Done* too (see *Kanban Board* in `SKILL.md`). An issue is never reopened: a follow-up is a new issue.
- **Completion**: Issue is marked resolved and all follow-ups addressed.
- **Note**: GitHub will automatically close the associated issue and may delete the branch upon successful merge. The remaining actions are local: return the main worktree to `main` if needed, drop the branch worktree, and synchronize.