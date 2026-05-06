extends Node3D

## StarField Session 1 + 3 test scene — galaxy catalog preview and skybox validation.
##
## S1: Renders the full star catalog as colored points via MultiMeshInstance3D
##     viewed from a top-down Camera3D. Verify galaxy shape, spiral arms, core
##     density, color gradient, Y-thickness, and destination distribution.
##
## S3: Adds a live galaxy sky (WorldEnvironment + galaxy_sky.gdshader) rendered
##     behind the MultiMesh preview. Warp simulation shows the skybox shifting
##     correctly as player_galaxy_position changes.
##
## S2: Galactic map overlay — press M to open, click a reachable system to warp.
##
## Controls:
##   WASD / Arrow keys  — pan camera
##   Mouse wheel        — zoom (camera height)
##   Shift              — fast pan
##   Right-click drag   — orbit (yaw + pitch)
##   R                  — regenerate catalog (also rebuilds skybox)
##   N                  — increment seed and regenerate
##   T                  — toggle destination-only view
##   Space              — warp: jump to next destination system (skybox shifts)
##   Backspace          — warp: jump back to galaxy center
##   M                  — open galactic map overlay
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

# Skybox / warp simulation state
var _sky_material: ShaderMaterial = null
var _warp_dest_idx: int = 0
var _current_system_pos: Vector3 = Vector3.ZERO
var _last_rebuild_ms: float = 0.0

# Galactic map state
var _map_open: bool = false
var _galactic_map: Control = null

const POINT_MESH_SIZE := 120.0
const DEST_MESH_SIZE := 400.0
const NEBULA_MESH_ALPHA := 0.12


func _ready() -> void:
	var sl = Engine.get_singleton("ServiceLocator")
	if sl:
		_perf = sl.GetService("PerformanceMonitor")

	# StarField is an autoload registered in project.godot.
	# Fall back to manual instantiation so the test works standalone.
	_starfield = _get_or_create_starfield()
	if _starfield == null:
		push_error("StarFieldTest: could not obtain StarField instance")
		return

	_rebuild_preview()
	_rebuild_nebula_preview()
	_setup_skybox()
	_setup_galactic_map()
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
				_do_rebuild_skybox(_current_system_pos)
			KEY_N:
				_starfield._galaxy_seed += 1
				_starfield._config["galaxy_seed"] = _starfield._galaxy_seed
				_starfield.generate_catalog()
				_rebuild_preview()
				_rebuild_nebula_preview()
				_do_rebuild_skybox(_current_system_pos)
			KEY_T:
				_show_destinations_only = not _show_destinations_only
				_rebuild_preview()
			KEY_M:
				_toggle_galactic_map()
			KEY_SPACE:
				_warp_to_next_destination()
			KEY_BACKSPACE:
				_warp_to_position(Vector3.ZERO, "galaxy center")
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
#  Skybox setup (S3) — creates WorldEnvironment + galaxy_sky.gdshader
# ---------------------------------------------------------------------------

## Creates the WorldEnvironment, Sky resource, and ShaderMaterial at runtime.
## Wires the ShaderMaterial to StarField.sky_material, then does the initial
## skybox build from the first destination system's galaxy position.
func _setup_skybox() -> void:
	if _starfield == null:
		return

	var shader := load("res://core/starfield/galaxy_sky.gdshader") as Shader
	if shader == null:
		push_error("StarFieldTest: cannot load galaxy_sky.gdshader")
		return

	var mat := ShaderMaterial.new()
	mat.shader = shader
	_sky_material = mat

	var sky_res := Sky.new()
	sky_res.sky_material = mat
	# PROCESS_MODE_QUALITY: sky re-renders when any parameter changes.
	sky_res.process_mode = Sky.PROCESS_MODE_QUALITY

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky_res
	# Slight ambient boost so the galaxy preview points are visible against the sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.5

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	# Wire to StarField so rebuild_skybox() can upload to this material
	_starfield.sky_material = mat

	# Initial build — start at the first destination system so we immediately
	# see a real nebula sky rather than a blank background
	var dests: Array[SFStarRecord] = _starfield.get_destinations()
	if dests.size() > 0:
		_current_system_pos = dests[0].galaxy_position
	else:
		_current_system_pos = Vector3.ZERO

	_do_rebuild_skybox(_current_system_pos)


