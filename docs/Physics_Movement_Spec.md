# Physics & Movement System Specification
*All Space Combat MVP — Ship and Entity Physics*

## Overview

A sim-lite physics system built on manual velocity control via `CharacterBody3D`. All physical entities share a common `SpaceBody` base. The system prioritizes tactile, momentum-based feel over strict Newtonian accuracy — ships have weight and inertia, but the universe applies gentle drag to prevent infinite drift.

**2.5D convention:** Assets and physics are fully 3D. The camera is a fixed orthographic camera looking straight down the Y axis and never moves off it. All gameplay movement is locked to the **XZ plane** — the Y component of `velocity` is always `0.0`. Ship heading is rotation around the **Y axis** only (no pitch or roll). This gives the feel of a 2D top-down game with the visual quality of 3D assets.

**Core Feel:**
- Ships feel heavy and purposeful, not floaty
- Turning is limited by angular inertia — hard course corrections take time
- High-speed turns bleed off lateral velocity naturally
- Projectiles inherit shooter momentum at the moment of firing

---

## Entity Hierarchy

```
CharacterBody3D
    └── SpaceBody.gd                  (base: mass, velocity, angular velocity, thrust)
            ├── Ship.gd               (modules, thruster budget, assisted steering)
            ├── Asteroid.gd           (static or slow-drifting, health, loot)
            └── Debris.gd             (short lifetime, spin, no thrust)

Node (C#)
    └── ProjectileManager.cs          (pooled, not a SpaceBody — see Projectile spec)
```

Projectiles are explicitly NOT `SpaceBody` instances. They inherit momentum from their firing ship at spawn time and are managed entirely by `ProjectileManager`.

---

## SpaceBody Base Class

### Properties

| Property | Type | Export | Description |
|---|---|---|---|
| `mass` | float | yes | kg equivalent — affects inertia and thrust response |
| `moment_of_inertia` | float | no | Derived in `_ready()`: `mass * 20.0 * 0.5`. Not tuned directly. |
| `velocity` | Vector2 | no | Current linear velocity (units/sec). Inherited from CharacterBody2D. |
| `angular_velocity` | float | no | Current rotation speed (radians/sec). Managed manually — not from the physics engine. |
| `max_speed` | float | yes | Hard velocity cap. Set equal to `v_terminal` so drag and thrust are balanced. |
| `linear_drag` | float | yes | Omnidirectional drag coefficient. Controls terminal velocity and stop time. |
| `alignment_drag` | float | yes | Lateral-only drag coefficient. Bleeds the velocity component perpendicular to the ship's heading. Set low (≤ 0.5) to preserve Newtonian drift; higher values couple velocity to heading direction. |

### Core Update Loop

Called in `_physics_process(delta)`:

1. Apply thruster forces → modify `velocity` and `angular_velocity`
2. Apply partial alignment drag (see below)
3. Apply base linear drag
4. Apply angular drag
5. Call `move_and_slide()`

### Linear Drag

Simple drag applied every frame to prevent infinite drift:

```gdscript
velocity *= (1.0 - linear_drag * delta)
```

`linear_drag` is a small value (e.g. 0.5–1.5) tuned per ship class. Space is not a vacuum in this universe — close enough for sim-lite.

### Partial Alignment Drag

Applied when the ship's velocity direction is misaligned with its heading. Only the **lateral component** (perpendicular to heading on the XZ plane) bleeds off — the **axial component** (along heading) is unaffected.

```gdscript
func apply_alignment_drag(delta: float) -> void:
    # Heading is a unit vector on the XZ plane derived from Y-axis rotation
    var heading = Vector3(sin(rotation.y), 0.0, cos(rotation.y))
    var axial = heading * velocity.dot(heading)        # component along heading
    var lateral = velocity - axial                     # component perpendicular (XZ only)

    # Only bleed lateral — axial momentum is preserved
    lateral *= (1.0 - alignment_drag * delta)
    velocity = axial + lateral
    velocity.y = 0.0  # enforce XZ-plane constraint
```

`alignment_drag` is tuned higher than `linear_drag` — lateral drift bleeds noticeably during hard turns, but not instantly.

**Tuning targets:**
- Gentle turn (< 30°): barely perceptible bleed
- Hard turn (90°+): noticeable speed loss, recoverable with thrust
- U-turn (180°): significant speed scrub, requires re-acceleration

---

## Ship Movement

### Ship Properties

| Property | Type | Export | Description |
|---|---|---|---|
| `thruster_force` | float | yes | Total thrust budget per frame (N equivalent). Shared between turning and linear movement. |
| `torque_thrust_ratio` | float | yes | Fraction of thruster budget that turning draws per rad/s² demanded. Heavier ships pay more for the same angular acceleration. |
| `max_angular_accel` | float | yes | Maximum angular acceleration in rad/s². Determines how quickly the ship can rotate. |
| `is_player_controlled` | bool | yes | When true, reads WASD + mouse input. When false, expects AI to set `target_angle` externally (not yet implemented). |

