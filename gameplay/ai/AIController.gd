extends Node
class_name AIController

## Unified flight + AI controller. Owns the full flight loop:
##   - AI state machine (IDLE / PURSUE / ENGAGE / TACTICAL_ATTACK)
##   - Tactical-order autopilot   (player + AI ships, signal-driven)
##   - Formation following        (escort queue ships, signal-driven)
##   - Emergency stop             (warp interrupt)
##
## Replaces the dissolved NavigationController. AIController is attached to
## every ship (player + AI). Player ships skip the combat state machine but
## still receive flight overrides via signals.

# ─── State Machine ─────────────────────────────────────────────────────────
enum State { IDLE, PURSUE, ENGAGE, FLEE, REGROUP, SEARCH, ORBIT, TACTICAL_ATTACK }

# ─── Flight Override Stack ─────────────────────────────────────────────────
# Priority (highest first): EMERGENCY_STOP > TACTICAL_ORDER > FORMATION > NONE.
# TACTICAL_ATTACK is a state-machine state, not a flight override — it shares
# the AI ship's state machine slot and is set by signal.
enum FlightMode { NONE, TACTICAL_ORDER, FORMATION, EMERGENCY_STOP }

var _flight_mode: FlightMode = FlightMode.NONE
var _destination: Vector3 = Vector3.ZERO
var _arrived: bool = false
var _thrust_fraction: float = 1.0

var _current_state: State = State.IDLE

# ─── References ────────────────────────────────────────────────────────────
var profile: Dictionary = {}
var _is_player: bool = false

# ─── Detection ─────────────────────────────────────────────────────────────
var _target_detected: bool = false
var _target: Node3D = null

# ─── Tactical ─────────────────────────────────────────────────────────────
var _tactical_target: Node3D = null

# ─── Patrol ────────────────────────────────────────────────────────────────
var _spawn_position: Vector3 = Vector3.ZERO
var _wander_target: Vector3 = Vector3.ZERO
var _wander_pause_timer: float = 0.0

# ─── Engage ────────────────────────────────────────────────────────────────
var _circle_direction: float = 1.0
var _primary_muzzle_speed: float = 600.0

# ─── Cached services ──────────────────────────────────────────────────────
var _perf: Node
var _event_bus: Node
var _stance_controller: Node = null


func _ready() -> void:
	var service_locator := Engine.get_singleton("ServiceLocator")
	_perf = service_locator.GetService("PerformanceMonitor")
	_event_bus = service_locator.GetService("GameEventBus")
	_stance_controller = service_locator.GetService("StanceController")

	var ship := get_parent()
	_is_player = ship.is_player if "is_player" in ship else false
	_spawn_position = ship.global_position
	_spawn_position.y = 0.0

	# Flight-mode signal listeners — both player and AI react.
	if _event_bus:
		_event_bus.connect("request_tactical_move", _on_request_tactical_move)
		_event_bus.connect("request_tactical_stop", _on_request_tactical_stop)
		_event_bus.connect("request_formation_destination", _on_request_formation_destination)

	# Combat-only init: detection, attack signals, wander target.
	if not _is_player:
		var detection := ship.get_node_or_null("DetectionVolume")
		if detection:
			detection.body_entered.connect(_on_detection_volume_body_entered)
			detection.body_exited.connect(_on_detection_volume_body_exited)

		if _event_bus:
			_event_bus.connect("request_tactical_attack", _on_request_tactical_attack)

		_cache_primary_muzzle_speed(ship)
		_pick_new_wander_target()
		_current_state = State.IDLE


# ─── Public API ────────────────────────────────────────────────────────────

func is_idle() -> bool:
	return _flight_mode == FlightMode.NONE


func request_emergency_stop() -> void:
	_flight_mode = FlightMode.EMERGENCY_STOP
	_arrived = false


func cancel_flight_override() -> void:
	# Called by InputManager when player takes manual control.
	if _flight_mode != FlightMode.NONE:
		_flight_mode = FlightMode.NONE
		_arrived = true


