# All Space — Agent Instructions

Top-down 3D space combat game. Godot 4.6 / GDScript. Physics on XZ plane (Y = 0). No 2D layer anywhere.

**Read `docs/agent_brief.md` before any session work.** It contains build status and all protocols.

## Hard Constraints

- No 2D nodes (`Node2D`, `CharacterBody2D`, `RigidBody2D`, `Area2D`, `Camera2D`, etc.) — banned entirely
- No `Vector2` for world-space — banned. `Vector2i` OK only for chunk grid (integer indices)
- Y = 0 always — every entity position and velocity. Enforce explicitly after every physics update
- No hardcoded values — all tunables in JSON under `/data/` or `/content/`
- Cross-system comms via `GameEventBus` signals only — no direct cross-system calls or `get_node()` across boundaries
- `Ship.gd` never writes velocity/position for motion — forces to Jolt only; only exception: zero `position.y` backstop
- C# only for `ProjectileManager` and `ServiceLocator` — everything else is GDScript
- `PerformanceMonitor` `begin()`/`end()` required on every system that does significant work

## Authoritative Sources

| What | Where |
|---|---|
| Build status + protocols | `docs/agent_brief.md` |
| Architecture + philosophy | `docs/spec/core_spec.md` |
| Systems lookup | `docs/SYSTEMS.md` |
| Per-system specs | `docs/spec/feature_spec-*.md` |
| Decision history | `docs/decisions_log.md` |

## Mandatory Protocols

**Graphify-first:** Before any codebase exploration, read `graphify-out/GRAPH_REPORT.md`. Only fall back to glob/grep/read if graph is missing or stale. Full protocol in `docs/agent_brief.md`.

**Living spec:** Any decision that affects system behavior, data format, signals, or algorithms must update the relevant spec in the same session. Code change + spec update = one atomic unit.

**Session end:** See checklist in `docs/agent_brief.md`. Always run before ending a session.
