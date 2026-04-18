---
name: all-space-project
description: >
  Load context and conventions for the "All Space" space combat simulation game project.
  Use this skill at the start of ANY session involving the All Space game — including
  design discussions, spec writing, architecture questions, code review, or system planning.
  Trigger whenever the user mentions "All Space", "the space game", "the combat sim",
  "the MVP", references any of the game's systems (weapons, physics, projectiles, ships,
  hardpoints, chunks, fleet command, AI, camera, navigation), or asks to continue working
  on the game project. Also trigger when the user asks to write a spec, update agent
  context, or plan a build session.
---

# All Space — Project Skill

Load this skill at the start of any All Space design or development session. It provides
the conventions, architecture rules, and spec format that must be consistent across all
sessions and all agents (Cursor, Claude Code, etc).

---

## Project Summary

**"All Space"** is a top-down 3D space combat simulation built in Godot 4.6 (GDScript
primary, C# for ProjectileManager only). Gameplay is constrained to the **XZ plane
(Y = 0)**. Everything is 3D — ships use `RigidBody3D`, detection uses `Area3D`, camera
is `Camera3D`. There are no 2D physics nodes in this project.

The current focus is a **combat MVP** — Pilot mode (direct ship control) and Tactical
mode (RTS fleet orders), a streaming map, ship customization, and roaming AI patrols.
The long-term vision scales to fleet command and empire building, but the MVP does not
implement those layers.

**Core philosophy:** "As complex or as simple as the player wants it to be."

---

## Tech Stack

| Concern | Choice | Notes |
|---|---|---|
| Engine | Godot 4.6 | — |
| Primary language | GDScript | All systems except where noted |
| Performance-critical | C# | ProjectileManager only at MVP |
| Physics backend | Jolt (Godot 4.6 default) | Full 3D physics; applies natively to all 3D nodes |
| Ship physics node | `RigidBody3D` | Forces/torques applied in `_integrate_forces()`; Jolt integrates; Y-translation and X/Z-rotation axis-locked |
| Play plane | XZ (Y = 0) | All ships, projectiles, gameplay at Y = 0 |
| Camera | `Camera3D`, perspective | Top-down, fixed angle; height above XZ sets zoom |
| Data / modding | JSON | All tunable values; no recompile for balance passes |
| Inter-system comms | `GameEventBus.gd` | No direct cross-system references |
| Service registry | `ServiceLocator.gd` (autoload) | Thin registry only |

---

## Hard Constraints — Never Violate

These apply to every suggestion, every session, every agent:

- **No 2D physics nodes** — `CharacterBody2D`, `RigidBody2D`, `Area2D`,
  `CollisionShape2D`, `Camera2D`, `Node2D` are banned from this project entirely.
- **`Vector2` banned for world-space** — never use `Vector2` for positions or velocities.
  `Vector2i` is permitted for chunk grid coordinates only.
- **Y = 0 always** — enforce `position.y = 0` after every physics update. Velocities
  always have `velocity.y = 0`.
- **Yaw only** — ship rotation uses Y axis only. `rotation.x` and `rotation.z` are
  always 0.
- **Ship forward** is `-transform.basis.z` — never `Vector2.RIGHT.rotated(rotation)`.
- **Mouse-to-world via ray-plane intersection** against Y = 0 — `get_global_mouse_position()`
  does not exist in 3D.
- **GameCamera is never a child of a ship** — it is a sibling of the game world.
- **One Ship.tscn for all ship types** — no `FighterShip.tscn` vs `DestroyerShip.tscn`.
  Configuration happens at spawn time from JSON via `ShipFactory.gd`.
- **C# only for ProjectileManager** — all other systems are GDScript.
- **PerformanceMonitor instrumentation required** — every system spec and implementation
  must include it.

---

## Project Structure

```
/all_space/
    CLAUDE.md                          ← agent entry point; points to agent_brief.md
    /docs/
        core_spec.md                   ← authoritative source of truth
        agent_brief.md                 ← build status, rules, deviation protocol
        decisions_log.md               ← append-only decision history
        feature_spec-performance_monitor.md
        feature_spec-physics_and_movement.md
        feature_spec-ship_system.md
        feature_spec-weapons_and_projectiles.md
        feature_spec-camera_system.md
        feature_spec-ai_patrol_behavior.md
        feature_spec-nav_controller.md
        feature_spec-chunk_streamer.md
        feature_spec-fleet_command.md
        feature_spec-game_event_bus_signals.md
    /.claude/
        /commands/
            new-ship.md                ← slash command: generate ship folder + ship.json
            new-weapon.md              ← slash command: generate weapon folder + weapon.json
            session-end.md             ← slash command: enforce session close discipline
    /core/
        /services/
            ServiceLocator.gd
            PerformanceMonitor.gd
        GameEventBus.gd
        GameBootstrap.gd
    /gameplay/
        /physics/
            SpaceBody.gd
        /entities/
            Ship.gd
            Ship.tscn                  ← one scene for ALL ship types
            ShipFactory.gd
            Asteroid.gd
            Debris.gd
        /ai/
            AIController.gd
            AIController.tscn
            NavigationController.gd
        /weapons/
            ProjectileManager.cs       ← C# only
            GuidedProjectilePool.gd
            WeaponComponent.gd
            HardpointComponent.gd
        /camera/
            GameCamera.gd
            GameCamera.tscn
        /parts/                        ← ship part sub-scenes (hull, engine, wing, etc.)
    /content/
        /ships/                        ← one folder per ship type
            /fighter_light/
                ship.json
                model.glb
                icon.png
        /weapons/                      ← one folder per weapon
        /modules/                      ← one folder per module
    /data/
        damage_types.json
        ai_profiles.json
        factions.json
        world_config.json
    /ui/
        /debug/
            PerformanceOverlay.tscn
            PerformanceOverlay.gd
    /assets/
        /shaders/
            ship_colorize.gdshader
    /test/
        TestScene.tscn
```

---

## Architecture Rules

These rules apply to every system, every session, every agent:

1. **No hardcoded values** — anything tunable belongs in JSON under `/data/` or
   `/content/<item>/`. Stats, ranges, timings, damage — all JSON.
2. **No direct cross-system references** — use `GameEventBus` for communication between
   systems. A system may hold references to its own components; it may not reach into
   another system's internals.
3. **PerformanceMonitor instrumentation is required** — every system spec includes a
   Performance Instrumentation section; every implementation follows it.
4. **One system per agent session** — do not mix concerns across systems in one session.
5. **Specs are authoritative** — if a spec says to do something a particular way, do it
   that way; flag conflicts rather than silently resolving them.
6. **C# only for ProjectileManager** — all other systems are GDScript.
7. **Enforce Y = 0** — any system that moves entities must enforce `position.y = 0`
   after every physics update.
8. **One Ship.tscn** — configuration happens at spawn time via `ShipFactory.gd`.

---

## Spec Status

| Spec | File | Spec | Impl |
|---|---|---|---|
| PerformanceMonitor | `feature_spec-performance_monitor.md` | ✅ | 🔲 |
| Physics & Movement | `feature_spec-physics_and_movement.md` | ✅ | 🔲 |
| Ship System | `feature_spec-ship_system.md` | ✅ | 🔲 |
| Weapons & Projectiles | `feature_spec-weapons_and_projectiles.md` | ✅ | 🔲 |
| Camera System | `feature_spec-camera_system.md` | ✅ | 🔲 |
| AI & Patrol Behavior | `feature_spec-ai_patrol_behavior.md` | ✅ | 🔲 |
| NavigationController | `feature_spec-nav_controller.md` | ✅ | 🔲 |
| Chunk Streamer | `feature_spec-chunk_streamer.md` | ✅ | 🔲 |
| Fleet Command | `feature_spec-fleet_command.md` | ✅ | 🔲 |
| GameEventBus Signals | `feature_spec-game_event_bus_signals.md` | ✅ | 🔲 |
| Station & Loadout UI | — | 🔲 | 🔲 |

---

## PerformanceMonitor Integration Contract

**Every system spec must include a "Performance Instrumentation" section.**
**Every implementation must follow it.**

`PerformanceMonitor` is registered before any other system via `GameBootstrap.gd`.
It is built first, always.

Canonical metric names — use exactly these strings:

| Metric | Name |
|---|---|
| Dumb projectile pool update | `ProjectileManager.dumb_update` |
| Guided projectile pool update | `ProjectileManager.guided_update` |
| Projectile collision checks | `ProjectileManager.collision_checks` |
| AI state machine updates | `AIController.state_updates` |
| Navigation controller update | `Navigation.update` |
| Ship thruster allocation | `Physics.thruster_allocation` |
| Hit detection / component resolve | `HitDetection.component_resolve` |
| Chunk load | `ChunkStreamer.load` |
| Chunk unload | `ChunkStreamer.unload` |
| Content registry startup scan | `ContentRegistry.load` |
| Ship assembly | `ShipFactory.assemble` |
| Camera update | `Camera.update` |
| Active projectiles (count) | `ProjectileManager.active_count` |
| Active AI ships (count) | `AIController.active_count` |
| Active physics bodies (count) | `Physics.active_bodies` |
| Active ships (count) | `Ships.active_count` |
| Loaded chunks (count) | `ChunkStreamer.loaded_chunks` |

Usage pattern:
```gdscript
PerformanceMonitor.begin("System.method")
# ... critical work ...
PerformanceMonitor.end("System.method")

PerformanceMonitor.set_count("System.metric", value)
```

Rules:
- Only instrument operations expected to take > 0.1ms
- Never instrument inside inner loops — wrap the whole loop
- `begin()` / `end()` must always be paired

---

## Spec Format

When writing a new system spec, always include these sections in order:

1. **Overview** — what the system does, design goals
2. **Architecture** — how it fits in the project structure; diagram if helpful
3. **Core properties / data model**
4. **Key algorithms** — with GDScript pseudocode where helpful
5. **JSON data format** — if system owns any data files
6. **Performance Instrumentation** — required; uses contract above
7. **Files** — exact paths for all files this system creates or modifies
8. **Dependencies** — what must exist before this system can be built
9. **Assumptions** — explicit list of values/decisions deferred to balancing
10. **Success Criteria** — checkbox list, concrete and testable

---

## Key Design Decisions

### Physics

- `RigidBody3D` with Jolt; forces and torques applied in `_integrate_forces()`; Jolt integrates — ships do **not** use `CharacterBody3D` or manual velocity
- Y-translation and X/Z-rotation axis-locked in Jolt; Y enforced explicitly after every physics update as a backstop
- **Assisted steering** — auto counter-torque prevents rotation overshoot; ships track the aim point smoothly without oscillation
- **Shared thruster budget** — turning takes priority; translation gets the remainder
- **Alignment drag** — lateral velocity bleeds when active (opt-in); axial velocity along heading is preserved
- **Momentum inheritance** — projectiles inherit the firing ship's `velocity` (Vector3) at spawn time
- Fighter vs destroyer feel emerges naturally from mass and moment of inertia — no special-casing needed

### Unified Ship Input Interface

All ships — player and AI alike — share the same low-level input contract:

```gdscript
# Set each frame by: player input, AIController, or NavigationController (Tactical mode)
var input_forward: float          # -1.0 to 1.0
var input_strafe: float           # -1.0 to 1.0
var input_aim_target: Vector3     # world-space XZ point to face toward (Y = 0)
var input_fire: Array[bool]       # [group1, group2, group3]
```

The physics system reads only from this interface — it never knows which mode is driving.

### NavigationController

`NavigationController.gd` translates a high-level destination into thrust inputs. It calculates when to thrust, when to brake, and what heading to face to arrive at a target within the ship's physical constraints.

Used by:
- AI ships navigating to patrol points and chasing targets (`AIController` → `NavigationController`)
- Player ship in Tactical mode when given a move order
- **Not used** in Pilot mode — player inputs go directly to the thrust interface

### Weapons

- All weapon stats in `weapon.json` — no recompile for balance passes
- **Damage type matrix:** ballistic beats hull, energy beats shields, missiles balanced
- **Heat** tracked per hardpoint — each hardpoint has its own capacity and cooling rate
- **Power** tracked per ship — shared pool; energy weapons compete with shield regen
- **Hardpoints are damageable** — own HP; degraded states: nominal → damaged → critical → destroyed
- **Missile guidance** is a JSON property: `track_cursor`, `auto_lock`, `click_lock`
- C# dumb pool for bullets and pulses; GDScript guided pool for missiles

### Content Architecture

All game content uses a **folder-per-item** structure under `/content/`. Each item lives
in its own folder with its JSON definition and assets co-located. Adding a new ship,
weapon, or module requires **only creating a new folder — no code changes.**

`ContentRegistry.gd` scans `/content/` at startup and indexes everything. It is
registered before any ship spawns.

Rule of thumb: equippable or interactable items → `/content/`. System config tables → `/data/`.

### Mouse-to-World

`get_global_mouse_position()` does not exist in 3D. Always use ray-plane intersection:

```gdscript
var plane := Plane(Vector3.UP, 0.0)
var ray_origin := camera.project_ray_origin(mouse_pos)
var ray_dir    := camera.project_ray_normal(mouse_pos)
var world_pos  := plane.intersects_ray(ray_origin, ray_dir)
```

---

## Build Order

Systems are sequenced by dependency. Build in this order.

| Step | System | Spec |
|---|---|---|
| 1 | PerformanceMonitor | `feature_spec-performance_monitor.md` |
| 2 | ServiceLocator + GameEventBus + GameBootstrap | Core Spec |
| 3 | ContentRegistry | `feature_spec-ship_system.md` |
| 4 | SpaceBody + Ship (physics only, no weapons) | `feature_spec-physics_and_movement.md` |
| 5 | NavigationController | `feature_spec-nav_controller.md` |
| 6 | ProjectileManager (C#, dumb pool) | `feature_spec-weapons_and_projectiles.md` |
| 7 | WeaponComponent + HardpointComponent | `feature_spec-weapons_and_projectiles.md` |
| 8 | GuidedProjectilePool | `feature_spec-weapons_and_projectiles.md` |
| 9 | ShipFactory + Ship visual assembly | `feature_spec-ship_system.md` |
| 10 | GameCamera — Pilot mode | `feature_spec-camera_system.md` |
| 11 | AIController + NavigationController integration | `feature_spec-ai_patrol_behavior.md` |
| 12 | Test scene: player vs AI, full Pilot mode loop | — |
| 13 | Tactical mode camera + input layer | `feature_spec-camera_system.md`, `feature_spec-fleet_command.md` |
| 14 | ChunkStreamer + Asteroid + Debris | `feature_spec-chunk_streamer.md` |
| — | Station & Loadout UI | Not yet specced |
| — | Galactic Strategy | Phase 3 — not yet specced |

---

## CLAUDE.md Template

Use this as the base for the project's `CLAUDE.md`. Update the Completed Systems section
as each system is implemented.

```markdown
# All Space — Agent Context

## Stack
Godot 4.6 · GDScript primary · C# for ProjectileManager only
Jolt physics · RigidBody3D with forces/torques for ships
Play plane: XZ (Y = 0) — no entity voluntarily leaves this plane

## Architecture
- ServiceLocator.gd — global service registry (autoload)
- GameEventBus.gd — all cross-system comms go through here; no direct cross-system refs
- PerformanceMonitor.gd — instrument every system; see feature_spec-performance_monitor.md
- NavigationController.gd — shared flight computer for AI and Tactical mode orders
- Ship.gd — unified input interface (input_forward, input_strafe, input_aim_target, input_fire)

## Hard Rules
- Never use 2D physics nodes — CharacterBody2D, Area2D, Camera2D, Node2D are banned
- Never use Vector2 for world-space positions or velocities (Vector2i OK for chunk coords)
- Enforce position.y = 0 and velocity.y = 0 after every physics update
- Never hardcode tunable values — they belong in /data/ or /content/<item>/ JSON files
- Cross-system calls go through GameEventBus only — no direct references between systems
- Always add PerformanceMonitor instrumentation per the spec
- One system per session — don't mix concerns
- Read the relevant feature spec before implementing anything

## Completed Systems
(Update this list as systems are implemented)
- [ ] PerformanceMonitor
- [ ] ServiceLocator + GameEventBus + GameBootstrap
- [ ] ContentRegistry
- [ ] SpaceBody + Ship (physics)
- [ ] NavigationController
- [ ] ProjectileManager (C#)
- [ ] WeaponComponent + HardpointComponent
- [ ] GuidedProjectilePool
- [ ] ShipFactory + Ship visual assembly
- [ ] GameCamera (Pilot mode)
- [ ] AIController
- [ ] Tactical mode camera + input
- [ ] ChunkStreamer + Asteroid + Debris

## Deviation Protocol
If a spec conflicts with engine behavior or another spec, STOP. Do not silently resolve
the conflict. Document it in docs/decisions_log.md and surface it for review before
proceeding.
```

---

## For More Detail

Read the relevant feature spec from `/docs/` for any system. The core spec
(`core_spec.md`) is the single source of truth — when any conflict arises between
memory, general knowledge, and spec files, the specs win.