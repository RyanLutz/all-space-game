extends Camera3D
class_name GameCamera

## Camera system supporting Pilot mode (spring-follow) and Tactical mode
## (free-pan). Sits above and behind the follow target at a fixed angle.
## Position is driven by a critically damped spring; zoom is height on Y.
## Never a child of any ship — always a sibling of the game world.

# ─── Angle & Position ─────────────────────────────────────────────────────────
@export_group("Angle & Position")
@export var smoothing_speed: float = 10.0     # spring response; higher = snappier

# ─── Zoom ─────────────────────────────────────────────────────────────────────
@export_group("Zoom")
@export var height_min: float = 50.0         # closest zoom (camera Y)
@export var height_max: float = 2000.0        # farthest zoom (camera Y)
@export var height_default: float = 500.0     # starting zoom
@export var zoom_step: float = 50.0           # world units per scroll tick
@export var zoom_smoothing: float = 10.0      # zoom interpolation speed

# ─── Tactical Mode ───────────────────────────────────────────────────────────
@export_group("Tactical")
@export var tactical_height: float = 900.0          # zoom-out target on entering tactical
@export var tactical_height_min: float = 500.0      # zoom floor in tactical mode
@export var tactical_height_max: float = 2000.0     # zoom ceiling in tactical mode
@export var pan_speed: float = 800.0                # world units/sec for WASD pan
@export var edge_scroll_margin: float = 20.0        # pixels from screen edge to trigger scroll
@export var edge_scroll_speed: float = 600.0        # world units/sec for edge scroll

# ─── Runtime State ────────────────────────────────────────────────────────────
var _follow_target: Node3D = null
var _spring_velocity: Vector3 = Vector3.ZERO
var _target_height: float = 0.0
var _current_height: float = 0.0

var _tactical_mode: bool = false
var _saved_pilot_target: Node3D = null    # remembered for re-follow on exit tactical
var _pilot_height_min: float = 0.0       # stashed pilot zoom limits
var _pilot_height_max: float = 0.0

var _event_bus: Node = null
var _player_state: Node = null


func _ready() -> void:
	_current_height = height_default
	_target_height = height_default
	_pilot_height_min = height_min
	_pilot_height_max = height_max

	var service_locator := Engine.get_singleton("ServiceLocator")
	if service_locator:
		_event_bus = service_locator.GetService("GameEventBus")
		_player_state = service_locator.GetService("PlayerState")
		if _event_bus:
			_event_bus.connect("player_ship_changed", _on_player_ship_changed)
			_event_bus.connect("game_mode_changed", _on_game_mode_changed)

	var player := get_tree().get_first_node_in_group("player")
	if player is Node3D:
		follow(player)


# ─── Target Management ────────────────────────────────────────────────────────

func follow(target: Node3D) -> void:
	_follow_target = target
	_spring_velocity = Vector3.ZERO


func release() -> void:
	_follow_target = null
	_spring_velocity = Vector3.ZERO


func get_follow_target() -> Node3D:
	return _follow_target


func set_zoom_limits(min_h: float, max_h: float) -> void:
	height_min = min_h
	height_max = max_h
	_target_height = clampf(_target_height, height_min, height_max)


func _on_player_ship_changed(ship: Node) -> void:
	if _tactical_mode:
		# Don't re-follow during tactical — just remember for when we exit
		_saved_pilot_target = ship as Node3D
		return
	if ship is Node3D:
		follow(ship)
	else:
		release()


# ─── Mode Switching ──────────────────────────────────────────────────────────

func _on_game_mode_changed(_old_mode: String, new_mode: String) -> void:
	if new_mode == "tactical":
		_enter_tactical()
	else:
		_exit_tactical()


func _enter_tactical() -> void:
	_tactical_mode = true
	_saved_pilot_target = _follow_target
	release()

	# Switch to tactical zoom limits and zoom out
	set_zoom_limits(tactical_height_min, tactical_height_max)
	_target_height = clampf(tactical_height, height_min, height_max)

	print("[GameCamera] Entering tactical mode — free pan enabled")


func _exit_tactical() -> void:
	_tactical_mode = false

	# Restore pilot zoom limits
	set_zoom_limits(_pilot_height_min, _pilot_height_max)
	_target_height = clampf(_current_height, height_min, height_max)

	# Re-follow the player ship
	var target := _saved_pilot_target
	if target == null or not is_instance_valid(target):
		# Try PlayerState as fallback
		if _player_state and _player_state.active_ship:
			target = _player_state.active_ship
	if target:
		follow(target)
	_saved_pilot_target = null

	print("[GameCamera] Exiting tactical mode — following player")


# ─── Cursor ───────────────────────────────────────────────────────────────────

