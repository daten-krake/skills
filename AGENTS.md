# AGENTS.md

This repo is a central collection of agent skills for OpenCode and Claude Code.
There is no code, build, or CI — the content is skill directories, and the
format rules below are the contract.

## Instruction files

- `AGENTS.md` (this file) is the only instruction file in this repo. Do not
  create a `CLAUDE.md`: Claude Code (v2.1.277+) reads `AGENTS.md` directly
  when no `CLAUDE.md` exists in the tree, and this repo intentionally does
  not support older Claude Code versions.

## Layout

- `skills/` is the single home for all skills. One skill = one directory:
  `skills/<skill-id>/SKILL.md`, with optional supporting `scripts/`,
  `references/`, `templates/` beside it.
- Do not create skill directories anywhere else in the repo, and do not nest
  skills inside skills.
- Paths written inside a SKILL.md are relative to the directory containing
  that SKILL.md. Reference supporting files with plain relative paths.
- README.md and AGENTS.md are repo documentation, not skills.
  Consumers point at `skills/`, never the repo root: OpenCode registers any
  `*.md` at a source root as a flat skill — without a `description` it is
  never advertised, but it is noise.

## Installing a skill

Install per skill: copy or symlink `skills/<skill-id>` into the consumer's
skill location.

- OpenCode: `~/.config/opencode/skills/` (global) or a project's
  `.opencode/skills/`. Alternatively, point the `skills` array in
  `opencode.json` at `<path-to-repo>/skills`.
- Claude Code: `~/.claude/skills/` (global) or a project's
  `.claude/skills/`. Symlinked skill folders are supported.

Cloning the whole repo into `~/.claude/skills` does not work — Claude Code
only loads skill directories one level deep. Cloning into
`~/.config/opencode/skills` does work (OpenCode finds `SKILL.md` at any
depth), but the root `*.md` docs register as unadvertised flat skills, so
prefer per-skill installs.

## Skill IDs

- The skill ID comes from the path (the directory name), is case-sensitive,
  and is not the frontmatter `name` (display label in OpenCode, command-name
  override in Claude Code).
- Use unique lowercase kebab-case directory names (1–64 chars) and keep the
  frontmatter `name` aligned with the directory name.
- Never create a root-level `SKILL.md`: OpenCode assigns it the literal ID
  `SKILL`.
- Avoid Claude Code's reserved names: `synced` and `anthropic-skills`.

## Frontmatter

- `description` is required for model-driven discovery — OpenCode does not
  advertise skills without one. State what the skill does and when to use it;
  Claude Code truncates the listing at 1,536 chars (description +
  `when_to_use`).
- For skills that must work in both tools, keep frontmatter to the shared
  Agent Skills set: `name`, `description`, `license`, `compatibility`,
  `metadata`, `allowed-tools`.
- Everything else is a tool extension: OpenCode has `slash` and
  `metadata.opencode/autoinvoke`; Claude Code has `argument-hint`,
  `arguments`, `disable-model-invocation`, `user-invocable`, `disallowed-tools`,
  `model`, `context`, `paths`, and more. Claude Code silently ignores fields
  it does not recognize.
- Claude-Code-only body features do not function in OpenCode, which loads the
  body as plain markdown: `` !`command` `` dynamic context injection,
  `${CLAUDE_SKILL_DIR}`, `${CLAUDE_PROJECT_DIR}`, and `$ARGUMENTS`/`$N`
  substitution. If a skill depends on tool-specific fields or body features,
  it is tool-specific — say so in its `description` (e.g. "Claude Code only").

## Verifying a skill

There is no test suite. Sanity-check by loading it:

- OpenCode: in a scratch project, add `skills/` to `opencode.json`
  (`"skills": ["<path-to-repo>/skills"]`) and load it with the `skill` tool
  using the directory-name ID.
- Claude Code: copy or symlink the skill directory into a scratch project's
  `.claude/skills/` and invoke `/skill-id`.

## Sources of truth

Check the canonical docs before guessing at format details:

- OpenCode skills: https://opencode.ai/v2/docs/skills
- Claude Code skills: https://code.claude.com/docs/en/skills
- Shared Agent Skills spec: https://agentskills.io
