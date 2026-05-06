# All Space — Development Guide

*Build order, model assignments, and session workflow*

---

## How to Use This Document

Work top to bottom. Each row is one agent session. When a step is done, check it off.
Do not skip steps — every system depends on the ones before it.

The **Model** column uses three tiers:
- **Opus** — high blast radius (other systems depend on this) or requires novel decisions
  that the spec cannot fully anticipate
- **Sonnet** — well-bounded scope, clear spec contract, novel math or shader work, limited
  downstream blast radius
- **Haiku** — routine work: UI wiring, event bus hookup, connecting already-built systems,
  tuning passes, checklist verification

---

## Build Order

| # | Status | System | Spec Reference | Model | Notes |
|---|---|---|---|---|---|
| 1 | ✅ | PerformanceMonitor | `spec/feature_spec-performance_monitor.md` | Sonnet | First build. Proves the CLI workflow. Tight spec, low risk. Test scene: `test/PerformanceMonitorTest.tscn`. |
| 2 | ✅ | ServiceLocator + GameEventBus + GameBootstrap | `spec/core_spec.md` §§ 8–9 | **Opus** | Load-bearing foundation. Every other system depends on the event bus contract. |
| 3 | ✅ | ContentRegistry | `spec/feature_spec-ship_system.md` (ContentRegistry section) | Sonnet | JSON loading and folder-per-item resolution. Well-defined, bounded. |
| 4 | ✅ | SpaceBody + Ship (physics only, no weapons) | `spec/feature_spec-physics_and_movement.md` | **Opus** | RigidBody3D + Jolt integration with XZ plane enforcement, thruster budget, and alignment drag. Novel and high blast radius. Test scene: `test/ShipPhysicsTest.tscn`. |
| 5 | ✅ | NavigationController | `spec/feature_spec-nav_controller.md` | **Opus** | Flight computer with braking/arrival algorithm. Complex math, novel logic. |
| 6 | ✅ | ProjectileManager (C#, dumb pool) | `spec/feature_spec-weapons_and_projectiles.md` | **Opus** | Only C# system. Performance-critical. Requires holding the full pooling architecture in context. |
| 7 | ✅ | WeaponComponent + HardpointComponent | `spec/feature_spec-weapons_and_projectiles.md` | Sonnet | Hardpoint types (fixed/gimbal/turret), heat system, fire groups, aim algorithm. All non-missile archetypes fire. Test scene: `test/WeaponTest.tscn`. |
| 8 | ✅ | GuidedProjectilePool | `spec/feature_spec-weapons_and_projectiles.md` | Sonnet | GDScript guided missile pool with track_cursor, auto_lock, click_lock modes. Area damage with falloff. |
| 9 | ✅ | ShipFactory + Ship visual assembly | `spec/feature_spec-ship_system.md` | Sonnet | `ShipFactory.gd`, `PlayerState.gd`, `ship_colorize.gdshader`. Spawns from `ship.json` + `parts.glb`; hardpoints `HardpointEmpty_{part}_{id}_{size}`. Example ship: `content/ships/axum-fighter-1/`. Test scene: `test/ShipFactoryTest.tscn`. |
| 10 | ✅ | GameCamera — Pilot mode | `spec/feature_spec-camera_system.md` | Sonnet | Follow camera with cursor offset. Bounded, spec is clear. |
| 11 | ✅ | AIController (+ NavigationController integration) | `spec/feature_spec-ai_patrol_behavior.md` | **Opus** | `AIController.gd` state machine; `data/ai_profiles.json` via ContentRegistry. ShipFactory attaches NavigationController, DetectionVolume (Area3D), and AIController for AI ships; nav uses `get_parent()` as ship. Test scene: `test/ShipFactoryTest.tscn`. |
| 12 | ✅ | Test scene: player vs AI, full Pilot mode loop | — | Sonnet | Wire existing systems into a playable test. No new logic; mostly scene setup and signal hookup. Test scene: `test/PilotLoopTest.tscn`. |
| 13 | ✅ | Tactical mode camera + input layer | `spec/feature_spec-camera_system.md`, `spec/feature_spec-fleet_command.md` | **Opus** | `InputManager.gd` (Tab toggle, pilot input routing), `SelectionState.gd`, `TacticalInputHandler.gd`, GameCamera tactical free-pan. All in `gameplay/fleet_command/`. Test via `test/PilotLoopTest.tscn`. |
| 14 | ✅ | Fleet Command — selection, orders, stance, escort queue | `spec/feature_spec-fleet_command.md` | **Opus** | Full RTS command layer. Large spec, many interacting concerns. |
| 15 | ✅ | ChunkStreamer + Asteroid + Debris | `spec/feature_spec-chunk_streamer.md` | **Opus** | Streaming architecture with deterministic generation. Novel and high blast radius — incorrect chunk lifecycle breaks AI spawning and everything in the world. |
| 16 | ✅ | GameEventBus signal audit | `spec/feature_spec-game_event_bus_signals.md` | Sonnet | Cross-cutting signal catalog. Spec reconciled with code — 12 signals added, 3 signatures fixed, emitter/listener columns updated. No code changes. |
| 17 | ✅ | Combat VFX System | `spec/feature_spec-combat_vfx.md` | Opus + Sonnet | Muzzle, beam, impact, shield, explosions. 3 sessions. |
| 18 | ✅ | Star System — Phase 1: Data + Generation + LOD 0 *(old spec — superseded)* | `spec/feature_spec-star_system.md` *(SUPERSEDED)* | Sonnet | `StarRecord.gd`, `StarRegistry.gd` skeleton, procedural catalog from seed (two-component bulge+disc distribution), `MultiMeshInstance3D` for galactic-scale point rendering. `world_config.json` galaxy fields. All four `StarRegistry.*` PerformanceMonitor metrics wired. Test scene: `test/StarSystemTest.tscn`. |
| 19 | ✅ | Star System — Phase 2: Screen-Space Glow Shader (LOD 1) *(old spec — superseded)* | `spec/feature_spec-star_system.md` *(SUPERSEDED)* | **Opus** | `star_screen_pass.gdshader` — fullscreen `MeshInstance3D` quad parented to `Camera3D`; fragment uses built-in `PROJECTION_MATRIX * VIEW_MATRIX`; 256-star cap. **Deviation logged** (decisions_log 2026-05-01): SubViewport replaced with 3D fullscreen quad due to Godot 4.x CanvasLayer regression #67633. |
| 20 | ✅ | Star System — Phase 3: StarMesh + Surface / Corona Shaders (LOD 2) *(old spec — superseded)* | `spec/feature_spec-star_system.md` *(SUPERSEDED)* | **Opus** | `core/stars/StarMesh.tscn` (3 concentric `SphereMesh` layers + corona `QuadMesh` + `OmniLight3D` + `Area3D` exclusion stub), `star_surface.gdshader` (object-local 3D fBm, TIME-driven flow), `star_corona.gdshader` (billboard, additive). |
| 21 | ✅ | Star System — Phase 4: Exclusion Zone + GameEventBus Integration *(old spec — superseded)* | `spec/feature_spec-star_system.md` *(SUPERSEDED)* | Sonnet | `star_exclusion_entered(star_id, ship_id)` added to GameEventBus. `StarMesh._configure_exclusion()` wired with monitoring + collision_mask=1. |
| 22 | ✅ | Star System — Phase 5: LOD Crossfade + Performance Validation *(old spec — superseded)* | `spec/feature_spec-star_system.md` *(SUPERSEDED)* | Sonnet | Per-star `blend_alpha` crossfade; `distance_squared_to()` perf opt; frustum-cull stub at >200 screen-pass stars. All four `StarRegistry.*` metrics in overlay; lod_update under 1ms. |

> **Steps 18–22 were built from `feature_spec-star_system.md`, which has been superseded.** The `core/stars/` implementation is retained as reference code. Do not extend it. See steps 23–30 below.

---

## Next Steps — StarField System (step 25 in project build order)

*Spec: `spec/feature_spec-star_field_2.md` — Session breakout: `spec/feature_spec-star_field-session_breakout.md`*

Sessions 24 and 25 can run in parallel after session 23 completes.

| # | Status | Session | Spec Reference | Model | Notes |
|---|---|---|---|---|---|
| 23 | ✅ | StarField S1 — Galaxy Generator + Testable Map Scene | `spec/feature_spec-star_field_2.md` | Sonnet | Most important session. Delivers: `StarField.gd` (catalog generation only), `StarRecord.gd`, `NebulaVolume.gd`, four-zone generator (smoothstep blending, logarithmic spiral arms, Y-thickness profile, color gradient), separate RNG branches for backdrop / destination systems / nebulae, standalone test scene with `MultiMeshInstance3D` galaxy preview, pan+zoom. All params in `world_config.json` starfield block. **You validate:** Does it look like a galaxy? Are spiral arms visible? Is the core dense and red? Tune JSON until happy before proceeding. |
| 24 | ✅ | StarField S2 — Galactic Map UI Layer | `spec/feature_spec-star_field_2.md` | **Haiku** | Takes the S1 test scene and wraps it in a proper UI mode. Delivers: `GalacticMap.gd` / `GalacticMap.tscn` as `CanvasLayer`, toggle via `GameEventBus.galactic_map_toggled`, destination systems highlighted, reachable systems glow by warp range, pan + zoom, `warp_destination_selected(system_id)` emitted on selection, three zoom levels with information density scaling. **Runs in parallel with S3 after S1.** |
| 25 | ✅ | StarField S3 — Skybox + Nebula Rendering | `spec/feature_spec-star_field_2.md` | Sonnet | Visual centerpiece. Delivers: `core/starfield/galaxy_sky.gdshader` (Godot `Sky` custom shader with `render_mode use_debanding`), backdrop + destination stars packed into two `sampler2D` textures (RGBAF direction+size, RGBA8 color+brightness) via `tex_width`/`tex_height` uniforms, domain-warped value noise nebula field in galaxy space keyed off `player_galaxy_position`, 24-volume nebula tinting via `vec3/vec4/float[32]` uniform arrays, `map_zoom` uniform, `StarField.rebuild_skybox()` fully implemented, warp simulation in `StarFieldTest` (Space=next dest, Backspace=galaxy center). `skybox_star_limit` in `world_config.json`. `StarField` registered as autoload. **You validate:** Does the sky look like you are inside a galaxy? Do nebulae have organic cloud shapes with dark voids? Does the sky shift plausibly on Space-warp? **Ran in parallel with S2 after S1.** |
| 26 | ✅ | StarField S4 — Galactic Map Nebula + Polish | `spec/feature_spec-star_field_2.md` | **Haiku** | Connects S3 nebula rendering into S2 map zoom levels. Delivers: nebula color regions fade in at mid map zoom, `map_zoom` piped from GalacticMap zoom state to sky shader, nav path lines between reachable systems at mid/close zoom, all PerformanceMonitor metrics in overlay, full success criteria checklist run and checked off. |

---

## Next Steps — SolarSystem (step 26 in project build order)

*Spec: `spec/feature_spec-solar_system.md` — Session breakout: `spec/feature_spec-solar_system-session_breakout.md`*

**Before Session 27:** Add the Solar System and Warp signals to `GameEventBus.gd` (definitions are already in `feature_spec-game_event_bus_signals.md`). Sessions 28 and 29 can run in parallel after Session 27 completes.

| # | Status | Session | Spec Reference | Model | Notes |
|---|---|---|---|---|---|
| 27 | ✅ | SolarSystem A — Generator + Flyable Test Scene | `spec/feature_spec-solar_system.md` | Sonnet | Foundation. Delivers: `SolarSystemGenerator.gd` (pure generation logic; returns Dictionary manifest from `system_id` + `galaxy_seed`; checks `content/systems/<id>/system.json` override first), `SolarSystem.gd` (instantiates manifest), `Star.gd` (sphere at `Y = -star_center_depth`, `OmniLight3D`, visual exclusion ring), `Planet.gd` (orbital drift in `_process`, `moon_mode`), `Station.gd` (placement only), `solar_system_archetypes.json`, flyable test scene with player ship. **You validate:** Same seed + system_id = same layout. Star correctly below Y=0. Planets drift visibly. Binary stars produce two exclusion rings. |
| 28 | 🔲 | SolarSystem B — Exclusion Zone + WarpDrive | `spec/feature_spec-solar_system.md` | Sonnet | Delivers: `Star.gd` XZ distance check in `_physics_process` + `ship.apply_damage()` call + `exclusion_zone_entered/exited` signals, `WarpDrive.gd` state machine (`IDLE → SPOOLING → ACTIVE → DECELERATING`), spool/decel timers, `warp_multiplier` integration with ship physics (read `feature_spec-physics_and_movement.md` first to determine cleanest hookup), interrupt conditions (damage + exclusion proximity), `warp_state_changed` / `warp_interrupted` signals emitted. **Runs in parallel with 29 after 27.** |
| 29 | 🔲 | SolarSystem C — OriginShifter + ChunkStreamer Belt Integration | `spec/feature_spec-solar_system.md` | **Haiku** | Delivers: `OriginShifter.gd` (subscribes to `chunk_loaded`, shifts `"physics_bodies"` group + solar system visual root, emits `origin_shifted`), `add_to_group("physics_bodies")` in `Ship.gd` and `Asteroid.gd` (additive, no behavior changes), `SolarSystem.get_belt_context_at(world_pos)` method, `ChunkStreamer._populate_asteroids` modified to call `get_belt_context_at()` per chunk, `system_loaded` / `system_unloaded` signals emitted. **Runs in parallel with 28 after 27.** |
| 30 | 🔲 | SolarSystem D — JSON Tuning Pass + Success Criteria | `spec/feature_spec-solar_system.md` | **Haiku** | Polish. Tune `solar_system_archetypes.json`: star depth/radius (reads as dangerous from pilot cam), planet radii/depths (visible from default camera angle), `warp_speed_multiplier` (30–90s to cross system at max warp), belt density (noticeably denser than open space), orbital speeds (visible drift over 5-minute session). Verify hand-authored override path. Confirm all PerformanceMonitor metrics in overlay; orbit update < 0.1ms at max system size (20 planets × 10 moons). Run full success criteria checklist. |

---

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