# AI & Patrol Behavior System Specification
*All Space Combat MVP — Enemy Ship Intelligence and Patrol Patterns*

## Overview

A state-machine-driven AI system that gives enemy ships autonomous behavior — wandering
through patrol regions, detecting the player, and engaging in combat. The system is
built on a JSON-driven **behavior profile** architecture: MVP ships all share one
profile, while the structure natively supports faction fighting styles, personality
variants, and advanced behaviors (flee, coordinate, use cover) without refactoring.

**Design Goals:**
- AI ships feel alive — they move with purpose, react to the player, and fight convincingly
- One behavior profile for MVP, but the architecture supports N profiles via JSON
- AI ships use the same `RigidBody3D` physics as the player — no cheating on thrust,
  turning, or speed
- All movement is routed through `NavigationController.gd` — the same flight computer
  used for Tactical mode player ship orders
- All tunable values live in `ai_profiles.json`
- State machine is clean enough to extend with new states post-MVP without rewriting
  existing ones

---

## Architecture

```
AI Ship (RigidBody3D)
    ├── Ship.gd                   — physics, modules, weapon fire groups (shared with player)
    ├── AIController.gd           — state machine, high-level decisions
    ├── NavigationController.gd   — flight computer: destination → thrust inputs
    └── DetectionVolume (Area3D)  — SphereShape3D trigger for player detection
```

`AIController.gd` is attached only to AI ships. In each physics frame it:
1. Runs the state machine to decide **where to go** and **what to aim at**
2. Gives `NavigationController` a destination (Vector3) and desired heading
3. Decides whether to fire — sets `input_fire` on the ship directly
4. Reads the resulting `input_forward`, `input_strafe` from `NavigationController`
   and writes them to the ship's unified input interface

The ship's physics system reads only from the unified input interface — it does not
know whether the source is a player, an AI, or a Tactical mode order:

```gdscript
# Ship.gd — unified input interface (set each frame by whatever controls the ship)
var input_forward: float          # -1.0 to 1.0
var input_strafe: float           # -1.0 to 1.0
var input_aim_target: Vector3     # world-space XZ point to face toward (Y = 0)
var input_fire: Array[bool]       # one bool per weapon group [group1, group2, group3]
```

In Pilot mode the player's keyboard/mouse populate these. In AI control,
`AIController` populates `input_aim_target` and `input_fire`;
`NavigationController` populates `input_forward` and `input_strafe`.

---

## The 3D Plane Contract

All AI positions and velocities live at **Y = 0**. No entity voluntarily leaves
the XZ play plane.

```gdscript
# When setting a wander target or any navigation destination:
var destination := Vector3(x, 0.0, z)   # Y is always 0

# Ship forward heading in 3D:
var heading: Vector3 = -transform.basis.z   # Godot's default 3D forward

# Distance checks use Vector3.distance_to() — equivalent to 2D distance since Y = 0
var dist: float = global_position.distance_to(target.global_position)
```

`Vector2` is banned for world-space positions and velocities. `Vector2i` is permitted
for chunk grid coordinates only.

---

## State Machine

### States

```
         ┌────────────────────────────────────────┐
         │           player in detection volume    │
  ┌──────▼─────┐                            ┌─────┴──────┐
  │    IDLE    │ ◄──────────────────────── │   PURSUE   │
  │  (wander)  │   player beyond leash      └─────┬──────┘
  └────────────┘   range from spawn               │
                                            within engage
                                            distance
                                                  │
                                           ┌──────▼──────┐
                                           │   ENGAGE    │
                                           └──────┬──────┘
                                                  │
                                           target lost or
                                           target destroyed
                                                  │
                                           ┌──────▼──────┐
                                           │    IDLE     │
                                           │  (wander)   │
                                           └─────────────┘
```

**Future states (enum and transition table reserve them — not implemented at MVP):**
```
FLEE     — disengage and boost away when HP drops below threshold
REGROUP  — return to formation with squad mates
SEARCH   — investigate last known player position after losing contact
ORBIT    — circle a point of interest or asset to guard
```

### Transition Table

Transitions are defined as data, not hardcoded `if` chains. Adding a new state
means adding a new entry here and writing its process function.

