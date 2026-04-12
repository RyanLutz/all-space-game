# All Space — Core Specification
*Single Source of Truth: Philosophy, Architecture, and Cross-Cutting Contracts*

---

## 1. What This Game Is

All Space is a **top-down 3D space combat simulation** where players begin as a lone
pilot and grow into a fleet commander, infrastructure builder, and galactic power.
The game world is a fully 3D scene — ships, projectiles, and debris are all proper
3D physics objects — but gameplay is constrained to the **XZ plane (Y = 0)** and
observed from a top-down camera. There is no 2D physics layer. Everything
is 3D; the play surface is flat.

The game runs on a single continuous streaming map — no loading screens, no sector
transitions.

**Primary inspirations:** Star Valor (customization depth), X4: Foundations (strategic
scope), Escape Velocity (accessible immediacy).

---

## 2. Core Philosophy

> **"As complex or as simple as the player wants it to be."**

Every system has a shallow entry point and a deep ceiling. Complexity is never forced
— it is unlocked on demand. A player can fly a found ship as-is and have a complete
experience. Another player can strip that same ship to components, blueprint it, and
mass-produce a customized fleet. Both are valid at every stage.

This principle governs every design and architecture decision. When in doubt, ask:
*does this force complexity on a player who doesn't want it?*

---

## 3. The Three Modes of Play

All Space has three gameplay modes representing different scales of engagement. The
current focus is **Pilot and Tactical modes**. Galactic Strategy is a future phase.

| Mode | Scale | Input | Camera |
|---|---|---|---|
| **Pilot** | Single ship | Direct thrust + mouse aim | Close follow, cursor offset |
| **Tactical** | Fleet (RTS) | Drag select, right-click orders | Zoomed out overview |
| **Galactic** | Empire | Map interface, diplomacy | Full map (future) |

### Mode Transitions

- **Tab** toggles between Pilot and Tactical mode
- No transition between Pilot/Tactical and Galactic at MVP — Galactic is Phase 3
- Transitions must feel smooth — no jarring stops, no sudden behavior changes
- Audio, camera, and UI all respond to mode transitions

### Pilot Mode

The player directly controls their ship:

- **Mouse position** — determines the direction the ship faces. Assisted steering
  rotates the ship toward the aim point automatically.
- **W / S** — forward / reverse thrust along the ship's current facing direction
- **A / D** — lateral strafe thrust
- **Left click** — fire weapon group 1 (primary)
- **Right click** — fire weapon group 2 (secondary)
- **Tertiary key (TBD)** — fire weapon group 3

The ship's physics — mass, inertia, drag — determine what actually happens as a result
of thrust inputs. The player feels the momentum; they are not abstracted from it.

### Tactical Mode

The player commands their fleet using RTS conventions:

- Camera zooms out to a tactical overview
- **Drag select** — box-select multiple ships
- **Click** — select individual ship
- **Right-click on destination** — order selected ships to navigate there. The ship's
  flight computer calculates the thrust sequence needed to arrive, respecting mass,
  inertia, and drag.
- **Right-click on enemy** — order selected ships to attack
- **Right-click on asteroid** — order selected ships to mine
- Additional contextual orders based on target type

**The player's own ship is fully included in the commandable fleet.** It can be
selected, drag-selected, and given orders exactly like any other ship. When the player
gives their ship a move order in Tactical mode, the ship's flight computer drives it
there; the player does not manually thrust.

When the player switches back to Pilot mode, their ship returns to direct manual control.

### Unified Ship Input Interface

All ships — player ship and AI ships alike — share the same low-level input interface:

```gdscript
# These are set each frame by player input, tactical orders, or AI controller
var input_forward: float        # -1.0 to 1.0
var input_strafe: float         # -1.0 to 1.0
var input_aim_target: Vector3   # world-space point to face toward
var input_fire: Array[bool]     # one bool per weapon group [group1, group2, group3]
```

In Pilot mode, the player's keyboard and mouse populate these fields directly.
In Tactical mode or AI control, a NavigationController populates them.
The physics system reads only from this interface — it never knows which mode is active.

