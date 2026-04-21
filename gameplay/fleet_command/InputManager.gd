extends Node
class_name InputManager

## Tab key mode toggle and player-ship input routing.
##
## In Pilot mode: reads WASD + mouse and writes to the player ship's unified
## input interface. In Tactical mode: writes nothing — the ship idles or
## follows NavigationController orders.
##
## This node must be a child of the test/game scene. It needs a reference to
## the GameCamera for cursor-to-world conversion.

var _current_mode: String = "pilot"
var _player_ship: Node = null
var _camera: Camera3D = null

var _event_bus: Node
var _player_state: Node


func _ready() -> void:
	var service_locator := Engine.get_singleton("ServiceLocator")
	_event_bus = service_locator.GetService("GameEventBus")
	_player_state = service_locator.GetService("PlayerState")

	if _event_bus:
		_event_bus.connect("player_ship_changed", _on_player_ship_changed)

	# Pick up existing player ship if already spawned
	if _player_state and _player_state.active_ship:
		_player_ship = _player_state.active_ship


func set_camera(camera: Camera3D) -> void:
	_camera = camera


func current_mode() -> String:
	return _current_mode


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_mode"):
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

		print("[InputManager] Mode: %s → %s" % [old_mode, _current_mode])


func _physics_process(_delta: float) -> void:
	if _player_ship == null or not is_instance_valid(_player_ship):
		return
	if _current_mode != "pilot":
		return

	_route_pilot_input()


func _route_pilot_input() -> void:
	_player_ship.input_forward = Input.get_axis("move_backward", "move_forward")
	_player_ship.input_strafe = Input.get_axis("move_left", "move_right")

	if _camera:
		_player_ship.input_aim_target = _camera.get_cursor_world_position()


func _unhandled_input(event: InputEvent) -> void:
	if _current_mode != "pilot":
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
