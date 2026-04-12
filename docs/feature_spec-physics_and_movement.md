# Physics & Movement System Specification
*All Space Combat MVP — Ship and Entity Physics (3D / Jolt)*

## Overview

A sim-lite, force-based physics system built on `RigidBody3D` and Jolt. Ships are
proper rigid bodies — forces and torques are applied each frame, Jolt integrates
them. Heavier ships turn and accelerate more slowly as a natural consequence of
mass and moment of inertia; no special-casing in code.

Gameplay is constrained to the **XZ plane (Y = 0)** by freezing Y translation and
X/Z rotation axes in Jolt. Ship heading is yaw (rotation around Y). Forward is
`-transform.basis.z` (Godot's default 3D forward).

**Core Feel:**
- Ships feel heavy and purposeful, not floaty
- Space feels nearly drag-free by default — ships coast, top speed is a soft limit
  rather than a hard one, and lateral momentum mostly persists through turns
- Turning takes time — and ships can optionally bite into their own lateral
  momentum to carve tighter turns at a cost (see Alignment Drag below)
- Projectiles inherit the firing ship's velocity at fire time
- A fighter and a destroyer feel meaningfully different with no other changes
- Assisted steering behaves like a competent navigation computer, not a cheat

---

## Three Layers

```
┌─────────────────────────────────────────┐
│ 1. Input Layer                          │
│    Player / AI / NavigationController   │
│    → populates Ship unified input vars  │
└────────────────┬────────────────────────┘
                 │  input_forward, input_strafe,
                 │  input_aim_target, input_fire[]
                 ▼
┌─────────────────────────────────────────┐
│ 2. Ship Logic Layer                     │
│    - Thruster budget allocation         │
│    - Assisted steering (target torque)  │
│    - Alignment drag (lateral bleed)     │
│    → calls apply_central_force / torque │
└────────────────┬────────────────────────┘
                 │  forces, torques
                 ▼
┌─────────────────────────────────────────┐
│ 3. Jolt Physics Integration             │
│    RigidBody3D integrates F and τ       │
│    Axis locks enforce XZ plane          │
│    Linear/angular damping applied       │
└─────────────────────────────────────────┘
```

The ship logic layer never writes directly to `linear_velocity` or `angular_velocity`.
It expresses its intent as forces and torques; Jolt does the integration.

---

## Entity Hierarchy

```
RigidBody3D
    └── SpaceBody.gd (logical interface)
            ├── Ship.gd         (thruster budget, assisted steering, input)
            ├── Asteroid.gd     (Jolt-driven tumble, damage, loot)
            └── Debris.gd       (short lifetime; may use Node3D instead — visual only)

Node (C#)
    └── ProjectileManager.cs    (pooled — see Weapons spec)
```

Projectiles are NOT `SpaceBody` instances. They inherit `linear_velocity` from
the firing ship at spawn and are managed entirely by `ProjectileManager`.

---

## RigidBody3D Configuration

Every ship is a `RigidBody3D` configured identically for play-plane enforcement:

| Property | Value | Why |
|---|---|---|
| `gravity_scale` | `0.0` | No gravity in space |
| `axis_lock_linear_y` | `true` | Entity stays at Y = 0 |
| `axis_lock_angular_x` | `true` | No pitch |
| `axis_lock_angular_z` | `true` | No roll |
| `linear_damp_mode` | `DAMP_MODE_REPLACE` | Use explicit per-ship drag from JSON |
| `angular_damp_mode` | `DAMP_MODE_REPLACE` | Use explicit per-ship angular drag from JSON |
| `linear_damp` | from JSON | Tuned per ship class |
| `angular_damp` | from JSON | Tuned per ship class |
| `can_sleep` | `false` | Ships are always active |

Mass and center of mass are set from `ship.json`. Moment of inertia is computed by
Jolt from mass and the collision shape automatically — heavier, longer ships resist
turning naturally.

**Y-enforcement backstop:** After each `_physics_process`, assert `position.y == 0`.
If nonzero (e.g. from a collision pushing vertically before axis locks clamp),
zero it explicitly. Cheap insurance.

---

## Core Properties / Data Model

### SpaceBody Interface

Logical interface — not a base class — implemented by all physics entities.
See Core Spec Section 9 for the full contract.

| Property | Type | Description |
|---|---|---|
| `mass` | float | kg; set on `RigidBody3D` |
| `max_speed` | float | Soft cap — drag scales up above this |
| `linear_drag` | float | Jolt `linear_damp` value — low by default (near drag-free coast) |
| `angular_drag` | float | Jolt `angular_damp` value |
| `alignment_drag_base` | float | Default lateral velocity bleed coefficient — low by default |
| `alignment_drag_current` | float | Active coefficient this frame — what the physics step actually uses |

### Ship-Specific Properties

| Property | Type | Description |
|---|---|---|
| `thruster_force` | float | Total per-frame thrust budget (N) |
| `torque_thrust_ratio` | float | How much of the budget one unit of torque demand costs |
| `max_torque` | float | Hard cap on torque magnitude |
| `input_forward` | float | −1.0 to 1.0, unified input interface (Core Spec §3) |
| `input_strafe` | float | −1.0 to 1.0 |
| `input_aim_target` | Vector3 | World-space point the ship wants to face |
| `input_fire` | Array[bool] | One bool per weapon fire group |

---

## Key Algorithms

### Mouse-to-World (Player Input)

The player's aim target is produced by intersecting a camera ray with the Y = 0
plane. This is the canonical mouse-to-world for the entire project.

```gdscript
func mouse_to_world(camera: Camera3D, mouse_pos: Vector2) -> Vector3:
    var plane := Plane(Vector3.UP, 0.0)            # Y = 0
    var ray_origin := camera.project_ray_origin(mouse_pos)
    var ray_dir := camera.project_ray_normal(mouse_pos)
    var hit = plane.intersects_ray(ray_origin, ray_dir)
    return hit if hit != null else ray_origin      # fallback: camera origin
```

Player input sets `input_aim_target` to this value each frame. AI and
NavigationController produce the same `Vector3` world point by their own means.

### Heading and Target Error

```gdscript
func get_heading() -> Vector3:
    return -transform.basis.z                      # Godot 3D forward

func get_heading_error(target_world: Vector3) -> float:
    var to_target := target_world - global_position
    to_target.y = 0.0
    if to_target.length_squared() < 0.0001:
        return 0.0
    var target_yaw := atan2(-to_target.x, -to_target.z)   # yaw for -Z forward
    return wrapf(target_yaw - rotation.y, -PI, PI)
```

### Assisted Steering (Target Torque)

A control-system problem, not magic. Each frame the ship decides whether to
accelerate toward its target heading or brake against its current angular
velocity. The decision is based on predicted stopping distance.

```gdscript
func compute_steering_torque() -> float:
    var heading_error := get_heading_error(input_aim_target)
    var omega := angular_velocity.y                  # current yaw rate

    # How far will we rotate before angular velocity hits zero at max torque?
    # Jolt integrates τ/I; we approximate with max_torque / moment_of_inertia.
    var I := get_inverse_inertia_tensor().inverse().y.y
    var max_alpha := max_torque / maxf(I, 0.001)
    var stopping_distance := (omega * omega) / (2.0 * max_alpha)

    # If we'll overshoot, brake. Otherwise accelerate toward the target.
    if stopping_distance >= absf(heading_error) and signf(omega) == signf(heading_error):
        return -signf(omega) * max_torque            # brake
    else:
        return signf(heading_error) * max_torque     # accelerate toward target
```

This gives every ship the feel of a competent flight computer: it decelerates
precisely and lands on the cursor heading without oscillation. Heavier ships
with higher moment of inertia simply take longer to turn — the lag is physical,
not artificial.

### Thruster Budget Allocation

The ship has one per-frame thrust budget. Turning gets priority; translation
gets the remainder. This creates natural tradeoffs with zero UI.

```gdscript
func apply_thrust_forces() -> void:
    # 1. Compute desired torque from assisted steering
    var torque_demand := compute_steering_torque()
    var torque_cost := absf(torque_demand) * torque_thrust_ratio
    var remaining := maxf(0.0, thruster_force - torque_cost)

    # 2. Translation gets whatever is left
    var forward_dir := get_heading()
    var right_dir := transform.basis.x
    var input_vec := Vector2(input_strafe, -input_forward)
    if input_vec.length() > 1.0:
        input_vec = input_vec.normalized()

    var translation_force :=
        forward_dir * (-input_vec.y) * remaining +
        right_dir   *   input_vec.x  * remaining

    # 3. Hand off to Jolt
    apply_central_force(translation_force)
    apply_torque(Vector3(0, torque_demand, 0))
```

**Effect in play:** Corkscrewing around an enemy turns slower than straight-line
flight. No UI explains this; players feel it.

### Partial Alignment Drag

The universe is nearly drag-free. Ships coast, `max_speed` is a soft limit rather
than a wall, and lateral momentum mostly persists through turns — a hard 90° cut
leaves the ship sliding sideways through the maneuver, carrying its original
velocity with it.

**Alignment drag** is a force that opposes only the **lateral** velocity component
(perpendicular to heading). The **axial** component (along heading) is unaffected.
When active, it bleeds off sideways drift without abolishing forward momentum —
the ship's hull "biting into" its own slide to carve a tighter turn.

Alignment drag has two values:

- **`alignment_drag_base`** — the default coefficient. Low. Ships feel near
  drag-free; turns are wide and preserve momentum.
- **`alignment_drag_current`** — what the physics step actually uses each frame.
  Starts equal to the base value, but can be raised on demand (e.g. a toggle the
  player activates for a sharp combat turn, or something an equipped module
  modulates). The physics system consumes this value each frame; it doesn't care
  who wrote to it or why.

Applied as a force (not a direct velocity edit) so it stacks correctly with other
forces and Jolt integration.

```gdscript
func apply_alignment_drag() -> void:
    var heading := get_heading()
    var v := linear_velocity
    v.y = 0.0

    var axial := heading * v.dot(heading)
    var lateral := v - axial

    # Drag force opposes lateral velocity, scaled by the *current* coefficient
    var drag_force := -lateral * alignment_drag_current * mass
    apply_central_force(drag_force)
```

At the end of each physics step, `alignment_drag_current` is reset to
`alignment_drag_base`. Anything that wants it higher writes to it again on the
next frame — a standard "one-frame override" pattern that keeps effects from
getting stuck on.

```gdscript
func _physics_process_end() -> void:
    alignment_drag_current = alignment_drag_base
```

**Tuning targets at base coefficient (low):**
- Gentle turn: essentially no bleed — ship keeps its momentum
- Hard turn: ship visibly slides sideways through the maneuver
- U-turn: lateral drift persists for several seconds

**Tuning targets at elevated coefficient (high):**
- Gentle turn: slight tightening
- Hard turn: noticeable grip, ship carves the turn
- U-turn: lateral drift scrubs quickly; requires re-acceleration

Specific mechanisms that alter `alignment_drag_current` (player toggles, modules,
status effects) are defined in their own specs. Physics only owns the field and
its consumption.

### Full Per-Frame Pipeline

```gdscript
func _physics_process(_delta: float) -> void:
    PerformanceMonitor.begin("Physics.thruster_allocation")
    apply_thrust_forces()
    apply_alignment_drag()
    PerformanceMonitor.end("Physics.thruster_allocation")

    # Reset per-frame overrides — anything wanting an elevated alignment drag
    # must write it again next frame
    alignment_drag_current = alignment_drag_base

    # Y-enforcement backstop
    if absf(global_position.y) > 0.0001:
        var p := global_position
        p.y = 0.0
        global_position = p
```

Jolt does the integration step outside `_physics_process`. `linear_drag` and
`angular_drag` (set on the body) are applied by Jolt automatically.

---

## Angular Inertia by Ship Mass

Tuning targets, not hard values. All fall out of mass, collision shape, and
`max_torque` interacting through Jolt.

| Ship Class | Feel |
|---|---|
| Fighter | Snappy — cursor tracking nearly immediate |
| Corvette | Responsive — small lag at high turn rates |
| Frigate | Deliberate — heading changes require planning |
| Destroyer+ | Sluggish — commit to your heading |

---

## Momentum Inheritance (Projectiles)

Projectiles inherit the firing ship's velocity at fire time:

```gdscript
# Ship.gd when firing — passes to ProjectileManager
var inherited_velocity := linear_velocity
inherited_velocity.y = 0.0
ProjectileManager.spawn(muzzle_pos, aim_dir, muzzle_speed, inherited_velocity, weapon_data)
```

Inside `ProjectileManager.cs`:
```csharp
projectile.Velocity = aimDirection * muzzleSpeed + inheritedVelocity;
// Velocity.Y is always 0 — projectiles ride the play plane
```

**Effect in play:**
- Firing forward while fast: rounds travel faster relative to the world
- Firing laterally while strafing: rounds angle with travel direction
- Firing backward: rounds slow or even travel backward

---

## Debris and Asteroids

### Asteroids
- `RigidBody3D` with same axis locks as ships (Y translation frozen, X/Z rotation
  frozen — they yaw tumble only, on the play plane)
- Jolt handles collision response and tumbling — free behavior, no code
- HP, size tier, and loot table per instance — see ChunkStreamer spec

### Debris
- `Node3D` (NOT a RigidBody3D) — purely visual
- Spawned with an initial velocity that is integrated manually each frame
- Yaw-only spin randomized at spawn
- Short lifetime timer → `queue_free()`
- No collision — debris never participates in hit detection

---

## JSON Data Format

Physics stats are part of each ship's `ship.json` `hull` block (see Ship System Spec).
Physics does not own its own JSON file — relevant fields:

```json
"hull": {
    "mass": 800,
    "max_speed": 450,
    "linear_drag": 0.05,
    "angular_drag": 3.0,
    "alignment_drag_base": 0.3,
    "thruster_force": 12000,
    "torque_thrust_ratio": 0.3,
    "max_torque": 4000
}
```

`linear_drag` and `alignment_drag_base` default low so space feels near drag-free.
`alignment_drag_base` is what ships coast with by default; the runtime
`alignment_drag_current` starts here each frame and can be raised by other systems
(player toggles, modules) to carve tighter turns on demand.

---

## Performance Instrumentation

Per the PerformanceMonitor contract (Core Spec §10):

```gdscript
# Ship._physics_process — wrap thruster + alignment drag as one block
PerformanceMonitor.begin("Physics.thruster_allocation")
apply_thrust_forces()
apply_alignment_drag()
PerformanceMonitor.end("Physics.thruster_allocation")

# Scene manager — once per frame
PerformanceMonitor.set_count("Physics.active_bodies",
    get_tree().get_nodes_in_group("space_bodies").size())
```

Register custom monitors in `_ready()`:

```gdscript
Performance.add_custom_monitor("AllSpace/physics_bodies",
    func(): return PerformanceMonitor.get_count("Physics.active_bodies"))
Performance.add_custom_monitor("AllSpace/physics_thrust_ms",
    func(): return PerformanceMonitor.get_avg_ms("Physics.thruster_allocation"))
```

**Note:** `Physics.move_and_slide` metric from the canonical list no longer applies
— ships are RigidBody3D and do not call `move_and_slide`. Jolt's integration cost
is visible via Godot's built-in physics profiler. The canonical name is retained
in the registry for backwards-compatibility but is unused in this spec.

---

## Files

```
/gameplay/physics/
    SpaceBody.gd              (logical interface / shared helpers)
/gameplay/entities/
    Ship.gd
    Ship.tscn
    Asteroid.gd
    Debris.gd
/gameplay/ai/
    NavigationController.gd   (flight computer — see AI spec)
```

---

## Dependencies

- `PerformanceMonitor` registered before any SpaceBody enters the scene tree
- `ContentRegistry` loaded — ships read physics stats from `ship.json`
- Jolt physics backend enabled in Godot project settings
- `ProjectileManager.cs` receives velocity data from `Ship.gd` at fire time
- Camera (any) providing the ray source for mouse-to-world — `mouse_to_world()` is
  a free helper, but player input requires a `Camera3D` reference

---

## Assumptions (Revisit During Balancing)

- `torque_thrust_ratio` starting values for each ship class are guesses — tune first
- `alignment_drag_base` defaults low — ships should feel near drag-free by default;
  tune so that coasting and hard-turn slide feel right before wiring up any
  mechanisms that elevate it
- `max_torque` per ship class is a guess — tune against the assisted-steering stopping
  distance for the desired snappy/sluggish feel
- Y-axis locks plus backstop assertion is belt-and-suspenders — if Jolt axis locks
  prove perfectly reliable in practice, the backstop can be removed
- Jolt's inertia-from-collision-shape approximation is adequate for MVP; explicit
  inertia tensor overrides are deferred
- Asteroids using `RigidBody3D` is assumed to work cleanly with Jolt — fall back to
  kinematic Node3D with scripted tumble only if collision proves problematic

---

## Success Criteria

- [ ] Fighter and Destroyer feel meaningfully different to pilot with no other changes
- [ ] Cursor tracking produces smooth deceleration with no oscillation overshoot
- [ ] Strafing while turning is visibly slower than turning while stationary
- [ ] Hard 90° turn at max speed at base drag produces visible lateral slide —
      ship carries its original momentum through the maneuver
- [ ] Raising `alignment_drag_current` mid-flight visibly tightens the turn arc;
      leaving it elevated one frame only confirms the reset behavior works
- [ ] Ships coast noticeably when thrust input is released — space feels near
      drag-free, not like molasses
- [ ] Projectiles visibly angle when fired laterally from a moving ship
- [ ] Debris inherits ship velocity on death and drifts convincingly
- [ ] All ships remain at Y = 0 under all conditions — including collisions
- [ ] Ships yaw only — no visible pitch or roll ever
- [ ] Mouse-to-world produces correct aim targets at all camera zoom levels
- [ ] `Physics.thruster_allocation` metric visible in Godot debugger and F3 overlay
- [ ] 50 simultaneous ships run within frame budget at 60fps
- [ ] All physics tuning values are modifiable in `ship.json` without recompile
- [ ] No `CharacterBody2D`, `CharacterBody3D`, `RigidBody2D`, or manual velocity
      assignment anywhere in the physics code path