```gdscript
# AIController.gd
enum State { IDLE, PURSUE, ENGAGE, FLEE, REGROUP, SEARCH, ORBIT }

const TRANSITIONS: Dictionary = {
    State.IDLE: {
        "player_detected": State.PURSUE,
    },
    State.PURSUE: {
        "in_engage_range":  State.ENGAGE,
        "target_leashed":   State.IDLE,
    },
    State.ENGAGE: {
        "target_lost":       State.IDLE,
        "target_destroyed":  State.IDLE,
        # Future: "hp_below_threshold": State.FLEE,
    },
}

func _transition_to(new_state: State) -> void:
    var old_state := _current_state
    _on_exit_state(_current_state)
    _current_state = new_state
    _on_enter_state(new_state)
    GameEventBus.emit("ai_state_changed", {
        "ship_id":    owner.get_instance_id(),
        "old_state":  State.keys()[old_state],
        "new_state":  State.keys()[new_state],
    })
```

---

## State: IDLE

The ship wanders randomly within its patrol region.

**Behavior:**
1. On entering IDLE (or when current wander target is reached), pick a new random
   point within `wander_radius` of `_spawn_position` — the ship's initial world
   position. Using spawn as the wander origin prevents gradual drift.
2. Pass the wander target to `NavigationController` as the destination.
3. `NavigationController` produces thrust inputs at `wander_thrust_fraction` of max.
4. When within `wander_arrival_distance` of the target, pause for a random duration
   within `[wander_pause_min, wander_pause_max]` seconds, then pick a new point.
5. Each frame, check `_player_detected` flag (set by `DetectionVolume` signals).

**Transition to PURSUE:** `_player_detected` is true.

```gdscript
func _idle_process(delta: float) -> void:
    if _player_detected:
        _transition_to(State.PURSUE)
        return

    var dist_to_target := global_position.distance_to(_wander_target)
    if dist_to_target < profile.wander_arrival_distance:
        _wander_pause_timer -= delta
        if _wander_pause_timer <= 0.0:
            _pick_new_wander_target()
        # Stopped — no thrust input
        nav_controller.set_destination(global_position)    # hold in place
    else:
        nav_controller.set_destination(_wander_target)
        nav_controller.set_thrust_fraction(profile.wander_thrust_fraction)

    _apply_nav_inputs()

func _pick_new_wander_target() -> void:
    var angle := randf() * TAU
    var dist  := randf() * profile.wander_radius
    _wander_target = _spawn_position + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
    _wander_pause_timer = randf_range(profile.wander_pause_min, profile.wander_pause_max)
```

---

## State: PURSUE

The ship has detected the player and is closing distance to engage.

**Behavior:**
1. Pass the player's current position to `NavigationController` as the destination.
2. `NavigationController` drives the ship toward the player at `pursue_thrust_fraction`.
3. Set `input_aim_target` to the player's position so the ship faces them.
4. Each frame: check leash range (distance from `_spawn_position`, not from detection
   point) and check proximity to player.

**Leash range** prevents AI ships from chasing the player across the map.

**Transition to ENGAGE:** Player within `engage_distance`.
**Transition to IDLE:** Ship strays beyond `leash_range` from `_spawn_position`.

```gdscript
func _pursue_process(_delta: float) -> void:
    if not is_instance_valid(_target_player):
        _transition_to(State.IDLE)
        return

    var dist_from_home  := global_position.distance_to(_spawn_position)
    var dist_to_player  := global_position.distance_to(_target_player.global_position)

    if dist_from_home > profile.leash_range:
        _player_detected = false
        _transition_to(State.IDLE)
        return

    if dist_to_player <= profile.engage_distance:
        _transition_to(State.ENGAGE)
        return

    nav_controller.set_destination(_target_player.global_position)
    nav_controller.set_thrust_fraction(profile.pursue_thrust_fraction)
    _apply_nav_inputs()
    # Face the player while closing
    owner.input_aim_target = _target_player.global_position
```

---

## State: ENGAGE

The ship is in combat range and actively fighting the player.

**Behavior:**
1. Compute a **predicted aim position** using linear lead prediction.
2. Maintain distance near `preferred_engage_distance`:
   - Too close (< 70% of preferred): reverse thrust via `NavigationController`
   - Too far (> 130% of preferred): close in
   - Sweet spot: hold position; apply lateral strafe thrust to orbit the player
3. Fire weapon group 1 when aim angle error is within `fire_angle_threshold` degrees.

