# AI & Patrol Behavior System Specification
*All Space Combat MVP — Enemy Ship Intelligence and Patrol Patterns*

## Overview

A state-machine-driven AI system that gives enemy ships autonomous behavior — wandering through patrol regions, detecting the player, and engaging in combat. The system is built on a JSON-driven **behavior profile** architecture so that MVP ships all share one profile, while the structure natively supports faction fighting styles, personality variants, and advanced behaviors (flee, coordinate, use cover) without refactoring.

**Design Goals:**
- AI ships feel alive — they move with purpose, react to the player, and fight convincingly
- One behavior profile for MVP, but the architecture supports N profiles via JSON
- AI ships use the same physics system as the player — no cheating on thrust, turning, or speed
- All tunable values (detection range, engagement distance, wander radius, etc.) live in JSON
- State machine is clean enough to extend with new states post-MVP without rewriting existing ones

---

## Architecture

### Behavior Profiles

Every AI ship references a `behavior_profile` by ID. The profile defines how the ship acts in each state — detection ranges, preferred engagement distance, aggression, whether to flee, etc. MVP ships all use the `"default"` profile.

```
AI Ship Instance
    → reads behavior_profile from JSON
    → feeds profile values into state machine
    → state machine drives the ship's physics inputs (thrust, strafe, aim target)
```

The AI controller does **not** move the ship directly. It produces the same inputs the player would — forward thrust, strafe thrust, and a target heading — and feeds them into the ship's existing physics pipeline. AI ships obey the same thruster budget, angular inertia, and drag as the player.

### Component Structure

```
Ship (CharacterBody2D)
    ├── Ship.gd                    (physics, modules — shared with player)
    ├── AIController.gd            (state machine, decision-making)
    └── DetectionArea (Area2D)     (circular trigger for player detection)
```

`AIController.gd` is attached only to AI ships — the player ship does not have one. It reads its behavior profile on `_ready()` and runs the state machine in `_physics_process()`.

---

## State Machine

### States

```
┌──────────┐    player in detection range    ┌──────────┐
│          │ ──────────────────────────────── │          │
│  IDLE    │                                 │  PURSUE  │
│ (wander) │ ◄────────────────────────────── │          │
└──────────┘    player out of leash range     └────┬─────┘
                                                   │
                                              within engage
                                              distance
                                                   │
                                                   ▼
                                              ┌──────────┐
                                              │          │
                                              │  ENGAGE  │
                                              │          │
                                              └────┬─────┘
                                                   │
                                              target lost OR
                                              target destroyed
                                                   │
                                                   ▼
                                              ┌──────────┐
                                              │  IDLE    │
                                              │ (wander) │
                                              └──────────┘
```

**Future states (not implemented at MVP, but the enum and transition table reserve them):**

```
FLEE        — disengage and boost away when HP drops below threshold
REGROUP     — return to formation with squad mates
SEARCH      — investigate last known player position after losing contact
ORBIT       — circle a point of interest or asset to guard
```

### State: IDLE

The ship wanders randomly within its assigned patrol region.

**Behavior:**
1. On entering IDLE (or when current wander target is reached), pick a new random point within `wander_radius` of the ship's **spawn position** (not current position — prevents drift)
2. Set that point as the aim target — the ship's assisted steering rotates toward it
3. Apply forward thrust at `wander_thrust_fraction` of max (e.g. 0.4 = leisurely cruise)
4. When within `wander_arrival_distance` of the target point, pause for `wander_pause_duration` seconds, then pick a new point
5. Each frame, check if the player is within `detection_range`

**Transition to PURSUE:** Player enters `detection_range`.

```gdscript
func _idle_process(delta: float) -> void:
    if _target_in_detection_range():
        _transition_to(State.PURSUE)
        return

    if position.distance_to(_wander_target) < profile.wander_arrival_distance:
        _wander_pause_timer -= delta
        if _wander_pause_timer <= 0.0:
            _pick_new_wander_target()
    else:
        _steer_toward(_wander_target)
        _set_thrust(profile.wander_thrust_fraction)
```

### State: PURSUE

The ship has detected the player and is closing distance to engage.

**Behavior:**
1. Set the player ship as the aim target
2. Apply forward thrust at `pursue_thrust_fraction` (e.g. 0.85 = aggressive approach)
3. Each frame, check distance to player:
   - If within `engage_distance` → transition to ENGAGE
   - If player moves beyond `leash_range` → give up, transition to IDLE

**Leash range** prevents AI ships from chasing the player across the entire map. It's measured from the ship's **spawn position**, not from where detection occurred.

