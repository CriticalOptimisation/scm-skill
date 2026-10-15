# scm-skill

The software configuration management process used by CalCool Studios' Claude Code sessions, packaged as a Claude Code skill. `SKILL.md` at the root is the entry point; `references/` holds the task-by-task workflow; `tools/worktree.sh` implements the one-worktree-per-branch convention the skill relies on. The skill refers to its own files through its own directory, so it works wherever a project links it.

## Using it in a project

The skill is linked, not copied, so every project follows the same, current process. From the project root:

```sh
mkdir -p .claude/skills
ln -s /path/to/scm-skill .claude/skills/scm-skill
echo "/.claude/skills/scm-skill" >> .git/info/exclude
```

The link stays local (`.git/info/exclude`), so the project repository never carries a path specific to one machine. The skill's name comes from the `name:` field of `SKILL.md`, not from the link: a link made under another name, such as `software-configuration-management`, keeps working, and the skill is listed as `scm-skill`.

Then link the agent the process delegates to, from the project:

```sh
/path/to/scm-skill/tools/agents.sh link          # into the project's .claude/agents/
/path/to/scm-skill/tools/agents.sh link --user   # or into ~/.claude/agents/
```

`agents.sh link` symlinks every definition of the skill's `agents/` directory. In project mode it targets the main worktree's `.claude/agents/`, even when run from a branch worktree, and excludes each link from git (`.git/info/exclude`). A second run changes nothing. It never overwrites a file or a link to another file: it refuses with exit code `3`, before writing anything. Exit codes: `0` success, `1` failure, `2` usage, `3` refused for safety.

The project itself needs:

- **`/.worktrees/` in its `.gitignore`**: each branch gets a worktree there, and `tools/worktree.sh new` refuses to create one where git would see it.
- **Optionally, a link list**: untracked paths of the main worktree (data, local analyses) to link into every branch worktree. Put it in `tools/worktree.links`, or in `.worktree-links` at the project root if the project has no `tools/` directory. Write one path per line, each ignored by an anchored `.gitignore` entry with no trailing slash (`/data`, not `data/`). With no list there is nothing to link. Don't create both files: the script would use `tools/worktree.links` and warn on every run.
- **Optionally, in `.vscode/settings.json`**: `"git.detectWorktrees": true`, so that VS Code lists worktrees in *Source Control Repositories*, and `"workbench.editor.closeOnFileDelete": true`, so that the `.git` tab `tools/worktree.sh new` opens closes when the worktree is dropped. The second setting closes the tab of any file deleted outside the editor, unless it has unsaved changes; leave it off if that is unwelcome.

### Running the process

The process splits the work of an issue between two roles (see *Conductor and Engineer* in `SKILL.md`):

- **the conductor**: the session you talk to. Start it on Sonnet: `claude --model sonnet`.
- **the engineer**: the `scm-engineer` agent, on Opus, started by the conductor. It runs in the background, so it cannot answer permission prompts: allow it the `git` and `gh` commands it needs, for example in `.claude/settings.local.json`:

  ```json
  { "permissions": { "allow": ["Bash(git:*)", "Bash(gh:*)", "Bash(bats:*)"] } }
  ```

Agents and skills are loaded when a session starts: after `agents.sh link`, start a new session.

## Developing the skill

In this repository, sessions load **fixed copies** of the skill, never a working tree. A checkout, a commit or a branch switch would otherwise change the skill under every running session, and a branch could not be tested in a new session. So:

- Never link this repository to its own main worktree. Tools that follow links (`find -L`, `grep -R`, `diff -r`) would loop.
- `.claude/skills/scm-skill` points to a detached worktree at one commit, `.worktrees/skill-<sha>`. Only the link moves. Since sessions resolve `<skill>` once when the skill loads (see *Paths* in `SKILL.md`), moving the link does not change the skill under a running session.

The procedure (setup, testing a branch, after a merge, checking what is loaded) and its command, `skill-copy.sh`, are a separate skill: [skill-repo-development](https://github.com/CriticalOptimisation/skill-repo-development). Clone it next to this repository and link it from here:

```sh
ln -s ../../../skill-repo-development .claude/skills/skill-repo-development
echo "/.claude/skills/skill-repo-development" >> .git/info/exclude
```

Projects that only *use* the skill link it as described in *Using it in a project*.

## Changing the process

Open an issue here. Changes follow the process they describe.

## Origin

Extracted on 7 October 2026 from the project repository where it was developed (`.claude/skills/software-configuration-management` and `tools/worktree.*` at commit `ae62f34`). `history.md` keeps the change log from that time; its issue and PR numbers refer to that repository.