**Circle direction** is chosen randomly on entering ENGAGE and held for the duration
of the state. This prevents jitter and makes AI feel intentional.

**Transition to IDLE:** Player destroyed or player beyond `leash_range` from spawn.

```gdscript
func _on_enter_engage() -> void:
    _circle_direction = 1.0 if randf() > 0.5 else -1.0

func _engage_process(_delta: float) -> void:
    if not is_instance_valid(_target_player) or _target_player.is_dead:
        _transition_to(State.IDLE)
        return

    if global_position.distance_to(_spawn_position) > profile.leash_range:
        _transition_to(State.IDLE)
        return

    var predicted_pos := _predict_aim_position(_target_player)
    owner.input_aim_target = predicted_pos    # ship faces predicted position

    var dist_to_player := global_position.distance_to(_target_player.global_position)
    var ratio := dist_to_player / profile.preferred_engage_distance

    if ratio < 0.7:
        # Too close — reverse away from player
        nav_controller.set_destination(global_position - (_target_player.global_position - global_position).normalized() * 200.0)
        nav_controller.set_thrust_fraction(profile.engage_thrust_fraction)
    elif ratio > 1.3:
        # Too far — close in
        nav_controller.set_destination(_target_player.global_position)
        nav_controller.set_thrust_fraction(profile.engage_thrust_fraction)
    else:
        # Sweet spot — orbit via strafe
        nav_controller.set_destination(global_position)    # hold position
        # input_strafe is a local-space scalar: +1.0 = ship's right, -1.0 = ship's left.
        # Ship.gd's physics layer multiplies this by transform.basis.x to produce force.
        # The AI just decides direction and magnitude; no world-space projection needed.
        owner.input_strafe = _circle_direction * profile.strafe_thrust_fraction

    _apply_nav_inputs()

    # Fire decision — compare ship's current facing to aim direction
    var to_predicted := (predicted_pos - global_position)
    to_predicted.y = 0.0
    var ship_forward := -transform.basis.z
    var aim_error_rad := ship_forward.angle_to(to_predicted.normalized())
    if aim_error_rad <= deg_to_rad(profile.fire_angle_threshold):
        owner.input_fire[0] = true   # fire weapon group 1
    else:
        owner.input_fire[0] = false
```

---

## Aim Prediction

Linear lead prediction. Operates fully in XZ — Y is always 0 on both positions.

```gdscript
func _predict_aim_position(target: Node3D) -> Vector3:
    var to_target := target.global_position - global_position
    to_target.y = 0.0
    var distance := to_target.length()

    var muzzle_speed := _get_primary_muzzle_speed()
    if muzzle_speed <= 0.0:
        return target.global_position

    # target.velocity is Vector3 with Y = 0
    var travel_time := distance / muzzle_speed
    var predicted := target.global_position + target.velocity * travel_time * profile.aim_accuracy
    predicted.y = 0.0    # enforce XZ plane

    return predicted
```

`aim_accuracy` is a float from 0.0 to 1.0 in the behavior profile:
- `1.0` — perfect prediction (hard)
- `0.7` — decent prediction with occasional misses on fast targets (default)
- `0.3` — mostly shoots where the player is now, not where they will be (easy)

This single parameter is the primary difficulty knob. Tune it first during playtesting.

---

## NavigationController Interface

`AIController` communicates with `NavigationController` through a clean interface.
The AI never touches ship thrust values directly.

```gdscript
# AIController calls these each frame in each state:
nav_controller.set_destination(pos: Vector3) -> void     # world-space XZ target
nav_controller.set_thrust_fraction(f: float) -> void     # 0.0 to 1.0 of max thrust

# NavigationController writes these to the ship each frame:
owner.input_forward = ...    # computed from destination + physics
owner.input_strafe  = ...    # computed from destination + physics
```

The navigation controller handles deceleration, overshoot prevention, and arrival.
The AI controller only decides *where* to go, not *how* to get there physically.

### Applying Nav Inputs

After calling the nav interface, the AI pulls results back through the ship interface:

```gdscript
func _apply_nav_inputs() -> void:
    # NavigationController has already written to owner.input_forward / input_strafe
    # Nothing else needed here — Ship.gd reads the unified interface in _physics_process
    pass
```

---

## Detection System