## Creates GalacticMap inside a CanvasLayer and wires GameEventBus signals.
func _setup_galactic_map() -> void:
	var map_scene := load("res://ui/galactic_map/GalacticMap.tscn") as PackedScene
	if map_scene == null:
		push_error("StarFieldTest: cannot load GalacticMap.tscn")
		return

	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)

	_galactic_map = map_scene.instantiate() as Control
	_galactic_map.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_galactic_map)

	var bus := get_node_or_null("/root/GameEventBus")
	if bus:
		bus.warp_destination_selected.connect(_on_warp_destination_selected)
		bus.galactic_map_toggled.connect(func(open: bool) -> void:
			_map_open = open)


func _toggle_galactic_map() -> void:
	_map_open = not _map_open
	var bus := get_node_or_null("/root/GameEventBus")
	if bus:
		bus.galactic_map_toggled.emit(_map_open)


## Called when the player selects a destination in the galactic map.
## Simulates a warp jump in the test scene.
func _on_warp_destination_selected(system_id: StringName) -> void:
	if _starfield == null:
		return
	for star: SFStarRecord in _starfield.get_destinations():
		if star.system_id == system_id:
			_starfield.current_system = star
			_warp_dest_idx = _starfield.get_destinations().find(star)
			_warp_to_position(star.galaxy_position,
				"map selection: %s" % system_id)
			# Close the map after selecting
			_map_open = false
			var bus := get_node_or_null("/root/GameEventBus")
			if bus:
				bus.galactic_map_toggled.emit(false)
			return


## Rebuilds the skybox from `pos` and records timing for the overlay.
func _do_rebuild_skybox(pos: Vector3) -> void:
	if _starfield == null or _sky_material == null:
		return
	var t0 := Time.get_ticks_usec()
	_starfield.rebuild_skybox(pos)
	_last_rebuild_ms = float(Time.get_ticks_usec() - t0) / 1000.0


## Advance to the next destination system and rebuild the skybox from there.
## Simulates a player warp jump — verifies that the skybox shifts plausibly.
func _warp_to_next_destination() -> void:
	var dests: Array[SFStarRecord] = _starfield.get_destinations()
	if dests.is_empty():
		return
	_warp_dest_idx = (_warp_dest_idx + 1) % dests.size()
	var dest: SFStarRecord = dests[_warp_dest_idx]
	_warp_to_position(dest.galaxy_position,
		"sys %s  [%d / %d]" % [dest.system_id, _warp_dest_idx + 1, dests.size()])


## Moves the "player system" to `pos` and rebuilds the skybox from there.
func _warp_to_position(pos: Vector3, label: String) -> void:
	_current_system_pos = pos
	_do_rebuild_skybox(pos)
	print("StarFieldTest: warped to %s at %s" % [label, pos])


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

	var rebuild_ms := _last_rebuild_ms
	var sys_pos    := _current_system_pos

	stats_label.text = (
		"FPS: %d  |  seed: %d  |  view: %s\n" % [fps, seed_val, view_mode]
		+ "catalog: %d  |  backdrops: %d  |  destinations: %d  |  nebulae: %d\n" % [
			catalog.size(), backdrop_count, dests.size(), nebulae.size()]
		+ "generate_ms: %.2f  |  skybox_rebuild_ms: %.2f\n" % [gen_ms, rebuild_ms]
		+ "current system: (%.0f, %.0f, %.0f)\n" % [sys_pos.x, sys_pos.y, sys_pos.z]
		+ "cam height: %.0f  |  target: (%.0f, %.0f)\n" % [
			_cam_height, _cam_target.x, _cam_target.z]
		+ "---\n"
		+ "WASD=pan  Wheel=zoom  RMB-drag=orbit  Shift=fast pan\n"
		+ "R=regen  N=next seed  T=toggle dests  1=top  2=45deg  3=edge-on\n"
		+ "Space=warp next dest  Backspace=warp to center  M=galactic map"
	)
