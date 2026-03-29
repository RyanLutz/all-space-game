# All Space MVP — Agent Context

## IMPORTANT: Read Before Every Session
- Read the relevant spec in `/docs/` before implementing anything — specs are authoritative
- One system per session — don't mix concerns
- Review the Build Order below and implement in sequence

## Stack
Godot 4.6 · GDScript primary · C# for ProjectileManager only
2.5D rendering: 3D ship models rendered over 2D gameplay plane
Physics: `CharacterBody2D` with manual velocity — all gameplay is 2D
Jolt physics available for 3D visual debris only — does NOT apply to `CharacterBody2D`
Forward Plus renderer

## Running the Project

Open in Godot 4.6 editor and press F5, or run:
```
godot --path "/home/lutz/Projects/All Space"
```

## Architecture

Core services (autoloaded or registered via ServiceLocator):
- `ServiceLocator.cs` — global service registry (autoloaded; registers GDScript services)
- `GameEventBus.gd` — all cross-system communication goes through here (autoloaded)
- `PerformanceMonitor.gd` — instrument every system per spec; **implement this first**
- `ContentRegistry.gd` — scans `/content/` on startup; indexes all ships, weapons, modules
- `PlayerState.gd` — tracks the currently piloted ship; emits `player_ship_changed`
- `GameBootstrap.gd` — autoload setup, service registration (autoloaded from project root)

All system specs are in `/docs/` — read the relevant spec before implementing any system.

**File layout:**
```
/core/services/
    ServiceLocator.cs
    PerformanceMonitor.gd
    ContentRegistry.gd
    PlayerState.gd
/core/
    GameEventBus.gd
GameBootstrap.gd                   # at project root (see project.godot autoload)
/ui/debug/
    PerformanceOverlay.tscn
    PerformanceOverlay.gd
/gameplay/physics/
    SpaceBody.gd               # base class for ships, asteroids, debris
/gameplay/entities/
    Ship.gd
    Ship.tscn                  # single scene, configured from data at spawn time
    ShipFactory.gd             # only way to create ships — spawns from content data
    Asteroid.gd
    Debris.gd
/gameplay/weapons/
    ProjectileManager.cs       # C# only; pre-allocated struct pool
    GuidedProjectilePool.gd
    WeaponComponent.gd
    HardpointComponent.gd
/gameplay/camera/
    GameCamera.gd
    GameCamera.tscn
/gameplay/ai/
    AIController.gd
    AIController.tscn
/content/
    /ships/<id>/ship.json + model.glb + icon.png
    /weapons/<id>/weapon.json + model.glb + icon.png
    /modules/<id>/module.json + icon.png
/data/
    damage_types.json          # global config — stays here
    ai_profiles.json           # global config — stays here
```

## Specs (in /docs/)

| Spec File | Covers |
|---|---|
| `PerformanceMonitor_Spec.md` | Observability service, canonical metric names, F3 overlay |
| `Physics_Movement_Spec.md` | SpaceBody, Ship movement, thruster budget, assisted steering |
| `Weapons_Projectiles_Spec.md` | Archetypes, hardpoints, heat/power, damage pipeline |
| `Camera_System_Spec.md` | Independent Camera2D, spring smoothing, cursor offset |
| `AI_Patrol_Behavior_Spec.md` | State machine, aim prediction, behavior profiles |
| `Ship_Content_Data_Architecture_Spec.md` | Folder-per-item, ContentRegistry, ShipFactory |

## Rules

### Always
- Never hardcode values that belong in JSON
- Always add PerformanceMonitor instrumentation per spec using canonical metric names
- Cross-system calls go through GameEventBus, not direct references
- One system per Claude Code session
- C# is used **only** for `ProjectileManager.cs`; everything else is GDScript
- Ships are `CharacterBody2D` — do not use CharacterBody3D for ships
- Read the spec fully before implementing — it contains the algorithm, not just the shape

### Content & Data
- `/content/` — ships, weapons, modules (player-visible, equippable items)
- `/data/` — global config tables (`damage_types.json`, `ai_profiles.json`)
- The folder name IS the item ID — no separate ID field needed in JSON
- `ShipFactory.spawn_ship(id, pos)` is the only way to create ships — never instantiate Ship.tscn directly
- `default_loadout` in `ship.json` maps slot/hardpoint IDs to content IDs (folder names)

### Ships & Camera
- One `Ship.tscn` configured from data at spawn time — no per-ship-class scenes
- Camera (`GameCamera`) is a sibling of the game world — **never** a child of any ship node
- Camera must survive player ship destruction — check `is_instance_valid(_follow_target)` each frame
- Retargeting the camera is a single `follow(target)` call

### AI
- `AIController.gd` produces physics inputs (thrust, strafe, target heading) — no physics cheating
- AI ships obey the same thruster budget, angular inertia, and drag as the player
- Behavior values in `data/ai_profiles.json`
- AI state transitions are broadcast via `GameEventBus` signals

## System Summaries

### PerformanceMonitor (`docs/PerformanceMonitor_Spec.md`)
Rolling 60-frame average using `Time.get_ticks_usec()`. API: `begin(metric)` / `end(metric)` / `set_count(metric, value)`. Registers with Godot's built-in debugger via `Performance.add_custom_monitor()`. F3 toggles in-game overlay. Every other system wraps its hot paths with these calls using the canonical metric names defined in the spec.

