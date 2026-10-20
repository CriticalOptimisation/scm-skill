# scm-skill

The software configuration management process used by CalCool Studios' Claude Code sessions, packaged as a Claude Code skill. `SKILL.md` at the root is the entry point; `references/` holds the task-by-task workflow; `tools/worktree.sh` implements the one-worktree-per-branch convention the skill relies on; `tools/thread.sh` and `tools/board.sh` read and write the issue and PR threads and the project board with minimal output (`references/shell-tools.md`). The skill refers to its own files through its own directory, so it works wherever a project links it; `tools/skill-copy.sh` installs it.

## Using it in a project

A project uses its own **fixed copy** of the skill: a detached worktree of the skill's repository at one commit, `.worktrees/skill-<sha12>-<pid>`, which is never edited and never checked out again. `<pid>` stands for the project: the first 8 hex digits of the SHA-1 of its absolute path. A copy is never shared: two projects on the same commit get two copies, because a skill may be set up with files of the project that uses it (see *The skill-copy hook*). Each copy has a `USER_PROJECT` file, a plain file (not a link) holding the absolute path of its project, which `skill-copy.sh` reads to find the project back and check that it is still there. `USER_PROJECT` is excluded in the skill repository's `.git/info/exclude`, unless git already ignores it, so that the copy of any commit stays clean. The project only gets links to it, and only the links move. A checkout, a pull or a branch switch in the skill's repository therefore never changes the skill under a running session, and a session that has loaded a copy keeps it when the links move (it resolves `<skill>` once; see *Paths* in `SKILL.md`).

`tools/skill-copy.sh` makes the copies and the links. Run it from the **main worktree of the project**:

```sh
/path/to/scm-skill/tools/skill-copy.sh use /path/to/scm-skill origin/main
```

**Bootstrap.** A project that has no scm-skill yet runs the tool from a clone of scm-skill, made next to the project:

```sh
git clone https://github.com/CriticalOptimisation/scm-skill.git ../scm-skill
../scm-skill/tools/skill-copy.sh use ../scm-skill origin/main
```

`<skill repo>` may also be a URL: when the repository is missing locally, `use` clones it next to the project, as `../<name of the repository>`, or where `--clone-to <path>` says.

`use <skill repo> <ref> [options]`, run again, updates the installation; with the same ref, it changes nothing. It:

1. fetches `origin` in the skill repository (a failed fetch only warns), and creates the project's copy `<skill repo>/.worktrees/skill-<sha12>-<pid>` of `<ref>`, with its `USER_PROJECT`, if it is missing;
2. sources the skill's hook, if the copy has one (see *The skill-copy hook*);
3. moves the links, all relative: `<skills dir>/<name>` to the copy, where `<name>` is the `name:` field of the copy's `SKILL.md` (`scm-skill` here, whatever the repository is called), and one link per agent, `<agents dir>/<file>`, to each `agents/<file>` of the copy. A link of this skill under an old name, or to an agent the copy no longer has, is removed. The project's own files and agents, and the links of other skills, are never touched;
4. excludes each link in the project's `.git/info/exclude`, unless git already ignores it, so that the project repository never carries a path specific to one machine;
5. logs `<epoch> skill-<sha12>-<pid> <project>` in `<skill repo>/.worktrees/skill-copies.log`;
6. prunes the copies that nothing uses any more.

Agents and skills are loaded when a session starts: after `use`, start a new session. The conductor's own update at session start is the exception (see *Updating* below).

**Updating.** `skill-copy.sh update <copy>`, run from the main worktree of the project, brings the project's copy up to `origin/main` of the skill's repository. `<copy>` is the copy the project uses, the resolved target of its skill link (`readlink -f .claude/skills/scm-skill`); the conductor runs it at the start of every session (see *Conductor and Engineer* in `SKILL.md`). It finds everything from the copy: the skill repository is the copy's own repository, the project is the copy's `USER_PROJECT`, the link directories are those recorded in `<skill repo>/.worktrees/<copy>.links`, and `--frozen` is repeated when the copy was made with it (`use --frozen` writes a marker `<skill repo>/.worktrees/<copy>.frozen`, which `use` without `--frozen` removes). It fetches `origin`, then compares the copy's commit with `origin/main`, and prints one line on stdout:

| Line | Meaning | Exit |
|---|---|---|
| `updated <old sha12> <new sha12> <new copy dir>` | the copy was behind: `use <skill repo> origin/main` ran with the same options and moved the links | `0` |
| `current <sha12>` | the copy is at `origin/main`: nothing changes | `0` |
| `kept <sha12> ahead` or `kept <sha12> diverged` | the copy is not behind `origin/main`: nothing changes | `0` |