---

## 4. The Four Phases of Play

The full game spans four phases. Current implementation covers Phases 1 and 2 (the MVP).
All systems are designed for extensibility into later phases from day one.

| Phase | Trigger | What Changes |
|---|---|---|
| **1 — Personal Pilot** | Start of game | Single ship, Pilot mode, combat and exploration |
| **2 — Small Fleet Commander** | Acquiring a second ship | Tactical mode becomes meaningful; fleet orders |
| **3 — Infrastructure Builder** | Resource accumulation | Construction ships, shipyards, blueprints |
| **4 — Galactic Power** | Territory control | Faction diplomacy, logistics, multi-system operations |

At any phase, the player can return to direct personal ship control. The personal ship
never becomes obsolete.

---

## 5. Tech Stack

| Concern | Choice | Notes |
|---|---|---|
| Engine | Godot 4.6 | — |
| Primary language | GDScript | All game systems except where noted |
| Performance-critical | C# | ProjectileManager only at MVP |
| Physics backend | Jolt (Godot 4.6 default) | Full 3D physics; applies natively to all 3D nodes |
| Ship physics node | `RigidBody3D` | Force/torque applied each frame; Jolt integrates; Y-translation and X/Z-rotation axis-locked |
| Play plane | XZ (Y = 0) | All ships, projectiles, and gameplay at Y = 0 |
| Camera | `Camera3D`, orthographic | Top-down, fixed elevation above XZ plane |
| Data / modding | JSON | All tunable values; no recompile for balance passes |
| Inter-system comms | `GameEventBus.gd` | No direct cross-system references |
| Service registry | `ServiceLocator.gd` | Single access point for all singleton services |

---

## 6. The 3D Play Plane Contract

**This is the most important architectural constraint in the project.**
Every system must respect it. Violating it corrupts gameplay.

- All ship and entity **positions** live at **Y = 0** in world space. No entity
  voluntarily leaves this plane.
- All **velocities** are `Vector3` with `velocity.y = 0` at all times for ships
  and projectiles. Enforce this explicitly after every physics update.
- All **rotations** for ships use the **Y axis only (yaw)**. `rotation.x` and
  `rotation.z` are always 0. Angular velocity is a float applied to `rotation.y`.
- Ship **heading** (forward direction) is `-transform.basis.z` — Godot's default
  3D forward. Never use `Vector2.RIGHT.rotated(rotation)`.
- **Mouse-to-world** requires a ray from the camera intersected with the Y = 0 plane.
  `get_global_mouse_position()` does not exist in 3D. Use:
  ```gdscript
  var plane = Plane(Vector3.UP, 0.0)
  var ray_origin = camera.project_ray_origin(mouse_pos)
  var ray_dir = camera.project_ray_normal(mouse_pos)
  var world_pos = plane.intersects_ray(ray_origin, ray_dir)
  ```
- **Distance checks** use `Vector3.distance_to()` — since Y is always 0, this is
  equivalent to 2D distance.
- Detection and trigger volumes use `Area3D` with `SphereShape3D`.
- Collision uses `CollisionShape3D` with appropriate 3D shapes.

**Banned in this project — none of these nodes exist:**
`CharacterBody2D`, `RigidBody2D`, `Area2D`, `CollisionShape2D`, `Camera2D`, `Node2D`.
`Vector2` is banned for any world-space position or velocity value.

`Vector2i` is permitted for chunk grid coordinates (integer grid indices only).

---

## 7. Architecture Rules

These rules apply to every system, every agent session, and every implementation.
They are non-negotiable.

1. **No hardcoded values.** Anything tunable belongs in JSON under `/data/` or
   `/content/<item>/`. Stats, ranges, timings, damage values — all JSON.

2. **No direct cross-system references.** Systems communicate through `GameEventBus`.
   A system may hold a reference to its own components; it may not reach into another
   system's internals.