**Transition to ENGAGE:** Player within `engage_distance`.
**Transition to IDLE:** Player beyond `leash_range` from ship's spawn point.

```gdscript
func _pursue_process(delta: float) -> void:
    var dist_to_player = position.distance_to(_target_player.position)
    var dist_from_home = position.distance_to(_spawn_position)

    if dist_from_home > profile.leash_range:
        _transition_to(State.IDLE)
        return

    if dist_to_player <= profile.engage_distance:
        _transition_to(State.ENGAGE)
        return

    _steer_toward(_target_player.position)
    _set_thrust(profile.pursue_thrust_fraction)
```

### State: ENGAGE

The ship is in combat range and actively fighting the player.

**Behavior:**
1. Aim at the player ship (with lead prediction — see Aim Prediction below)
2. Maintain distance near `preferred_engage_distance`:
   - If too close (< `preferred_engage_distance * 0.7`): apply reverse thrust
   - If too far (> `preferred_engage_distance * 1.3`): apply forward thrust
   - If in the sweet spot: apply light strafe thrust to circle the player
3. Fire weapons when aim angle error is within `fire_angle_threshold` degrees
4. Each frame, check if player is still alive and within `leash_range`

**Distance maintenance** keeps the AI from just sitting on top of the player. The circling behavior (lateral thrust in the sweet spot) makes fights feel dynamic without requiring complex maneuvering AI.

**Transition to IDLE:** Player destroyed, or player moves beyond `leash_range` from spawn.

```gdscript
func _engage_process(delta: float) -> void:
    if not is_instance_valid(_target_player) or _target_player.is_dead:
        _transition_to(State.IDLE)
        return

    var dist_from_home = position.distance_to(_spawn_position)
    if dist_from_home > profile.leash_range:
        _transition_to(State.IDLE)
        return

    var dist_to_player = position.distance_to(_target_player.position)
    var predicted_pos = _predict_aim_position(_target_player)

    _steer_toward(predicted_pos)

    # Distance maintenance
    var ratio = dist_to_player / profile.preferred_engage_distance
    if ratio < 0.7:
        _set_thrust(-profile.engage_thrust_fraction)   # reverse away
    elif ratio > 1.3:
        _set_thrust(profile.engage_thrust_fraction)     # close in
    else:
        _set_thrust(0.0)
        _set_strafe(_circle_direction * profile.strafe_thrust_fraction)

    # Fire decision
    var aim_error = abs(angle_difference(rotation, predicted_pos.angle()))
    if aim_error <= deg_to_rad(profile.fire_angle_threshold):
        _fire_weapons()
```

---

## Aim Prediction

AI ships use simple linear prediction to lead their shots. This makes them feel competent without being oppressively accurate.

```gdscript
func _predict_aim_position(target: Node2D) -> Vector2:
    var to_target = target.position - position
    var distance = to_target.length()

    # Use the AI's primary weapon muzzle speed for prediction
    var muzzle_speed = _get_primary_muzzle_speed()
    if muzzle_speed <= 0.0:
        return target.position

    var travel_time = distance / muzzle_speed
    var predicted = target.position + target.velocity * travel_time * profile.aim_accuracy

    return predicted
```

`aim_accuracy` is a float from 0.0 to 1.0 in the behavior profile:
- `1.0` = perfect lead prediction (hard difficulty)
- `0.7` = decent prediction, occasionally misses moving targets (default)
- `0.3` = mostly shoots where the player is, not where they'll be (easy)

This single parameter controls difficulty more than any other value — adjust it first during playtesting.

---

## Detection System

Detection uses a simple `Area2D` circle collider on each AI ship. No facing cone, no line-of-sight checks at MVP.

```
DetectionArea (Area2D)
    └── CollisionShape2D (CircleShape2D, radius = detection_range)
```

- The `Area2D` is set to detect only the player's collision layer
- On `body_entered`: flag player as detected, store reference
- On `body_exited`: clear detection flag (only matters in IDLE — PURSUE and ENGAGE use leash range instead)

This is cheaper than per-frame distance checks against every AI ship — the physics engine handles broadphase.

**Future extension point:** Replace the `Area2D` circle with a more complex shape (facing cone, reduced range behind the ship) by swapping the `CollisionShape2D`. The state machine doesn't care how detection works — it just checks `_target_in_detection_range()`.

---

## Behavior Profile (JSON)

All AI tuning values live in `ai_profiles.json`. MVP ships reference the `"default"` profile.

