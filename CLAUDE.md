# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Godot 4.6, GDScript primary, C# for ProjectileManager only.
Jolt physics enabled. CharacterBody3D with manual velocity for ships.
2.5D: 3D assets and physics, fixed orthographic top-down camera. Movement locked to the XZ plane (Y = 0). Ship heading is rotation around the Y axis.
Forward Plus renderer.

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
`SpaceBody.gd` extends `CharacterBody3D` with manual velocity. Movement locked to XZ plane; Y velocity always 0. Physics loop order: apply thruster forces → partial alignment drag → linear drag (`velocity *= 1.0 - linear_drag * delta`) → angular drag → `move_and_slide()`. Single `thruster_force` stat shared across thrust/strafe/torque — torque deducted first ("turning wins"). Assisted steering uses stopping-distance calculation to prevent overshoot. Projectiles inherit firing ship's velocity. Rotation around Y axis only.

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

## Godot 4.6 + Jolt

---

**Jolt is 3D physics only**

This is the critical one for your architecture. Jolt functions as a drop-in replacement for Godot Physics by implementing the same 3D nodes like `RigidBody3D` and `CharacterBody3D`. It does **not** affect 2D physics nodes. `CharacterBody2D`, `RigidBody2D` — those still use Godot's built-in 2D physics engine regardless of Jolt being enabled.

**What this means for All Space:** your ship physics spec (`CharacterBody2D` with manual velocity) is unaffected by Jolt. Jolt only matters if you use `RigidBody3D` for 3D debris tumbling in the 2.5D setup.

---

**In 4.6, Jolt is now the default for new 3D projects** — no longer experimental, no longer opt-in. Existing projects keep their config unless changed manually. So a fresh 4.6 project already has Jolt active for any 3D nodes you add.

---

**The 2.5D question — pick your approach before Cursor touches SpaceBody**

Two valid paths in Godot for "3D assets, top-down 2D gameplay":

| Approach | Physics Node | Camera | Notes |
|---|---|---|---|
| **2D plane + 3D visuals** | `CharacterBody2D` | Camera2D | 3D mesh as child of 2D node. Physics stays 2D. Spec as written. |
| **3D scene + locked camera** | `CharacterBody3D` | Camera3D locked at Y | Full 3D, movement constrained to XZ plane. Jolt applies. More complex. |

**Recommendation: stick with `CharacterBody2D`.** It matches your spec exactly, Jolt doesn't complicate it, and 3D ship meshes render fine as children of 2D nodes. The "2.5D" is purely visual — the gameplay plane is still 2D.

---

**Other 4.6 gotchas worth telling Sonnet:**

- `move_and_slide()` no longer takes arguments — velocity is set via `velocity` property directly before calling it
- `angle_to()` and `angle_difference()` exist as built-ins — no need to hand-roll angle math
- `Time.get_ticks_usec()` is the right call for PerformanceMonitor timing (not `OS.get_ticks_usec()` — that's deprecated)
- `Performance.add_custom_monitor()` takes a `Callable` as second argument in 4.x — lambda syntax works fine
- C# in Godot 4.6 uses .NET 8 — no `Godot.Object`, use `GodotObject` instead

---

Ready to write the Cursor prompt for `SpaceBody.gd` and `Ship.gd`?