### Thruster Budget

Each ship has a single `thruster_force` stat representing total available thrust per frame. This budget is shared between:

- **Main thrust** (forward/reverse)
- **Strafe thrust** (lateral)
- **Torque** (turning)

**Automatic priority — turning wins:**

```gdscript
func allocate_thrust(forward_input: float, strafe_input: float, torque_demand: float) -> void:
    var torque_cost = abs(torque_demand) * torque_thrust_ratio
    var remaining = max(0.0, thruster_force - torque_cost)

    # Build movement vector on XZ plane relative to ship heading
    var heading  = Vector3(sin(rotation.y), 0.0,  cos(rotation.y))
    var right    = Vector3(cos(rotation.y), 0.0, -sin(rotation.y))
    var movement_input = heading * forward_input + right * strafe_input
    if movement_input.length() > 1.0:
        movement_input = movement_input.normalized()

    var movement_force = movement_input * remaining
    apply_force(movement_force, torque_demand)
```

`torque_thrust_ratio` defines how expensive turning is relative to linear thrust — heavier ships pay more for the same angular acceleration.

**Effect in play:**
- Corkscrewing around an enemy while strafing turns slower than flying straight
- No explicit UI — tradeoffs emerge naturally from physics
- Players learn to feel the budget limit, not read it

### Input → Force Pipeline

```
Mouse Position (screen)
    → Unproject ray onto Y=0 plane → world XZ position
        → Target Heading Angle (atan2 on XZ delta)
            → Heading Error (signed angle from rotation.y to target)
                → Torque Demand
                    → Thruster Budget Allocation
                        → angular_velocity delta
                            → rotation.y update
```

---

## Assisted Steering

Prevents overshoot by automatically applying counter-torque when the ship is about to pass its target heading. No player input required — assume best-in-class navigation computer for MVP.

### Algorithm

Each frame:

1. Calculate `heading_error` — signed angle from current rotation to target heading
2. Calculate `stopping_distance` — how far the ship will rotate before `angular_velocity` reaches zero at max counter-torque
3. If `stopping_distance >= abs(heading_error)`: apply full counter-torque (brake)
4. Otherwise: apply full torque toward target (accelerate)

```gdscript
func update_assisted_steering(target_angle: float, delta: float) -> float:
    var heading_error = angle_difference(rotation.y, target_angle)
    var stopping_distance = (angular_velocity * angular_velocity) / (2.0 * max_angular_accel)

    var torque_direction: float
    if stopping_distance >= abs(heading_error):
        torque_direction = -sign(angular_velocity)   # brake
    else:
        torque_direction = sign(heading_error)        # accelerate toward target

    return torque_direction * max_angular_accel * delta
```

**Result:** Ships rotate confidently toward the cursor, decelerate precisely, and land on target without oscillation. Heavier ships with less `max_angular_accel` simply take longer — the lag is physical, not artificial.

---

## Angular Inertia by Ship Class

`max_angular_accel` is derived from `thruster_force`, `mass`, and `moment_of_inertia`. Tuning targets:

| Ship Class | Feel |
|---|---|
| Fighter | Snappy — cursor tracking feels nearly immediate |
| Corvette | Responsive — small lag noticeable at high turn rates |
| Frigate | Deliberate — heading changes require planning |
| Destroyer+ | Sluggish — commit to your heading, course corrections are costly |

These are tuning targets, not hard values. Exact numbers determined during implementation.

---

## Momentum Inheritance (Projectiles)

When a projectile is fired, it receives the firing ship's current velocity added to its own muzzle velocity:

```gdscript
# Called by Ship.gd when firing — passes to ProjectileManager
# velocity is Vector3; aim_direction is a normalised Vector3 on XZ plane
var inherited_velocity = self.velocity
ProjectileManager.spawn(muzzle_position, aim_direction, muzzle_speed, inherited_velocity, weapon_data)
```

Inside `ProjectileManager.cs`:
```csharp
// All vectors are Vector3; Y component remains 0 throughout projectile lifetime
projectile.velocity = aimDirection * muzzleSpeed + inheritedVelocity;
```

**Effect in play:**
- Firing forward while flying fast: projectiles travel faster relative to a stationary observer
- Firing laterally while strafing: bullets angle slightly in the direction of travel
- Firing backward: projectiles slow down or may travel backward if ship is faster than muzzle speed

This is intentional sim-lite behavior — adds tactical depth to positioning and attack vectors without any extra systems.

---

## Debris & Asteroids

### Asteroids
- Extend `SpaceBody` with zero thrust
- Slow ambient drift set at spawn, never changes
- Use `RigidBody3D` if Godot 4.6 Jolt physics handles them cleanly — free tumbling collision response at no code cost; tumble is visible from top-down and adds visual life
- Fall back to `SpaceBody` with randomized angular velocity if RigidBody3D introduces complexity