# ─── Physics Process ───────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	_perf.begin("AIController.state_updates")
	match _flight_mode:
		FlightMode.EMERGENCY_STOP:
			_emergency_stop_update()
		FlightMode.TACTICAL_ORDER:
			_face_destination()
			_flight_update()
			if _arrived:
				_flight_mode = FlightMode.NONE
				_event_bus.navigation_order_completed.emit(get_parent().get_instance_id())
		FlightMode.FORMATION:
			_face_destination()
			_flight_update()
			# Formation refreshes destination each tick — no completion signal.
		FlightMode.NONE:
			if not _is_player:
				match _current_state:
					State.IDLE:             _idle_process(delta)
					State.PURSUE:           _pursue_process(delta)
					State.ENGAGE:           _engage_process(delta)
					State.TACTICAL_ATTACK:  _tactical_attack_process(delta)
	_perf.end("AIController.state_updates")


# ─── Flight Methods ────────────────────────────────────────────────────────

func _face_destination() -> void:
	var ship := get_parent()
	if ship and "input_aim_target" in ship:
		ship.input_aim_target = _destination


func _flight_update() -> void:
	var ship := get_parent() as RigidBody3D

	var to_dest: Vector3 = _destination - ship.global_position
	to_dest.y = 0.0
	var distance: float = to_dest.length()

	var arrival_distance: float = float(profile.get("arrival_distance", 25.0))
	if distance <= arrival_distance:
		ship.input_forward = 0.0
		ship.input_strafe = 0.0
		_arrived = true
		return

	_arrived = false

	# Braking distance from constant-decel approximation, padded by margin.
	var velocity: Vector3 = ship.linear_velocity
	velocity.y = 0.0
	var speed: float = velocity.length()

	var max_decel: float = (ship.thruster_force * _thrust_fraction) / maxf(ship.mass, 0.001)
	var brake_safety: float = float(profile.get("brake_safety_margin", 1.25))
	var braking_distance: float = 0.0
	if max_decel > 0.0:
		braking_distance = (speed * speed) / (2.0 * max_decel) * brake_safety

	var ship_forward: Vector3 = -ship.transform.basis.z
	var ship_right: Vector3 = ship.transform.basis.x

	if distance <= braking_distance and speed > 0.1:
		var brake_dir: Vector3 = -velocity.normalized()
		ship.input_forward = brake_dir.dot(ship_forward) * _thrust_fraction
		ship.input_strafe = brake_dir.dot(ship_right) * _thrust_fraction
	else:
		var dest_dir: Vector3 = to_dest / distance
		ship.input_forward = dest_dir.dot(ship_forward) * _thrust_fraction
		ship.input_strafe = dest_dir.dot(ship_right) * _thrust_fraction


func _emergency_stop_update() -> void:
	var ship := get_parent() as RigidBody3D
	var velocity: Vector3 = ship.linear_velocity
	velocity.y = 0.0
	var speed: float = velocity.length()
	if speed < 1.0:
		ship.input_forward = 0.0
		ship.input_strafe = 0.0
		_flight_mode = FlightMode.NONE
		return
	var brake_dir: Vector3 = -velocity.normalized()
	ship.input_forward = brake_dir.dot(-ship.transform.basis.z)
	ship.input_strafe = brake_dir.dot(ship.transform.basis.x)


# ─── Internal flight setters (for combat states) ──────────────────────────

func _set_flight_target(dest: Vector3, thrust_fraction: float) -> void:
	_destination = Vector3(dest.x, 0.0, dest.z)
	_thrust_fraction = clampf(thrust_fraction, 0.0, 1.0)


# ─── State: IDLE ───────────────────────────────────────────────────────────

