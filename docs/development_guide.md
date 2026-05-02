# All Space — Development Guide

*Build order, model assignments, and session workflow*

---

## How to Use This Document

Work top to bottom. Each row is one agent session. When a step is done, check it off.
Do not skip steps — every system depends on the ones before it.

The **Model** column uses two tiers:
- **Opus** — high blast radius (other systems depend on this) or requires novel decisions
  that the spec cannot fully anticipate
- **Sonnet** — well-bounded scope, clear spec contract, limited downstream blast radius

---

## Build Order

| # | Status | System | Spec Reference | Model | Notes |
|---|---|---|---|---|---|
| 1 | ✅ | PerformanceMonitor | `feature_spec-performance_monitor.md` | Sonnet | First build. Proves the CLI workflow. Tight spec, low risk. Test scene: `test/PerformanceMonitorTest.tscn`. |
| 2 | ✅ | ServiceLocator + GameEventBus + GameBootstrap | `core_spec.md` §§ 8–9 | **Opus** | Load-bearing foundation. Every other system depends on the event bus contract. |
| 3 | ✅ | ContentRegistry | `feature_spec-ship_system.md` (ContentRegistry section) | Sonnet | JSON loading and folder-per-item resolution. Well-defined, bounded. |
| 4 | ✅ | SpaceBody + Ship (physics only, no weapons) | `feature_spec-physics_and_movement.md` | **Opus** | RigidBody3D + Jolt integration with XZ plane enforcement, thruster budget, and alignment drag. Novel and high blast radius. Test scene: `test/ShipPhysicsTest.tscn`. |
| 5 | ✅ | NavigationController | `feature_spec-nav_controller` | **Opus** | Flight computer with braking/arrival algorithm. Complex math, novel logic. |
| 6 | ✅ | ProjectileManager (C#, dumb pool) | `feature_spec-weapons_and_projectiles.md` | **Opus** | Only C# system. Performance-critical. Requires holding the full pooling architecture in context. |
| 7 | ✅ | WeaponComponent + HardpointComponent | `feature_spec-weapons_and_projectiles.md` | Sonnet | Hardpoint types (fixed/gimbal/turret), heat system, fire groups, aim algorithm. All non-missile archetypes fire. Test scene: `test/WeaponTest.tscn`. |
| 8 | ✅ | GuidedProjectilePool | `feature_spec-weapons_and_projectiles.md` | Sonnet | GDScript guided missile pool with track_cursor, auto_lock, click_lock modes. Area damage with falloff. |
| 9 | ✅ | ShipFactory + Ship visual assembly | `feature_spec-ship_system.md` | Sonnet | `ShipFactory.gd`, `PlayerState.gd`, `ship_colorize.gdshader`. Spawns from `ship.json` + `parts.glb`; hardpoints `HardpointEmpty_{part}_{id}_{size}`. Example ship: `content/ships/axum-fighter-1/`. Test scene: `test/ShipFactoryTest.tscn`. |
| 10 | ✅ | GameCamera — Pilot mode | `feature_spec-camera_system.md` | Sonnet | Follow camera with cursor offset. Bounded, spec is clear. |
| 11 | ✅ | AIController (+ NavigationController integration) | `feature_spec-ai_patrol_behavior.md` | **Opus** | `AIController.gd` state machine; `data/ai_profiles.json` via ContentRegistry. ShipFactory attaches NavigationController, DetectionVolume (Area3D), and AIController for AI ships; nav uses `get_parent()` as ship. Test scene: `test/ShipFactoryTest.tscn`. |
| 12 | ✅ | Test scene: player vs AI, full Pilot mode loop | — | Sonnet | Wire existing systems into a playable test. No new logic; mostly scene setup and signal hookup. Test scene: `test/PilotLoopTest.tscn`. |
| 13 | ✅ | Tactical mode camera + input layer | `feature_spec-camera_system.md`, `feature_spec-fleet_command` | **Opus** | `InputManager.gd` (Tab toggle, pilot input routing), `SelectionState.gd`, `TacticalInputHandler.gd`, GameCamera tactical free-pan. All in `gameplay/fleet_command/`. Test via `test/PilotLoopTest.tscn`. |
| 14 | ✅ | Fleet Command — selection, orders, stance, escort queue | `feature_spec-fleet_command` | **Opus** | Full RTS command layer. Large spec, many interacting concerns. |
| 15 | ✅ | ChunkStreamer + Asteroid + Debris | `feature_spec-chunk_streamer.md` | **Opus** | Streaming architecture with deterministic generation. Novel and high blast radius — incorrect chunk lifecycle breaks AI spawning and everything in the world. |
| 16 | ✅ | GameEventBus signal audit | `feature_spec-game_event_bus_signals.md` | Sonnet | Cross-cutting signal catalog. Spec reconciled with code — 12 signals added, 3 signatures fixed, emitter/listener columns updated. No code changes. |
| 17 | ✅ | Combat VFX System | `feature_spec-combat_vfx.md` | Opus + Sonnet | Muzzle, beam, impact, shield, explosions. 3 sessions. |
| 18 | ✅ | Star System — Phase 1: Data + Generation + LOD 0 | `feature_spec-star_system.md` | Sonnet | `StarRecord.gd`, `StarRegistry.gd` skeleton, procedural catalog from seed (two-component bulge+disc distribution), `MultiMeshInstance3D` for galactic-scale point rendering. `world_config.json` galaxy fields. All four `StarRegistry.*` PerformanceMonitor metrics wired. Test scene: `test/StarSystemTest.tscn` (added in Phase 2). |
| 19 | ✅ | Star System — Phase 2: Screen-Space Glow Shader (LOD 1) | `feature_spec-star_system.md` | **Opus** | `star_screen_pass.gdshader` — fullscreen `MeshInstance3D` quad parented to `Camera3D`; vertex writes POSITION in NDC at clip z=0.999 so default depth test occludes against scene; fragment uses built-in `PROJECTION_MATRIX * VIEW_MATRIX` to project per-star world positions (no CPU VP uniform → no rotation lag). `_update_shader_uniforms()` packs visible star list (`vec4` arrays, `PackedVector4Array`) with closest-N cap of 256 (`MAX_SCREEN_PASS_STARS`); frustum culling deferred to Phase 5. `min_pixel_radius` lifted to `world_config.json` and shared by both LOD 0 and LOD 1 shaders so the boundary cannot develop a size discontinuity. Test scene: `test/StarSystemTest.tscn`. **Deviation logged** (decisions_log 2026-05-01): SubViewport approach replaced with 3D fullscreen quad due to Godot 4.x CanvasLayer regression #67633. |
| 20 | 🔲 | Star System — Phase 3: StarMesh + Surface / Corona Shaders (LOD 2) | `feature_spec-star_system.md` | **Opus** | `StarMesh.tscn` (layered billboard spheres + OmniLight3D + ExclusionArea stub), `StarMesh.gd`, `star_surface.gdshader` (noise-driven animated plasma, TIME uniform), `star_corona.gdshader` (additive billboard). `_spawn_mesh()` / `_despawn_mesh()` lifecycle. Backdrop tier guard — never reaches LOD 2. Gate: close-range star has roiling surface animation, corona glow, and its light colors nearby ships. |
| 21 | 🔲 | Star System — Phase 4: Exclusion Zone + GameEventBus Integration | `feature_spec-star_system.md` | Sonnet | Wire `ExclusionArea` (`Area3D + SphereShape3D`) in `StarMesh.tscn` from `StarRecord.exclusion_radius`. Emit `star_exclusion_entered(star_id, ship_id)` on `GameEventBus`. Confirm backdrop stars never spawn exclusion area. Flag boundary-force integration point for physics/nav specs. Gate: signal fires on breach; no exclusion area on backdrop stars. |
| 22 | 🔲 | Star System — Phase 5: LOD Crossfade + Performance Validation | `feature_spec-star_system.md` | Sonnet | Per-star `blend_alpha` float; crossfade over `lod_crossfade_frames` using `mix()` in screen-pass and MultiMesh shaders. Profile `StarRegistry.lod_update` at 3000 stars — must be < 1ms. Add frustum-culling stub for `_screen_pass_stars` if `screen_pass_count` > ~200. Gate: no visible pop at LOD transitions; all four metrics in overlay; lod_update under 1ms. |
| — | 🔲 | Station & Loadout UI | Not yet specced | TBD | Post-MVP. Spec before building. |
| — | 🔲 | Galactic Strategy | Not yet specced | TBD | Phase 3. Do not spec until MVP loop is proven. |

---

## Session Checklist

Before starting any agent session:

- [ ] Previous step is committed and working
- [ ] You know which spec file the agent should read
- [ ] The `.cursor/rules/always-on.mdc` is present and current
- [ ] Any `.mdc` files from prior sessions that this system depends on exist

During the session:

- [ ] Confirm the agent reads the spec before writing any code
- [ ] Confirm the agent produces a `.cursor/rules/[system].mdc` file on completion
- [ ] Watch for the agent touching files outside the system's declared scope (flag it)

After the session:

- [ ] Run the relevant test scene for the step you touched (e.g. `test/ShipFactoryTest.tscn` for Step 9, `test/ShipPhysicsTest.tscn` for Step 4) — nothing regresses; Step 12 uses `test/PilotLoopTest.tscn` (also the project main scene)
- [ ] Mark the step complete in this document
- [ ] Commit before starting the next session

---

## Model Decision Rule (quick reference)

**Use Opus when:**
- Other systems depend directly on the output (high blast radius)
- The spec cannot fully anticipate decisions the agent will face (novel)
- The system crosses multiple spec files simultaneously
- It's C# (ProjectileManager only)

**Use Sonnet when:**
- The spec contract is tight and complete
- The system is largely self-contained
- Errors here are easy to catch and fix without cascading

**When in doubt:** Opus. The cost delta is not worth a broken foundation.

---

## Spec Authority Reminder

Core Spec > Feature Spec > Agent assumption.

If the implementing agent finds a conflict between the core spec and a feature spec,
it must surface the conflict and stop — not silently resolve it. Build this into your
session prompt.