extends Node3D

## StarField Session 1 test scene — galaxy catalog preview.
##
## Renders the full star catalog as colored points via MultiMeshInstance3D
## viewed from a top-down Camera3D. Use this to verify galaxy shape: spiral
## arms, core density, color gradient, Y-thickness, and destination distribution.
##
## Controls:
##   WASD / Arrow keys  — pan camera
##   Mouse wheel        — zoom (camera height)
##   Shift              — fast pan
##   Right-click drag   — orbit (yaw + pitch)
##   R                  — regenerate with current seed
##   N                  — increment seed and regenerate
##   T                  — toggle destination-only view
##   1                  — top-down view (default)
##   2                  — 45-degree perspective view
##   3                  — edge-on view (see disc thickness)

@onready var camera: Camera3D = $TopCamera
@onready var multi_mesh_instance: MultiMeshInstance3D = $GalaxyPreview
@onready var nebula_preview: MultiMeshInstance3D = $NebulaPreview
@onready var stats_label: Label = $DebugOverlay/Panel/Stats

var _starfield: Node = null
var _perf: Node = null

var _cam_target := Vector3.ZERO
var _cam_height := 150000.0
var _pan_speed := 3000.0
var _show_destinations_only := false
var _orbiting := false
var _orbit_yaw := 0.0
var _orbit_pitch := -PI / 2.0

const POINT_MESH_SIZE := 120.0
const DEST_MESH_SIZE := 400.0
const NEBULA_MESH_ALPHA := 0.12


func _ready() -> void:
	var sl = Engine.get_singleton("ServiceLocator")
	if sl:
		_perf = sl.GetService("PerformanceMonitor")

	# StarField is an autoload registered in project.godot (or added by
	# GameBootstrap). For the standalone test scene it may not exist yet —
	# instantiate it manually if needed.
	_starfield = _get_or_create_starfield()
	if _starfield == null:
		push_error("StarFieldTest: could not obtain StarField instance")
		return

	_rebuild_preview()
	_rebuild_nebula_preview()
	_update_camera()


func _get_or_create_starfield() -> Node:
	# Try the autoload first
	var sf = get_node_or_null("/root/StarField")
	if sf:
		return sf

	# Fallback: instantiate one as a child so the test works standalone
	var script := load("res://core/starfield/StarField.gd")
	if script == null:
		return null
	var node := Node.new()
	node.set_script(script)
	node.name = "StarField"
	add_child(node)
	return node


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = event.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _orbiting else Input.MOUSE_MODE_VISIBLE
		elif event.pressed:
			match event.button_index:
				MOUSE_BUTTON_WHEEL_UP:
					_cam_height = maxf(_cam_height * 0.85, 5000.0)
					_update_camera()
				MOUSE_BUTTON_WHEEL_DOWN:
					_cam_height = minf(_cam_height * 1.18, 500000.0)
					_update_camera()
	elif event is InputEventMouseMotion and _orbiting:
		_orbit_yaw -= event.relative.x * 0.004
		_orbit_pitch = clampf(_orbit_pitch - event.relative.y * 0.004, -PI / 2.0, -0.05)
		_update_camera()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_R:
				_starfield.generate_catalog()
				_rebuild_preview()
				_rebuild_nebula_preview()
			KEY_N:
				_starfield._galaxy_seed += 1
				_starfield._config["galaxy_seed"] = _starfield._galaxy_seed
				_starfield.generate_catalog()
				_rebuild_preview()
				_rebuild_nebula_preview()
			KEY_T:
				_show_destinations_only = not _show_destinations_only
				_rebuild_preview()
			KEY_1:
				_orbit_pitch = -PI / 2.0
				_orbit_yaw = 0.0
				_update_camera()
			KEY_2:
				_orbit_pitch = -PI / 4.0
				_update_camera()
			KEY_3:
				_orbit_pitch = -0.15
				_update_camera()


func _process(delta: float) -> void:
	_handle_pan(delta)
	_update_overlay()


func _handle_pan(delta: float) -> void:
	var speed := _pan_speed * (_cam_height / 50000.0)
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= 4.0

	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move.z -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move.z += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move.x += 1.0

	if move != Vector3.ZERO:
		_cam_target += move.normalized() * speed * delta
		_update_camera()


