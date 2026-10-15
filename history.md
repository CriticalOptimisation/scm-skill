# Change History

This file tracks which product or process PRs drove changes to the
software-configuration-management skill files. It is never referenced
from skill content and is not loaded into Claude's context.

| PR  | Closes | Skill files changed | Process change |
|-----|--------|---------------------|----------------|
| #22 | —      | ALL (initial creation) | initial SCM skill framework |
| #23 | —      | ALL | feature/skills update |
| #29 | #25    | SKILL.md | fix duplicated headers |
| #31 | #30    | SKILL.md | remove manual merge instructions |
| #37 | —      | SKILL.md, implementation-workflow.md, templates.md | document meta-task path |
| #45 | —      | SKILL.md | prohibit direct commits to main |
| #52 | #51    | ALL references | restructure task selection; add TDD, planning, integration phases |
| #114 | #112  | references/pr-threads.sh | add pr-threads helper script (added during PATH enforcement PR) |
| #43 | —      | templates.md, implementation.md, integration.md | introduce per-file change history sections |
| #134 | #133  | implementation.md | add new-library checklist: skill command + history.md + structural tests |
| #145 | #143  | SKILL.md, shared-issue-understanding.md | require posting the Task 2 assessment as an issue comment |
| #145 | #143  | test-driven-development.md, implementation.md, integration.md | assert captured stderr; REVIEW PLACEHOLDER for replaced tests + integration cleanup |
| #127 | #126  | SKILL.md, implementation-planning.md, integration.md | one worktree per branch under .worktrees/; the main worktree is the maintainer's; tools/worktree.sh links untracked data |
| #6 | #3    | tools/worktree.sh, tools/worktree.bats | messages in English; every captured stderr asserted |
| #8 | #2    | SKILL.md, ALL references | Kanban board in the process; branch created after plan approval (Task 4); PR when the first version is ready; one numbering (Tasks 1–6, steps named) |
| #9 | #4    | SKILL.md, test-driven-development.md, integration.md, implementation.md, tools/worktree.sh, tools/worktree*.bats | skill self-contained: paths through the skill's own directory; project link list in tools/worktree.links or .worktree-links (both: warning; neither: nothing to link); new-library checklist made general |
| #11 | #10   | SKILL.md, implementation.md, implementation-execution.md, integration.md, templates.md | PRs off the board: the issue card is In review while its PR is open, Done when it closes; only a reopened PR gets a card, added and set to In review by the session; start-of-task checks and board query follow |
| #12 | #7    | SKILL.md, test-driven-development.md, integration.md, README.md, tools/worktree.sh, tools/worktree*.bats | VS Code does not see the session's git commands: `worktree.sh new` opens the worktree's `.git` in the session's VS Code window so it is listed; skipped outside VS Code; a failing `code` only warns |
| #14 | #13   | SKILL.md, tools/skill-md.bats | board query uses filteredCount (not totalCount) for REOPENED_EVENT; totalCount ignores itemTypes |
| #18 | #16   | SKILL.md, implementation.md, tools/skill-md.bats | Prepare for Review reordered: open the PR, commit the change history with its number, then auto-merge, then review request |
| #19 | #17   | test-driven-development.md, implementation.md, integration.md | REVIEW PLACEHOLDER: old test kept as comments next to its replacement; placeholders stay in merged tests; the next PR editing the file removes them; no clean-up after approval |
| #22 | #20   | SKILL.md, ALL references, README.md, agents/scm-engineer.md, tools/agents.sh, tools/agents.bats, tools/skill-md.bats; scripts/detect_unguarded_calls.sh removed | conductor (main session, Sonnet) and engineer (scm-engineer agent, Opus): the conductor runs the process and assesses approval, the engineer writes, posts and commits; By line on every step; agents.sh links the agent definitions; a bash-deploy-libs script removed |
| #25 | #23   | SKILL.md, README.md, agents/scm-engineer.md, .gitignore, tools/skill-copy.sh, tools/skill-copy.bats, tools/skill-md.bats; tools/agents.sh, tools/agents.bats removed | fixed skill copies for every project: skill-copy.sh (ported from skill-repo-development 74caa22) makes one detached copy per project, `.worktrees/skill-<sha12>-<pid>` with USER_PROJECT, links the skill and each agent relatively, sources the skill's hook (frozen option), prunes across projects; agents.sh folded in and removed; `name: scm-skill`; `<skill>` resolved once with readlink -f and handed on resolved |
| #28 | #26   | SKILL.md, README.md, tools/skill-copy.sh, tools/skill-copy.bats, tools/skill-md.bats | auto-update at session start: the conductor runs `skill-copy.sh update <skill>` before the engineer starts, and on `updated` resolves `<skill>` again and re-reads SKILL.md (no restart); `update` follows origin/main of the linked repository, keeps the link directories and `--frozen` (marker `<copy>.frozen`), and never moves the links when offline or refused |
