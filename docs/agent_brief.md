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
| 9 | ShipFactory + ship assembly (GLB parts + `-colonly` → RigidBody3D collision) | Implemented |
| 10 | GameCamera — Pilot mode | Implemented |
| 11 | AIController + NavigationController integration | Implemented |
| 12 | Test scene: player vs AI, full Pilot mode loop | Implemented |
| 13 | Tactical mode camera + input layer | Implemented |
| 14 | Fleet Command — selection, orders, stance, escort queue | Implemented |
| 15 | ChunkStreamer + Asteroid + Debris | Implemented |
| 16 | GameEventBus signal audit | Implemented |
| 17 | Combat VFX System (Session 1: VFX core + pools; Session 2: local players) | In progress |
|| 18 | UI Foundation (UITokens, UITheme, StatBar, SegBar, HeatBar, WeaponSlot, RosterRow, ModeSwitch) | Implemented |
|| 19 | Pilot HUD (PilotHUD, Radar — five panels, hit flash, event subscriptions) | Implemented |
| 20 | Star System — Phase 1 (StarRecord, StarRegistry skeleton, catalog generation, LOD 0 MultiMesh point shader, `world_config.galaxy` block) | Implemented |
| 21 | Star System — Phase 2 (LOD 1 fullscreen-quad screen-pass glow shader, `_update_shader_uniforms`, closest-N cap, camera-attach lifecycle) | Implemented |
| 22 | Star System — Phase 3 (LOD 2 `StarMesh.tscn`, `star_surface.gdshader`, `star_corona.gdshader`, `_spawn_mesh` lifecycle, `StarRecord.light_range`, backdrop-clamp fix, `galaxy.star_mesh` tunables) | Implemented |
| 23 | Star System — Phase 4 (`star_exclusion_entered` signal in GameEventBus, `StarMesh` ExclusionArea live, collision_mask=1, body_entered handler filters to Ship, emits signal) | Implemented |
| 24 | Star System — Phase 5 (per-star `blend_alpha` + `lod_prev_state` on `StarRecord`; `mix()` crossfade in `star_point.gdshader`, `star_screen_pass.gdshader`, `star_surface.gdshader`, `star_corona.gdshader`; delayed LOD 2 despawn; frustum-cull stub at >200 screen-pass stars; `distance_squared_to()` perf optimisation; all four `StarRegistry.*` metrics) | Implemented |

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
| `docs/SYSTEMS.md` | Systems lookup — build step → spec, JSON ownership, PerformanceMonitor metrics |
| `data/` | Global config JSON (damage types, AI profiles, world config, factions) |
| `content/` | Per-item content folders (ships, weapons, modules) |
| `core/` | Bootstrap, GameEventBus, ServiceLocator |
| `gameplay/` | All game systems |

---

## Recent Decisions

The most recent decisions are summarised here for quick context. Full history in
`docs/decisions_log.md`.

<!-- RECENT-DECISIONS-START -->
1. **2026-05-02 — Star System Phase 5: LOD crossfade + perf** —
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
2. **2026-05-02 — Star System depth fix: reversed-Z occlusion** —
   `star_screen_pass.gdshader` vertex z changed `0.999 → 0.0001`
   (far plane in reversed-Z). Fragment adds `hint_depth_texture`
   sample; discards where `depth > 0.00001` (geometry present).
   Fixes stars painting in front of opaque objects.
3. **2026-05-01 — Star System Phase 3: LOD 2 mesh** —
   `StarMesh.tscn`, `star_surface.gdshader`, `star_corona.gdshader`,
   `_spawn_mesh` lifecycle, `StarRecord.light_range`, backdrop-clamp
   fix, `galaxy.star_mesh` JSON tunables block.
4. **2026-05-01 — Star System Phase 2: LOD 1 screen-pass glow** —
   `star_screen_pass.gdshader` fullscreen quad parented to Camera3D;
   built-in `PROJECTION_MATRIX * VIEW_MATRIX` in fragment; 256-star
   cap with closest-N selection; deviation from SubViewport spec
   logged (Godot #67633).
<!-- RECENT-DECISIONS-END -->
2. **2026-04-29 — UI Session 2: Pilot HUD** —
   PilotHUD.gd (five panels: Mode Tag, Target Lock, Vessel Status, Weapon Systems, Radar;
   hit flash overlay). Radar.gd (custom _draw() sweep + enemy dots via scene group query).
   Hardpoints discovered from ship's ShipVisual subtree on player_ship_changed.
   Heat polled from HardpointComponent. Ammo: ∞ for energy, -- for ballistic (deferred).
   Target Lock panel built but always hidden (player targeting not yet specced).
   Flash decay frame-rate-independent: 3.3 alpha/sec (≡ 0.055/frame at 60fps).
2. **2026-04-29 — UI Session 1: Foundation Layer** —
   UITokens autoload (all design token constants + font helpers), UITheme.tres (panel/
   label/button base styles), StatBar/SegBar/HeatBar/WeaponSlot/RosterRow components,
   ModeSwitch (Tab → game_mode_changed). Components build UI in _ready() via GDScript.
   Font application deferred gracefully until Orbitron + Share Tech Mono are imported
   into assets/fonts/. Corner-clip polygons deferred to post-MVP. No deviations.
2. **2026-04-29 — Ship collision from parts GLB (`-colonly`)** —
   ShipFactory assembles `part_name-colonly` meshes into child `CollisionShape3D` nodes on
   the ship `RigidBody3D`, removes the scene placeholder when any part defines collision,
   sets `part_category` meta for future use; whole-ship damage unchanged (raycast hits body).
   axum-fighter-1 `parts.glb` + blender asset committed; `feature_spec-ship_system.md` not yet
   updated for this pipeline. See decisions_log.md.
2. **2026-04-25 — Phase 17 Session 2: Combat VFX local players** —
   MuzzleFlashPlayer.gd (local GPUParticles3D per weapon, Muzzle-marker positioned),
   BeamRenderer.gd (BoxMesh stretched by look_at + scale.z, StandardMaterial3D placeholder),
   ShieldEffectPlayer.gd (drives shield_ripple.gdshader uniforms on parent ShieldMesh),
   assets/shaders/shield_ripple.gdshader (expanding ring ripple, blend_add).
   ShipFactory gains MuzzleFlashPlayer on every weapon, BeamRenderer on energy_beam weapons,
   _create_shield_mesh() for ships with shield_max > 0. Ship.gd gains shield_mesh reference.
   No deviations.
3. **2026-04-21 — Phase 16: GameEventBus signal audit** —
   Reconciled spec with code after phases 12-15. Added 12 undocumented signals to spec
   (tactical stop/stance/escort, context menu, escort & formation, ship_damaged, debug_toggled).
   Fixed queue_mode parameter on tactical move/attack/mine. Updated all emitter/listener
   columns to match actual connections. Marked reserved-but-unused signals (projectile_spawned,
   power_depleted, all station signals). No code changes — spec-only update. No deviations.
<!-- RECENT-DECISIONS-END -->
