# scm-skill

The software configuration management process used by CalCool Studios' Claude Code sessions, packaged as a Claude Code skill. `SKILL.md` at the root is the entry point; `references/` holds the task-by-task workflow; `tools/worktree.sh` implements the one-worktree-per-branch convention the skill relies on. The skill refers to its own files through its own directory, so it works wherever a project links it.

## Using it in a project

The skill is linked, not copied, so every project follows the same, current process. From the project root:

```sh
mkdir -p .claude/skills
ln -s /path/to/scm-skill .claude/skills/software-configuration-management
echo ".claude/skills/software-configuration-management" >> .git/info/exclude
```

The link stays local (`.git/info/exclude`), so the project repository never carries a path specific to one machine.

The project itself needs:

- **`/.worktrees/` in its `.gitignore`**: each branch gets a worktree there, and `tools/worktree.sh new` refuses to create one where git would see it.
- **Optionally, a link list**: untracked paths of the main worktree (data, local analyses) to link into every branch worktree. Put it in `tools/worktree.links`, or in `.worktree-links` at the project root if the project has no `tools/` directory. Write one path per line, each ignored by an anchored `.gitignore` entry with no trailing slash (`/data`, not `data/`). With no list there is nothing to link. Don't create both files: the script would use `tools/worktree.links` and warn on every run.
- **Optionally, in `.vscode/settings.json`**: `"git.detectWorktrees": true`, so that VS Code lists worktrees in *Source Control Repositories*, and `"workbench.editor.closeOnFileDelete": true`, so that the `.git` tab `tools/worktree.sh new` opens closes when the worktree is dropped. The second setting closes the tab of any file deleted outside the editor, unless it has unsaved changes; leave it off if that is unwelcome.

## Changing the process

Open an issue here. Changes follow the process they describe.

## Origin

Extracted on 7 October 2026 from the project repository where it was developed (`.claude/skills/software-configuration-management` and `tools/worktree.*` at commit `ae62f34`). `history.md` keeps the change log from that time; its issue and PR numbers refer to that repository.
