# Phase 0: Spikes & Alignment - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-07
**Phase:** 0-spikes-alignment
**Areas discussed:** CLI language criteria, macOS validation, Spike artifact layout, Audit scope / time-box

---

## CLI Language Criteria

### How the language decision is made

| Option | Description | Selected |
|--------|-------------|----------|
| Hard gate for Lua | Lua wins only if installs without sudo + covers required capabilities on both OSes; any gap → Python/uv | |
| Evidence, then judgment | Spike both minimally, user picks on overall friction; no fixed threshold | ✓ |
| Python/uv default | Bias to known-good kitty-setup path; adopt Lua only if clearly less friction | |

**User's choice:** Evidence, then judgment

### Primary optimization axis (tie-breaker)

| Option | Description | Selected |
|--------|-------------|----------|
| Install friction | End-user first-run experience wins ties | |
| Maintainability | Dev experience over 5 phases wins ties | |
| Distribution simplicity | Fewest cross-platform moving parts wins ties | ✓ |

**User's choice:** Distribution simplicity

### Spike bounding

| Option | Description | Selected |
|--------|-------------|----------|
| Fixed scope script | Fixed proof scope in both languages; done when both run; no open-ended polishing | ✓ |
| Hard time-box | Cap each prototype at set effort; stop on the clock | |
| Scope + time-box both | Fixed scope AND time cap, whichever hits first | |

**User's choice:** Fixed scope script
**Notes:** Proof scope = arg parsing + one real `wezterm cli` call + JSON + file I/O.

---

## macOS Validation

### Real macOS access during Phase 0

| Option | Description | Selected |
|--------|-------------|----------|
| Have a Mac now | Both-platform proof achievable this phase | |
| Linux-only now | No Mac; Linux proof + deferred macOS gate | |
| Mac later / intermittent | Linux spikes now; batch macOS verification into a later pass | ✓ |

**User's choice:** Mac later / intermittent

### Handling the language lock under macOS uncertainty

| Option | Description | Selected |
|--------|-------------|----------|
| Commit, verify later | Lock on Linux evidence + macOS research now; macOS distribution is a verification checkpoint | ✓ |
| Provisional lock | Working assumption marked PROVISIONAL until Mac pass confirms | |
| Hold the lock | Don't finalize language until macOS tested; risks stalling Phase 1 | |

**User's choice:** Commit, verify later

---

## Spike Artifact Layout

### Resolving scripts/experiments/ vs .tmp/ contradiction

| Option | Description | Selected |
|--------|-------------|----------|
| Playbook .tmp/ wins | Playbook authoritative; .tmp/ gitignored, deleted after promotion | ✓ |
| Keep scripts/ committed | Version-control Phase 0 spikes in scripts/experiments/ | |
| Split: scratch vs evidence | Scratch in .tmp/, final proving script committed alongside decision record | |

**User's choice:** `.tmp/` wins — and explicitly requested updating CLAUDE.md.
**Notes:** CLAUDE.md `scripts/experiments/` line edited to point at the `.tmp/` convention
(D-08). Edit applied; not committed (No-auto-commit rule).

---

## Audit Scope / Time-box

### How wide the `wezterm cli` surface audit goes

| Option | Description | Selected |
|--------|-------------|----------|
| Only what v1 needs | Audit just subcommands Phases 1-5 depend on | |
| v1 needs + adjacent | v1 needs plus closely-related subcommands | |
| Full surface sweep | Catalogue entire `wezterm cli` surface as durable reference | ✓ |

**User's choice:** Full surface sweep
**Notes:** Bounded by what `wezterm cli --help` enumerates. Linux columns now; macOS
columns on the batched Mac pass (consistent with the macOS validation decision).

---

## Claude's Discretion

- `<change>` identifier for `.tmp/probes/<change>/` paths in a validation phase with no GSD change.
- Exact structure/columns of the full `wezterm cli` reference catalogue document.

## Deferred Ideas

- Committing the CLAUDE.md fix (awaits explicit go-ahead).
- The batched macOS verification pass (CWD mechanism, audit catalogue, language distribution)
  before Phase 1 closes.
