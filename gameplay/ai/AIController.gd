extends Node
class_name AIController

# AIController — state-machine AI for enemy ships.
# Produces physics inputs (ai_forward_input, ai_strafe_input, ai_aim_target) that
# Ship.gd reads each frame — no physics cheating; AI obeys the same thruster budget.
# State transitions are broadcast via GameEventBus.
# See docs/AI_Patrol_Behavior_Spec.md.

enum State { IDLE, PURSUE, ENGAGE, FLEE, REGROUP, SEARCH, ORBIT }

# Outputs read by Ship.gd every physics frame.
var ai_forward_input: float = 0.0
var ai_strafe_input: float  = 0.0
var ai_aim_target: Vector2  = Vector2.ZERO

# Behavior profile ID — set before entering the scene tree (e.g. from ShipFactory).
@export var profile_id: String = "default"

var _profile: Dictionary = {}
var _current_state: State = State.IDLE
var _spawn_position: Vector2 = Vector2.ZERO

var _target_player: Ship = null
var _wander_target: Vector2 = Vector2.ZERO
var _wander_pause_timer: float = 0.0
var _circle_direction: float = 1.0

var _ship: Ship
var _event_bus: Node
var _perf: Node

# Transition table — data-driven, extensible.
const _TRANSITIONS: Dictionary = {
	# State.IDLE transitions defined in _idle_process()
	# State.PURSUE transitions defined in _pursue_process()
	# State.ENGAGE transitions defined in _engage_process()
}


func _ready() -> void:
	_ship = get_parent() as Ship
	if _ship == null:
		push_error("AIController: parent must be a Ship node")
		return

	_event_bus = ServiceLocator.GetService("GameEventBus") as Node
	_perf = ServiceLocator.GetService("PerformanceMonitor") as Node

	_spawn_position = _ship.global_position
	_load_profile(profile_id)
	_pick_new_wander_target()
	_current_state = State.IDLE

	# Register custom monitors (first AI controller to enter tree registers them).
	_register_monitors()


func _register_monitors() -> void:
	if Performance.has_custom_monitor("AllSpace/ai_ships_active"):
		return
	Performance.add_custom_monitor("AllSpace/ai_ships_active",
		func(): return _perf.get_count("AIController.active_count") if _perf else 0)
	Performance.add_custom_monitor("AllSpace/ai_ms",
		func(): return _perf.get_avg_ms("AIController.state_updates") if _perf else 0.0)


func _load_profile(id: String) -> void:
	var file_path := "res://data/ai_profiles.json"
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("AIController: failed to open '%s'" % file_path)
		return

	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_error(
			"AIController: JSON parse failed for '%s': %s (line %d)" % [
				file_path, json.get_error_message(), json.get_error_line()
			]
		)
		return

	var data = json.get_data()
	if typeof(data) != TYPE_DICTIONARY or not data.has("ai_profiles"):
		push_error("AIController: missing 'ai_profiles' array in '%s'" % file_path)
		return

	for entry in data["ai_profiles"]:
		if typeof(entry) == TYPE_DICTIONARY and entry.get("id", "") == id:
			_profile = entry
			return

	push_warning("AIController: profile '%s' not found in '%s', using defaults" % [id, file_path])


## Allow ShipFactory (or inspector) to set the profile before _ready().
func set_profile(id: String) -> void:
	profile_id = id


func _physics_process(delta: float) -> void:
	if _ship == null or _ship.is_dead:
		return

	_perf.begin("AIController.state_updates")

	match _current_state:
		State.IDLE:   _idle_process(delta)
		State.PURSUE: _pursue_process(delta)
		State.ENGAGE: _engage_process(delta)

	_perf.end("AIController.state_updates")

	# Update active AI count metric once per frame (slight overcount with many controllers,
	# but accurate enough for the overlay).
	_perf.set_count("AIController.active_count",
		get_tree().get_nodes_in_group("ai_ships").size())


# --- State: IDLE (wander) ---

func _idle_process(delta: float) -> void:
	if _target_in_detection_range():
		_transition_to(State.PURSUE)
		return

	var dist_to_wander := _ship.position.distance_to(_wander_target)
	if dist_to_wander < _get_profile_float("wander_arrival_distance", 40.0):
		_wander_pause_timer -= delta
		ai_forward_input = 0.0
		ai_strafe_input  = 0.0
		if _wander_pause_timer <= 0.0:
			_pick_new_wander_target()
	else:
		ai_aim_target    = _wander_target
		ai_forward_input = _get_profile_float("wander_thrust_fraction", 0.4)
		ai_strafe_input  = 0.0


func _pick_new_wander_target() -> void:
	var radius: float = _get_profile_float("wander_radius", 600.0)
	var angle := randf() * TAU
	_wander_target = _spawn_position + Vector2(cos(angle), sin(angle)) * randf_range(0.0, radius)

	var pause_min: float = _get_profile_float("wander_pause_min", 1.0)
	var pause_max: float = _get_profile_float("wander_pause_max", 3.0)
	_wander_pause_timer = randf_range(pause_min, pause_max)


# --- State: PURSUE ---