When the fetch fails, `update` warns and exits `1` without falling back to local refs: offline, the links never move. A refusal or failure of `use` is passed on with its exit code, after a warning, and the links do not move. `update` refuses with exit `3` when it is not run from the main worktree of the project or when the copy belongs to another project, and exits `1` when `<copy>` is not a copy of the skill. A copy made with `--frozen` before the marker existed is updated as a linked copy: run `use … --frozen` once again to record it. `update` follows `origin/main` of the repository the project already links; the new commit's hook runs with your rights, as with `use` (see *The skill-copy hook*).

| Option | Effect |
|---|---|
| `--skills-dir <dir>` | where the skill link goes, relative to the project root; default `.claude/skills` |
| `--agents-dir <dir>` | where the agent links go, relative to the project root; default `.claude/agents` |
| `--clone-to <path>` | where a missing skill repository is cloned; default next to the project |
| `--frozen` | the hook copies files into the copy instead of linking them (see *The skill-copy hook*) |

Nothing depends on Claude Code: with both directories set elsewhere, `use` works with no `claude` process and no `~/.claude`.

**Pruning.** `use` prunes; `skill-copy.sh prune <skill repo>` prunes on demand. A copy is kept while its project, the one in its `USER_PROJECT`, is still there and still has a link into it (the link itself is checked, not only the log: `use` records the links of each copy in `<skill repo>/.worktrees/<copy>.links`), or while a running session may use it: when it stopped being current later than the start of the oldest `claude` process minus a margin, `SKILL_COPY_MARGIN` seconds (120 by default). With no session, only the linked copies stay; a copy whose project was deleted goes. A copy with changes in it is never removed. `skill-copy.sh status <skill repo>` lists the copies, the project of each and when each stopped being current. `SKILL_COPY_STARTS` (session start times) and `SKILL_COPY_NOW` (the clock) replace the process list and the clock in tests.

**Refusals.** `use` (and `update`, through it) refuses, with exit code `3` and before changing anything, when it is not run from the main worktree of the project; when `/.worktrees/` is not ignored in the skill repository; when `SKILL.md` has no `name:` field at `<ref>`; and when something other than a link to a copy (`.worktrees/skill-*`) is in the way of a link: a file, a directory, a link elsewhere or a dangling link. Exit codes, as for `tools/worktree.sh`: `0` success, `1` failure, `2` usage, `3` refused for safety.

**The skill's own repository** uses itself the same way, which is how scm-skill develops itself with its own process: from its main worktree, `tools/skill-copy.sh use . origin/main`. The copy and the links are then in the same repository; the links point to a copy, never to the working tree, so tools that follow links (`find -L`, `grep -R`, `diff -r`) do not loop.

The project itself needs:

- **`/.worktrees/` in its `.gitignore`**: each branch gets a worktree there, and `tools/worktree.sh new` refuses to create one where git would see it.
- **Optionally, a link list**: untracked paths of the main worktree (data, local analyses) to link into every branch worktree. Put it in `tools/worktree.links`, or in `.worktree-links` at the project root if the project has no `tools/` directory. Write one path per line, each ignored by an anchored `.gitignore` entry with no trailing slash (`/data`, not `data/`). With no list there is nothing to link. Don't create both files: the script would use `tools/worktree.links` and warn on every run.
- **Optionally, in `.vscode/settings.json`**: `"git.detectWorktrees": true`, so that VS Code lists worktrees in *Source Control Repositories*, and `"workbench.editor.closeOnFileDelete": true`, so that the `.git` tab `tools/worktree.sh new` opens closes when the worktree is dropped. The second setting closes the tab of any file deleted outside the editor, unless it has unsaved changes; leave it off if that is unwelcome.

The skill and agent links live in the main worktree only: start sessions there.

### Running the process

The process splits the work of an issue between two roles (see *Conductor and Engineer* in `SKILL.md`):

- **the conductor**: the session you talk to. Start it on Sonnet: `claude --model sonnet`.
- **the engineer**: the `scm-engineer` agent, on Opus, started by the conductor and installed by `use` with the skill. It runs in the background, so it cannot answer permission prompts: allow it the `git` and `gh` commands it needs, and the two scripts it posts with, under any copy of the skill, for example in `.claude/settings.local.json`:

  ```json
  { "permissions": { "allow": ["Bash(git:*)", "Bash(gh:*)", "Bash(bats:*)",
    "Bash(/path/to/scm-skill/.worktrees/skill-*/tools/thread.sh:*)",
    "Bash(/path/to/scm-skill/.worktrees/skill-*/tools/board.sh:*)"] } }
  ```

## The skill-copy hook

A skill may ship `tools/skill-copy-hook.sh` to make a copy work in the project that uses it, for example by giving the copy access to unversioned or configuration files prepared in the project. The hook is versioned with the skill: the one that runs is the copy's own.

