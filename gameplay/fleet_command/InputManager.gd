extends Node
class_name InputManager

## Tab key mode toggle and player-ship input routing.
##
## In Pilot mode: reads WASD + mouse and writes to the player ship's unified
## input interface. In Tactical mode: writes nothing — the ship idles or
## follows AIController autopilot orders.
##
## This node must be a child of the test/game scene. It needs a reference to
## the GameCamera for cursor-to-world conversion.

var _current_mode: String = "pilot"
var _player_ship: Node = null
var _camera = null
var _cinematic_active: bool = false

var _event_bus: Node
var _player_state: Node


func _ready() -> void:
	var service_locator := Engine.get_singleton("ServiceLocator")
	_event_bus = service_locator.GetService("GameEventBus")
	_player_state = service_locator.GetService("PlayerState")

	if _event_bus:
		_event_bus.connect("player_ship_changed", _on_player_ship_changed)
		_event_bus.connect("cinematic_active_changed", _on_cinematic_active_changed)
		_event_bus.connect("game_mode_changed", _on_game_mode_changed)

	# Pick up existing player ship if already spawned
	if _player_state and _player_state.active_ship:
		_player_ship = _player_state.active_ship


func set_camera(camera) -> void:
	_camera = camera


func current_mode() -> String:
	return _current_mode


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_mode"):
		if _current_mode == "galaxy_map":
			return
		var old_mode := _current_mode
		_current_mode = "tactical" if _current_mode == "pilot" else "pilot"
		_event_bus.game_mode_changed.emit(old_mode, _current_mode)

		# Clear ship inputs when leaving pilot mode
		if old_mode == "pilot" and _player_ship and is_instance_valid(_player_ship):
			_player_ship.input_forward = 0.0
			_player_ship.input_strafe = 0.0
			_player_ship.input_fire[0] = false
			_player_ship.input_fire[1] = false
			_player_ship.input_fire[2] = false

		# Entering pilot mode cancels any autopilot — player takes manual control.
		if _current_mode == "pilot" and _player_ship and is_instance_valid(_player_ship):
			var ai: AIController = _player_ship.get_node_or_null("AIController") as AIController
			if ai != null:
				ai.cancel_flight_override()

		print("[InputManager] Mode: %s → %s" % [old_mode, _current_mode])

	if event.is_action_pressed("toggle_galaxy_map"):
		if _current_mode == "galaxy_map":
			# Galaxy map always returns to pilot mode
			var old_mode := "galaxy_map"
			_current_mode = "pilot"
			_event_bus.game_mode_changed.emit(old_mode, _current_mode)
			print("[InputManager] Mode: %s → %s" % [old_mode, _current_mode])
		else:
			var old_mode := _current_mode
			_current_mode = "galaxy_map"
			_event_bus.game_mode_changed.emit(old_mode, _current_mode)
			# Clear ship inputs when entering galaxy map
			if _player_ship and is_instance_valid(_player_ship):
				_player_ship.input_forward = 0.0
				_player_ship.input_strafe = 0.0
				_player_ship.input_fire[0] = false
				_player_ship.input_fire[1] = false
				_player_ship.input_fire[2] = false
			print("[InputManager] Mode: %s → %s" % [old_mode, _current_mode])


func _physics_process(_delta: float) -> void:
	if _player_ship == null or not is_instance_valid(_player_ship):
		return
	if _current_mode == "galaxy_map":
		return
	if _current_mode != "pilot":
		return
	if _cinematic_active:
		return

	_route_pilot_input()


func _route_pilot_input() -> void:
	_player_ship.input_forward = Input.get_axis("move_backward", "move_forward")
	_player_ship.input_strafe = Input.get_axis("move_left", "move_right")

	if _camera and _camera.has_method("get_cursor_world_position"):
		_player_ship.input_aim_target = _camera.get_cursor_world_position()


func _unhandled_input(event: InputEvent) -> void:
	if _current_mode == "galaxy_map":
		return
	if _current_mode != "pilot":
		return
	if _cinematic_active:
		return
	if _player_ship == null or not is_instance_valid(_player_ship):
		return

	if event is InputEventMouseButton:
		var e := event as InputEventMouseButton
		if e.button_index == MOUSE_BUTTON_LEFT:
			_player_ship.input_fire[0] = e.pressed
		elif e.button_index == MOUSE_BUTTON_RIGHT:
			_player_ship.input_fire[1] = e.pressed


func _on_player_ship_changed(ship: Node) -> void:
	_player_ship = ship


func _on_game_mode_changed(_old_mode: String, new_mode: String) -> void:
	_current_mode = new_mode


func _on_cinematic_active_changed(active: bool) -> void:
	_cinematic_active = active
	if active and _player_ship and is_instance_valid(_player_ship):
		# Clear inputs when cinematic takes over
		_player_ship.input_forward = 0.0
		_player_ship.input_strafe = 0.0
		_player_ship.input_fire[0] = false
		_player_ship.input_fire[1] = false
		_player_ship.input_fire[2] = false