func _pursue_process(_delta: float) -> void:
	if not is_instance_valid(_target_player):
		_transition_to(State.IDLE)
		return

	var dist_from_home := _ship.position.distance_to(_spawn_position)
	if dist_from_home > _get_profile_float("leash_range", 1500.0):
		_transition_to(State.IDLE)
		return

	var dist_to_player := _ship.position.distance_to(_target_player.position)
	if dist_to_player <= _get_profile_float("engage_distance", 500.0):
		_transition_to(State.ENGAGE)
		return

	ai_aim_target    = _target_player.position
	ai_forward_input = _get_profile_float("pursue_thrust_fraction", 0.85)
	ai_strafe_input  = 0.0


# --- State: ENGAGE ---

func _engage_process(_delta: float) -> void:
	if not is_instance_valid(_target_player) or _target_player.is_dead:
		_transition_to(State.IDLE)
		return

	var dist_from_home := _ship.position.distance_to(_spawn_position)
	if dist_from_home > _get_profile_float("leash_range", 1500.0):
		_transition_to(State.IDLE)
		return

	var dist_to_player := _ship.position.distance_to(_target_player.position)
	var predicted_pos := _predict_aim_position(_target_player)

	ai_aim_target = predicted_pos

	# Distance maintenance
	var preferred: float = _get_profile_float("preferred_engage_distance", 350.0)
	var ratio := dist_to_player / preferred if preferred > 0.0 else 1.0
	var engage_thrust: float = _get_profile_float("engage_thrust_fraction", 0.7)
	var strafe_thrust: float = _get_profile_float("strafe_thrust_fraction", 0.3)

	if ratio < 0.7:
		ai_forward_input = -engage_thrust   # too close — reverse
		ai_strafe_input  = 0.0
	elif ratio > 1.3:
		ai_forward_input = engage_thrust    # too far — close in
		ai_strafe_input  = 0.0
	else:
		ai_forward_input = 0.0
		ai_strafe_input  = _circle_direction * strafe_thrust  # orbit

	# Fire decision — fire when facing approximately toward predicted position
	var aim_error := absf(angle_difference(_ship.rotation, _ship.position.direction_to(predicted_pos).angle()))
	var threshold: float = deg_to_rad(_get_profile_float("fire_angle_threshold", 15.0))
	if aim_error <= threshold:
		_fire_weapons(predicted_pos)


func _fire_weapons(target_pos: Vector2) -> void:
	if _ship._weapon_component == null:
		return
	_ship._weapon_component.fire_primary_at(target_pos)


# --- Aim Prediction ---

func _predict_aim_position(target: Ship) -> Vector2:
	var to_target := target.position - _ship.position
	var distance := to_target.length()
	var muzzle_speed := _get_primary_muzzle_speed()
	if muzzle_speed <= 0.0:
		return target.position

	var travel_time := distance / muzzle_speed
	var accuracy: float = _get_profile_float("aim_accuracy", 0.7)
	return target.position + target.velocity * travel_time * accuracy


func _get_primary_muzzle_speed() -> float:
	if _ship._weapon_component == null:
		return 900.0
	var hardpoints := _ship._weapon_component.get_all_hardpoints()
	for hp_node in hardpoints:
		var hp := hp_node as HardpointComponent
		if hp == null:
			continue
		if not hp.allowed_groups.has("primary"):
			continue
		var w_data: Dictionary = hp.weapon_data
		if w_data.is_empty():
			continue
		var archetype: String = w_data.get("archetype", "")
		if archetype == "ballistic":
			return float(w_data.get("muzzle_speed", 900.0))
		elif archetype == "energy_beam" or archetype == "energy_pulse":
			return 9999.0  # hitscan — treat as instant
	return 900.0


# --- Detection ---

func _target_in_detection_range() -> bool:
	var player := _find_player()
	if player == null:
		return false
	var detection_range: float = _get_profile_float("detection_range", 800.0)
	if _ship.position.distance_to(player.position) <= detection_range:
		_target_player = player
		return true
	return false


func _find_player() -> Ship:
	for body in get_tree().get_nodes_in_group("player"):
		if body is Ship:
			return body
	return null


# --- Transitions ---

func _transition_to(new_state: State) -> void:
	var old_state := _current_state
	_on_exit_state(old_state)
	_current_state = new_state
	_on_enter_state(new_state)

	if _event_bus != null:
		_event_bus.emit_signal("ai_state_changed", {
			"ship_id":   _ship.get_instance_id(),
			"old_state": State.keys()[old_state],
			"new_state": State.keys()[new_state]
		})


func _on_exit_state(_state: State) -> void:
	ai_forward_input = 0.0
	ai_strafe_input  = 0.0


func _on_enter_state(state: State) -> void:
	match state:
		State.IDLE:
			_pick_new_wander_target()
		State.PURSUE:
			if _event_bus != null and _target_player != null:
				_event_bus.emit_signal("ai_target_acquired", {
					"ship_id":   _ship.get_instance_id(),
					"target_id": _target_player.get_instance_id()
				})
		State.ENGAGE:
			_circle_direction = 1.0 if randf() > 0.5 else -1.0


# --- Helpers ---

func _get_profile_float(key: String, default_val: float) -> float:
	if _profile.is_empty():
		return default_val
	var v = _profile.get(key, default_val)
	return float(v)
