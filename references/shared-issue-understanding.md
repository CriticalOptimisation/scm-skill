# Shared Issue Understanding

**Precondition**: Issue exists and is assigned. This is the first task in the implementation workflow.

This segment covers the initial assessment and approval phase of the implementation workflow.

## Issue Assessment & Approval
- **Objective**: Establish a shared understanding of scope, dependencies, and blockers before editing any git-tracked files.
- **Activities**:
  - Review the issue description, comments, and attachments.
  - Assess technical impact, dependencies, and required configuration changes.
  - Identify **high-level show stoppers** that would prevent the task from progressing immediately (e.g., missing remote test infrastructure, unavailable SSH servers, or blocker secrets).
  - **Post the assessment result as a comment on the GitHub issue.** This is mandatory and is the deliverable of Task 2: the scope, technical impact, dependency/show-stopper analysis, and proposed mitigation must all appear in a single issue comment so the reviewer can respond in-thread. Do not carry the assessment only in the working conversation — it must be recorded on the issue.
  - Ask for and obtain formal reviewer approval before touching any configuration controlled item.
  - When the assessment is approved, move the issue to *Ready* on the board (see *Kanban Board* in `SKILL.md`).
- **Validation**: The assessment comment **and** an approval comment (or explicit sign-off) are both present in the GitHub issue conversation. No git changes until this approval exists. The issue is *Ready* on the board.
- **Prohibition**: Even with formal approval, proceeding is prohibited if high-level show stoppers remain identified. The situation can only be resolved by a revised assessment (e.g., necessary fixtures have been implemented).