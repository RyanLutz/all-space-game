extends Node3D

## Step 12 — Player vs AI, full Pilot mode loop (integration test).
##
## Controls:
##   W / S / A / D  — thrust (InputMap: move_forward, move_backward, move_left, move_right)
##   Mouse          — aim (GameCamera cursor ray → XZ plane)
##   Scroll         — zoom (GameCamera)
##   LMB / RMB      — weapon groups 1 and 2
##
## Manual verification checklist:
##   [ ] Player ship thrusts and rotates toward aim point; Y stays on the play plane
##   [ ] GameCamera follows player; cursor lead and zoom behave as in CameraTest
##   [ ] AI ship patrols / engages per ai_profile_id (see data/ai_profiles.json)
##   [ ] Primary and secondary fire spawn projectiles; impacts register
##   [ ] Ships can be destroyed; GameEventBus ship_destroyed / player flow makes sense
##   [ ] No new gameplay systems required — ShipFactory + existing components only

var _player_ship: Ship = null
var _camera: GameCamera = null
var _ship_factory: ShipFactory = null

@export_group("Player ship")
@export var player_class_id: String = "axum-fighter-1"
@export var player_variant_id: String = "axum_fighter_interceptor"
@export var player_faction: String = "axum"
@export var player_spawn: Vector3 = Vector3.ZERO

@export_group("AI ship")
@export var ai_class_id: String = "axum-fighter-1"
@export var ai_variant_id: String = "axum_fighter_patrol"
@export var ai_faction: String = "pirate"
@export var ai_spawn: Vector3 = Vector3(60, 0, 0)
@export var ai_profile_id: String = "default"


func _ready() -> void:
	print("[PilotLoopTest] Starting — Step 12 player vs AI Pilot loop.")

	var service_locator := Engine.get_singleton("ServiceLocator")
	if service_locator == null:
		push_error("[PilotLoopTest] ServiceLocator not found. Autoload GameBootstrap required.")
		return

	_camera = $GameCamera as GameCamera
	if _camera == null:
		push_error("[PilotLoopTest] GameCamera child missing.")
		return

	_ship_factory = ShipFactory.new()
	_ship_factory.name = "ShipFactory"
	add_child(_ship_factory)

	_player_ship = _ship_factory.spawn_ship(
		player_class_id,
		player_variant_id,
		player_spawn,
		player_faction,
		true
	) as Ship

	if _player_ship == null:
		push_error("[PilotLoopTest] Failed to spawn player ship.")
		return

	var ai_ship := _ship_factory.spawn_ship(
		ai_class_id,
		ai_variant_id,
		ai_spawn,
		ai_faction,
		false,
		{},
		ai_profile_id
	)
	if ai_ship == null:
		push_error("[PilotLoopTest] Failed to spawn AI ship.")

	print("[PilotLoopTest] Player: %s  |  AI spawned: %s" % [
		_player_ship.display_name,
		"yes" if ai_ship != null else "no"
	])
	print("[PilotLoopTest] WASD = thrust  |  Mouse = aim  |  Scroll = zoom  |  LMB/RMB = fire")


func _physics_process(_delta: float) -> void:
	if _player_ship == null or not is_instance_valid(_player_ship):
		return
	if _camera == null:
		return

	_player_ship.input_forward = Input.get_axis("move_backward", "move_forward")
	_player_ship.input_strafe = Input.get_axis("move_left", "move_right")
	_player_ship.input_aim_target = _camera.get_cursor_world_position()


func _input(event: InputEvent) -> void:
	if _player_ship == null or not is_instance_valid(_player_ship):
		return

	if event is InputEventMouseButton:
		var e := event as InputEventMouseButton
		if e.button_index == MOUSE_BUTTON_LEFT:
			_player_ship.input_fire[0] = e.pressed
		elif e.button_index == MOUSE_BUTTON_RIGHT:
			_player_ship.input_fire[1] = e.pressed
