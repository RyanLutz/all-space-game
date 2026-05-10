# AI Flight Refactor — Feature Specification
*All Space Combat MVP — Dissolve NavigationController; fold flight logic into AIController*

---

## 1. Overview

`NavigationController.gd` is dissolved. Its flight logic — rotation toward a
destination, acceleration, and braking — moves directly into `AIController.gd`.

The motivation is simplicity: there is no meaningful distinction between "deciding
where to go" and "figuring out how to get there" at this scale. A single actor —
AIController — now owns the full flight loop for AI ships. When the player requests
autopilot (Tactical mode move orders), the same AIController code path steers the
player's ship. No duplication.

**Design goals:**
- AI ships navigate correctly: they rotate toward a destination, thrust, and brake
  without overshooting or sliding
- Player autopilot reuses the AI flight code — no separate navigator
- The unified ship input interface is unchanged (`input_forward`, `input_strafe`,
  `input_aim_target`, `input_fire`)
- All tuning values remain in JSON; no hardcoded constants

---

## 2. Architecture

### Before

```
AI Ship (RigidBody3D)
    ├── Ship.gd
    ├── AIController.gd           — decides where to go
    └── NavigationController.gd   — flight + signal listener (tactical/formation/warp)

Player Ship (RigidBody3D)
    ├── Ship.gd
    └── NavigationController.gd   — autopilot via signals
```

### After

```
AI Ship (RigidBody3D)
    ├── Ship.gd
    └── AIController.gd           — flight + state machine + signal listener

Player Ship (RigidBody3D)
    ├── Ship.gd
    └── AIController.gd           — autopilot-only mode (combat AI disabled)
```

`NavigationController.gd` is deleted. AIController absorbs all four legacy
NavigationController drive modes (EXTERNAL/TACTICAL_ORDER/FORMATION/EMERGENCY_STOP)
as a single prioritized override stack. The signal architecture is preserved —
EscortQueue, FormationController, and WarpDrive emit the same signals; AIController
now listens instead of NavigationController.

### Responsibility Table (updated)

| Concern | Owner |
|---|---|
| Where to go (destination) | AIController override stack |
| How to get there (rotation, thrust, braking) | AIController flight methods |
| What to face (aim target) | AIController state machine / autopilot |
| Whether to fire | AIController state machine |
| Player autopilot steering | AIController (autopilot mode) |
| Formation slot following (escort) | AIController (formation mode) |
| Emergency brake on warp interrupt | AIController (emergency-stop mode) |
| Translate inputs → forces/torques | Ship.gd (unchanged) |
| Integrate forces → position | Jolt (unchanged) |

### Override Priority Stack

AIController evaluates these each `_physics_process`, highest first:

1. **EMERGENCY_STOP** — set by WarpDrive on interrupt; brakes velocity to zero
2. **TACTICAL_ORDER** — `request_tactical_move` from player Tactical input or warp queue
3. **TACTICAL_ATTACK** — `request_tactical_attack` (existing state, unchanged)
4. **FORMATION** — `request_formation_destination` from FormationController (escort queue only)
5. **AI state machine** — IDLE / PURSUE / ENGAGE (only when no override active)

TACTICAL_ORDER preempts FORMATION. EMERGENCY_STOP preempts everything.

---

## 3. Core Properties / Data Model

The following replaces NavigationController's properties; they live in AIController:

```gdscript
# AIController.gd — flight state (replaces NavigationController)
enum FlightMode { NONE, TACTICAL_ORDER, FORMATION, EMERGENCY_STOP }

var _destination: Vector3       # current flight target; Y = 0 always
var _arrived: bool = false      # true when within arrival_distance
var _thrust_fraction: float     # 0.0–1.0; set per state from profile
var _flight_mode: FlightMode = FlightMode.NONE   # active override; NONE = run state machine

# Convenience flag (true when _flight_mode != NONE; kept for spec readability).
# Implementation may simply check _flight_mode != FlightMode.NONE.
```

`autopilot_enabled` from earlier draft is replaced by `_flight_mode`. The override
stack is a single state field rather than several booleans, because the modes are
mutually exclusive — one wins, the others wait.

Tuning constants are loaded from `ai_profiles.json` (see Section 5). No values
are hardcoded in the script.

---

## 4. Key Algorithms

### 4.1 Flight Update (called each physics frame, replaces NavigationController.update)

