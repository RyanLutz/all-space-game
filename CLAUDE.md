# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Godot 4.6, GDScript primary, C# for ProjectileManager only.
Jolt physics enabled for 3D debris — **ship physics use CharacterBody2D with manual velocity**.
2.5D: 3D assets rendered on a 2D gameplay plane, fixed top-down Camera2D. Movement is Vector2; ship heading is `rotation` (Z-axis in 2D).
Forward Plus renderer.

## Running the Project

Open in Godot 4.6 editor and press F5, or run:
```
godot --path "/home/lutz/Projects/All Space"
```

## Architecture

- `ServiceLocator.cs` — global service registry (autoloaded; registers GDScript services)
- `GameEventBus.gd` — all cross-system communication goes through here (autoloaded)
- `ContentRegistry.gd` — scans `/content/` on startup; indexes all ships, weapons, modules
- `PlayerState.gd` — tracks the currently piloted ship; emits `player_ship_changed`
- `PerformanceMonitor.gd` — instrument every system per spec; **implement this first**
- All system specs are in `/docs/` — read the relevant spec before implementing any system

**File layout:**
```
/core/services/
    ServiceLocator.cs
    PerformanceMonitor.gd
    ContentRegistry.gd
    PlayerState.gd
/core/
    GameEventBus.gd
    GameBootstrap.gd
/ui/debug/
    PerformanceOverlay.tscn
    PerformanceOverlay.gd
/gameplay/physics/
    SpaceBody.gd               # base class for ships, asteroids, debris
/gameplay/entities/
    Ship.gd
    Ship.tscn                  # single scene, configured from data at spawn time
    ShipFactory.gd
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

## System Summaries

### PerformanceMonitor (`docs/PerformanceMonitor_Spec.md`)
Rolling 60-frame average using `Time.get_ticks_usec()`. API: `begin(metric)` / `end(metric)` / `set_count(metric, value)`. Registers with Godot's built-in debugger via `Performance.add_custom_monitor()`. F3 toggles in-game overlay. Every other system wraps its hot paths with these calls using the canonical metric names defined in the spec.

### Physics & Movement (`docs/Physics_Movement_Spec.md`)
`SpaceBody.gd` extends `CharacterBody2D` with manual `Vector2` velocity. Physics loop order: apply thruster forces → partial alignment drag → linear drag (`velocity *= 1.0 - linear_drag * delta`) → angular drag → `move_and_slide()`. Single `thruster_force` stat shared across thrust/strafe/torque — torque deducted first ("turning wins"). Assisted steering uses stopping-distance calculation to prevent overshoot. Projectiles inherit firing ship's velocity. Rotation is a 2D `rotation` float.

### Weapons & Projectiles (`docs/Weapons_Projectiles_Spec.md`)
Five archetypes: ballistic, energy_beam (hitscan held), energy_pulse (hitscan burst), missile_dumb, missile_guided. All stats in per-weapon JSON under `/content/weapons/`. `ProjectileManager.cs` manages a pre-allocated `DumbProjectile` struct array; raycast collision per frame. Heat system is per-hardpoint; power is a per-ship shared pool. Damage pipeline: hit point → HitDetection region → shield absorption → hull damage with type multiplier from `data/damage_types.json` → hardpoint split → state threshold check.

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

## Rules

- Never hardcode values that belong in JSON
- Always add PerformanceMonitor instrumentation per spec using canonical metric names
- Cross-system calls go through GameEventBus, not direct references
- One system per Claude Code session
- C# is used **only** for `ProjectileManager.cs`; everything else is GDScript
- Ships are `CharacterBody2D` — do not use CharacterBody3D for ships
- Weapon and ship data lives in `/content/<type>/<id>/`; global config tables live in `/data/`

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
