extends Node
class_name AIController

## State-machine-driven AI controller. Populates the ship's unified input
## interface (input_aim_target, input_fire) and delegates movement to
## NavigationController (input_forward, input_strafe).
##
## Attached as a child of the ship RigidBody3D by ShipFactory for AI ships.
## DetectionVolume (Area3D) is a sibling node — signals are connected in _ready().

# ─── State Machine ─────────────────────────────────────────────────────────
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
	},
}

var _current_state: State = State.IDLE

# ─── References ────────────────────────────────────────────────────────────
var nav_controller: NavigationController
var profile: Dictionary = {}

# ─── Detection ─────────────────────────────────────────────────────────────
var _player_detected: bool = false
var _target_player: Node3D = null

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


func _ready() -> void:
	var service_locator := Engine.get_singleton("ServiceLocator")
	_perf = service_locator.GetService("PerformanceMonitor")
	_event_bus = service_locator.GetService("GameEventBus")

	var ship := get_parent()
	_spawn_position = ship.global_position
	_spawn_position.y = 0.0

	# Find sibling NavigationController
	nav_controller = ship.get_node("NavigationController") as NavigationController

	# Connect DetectionVolume signals
	var detection := ship.get_node_or_null("DetectionVolume")
	if detection:
		detection.body_entered.connect(_on_detection_volume_body_entered)
		detection.body_exited.connect(_on_detection_volume_body_exited)

	# Cache primary weapon muzzle speed for aim prediction
	_cache_primary_muzzle_speed(ship)

	_pick_new_wander_target()
	_current_state = State.IDLE


# ─── Physics Process ───────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	_perf.begin("AIController.state_updates")
	match _current_state:
		State.IDLE:    _idle_process(delta)
		State.PURSUE:  _pursue_process(delta)
		State.ENGAGE:  _engage_process(delta)
	_perf.end("AIController.state_updates")


# ─── State: IDLE ───────────────────────────────────────────────────────────

func _idle_process(delta: float) -> void:
	if _player_detected:
		_transition_to(State.PURSUE)
		return

	var ship := get_parent() as RigidBody3D
	var dist_to_target := ship.global_position.distance_to(_wander_target)

	if dist_to_target < profile.get("wander_arrival_distance", 40.0):
		_wander_pause_timer -= delta
		if _wander_pause_timer <= 0.0:
			_pick_new_wander_target()
		# Hold position while paused
		nav_controller.set_destination(ship.global_position)
		nav_controller.set_thrust_fraction(0.0)
	else:
		nav_controller.set_destination(_wander_target)
		nav_controller.set_thrust_fraction(profile.get("wander_thrust_fraction", 0.4))

	# Face direction of travel while wandering
	ship.input_aim_target = _wander_target

	nav_controller.update(delta)


func _pick_new_wander_target() -> void:
	var angle := randf() * TAU
	var dist: float = randf() * float(profile.get("wander_radius", 600.0))
	_wander_target = _spawn_position + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
	_wander_pause_timer = randf_range(
		profile.get("wander_pause_min", 1.0),
		profile.get("wander_pause_max", 3.0)
	)


# ─── State: PURSUE ─────────────────────────────────────────────────────────

func _pursue_process(delta: float) -> void:
	if not is_instance_valid(_target_player):
		_transition_to(State.IDLE)
		return

	var ship := get_parent() as RigidBody3D
	var dist_from_home := ship.global_position.distance_to(_spawn_position)
	var dist_to_player := ship.global_position.distance_to(_target_player.global_position)

	if dist_from_home > profile.get("leash_range", 1500.0):
		_player_detected = false
		_transition_to(State.IDLE)
		return

	if dist_to_player <= profile.get("engage_distance", 500.0):
		_transition_to(State.ENGAGE)
		return

	nav_controller.set_destination(_target_player.global_position)
	nav_controller.set_thrust_fraction(profile.get("pursue_thrust_fraction", 0.85))
	nav_controller.update(delta)

	# Face the player while closing
	ship.input_aim_target = _target_player.global_position


# ─── State: ENGAGE ──────────────────────────────────────────────────────────

func _engage_process(delta: float) -> void:
	var ship := get_parent() as RigidBody3D

	if not is_instance_valid(_target_player):
		_transition_to(State.IDLE)
		return

	if ship.global_position.distance_to(_spawn_position) > profile.get("leash_range", 1500.0):
		_transition_to(State.IDLE)
		return

	var predicted_pos := _predict_aim_position(_target_player)
	ship.input_aim_target = predicted_pos

	var dist_to_player := ship.global_position.distance_to(_target_player.global_position)
	var preferred: float = float(profile.get("preferred_engage_distance", 350.0))
	var ratio: float = dist_to_player / maxf(preferred, 1.0)
	var engage_thrust: float = float(profile.get("engage_thrust_fraction", 0.7))

	if ratio < 0.7:
		# Too close — reverse away from player
		var away := (ship.global_position - _target_player.global_position).normalized()
		nav_controller.set_destination(ship.global_position + away * 200.0)
		nav_controller.set_thrust_fraction(engage_thrust)
		nav_controller.update(delta)
	elif ratio > 1.3:
		# Too far — close in
		nav_controller.set_destination(_target_player.global_position)
		nav_controller.set_thrust_fraction(engage_thrust)
		nav_controller.update(delta)
	else:
		# Sweet spot — hold position, orbit via strafe
		nav_controller.set_destination(ship.global_position)
		nav_controller.set_thrust_fraction(0.0)
		nav_controller.update(delta)
		ship.input_strafe = _circle_direction * profile.get("strafe_thrust_fraction", 0.3)

	# Fire decision
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
	if body.is_in_group("player"):
		_player_detected = true
		_target_player = body
		_event_bus.emit_signal("ai_target_acquired",
			get_parent().get_instance_id(),
			body.get_instance_id())


func _on_detection_volume_body_exited(body: Node3D) -> void:
	if body == _target_player:
		_player_detected = false
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
