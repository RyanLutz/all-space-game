# Navigation Controller — Feature Specification
*All Space Combat MVP — Ship Flight Computer*

---

## 1. Overview

`NavigationController.gd` is the flight computer that sits between a high-level
destination and a ship's unified input interface. It converts a world-space target
position into per-frame `input_forward` and `input_strafe` values, handling
acceleration, braking, and arrival without overshooting.

It is a **tool, not an actor.** It has no `_physics_process` of its own and makes
no decisions about where to go, what to face, or when to fire. It is called
explicitly by whoever controls the ship — `AIController.gd` for AI ships, or
`TacticalInputHandler` for player ships in Tactical mode. The caller drives it;
it does not drive itself.

NavigationController is **not used in Pilot mode.** A human player already thinks
in terms of raw thrust inputs. The translation layer NavigationController provides
only exists for callers that think in terms of destinations.

**Design goals:**
- Ships arrive at destinations without overshooting, regardless of their mass or speed
- Works correctly across all ship classes — from a nimble fighter to a sluggish destroyer
- Facing is never its concern — that belongs to the caller
- Clean, replaceable interface — swapping in a smarter pathfinding version requires
  no changes to callers

---

## 2. Architecture

```
AI Ship (RigidBody3D)
    ├── Ship.gd                   — physics translation, unified input interface
    ├── AIController.gd           — state machine, calls nav_controller.update(delta)
    └── NavigationController.gd   — destination → input_forward / input_strafe

Player Ship (RigidBody3D) — Tactical mode only
    ├── Ship.gd
    ├── TacticalInputHandler      — issues move orders, calls nav_controller.update(delta)
    └── NavigationController.gd
```

NavigationController is a **child Node of the ship**. It is not an autoload or a
singleton. Each ship that requires destination-based navigation has its own instance.

### Responsibility Split

| Concern | Owner |
|---|---|
| Where to go (destination) | AIController / TacticalInputHandler |
| What to face (aim target) | AIController / player directly |
| Whether to fire | AIController / player directly |
| Lateral orbit thrust (ENGAGE state) | AIController writes `input_strafe` directly |
| Translate destination → forward / strafe | **NavigationController** |
| Translate aim + inputs → forces / torques | Ship.gd |
| Integrate forces → velocity + position | Jolt |

NavigationController **never writes `input_aim_target`** or `input_fire`. It only
writes `input_forward` and `input_strafe`. If the caller wants to override strafe
after calling `update()` — as AIController does in the ENGAGE orbit case — it
simply writes `owner.input_strafe` after the update call. NavigationController does
not re-run after that.

---

## 3. Core Properties / Data Model

```gdscript
# NavigationController.gd

# Caller-set each frame (before update())
var _destination: Vector3       # world-space XZ target; Y is always 0
var _thrust_fraction: float     # 0.0–1.0 scale on thruster output

# Read from parent ship each frame
# owner.linear_velocity         (Vector3)
# owner.mass                    (float)
# owner.thruster_force          (float)
# owner.transform.basis.z       (ship forward axis, negated)
# owner.transform.basis.x       (ship right axis)

# Internal state
var _arrived: bool = false      # true when within arrival threshold; cleared on new destination
```

NavigationController reads ship physics properties directly from its owner. It does
not maintain its own physics model or cache values between frames — it reads fresh
each `update()` call.

### Tuning Constants

These values are loaded from the ship's `hull` block in `ship.json` and stored
as plain floats. No hardcoded defaults — every ship class defines its own.

```gdscript
var arrival_distance: float       # metres — "close enough" threshold
var brake_safety_margin: float    # multiply braking distance by this before braking
```

Both are populated in `_ready()` from the ship's loaded JSON data. See Section 5
for the JSON format.

`brake_safety_margin` gives the ship a head start on braking — it begins
decelerating earlier than the raw math requires. This compensates for the fact
that drag is intentionally low and the braking force calculation is an
approximation. Values between 1.1 and 1.5 are reasonable; tune against the
heaviest ship class first.

---

## 4. Key Algorithms

### 4.1 Public Interface