Detection uses an `Area3D` with a `SphereShape3D` on each AI ship. No line-of-sight
or facing cone at MVP — simple radius trigger.

```
DetectionVolume (Area3D)
    └── CollisionShape3D (SphereShape3D, radius = detection_range)
```

- Collision layer set to detect only the player's physics layer
- `body_entered` → set `_player_detected = true`, store `_target_player` reference
- `body_exited` → clear `_player_detected` (only matters in IDLE; PURSUE and ENGAGE
  use leash range instead)

Using `Area3D` signals is cheaper than per-frame distance checks across all AI ships —
the physics engine handles broadphase.

**Future extension:** Replace `SphereShape3D` with a cone or sector shape for directional
detection without touching any state machine code. The state machine only checks
`_player_detected`.

```gdscript
# AIController.gd — connected in _ready()
func _on_detection_volume_body_entered(body: Node3D) -> void:
    if body.is_in_group("player"):
        _player_detected = true
        _target_player   = body

func _on_detection_volume_body_exited(body: Node3D) -> void:
    if body == _target_player:
        _player_detected = false
```

---

## Spawning & Patrol Region

### MVP Approach

AI ships are placed in the test scene manually or by a simple spawner script. Each
ship stores its initial world position as `_spawn_position` on `_ready()`.

```gdscript
# AIController.gd
var _spawn_position: Vector3

func _ready() -> void:
    _spawn_position = global_position    # Y = 0 by construction
    _load_profile(profile_id)
    _pick_new_wander_target()
    _current_state = State.IDLE
```

### Future: Patrol Region Nodes (Post-MVP)

When the chunk streamer is built, patrol regions will be `Area3D` zones placed in chunk
scenes. When a chunk loads, its patrol regions spawn AI ships at random points within
their bounds. The AI controller will reference those region bounds instead of a fixed
`wander_radius`. The architecture supports this without refactoring — `_spawn_position`
and `profile.wander_radius` are the only wander constraints today, and they stay clean
enough to replace.

---

## Behavior Profile (JSON)

All tuning values live in `/data/ai_profiles.json`. MVP ships reference `"default"`.

```json
{
  "ai_profiles": [
    {
      "id": "default",
      "display_name": "Standard Patrol",

      "detection_range": 800.0,
      "leash_range": 1500.0,
      "engage_distance": 500.0,
      "preferred_engage_distance": 350.0,

      "wander_radius": 600.0,
      "wander_thrust_fraction": 0.4,
      "wander_arrival_distance": 40.0,
      "wander_pause_min": 1.0,
      "wander_pause_max": 3.0,

      "pursue_thrust_fraction": 0.85,

      "engage_thrust_fraction": 0.7,
      "strafe_thrust_fraction": 0.3,
      "fire_angle_threshold": 15.0,

      "aim_accuracy": 0.7,

      "flee_enabled": false,
      "flee_hp_threshold": 0.0,

      "faction": "neutral",
      "personality": "standard"
    }
  ]
}
```

**Fields reserved for future use (ignored at MVP):**
- `flee_enabled` / `flee_hp_threshold` — when FLEE state is implemented
- `faction` — when faction-specific styles are added
- `personality` — behavioral variants within a faction (e.g., "aggressive", "cautious")

Adding a new archetype post-MVP = new JSON entry + assign it to ships. No code changes.

---

## Events Emitted

AI state transitions and target changes are broadcast on `GameEventBus`. No system
should poll AI state directly.

```gdscript
GameEventBus.emit("ai_state_changed", {
    "ship_id":   owner.get_instance_id(),
    "old_state": State.keys()[old_state],
    "new_state": State.keys()[new_state],
})

GameEventBus.emit("ai_target_acquired", {
    "ship_id":   owner.get_instance_id(),
    "target_id": _target_player.get_instance_id(),
})

GameEventBus.emit("ai_target_lost", {
    "ship_id": owner.get_instance_id(),
})
```

---

## Performance Instrumentation

Per the PerformanceMonitor integration contract:

```gdscript
# AIController.gd — wrap the full state machine update per ship
func _physics_process(delta: float) -> void:
    PerformanceMonitor.begin("AIController.state_updates")
    match _current_state:
        State.IDLE:    _idle_process(delta)
        State.PURSUE:  _pursue_process(delta)
        State.ENGAGE:  _engage_process(delta)
    PerformanceMonitor.end("AIController.state_updates")
```