## Returns the world-space XZ position under the mouse cursor.
## Uses ray-plane intersection against Y = 0 — get_global_mouse_position() does
## not exist in 3D. Returns Vector3.ZERO as a fallback (cursor above horizon).
func get_cursor_world_position() -> Vector3:
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var ray_origin: Vector3 = project_ray_origin(mouse_pos)
	var ray_dir: Vector3 = project_ray_normal(mouse_pos)
	var play_plane := Plane(Vector3.UP, 0.0)
	var intersect = play_plane.intersects_ray(ray_origin, ray_dir)
	if intersect != null:
		return intersect
	return Vector3.ZERO


# ─── Position Computation ─────────────────────────────────────────────────────

func _compute_desired_position() -> Vector3:
	if _follow_target == null:
		return global_position

	var target_pos: Vector3 = _follow_target.global_position

	# Position camera behind target based on current tilt angle
	# No cursor offset - fixed position relative to target
	var tilt_angle := _get_tilt_for_height()
	var depth_back: float = _current_height * tan(deg_to_rad(90.0 - tilt_angle))

	return Vector3(
		target_pos.x,
		_current_height,
		target_pos.z + depth_back
	)


## Critically damped spring follow — no overshoot, no oscillation, frame-rate
## independent. Integrates internal spring velocity across frames.
func _smooth_follow(desired: Vector3, delta: float) -> Vector3:
	var omega: float = smoothing_speed
	var exp_term: float = exp(-omega * delta)

	var delta_pos: Vector3 = global_position - desired
	var new_pos: Vector3 = desired + (delta_pos + (_spring_velocity + omega * delta_pos) * delta) * exp_term
	_spring_velocity = (_spring_velocity - omega * omega * delta_pos * delta) * exp_term

	return new_pos


func _get_tilt_for_height() -> float:
	# Map height to tilt angle: 45° at zoom_in (height_min) to 90° at zoom_out (height_max)
	var t := (_current_height - height_min) / (height_max - height_min)
	return lerpf(45.0, 90.0, clampf(t, 0.0, 1.0))


func _update_orientation() -> void:
	# Fixed orientation - no rotation based on target or mouse
	# Camera tilt: 45° (angled) at zoom_in to 90° (top-down) at zoom_out
	# In Godot, negative X rotation looks downward
	var tilt_angle := _get_tilt_for_height()
	rotation_degrees = Vector3(-tilt_angle, 0, 0)


# ─── Tactical Pan ────────────────────────────────────────────────────────────

func _compute_pan_velocity(delta: float) -> Vector3:
	var pan := Vector3.ZERO

	# WASD pan (uses same input actions, but InputManager doesn't route them
	# to the ship in tactical mode — they come through as raw axis here)
	var fwd := Input.get_axis("move_backward", "move_forward")
	var strafe := Input.get_axis("move_left", "move_right")
	pan.z -= fwd   # forward = -Z in world
	pan.x += strafe

	# Edge scroll
	var viewport := get_viewport()
	if viewport:
		var mouse_pos := viewport.get_mouse_position()
		var screen_size := viewport.get_visible_rect().size
		if mouse_pos.x < edge_scroll_margin:
			pan.x -= 1.0
		elif mouse_pos.x > screen_size.x - edge_scroll_margin:
			pan.x += 1.0
		if mouse_pos.y < edge_scroll_margin:
			pan.z -= 1.0
		elif mouse_pos.y > screen_size.y - edge_scroll_margin:
			pan.z += 1.0

	if pan.length_squared() > 1.0:
		pan = pan.normalized()

	# Scale pan speed with height — panning should feel consistent at any zoom
	var height_scale := _current_height / height_default
	return pan * pan_speed * height_scale * delta


# ─── Zoom ─────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_target_height = clampf(_target_height - zoom_step, height_min, height_max)
			MOUSE_BUTTON_WHEEL_DOWN:
				_target_height = clampf(_target_height + zoom_step, height_min, height_max)


func _update_zoom(delta: float) -> void:
	_current_height = lerpf(
		_current_height,
		_target_height,
		1.0 - exp(-zoom_smoothing * delta)
	)


# ─── Main Loop ────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if not is_inside_tree():
		return

	if _follow_target != null and not is_instance_valid(_follow_target):
		release()

	_update_zoom(delta)

	if _tactical_mode:
		# Free-pan: move position directly, no spring follow
		var pan_delta := _compute_pan_velocity(delta)
		global_position.x += pan_delta.x
		global_position.z += pan_delta.z
		global_position.y = _current_height
		_update_orientation()
	else:
		var desired: Vector3 = _compute_desired_position()
		global_position = _smooth_follow(desired, delta)
		_update_orientation()
