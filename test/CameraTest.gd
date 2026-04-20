extends Node3D

## Manual test harness for GameCamera Pilot mode (Phase 10).
##
## Controls:
##   W / S       — forward / reverse thrust
##   A / D       — strafe left / right
##   Mouse       — aim direction (cursor offset drives camera lead)
##   Scroll      — zoom in / out
##
## Success criteria to verify visually:
##   [ ] Camera follows ship with no overshoot or wobble at speed
##   [ ] Camera offset leads toward cursor — aim right shifts view right
##   [ ] Cursor near ship = minimal offset; cursor far = maximum offset
##   [ ] Cursor offset shrinks when zoomed out
##   [ ] Scroll wheel zooms smoothly — no snapping, no FOV distortion
##   [ ] Zoom in/out does not change the camera tilt angle
##   [ ] GameCamera node is NOT a child of the ship in the scene tree

var _player_ship: Node = null
var _camera: GameCamera = null
var _ship_factory: ShipFactory

@export var ship_class_id: String = "axum-fighter-1"
@export var ship_variant_id: String = "axum_fighter_interceptor"
@export var ship_faction: String = "axum"


func _ready() -> void:
	print("[CameraTest] Starting — check Output for success criteria checklist.")

	var service_locator := Engine.get_singleton("ServiceLocator")
	if service_locator == null:
		push_error("[CameraTest] ServiceLocator not found. Is GameBootstrap in the scene?")
		return

	_camera = $GameCamera

	_ship_factory = ShipFactory.new()
	_ship_factory.name = "ShipFactory"
	add_child(_ship_factory)

	_player_ship = _ship_factory.spawn_ship(
		ship_class_id,
		ship_variant_id,
		Vector3.ZERO,
		ship_faction,
		true
	)

	if _player_ship == null:
		push_error("[CameraTest] Failed to spawn player ship. Check ContentRegistry / ship.json.")
		return

	print("[CameraTest] Spawned: %s" % _player_ship.display_name)
	print("[CameraTest] WASD = thrust  |  Mouse = aim  |  Scroll = zoom")
	_print_checklist()


func _physics_process(_delta: float) -> void:
	if _player_ship == null or not is_instance_valid(_player_ship):
		return
	if _camera == null:
		return

	_player_ship.input_forward = Input.get_axis("ui_down", "ui_up")
	_player_ship.input_strafe  = Input.get_axis("ui_left", "ui_right")
	_player_ship.input_aim_target = _camera.get_cursor_world_position()


func _print_checklist() -> void:
	print("─────────────────────────────────────────────────")
	print("  CAMERA TEST — Manual Verification Checklist")
	print("─────────────────────────────────────────────────")
	print("  [ ] Camera follows ship — no overshoot / wobble")
	print("  [ ] Aiming right shifts view right")
	print("  [ ] Cursor near ship = minimal camera offset")
	print("  [ ] Cursor offset shrinks when zoomed out")
	print("  [ ] Scroll zooms smoothly — no snapping / FOV warp")
	print("  [ ] Tilt angle is constant at all zoom levels")
	print("  [ ] GameCamera is sibling of ship, not its child")
	print("─────────────────────────────────────────────────")
