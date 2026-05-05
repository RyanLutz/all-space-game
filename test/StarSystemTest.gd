extends Node3D

## Phase 2 verification scene for the Star System.
##
## Provides a fly-camera to traverse LOD bands (galactic → mid → close), a
## handful of opaque box occluders to verify the screen-pass depth-test
## interaction (boxes must visibly occlude star glow), and a debug overlay
## reading PerformanceMonitor counters.
##
## Controls:
##   WASD              — pan camera in look direction / strafe
##   Q / E             — descend / ascend
##   Right-mouse drag  — look (yaw + pitch)
##   Shift / Ctrl      — boost / fine speed
##   Mouse wheel       — adjust base pan speed multiplier
##   1                 — bookmark: galaxy outer edge, look inward
##   2                 — bookmark: mid-galaxy, look toward core
##   3                 — bookmark: galactic core
##   4                 — teleport near nearest destination star (just outside LOD 2)

@onready var camera: Camera3D = $TestCamera
@onready var fps_label: Label = $DebugOverlay/Panel/Stats

var _pan_base_speed: float = 200.0
var _yaw: float = 0.0
var _pitch: float = -0.2
var _looking: bool = false

var _star_registry: Node = null
var _perf: Node = null

func _ready() -> void:
	var sl := Engine.get_singleton("ServiceLocator")
	if sl:
		_star_registry = sl.GetService("StarRegistry")
		_perf = sl.GetService("PerformanceMonitor")

	camera.rotation = Vector3(_pitch, _yaw, 0.0)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_looking = event.pressed
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _looking else Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and _looking:
		_yaw   -= event.relative.x * 0.0035
		_pitch -= event.relative.y * 0.0035
		_pitch = clampf(_pitch, -PI * 0.49, PI * 0.49)
		camera.rotation = Vector3(_pitch, _yaw, 0.0)
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_pan_base_speed = minf(_pan_base_speed * 1.5, 5_000_000.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				_pan_base_speed = maxf(_pan_base_speed / 1.5, 5.0)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1: _bookmark_outer_edge()
			KEY_2: _bookmark_mid_galaxy()
			KEY_3: _bookmark_galactic_core()
			KEY_4: _bookmark_near_star()


func _process(delta: float) -> void:
	_handle_fly(delta)
	_update_overlay()


func _handle_fly(delta: float) -> void:
	var speed := _pan_base_speed
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= 10.0
	if Input.is_key_pressed(KEY_CTRL):
		speed *= 0.1

	var move := Vector3.ZERO
	var cam_basis := camera.transform.basis
	if Input.is_key_pressed(KEY_W): move -= cam_basis.z
	if Input.is_key_pressed(KEY_S): move += cam_basis.z
	if Input.is_key_pressed(KEY_A): move -= cam_basis.x
	if Input.is_key_pressed(KEY_D): move += cam_basis.x
	if Input.is_key_pressed(KEY_E): move += Vector3.UP
	if Input.is_key_pressed(KEY_Q): move -= Vector3.UP

	if move != Vector3.ZERO:
		camera.global_position += move.normalized() * speed * delta


func _update_overlay() -> void:
	if _star_registry == null or _perf == null:
		return

	var screen_pass: int   = int(_perf.get_count("StarRegistry.screen_pass_count"))
	var active_meshes: int = int(_perf.get_count("StarRegistry.active_meshes"))
	var lod_ms: float      = float(_perf.get_avg_ms("StarRegistry.lod_update"))
	var gen_ms: float      = float(_perf.get_avg_ms("StarRegistry.generate"))
	var fps: int           = int(Engine.get_frames_per_second())
	var pos: Vector3       = camera.global_position

	var nearest_dist := INF
	var nearest_type := "—"
	var nearest_tier := "—"
	var nearest_lod  := -1
	for star in _star_registry.get_catalog():
		var d: float = pos.distance_to(star.position)
		if d < nearest_dist:
			nearest_dist = d
			nearest_type = String(star.star_type)
			nearest_tier = String(star.tier)
			nearest_lod  = int(star.lod_state)

	fps_label.text = (
		"FPS: %d   |   pan/sec: %.0f\n" % [fps, _pan_base_speed]
		+ "cam pos:   (%.0f, %.0f, %.0f)\n" % [pos.x, pos.y, pos.z]
		+ "lod_update_ms: %.3f   generate_ms: %.2f\n" % [lod_ms, gen_ms]
		+ "screen_pass_count: %d   active_meshes: %d\n" % [screen_pass, active_meshes]
		+ "nearest star: %s (%s) @ %.0fu  lod=%d" % [
			nearest_type, nearest_tier, nearest_dist, nearest_lod]
	)


# ─── Bookmarks ────────────────────────────────────────────────────────────────

func _bookmark_outer_edge() -> void:
	camera.global_position = Vector3(450_000.0, 2_000.0, 0.0)
	_yaw = -PI * 0.5
	_pitch = -0.1
	camera.rotation = Vector3(_pitch, _yaw, 0.0)


func _bookmark_mid_galaxy() -> void:
	camera.global_position = Vector3(150_000.0, 1_000.0, 0.0)
	_yaw = -PI * 0.5
	_pitch = -0.05
	camera.rotation = Vector3(_pitch, _yaw, 0.0)


func _bookmark_galactic_core() -> void:
	camera.global_position = Vector3(0.0, 500.0, 0.0)
	_yaw = 0.0
	_pitch = 0.0
	camera.rotation = Vector3(_pitch, _yaw, 0.0)


func _bookmark_near_star() -> void:
	if _star_registry == null:
		return
	var pos := camera.global_position
	var nearest: StarRecord = null
	var best := INF
	for star in _star_registry.get_catalog():
		if star.tier != &"destination":
			continue
		var d: float = pos.distance_to(star.position)
		if d < best:
			best = d
			nearest = star
	if nearest == null:
		return
	# Drop just outside the LOD 2 threshold so we sit firmly in screen-pass.
	var offset := Vector3(nearest.exclusion_radius * 6.0, 200.0, 0.0)
	camera.global_position = nearest.position + offset
	camera.look_at(nearest.position, Vector3.UP)
	# Sync our yaw/pitch trackers to the look_at result.
	var euler := camera.rotation
	_pitch = euler.x
	_yaw   = euler.y
