extends Camera3D
class_name GameCamera3D

## Perspective Camera3D that follows a Ship in the 3D visual layer.
##
## Mirrors the GameCamera (Camera2D) public API — follow(target) / release() —
## so IntegrationScene can swap between them without changing call sites.
##
## Architecture: sibling of the game world, never a child of any ship.
## The 2D physics world and 3D visual world share the same layout convention:
##   2D (x, y) ↔ 3D (x, 0, -y) scaled by PIXELS_PER_UNIT.
##
## Scroll-wheel adjusts _target_height rather than a zoom factor; this keeps
## FOV constant and changes depth naturally.

# Must match Ship.PIXELS_PER_UNIT — both sides of the 2D/3D bridge.
const PIXELS_PER_UNIT := 2.8

@export_group("Follow")
@export var smoothing_speed: float = 10.0
## Horizontal cursor offset at default height (world units).
@export var max_cursor_offset: float = 3.0

@export_group("Height / Zoom")
@export var default_height: float = 14.0
@export var min_height: float = 5.0
@export var max_height: float = 40.0
## Each scroll tick changes height by this fraction of current height.
@export var scroll_step: float = 0.12
@export var height_smoothing: float = 8.0

@export_group("Tilt")
## Degrees forward tilt from straight-down (0 = top-down, 30 = cinematic).
@export_range(0.0, 60.0) var tilt_degrees: float = 25.0

var _follow_target: Ship = null
## Spring state — tracks the 3D look-at point.
var _spring_pos: Vector3 = Vector3.ZERO
var _spring_vel: Vector3 = Vector3.ZERO
var _target_height: float = 0.0
var _current_height: float = 0.0

var _event_bus: Node


func _ready() -> void:
	_event_bus = ServiceLocator.GetService("GameEventBus") as Node
	_target_height = default_height
	_current_height = default_height

	var player := get_tree().get_first_node_in_group("player") as Ship
	if player != null:
		follow(player)

	if _event_bus != null:
		_event_bus.connect("player_ship_changed", _on_player_ship_changed)


func _on_player_ship_changed(ship: Ship) -> void:
	follow(ship)


# --- Public API ---

func follow(target: Ship) -> void:
	_follow_target = target
	if target != null:
		_spring_pos = _ship_to_3d(target.global_position)


func release() -> void:
	_follow_target = null
	_spring_vel = Vector3.ZERO


func get_follow_target() -> Ship:
	return _follow_target


# --- Process ---

func _physics_process(delta: float) -> void:
	if _follow_target != null and not is_instance_valid(_follow_target):
		release()

	var desired := _compute_desired_look_pos()
	_spring_follow(desired, delta)
	_update_height(delta)
	_place_camera()


func _compute_desired_look_pos() -> Vector3:
	if _follow_target == null:
		return _spring_pos

	var target_3d := _ship_to_3d(_follow_target.global_position)

	# Cursor offset: shift look-at toward the mouse, scaled by height (like zoom).
	var screen_center := get_viewport().get_visible_rect().size * 0.5
	var mouse_screen := get_viewport().get_mouse_position()
	var cursor_vec := mouse_screen - screen_center

	var offset_scale := clampf(cursor_vec.length() / screen_center.length(), 0.0, 1.0)
	var cursor_dir_2d := cursor_vec.normalized() if cursor_vec.length() > 0.1 else Vector2.ZERO

	# Scale cursor offset proportionally with height so feel is consistent.
	var effective_offset := max_cursor_offset * (_current_height / default_height)
	var offset_3d := Vector3(cursor_dir_2d.x, 0.0, cursor_dir_2d.y) * effective_offset * offset_scale

	return target_3d + offset_3d


func _spring_follow(desired: Vector3, delta: float) -> void:
	var omega := smoothing_speed
	var exp_term := exp(-omega * delta)
	var delta_pos := _spring_pos - desired
	_spring_pos = desired + (delta_pos + (_spring_vel + omega * delta_pos) * delta) * exp_term
	_spring_vel = (_spring_vel - omega * omega * delta_pos * delta) * exp_term


func _update_height(delta: float) -> void:
	_current_height = lerpf(_current_height, _target_height, 1.0 - exp(-height_smoothing * delta))


func _place_camera() -> void:
	# Position the camera behind-and-above the look target based on tilt angle.
	var tilt_rad := deg_to_rad(tilt_degrees)
	# At 0° tilt: camera directly above. At 90°: camera at same height looking sideways.
	# We keep the look-at point on the ground plane and back the camera off.
	var back_offset := _current_height * tan(tilt_rad)
	var cam_offset := Vector3(0.0, _current_height, back_offset)

	global_position = _spring_pos + cam_offset
	look_at(_spring_pos, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_target_height = clampf(_target_height * (1.0 - scroll_step), min_height, max_height)
			MOUSE_BUTTON_WHEEL_DOWN:
				_target_height = clampf(_target_height * (1.0 + scroll_step), min_height, max_height)


# --- Helpers ---

## Convert 2D physics world position to 3D world position.
static func _ship_to_3d(pos2d: Vector2) -> Vector3:
	return Vector3(pos2d.x, 0.0, -pos2d.y) / PIXELS_PER_UNIT