### Physics & Movement (`docs/Physics_Movement_Spec.md`)
`SpaceBody.gd` extends `CharacterBody2D` with manual `Vector2` velocity. Physics loop order: apply thruster forces → partial alignment drag → linear drag (`velocity *= 1.0 - linear_drag * delta`) → angular drag → `move_and_slide()`. Single `thruster_force` stat shared across thrust/strafe/torque — torque deducted first ("turning wins"). Assisted steering uses stopping-distance calculation to prevent overshoot. Projectiles inherit firing ship's velocity. Rotation is a 2D `rotation` float.

### Weapons & Projectiles (`docs/Weapons_Projectiles_Spec.md`)
Five archetypes: `ballistic`, `energy_beam` (hitscan held), `energy_pulse` (hitscan burst), `missile_dumb`, `missile_guided`. All stats in per-weapon JSON under `/content/weapons/`. `ProjectileManager.cs` manages a pre-allocated `DumbProjectile` struct array; raycast collision per frame. Heat system is per-hardpoint; power is a per-ship shared pool. Damage pipeline: hit point → HitDetection region → shield absorption → hull damage with type multiplier from `data/damage_types.json` → hardpoint split → state threshold check.

### Camera System (`docs/Camera_System_Spec.md`)
`Camera2D` — sibling of the game world, never a child of any ship. Follows target with cursor-direction offset and critically damped spring smoothing. Zoom via scroll wheel. Retargeting is a single `follow(target)` call. All code uses `Vector2` / `Node2D`.

### Ship & Content Data Architecture (`docs/Ship_Content_Data_Architecture_Spec.md`)
Folder-per-item under `/content/`. Each ship/weapon/module is a folder with a JSON definition + assets. `ContentRegistry.gd` scans on startup. One `Ship.tscn` configured at spawn time from data — no per-ship-class scenes. `ShipFactory.spawn_ship(id, pos)` is the only way to create ships. `PlayerState.gd` tracks the active player ship.

### AI & Patrol Behavior (`docs/AI_Patrol_Behavior_Spec.md`)
State machine: IDLE (wander) → PURSUE → ENGAGE → IDLE. `AIController.gd` attached only to AI ships. Produces physics inputs (thrust, strafe, target heading) fed into the same `Ship.gd` pipeline as the player — no physics cheating. Behavior values in `data/ai_profiles.json`. Aim prediction for lead targeting.

## PerformanceMonitor Metric Names (canonical — use exactly these)
```
Physics.move_and_slide · Physics.thruster_allocation · Physics.active_bodies
ProjectileManager.dumb_update · ProjectileManager.guided_update
ProjectileManager.collision_checks · ProjectileManager.active_count
AIController.state_updates · AIController.active_count
HitDetection.component_resolve
ChunkStreamer.load · ChunkStreamer.unload · ChunkStreamer.loaded_chunks
ContentRegistry.load
```

## Build Order
1. PerformanceMonitor + overlay (must exist before anything else)
2. GameEventBus — define initial signal set
3. GameBootstrap — autoload setup, service registration
4. SpaceBody.gd + Ship.gd (physics only, no weapons)
5. Camera system (GameCamera.gd)
6. ContentRegistry.gd + PlayerState.gd
7. ProjectileManager.cs (dumb pool only)
8. WeaponComponent.gd + HardpointComponent.gd + content/weapons/ JSON
9. GuidedProjectilePool.gd
10. AIController.gd
11. TestScene — placeholder AI targets, verify full loop

## Godot 4.6 Notes

- `move_and_slide()` takes no arguments — set `velocity` before calling it
- `angle_difference()` is a built-in — no need to hand-roll angle math
- `Time.get_ticks_usec()` is correct for PerformanceMonitor (not `OS.get_ticks_usec()` — deprecated)
- `Performance.add_custom_monitor()` takes a `Callable` as second argument — lambda syntax works fine
- C# in Godot 4.6 uses .NET 8 — use `GodotObject`, not `Godot.Object`
- Jolt is 3D-only — ship physics (`CharacterBody2D`) are unaffected by Jolt

## Key Design Decisions

| Decision | What It Is |
|---|---|
| 2.5D | All physics/gameplay is 2D (`CharacterBody2D`, `Vector2`); 3D assets are a rendering concern only |
| Thruster budget | Single `thruster_force` shared between thrust, strafe, and torque — turning wins |
| Partial alignment drag | Only lateral velocity bleeds on hard turns, not forward momentum |
| Projectile inheritance | All projectiles inherit the firing ship's velocity at spawn |
| Content architecture | Folder-per-item; folder name is the ID; no per-class scenes for ships |
| Single Ship.tscn | All ships use one scene configured from JSON data at spawn time |
| Camera independence | Camera never parented to a ship — decoupled for retargeting and survival |
| AI physics parity | AI uses same physics inputs as player; no velocity or turn-rate cheating |
| Heat per-hardpoint | Heat tracked per hardpoint; each gun manages its own overheat independently |
| Power per-ship | Power is a shared ship pool; energy weapons and shield regen compete for it |
