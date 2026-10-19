# Test Driven Development

**Precondition**: Task 3 (Implementation Planning) completed with validated plan. Do not proceed without plan validation.

This task covers branch creation, documentation updates and preliminary tests definition.

## Branch and Worktree Creation
- **Objective**: Create an isolated workspace for the approved plan, without touching the main worktree. The branch is needed to commit the preliminary tests and check that they fail before the implementation starts.
- **By**: the conductor, before it orders `scm-engineer` to start Task 4.
- **Activities**:
  - Choose the branch name `{type}/{number}-{short-description}`, where {type} is:
    - `feature` for new features
    - `bug` for bugs (actual behavior different from documented or desirable behavior, or documentation error, or skill/process description error)
    - `test` for issues requiring additional tests, but failing tests must be labelled `bug` if they should pass and the error appears to be in the test rather than the library
    - `doc` for issues involving only documentation but not errors (e.g., translations, etc.)
  - From the main worktree, run `<skill>/tools/worktree.sh new {type} {number} {short-description}`, where `<skill>` is this skill's own directory (see *Paths* in `SKILL.md`), never the project root. It fetches `origin`, creates the branch from `origin/main`, creates the worktree `.worktrees/{number}-{short-description}`, links the untracked paths listed in the project's link list, and, in a session started from VS Code, opens the worktree's `.git` file so that VS Code shows the worktree in *Source Control Repositories* (see *Worktrees and Parallel Sessions* in `SKILL.md`).
  - **Work only inside that worktree from now on.** Never switch the branch of the main worktree: that is the maintainer's prerogative.
  - From the worktree, push the branch with its upstream (`git push -u origin HEAD`).
  - Move the issue to *In progress* on the board (see *Kanban Board* in `SKILL.md`).
- **The script's contract** (`<skill>/tools/worktree.sh`, tested by `<skill>/tools/worktree.bats` and `<skill>/tools/worktree-links.bats`):

  | Command | Effect |
  |---|---|
  | `new {type} {number} {short-description} [base]` | branch + worktree under `.worktrees/`, links posed; `base` defaults to `origin/main`; then the VS Code step below |
  | `link` | creates or repairs the links of the current worktree; idempotent |
  | `check` | verifies the links; changes nothing; exits non-zero on a missing or broken link |
  | `reclaim` | in the main worktree only: if the current branch has disappeared from `origin` and the tree is clean, switches back to `main` and fast-forwards it |
  | `drop {number}-{short-description}` | removes a clean worktree and prunes; never deletes a link target |

  - **The link list** is read from the checkout the script runs in:

    | `tools/worktree.links` | `.worktree-links` | Result |
    |---|---|---|
    | present | absent | used |
    | absent | present | used |
    | present | present | `tools/worktree.links` is used, and every `new`, `link` and `check` warns on stderr: `warning: both tools/worktree.links and .worktree-links exist; using tools/worktree.links — remove one`. Exit status is unchanged. |
    | absent | absent | nothing to link: `new`, `link` and `check` succeed and say `no link list: nothing to link` |

    `link` and `check` say which list they read: `link list: <file>`. One path per line; `#` starts a comment; a trailing `/` is dropped.
  - **The VS Code step** of `new` runs only when `VSCODE_IPC_HOOK_CLI` is set and `code` is on the `PATH`; otherwise it is skipped without a message. It runs `code -r <worktree>/.git` and says `opened in VS Code: <worktree>/.git`. If `code` fails, `new` warns `warning: VS Code could not open <worktree>/.git; reload the window to list the worktree in Source Control Repositories` and still succeeds: the worktree and its links are kept. A refused or failed `new` never calls `code`, and `drop` never does.
  - **Exit status**: `0` success; `1` a check failed or git failed; `2` usage error; `3` refused for safety. Safety refusals are tested on code `3`, so that a missing script (exit `127`) can never pass them.
  - **Detection never trusts paths**, which symbolic links falsify. A worktree is linked when `git rev-parse --git-dir` differs from `--git-common-dir` (compared after `realpath`) **and** its `.git` is a file rather than a directory. If the two tests disagree, the script stops.
  - **`link` refuses the main worktree**, never overwrites a real directory, and refuses any path that git does not ignore *as a link*: the matching `.gitignore` entry must be anchored and have no trailing slash (`/poc-data`, not `poc-data/`), because git treats a symbolic link as a file.
- **Validation**: The branch exists and is pushed, its worktree exists under `.worktrees/`, and `<skill>/tools/worktree.sh check` passes inside it. The issue is *In progress*.

## Documentation Updates
- **Objective**: Keep docs, comments, and AI skills aligned with the code.
- **By**: `scm-engineer`.
- **Activities**:
  - Update README, Sphinx docs, skill files, or other relevant documentation.
  - Include usage notes, caveats, and cross-references as needed.
  - Commit the documentation changes.
