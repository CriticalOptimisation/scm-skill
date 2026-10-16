# Change History Template: Markdown

Covers: `.md` read by people: README, documentation, guides

Place at the end of the file. An HTML comment, which Markdown renderers hide. A summary must not contain `-->`, which would end the comment early.

```markdown
<!--
Change History

| PR  | Summary              |
|-----|----------------------|
| #N  | one-line description |
-->
```

Markdown that Claude reads or copies is exempt: `CLAUDE.md`, agent definitions, slash commands and GitHub issue and PR templates. Skill files use their skill's `history.md` (see *Exempt files* in `templates.md`).
