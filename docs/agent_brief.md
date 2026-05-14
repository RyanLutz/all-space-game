# All Space — Agent Brief
*Read this first. Every session. Every agent.*

---

## What This Project Is

A top-down 3D space combat game built in Godot 4.6 / GDScript (C# for ProjectileManager
and ServiceLocator only). Ships, projectiles, and debris are full 3D physics objects
constrained to the XZ plane (Y = 0). The camera is top-down perspective. There is no
2D physics layer anywhere.

Full design intent: `docs/spec/core_spec.md`

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

## Build Status

From `docs/spec/core_spec.md` §19. Update this table at the end of every session.

| Step | System | Status |
|---|---|---|
| 1 | PerformanceMonitor | Implemented |
| 2 | ServiceLocator + GameEventBus + GameBootstrap | Implemented |
| 3 | ContentRegistry | Implemented |
| 4 | SpaceBody + Ship (physics only, no weapons) | Implemented |
| 5 | ~~NavigationController~~ | Dissolved — folded into AIController (see step 11) |
| 6 | ProjectileManager (C#, dumb pool) | Implemented |
| 7 | WeaponComponent + HardpointComponent | Implemented |
| 8 | GuidedProjectilePool | Implemented |
| 9 | ShipFactory + ship assembly (GLB parts + `-colonly` → RigidBody3D collision) | Implemented |
| 10 | GameCamera — Pilot mode | Implemented |
| 11 | AIController (flight + state machine, post-refactor) | Implemented |
| 12 | Test scene: player vs AI, full Pilot mode loop | Implemented |
| 13 | Tactical mode camera + input layer | Implemented |
| 14 | Fleet Command — selection, orders, stance, escort queue | Implemented |
| 15 | ChunkStreamer + Asteroid + Debris | Implemented |
| 16 | GameEventBus signal audit | Implemented |
| 17 | Combat VFX System (Session 1: VFX core + pools; Session 2: local players) | In progress |
| 18 | UI Foundation (UITokens, UITheme, StatBar, SegBar, HeatBar, WeaponSlot, RosterRow, ModeSwitch) | Implemented |
| 19 | Pilot HUD (PilotHUD, Radar — five panels, hit flash, event subscriptions) | Implemented |
| 20 | Star System — Phase 1 (StarRecord, StarRegistry skeleton, catalog generation, LOD 0 MultiMesh point shader, `world_config.galaxy` block) | Implemented |
| 21 | Star System — Phase 2 (LOD 1 fullscreen-quad screen-pass glow shader, `_update_shader_uniforms`, closest-N cap, camera-attach lifecycle) | Implemented |
| 22 | Star System — Phase 3 (LOD 2 `StarMesh.tscn`, `star_surface.gdshader`, `star_corona.gdshader`, `_spawn_mesh` lifecycle, `StarRecord.light_range`, backdrop-clamp fix, `galaxy.star_mesh` tunables) | Implemented |
| 23 | Star System — Phase 4 (`star_exclusion_entered` signal in GameEventBus, `StarMesh` ExclusionArea live, collision_mask=1, body_entered handler filters to Ship, emits signal) | Implemented |
| 24 | Star System — Phase 5 (per-star `blend_alpha` + `lod_prev_state` on `StarRecord`; `mix()` crossfade in all four shaders; delayed LOD 2 despawn; frustum-cull stub; `distance_squared_to()` perf optimisation; all four `StarRegistry.*` metrics) | Implemented |

> **Steps 20–24 reference code has been deleted.** `core/stars/` directory removed in spec correction pass. The superseded `feature_spec-star_system.md` remains in `docs/spec/` for historical reference only.

| 25 | StarField S1–S4 complete: galaxy catalog, galactic map UI, galaxy sky shader, nebula map zoom wiring. All four PerformanceMonitor metrics in overlay. | Implemented |
| 26 | SolarSystem A–D complete. | Implemented |
| 27 | Main Scene Integration — `Main.tscn`, `GameOrchestrator.gd`, warp transitions, hand-authored `sol_start` system. | Implemented |
| 28 | Performance: removed superseded `StarRegistry` autoload, fixed `star_point.gdshader` `INSTANCE_CUSTOM` → `INSTANCE_CUSTOM_DATA`. | Implemented |
| — | Galaxy Map (3D, camera-attached) | Implemented |

**Status values:** `Not started` / `In progress` / `Implemented` / `Tested ✓`

---

## Graphify-First Protocol

**Mandatory before any codebase exploration — no exceptions.**

1. Check if `graphify-out/` exists.
2. If yes, read `graphify-out/GRAPH_REPORT.md` first — god nodes and community structure tell you where things live.
3. If `graphify-out/wiki/index.md` exists, use it to navigate rather than reading raw files.
4. Only fall back to glob/grep/read if the graph is missing, stale, or doesn't answer the question.

**After modifying code files, run `graphify update .` before ending the session.**
This is AST-only — no API cost. It keeps the graph current for the next agent.

---

## Living Spec Protocol

**Any decision that affects a system's behavior, data format, signals, or algorithms requires a spec update in the same session.**

The spec update and the code change are one atomic unit — commit them together.

- If you change how a signal is emitted or what parameters it carries → update `feature_spec-game_event_bus_signals.md`
- If you change a JSON schema → update the owning spec (see `docs/SYSTEMS.md` JSON ownership column)
- If you change physics behavior → update `feature_spec-physics_and_movement.md`
- If you add or remove a PerformanceMonitor metric → update both `feature_spec-performance_monitor.md` and `docs/SYSTEMS.md`

`Spec updated: no` in `decisions_log.md` is acceptable only for implementation details that are genuinely internal and invisible to other systems. When in doubt, update the spec.

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

## Session End Checklist

Before ending any session, in order:

1. **Run `graphify update .`** — keeps the knowledge graph current (AST-only, no API cost)
2. **Update build status** — update the table above to reflect what was completed
3. **Append to `docs/decisions_log.md`** — every decision made this session, with `Spec updated: yes/no/pending`
4. **If `Spec updated: pending`** — create a follow-up task note in the decisions entry so it isn't forgotten

---

## Agent Tiers

Not all tasks require the same agent. Match the task to the tool.

| Task type | Examples | Use |
|---|---|---|
| Architecture / spec changes | Redesigning a system, resolving conflicts | Claude Opus (Claude Code) |
| System implementation | Building Ship.gd, ProjectileManager.cs | Claude Sonnet (Cursor or Claude Code) |
| Mechanical / repetitive | Generating weapon JSON files, content stubs | Lighter agent / scripting |
| Doc updates | Updating build status, logging decisions | Any agent |

If a task feels architectural — it changes how systems relate, introduces a new pattern, or requires updating a spec — flag it rather than deciding yourself.

---

## Key Files

| File | Purpose |
|---|---|
| `docs/spec/core_spec.md` | Philosophy, architecture, cross-cutting rules |
| `docs/agent_brief.md` | This file — build status, protocols, deviation handling |
| `docs/decisions_log.md` | Full history of decisions and spec deviations |
| `docs/spec/feature_spec-*.md` | Per-system specifications (authoritative) |
| `docs/SYSTEMS.md` | Systems lookup — build step → spec, JSON ownership, PerformanceMonitor metrics |
| `data/` | Global config JSON (damage types, AI profiles, world config, factions) |
| `content/` | Per-item content folders (ships, weapons, modules, effects) |
| `core/` | Bootstrap, GameEventBus, ServiceLocator, StarField |
| `gameplay/` | All game systems |

---

## Recent Decisions

The most recent decisions are summarised here for quick context. Full history in
`docs/decisions_log.md`.

<!-- RECENT-DECISIONS-START -->
1. **2026-05-14 — Spec corrections from codebase audit** — Code authoritative in all cases: `projectile_hit` updated to VFX-notification signature, `ship_damaged` gained `amount` param, `ship_spawned`/`missile_detonated` documented, `lod_billboard_distance` removed from shader, `core/stars/` deleted. See decisions_log.md.
2. **2026-05-06 — SolarSystem Session D: Tuning + SolarPlayTest scene** — `interrupt_damage` key fix, `origin_shift_threshold` 1000→10000, hand-authored `content/systems/test_authored/system.json`, new `test/SolarPlayTest.tscn` for ongoing solar play testing. See decisions_log.md.
3. **2026-05-06 — SolarSystem Session C: OriginShifter + ChunkStreamer belt integration** — `OriginShifter.gd` created, `SolarSystem` emits `system_loaded`/`system_unloaded`, `ChunkStreamer` gates streaming on `system_loaded` and queries belt context per chunk. See decisions_log.md.
<!-- RECENT-DECISIONS-END -->
