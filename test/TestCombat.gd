extends Node3D

const _GameCamera := preload("res://gameplay/camera/GameCamera.gd")
const _ChunkStreamer := preload("res://gameplay/world/ChunkStreamer.gd")
const _AIController := preload("res://gameplay/ai/AIController.gd")

var _player_ship: Ship
var _enemy_ship: Ship
var _camera: Node
var _chunk_streamer: Node
var _game_mode: String = "pilot"
var _player_nav: NavigationController

var _perf: Node
var _bus: Node


func _ready() -> void:
	_perf = ServiceLocator.GetService("PerformanceMonitor") as Node
	_bus = ServiceLocator.GetService("GameEventBus") as Node
	_spawn_world()
	if _bus != null:
		_bus.connect("request_tactical_move", Callable(self, "_on_tactical_move"))


func _spawn_world() -> void:
	_camera = _GameCamera.new()
	_camera.name = "GameCamera"
	_camera.current = true
	add_child(_camera)

	_chunk_streamer = _ChunkStreamer.new()
	_chunk_streamer.name = "ChunkStreamer"
	add_child(_chunk_streamer)

	_player_ship = ShipFactory.spawn_ship("fighter_light")
	add_child(_player_ship)
	_player_ship.global_position = Vector3(0, 0, 0)
	_player_ship.set_faction("player")
	_player_ship.control_source = "pilot"

	_player_nav = NavigationController.new()
	_player_nav.name = "PlayerNav"
	_player_nav.setup(_player_ship)
	_player_ship.add_child(_player_nav)
	_player_nav.clear_destination()

	PlayerState.set_active_ship(_player_ship)

	_camera.follow(_player_ship)
	_chunk_streamer.set_follow_target(_player_ship)

	var profile: Dictionary = _load_ai_profile("default")
	_enemy_ship = ShipFactory.spawn_ship("corvette_patrol")
	add_child(_enemy_ship)
	_enemy_ship.global_position = Vector3(900, 0, 400)
	_enemy_ship.set_faction("pirate")
	_enemy_ship.control_source = "ai"

	var ai := _AIController.new()
	ai.name = "AIController"
	ai.setup(_enemy_ship, profile, _enemy_ship.global_position)
	_enemy_ship.add_child(ai)
	ai.set_player_target(_player_ship)


func _load_ai_profile(profile_id: String) -> Dictionary:
	var f := FileAccess.open("res://data/ai_profiles.json", FileAccess.READ)
	if f == null:
		return {}
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		f.close()
		return {}
	f.close()
	var root: Dictionary = json.data as Dictionary
	var arr: Array = root.get("ai_profiles", []) as Array
	for item in arr:
		if typeof(item) == TYPE_DICTIONARY:
			var d: Dictionary = item
			if str(d.get("id", "")) == profile_id:
				return d
	return {}


func _physics_process(_delta: float) -> void:
	if _perf == null:
		return
	_perf.set_count("Physics.active_bodies", get_tree().get_nodes_in_group("physics_bodies").size())
	_perf.set_count("Ships.active_count", get_tree().get_nodes_in_group("ships").size())
	_perf.set_count("AIController.active_count", get_tree().get_nodes_in_group("ai_ships").size())
	if _game_mode == "tactical" and _player_ship != null:
		_player_ship.input_fire = [false, false, false]
	_pilot_input()


func _pilot_input() -> void:
	if _player_ship == null:
		return
	if _game_mode != "pilot":
		return
	var f := Input.get_axis("thrust_reverse", "thrust_forward")
	var s := Input.get_axis("strafe_left", "strafe_right")
	_player_ship.input_forward = f
	_player_ship.input_strafe = s
	var aim := _mouse_aim()
	_player_ship.input_aim_target = aim
	_player_ship.input_fire = [
		Input.is_action_pressed("fire_primary"),
		Input.is_action_pressed("fire_secondary"),
		Input.is_action_pressed("fire_missile"),
	]


func _mouse_aim() -> Vector3:
	var cam := _camera as Camera3D
	if cam == null:
		return Vector3.ZERO
	var mouse := get_viewport().get_mouse_position()
	var ray_o: Vector3 = cam.project_ray_origin(mouse)
	var ray_d: Vector3 = cam.project_ray_normal(mouse)
	var plane := Plane(Vector3.UP, 0.0)
	var hit: Variant = plane.intersects_ray(ray_o, ray_d)
	if hit == null:
		return _player_ship.global_position + Vector3(1, 0, 0)
	var p: Vector3 = hit
	p.y = 0.0
	return p


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_mode"):
		_toggle_mode()
	if _game_mode == "tactical" and event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var hit := _mouse_aim_from_camera(mb.position)
			if _bus != null:
				_bus.emit_signal("request_tactical_move", [_player_ship.get_instance_id()], hit)


func _mouse_aim_from_camera(screen_pos: Vector2) -> Vector3:
	var cam := _camera as Camera3D
	if cam == null:
		return Vector3.ZERO
	var ray_o: Vector3 = cam.project_ray_origin(screen_pos)
	var ray_d: Vector3 = cam.project_ray_normal(screen_pos)
	var plane := Plane(Vector3.UP, 0.0)
	var hit: Variant = plane.intersects_ray(ray_o, ray_d)
	if hit == null:
		return Vector3.ZERO
	var p: Vector3 = hit
	p.y = 0.0
	return p


func _toggle_mode() -> void:
	if _game_mode == "pilot":
		_game_mode = "tactical"
		_player_ship.control_source = "tactical"
		_camera.set_mode_heights(false)
		if _bus != null:
			_bus.emit_signal("game_mode_changed", "pilot", "tactical")
	else:
		_game_mode = "pilot"
		_player_ship.control_source = "pilot"
		_player_nav.clear_destination()
		_camera.set_mode_heights(true)
		if _bus != null:
			_bus.emit_signal("game_mode_changed", "tactical", "pilot")


func _on_tactical_move(ship_ids: Array, destination: Vector3) -> void:
	if _game_mode != "tactical":
		return
	var dest := destination
	dest.y = 0.0
	for sid in ship_ids:
		if int(sid) == _player_ship.get_instance_id():
			_player_nav.set_destination(dest)
