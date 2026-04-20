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
| 4 | SpaceBody + Ship (physics only, no weapons) | Implemented |
| 5 | NavigationController | Implemented |
| 6 | ProjectileManager (C#, dumb pool) | Implemented |
| 7 | WeaponComponent + HardpointComponent | Implemented |
| 8 | GuidedProjectilePool | Implemented |
| 9 | ShipFactory + Ship visual assembly | Implemented |
| 10 | GameCamera — Pilot mode | Implemented |
| 11 | AIController + NavigationController integration | Implemented |
| 12 | Test scene: player vs AI, full Pilot mode loop | Implemented |
| 13 | Tactical mode camera + input layer | Implemented |
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

The most recent decisions are summarised here for quick context. Full history in
`docs/decisions_log.md`.

<!-- RECENT-DECISIONS-START -->
1. **2026-04-19 — Phase 13: Tactical mode camera + input layer** — InputManager.gd
   (Tab toggle, pilot input routing), SelectionState.gd (click/drag/shift selection),
   TacticalInputHandler.gd (right-click dispatch, stop key), GameCamera tactical mode
   (free-pan WASD + edge-scroll, zoom-out on enter, re-follow on exit). GameEventBus
   updated with queue_mode on order signals, new signals for escort/stance/formation/
   damage. PilotLoopTest refactored to use InputManager. Spec file location deviation:
   `gameplay/fleet_command/` instead of `systems/fleet_command/` to match existing layout.
2. **2026-04-19 — Step 12: Pilot loop test scene** — `test/PilotLoopTest.tscn` / `PilotLoopTest.gd`:
   ShipFactory spawns player + AI, GameCamera + `move_*` thrust + LMB/RMB fire; exports for
   spawns and content IDs. `run/main_scene` set to PilotLoopTest. Default AI variant
   `axum_fighter_patrol` (same class as player) so JSON variants resolve.
3. **2026-04-19 — Phase 11: AIController + NavigationController integration** —
   `AIController.gd`, `data/ai_profiles.json`, ShipFactory `_attach_ai_components`,
   ContentRegistry `get_ai_profile`, NavigationController ship via `get_parent()` (factory
   spawn). `Engine.RegisterSingleton("ServiceLocator", …)` for GDScript `get_singleton`.
4. **2026-04-19 — Phase 10: GameCamera — Pilot mode** — Implemented
   GameCamera.gd (extends Camera3D), GameCamera.tscn, CameraTest.tscn/.gd, and
   .cursor/rules/camera.mdc. Critically damped spring follow, cursor-offset lead,
   height-based zoom, ray-plane mouse-to-world, and PlayerState signal retargeting.
   No deviations from spec.
5. **2026-04-18 — Phase 9: ShipFactory + Ship visual assembly** — Implemented
   ServiceLocator.cs, ContentRegistry.gd, PlayerState.gd, ShipFactory.gd, and
   ship_colorize.gdshader. Full spawn_ship() pipeline with stat resolution, part
   assembly from GLB, hardpoint discovery/configuration, faction-based naming, and
   vertex color material application. All content is JSON-driven.
<!-- RECENT-DECISIONS-END -->