```json
{
  "ai_profiles": [
    {
      "id": "default",
      "display_name": "Standard Patrol",

      "detection_range": 800,
      "leash_range": 1500,
      "engage_distance": 500,
      "preferred_engage_distance": 350,

      "wander_radius": 600,
      "wander_thrust_fraction": 0.4,
      "wander_arrival_distance": 40,
      "wander_pause_min": 1.0,
      "wander_pause_max": 3.0,

      "pursue_thrust_fraction": 0.85,

      "engage_thrust_fraction": 0.7,
      "strafe_thrust_fraction": 0.3,
      "fire_angle_threshold": 15,

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
- `flee_enabled` / `flee_hp_threshold` — when flee state is implemented
- `faction` — when faction-specific fighting styles are added
- `personality` — when behavioral variants within a faction are added (e.g. "aggressive", "cautious", "sniper")

Adding a new archetype post-MVP is just adding a new entry to this array and assigning it to ships.

---

## Spawning & Patrol Region Assignment

AI ships need to know their spawn position (for wander origin and leash range) and their patrol region. At MVP, this is handled simply:

### MVP Approach

AI ships are placed in the test scene manually or by a simple spawner script. Each ship stores its initial position as `_spawn_position` on `_ready()`.

```gdscript
# AIController.gd
var _spawn_position: Vector2

func _ready() -> void:
    _spawn_position = global_position
    _load_profile(profile_id)
    _pick_new_wander_target()
    _current_state = State.IDLE
```

### Future: Patrol Region Nodes

For the streaming map, patrol regions will be defined as `Area2D` zones placed in chunk scenes. When a chunk loads, its patrol regions spawn AI ships at random points within their bounds. When the chunk unloads, those ships are freed. The AI controller will reference the region bounds instead of a fixed wander radius.

This is not implemented at MVP — the architecture just needs to not prevent it. Keeping `_spawn_position` and `wander_radius` as the wander bounds (rather than hardcoding anything about scene structure) is sufficient.

---

## Ship ↔ AI Interface

The AI controller needs to talk to the ship's existing systems. It does this through a clean interface — the AI never reaches into physics internals.

### Inputs AI Provides to Ship

```gdscript
# AIController sets these each frame; Ship.gd reads them in _physics_process
var ai_forward_input: float = 0.0     # -1.0 to 1.0
var ai_strafe_input: float = 0.0      # -1.0 to 1.0
var ai_aim_target: Vector2 = Vector2.ZERO
var ai_fire_primary: bool = false
```

`Ship.gd` already processes inputs for the player. The change is minimal:

```gdscript
# Ship.gd — in _physics_process()
var forward_input: float
var strafe_input: float
var aim_target: Vector2

if is_player:
    forward_input = Input.get_axis("thrust_reverse", "thrust_forward")
    strafe_input = Input.get_axis("strafe_left", "strafe_right")
    aim_target = get_global_mouse_position()
else:
    forward_input = ai_controller.ai_forward_input
    strafe_input = ai_controller.ai_strafe_input
    aim_target = ai_controller.ai_aim_target
```

This guarantees AI ships obey the same physics — same thruster budget, same angular inertia, same drag. No cheating.

### Events AI Emits

AI state transitions are broadcast via `GameEventBus` for UI, audio, and future systems:

```gdscript
GameEventBus.emit("ai_state_changed", {
    "ship_id": owner.get_instance_id(),
    "old_state": old_state_name,
    "new_state": new_state_name
})

GameEventBus.emit("ai_target_acquired", {
    "ship_id": owner.get_instance_id(),
    "target_id": _target_player.get_instance_id()
})

GameEventBus.emit("ai_target_lost", {
    "ship_id": owner.get_instance_id()
})
```

---

## Circle Direction

When the AI is in the ENGAGE sweet spot and strafing to circle the player, it picks a circle direction (clockwise or counter-clockwise) on entering ENGAGE and sticks with it until it exits the state.

```gdscript
func _on_enter_engage() -> void:
    _circle_direction = 1.0 if randf() > 0.5 else -1.0
```

This prevents the AI from jittering between directions. Future personality profiles could bias this (e.g. "always circle left" for predictable enemies, "reverse direction periodically" for aggressive ones).

---

## State Transition Table

Defined as data, not hardcoded `if` chains. This makes adding new states clean:

```gdscript
# AIController.gd
enum State { IDLE, PURSUE, ENGAGE, FLEE, REGROUP, SEARCH, ORBIT }

