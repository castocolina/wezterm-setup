# wezterm-setup — Agent Rules

## Authoritative sources

- v1 scope: [.planning/REQUIREMENTS.md](.planning/REQUIREMENTS.md)
- Roadmap: [.planning/ROADMAP.md](.planning/ROADMAP.md)
- Project state: [.planning/STATE.md](.planning/STATE.md)
- Hypothesis playbook: [docs/agent-iteration.md](docs/agent-iteration.md)

## Critical rules

- **Commit discipline** — prefer fewer, cohesive commits; amend the current commit to fold in closely related follow-ups, and when review feedback requires a fix, amend rather than stacking a new commit if it belongs to the same change
- **Hypothesis before implementation** — every behavior starts as a hypothesis in `.tmp/h<NN>-<slug>/` (or a probe in `.tmp/probes/<change>/`), gitignored and deleted after manual promotion — see [docs/agent-iteration.md](docs/agent-iteration.md)
- **Verify before declaring done** — `wez doctor` output or recorded manual repro; no "should work"
- **Questions are not orders** — answer questions; do not auto-change code

## Guidelines

- [Universal agent rules](.claude/agent-rules.md)

---

<!-- GSD:project-start source:PROJECT.md -->

## Project

**wezterm-setup**

A WezTerm config distribution and companion CLI (`wez`) that ships daily-friction fixes, rich visual
identity at the pane and tab level, and a named workspace launcher — all installed non-destructively
via a single injected `require` line. Targets a solo developer on Linux and macOS daily-driving
WezTerm as a full multiplexer.

**Core Value:** A working WezTerm install that is easy to understand, audit, and extend — where every shipped
behavior is verified against a real running session before it integrates.

### Constraints

- **Runtime (config layer)**: Pure Lua inside WezTerm — zero external dependencies
- **Runtime (companion CLI)**: TBD via spike — Lua 5.4 standalone preferred; Python/uv as fallback
  (proven in kitty-setup); Bash explicitly excluded for cross-platform reasons

- **Platform**: Linux (Wayland + X11) + macOS parity for every shipped feature
- **Install**: Must work without `sudo` on both platforms
- **Philosophy**: No vi-modal bindings, no `less`-style search overlays anywhere in the shipped UX
- **Hypothesis-driven**: Every capability in Phase 2+ starts as a hypothesis in
  `.tmp/h<NN>-<slug>/` with a manual repro before integration (see `docs/agent-iteration.md`)
<!-- GSD:project-end -->

<!-- GSD:stack-start source:STACK.md -->

## Technology Stack

Technology stack not yet documented. Will populate after codebase mapping or first phase.
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->

## Conventions

Conventions not yet established. Will populate as patterns emerge during development.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->

## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->

## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, `.github/skills/`, or `.codex/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->

## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:

- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->

<!-- GSD:profile-start -->

## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
