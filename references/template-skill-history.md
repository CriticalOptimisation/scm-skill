# Change History Template: Skill `history.md`

Covers: `history.md` of a skill

A skill's files carry no change history block. Their history is a standalone `history.md` in the skill directory, **never referenced from skill content**.

## SCM skill (tracks product→process causality)

Records which product or process PRs drove each change to the skill files.

```markdown
# Change History

| PR  | Closes | Skill files changed | Process change |
|-----|--------|---------------------|----------------|
| #N  | #M     | filename.md         | one-line description |
```

## All other skills

```markdown
# Change History

| PR  | Closes | Summary |
|-----|--------|---------|
| #N  | #M     | one-line description |
```