func _idle_process(delta: float) -> void:
	if _target_detected:
		_transition_to(State.PURSUE)
		return

	var ship := get_parent() as RigidBody3D
	var dist_to_target := ship.global_position.distance_to(_wander_target)

	if dist_to_target < profile.get("wander_arrival_distance", 40.0):
		_wander_pause_timer -= delta
		if _wander_pause_timer <= 0.0:
			_pick_new_wander_target()
		# Hold position while paused
		_set_flight_target(ship.global_position, 0.0)
	else:
		_set_flight_target(_wander_target, profile.get("wander_thrust_fraction", 0.4))

	# Face direction of travel while wandering
	ship.input_aim_target = _wander_target
	_flight_update()


func _pick_new_wander_target() -> void:
	var angle := randf() * TAU
	var dist: float = randf() * float(profile.get("wander_radius", 600.0))
	_wander_target = _spawn_position + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
	_wander_pause_timer = randf_range(
		profile.get("wander_pause_min", 1.0),
		profile.get("wander_pause_max", 3.0)
	)


# ─── State: PURSUE ─────────────────────────────────────────────────────────

func _pursue_process(_delta: float) -> void:
	if not is_instance_valid(_target):
		_transition_to(State.IDLE)
		return

	var ship := get_parent() as RigidBody3D
	var dist_from_home := ship.global_position.distance_to(_spawn_position)
	var dist_to_target := ship.global_position.distance_to(_target.global_position)

	if dist_from_home > profile.get("leash_range", 1500.0):
		_target_detected = false
		_transition_to(State.IDLE)
		return

	if dist_to_target <= profile.get("engage_distance", 500.0):
		_transition_to(State.ENGAGE)
		return

	_set_flight_target(_target.global_position, profile.get("pursue_thrust_fraction", 0.85))
	ship.input_aim_target = _target.global_position
	_flight_update()


# ─── State: ENGAGE ──────────────────────────────────────────────────────────

func _engage_process(_delta: float) -> void:
	var ship := get_parent() as RigidBody3D

	if not is_instance_valid(_target):
		_transition_to(State.IDLE)
		return

	if ship.global_position.distance_to(_spawn_position) > profile.get("leash_range", 1500.0):
		_transition_to(State.IDLE)
		return

	var predicted_pos := _predict_aim_position(_target)
	ship.input_aim_target = predicted_pos

	var dist_to_target := ship.global_position.distance_to(_target.global_position)
	var preferred: float = float(profile.get("preferred_engage_distance", 350.0))
	var ratio: float = dist_to_target / maxf(preferred, 1.0)
	var engage_thrust: float = float(profile.get("engage_thrust_fraction", 0.7))

	if ratio < 0.7:
		var away := (ship.global_position - _target.global_position).normalized()
		_set_flight_target(ship.global_position + away * 200.0, engage_thrust)
		_flight_update()
	elif ratio > 1.3:
		_set_flight_target(_target.global_position, engage_thrust)
		_flight_update()
	else:
		# Sweet spot — stop translation, orbit via strafe
		_set_flight_target(ship.global_position, 0.0)
		_flight_update()
		ship.input_strafe = _circle_direction * profile.get("strafe_thrust_fraction", 0.3)

	# Orbit always faces target — overrides _flight_update's facing.
	ship.input_aim_target = predicted_pos

	# Fire decision (check stance)
	if _should_hold_fire():
		ship.input_fire[0] = false
		return

	var to_predicted := predicted_pos - ship.global_position
	to_predicted.y = 0.0
	var ship_forward := -ship.transform.basis.z
	if to_predicted.length() > 0.001:
		var aim_error_rad := ship_forward.angle_to(to_predicted.normalized())
		if aim_error_rad <= deg_to_rad(profile.get("fire_angle_threshold", 15.0)):
			ship.input_fire[0] = true
		else:
			ship.input_fire[0] = false
	else:
		ship.input_fire[0] = false


# ─── State: TACTICAL_ATTACK ───────────────────────────────────────────────

