# Test Driven Development

**Precondition**: Task 3 (Implementation Planning) completed with validated plan. Do not proceed without plan validation.

This task covers branch creation, documentation updates and preliminary tests definition.

## Step 3: Branch and Worktree Creation
- **Objective**: Create an isolated workspace for the approved plan, without touching the main worktree. The branch is needed to commit the preliminary tests and check that they fail before the implementation starts.
- **Activities**:
  - Choose the branch name `{type}/{number}-{short-description}`, where {type} is:
    - `feature` for new features
    - `bug` for bugs (actual behavior different from documented or desirable behavior, or documentation error, or skill/process description error)
    - `test` for issues requiring additional tests, but failing tests must be labelled `bug` if they should pass and the error appears to be in the test rather than the library
    - `doc` for issues involving only documentation but not errors (e.g., translations, etc.)
  - From the main worktree, run `tools/worktree.sh new {type} {number} {short-description}`. It fetches `origin`, creates the branch from `origin/main`, creates the worktree `.worktrees/{number}-{short-description}`, and links the untracked paths listed in `tools/worktree.links`.
  - **Work only inside that worktree from now on.** Never switch the branch of the main worktree: that is the maintainer's prerogative.
  - From the worktree, push the branch with its upstream (`git push -u origin HEAD`).
  - Move the issue to *In progress* on the board (see *Kanban Board* in `SKILL.md`).
- **The script's contract** (`tools/worktree.sh`, tested by `tools/worktree.bats`):

  | Command | Effect |
  |---|---|
  | `new {type} {number} {short-description} [base]` | branch + worktree under `.worktrees/`, links posed; `base` defaults to `origin/main` |
  | `link` | creates or repairs the links of the current worktree; idempotent |
  | `check` | verifies the links; changes nothing; exits non-zero on a missing or broken link |
  | `reclaim` | in the main worktree only: if the current branch has disappeared from `origin` and the tree is clean, switches back to `main` and fast-forwards it |
  | `drop {number}-{short-description}` | removes a clean worktree and prunes; never deletes a link target |

  - **Exit status**: `0` success; `1` a check failed or git failed; `2` usage error; `3` refused for safety. Safety refusals are tested on code `3`, so that a missing script (exit `127`) can never pass them.
  - **Detection never trusts paths**, which symbolic links falsify. A worktree is linked when `git rev-parse --git-dir` differs from `--git-common-dir` (compared after `realpath`) **and** its `.git` is a file rather than a directory. If the two tests disagree, the script stops.
  - **`link` refuses the main worktree**, never overwrites a real directory, and refuses any path that git does not ignore *as a link*: the matching `.gitignore` entry must be anchored and have no trailing slash (`/poc-data`, not `poc-data/`), because git treats a symbolic link as a file.
- **Validation**: The branch exists and is pushed, its worktree exists under `.worktrees/`, and `tools/worktree.sh check` passes inside it. The issue is *In progress*.

## Step 4: Documentation Updates
- **Objective**: Keep docs, comments, and AI skills aligned with the code.
- **Activities**:
  - Update README, Sphinx docs, skill files, or other relevant documentation.
  - Include usage notes, caveats, and cross-references as needed.
  - Commit the documentation changes.
- **Validation**: Documentation builds successfully (use `sphinx-docs` when applicable).

## Preliminary Tests Definition
- **Objective**: Define preliminary tests to illustrate the documented behavior.
- **Activities**:
  - Extend the relevant test suite (`test/...`), keeping new tests close to the projected behavior being implemented (focus on core tests that illustrate new or corrected behaviors, not edge cases).
  - Follow coding standards; use `xfail` tags for tests that are known to fail temporarily.
  - **Assert on captured stderr.** Whenever a bats test captures stderr (`run --separate-stderr`), assert its expected content: for an error/warning path, match the diagnostic (`[[ "$stderr" == *"..."* ]]`); for a clean/happy path, assert it is empty (`[[ -z "$stderr" ]]`). A captured stream that is never asserted is an untested output.
  - **Never silently delete a test.** When a change removes or replaces an existing test, either convert it in place or leave a `REVIEW PLACEHOLDER` comment mapping the old test title to the new test(s) that cover it (`old title -> new title`), so reviewers can see nothing was lost. These placeholders are cleaned up at integration (see `integration.md`).
  - Include clear commit messages referencing the issue.
  - When necessary, re-use helper modules such as `bats-support` or `bats-assert` from the `devel` branch.
  - Commit the extended test suite **on its own**, before any implementation change, so that a later branch can start from it if the tests turn out to fire regardless of the implementation.
  - Run the new tests against the unchanged code and record the result in the issue: each new test must fail, and fail on the behaviour it illustrates.
- **Validation**: Tests compile/run locally and reflect the intended behavior. New tests must fail at this step (use xfail if needed); a passing new test does not discriminate between old and new behaviors.
- **Note**: Confirm that the preliminary tests are a straightforward illustration of the documented behavior and correct if needed. Post the branch compare link (`https://github.com/{owner}/{repo}/compare/main...{branch}`) in the issue so the maintainer can review the work before any PR exists, then **stop**. Do not proceed to other tasks without approval on the documentation and the preliminary tests.