```gdscript
func _flight_update(delta: float) -> void:
    var to_dest: Vector3 = _destination - owner.global_position
    to_dest.y = 0.0
    var distance: float = to_dest.length()

    # --- Arrival ---
    if distance <= profile.arrival_distance:
        owner.input_forward = 0.0
        owner.input_strafe  = 0.0
        _arrived = true
        return

    _arrived = false
    var dir_to_dest: Vector3 = to_dest / distance   # normalized

    # --- Braking check ---
    # Estimate stopping distance from current speed and thruster capability.
    # Begin braking when we would overshoot if we kept thrusting.
    var speed: float = owner.linear_velocity.length()
    var decel_force: float = owner.thruster_force / owner.mass
    var stopping_dist: float = (speed * speed) / (2.0 * decel_force)
    stopping_dist *= profile.brake_safety_margin

    var braking: bool = distance <= stopping_dist

    # --- Compute desired world-space thrust vector ---
    var thrust_dir: Vector3
    if braking:
        # Oppose current velocity to decelerate
        if speed > 0.001:
            thrust_dir = -owner.linear_velocity.normalized()
        else:
            thrust_dir = Vector3.ZERO
    else:
        thrust_dir = dir_to_dest

    # --- Project onto ship local axes ---
    # Ship forward is -transform.basis.z (Godot 3D convention).
    # Positive input_forward = thrust along ship forward.
    var ship_fwd: Vector3   = -owner.transform.basis.z
    var ship_right: Vector3 =  owner.transform.basis.x

    owner.input_forward = thrust_dir.dot(ship_fwd)  * _thrust_fraction
    owner.input_strafe  = thrust_dir.dot(ship_right) * _thrust_fraction
```

### 4.2 Rotation Toward Destination

Navigation facing is set by writing `input_aim_target` to the destination. This
reuses the ship's existing rotation-toward-aim logic — no new rotation code needed.

```gdscript
func _face_destination() -> void:
    owner.input_aim_target = _destination
```

Each state that uses `_flight_update` calls `_face_destination()` first unless it
has a different aim target (e.g., ENGAGE faces the player while navigating).

### 4.3 State Integration Example

```gdscript
func _idle_process(delta: float) -> void:
    _thrust_fraction = profile.wander_thrust_fraction
    _face_destination()           # face the wander target
    _flight_update(delta)         # compute forward/strafe

    if _arrived:
        _pause_timer -= delta
        if _pause_timer <= 0.0:
            _pick_new_wander_target()

func _pursue_process(delta: float) -> void:
    _destination     = _target_player.global_position
    _thrust_fraction = profile.pursue_thrust_fraction
    _face_destination()
    _flight_update(delta)
    # transition to ENGAGE handled separately

func _engage_process(delta: float) -> void:
    _destination     = _compute_orbit_position()
    _thrust_fraction = profile.engage_thrust_fraction
    owner.input_aim_target = _target_player.global_position   # face player, not destination
    _flight_update(delta)
    # AIController may overwrite input_strafe after this for orbit thrust
```

### 4.4 Tactical Order Mode (Player + AI)

`TacticalInputHandler` continues to emit `request_tactical_move` on the
GameEventBus — this is the public contract that EscortQueue and other listeners
rely on. AIController subscribes to it.

```gdscript
# AIController.gd — _ready()
_event_bus.connect("request_tactical_move", _on_request_tactical_move)
_event_bus.connect("request_tactical_stop", _on_request_tactical_stop)
_event_bus.connect("request_formation_destination", _on_request_formation_destination)

func _on_request_tactical_move(ship_ids: Array, destination: Vector3, _queue_mode: String) -> void:
    var my_id := get_parent().get_instance_id()
    if my_id not in ship_ids:
        return

    # Defer to warp if active — queue the move for after warp ends
    var warp: WarpDrive = get_parent().get_node_or_null("WarpDrive") as WarpDrive
    if warp != null and warp.is_warp_active():
        warp.queue_move(destination)
        return

    _destination       = Vector3(destination.x, 0.0, destination.z)
    _arrived           = false
    _flight_mode       = FlightMode.TACTICAL_ORDER
    _thrust_fraction   = float(profile.get("autopilot_thrust_fraction",
                          profile.get("pursue_thrust_fraction", 0.85)))

func _on_request_tactical_stop(ship_ids: Array) -> void:
    var my_id := get_parent().get_instance_id()
    if my_id not in ship_ids:
        return
    if _flight_mode == FlightMode.TACTICAL_ORDER:
        _clear_flight_override()
```