### Debris
- Extend `SpaceBody`, spawned on ship death
- Inherit a fraction of the destroyed ship's velocity + randomized spread
- Angular velocity randomized at spawn for visual spin
- Lifetime timer — auto-free after N seconds
- No thrust, no collision response needed beyond initial spawn physics

---

## Performance Instrumentation

Per the PerformanceMonitor integration contract:

```gdscript
# In SpaceBody._physics_process():
PerformanceMonitor.begin("Physics.move_and_slide")
move_and_slide()
PerformanceMonitor.end("Physics.move_and_slide")

# In Ship._physics_process(), wrap full thruster allocation:
PerformanceMonitor.begin("Physics.thruster_allocation")
allocate_thrust(forward_input, strafe_input, torque_demand)
PerformanceMonitor.end("Physics.thruster_allocation")
```

```gdscript
# In the scene manager or Ship spawner, once per frame:
PerformanceMonitor.set_count("Physics.active_bodies", get_tree().get_nodes_in_group("space_bodies").size())
```

Register in `_ready()`:
```gdscript
Performance.add_custom_monitor("AllSpace/physics_bodies",
    func(): return PerformanceMonitor.get_count("Physics.active_bodies"))
Performance.add_custom_monitor("AllSpace/physics_ms",
    func(): return PerformanceMonitor.get_avg_ms("Physics.move_and_slide"))
```

---

## Tuning Reference

### Scale

**1 unit = 1 metre.** The ship polygon in `TestScene.gd` is ~35u nose-to-tail = a 35m light fighter. At Camera2D zoom=1 a 1920px-wide viewport shows 1920m of space.

### Key Formulas

```
# Terminal velocity — the actual top speed drag and thrust balance at.
# Set max_speed equal to this so the cap is meaningful.
v_terminal (m/s) = (thruster_force / mass) / linear_drag

# Time constant — seconds to reach 63% of terminal velocity.
tau (s) = 1 / linear_drag

# Stop time (approx) — seconds to coast from v_terminal to near-zero.
stop_time ≈ 3 × tau

# Angular stop distance — radians the ship travels while braking from angular_velocity.
stopping_distance = (angular_velocity²) / (2 × max_angular_accel)
```

### Ship Class Starting Values

These are reference starting points. All values are `@export` and tunable in the editor.

| Class | `mass` | `thruster_force` | `linear_drag` | `max_speed` | `max_angular_accel` | Accel feel |
|---|---|---|---|---|---|---|
| Fighter | 100 | 15 000 | 0.5 | 300 | 5.0 | Snappy, 2 s to top speed |
| Corvette | 250 | 25 000 | 0.5 | 200 | 3.0 | Responsive, 3 s to top speed |
| Frigate | 600 | 36 000 | 0.5 | 120 | 1.5 | Deliberate, 4 s to top speed |
| Destroyer | 1 500 | 60 000 | 0.5 | 80 | 0.7 | Sluggish, 6 s to top speed |

All classes share `alignment_drag = 0.2` and `torque_thrust_ratio = 0.4` unless overridden.

### Parameter Effect Summary

| Parameter | Increase effect | Decrease effect |
|---|---|---|
| `mass` | Slower acceleration, same terminal speed | Faster acceleration |
| `thruster_force` | Higher terminal speed, faster acceleration | Weaker acceleration |
| `linear_drag` | Lower terminal speed, quicker stop | Higher terminal speed, longer drift |
| `alignment_drag` | Velocity couples more tightly to heading on turns | More Newtonian drift; velocity ignores heading unless thrust applied |
| `max_angular_accel` | Snappier turning | Sluggish turning — commits to heading |
| `torque_thrust_ratio` | Turning draws more from the linear thrust budget | Turning is cheaper, more thrust left for movement |

---

## Files

```
/gameplay/physics/
    SpaceBody.gd
/gameplay/entities/
    Ship.gd
    Asteroid.gd
    Debris.gd
```

---

## Dependencies

- `PerformanceMonitor` service must be registered before any SpaceBody enters the scene tree
- `ProjectileManager.cs` receives velocity data from `Ship.gd` at fire time (see Projectile spec)

---

## Success Criteria

- [ ] Fighter and Destroyer feel meaningfully different to pilot with no other changes
- [ ] Cursor tracking produces smooth deceleration with no oscillation overshoot
- [ ] Strafing while turning is visibly slower than turning while stationary
- [ ] Hard 90° turn at max speed produces noticeable but not punishing speed loss
- [ ] Projectiles visibly angle when fired laterally from a moving ship
- [ ] Debris inherits ship velocity on death and drifts convincingly
- [ ] `Physics.move_and_slide` metric visible in Godot debugger graphs
- [ ] 50 simultaneous SpaceBody entities run within frame budget at 60fps