func _update_camera() -> void:
	# Spherical orbit around _cam_target
	var dir := Vector3(
		cos(_orbit_pitch) * sin(_orbit_yaw),
		sin(-_orbit_pitch),
		cos(_orbit_pitch) * cos(_orbit_yaw))
	camera.global_position = _cam_target + dir * _cam_height
	camera.look_at(_cam_target, Vector3.UP)


# ---------------------------------------------------------------------------
#  Galaxy preview rendering via MultiMeshInstance3D
# ---------------------------------------------------------------------------

func _rebuild_preview() -> void:
	var catalog: Array[SFStarRecord]
	if _show_destinations_only:
		catalog = _starfield.get_destinations()
	else:
		catalog = _starfield.get_catalog()

	if catalog.is_empty():
		return

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = catalog.size()

	# Point mesh — small quad used per-instance
	var qm := QuadMesh.new()
	qm.size = Vector2(POINT_MESH_SIZE, POINT_MESH_SIZE)
	mm.mesh = qm

	for i in catalog.size():
		var star: SFStarRecord = catalog[i]
		var xf := Transform3D()
		xf.origin = star.galaxy_position

		# Billboard the quad to face up (XZ plane top-down view)
		xf.basis = Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.DOWN)

		var size: float = DEST_MESH_SIZE if star.is_destination else POINT_MESH_SIZE
		var s: float = size / POINT_MESH_SIZE
		xf.basis = xf.basis.scaled(Vector3(s, s, s))

		mm.set_instance_transform(i, xf)

		var c := star.color
		c.a = clampf(star.brightness, 0.3, 1.0)
		if star.is_destination:
			c.a = 1.0
		mm.set_instance_color(i, c)

	multi_mesh_instance.multimesh = mm

	# Unshaded material so colors are not affected by lighting
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	multi_mesh_instance.material_override = mat


func _rebuild_nebula_preview() -> void:
	var nebulae: Array[SFNebulaVolume] = _starfield.get_nebulae()
	if nebulae.is_empty():
		return

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = nebulae.size()

	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 16
	sphere.rings = 8
	mm.mesh = sphere

	for i in nebulae.size():
		var vol: SFNebulaVolume = nebulae[i]
		var xf := Transform3D()
		xf.origin = vol.galaxy_position
		xf.basis = Basis.IDENTITY.scaled(Vector3.ONE * vol.radius)
		mm.set_instance_transform(i, xf)

		var c := vol.color
		c.a = NEBULA_MESH_ALPHA
		mm.set_instance_color(i, c)

	nebula_preview.multimesh = mm

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	nebula_preview.material_override = mat


# ---------------------------------------------------------------------------
#  Debug overlay
# ---------------------------------------------------------------------------

func _update_overlay() -> void:
	if _starfield == null:
		return

	var catalog: Array = _starfield.get_catalog()
	var nebulae: Array = _starfield.get_nebulae()
	var fps: int = int(Engine.get_frames_per_second())

	var gen_ms := 0.0
	var backdrop_count := 0
	if _perf:
		gen_ms = float(_perf.get_avg_ms("StarField.generate"))
		backdrop_count = int(_perf.get_count("StarField.backdrop_count"))

	var dests: Array = _starfield.get_destinations()
	var view_mode := "destinations only" if _show_destinations_only else "all stars"
	var seed_val: int = _starfield.get_galaxy_seed()

	stats_label.text = (
		"FPS: %d  |  seed: %d  |  view: %s\n" % [fps, seed_val, view_mode]
		+ "catalog: %d  |  backdrops: %d  |  destinations: %d  |  nebulae: %d\n" % [
			catalog.size(), backdrop_count, dests.size(), nebulae.size()]
		+ "generate_ms: %.2f\n" % gen_ms
		+ "cam height: %.0f  |  target: (%.0f, %.0f)\n" % [
			_cam_height, _cam_target.x, _cam_target.z]
		+ "---\n"
		+ "WASD=pan  Wheel=zoom  RMB-drag=orbit  Shift=fast pan\n"
		+ "R=regen  N=next seed  T=toggle dests  1=top  2=45deg  3=edge-on"
	)