In `_physics_process`, when `_flight_mode == TACTICAL_ORDER`:

```gdscript
_face_destination()
_flight_update(delta)
if _arrived:
    _flight_mode = FlightMode.NONE
    _event_bus.navigation_order_completed.emit(get_parent().get_instance_id())
return  # skip state machine
```

`navigation_order_completed` MUST be emitted on arrival — EscortQueue listens for
it to clear the "away on orders" flag.

Player autopilot disengages on arrival OR on any direct pilot input
(`TacticalInputHandler` calls a helper to clear the flight mode).

### 4.5 Formation Mode (Escort Following Player)

`FormationController` ticks ~4Hz and emits `request_formation_destination` per
slot. AIController listens; FORMATION has lower priority than TACTICAL_ORDER:

```gdscript
func _on_request_formation_destination(ship_id: int, destination: Vector3) -> void:
    if get_parent().get_instance_id() != ship_id:
        return
    if _flight_mode == FlightMode.TACTICAL_ORDER \
       or _flight_mode == FlightMode.EMERGENCY_STOP:
        return    # higher-priority override active

    _destination     = Vector3(destination.x, 0.0, destination.z)
    _arrived         = false
    _flight_mode     = FlightMode.FORMATION
    _thrust_fraction = float(profile.get("formation_thrust_fraction",
                       profile.get("pursue_thrust_fraction", 0.85)))
```

FORMATION mode does NOT emit `navigation_order_completed` on arrival — formation
slots are continuously refreshed by FormationController, and EscortQueue does not
flag formation-following as "away on orders."

### 4.6 Emergency Stop (Warp Interrupt)

When warp is interrupted (damage, exclusion zone, key release), WarpDrive must
brake the ship to a halt. Replaces the legacy `_nav._drive_mode = EMERGENCY_STOP`
hack with a public method:

```gdscript
# AIController.gd
func request_emergency_stop() -> void:
    _flight_mode = FlightMode.EMERGENCY_STOP
    _arrived     = false

func _emergency_stop_update(_delta: float) -> void:
    var ship := get_parent() as RigidBody3D
    var velocity := ship.linear_velocity
    velocity.y = 0.0
    var speed := velocity.length()
    if speed < 1.0:
        ship.input_forward = 0.0
        ship.input_strafe  = 0.0
        _flight_mode = FlightMode.NONE
        return
    var brake_dir := -velocity.normalized()
    ship.input_forward = brake_dir.dot(-ship.transform.basis.z)
    ship.input_strafe  = brake_dir.dot( ship.transform.basis.x)
```

WarpDrive replaces the two-line nav coupling with a single method call:

```gdscript
# WarpDrive.gd — _enter_decelerating()
var ai: AIController = _ship.get_node_or_null("AIController") as AIController
if ai != null:
    ai.request_emergency_stop()
```

WarpDrive's `_update_decelerating` previously polled `_nav.has_arrived()`. Replace
with a check that velocity has dropped below a threshold (or that AIController's
`_flight_mode` has returned to NONE). Implementation detail: expose
`AIController.is_idle() -> bool` returning `_flight_mode == FlightMode.NONE`.

### 4.7 Unified `_physics_process` Dispatch

```gdscript
func _physics_process(delta: float) -> void:
    _perf.begin("AIController.state_updates")

    match _flight_mode:
        FlightMode.EMERGENCY_STOP:
            _emergency_stop_update(delta)
        FlightMode.TACTICAL_ORDER:
            _face_destination()
            _flight_update(delta)
            if _arrived:
                _flight_mode = FlightMode.NONE
                _event_bus.navigation_order_completed.emit(get_parent().get_instance_id())
        FlightMode.FORMATION:
            _face_destination()
            _flight_update(delta)
            # no completion signal; formation refreshes destination each tick
        FlightMode.NONE:
            if not get_parent().is_player:
                match _current_state:
                    State.IDLE:             _idle_process(delta)
                    State.PURSUE:           _pursue_process(delta)
                    State.ENGAGE:           _engage_process(delta)
                    State.TACTICAL_ATTACK:  _tactical_attack_process(delta)
            # player ship in NONE mode: no flight input written; player drives directly

    _perf.end("AIController.state_updates")
```

