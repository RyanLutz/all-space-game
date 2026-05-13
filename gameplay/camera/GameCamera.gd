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
@export var tactical_height_max: float = 120000.0   # zoom ceiling in tactical mode (system scale)
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

# ─── Galaxy Map Mode ───────────────────────────────────────────────────────────
var _galaxy_map_active: bool = false
var _galaxy_map_camera_yaw: float = 0.0
var _galaxy_map_camera_pitch: float = 0.0
var _rmb_held: bool = false
var _last_click_time: int = 0
var _last_click_pos: Vector2 = Vector2.ZERO
var _active_selection: SFStarRecord = null

var _camera_move_speed: float = 50.0
var _camera_rotation_speed: float = 0.003

var _event_bus: Node = null
var _player_state: Node = null
var _galaxy_container: GalaxyContainer = null


func _ready() -> void:
	_current_height = height_default
	_target_height = height_default
	_pilot_height_min = height_min
	_pilot_height_max = height_max

	_load_galaxy_map_config()

	var service_locator := Engine.get_singleton("ServiceLocator")
	if service_locator:
		_event_bus = service_locator.GetService("GameEventBus")
		_player_state = service_locator.GetService("PlayerState")
		if _event_bus:
			_event_bus.connect("player_ship_changed", _on_player_ship_changed)
			_event_bus.connect("game_mode_changed", _on_game_mode_changed)

	_galaxy_container = get_node_or_null("GalaxyContainer")

	var player := get_tree().get_first_node_in_group("player")
	if player is Node3D:
		follow(player)


func _load_galaxy_map_config() -> void:
	var file := FileAccess.open("res://data/world_config.json", FileAccess.READ)
	if not file:
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		return
	var data: Dictionary = json.data
	if not data.has("galaxy_map"):
		return
	var cfg: Dictionary = data["galaxy_map"]
	_camera_move_speed = float(cfg.get("camera_move_speed", 50.0))
	_camera_rotation_speed = float(cfg.get("camera_rotation_speed", 0.003))


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

func _on_game_mode_changed(old_mode: String, new_mode: String) -> void:
	if old_mode == "galaxy_map":
		_exit_galaxy_map()
	elif old_mode == "tactical":
		_exit_tactical()

	if new_mode == "galaxy_map":
		_enter_galaxy_map()
	elif new_mode == "tactical":
		_enter_tactical()
	elif new_mode == "pilot":
		if _galaxy_map_active:
			_exit_galaxy_map()
		if _tactical_mode:
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


# ─── Galaxy Map Mode ───────────────────────────────────────────────────────────

func _enter_galaxy_map() -> void:
	_galaxy_map_active = true
	_galaxy_map_camera_yaw = rotation.y
	_galaxy_map_camera_pitch = rotation.x
	release()
	# Teleport camera to current system's galaxy position so the map is centered
	if _galaxy_container:
		global_position = _galaxy_container._current_system_pos
	if _event_bus:
		_event_bus.cinematic_active_changed.emit(false)
	print("[GameCamera] Entering galaxy map mode")


func _exit_galaxy_map() -> void:
	_galaxy_map_active = false
	_rmb_held = false
	_active_selection = null
	var ship = _player_state.get_active_ship() if _player_state else null
	if ship:
		follow(ship)
	print("[GameCamera] Exiting galaxy map mode")


func _galaxy_map_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var e := event as InputEventMouseButton
		if e.button_index == MOUSE_BUTTON_RIGHT:
			_rmb_held = e.pressed
		elif e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
			var now := Time.get_ticks_msec()
			var pos := get_viewport().get_mouse_position()
			if now - _last_click_time < 300 and pos.distance_to(_last_click_pos) < 10.0:
				_try_warp_select(pos)
			else:
				_try_select(pos)
			_last_click_time = now
			_last_click_pos = pos

	if event is InputEventMouseMotion and _rmb_held:
		_galaxy_map_camera_yaw -= event.relative.x * _camera_rotation_speed
		_galaxy_map_camera_pitch -= event.relative.y * _camera_rotation_speed
		_galaxy_map_camera_pitch = clampf(
			_galaxy_map_camera_pitch,
			deg_to_rad(-80.0),
			deg_to_rad(80.0)
		)
		rotation = Vector3(_galaxy_map_camera_pitch, _galaxy_map_camera_yaw, 0.0)


func _galaxy_map_process(delta: float) -> void:
	var move := Vector3.ZERO
	if Input.is_action_pressed("move_forward"):     move -= basis.z
	if Input.is_action_pressed("move_backward"):    move += basis.z
	if Input.is_action_pressed("move_left"):        move -= basis.x
	if Input.is_action_pressed("move_right"):       move += basis.x
	if Input.is_action_pressed("galaxy_map_up"):    move += Vector3.UP
	if Input.is_action_pressed("galaxy_map_down"):  move -= Vector3.UP

	if move.length_squared() > 0.0:
		global_position += move.normalized() * _camera_move_speed * delta


func _try_select(screen_pos: Vector2) -> void:
	var space := get_world_3d().direct_space_state
	var origin := project_ray_origin(screen_pos)
	var end := origin + project_ray_normal(screen_pos) * 10000.0
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	query.collide_with_areas = true
	var hit := space.intersect_ray(query)

	if hit and hit.collider is GalaxyStar:
		var star := (hit.collider as GalaxyStar).star_record
		if star.is_destination:
			_active_selection = star
			if _galaxy_container:
				_galaxy_container.select_star(star)
			if _event_bus:
				_event_bus.tactical_selection_changed.emit([star.system_id])
	else:
		_active_selection = null
		if _galaxy_container:
			_galaxy_container.clear_selection()


func _try_warp_select(screen_pos: Vector2) -> void:
	if _active_selection == null:
		_try_select(screen_pos)
	if _active_selection != null and _is_reachable(_active_selection):
		if _event_bus:
			_event_bus.warp_destination_selected.emit(_active_selection.system_id)
		_close_galaxy_map()


func _is_reachable(star: SFStarRecord) -> bool:
	var starfield := get_node_or_null("/root/StarField")
	if starfield == null or starfield.current_system == null:
		return false
	var current: SFStarRecord = starfield.current_system
	var dist := current.galaxy_position.distance_to(star.galaxy_position)
	return dist <= star.warp_range


func _close_galaxy_map() -> void:
	_galaxy_map_active = false
	if _event_bus:
		_event_bus.game_mode_changed.emit("galaxy_map", "pilot")


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
	if _galaxy_map_active:
		_galaxy_map_input(event)
		return

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

	if _galaxy_map_active:
		_galaxy_map_process(delta)
	elif _tactical_mode:
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
