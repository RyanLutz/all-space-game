extends Camera2D
class_name GameCamera

# GameCamera — independent Camera2D that follows a target with cursor-direction offset
# and critically damped spring smoothing.
#
# Architecture: sibling of the game world, never a child of any ship.
# Retarget with follow(target). Release with release().
# See docs/Camera_System_Spec.md.

@export_group("Follow")
@export var smoothing_speed: float = 10.0
@export var max_cursor_offset: float = 120.0

@export_group("Zoom")
@export var min_zoom: float = 0.5
@export var max_zoom: float = 2.5
@export var default_zoom: float = 1.0
@export var zoom_step: float = 0.1
@export var zoom_smoothing: float = 10.0

var _follow_target: Node2D = null
var _spring_velocity: Vector2 = Vector2.ZERO
var _target_zoom: float = 1.0

var _event_bus: Node


func _ready() -> void:
	_event_bus = ServiceLocator.GetService("GameEventBus") as Node

	# Follow the player ship once the scene tree is ready.
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player != null:
		follow(player)

	zoom = Vector2(default_zoom, default_zoom)
	_target_zoom = default_zoom

	# Retarget when the player ship changes (e.g. respawn, ship swap post-MVP).
	if _event_bus != null:
		_event_bus.connect("player_ship_changed", _on_player_ship_changed)


func _on_player_ship_changed(ship: Node2D) -> void:
	follow(ship)


# --- Public API ---

func follow(target: Node2D) -> void:
	_follow_target = target


func release() -> void:
	_follow_target = null
	_spring_velocity = Vector2.ZERO


func get_follow_target() -> Node2D:
	return _follow_target


# --- Process ---

func _physics_process(delta: float) -> void:
	# Gracefully handle destroyed follow target.
	if _follow_target != null and not is_instance_valid(_follow_target):
		release()

	var desired := _compute_desired_position()
	global_position = _smooth_follow(desired, delta)
	_update_zoom(delta)


func _compute_desired_position() -> Vector2:
	if _follow_target == null:
		return global_position  # hold position when no target (future: free-pan)

	var target_pos := _follow_target.global_position

	# Cursor offset: shift camera toward where the player is aiming.
	var screen_center := get_viewport_rect().size * 0.5
	var mouse_screen := get_viewport().get_mouse_position()
	var cursor_vec := mouse_screen - screen_center
	var cursor_offset_magnitude := clampf(cursor_vec.length() / screen_center.length(), 0.0, 1.0)
	var cursor_offset_dir := cursor_vec.normalized() if cursor_vec.length() > 0.1 else Vector2.ZERO

	# Scale offset inversely with zoom so it feels consistent at all zoom levels.
	var effective_offset := max_cursor_offset / zoom.x
	var offset := cursor_offset_dir * effective_offset * cursor_offset_magnitude

	return target_pos + offset


func _smooth_follow(desired: Vector2, delta: float) -> Vector2:
	# Critically damped spring — no overshoot, no oscillation.
	var omega: float = smoothing_speed
	var exp_term: float = exp(-omega * delta)

	var delta_pos := global_position - desired
	var new_pos := desired + (delta_pos + (_spring_velocity + omega * delta_pos) * delta) * exp_term
	_spring_velocity = (_spring_velocity - omega * omega * delta_pos * delta) * exp_term

	return new_pos


func _update_zoom(delta: float) -> void:
	var current := zoom.x
	var new_zoom := lerpf(current, _target_zoom, 1.0 - exp(-zoom_smoothing * delta))
	zoom = Vector2(new_zoom, new_zoom)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_target_zoom = clampf(_target_zoom - zoom_step, min_zoom, max_zoom)
			MOUSE_BUTTON_WHEEL_DOWN:
				_target_zoom = clampf(_target_zoom + zoom_step, min_zoom, max_zoom)
