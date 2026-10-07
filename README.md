# scm-skill

The software configuration management process used by CalCool Studios' Claude Code sessions, packaged as a Claude Code skill. `SKILL.md` at the root is the entry point; `references/` holds the task-by-task workflow; `tools/worktree.sh` implements the one-worktree-per-branch convention the skill relies on.

## Using it in a project

The skill is linked, not copied, so every project follows the same, current process. From the project root:

```sh
mkdir -p .claude/skills
ln -s /path/to/scm-skill .claude/skills/software-configuration-management
echo ".claude/skills/software-configuration-management" >> .git/info/exclude
```

The link stays local (`.git/info/exclude`), so the project repository never carries a path specific to one machine.

## Changing the process

Open an issue here. Changes follow the process they describe.

## Origin

Extracted on 7 October 2026 from the project repository where it was developed (`.claude/skills/software-configuration-management` and `tools/worktree.*` at commit `ae62f34`). `history.md` keeps the change log from that time; its issue and PR numbers refer to that repository.