With multiple AI ships each calling `begin()`/`end()`, the metric accumulates all AI
time within one frame. This is correct — the metric represents **total AI cost per
frame**, not per-ship cost.

```gdscript
# In the scene manager or AI spawner, once per frame:
PerformanceMonitor.set_count("AIController.active_count",
    get_tree().get_nodes_in_group("ai_ships").size())
```

Register custom monitors in `_ready()`:

```gdscript
Performance.add_custom_monitor("AllSpace/ai_ships_active",
    func(): return PerformanceMonitor.get_count("AIController.active_count"))
Performance.add_custom_monitor("AllSpace/ai_ms",
    func(): return PerformanceMonitor.get_avg_ms("AIController.state_updates"))
```

---

## Files

```
/gameplay/ai/
    AIController.gd
    AIController.tscn
    NavigationController.gd    ← flight computer shared with Tactical mode
/data/
    ai_profiles.json
```

---

## Dependencies

- `Ship.gd` from Physics spec — AI writes through the same unified input interface
  as the player (`input_forward`, `input_strafe`, `input_aim_target`, `input_fire`)
- `NavigationController.gd` — must exist before AIController can be built; provides
  the flight computer abstraction
- `PerformanceMonitor` registered before any AI ship enters the scene tree
- `GameEventBus` for state transition events
- `WeaponComponent.gd` — `input_fire` triggers weapon groups through the same weapon
  interface the player uses; AI does not call fire methods directly
- Player ship must be in the `"player"` group for detection callbacks

---

## Assumptions (Revisit During Balancing)

- All distance values (detection 800, leash 1500, engage 500, preferred 350) are in
  world-space units — tune after first playtest
- `aim_accuracy` of 0.7 is a guess — this is the primary difficulty lever, adjust first
- `preferred_engage_distance` of 350 assumes medium-range weapons; will need to scale
  with loadout post-MVP
- Wander pause range (1–3 seconds) affects how "alive" idle AI feels — arbitrary for now
- `strafe_thrust_fraction` of 0.3 during circling is conservative; increase for more
  dynamic fights
- Single circle direction per engage session may feel predictable — acceptable at MVP

---

## Future Extension Points

| Feature | How It Fits |
|---|---|
| **Flee behavior** | Add `FLEE` state; transition when `flee_enabled && hp < flee_hp_threshold` |
| **Faction fighting styles** | New profiles: `"pirate_aggressive"`, `"militia_cautious"`, etc. |
| **Personality variants** | Multiple profiles per faction with weighted random selection at spawn |
| **Squad coordination** | `REGROUP` state + shared target list between ships in a patrol group |
| **Cover usage** | `SEARCH` state + raycast checks for asteroid occlusion during ENGAGE |
| **Difficulty scaling** | Adjust `aim_accuracy`, thrust fractions, and engage distances per difficulty |
| **Patrol region zones** | Replace `_spawn_position + wander_radius` with `Area3D` bounds from chunks |
| **Conditional orders** | Add priority interrupts to transition table (e.g., "if ally under attack → assist") |

---

## Success Criteria

- [ ] AI ships wander visibly within their patrol region when no player is nearby
- [ ] AI ship transitions to PURSUE when player enters detection volume
- [ ] AI ship closes distance and transitions to ENGAGE at the correct range
- [ ] AI ship maintains preferred distance — backs off when too close, advances when too far
- [ ] AI ship circles the player with strafe thrust when in the engagement sweet spot
- [ ] AI ship leads shots using aim prediction — hits are frequent but not perfect
- [ ] AI ship fires only when facing approximately toward the predicted player position
- [ ] AI ship returns to IDLE wander when player moves beyond leash range
- [ ] AI ship uses `RigidBody3D` physics — no teleporting, no instant turns
- [ ] All positions and velocities remain at Y = 0 throughout all state transitions
- [ ] AI state transitions are visible in the PerformanceMonitor debug overlay (F3)
- [ ] 15+ simultaneous AI ships run within frame budget at 60fps
- [ ] All AI tuning values are modifiable in `ai_profiles.json` without recompile
- [ ] Adding a second behavior profile requires only a new JSON entry and assigning it to a ship
- [ ] AI movement routes through `NavigationController` — no direct thrust writes in AIController