```gdscript
# Called each frame by AIController or TacticalInputHandler before update()
func set_destination(pos: Vector3) -> void:
    pos.y = 0.0               # enforce XZ plane — defensive
    _destination = pos
    _arrived = false          # new destination clears arrival state

func set_thrust_fraction(f: float) -> void:
    _thrust_fraction = clampf(f, 0.0, 1.0)

# Called each frame by the controlling system — explicit, not automatic
func update(delta: float) -> void:
    _update_nav(delta)
```

The caller pattern each frame is always:

```gdscript
# AIController._physics_process (example)
nav_controller.set_destination(target_pos)
nav_controller.set_thrust_fraction(profile.wander_thrust_fraction)
nav_controller.update(delta)
# After this point the caller may write input_strafe if it wants lateral thrust
```

### 4.2 Core Navigation Logic

```gdscript
func _update_nav(_delta: float) -> void:
    var ship := owner as RigidBody3D

    var to_dest := _destination - ship.global_position
    to_dest.y = 0.0
    var distance := to_dest.length()

    # --- Arrival ---
    if distance <= arrival_distance:
        ship.input_forward = 0.0
        ship.input_strafe  = 0.0
        _arrived = true
        return

    # --- Braking decision ---
    var velocity := ship.linear_velocity
    velocity.y = 0.0
    var speed := velocity.length()

    var max_decel := (ship.thruster_force * _thrust_fraction) / maxf(ship.mass, 0.001)
    var braking_distance := 0.0
    if max_decel > 0.0:
        braking_distance = (speed * speed) / (2.0 * max_decel) * brake_safety_margin

    var ship_forward := -ship.transform.basis.z   # Godot 3D forward
    var ship_right   :=  ship.transform.basis.x

    if distance <= braking_distance and speed > 0.1:
        # --- Braking: reverse velocity vector projected onto ship axes ---
        var brake_dir := -velocity.normalized()
        ship.input_forward = brake_dir.dot(ship_forward) * _thrust_fraction
        ship.input_strafe  = brake_dir.dot(ship_right)  * _thrust_fraction
    else:
        # --- Accelerate: destination vector projected onto ship axes ---
        var dest_dir := to_dest.normalized()
        ship.input_forward = dest_dir.dot(ship_forward) * _thrust_fraction
        ship.input_strafe  = dest_dir.dot(ship_right)  * _thrust_fraction
```

### Why project onto ship axes?

NavigationController computes thrust in world space (toward destination, or opposing
velocity) and projects that vector onto the ship's local forward and right axes to
produce `input_forward` and `input_strafe`. This is correct regardless of what the
caller told the ship to face. If the AI has the ship facing an enemy during combat
while NavigationController brakes, the braking thrust is decomposed into whatever
combination of forward and strafe achieves the correct world-space direction. Ship.gd
then translates those local inputs into actual forces. Jolt integrates.

### 4.3 Arrival Behaviour

When within `arrival_distance`:
- Both `input_forward` and `input_strafe` are zeroed
- `_arrived` is set to `true`
- The function returns immediately — no further computation

The ship will continue to drift slightly on arrival due to residual momentum and low
drag. This is intentional. Space feels near drag-free; the ship is "there" when it
is close, not when it has achieved a perfect dead stop. If the caller wants the ship
to hold position exactly, it calls `set_destination(global_position)` each frame —
NavigationController will detect arrival immediately and zero thrust, allowing drag
to bleed the remainder.

### 4.4 Thrust Fraction Scaling

`_thrust_fraction` scales all output values uniformly:

```gdscript
ship.input_forward = computed_value * _thrust_fraction
ship.input_strafe  = computed_value * _thrust_fraction
```

A fraction of `0.5` means NavigationController will never push `input_forward` or
`input_strafe` beyond `0.5`. The caller uses this to express intent — a ship
wandering at patrol speed uses a low fraction; a ship pursuing at full combat thrust
uses a high fraction. The ship's physics layer applies the thruster budget on top of
this, so actual thrust is always consistent with ship stats.

---

## 5. JSON Data Format