func _tactical_attack_process(_delta: float) -> void:
	var ship := get_parent() as RigidBody3D

	if not is_instance_valid(_tactical_target):
		_tactical_target = null
		_transition_to(State.IDLE)
		if _event_bus:
			_event_bus.navigation_order_completed.emit(ship.get_instance_id())
		return

	var predicted_pos := _predict_aim_position(_tactical_target)

	var dist_to_target := ship.global_position.distance_to(_tactical_target.global_position)
	var preferred: float = float(profile.get("preferred_engage_distance", 350.0))
	var ratio: float = dist_to_target / maxf(preferred, 1.0)
	var engage_thrust: float = float(profile.get("engage_thrust_fraction", 0.7))

	if ratio < 0.7:
		var away := (ship.global_position - _tactical_target.global_position).normalized()
		_set_flight_target(ship.global_position + away * 200.0, engage_thrust)
		_flight_update()
	elif ratio > 1.3:
		_set_flight_target(_tactical_target.global_position, engage_thrust)
		_flight_update()
	else:
		_set_flight_target(ship.global_position, 0.0)
		_flight_update()
		ship.input_strafe = _circle_direction * profile.get("strafe_thrust_fraction", 0.3)

	ship.input_aim_target = predicted_pos

	# Fire decision (check stance)
	if _should_hold_fire():
		ship.input_fire[0] = false
		return

	var to_predicted := predicted_pos - ship.global_position
	to_predicted.y = 0.0
	var ship_forward := -ship.transform.basis.z
	if to_predicted.length() > 0.001:
		var aim_error_rad := ship_forward.angle_to(to_predicted.normalized())
		if aim_error_rad <= deg_to_rad(profile.get("fire_angle_threshold", 15.0)):
			ship.input_fire[0] = true
		else:
			ship.input_fire[0] = false
	else:
		ship.input_fire[0] = false


# ─── Signal Handlers ──────────────────────────────────────────────────────

func _on_request_tactical_move(ship_ids: Array, destination: Vector3, _queue_mode: String) -> void:
	var my_id := get_parent().get_instance_id()
	if my_id not in ship_ids:
		return

	# Defer to warp if active — queue the move for after warp ends.
	var warp: WarpDrive = get_parent().get_node_or_null("WarpDrive") as WarpDrive
	if warp != null and warp.is_warp_active():
		warp.queue_move(destination)
		return

	_destination = Vector3(destination.x, 0.0, destination.z)
	_arrived = false
	_flight_mode = FlightMode.TACTICAL_ORDER
	_thrust_fraction = float(profile.get("autopilot_thrust_fraction",
			profile.get("pursue_thrust_fraction", 0.85)))


func _on_request_tactical_stop(ship_ids: Array) -> void:
	var my_id := get_parent().get_instance_id()
	if my_id not in ship_ids:
		return
	if _flight_mode == FlightMode.TACTICAL_ORDER:
		_flight_mode = FlightMode.NONE
		_arrived = true
		var ship := get_parent()
		ship.input_forward = 0.0
		ship.input_strafe = 0.0
	# AI ships: also drop any tactical-attack state
	if not _is_player and _current_state == State.TACTICAL_ATTACK:
		_tactical_target = null
		_transition_to(State.IDLE)


func _on_request_formation_destination(ship_id: int, destination: Vector3) -> void:
	if get_parent().get_instance_id() != ship_id:
		return
	if _flight_mode == FlightMode.TACTICAL_ORDER \
			or _flight_mode == FlightMode.EMERGENCY_STOP:
		return    # higher-priority override active

	_destination = Vector3(destination.x, 0.0, destination.z)
	_arrived = false
	_flight_mode = FlightMode.FORMATION
	_thrust_fraction = float(profile.get("formation_thrust_fraction",
			profile.get("pursue_thrust_fraction", 0.85)))


