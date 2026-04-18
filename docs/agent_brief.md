# All Space — Agent Brief
*Read this first. Every session. Every agent.*

---

## What This Project Is

A top-down 3D space combat game built in Godot 4.6 / GDScript (C# for ProjectileManager
only). Ships, projectiles, and debris are full 3D physics objects constrained to the XZ
plane (Y = 0). The camera is top-down perspective. There is no 2D physics layer anywhere.

Full design intent: `docs/core_spec.md`

---

## Tech Stack

| Concern | Choice |
|---|---|
| Engine | Godot 4.6 |
| Primary language | GDScript |
| Performance-critical | C# — ProjectileManager only |
| Physics | Jolt (Godot 4.6 default) — `RigidBody3D` |
| Play plane | XZ (Y = 0) — all ships, projectiles, gameplay |
| Camera | `Camera3D`, perspective, top-down |
| Data / tuning | JSON under `/data/` and `/content/` |
| Cross-system comms | `GameEventBus.gd` signals only |
| Service registry | `ServiceLocator` (C# autoload) |

---

## Non-Negotiable Architecture Rules

These apply to every agent, every session. Violating them corrupts the project.

1. **No 2D nodes.** `CharacterBody2D`, `RigidBody2D`, `Area2D`, `CollisionShape2D`,
   `Camera2D`, `Node2D` are banned. If you are about to use one, stop.

2. **No `Vector2` for world-space.** `Vector2` is banned for any position or velocity
   value. `Vector2i` is permitted only for chunk grid coordinates (integer indices).

3. **Y = 0 always.** Every entity position has `y = 0`. Every velocity has `y = 0`.
   Enforce explicitly after every physics update. This is non-optional.

4. **No hardcoded values.** Anything tunable belongs in JSON. No magic numbers in code.

5. **No direct cross-system calls.** Systems communicate only through `GameEventBus`
   signals. A system may not call methods on another system or use `get_node()` to
   reach across system boundaries.

6. **Ship.gd never writes velocity or position to produce motion.** Forces and torques
   go to Jolt via `apply_central_force()` / `apply_torque()`. Jolt integrates. The
   only direct write allowed is zeroing `position.y` as a backstop.

7. **One Ship.tscn.** No FighterShip.tscn or DestroyerShip.tscn. All ship types use
   the same scene, configured at spawn time from JSON.

8. **PerformanceMonitor instrumentation is required.** Every system that does
   significant work must wrap it with `begin()` / `end()` pairs. See
   `docs/feature_spec-performance_monitor.md` for canonical metric names.

9. **Specs are authoritative.** If a spec says to do something a particular way, do it
   that way. If you cannot, follow the deviation protocol below — do not silently resolve.

10. **C# only for ProjectileManager and ServiceLocator.** Everything else is GDScript.

---

## Build Status

From `docs/core_spec.md` §19. Update this table at the end of every session.

| Step | System | Status |
|---|---|---|
| 1 | PerformanceMonitor | Implemented |
| 2 | ServiceLocator + GameEventBus + GameBootstrap | Implemented |
| 3 | ContentRegistry | Implemented |
| 4 | SpaceBody + Ship (physics only, no weapons) | Not started |
| 5 | NavigationController | Not started |
| 6 | ProjectileManager (C#, dumb pool) | Not started |
| 7 | WeaponComponent + HardpointComponent | Not started |
| 8 | GuidedProjectilePool | Not started |
| 9 | ShipFactory + Ship visual assembly | Not started |
| 10 | GameCamera — Pilot mode | Not started |
| 11 | AIController + NavigationController integration | Not started |
| 12 | Test scene: player vs AI, full Pilot mode loop | Not started |
| 13 | Tactical mode camera + input layer | Not started |
| 14 | ChunkStreamer + Asteroid + Debris | Not started |

**Status values:** `Not started` / `In progress` / `Implemented` / `Tested ✓`

---

## Deviation Protocol

If you encounter a situation where following a spec as written is not possible — a
Godot API limitation, a logical conflict, a missing dependency, a discovered error —
**stop before writing any code that deviates from the spec.**

Write a deviation report in this format and wait for confirmation:

```
[DEVIATION REQUIRED]
Spec:     <filename> §<section>
Problem:  <what the spec says and exactly why it cannot be followed>
Options:
  A. <description> — <tradeoffs>
  B. <description> — <tradeoffs>
Recommendation: A because <reason>
```

Do not implement until the user confirms an option. Once confirmed:
1. Implement the confirmed approach
2. Update the spec to reflect the decision
3. Append an entry to `docs/decisions_log.md`
4. Update the build status table above

---

## Agent Tiers

Not all tasks require the same agent. Match the task to the tool.

| Task type | Examples | Use |
|---|---|---|
| Architecture / spec changes | Redesigning a system, resolving conflicts | Claude Opus (Claude Code) |
| System implementation | Building Ship.gd, ProjectileManager.cs | Claude Sonnet (Cursor or Claude Code) |
| Mechanical / repetitive | Generating weapon JSON files, content stubs | Lighter agent / scripting |
| Doc updates | Updating build status, logging decisions | Any agent |

If a task you've been given feels architectural — it changes how systems relate, introduces
a new pattern, or requires updating a spec — flag it rather than deciding yourself.

---

## Key Files

| File | Purpose |
|---|---|
| `docs/core_spec.md` | Philosophy, architecture, cross-cutting rules |
| `docs/agent_brief.md` | This file — agent context, build status, deviation protocol |
| `docs/decisions_log.md` | Full history of decisions and spec deviations |
| `docs/feature_spec-*.md` | Per-system specifications |
| `data/` | Global config JSON (damage types, AI profiles, world config, factions) |
| `content/` | Per-item content folders (ships, weapons, modules) |
| `core/` | Bootstrap, GameEventBus, ServiceLocator |
| `gameplay/` | All game systems |

---

## Recent Decisions

The last three decisions are summarised here for quick context. Full history in
`docs/decisions_log.md`.

<!-- RECENT-DECISIONS-START -->
1. **2026-04-16 — Spec audit and 3D cleanup** — All feature specs reviewed and corrected
   before implementation begins. See decisions_log.md for full list of fixes.
<!-- RECENT-DECISIONS-END -->
