# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Godot 4.6, GDScript primary, C# for ProjectileManager only.
Jolt physics enabled. CharacterBody2D with manual velocity for ships.
Forward Plus renderer. Project is in the specification phase — no source files exist yet.

## Running the Project

Open in Godot 4.6 editor and press F5, or run:
```
godot --path "/home/lutz/Projects/All Space"
```

## Architecture

- `ServiceLocator.cs` — global service registry (planned, not yet created)
- `GameEventBus.gd` — all cross-system communication goes through here (planned)
- `PerformanceMonitor.gd` — instrument every system per spec; **implement this first**
- All system specs are in `/docs/` — read the relevant spec before implementing any system

**Planned file layout:**
```
/core/services/PerformanceMonitor.gd
/ui/debug/PerformanceOverlay.tscn + .gd
/gameplay/physics/SpaceBody.gd         # base class for ships, asteroids, debris
/gameplay/entities/Ship.gd
/gameplay/entities/Asteroid.gd
/gameplay/entities/Debris.gd
/gameplay/weapons/ProjectileManager.cs  # C# only; pre-allocated struct pool
/gameplay/weapons/GuidedProjectilePool.gd
/gameplay/weapons/WeaponComponent.gd
/gameplay/weapons/HardpointComponent.gd
/data/weapons.json
/data/damage_types.json
```

## System Summaries

### PerformanceMonitor (`docs/PerformanceMonitor_Spec.md`)
Rolling 60-frame average using `Time.get_ticks_usec()`. API: `begin(metric)` / `end(metric)` / `set_count(metric, value)`. Registers with Godot's built-in debugger via `Performance.add_custom_monitor()`. F3 toggles in-game overlay. Every other system wraps its hot paths with these calls using the canonical metric names defined in the spec.

## PerformanceMonitor Metric Names (canonical — use exactly these)
Physics.move_and_slide · Physics.thruster_allocation · Physics.active_bodies
ProjectileManager.dumb_update · ProjectileManager.guided_update
ProjectileManager.collision_checks · ProjectileManager.active_count
AIController.state_updates · AIController.active_count
HitDetection.component_resolve
ChunkStreamer.load · ChunkStreamer.unload · ChunkStreamer.loaded_chunks

### Physics & Movement (`docs/Physics_Movement_Spec.md`)
`SpaceBody.gd` extends `CharacterBody2D` with manual velocity. Physics loop order: apply thruster forces → partial alignment drag → linear drag (`velocity *= 1.0 - linear_drag * delta`) → angular drag → `move_and_slide()`. Single `thruster_force` stat shared across thrust/strafe/torque — torque deducted first ("turning wins"). Assisted steering uses stopping-distance calculation to prevent overshoot. Projectiles inherit firing ship's velocity.

### Weapons & Projectiles (`docs/Weapons_Projectiles_Spec.md`)
Five archetypes: ballistic, continuous beam (hitscan), rapid pulse (hitscan), dumb rocket, guided missile. All stats in `weapons.json` — nothing hardcoded. `ProjectileManager.cs` manages a pre-allocated `DumbProjectile` struct array; raycast collision per frame. Heat system is per-hardpoint; power is a per-ship shared pool. Damage pipeline: hit point → HitDetection region → shield absorption → hull damage with type multiplier → hardpoint split → state threshold check.

## Rules

- Never hardcode values that belong in JSON
- Always add PerformanceMonitor instrumentation per spec using canonical metric names
- Cross-system calls go through GameEventBus, not direct references
- One system per Claude Code session
- C# is used **only** for `ProjectileManager.cs`; everything else is GDScript

## Build Order
1. PerformanceMonitor + overlay (must exist before anything else)
2. SpaceBody.gd + Ship.gd (physics only, no weapons)
3. ProjectileManager.cs (dumb pool only)
4. WeaponComponent.gd + HardpointComponent.gd + weapons.json
5. GuidedProjectilePool.gd
6. TestScene — placeholder AI targets, verify full loop