func _on_request_tactical_attack(ship_ids: Array, target_id: int, _queue_mode: String) -> void:
	var my_id := get_parent().get_instance_id()
	if my_id not in ship_ids:
		return
	var target_node := instance_from_id(target_id)
	if target_node == null or not is_instance_valid(target_node):
		return
	_tactical_target = target_node as Node3D
	_transition_to(State.TACTICAL_ATTACK)


# ─── Stance ───────────────────────────────────────────────────────────────

func _should_hold_fire() -> bool:
	if _stance_controller == null:
		return false
	var ship_id := get_parent().get_instance_id()
	# StanceController.Stance.HOLD_FIRE == 0
	return _stance_controller.get_effective_stance(ship_id) == 0


# ─── Aim Prediction ────────────────────────────────────────────────────────

func _predict_aim_position(target: Node3D) -> Vector3:
	var ship := get_parent() as RigidBody3D
	var to_target := target.global_position - ship.global_position
	to_target.y = 0.0
	var distance := to_target.length()

	if _primary_muzzle_speed <= 0.0:
		return target.global_position

	var travel_time := distance / _primary_muzzle_speed
	var target_vel: Vector3 = target.linear_velocity if target is RigidBody3D else Vector3.ZERO
	var predicted: Vector3 = target.global_position + target_vel * travel_time * float(profile.get("aim_accuracy", 0.7))
	predicted.y = 0.0
	return predicted


# ─── Detection ─────────────────────────────────────────────────────────────

func _on_detection_volume_body_entered(body: Node3D) -> void:
	var ship := get_parent()

	# Fleet ships only target enemies, not the player or other fleet members
	if ship.is_in_group("player_fleet"):
		if body.is_in_group("enemies"):
			_target_detected = true
			_target = body
			_event_bus.emit_signal("ai_target_acquired",
				ship.get_instance_id(),
				body.get_instance_id())
		return

	# Non-fleet (enemy) AI targets the player
	if body.is_in_group("player"):
		_target_detected = true
		_target = body
		_event_bus.emit_signal("ai_target_acquired",
			ship.get_instance_id(),
			body.get_instance_id())


func _on_detection_volume_body_exited(body: Node3D) -> void:
	if body == _target:
		_target_detected = false
		_event_bus.emit_signal("ai_target_lost", get_parent().get_instance_id())


# ─── State Transitions ─────────────────────────────────────────────────────

func _transition_to(new_state: State) -> void:
	var old_state := _current_state
	_on_exit_state(_current_state)
	_current_state = new_state
	_on_enter_state(new_state)
	_event_bus.emit_signal("ai_state_changed",
		get_parent().get_instance_id(),
		State.keys()[old_state],
		State.keys()[new_state])


func _on_enter_state(state: State) -> void:
	match state:
		State.IDLE:
			_pick_new_wander_target()
		State.ENGAGE:
			_circle_direction = 1.0 if randf() > 0.5 else -1.0
		State.TACTICAL_ATTACK:
			_circle_direction = 1.0 if randf() > 0.5 else -1.0


func _on_exit_state(_state: State) -> void:
	# Clear fire inputs on leaving any state
	var ship := get_parent()
	if ship and "input_fire" in ship:
		ship.input_fire[0] = false


# ─── Helpers ───────────────────────────────────────────────────────────────

func _cache_primary_muzzle_speed(ship: Node) -> void:
	# Find the first HardpointComponent in fire group 0 that has a weapon
	var hardpoints := _find_hardpoints_recursive(ship, [])
	for hp in hardpoints:
		if hp is HardpointComponent and 0 in hp.fire_groups:
			if hp._weapon_component != null:
				_primary_muzzle_speed = hp._weapon_component.muzzle_speed
				return
	# Fallback — use a reasonable default
	_primary_muzzle_speed = 700.0


func _find_hardpoints_recursive(node: Node, result: Array) -> Array:
	if node is HardpointComponent:
		result.append(node)
	for child in node.get_children():
		_find_hardpoints_recursive(child, result)
	return result