var _transitions: Dictionary = {
    State.IDLE: {
        "player_detected": State.PURSUE,
    },
    State.PURSUE: {
        "in_engage_range": State.ENGAGE,
        "target_leashed": State.IDLE,
    },
    State.ENGAGE: {
        "target_lost": State.IDLE,
        "target_destroyed": State.IDLE,
        # Future: "hp_below_threshold": State.FLEE,
    },
    # Future states defined here when implemented
}

func _transition_to(new_state: State) -> void:
    var old_state = _current_state
    _on_exit_state(_current_state)
    _current_state = new_state
    _on_enter_state(new_state)
    GameEventBus.emit("ai_state_changed", {
        "ship_id": owner.get_instance_id(),
        "old_state": State.keys()[old_state],
        "new_state": State.keys()[new_state]
    })
```

---

## Performance Instrumentation

Per the PerformanceMonitor integration contract:

```gdscript
# AIController.gd — wrap the full AI update for all ships
# Called from a manager or from each AIController individually:

# Option A: Each AIController instruments itself
func _physics_process(delta: float) -> void:
    PerformanceMonitor.begin("AIController.state_updates")
    match _current_state:
        State.IDLE: _idle_process(delta)
        State.PURSUE: _pursue_process(delta)
        State.ENGAGE: _engage_process(delta)
    PerformanceMonitor.end("AIController.state_updates")
```

**Note:** With many AI ships, each calling `begin()`/`end()` per frame, the timing will accumulate across all ships within one frame (since `begin` captures a start time and `end` adds the elapsed). This is correct — the metric should reflect **total AI time per frame**, not per-ship time.

```gdscript
# In the scene manager or AI spawner, once per frame:
PerformanceMonitor.set_count("AIController.active_count",
    get_tree().get_nodes_in_group("ai_ships").size())
```

Register in `_ready()`:
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
/data/
    ai_profiles.json
```

---

## Dependencies

- `Ship.gd` from Physics spec — AI feeds inputs through the same interface as the player
- `PerformanceMonitor` registered before any AI ship enters the scene tree
- `GameEventBus` for state transition events
- `WeaponComponent.gd` — AI calls `fire()` through the same weapon interface the player uses
- Player ship must be findable (e.g. in a `"player"` group or via a global reference)

---

## Assumptions (Revisit During Balancing)

- All distance values (detection, leash, engage) are placeholder — tune after first playtest
- `aim_accuracy` of 0.7 is a guess — this is the primary difficulty knob, adjust first
- `preferred_engage_distance` of 350 assumes medium-range weapons — will need to scale with loadout post-MVP
- Wander pause duration range (1–3 seconds) is arbitrary — affects how "alive" idle AI feels
- Strafe thrust fraction of 0.3 during circling is conservative — increase for more dynamic fights
- Single circle direction per engage session may feel predictable — acceptable for MVP

---

## Future Extension Points

These are explicitly **not** in scope for MVP but the architecture accommodates them:

| Feature | How It Fits |
|---|---|
| **Flee behavior** | Add `FLEE` state, activate when `flee_enabled && hp < flee_hp_threshold` |
| **Faction fighting styles** | New profiles in `ai_profiles.json` — "pirate_aggressive", "militia_cautious", etc. |
| **Personality variants** | Multiple profiles per faction with weighted random selection at spawn |
| **Squad coordination** | `REGROUP` state + shared target list between ships in a patrol group |
| **Cover usage** | `SEARCH` state + raycast checks for asteroid occlusion during ENGAGE |
| **Difficulty scaling** | Adjust `aim_accuracy`, thrust fractions, and engage distances per difficulty level |
| **Conditional orders** | Add priority interrupts to transition table (e.g. "if ally under attack → assist") |

---

## Success Criteria

- [ ] AI ships wander visibly within their patrol region when no player is nearby
- [ ] AI ship detects player entering detection range and transitions to PURSUE
- [ ] AI ship closes distance to player and transitions to ENGAGE at correct range
- [ ] AI ship maintains preferred distance during combat — backs off when too close, approaches when too far
- [ ] AI ship leads shots with aim prediction — hits are frequent but not perfect
- [ ] AI ship fires weapons only when facing approximately toward the player
- [ ] AI ship returns to IDLE wander when player moves beyond leash range
- [ ] AI ship uses the same physics as the player — no teleporting, no instant turns
- [ ] AI state transitions are visible in the PerformanceMonitor overlay
- [ ] 15+ simultaneous AI ships run within frame budget at 60fps
- [ ] All AI tuning values are modifiable in `ai_profiles.json` without recompile
- [ ] Adding a second behavior profile requires only a new JSON entry and assigning it to a ship