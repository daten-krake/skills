# skills

Central collection of agent skills for [OpenCode](https://opencode.ai) and
[Claude Code](https://code.claude.com). One skill per directory under
`skills/` (`skills/<skill-id>/SKILL.md`); see [AGENTS.md](AGENTS.md) for the
format contract.

## Installing skills

`./install.sh` copies a selection of skills into your Claude Code and OpenCode
skill directories (symlink with `--link`).

```sh
./install.sh                     # interactive picker, project-local
./install.sh worker --global     # copy 'worker' into ~/.claude/skills and
                                 # ~/.config/opencode/skills
./install.sh --all --opencode --link
./install.sh --remove worker     # uninstall
```

Options:

| Flag | Meaning |
|------|---------|
| `--all` | install every skill in the repo |
| `--remove [id ...]` | uninstall instead of install (picker if no IDs) |
| `--claude` / `--opencode` | target only that tool (default: both) |
| `--global` | install into `~/.claude/skills` + `~/.config/opencode/skills` |
| `--project <dir>` | project-local target dir (default: current working dir; installs into `.claude/skills` + `.opencode/skills`) |
| `--link` | install as symlinks instead of copies (default: copy) |
| `--force` | replace conflicting or diverged existing entries |

Behavior notes:

- Re-running is safe: identical installs are skipped, and a locally modified
  copy is never overwritten — `--force` is the explicit "update from repo".
- Skills without a non-empty `description` are skipped with a warning.
- `--remove` only touches entries created from this repo: symlinks are
  removed if they point into it, copies only if unchanged (else `--force`).
- Skills load at startup — restart OpenCode / Claude Code after changes.