Player ships skip the AI state machine entirely. They only ever flight-update
when an override mode is active.

---

## 5. JSON Data Format

All flight tuning values move into `ai_profiles.json`. Add the following fields
to every profile that needs them (add to the existing `"default"` profile):

```json
{
  "id": "default",

  "arrival_distance":    25.0,
  "brake_safety_margin": 1.25,

  "wander_thrust_fraction":     0.4,
  "pursue_thrust_fraction":     0.85,
  "engage_thrust_fraction":     0.7,
  "autopilot_thrust_fraction":  0.75,
  "formation_thrust_fraction":  0.85
}
```

`arrival_distance` and `brake_safety_margin` vary by ship class — a destroyer
needs a wider arrival bubble and earlier braking than a fighter. Per-class profiles
already support this without code changes.

Remove `arrival_distance` and `brake_safety_margin` from the `hull` block in
`ship.json` — they now live in `ai_profiles.json` and are the AI/autopilot's
concern, not the hull's.

---

## 6. Performance Instrumentation

`Navigation.update` metric is retired. Replace with coverage under the existing
`AIController.state_updates` metric, which already wraps the full per-ship
state-machine update. The flight logic is now part of that work; no separate
metric is needed.

```gdscript
func _physics_process(delta: float) -> void:
    PerformanceMonitor.begin("AIController.state_updates")
    if autopilot_enabled:
        _face_destination()
        _flight_update(delta)
    else:
        match _current_state:
            State.IDLE:    _idle_process(delta)
            State.PURSUE:  _pursue_process(delta)
            State.ENGAGE:  _engage_process(delta)
    PerformanceMonitor.end("AIController.state_updates")
```

Remove `AllSpace/nav_update_ms` from `GameBootstrap._register_custom_monitors()`.

---

## 7. Files

| Action | File |
|---|---|
| **Delete** | `gameplay/ai/NavigationController.gd` (and `.uid`) |
| **Modify** | `gameplay/ai/AIController.gd` — add `FlightMode` enum, `_flight_update`, `_face_destination`, `_emergency_stop_update`, `request_emergency_stop`, `is_idle`; subscribe to `request_tactical_move`, `request_tactical_stop`, `request_formation_destination`; emit `navigation_order_completed` on tactical-order arrival; remove direct `nav_controller` references; replace `has_tactical_order()` checks with `_flight_mode != NONE` checks |
| **Modify** | `gameplay/entities/ShipFactory.gd` — remove `NavigationController` attachment for both player and AI ships; ensure player ship gets an `AIController` (autopilot-only — guard combat-init in `AIController._ready` on `ship.is_player`) |
| **Modify** | `gameplay/world/WarpDrive.gd` — drop `_nav` field; replace `_nav.queue_move` callsite (warp itself still owns the queue, no change there); replace `_nav._drive_mode = EMERGENCY_STOP` with `ai.request_emergency_stop()`; replace `_nav.has_arrived()` poll with `ai.is_idle()` (or velocity threshold); replace `_nav.set_destination/set_thrust_fraction` in `_enter_active` (warp ACTIVE no longer needs nav — Ship physics drives forward directly under warp thrust) |
| **Verify** | `gameplay/fleet_command/TacticalInputHandler.gd` — no change (still emits `request_tactical_move`) |
| **Verify** | `gameplay/fleet_command/FormationController.gd` — no change (still emits `request_formation_destination`) |
| **Verify** | `gameplay/fleet_command/EscortQueue.gd` — no change (still listens to `navigation_order_completed`) |
| **Modify** | `data/ai_profiles.json` — add `arrival_distance`, `brake_safety_margin`, `autopilot_thrust_fraction`, `formation_thrust_fraction` |
| **Modify** | `data/ship.json` — remove `arrival_distance`, `brake_safety_margin` from `hull` block |
| **Modify** | `core/GameBootstrap.gd` — remove `AllSpace/nav_update_ms` monitor registration |
| **Modify** | `ui/debug/PerformanceOverlay.gd` — remove `Navigation.update` row |
| **Modify** | `core/services/PerformanceMonitor.gd` — drop NavigationController mention from doc comment |
| **Modify** | `test/ShipPhysicsTest.gd` — replace `NavigationController` instantiation with `AIController` autopilot driver, OR drop nav-driven test path |
| **Modify** | `test/PerformanceMonitorTest.gd` — replace `Navigation.update` metric usage with `AIController.state_updates` |
| **Modify** | `docs/spec/feature_spec-nav_controller.md` — mark deprecated/superseded by this spec, or delete |
| **Modify** | `docs/spec/feature_spec-fleet_command.md` — update flight-routing description |
| **Modify** | `docs/spec/feature_spec-ai_patrol_behavior.md` — update flight-call examples |
| **Modify** | `docs/SYSTEMS.md` — remove NavigationController row |
| **Modify** | `docs/decisions_log.md` — record this dissolution |
| **Modify** | `docs/agent_brief.md` — update build status |