NavigationController does not own a JSON file. All values it needs live in the
ship's `hull` block in `ship.json` (see Ship System Spec). The implementing agent
reads these in `Ship.gd` on `_ready()` and passes them to NavigationController.

```json
"hull": {
    "mass": 800,
    "max_speed": 450,
    "linear_drag": 0.05,
    "angular_drag": 3.0,
    "alignment_drag_base": 0.3,
    "thruster_force": 12000,
    "torque_thrust_ratio": 0.3,
    "max_torque": 4000,
    "arrival_distance": 25.0,
    "brake_safety_margin": 1.25
}
```

`arrival_distance` and `brake_safety_margin` vary per ship class — a destroyer
brakes over a much longer distance than a fighter and should arrive with a wider
threshold. Defining them in JSON means tuning requires no code changes.

---

## 6. Performance Instrumentation

```gdscript
func update(_delta: float) -> void:
    PerformanceMonitor.begin("Navigation.update")
    _update_nav(_delta)
    PerformanceMonitor.end("Navigation.update")
```

Register in `_ready()`:

```gdscript
func _ready() -> void:
    Performance.add_custom_monitor("AllSpace/nav_update_ms",
        func(): return PerformanceMonitor.get_avg_ms("Navigation.update"))
```

NavigationController runs once per ship per physics frame. At MVP scale (up to 50
AI ships) this is well within budget. Instrument regardless — it establishes the
baseline and catches regressions if ship count grows.

---

## 7. Files

```
/gameplay/ai/
    NavigationController.gd     — flight computer (this spec)
    AIController.gd             — state machine (AI spec)
```

NavigationController lives in `/gameplay/ai/` because its primary consumer is
AIController. TacticalInputHandler will reference it from `/gameplay/player/` when
that system is built.

---

## 8. Dependencies

- **Ship.gd** — NavigationController reads `linear_velocity`, `mass`,
  `thruster_force`, and `transform.basis` from its owner; writes `input_forward`
  and `input_strafe` to it. Ship.gd must exist and expose these before
  NavigationController can function.
- **PerformanceMonitor** — must be registered before any ship enters the scene tree.
- **AIController.gd** — the primary caller at MVP. NavigationController is useless
  without a caller driving it each frame.

NavigationController has no dependency on the GameEventBus — it does not emit or
subscribe to any events. It is a pure computation node.

---

## 9. Assumptions

- `arrival_distance = 25.0` is a starting guess — tune against actual ship speeds
  in the test scene. Fighters may need a tighter threshold; destroyers wider.
- `brake_safety_margin = 1.25` is conservative. If ships are still overshooting,
  increase it. If they are braking too early and arriving uncomfortably far out,
  decrease it.
- Low drag is intentional. NavigationController is not responsible for stopping the
  ship cleanly from every angle — it applies its best braking vector and arrival
  is "close enough." Perfect dead-stop arrival is not a goal.
- The braking calculation assumes constant deceleration, which is only approximately
  true in a Jolt sim with drag. The safety margin exists to absorb this error.
- At MVP, NavigationController does no pathfinding — it steers directly toward the
  destination in a straight line. Obstacle avoidance is out of scope.

---

## 10. Success Criteria

- [ ] AI ship in IDLE state reaches wander targets without overshooting and without
      oscillating back and forth past the arrival point
- [ ] AI ship in PURSUE state closes on the player and transitions to ENGAGE at the
      correct distance — not before, not after a significant overshoot
- [ ] A destroyer (high mass) and a fighter (low mass) both arrive correctly — heavier
      ship starts braking earlier as a natural consequence of the math
- [ ] Calling `set_destination(global_position)` each frame zeroes thrust and holds
      position (drifting only from residual momentum)
- [ ] `input_aim_target` and `input_fire` are never written by NavigationController
      under any circumstances
- [ ] After AIController writes `input_strafe` following `nav_controller.update()`,
      the value persists to Ship.gd unchanged — NavigationController does not clobber it
- [ ] `Navigation.update` metric is visible in the Godot debugger and F3 overlay
- [ ] All tuning values (`arrival_distance`, `brake_safety_margin`, thrust fractions
      from caller profiles) are modifiable without recompile