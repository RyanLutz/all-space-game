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

> **Steps 20–24 are reference code from the superseded `feature_spec-star_system.md`.** The architecture built in these steps (`StarRegistry`, screen-pass quad glow shader, `StarMesh` LOD 2) has been replaced by `feature_spec-star_field_2.md` (step 25) and `feature_spec-solar_system.md` (step 26). The `core/stars/` implementation is retained for reference. Do not extend it.

| 25 | StarField S1–S4 complete: galaxy catalog, galactic map UI, galaxy sky shader, nebula map zoom wiring. All four PerformanceMonitor metrics in overlay. | Implemented |
| 26 | SolarSystem A–D complete. | Implemented |

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
1. **2026-05-06 — SolarSystem Session D: Tuning + SolarPlayTest scene** —
   `interrupt_damage_threshold` → `interrupt_damage` key fix (WarpDrive never read
   the JSON value). `origin_shift_threshold` 1000 → 10000 (was sub-chunk-size, triggered
   every load). `max_warp_speed` 2500 kept — ~34s for 5-planet system. Hand-authored
   override: `content/systems/test_authored/system.json` (neutron star, 2 planets, 1 belt).
   New `test/SolarPlayTest.tscn` combines full pilot+tactical loop with SolarSystem +
   ChunkStreamer — use this for ongoing solar system play testing and tuning.
   Spec updated: yes.
2. **2026-05-06 — SolarSystem Session C: OriginShifter + ChunkStreamer belt integration** —
   `OriginShifter.gd` created; parented to `SolarSystem` in `_ready()`. Shifts all
   `physics_bodies` group nodes + `SolarSystemRoot` when player exceeds `shift_threshold`
   (from `world_config.json`). `Ship.gd` + `Asteroid.gd` add `physics_bodies` group.
   `Planet._process` replaced with `update_orbit(delta, system_origin)` called from
   `SolarSystem._process` (flat `_orbiters` list, one perf timer for all orbital math).
   `SolarSystem` emits `system_loaded`/`system_unloaded`. `ChunkStreamer` gates streaming
   until `system_loaded`, stores SolarSystem ref, calls `get_belt_context_at()` per chunk,
   scales `max_fields` by `density_multiplier`. 5 perf monitors added to `GameBootstrap`.
   Note: `origin_shift_threshold` at 1000 is too low — tune in Session D.
   Spec updated: yes.
2. **2026-05-02 — Star System Phase 5: LOD crossfade + perf** —
   `StarRecord` gains `blend_alpha` (0→1 settling progress) and `lod_prev_state`.
   `StarRegistry._update_lod()` drives crossfade: delayed mesh despawn (LOD 2→1
   fades out over `lod_crossfade_frames` before queue_free), per-star
   `_compute_screen_pass_weight()` packed into `_u_color[i].w`.
   `distance_squared_to()` replaces `distance_to()` (eliminates 3000 sqrt/frame).
   Frustum-cull stub fires when `screen_pass_count > 200` (half-space dot product).
   `mix()` used in all four shaders: `star_point`, `star_screen_pass`,
   `star_surface`, `star_corona`. All four `StarRegistry.*` metrics in overlay.
2. **2026-05-02 — Star System Phase 4: ExclusionArea wired** —
   `star_exclusion_entered(star_id: int, ship_id: int)` added to
   `GameEventBus.gd`. `StarMesh._configure_exclusion()` enables
   `monitoring = true`, `collision_mask = 1` (ship layer),
   connects `body_entered` → handler filters to `Ship` bodies,
   emits `star_exclusion_entered`. Backdrop guard remains upstream
   in `StarRegistry._update_lod()`. Boundary-force enforcement
   flagged as integration point for physics/nav specs.
3. **2026-05-02 — Star System depth fix: reversed-Z occlusion** —
   `star_screen_pass.gdshader` vertex z changed `0.999 → 0.0001`
   (far plane in reversed-Z). Fragment adds `hint_depth_texture`
   sample; discards where `depth > 0.00001` (geometry present).
   Fixes stars painting in front of opaque objects.
4. **2026-05-01 — Star System Phase 3: LOD 2 mesh** —
   `StarMesh.tscn`, `star_surface.gdshader`, `star_corona.gdshader`,
   `_spawn_mesh` lifecycle, `StarRecord.light_range`, backdrop-clamp
   fix, `galaxy.star_mesh` JSON tunables block.
5. **2026-05-01 — Star System Phase 2: LOD 1 screen-pass glow** —
   `star_screen_pass.gdshader` fullscreen quad parented to Camera3D;
   built-in `PROJECTION_MATRIX * VIEW_MATRIX` in fragment; 256-star
   cap with closest-N selection; deviation from SubViewport spec
   logged (Godot #67633).
6. **2026-04-29 — UI Session 2: Pilot HUD** —
   PilotHUD.gd (five panels: Mode Tag, Target Lock, Vessel Status, Weapon Systems, Radar;
   hit flash overlay). Radar.gd (custom _draw() sweep + enemy dots via scene group query).
   Hardpoints discovered from ship's ShipVisual subtree on player_ship_changed.
   Heat polled from HardpointComponent. Ammo: ∞ for energy, -- for ballistic (deferred).
   Target Lock panel built but always hidden (player targeting not yet specced).
   Flash decay frame-rate-independent: 3.3 alpha/sec (≡ 0.055/frame at 60fps).
7. **2026-04-29 — UI Session 1: Foundation Layer** —
   UITokens autoload (all design token constants + font helpers), UITheme.tres (panel/
   label/button base styles), StatBar/SegBar/HeatBar/WeaponSlot/RosterRow components,
   ModeSwitch (Tab → game_mode_changed). Components build UI in _ready() via GDScript.
   Font application deferred gracefully until Orbitron + Share Tech Mono are imported
   into assets/fonts/. Corner-clip polygons deferred to post-MVP. No deviations.
8. **2026-04-29 — Ship collision from parts GLB (`-colonly`)** —
   ShipFactory assembles `part_name-colonly` meshes into child `CollisionShape3D` nodes on
   the ship `RigidBody3D`, removes the scene placeholder when any part defines collision,
   sets `part_category` meta for future use; whole-ship damage unchanged (raycast hits body).
   axum-fighter-1 `parts.glb` + blender asset committed; `docs/spec/feature_spec-ship_system.md`
   not yet updated for this pipeline. Spec updated: pending.
9. **2026-04-25 — Phase 17 Session 2: Combat VFX local players** —
   MuzzleFlashPlayer.gd, BeamRenderer.gd, ShieldEffectPlayer.gd, shield_ripple.gdshader.
   ShipFactory gains MuzzleFlashPlayer on every weapon, BeamRenderer on energy_beam weapons,
   _create_shield_mesh() for ships with shield_max > 0. Ship.gd gains shield_mesh reference.
   No deviations.
10. **2026-04-21 — Phase 16: GameEventBus signal audit** —
    Reconciled spec with code after phases 12-15. Added 12 undocumented signals to spec.
    Fixed queue_mode parameter on tactical move/attack/mine. Updated all emitter/listener
    columns. Marked reserved-but-unused signals. No code changes — spec-only update.
<!-- RECENT-DECISIONS-END -->