---

## 8. Dependencies

- `AIController.gd` must exist (build step 11 — already complete)
- `TacticalInputHandler.gd` must exist (build step 13 — already complete)
- `ShipFactory.gd` must be updated before any test scene is run — it currently
  attaches `NavigationController` as a child node; that attachment must be removed

---

## 9. Assumptions

- `arrival_distance = 25.0` and `brake_safety_margin = 1.25` are carried over from
  the NavigationController spec as starting values. Tune against the test scene.
- Autopilot uses `pursue_thrust_fraction` as a default; a dedicated
  `autopilot_thrust_fraction` field is provided in JSON if the feel needs to differ.
- The braking approximation (constant decel, ignoring drag) is intentional. The
  safety margin absorbs the error. Ships may arrive slightly past the threshold on
  very high speeds — acceptable at MVP.
- Player ships with autopilot enabled do not participate in the AI combat state
  machine. They navigate only. Combat decisions remain with the player.
- Player ship's `AIController._ready` skips detection-volume hookup and combat-state
  initialization when `ship.is_player == true`. Only signal listeners (tactical
  move, tactical stop, formation, emergency stop) and flight methods are active.
- WarpDrive's ACTIVE phase no longer routes thrust through NavigationController.
  Warp directly boosts `thruster_force` and the ship's existing forward-thrust
  input drives motion. Plotted-warp arrival check (line 200-205 of WarpDrive)
  remains; no nav coupling needed during ACTIVE.
- `request_tactical_move` remains the canonical signal. AIController is now the
  sole listener; EscortQueue's tracking and WarpDrive's queued-move replay
  continue to work because both sides of the contract (emit + listen) remain on
  the GameEventBus.
- The `ai_profiles.json` `default` profile is loaded for player ships in
  autopilot mode if no per-ship profile applies. `arrival_distance` and
  `brake_safety_margin` default values match the legacy ship.json hull values
  (25.0 / 1.25).

---

## 10. Success Criteria

- [ ] `NavigationController.gd` is deleted; no file in the project references it
- [ ] AI ships rotate toward their destination before thrusting — no sideways sliding
- [ ] AI ships brake before arrival and do not overshoot the destination
- [ ] A fighter and a destroyer both arrive correctly with their respective JSON profiles
- [ ] Player ship in Tactical mode navigates to shift-click destinations using the
      same `AIController` flight code
- [ ] Autopilot disengages on arrival; player regains direct control immediately
- [ ] `Navigation.update` metric is gone from the F3 overlay and Godot debugger
- [ ] `AIController.state_updates` metric still appears and reflects total AI cost
- [ ] All tuning values (`arrival_distance`, `brake_safety_margin`, thrust fractions)
      are editable in `ai_profiles.json` without recompile
- [ ] `input_aim_target` and `input_fire` are never written by the flight methods
- [ ] 15+ simultaneous AI ships navigate correctly within 60fps frame budget
- [ ] Escort queue ships fly formation in Pilot mode (FORMATION override drives them)
- [ ] Escort queue ship receiving a tactical move order leaves formation, completes
      the order, and rejoins formation on the next FormationController tick
      (signaled by `navigation_order_completed` clearing the away-on-orders flag)
- [ ] Warp interrupt (damage / exclusion / key-release) brakes the ship to a halt
      via `request_emergency_stop` — same feel as legacy NavigationController EMERGENCY_STOP
- [ ] Warp completion with a queued move order flies the ship to the queued
      destination (TacticalInputHandler emits → AIController receives → arrives → emits completion)
- [ ] No file in the project references `NavigationController`, `nav_controller`,
      `has_tactical_order`, or `Navigation.update`