- On every `use`, once the copy exists and before the links move, `skill-copy.sh` **sources** the hook in a subshell, from the project root, with two arguments: `$1`, the copy's directory, and `$2`, the project's directory, both absolute. Nothing the hook sets, defines or changes, including the working directory, reaches `skill-copy.sh`.
- `skill_copy_link <source> <dest>` is defined for the hook: it makes `<dest>` a relative link to `<source>`. With `--frozen`, it copies `<source>` to `<dest>` instead. `SKILL_COPY_FROZEN` is `1` with `--frozen`, and empty otherwise. Links go from the copy to the project, so there is no unlink hook. Frozen copies suit files that are developed actively rather than plain data, such as a git submodule in a private repository.
- If the hook fails (a non-zero status), `use` exits `1`: the links do not move and nothing is logged.
- The hook runs on every `use`, so it must be idempotent. What it places in the copy must be ignored by the skill's `.gitignore`: otherwise the copy has changes in it, and pruning keeps it.
- The copy belongs to one project, so what the hook places in it comes from that project only. Code of the skill that runs later finds the project in the copy's `USER_PROJECT`.

**Trust.** The hook is code from the ref you fetched, and it runs with your rights. Run `use` only on refs of a repository you trust, as you would before running any of its scripts.

## Add-ons

An add-on is a skill that works on top of scm-skill, such as [skill-repo-development](https://github.com/CriticalOptimisation/skill-repo-development), which keeps the guidance on developing skills. `skill-copy.sh` installs an add-on like any other skill; nothing in scm-skill knows about add-ons. An add-on declares that it depends on scm-skill:

- its `SKILL.md` has a strict instruction to refuse to run without scm-skill;
- it may ship its own `tools/skill-copy.sh`, which delegates to scm-skill's and, when scm-skill cannot be found, fails with the installation instructions above.

An add-on may ship **change-history templates**, for file types that scm-skill does not cover, or to replace its built-in ones. The rules are in `references/templates.md`, *Change History Section Templates*.
- **Template files**: each is a file `references/template-<language>.md`, with a `Covers:` line that lists its file types.
- **Declaration**: the add-on declares its templates in the `description` of its `SKILL.md`, with `Change-history templates for file types: <list>` or `Change-history templates for project: <owner>/<repo>`.
- **Precedence**: an installed add-on takes precedence over the built-in templates. A project-specific add-on takes precedence over the other add-ons.
- **Available add-ons**: an add-on listed by Claude Code but not installed in the project is used only when no built-in template covers the file type. The conductor finds it from the frontmatter in its list of skills, and installs it with `skill-copy.sh use`.

## Requirements

Linux, bash, git, `flock` (util-linux), GNU coreutils (`mv -T`), procps (`pgrep`, `ps`), and, for `tools/thread.sh` and `tools/board.sh`, `gh` (with the `project` scope) and `jq`. The tests need bats ≥ 1.5 (see *Tests*).

## Tests

Run the whole suite from the root of a checkout: `bats tools/`. The suites need git, jq and the requirements above, but no token and no network: `tools/thread.sh` and `tools/board.sh` are tested against the `gh` stub in `tools/fixtures/`. [`shellcheck`](https://www.shellcheck.net/) is optional on a workstation: `tools/shellcheck.bats` checks that `tools/*.sh`, `tools/*.bats` and `tools/fixtures/gh` are shellcheck-clean, and that every `# shellcheck disable=` directive gives its reason after a `#`. It is skipped without shellcheck. In CI it is required (see *Continuous integration*).

### Continuous integration

The workflow `CI` (`.github/workflows/ci.yml`) runs on every pull request, on every push to `main`, and by hand (`gh workflow run CI`). Its single job, and so its check, is named **`bats`**. It runs on `ubuntu-24.04`, with bats, ShellCheck and jq from that release's packages (bats 1.10.0, ShellCheck 0.9.0). It installs the three and prints their versions, then runs `bats tools/`. It fails if a test fails, and also if any test is skipped, so `tools/shellcheck.bats` always runs in CI. Its permissions are `contents: read`, and its actions are pinned to a commit SHA. Moving to a newer runner is its own issue.

To make the check required on `main`: *Settings → Rules → Rulesets → Protect main → Require status checks to pass → Add checks → `bats`* (source: GitHub Actions). The check must have run once before it can be picked. Until it is required, auto-merge does not wait for it.

## Changing the process

Open an issue here. Changes follow the process they describe.

## Origin

Extracted on 7 October 2026 from the project repository where it was developed (`.claude/skills/software-configuration-management` and `tools/worktree.*` at commit `ae62f34`). `history.md` keeps the change log from that time; its issue and PR numbers refer to that repository.

`tools/skill-copy.sh` is ported from [skill-repo-development](https://github.com/CriticalOptimisation/skill-repo-development) `tools/skill-copy.sh` at commit `74caa22`, and extended to projects other than the skill's own repository (#23).
