# Issue and PR Templates

**Note**: These templates are custom-tailored for this repository and always take precedence over any generic templates provided by the `github-issues` skill. Use these when creating or updating issues to ensure consistency with SCM workflows.

## Bug Report Template

```
## Bug Report

**Title:** [Bug] Brief description of the issue

**Description:**
Detailed description of the bug, including:
- What happened
- What should have happened
- Steps to reproduce
- Environment details

**Severity:** Critical/Major/Minor
**Priority:** High/Medium/Low

**Additional Context:**
- Screenshots
- Logs
- Related issues
```

## Feature Request Template

```
## Feature Request

**Title:** [Feature] Brief description of requested feature

**Problem Statement:**
What problem does this solve?

**Proposed Solution:**
Describe the proposed implementation

**Alternatives Considered:**
Other solutions that were considered

**Acceptance Criteria:**
- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Criterion 3
```

## Pull Request Template

```
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing
- [ ] Unit tests added/updated
- [ ] Integration tests added/updated
- [ ] Manual testing completed

## Related Issues
Closes #123   <!-- mandatory: links the PR to its issue; the issue card carries the review state -->
Related to #456

## Checklist
- [ ] Code follows project standards
- [ ] Documentation updated
- [ ] Tests pass
- [ ] Reviewed by team member
```

### API Reference Example
- Overview
- Authentication
- Endpoints with examples
- Error codes
- Rate limits

### Workflow Guide Example
- Prerequisites
- Step-by-step instructions
- Common patterns
- Troubleshooting
- Best practices

## Change History Section Templates

Every file modified by a PR carries a change history section, unless it is exempt. This section is the index of the templates: it holds the rules shared by every file type, and says where to find the template for each one. Read it, then only the template files for the file types the PR changes.

### Shared rules

- The block sits at the end of the file and holds one row per PR, in ascending PR-number order.
- Use the GitHub API (`gh api repos/{owner}/{repo}/pulls/{n}/files`) to confirm which files a PR actually changed; do not rely on `git log`.
- No backfill: a file gets its block the next time a PR modifies it.
- A summary never contains the comment's own terminator, such as `-->` or `*/`.

### Exempt files

Exempt files never carry a block, whatever the templates say:

- **Generated files**: lockfiles (`package-lock.json`, `go.sum`), files marked `Code generated … DO NOT EDIT.`, and committed build output.
- **Binaries**.
- **Markdown that Claude reads or copies**: `CLAUDE.md`, agent definitions (`.claude/agents/*.md`), slash commands (`.claude/commands/*.md`), and the GitHub issue and PR templates (`.github/**/*.md`). **Skill files** record their history in their skill's `history.md` (see `template-skill-history.md`), never in the file itself.

### Choosing the template

For a file that is not exempt, the template comes from the first source that applies:

1. **Installed project-specific add-on** covering the file type.
2. **Other installed add-on** covering the file type. If several do, use any one of them.
3. **Built-in template** for the file type (table below).
4. **Project-specific fallback rule**: an installed project-specific add-on that gives a generic fallback rule. Such an add-on is never installed automatically.
5. **Available add-on** covering the file type. It is installed automatically (see below).
6. **Built-in fallback rule**. Use the file type's line-comment prefix, in the block of `template-shell.md` without `return 0`. A file type with only block comments wraps the block as `template-markdown.md` does. A file with no comment syntax (JSON, for example) is exempt.

### Built-in templates

| Template file | File types |
|---|---|
| `template-shell.md` | `.sh`, `.bats` |
| `template-rst.md` | `.rst` |
| `template-markdown.md` | `.md` read by people: README, documentation, guides |
| `template-skill-history.md` | the `history.md` of a skill |
| `template-go.md` | `.go`, `go.mod` |
| `template-javascript.md` | `.js`, `.mjs`, `.cjs`, `.jsx`, `.ts`, `.tsx` |
| `template-yaml.md` | `.yml`, `.yaml` |
| `template-sql.md` | `.sql` |
| `template-python.md` | `.py` |
| `template-config.md` | `.gitignore`, `CODEOWNERS`, Dockerfile, Makefile, `.toml` |

### Templates from add-ons

An add-on is a skill installed next to scm-skill (see *Add-ons* in `README.md`). It ships templates as files `references/template-<language>.md`, in the same form as the built-in ones:

- a `Covers:` line listing the file types;
- the placement notes;
- the block.

An add-on declares its templates in the `description` of its `SKILL.md`, which Claude Code shows in the list of installed skills. It uses one or both of these phrases:

- `Change-history templates for file types: <list>`: the add-on covers these file types in every project.
- `Change-history templates for project: <owner>/<repo>`: the add-on is project-specific. It applies only to PRs in that repository, and covers the file types on the `Covers:` lines of its template files. Its generic fallback rule, if it has one, is `references/template-fallback.md`, with `Covers: *`.

To use an installed add-on's template, load the add-on with the Skill tool, then read its template file.

**Available add-ons** are listed on the `Add-ons:` line of the project's *Session bootstrap* issue, as `<owner>/<repo>`. scm-skill itself keeps no list of add-ons.

- **Is it a candidate?** Read the add-on's `SKILL.md` on its `main` branch (`gh api repos/<owner>/<repo>/contents/SKILL.md`). It is a candidate when it declares the file type, and is not a project-specific add-on that gives only a fallback rule.
- **Installing it**: `skill-copy.sh use <repo> origin/main` installs it, from the main worktree. That is the conductor's ground, so the engineer stops with `BLOCKED` and names the add-on and the command.
- **After installation**: the engineer reads the template from the new copy. Sessions started later load the add-on as a skill.
