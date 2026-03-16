# Physics & Movement System Specification
*All Space Combat MVP — Ship and Entity Physics*

## Overview

A sim-lite physics system built on manual velocity control via `CharacterBody2D`. All physical entities share a common `SpaceBody` base. The system prioritizes tactile, momentum-based feel over strict Newtonian accuracy — ships have weight and inertia, but the universe applies gentle drag to prevent infinite drift.

**Core Feel:**
- Ships feel heavy and purposeful, not floaty
- Turning is limited by angular inertia — hard course corrections take time
- High-speed turns bleed off lateral velocity naturally
- Projectiles inherit shooter momentum at the moment of firing

---

## Entity Hierarchy

```
CharacterBody2D
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

| Property | Type | Description |
|---|---|---|
| `mass` | float | kg equivalent — affects inertia and torque response |
| `moment_of_inertia` | float | Resistance to angular acceleration. Derived: `mass * radius_sq * 0.5` |
| `velocity` | Vector2 | Current linear velocity (pixels/sec) |
| `angular_velocity` | float | Current rotation speed (radians/sec) |
| `max_speed` | float | Soft cap — drag increases above this, hard cap slightly above |
| `linear_drag` | float | Base drag coefficient applied each frame |

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

Applied when the ship's velocity direction is misaligned with its heading. Only the **lateral component** (perpendicular to heading) bleeds off — the **axial component** (along heading) is unaffected.

```gdscript
func apply_alignment_drag(delta: float) -> void:
    var heading = Vector2.RIGHT.rotated(rotation)
    var axial = heading * velocity.dot(heading)        # component along heading
    var lateral = velocity - axial                     # component perpendicular

    # Only bleed lateral — axial momentum is preserved
    lateral *= (1.0 - alignment_drag * delta)
    velocity = axial + lateral
```

`alignment_drag` is tuned higher than `linear_drag` — lateral drift bleeds noticeably during hard turns, but not instantly.

**Tuning targets:**
- Gentle turn (< 30°): barely perceptible bleed
- Hard turn (90°+): noticeable speed loss, recoverable with thrust
- U-turn (180°): significant speed scrub, requires re-acceleration

---

## Ship Movement

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

    var movement_input = Vector2(strafe_input, -forward_input)
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
Mouse Position
    → Target Heading Angle
        → Heading Error (delta between current rotation and target)
            → Torque Demand
                → Thruster Budget Allocation
                    → angular_velocity delta
                        → rotation update
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
    var heading_error = angle_difference(rotation, target_angle)
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
var inherited_velocity = self.velocity
ProjectileManager.spawn(muzzle_position, aim_direction, muzzle_speed, inherited_velocity, weapon_data)
```

Inside `ProjectileManager.cs`:
```csharp
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
- Use `RigidBody2D` if Godot 4.6 Jolt physics handles them cleanly — free tumbling collision response at no code cost
- Fall back to `SpaceBody` with randomized angular velocity if RigidBody2D introduces complexity

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