3. **PerformanceMonitor instrumentation is required.** Every system spec includes a
   Performance Instrumentation section. Every implementation follows it. See Section 10.

4. **One system per agent session.** Do not mix concerns in a single Cursor or Claude
   Code session. Context overload is the enemy of correctness.

5. **Specs are authoritative.** If a spec says to do something a particular way, do it
   that way. Flag conflicts rather than silently resolving them.

6. **C# only for ProjectileManager.** All other systems are GDScript.

7. **No 2D physics nodes.** See Section 6.

8. **Enforce Y = 0.** Any system that moves entities must ensure `position.y = 0`
   after every physics update. Add `position.y = 0` explicitly where necessary.

9. **One Ship.tscn for all ship types.** Configuration happens at spawn time from
   data. There is no FighterShip.tscn vs DestroyerShip.tscn.

---

## 8. Project Structure

```
/all_space/
    CLAUDE.md                          ← agent context file (always up to date)
    /docs/
        core_spec.md         ← this file
        feature_spec-performance_monitor.md
        feature_spec-physics_and_movement.md
        feature_spec-ship_system.md
        feature_spec-weapons_and_projectiles.md
        feature_spec-camera_system.md
        feature_spec-ai_patrol_behavior.md
        feature_spec-chunk_streamer.md
        feature_spec-fleet_command.md
        feature_spec-game_event_bus_signals.md
    /core/
        /services/
            ServiceLocator.gd
            PerformanceMonitor.gd
        GameEventBus.gd
        GameBootstrap.gd
    /gameplay/
        /physics/
            SpaceBody.gd               ← shared physics properties and interface
        /entities/
            Ship.gd
            Ship.tscn                  ← one scene for all ship types
            ShipFactory.gd
            Asteroid.gd
            Debris.gd
        /ai/
            AIController.gd
            AIController.tscn
            NavigationController.gd    ← flight computer: orders → thrust inputs
        /weapons/
            ProjectileManager.cs       ← C# only
            GuidedProjectilePool.gd
            WeaponComponent.gd
            HardpointComponent.gd
        /camera/
            GameCamera.gd
            GameCamera.tscn
        /parts/                        ← ship part sub-scenes
    /content/
        /ships/                        ← one folder per ship
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

## 9. Entity Overview

All moving entities in the world follow a common physics interface defined in
`SpaceBody.gd`. This is a logical interface, not a Godot base node class. Both ships
and asteroids use `RigidBody3D`; ships have axis locks enforcing the XZ plane while
asteroids tumble freely. Both implement the same property and method contract.

### SpaceBody Contract

Every entity that participates in the physics world exposes:

| Property | Type | Description |
|---|---|---|
| `mass` | float | Affects inertia and response to forces |
| `velocity` | Vector3 | Current linear velocity; Y is always 0 |
| `angular_velocity` | float | Current yaw rate (radians/sec); Y axis only |
| `max_speed` | float | Soft speed cap |
| `linear_drag` | float | Drag coefficient per frame |

And the methods:

```gdscript
func apply_damage(amount: float, damage_type: String,
                  hit_pos: Vector3, component_ratio: float) -> void

func apply_impulse(impulse: Vector3) -> void  # explosions, collisions
```

### Entity Types

```
RigidBody3D (axis-locked to XZ plane)
    └── Ship.gd             Player and AI ships. Forces/torques applied in
                            _integrate_forces(); Jolt integrates. Thruster budget,
                            assisted steering, hardpoints, weapon fire groups,
                            module slots. Controlled via unified input interface.

RigidBody3D (free tumble)
    └── Asteroid.gd         World objects. Jolt handles collision response and tumbling.
                            Has HP, size tier, loot table. Spawned and freed by
                            ChunkStreamer. Can be mined or destroyed.

Node3D
    └── Debris.gd           Lightweight fragments. Short lifetime, inherits velocity
                            at spawn, no further physics. Visual only — no collision.

# Managed separately (not scene nodes in the usual sense):
ProjectileManager.cs        Pooled dumb projectiles (ballistic, pulse).
                            Vector3 position/velocity, Y = 0 enforced.