- **Validation**: Documentation builds successfully (use `sphinx-docs` when applicable).

## Preliminary Tests Definition
- **Objective**: Define preliminary tests to illustrate the documented behavior.
- **By**: `scm-engineer`, including the failure record, the handoff and the compare link; the conductor assesses approval.
- **Activities**:
  - Extend the relevant test suite (`test/...`), keeping new tests close to the projected behavior being implemented (focus on core tests that illustrate new or corrected behaviors, not edge cases).
  - Follow coding standards; use `xfail` tags for tests that are known to fail temporarily.
  - **Assert on captured stderr.** Whenever a bats test captures stderr (`run --separate-stderr`), assert its expected content: for an error/warning path, match the diagnostic (`[[ "$stderr" == *"..."* ]]`); for a clean/happy path, assert it is empty (`[[ -z "$stderr" ]]`). A captured stream that is never asserted is an untested output.
  - **Never silently delete a test.** When a change removes or replaces an existing test, either convert it in place or keep the old test **as comments** next to its replacement, under a `REVIEW PLACEHOLDER` line mapping the old title to the new test(s) that cover it (`old title -> new title`). The reviewer can then compare old and new tests and check that the test scope was not reduced too much. Tests are not shipped, so the placeholders stay in the merged tests. **The next PR that edits the same test file removes all the placeholders already in it**: they were reviewed in their own PR. That PR's own new placeholders stay until the next one.
  - Include clear commit messages referencing the issue.
  - When necessary, re-use helper modules such as `bats-support` or `bats-assert` from the `devel` branch.
  - Commit the extended test suite **on its own**, before any implementation change, so that a later branch can start from it if the tests turn out to fire regardless of the implementation.
  - Run the new tests against the unchanged code and record the result in the issue: each new test must fail, and fail on the behaviour it illustrates.
  - **On a return to Task 4** (see *Return to Task 4* in `implementation.md`), the engineer **never deletes a test** that exists on the branch, preliminary or edge-case. A test it changes or drops is commented out under a `REVIEW PLACEHOLDER` line (`old title -> new title`), as a new set of placeholders. It **wipes the placeholders** the questioned Task 4 added: they were reviewed with it, and the tests they led to, now questioned, become the new placeholders. The questioned patches stay readable in the handoff. The reworked deliverable goes on the issue, like every Task 4 deliverable, and links the PR and the engineer's conclusions.
- **Validation**: Tests compile/run locally and reflect the intended behavior. New tests must fail at this step (use xfail if needed); a passing new test does not discriminate between old and new behaviors.
- **Note**: Confirm that the preliminary tests are a straightforward illustration of the documented behavior and correct if needed. Post the branch compare link (`https://github.com/{owner}/{repo}/compare/main...{branch}`) in the issue so the maintainer can review the work before any PR exists, with the handoff (see *Handoff*), then **stop**: this deliverable is the engineer's last (see *Handoff*). Do not proceed to other tasks without approval on the documentation and the preliminary tests.

## Handoff
- **Objective**: Give the fresh engineer of Task 5 everything the Task 4 engineer knows. Anything the maintainer cannot see on the issue, in a commit or in a file is lost when the engineer stops.
- **By**: `scm-engineer` writes it in every Task 4 deliverable; on approval, the conductor stops the engineer and starts a fresh one for Task 5.
- **Activities**: the Task 4 deliverable has a handoff section, with these items:
  1. **Decisions and rulings**: the decisions and maintainer rulings that apply to the code.
  2. **Internal structures**: the internal structures chosen by the plan.
  3. **Departures from the plan**: any, with the reason; "none" otherwise.
  4. **Test commands**: the commands that run the tests.
  5. **Failure record**: the record of the failing tests, so the check of the branch state compares against one place.
  6. **What Task 5 still has to do**.
  7. **Patches of the questioned update**, after a return to Task 4 only: the documentation and test diff approved at the previous Task 4 and now replaced, as `git diff` output limited to the documentation and test files, in a collapsed `<details>` block. On a first Task 4 there is none: the branch diff is the patch.
- **Citations**: to show what goes wrong, cite the code base as fenced excerpts, each headed by its path, its line range and the short SHA it was read at (`tools/x.sh` L40-52 @ `abc1234`). A permalink may go with an excerpt but never replaces it: a sync rebases the branch and changes every SHA, so a link can stop resolving.
- **The last deliverable counts**: with iterations, the handoff that counts is the one in the last Task 4 deliverable, the one the maintainer approves. Each revision restates it in full and never points to an earlier comment for part of it. An engineer replaced while cold during Task 4 takes the handoff over the same way.
- **Validation**: The handoff has the items above, and the failure record matches the branch.
