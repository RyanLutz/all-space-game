class_name AIController
extends Node

enum State { IDLE, PURSUE, ENGAGE }

var _ship: Ship
var _nav: NavigationController
var _state: State = State.IDLE
var _profile: Dictionary = {}
var _spawn_origin: Vector3 = Vector3.ZERO

var _player_ship: Node3D = null
var _rng := RandomNumberGenerator.new()

var _wander_target: Vector3 = Vector3.ZERO
var _wander_timer: float = 0.0

var _perf: Node
var _event_bus: Node


func setup(ship: Ship, profile: Dictionary, spawn_origin: Vector3) -> void:
	_ship = ship
	_ship.add_to_group("ai_ships")
	_spawn_origin = spawn_origin
	_profile = profile
	_perf = ServiceLocator.GetService("PerformanceMonitor") as Node
	_event_bus = ServiceLocator.GetService("GameEventBus") as Node
	_nav = NavigationController.new()
	_nav.name = "NavigationController"
	_nav.setup(ship)
	ship.add_child(_nav)
	_rng.randomize()
	_pick_wander_target()


func set_player_target(player: Node3D) -> void:
	_player_ship = player


func _physics_process(_delta: float) -> void:
	if _ship == null:
		return
	if _perf != null:
		_perf.begin("AIController.state_updates")
	match _state:
		State.IDLE:
			_process_idle()
		State.PURSUE:
			_process_pursue()
		State.ENGAGE:
			_process_engage()
	if _perf != null:
		_perf.end("AIController.state_updates")


func _process_idle() -> void:
	_ship.input_fire = [false, false, false]
	if _player_ship != null and is_instance_valid(_player_ship):
		var d: float = _ship.global_position.distance_to(_player_ship.global_position)
		if d < float(_profile.get("detection_range", 800.0)):
			_transition(State.PURSUE)
			return
	_wander_timer -= get_physics_process_delta_time()
	if _wander_timer <= 0.0:
		_pick_wander_target()
		_wander_timer = _rng.randf_range(1.0, 3.0)
	_nav.set_destination(_wander_target)
	_ship.input_aim_target = _wander_target


func _process_pursue() -> void:
	if _player_ship == null or not is_instance_valid(_player_ship):
		_transition(State.IDLE)
		return
	var detect_r: float = float(_profile.get("detection_range", 800.0))
	if _ship.global_position.distance_to(_player_ship.global_position) > detect_r * 1.1:
		_transition(State.IDLE)
		return
	var leash: float = float(_profile.get("leash_range", 1500.0))
	if _ship.global_position.distance_to(_spawn_origin) > leash:
		_transition(State.IDLE)
		return
	var engage_d: float = float(_profile.get("engage_distance", 500.0))
	var dist: float = _ship.global_position.distance_to(_player_ship.global_position)
	if dist < engage_d:
		_transition(State.ENGAGE)
		return
	_nav.set_destination(_player_ship.global_position)
	_ship.input_aim_target = _predict_aim()


func _process_engage() -> void:
	if _player_ship == null or not is_instance_valid(_player_ship):
		_transition(State.IDLE)
		return
	var detect_r2: float = float(_profile.get("detection_range", 800.0))
	if _ship.global_position.distance_to(_player_ship.global_position) > detect_r2 * 1.15:
		_transition(State.IDLE)
		return
	var pref: float = float(_profile.get("preferred_engage_distance", 350.0))
	var dist: float = _ship.global_position.distance_to(_player_ship.global_position)
	if dist > float(_profile.get("engage_distance", 500.0)) * 1.2:
		_transition(State.PURSUE)
		return
	var orbit: Vector3 = _player_ship.global_position
	if dist < pref * 0.85:
		var away: Vector3 = (_ship.global_position - _player_ship.global_position).normalized()
		orbit = _player_ship.global_position + away * pref
	orbit.y = 0.0
	_nav.set_destination(orbit)
	_ship.input_aim_target = _predict_aim()
	var err: float = absf(
		wrapf(
			atan2(-(_player_ship.global_position - _ship.global_position).x, -(_player_ship.global_position - _ship.global_position).z) - _ship.rotation.y,
			-PI,
			PI
		)
	)
	var fire_thresh: float = deg_to_rad(float(_profile.get("fire_angle_threshold", 15.0)))
	var primary_secondary: bool = err < fire_thresh
	var missile_ok: bool = dist < float(_profile.get("engage_distance", 500.0)) * 1.1
	_ship.input_fire = [primary_secondary, primary_secondary, missile_ok and primary_secondary]


func _predict_aim() -> Vector3:
	if _player_ship == null:
		return _ship.global_position + _ship.get_heading() * 100.0
	var acc: float = float(_profile.get("aim_accuracy", 0.7))
	var vel: Vector3 = _player_ship.linear_velocity
	vel.y = 0.0
	var lead: Vector3 = _player_ship.global_position + vel * acc * 0.35
	lead.y = 0.0
	return lead


func _pick_wander_target() -> void:
	var r: float = float(_profile.get("wander_radius", 600.0))
	_wander_target = _spawn_origin + Vector3(_rng.randf_range(-r, r), 0.0, _rng.randf_range(-r, r))


func _transition(new_state: State) -> void:
	var old := _state
	_state = new_state
	if _event_bus != null:
		_event_bus.emit_signal(
			"ai_state_changed",
			_ship.get_instance_id(),
			_state_to_str(old),
			_state_to_str(new_state)
		)
		if new_state == State.PURSUE and _player_ship != null:
			_event_bus.emit_signal(
				"ai_target_acquired",
				_ship.get_instance_id(),
				_player_ship.get_instance_id()
			)


func _state_to_str(s: State) -> String:
	match s:
		State.IDLE:
			return "IDLE"
		State.PURSUE:
			return "PURSUE"
		State.ENGAGE:
			return "ENGAGE"
		_:
			return "IDLE"