GuidedProjectilePool.gd     GDScript-managed missiles.

# Camera (sibling of game world — never a child of any ship):
GameCamera (Camera3D)       Orthographic projection. Follows target with
                            cursor-offset in Pilot mode. Zooms out in Tactical mode.
```

---

## 10. PerformanceMonitor Contract

`PerformanceMonitor` is registered before any other system via `GameBootstrap.gd`.
It is built first, always. See `PerformanceMonitor_Spec.md` for the full API.

**Every system spec must include a "Performance Instrumentation" section.**
**Every implementation must follow it.**

### Canonical Metric Names

Use exactly these strings. New systems must add their metric names here before
implementation begins.

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

### Usage Pattern

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

## 11. Content Architecture

All game content (ships, weapons, modules) uses a **folder-per-item** structure.
Each item lives in its own folder with its JSON definition and assets co-located.
The folder name is the item's content ID.

```
/content/
    /ships/
        /fighter_light/
            ship.json
            model.glb
            icon.png
    /weapons/
        /autocannon_light/
            weapon.json
            model.glb
            icon.png
    /modules/
        /shield_standard/
            module.json
            icon.png
```

**Adding a new ship, weapon, or module requires only creating a new folder.
No code changes.**

`ContentRegistry.gd` scans `/content/` at startup and indexes everything.
It is registered before any ship spawns.

**Rule of thumb:** If it is something the player can see, equip, or interact with
→ `/content/`. If it is a system configuration table → `/data/`.

---

## 12. Ship System Summary

Full detail in `Ship_System_Spec.md`. Key decisions recorded here for cross-spec reference.

### One Ship.tscn

No `FighterShip.tscn` vs `DestroyerShip.tscn`. Every ship type uses the same
`Ship.tscn`, configured at spawn time by `ShipFactory.gd` reading from `ContentRegistry`.

### Ship Definition vs Loadout

**Definition** — what the ship *is*: hull stats, hardpoint positions, module slot layout.
Lives in `ship.json`.

**Loadout** — what is currently installed: which weapons in which hardpoints, which modules
in which slots. Stored as runtime state and in save data. `ship.json` contains a
`default_loadout` used when no override is provided.

### Weapon Fire Groups

Weapons are assigned to fire groups. The player fires an entire group simultaneously:

| Group | Default Input |
|---|---|
| 1 — Primary | Left click |
| 2 — Secondary | Right click |
| 3 — Tertiary | TBD (middle mouse or dedicated key) |

Hardpoints are assigned to groups via a **many-to-many** mapping — a single hardpoint
can belong to multiple groups simultaneously. A hardpoint fires whenever any of its
assigned groups is activated. Group assignments are configured at the station loadout
screen and stored in the ship's loadout data.

### Hardpoint Types

| Type | Fire Arc | Notes |
|---|---|---|
| Fixed | ~5° | Ship must aim. No rotation. |
| Gimbal | ~25° | Slight auto-rotation to compensate for heading lag. |
| Partial Turret | ~120° | Cannot fire directly behind. |
| Full Turret | 360° | Any direction. Heaviest, slowest traverse. |

### Modular Parts

Ships are assembled from interchangeable 3D mesh sub-scenes: hull, engine pod,
wing/strut, cockpit. All parts of one ship share a single material instance.
Vertex color channels drive a colorization shader (primary, trim, accent, glow).

---

## 13. Physics Summary

Full detail in `Physics_Movement_Spec.md`. Key decisions recorded here.

- `RigidBody3D` with Jolt; forces/torques applied in `_integrate_forces()`; Jolt integrates — ships do not use `CharacterBody3D`
- Y-translation and X/Z-rotation axis-locked in Jolt; Y enforced explicitly as a backstop after every physics update
- **Assisted steering** — auto counter-torque prevents rotation overshoot. Ships track
  the aim point smoothly without oscillation.
- **Shared thruster budget** — turning takes priority; translation gets the remainder
- **Partial alignment drag** — only lateral velocity bleeds during hard turns; axial
  velocity along the heading is preserved
- **Momentum inheritance** — projectiles inherit the firing ship's `velocity` (Vector3)
  at spawn time

### NavigationController

`NavigationController.gd` sits between high-level destinations and the ship's raw
thrust interface. It calculates when to thrust, when to brake, and what heading to
face in order to arrive at a target position within the ship's physical constraints.

Used by:
- AI ships navigating to patrol points and chasing targets
- Player ship in **Tactical mode** when given a move order
- **Not used** in Pilot mode — player inputs go directly to the thrust interface

---

## 14. Weapons Summary

Full detail in `Weapons_Projectiles_Spec.md`. Key decisions recorded here.

- All weapon stats in `weapon.json` — no recompile for balance passes
- **Damage type matrix:** ballistic beats hull, energy beats shields, missiles balanced
- **Heat** tracked per hardpoint — each hardpoint has its own capacity and cooling rate
- **Power** tracked per ship — shared pool; energy weapons compete with shield regen
- **Hardpoints are damageable** — own HP, degraded states: nominal → damaged → critical → destroyed
- **Missile guidance** is a JSON property: `track_cursor`, `auto_lock`, `click_lock`
- C# dumb pool for bullets and pulses; GDScript guided pool for missiles

---

## 15. AI Summary

Full detail in `AI_Patrol_Behavior_Spec.md`. Key decisions recorded here.

- State machine: IDLE (wander) → PURSUE → ENGAGE → (future: FLEE, REGROUP, SEARCH)
- JSON behavior profiles — MVP uses one "default" profile; architecture supports N profiles
- AI ships use the same `RigidBody3D` physics as the player — no cheating on thrust
  or turning
- AI routes all movement through `NavigationController` — the same flight computer used
  by Tactical mode orders
- Detection via `Area3D` / `SphereShape3D`; leash range limits pursuit from spawn point
- Aim prediction via linear lead; `aim_accuracy` float is the primary difficulty knob

---

## 16. Camera Summary

Full detail in `Camera_System_Spec.md`. Key decisions recorded here.

- `Camera3D`, orthographic projection, fixed Y elevation above the XZ plane
- Camera is **never** a child of a ship — it is a sibling of the game world
- Retargeting is a single function call: `follow(target: Node3D)`
- **Pilot mode:** cursor-offset follow with critically damped spring smoothing
- **Tactical mode:** zooms out to overview; cursor-offset disabled
- Zoom is controlled via `camera.size` (orthographic world-space height), not a scale
- Mouse-to-world always uses ray-plane intersection against Y = 0 (see Section 6)

---

## 17. World Streaming Summary

Full detail in `ChunkStreamer_Spec.md`. Key decisions recorded here.

- Square chunk grid; player's local neighborhood loaded, distant chunks freed
- Chunks are generated **deterministically** — same chunk coordinate = same content on
  every visit
- `chunk_loaded` / `chunk_unloaded` events on `GameEventBus` — AI spawner and other
  systems react to these signals; ChunkStreamer does not call them directly
- Asteroids (`RigidBody3D`) are placed per-chunk at load time and freed with the chunk
- Debris is visual-only — no collision, short lifetime, freed by timer

---

## 18. Spec Format

When writing a new feature spec, include these sections in this order as necessary:

1. **Overview** — what the system does, design goals
2. **Architecture** — how it fits in the project; diagram if helpful
3. **Core properties / data model** — key structs, classes, properties
4. **Key algorithms** — with GDScript pseudocode where helpful
5. **JSON data format** — if the system owns any data files
6. **Performance Instrumentation** — required; follows the contract in Section 10
7. **Files** — exact paths for every file this system creates or modifies
8. **Dependencies** — what must exist before this system can be built
9. **Assumptions** — explicit list of values and decisions deferred to balancing
10. **Success Criteria** — checkbox list, concrete and testable

---

## 19. Build Order

Systems are sequenced by dependency. Build in this order.

| Step | System | Spec |
|---|---|---|
| 1 | PerformanceMonitor | `PerformanceMonitor_Spec.md` |
| 2 | ServiceLocator + GameEventBus + GameBootstrap | Core Spec / CLAUDE.md |
| 3 | ContentRegistry | `Ship_System_Spec.md` |
| 4 | SpaceBody + Ship (physics only, no weapons) | `Physics_Movement_Spec.md` |
| 5 | NavigationController | `Physics_Movement_Spec.md` |
| 6 | ProjectileManager (C#, dumb pool) | `Weapons_Projectiles_Spec.md` |
| 7 | WeaponComponent + HardpointComponent | `Weapons_Projectiles_Spec.md` |
| 8 | GuidedProjectilePool | `Weapons_Projectiles_Spec.md` |
| 9 | ShipFactory + Ship visual assembly | `Ship_System_Spec.md` |
| 10 | GameCamera — Pilot mode | `Camera_System_Spec.md` |
| 11 | AIController + NavigationController integration | `AI_Patrol_Behavior_Spec.md` |
| 12 | Test scene: player vs AI, full Pilot mode loop | — |
| 13 | Tactical mode camera + input layer | `Camera_System_Spec.md`, `Fleet_Command_Spec.md` |
| 14 | ChunkStreamer + Asteroid + Debris | `ChunkStreamer_Spec.md` |
| — | Station & Loadout UI | Not yet specced |
| — | Galactic Strategy | Phase 3 — not yet specced |

---

## 20. Feature Spec Status

| Spec | File | Status |
|---|---|---|
| PerformanceMonitor | `PerformanceMonitor_Spec.md` | ⚠️ Minor 3D audit needed |
| Physics & Movement | `Physics_Movement_Spec.md` | 🔄 Needs full 3D rewrite |
| Ship System | `Ship_System_Spec.md` | 🔄 Needs 3D migration + fire groups |
| Weapons & Projectiles | `Weapons_Projectiles_Spec.md` | 🔄 Needs 3D migration |
| Camera System | `Camera_System_Spec.md` | 🔄 Needs full 3D rewrite (Camera3D, orthographic) |
| AI & Patrol Behavior | `AI_Patrol_Behavior_Spec.md` | 🔄 Needs 3D migration + nav controller |
| Chunk Streaming | `ChunkStreamer_Spec.md` | 🔄 Needs 3D migration |
| Fleet Command & Control | `Fleet_Command_Spec.md` | 🔄 Needs Tactical mode refinement |
| GameEventBus Signals | `GameEventBus_Signals.md` | 🔄 Vector3 migration |
| Station & Loadout UI | — | 🔲 Not started |

---

## 21. What the MVP Establishes

The MVP is a tight, testable loop: **fly → fight → dock → customize → repeat.**

- **Sim-lite physics:** Ships have mass, momentum, and angular inertia. Turning takes
  time. Hard turns bleed lateral velocity. Projectiles inherit shooter momentum.
- **Two gameplay modes:** Pilot (direct control) and Tactical (fleet RTS orders).
  Both available from game start. Switch with Tab.
- **Weapons with tactical texture:** Three archetypes (ballistic, energy, missile) with
  distinct feel and purpose. Heat and power create tradeoffs under sustained fire.
- **Ship customization:** Modular weapon and system slots with fire group assignment.
  Real tradeoffs between speed, armor, and firepower.
- **Streaming map:** Chunk-based, seamless, no sector transitions.
- **Observability from day one:** PerformanceMonitor instruments every system.
  In-game F3 overlay. No retrofitting later.

Nothing in the MVP is throwaway. Every system is specced for modularity and future
expansion from the start.

---

## 22. What the MVP Is Not

- Not a game where the personal ship becomes obsolete at any phase.
- Not a game with forced complexity. Depth is always opt-in.
- Not balanced in the spec. All stat values are placeholders until playtesting.
- Not 2.5D. There is no 2D physics layer. The game is fully 3D on a flat XZ plane.
- Not a game with loading screens or sector transitions.
