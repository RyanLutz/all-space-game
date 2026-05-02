extends Node3D
class_name StarRegistry

## Owns the galaxy-wide star catalog for the session lifetime.
## Generates all StarRecords from a seed at startup, manages per-star LOD state,
## and drives the MultiMeshInstance3D for LOD 0 (galactic-scale point rendering).
##
## LOD levels:
##   0 — MultiMesh point (all distances > lod1_distance)
##   1 — Screen-space glow pass (fullscreen MeshInstance3D quad child of camera)
##   2 — StarMesh + OmniLight3D (spawned per-star within lod2_spawn_distance)
##
## Never chunk-streamed. All star data is always resident.

# ─── Dependencies ─────────────────────────────────────────────────────────────
var _perf: Node = null
var _camera: Camera3D = null

# ─── Catalog ──────────────────────────────────────────────────────────────────
var _catalog: Array[StarRecord] = []
var _galaxy_seed: int = 0
var _config: Dictionary = {}

# ─── LOD Config (cached from world_config) ───────────────────────────────────
var _lod1_distance: float = 80000.0
var _lod2_spawn_distance: float = 8000.0

# ─── Screen-Pass Tunables (cached from world_config.galaxy.lod) ──────────────
# Hard ceiling on how many stars we pack into the shader uniform array per
# frame. Must match the const in star_screen_pass.gdshader.
const MAX_SCREEN_PASS_STARS: int = 256

# min_pixel_radius is the visual size floor (in screen pixels) shared by the
# LOD 0 point shader and the LOD 1 screen-pass shader. Single source of
# truth — both shaders read this same value so the LOD 0->1 handoff cannot
# develop a size discontinuity if it is later tuned.
var _min_pixel_radius: float = 2.0

var _screen_pass_max_stars: int = MAX_SCREEN_PASS_STARS
var _glow_world_radius_multiplier: float = 3.0
var _glow_max_pixel_radius: float = 64.0
var _glow_intensity: float = 1.5
var _glow_core_radius: float = 0.15

# ─── MultiMesh (LOD 0) ───────────────────────────────────────────────────────
var _multimesh_instance: MultiMeshInstance3D = null
var _multimesh: MultiMesh = null

# ─── Screen-Pass (LOD 1) ─────────────────────────────────────────────────────
var _screen_pass_quad: MeshInstance3D = null
var _screen_pass_material: ShaderMaterial = null

# ─── Star Mesh (LOD 2) ───────────────────────────────────────────────────────
const _STAR_MESH_SCENE := preload("res://core/stars/StarMesh.tscn")
var _star_mesh_cfg: Dictionary = {}

# Pre-allocated uniform buffers — re-assigned to the shader each frame to
# avoid per-frame PackedVector4Array allocation churn.
var _u_pos_radius: PackedVector4Array = PackedVector4Array()
var _u_color: PackedVector4Array = PackedVector4Array()

# ─── Runtime Counts ──────────────────────────────────────────────────────────
var _screen_pass_stars: Array[StarRecord] = []
var _active_mesh_count: int = 0
var _lod_dirty: PackedByteArray = PackedByteArray()

# Hidden transform — moves an instance far off-screen so it doesn't render.
const _HIDDEN_TRANSFORM := Transform3D(Basis.IDENTITY, Vector3(1e9, 0.0, 1e9))


# ─── Initialisation ───────────────────────────────────────────────────────────

func _ready() -> void:
	var sl := Engine.get_singleton("ServiceLocator")
	_perf = sl.GetService("PerformanceMonitor")

	var world_config := _load_world_config()
	if not world_config.has("galaxy"):
		push_error("[StarRegistry] world_config.json missing 'galaxy' section")
		return

	_config = world_config["galaxy"]
	_galaxy_seed = int(_config.get("seed", 8675309))

	var lod_cfg: Dictionary = _config.get("lod", {})
	_lod1_distance       = float(lod_cfg.get("lod1_distance",      80000.0))
	_lod2_spawn_distance = float(lod_cfg.get("lod2_spawn_distance", 8000.0))
	_load_screen_pass_config(lod_cfg)
	_star_mesh_cfg = _config.get("star_mesh", {})

	_perf.begin("StarRegistry.generate")
	_catalog = _generate_catalog(_galaxy_seed, _config)
	_perf.end("StarRegistry.generate")

	_lod_dirty.resize(_catalog.size())
	_lod_dirty.fill(1)

	_setup_multimesh()
	_setup_screen_pass()

	print("[StarRegistry] Generated %d stars (seed %d)" % [_catalog.size(), _galaxy_seed])


func _physics_process(_delta: float) -> void:
	# Lazy-resolve camera — GameCamera is placed in the scene, not registered
	# at boot. Re-resolve if the camera was freed (scene change, etc).
	if _camera == null or not is_instance_valid(_camera):
		_camera = get_viewport().get_camera_3d()
		if _camera == null:
			return
		_attach_screen_pass_to_camera()

	_update_lod(_camera.global_position)


# ─── Galaxy Generation ────────────────────────────────────────────────────────

func _generate_catalog(seed: int, config: Dictionary) -> Array[StarRecord]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	var stars: Array[StarRecord] = []
	var total: int             = int(config.get("star_count",            3000))
	var galaxy_radius: float   = float(config.get("galaxy_radius",   500000.0))
	var thickness: float       = float(config.get("galaxy_thickness",  8000.0))
	var y_threshold: float     = float(config.get("destination_y_threshold", 1200.0))
	var type_weights: Dictionary = config.get("star_type_weights", {})
	var star_types: Dictionary   = config.get("star_types", {})

	stars.resize(total)
	for i in total:
		var record := StarRecord.new()
		record.id = i

		var angle := rng.randf() * TAU
		var dist  := _sample_galaxy_radius(rng, galaxy_radius)
		var y_off := rng.randf_range(-thickness, thickness)

		record.position  = Vector3(cos(angle) * dist, y_off, sin(angle) * dist)
		record.tier      = &"destination" if absf(y_off) <= y_threshold else &"backdrop"
		record.star_type = _pick_star_type(rng, type_weights)

		if star_types.has(record.star_type):
			_apply_type_stats(record, star_types[record.star_type], rng, config)

		stars[i] = record

	return stars


func _sample_galaxy_radius(rng: RandomNumberGenerator, galaxy_radius: float) -> float:
	# Two-component distribution: dense inner bulge + broader disc.
	# sqrt(u) over [0,1] gives uniform distribution over a 2D disc.
	if rng.randf() < 0.4:
		# Inner bulge: 40% of stars within 20% of galaxy radius
		return galaxy_radius * 0.20 * sqrt(rng.randf())
	else:
		# Outer disc: remaining stars across the full radius
		return galaxy_radius * sqrt(rng.randf())


func _pick_star_type(rng: RandomNumberGenerator, weights: Dictionary) -> StringName:
	var roll       := rng.randf()
	var cumulative := 0.0
	for type in weights:
		cumulative += float(weights[type])
		if roll <= cumulative:
			return StringName(type)
	# Fallback if weights don't sum to 1.0
	return StringName(weights.keys().back())


func _apply_type_stats(
		record: StarRecord,
		type_data: Dictionary,
		rng: RandomNumberGenerator,
		config: Dictionary) -> void:

	var r_range: Array = type_data.get("radius_range", [1000, 2000])
	record.radius = rng.randf_range(float(r_range[0]), float(r_range[1]))
	record.exclusion_radius = record.radius * float(config.get("exclusion_margin", 1.4))

	var color_arr: Array = type_data.get("color", [1.0, 1.0, 1.0, 1.0])
	record.color = Color(
		float(color_arr[0]), float(color_arr[1]),
		float(color_arr[2]), float(color_arr[3]))

	var e_range: Array = type_data.get("light_energy_range", [1.0, 3.0])
	record.light_energy = rng.randf_range(float(e_range[0]), float(e_range[1]))

	# OmniLight3D range = visual radius × per-type multiplier. Read once at
	# generation; LOD 2 spawn just copies it to the light node.
	var range_mult: float = float(type_data.get("light_range_multiplier", 6.0))
	record.light_range = record.radius * range_mult


# ─── MultiMesh Setup (LOD 0) ──────────────────────────────────────────────────

func _setup_multimesh() -> void:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(1.0, 1.0)

	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = preload("res://core/stars/star_point.gdshader")
	shader_mat.set_shader_parameter("min_pixel_radius", _min_pixel_radius)
	mesh.material = shader_mat

	_multimesh = MultiMesh.new()
	_multimesh.transform_format  = MultiMesh.TRANSFORM_3D
	_multimesh.use_custom_data   = true
	_multimesh.use_colors        = false
	_multimesh.mesh              = mesh
	_multimesh.instance_count    = _catalog.size()

	# Write all transforms and colors up-front; dirty flags handle per-frame deltas.
	for i in _catalog.size():
		var star := _catalog[i]
		_multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, star.position))
		_multimesh.set_instance_custom_data(i, star.color)

	_multimesh_instance = MultiMeshInstance3D.new()
	_multimesh_instance.name       = "StarMultiMesh"
	_multimesh_instance.multimesh  = _multimesh
	_multimesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_multimesh_instance)


# ─── LOD Update ───────────────────────────────────────────────────────────────

func _update_lod(camera_pos: Vector3) -> void:
	_perf.begin("StarRegistry.lod_update")

	_screen_pass_stars.clear()

	for i in _catalog.size():
		var star := _catalog[i]
		var dist := camera_pos.distance_to(star.position)
		var new_lod: int

		# Backdrop tier never reaches LOD 2 — clamp at 1 even when within
		# lod2_spawn_distance so it stays a screen-space glow only.
		if dist > _lod1_distance:
			new_lod = 0
		elif dist > _lod2_spawn_distance or star.tier == &"backdrop":
			new_lod = 1
		else:
			new_lod = 2

		var prev_lod: int = star.lod_state
		if new_lod != prev_lod:
			# LOD 2 ↔ {0,1} requires mesh lifecycle — spawn or despawn before
			# the state flip so the dirty flag accurately reflects rendering.
			if prev_lod == 2 and new_lod != 2:
				_despawn_mesh(star)
			elif new_lod == 2 and prev_lod != 2:
				_spawn_mesh(star)
			star.lod_state = new_lod
			_lod_dirty[i]  = 1

		# LOD 1 and LOD 2 both contribute to the screen-pass — at LOD 2 the
		# screen-pass glow halos around the mesh corona; depth-test makes the
		# opaque core occlude its own glow naturally.
		if star.lod_state >= 1:
			_screen_pass_stars.append(star)

	_update_multimesh()
	_update_shader_uniforms(camera_pos)

	_perf.end("StarRegistry.lod_update")
	_perf.set_count("StarRegistry.active_meshes",    _active_mesh_count)
	_perf.set_count("StarRegistry.screen_pass_count", _screen_pass_stars.size())


func _update_multimesh() -> void:
	for i in _catalog.size():
		if _lod_dirty[i] == 0:
			continue
		var star := _catalog[i]
		if star.lod_state == 0:
			_multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, star.position))
		else:
			# Star is handled by screen-pass (LOD 1) or mesh (LOD 2) — hide from MultiMesh.
			_multimesh.set_instance_transform(i, _HIDDEN_TRANSFORM)
		_lod_dirty[i] = 0


# ─── Screen-Pass Setup (LOD 1) ───────────────────────────────────────────────

func _load_screen_pass_config(lod_cfg: Dictionary) -> void:
	# Shared by both LOD 0 and LOD 1 — must be loaded before _setup_multimesh().
	_min_pixel_radius             = float(lod_cfg.get("min_pixel_radius",             2.0))
	_screen_pass_max_stars = mini(
		int(lod_cfg.get("screen_pass_max_stars", MAX_SCREEN_PASS_STARS)),
		MAX_SCREEN_PASS_STARS)
	_glow_world_radius_multiplier = float(lod_cfg.get("glow_world_radius_multiplier", 3.0))
	_glow_max_pixel_radius        = float(lod_cfg.get("glow_max_pixel_radius",       64.0))
	_glow_intensity               = float(lod_cfg.get("glow_intensity",               1.5))
	_glow_core_radius             = float(lod_cfg.get("glow_core_radius",             0.15))


## Builds the fullscreen MeshInstance3D + ShaderMaterial for the LOD 1 screen
## pass. The quad is intentionally created un-parented; it is attached as a
## child of the active Camera3D the first time the camera is resolved in
## _physics_process(). The vertex shader writes POSITION directly in NDC, so
## the quad's transform is irrelevant — being a camera child guarantees it
## is never frustum-culled and that PROJECTION_MATRIX/VIEW_MATRIX inside the
## shader resolve to the correct camera.
func _setup_screen_pass() -> void:
	var quad_mesh := QuadMesh.new()
	# size = (2,2) → VERTEX.xy spans [-1, 1] = full NDC, matching the shader.
	quad_mesh.size = Vector2(2.0, 2.0)

	_screen_pass_material = ShaderMaterial.new()
	_screen_pass_material.shader = preload("res://core/stars/star_screen_pass.gdshader")
	_screen_pass_material.set_shader_parameter("min_pixel_radius", _min_pixel_radius)
	_screen_pass_material.set_shader_parameter("max_pixel_radius", _glow_max_pixel_radius)
	_screen_pass_material.set_shader_parameter("intensity",        _glow_intensity)
	_screen_pass_material.set_shader_parameter("core_radius",      _glow_core_radius)
	_screen_pass_material.set_shader_parameter("star_count",       0)

	quad_mesh.material = _screen_pass_material

	_screen_pass_quad = MeshInstance3D.new()
	_screen_pass_quad.name = "StarScreenPass"
	_screen_pass_quad.mesh = quad_mesh
	_screen_pass_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_screen_pass_quad.gi_mode     = GeometryInstance3D.GI_MODE_DISABLED
	_screen_pass_quad.extra_cull_margin = 16384.0   # max — frustum cull never trims us

	# Pre-allocate uniform buffers at the shader's array size.
	_u_pos_radius.resize(MAX_SCREEN_PASS_STARS)
	_u_color.resize(MAX_SCREEN_PASS_STARS)


## Re-parents the screen-pass quad onto the resolved Camera3D. Idempotent —
## safe to call every camera-resolution attempt.
func _attach_screen_pass_to_camera() -> void:
	if _screen_pass_quad == null or _camera == null:
		return
	if _screen_pass_quad.get_parent() == _camera:
		return
	if _screen_pass_quad.get_parent() != null:
		_screen_pass_quad.get_parent().remove_child(_screen_pass_quad)
	_camera.add_child(_screen_pass_quad)
	_screen_pass_quad.position = Vector3.ZERO
	_screen_pass_quad.rotation = Vector3.ZERO


## Packs the visible-star list into the shader's uniform arrays. If the list
## exceeds the per-frame cap, sort by camera distance and keep the closest N
## (closer stars are bigger on screen and matter more visually). Frustum
## culling is deferred to Phase 5.
func _update_shader_uniforms(camera_pos: Vector3) -> void:
	if _screen_pass_material == null:
		return

	var n: int = _screen_pass_stars.size()
	if n > _screen_pass_max_stars:
		_screen_pass_stars.sort_custom(
			func(a: StarRecord, b: StarRecord) -> bool:
				return camera_pos.distance_squared_to(a.position) \
					<  camera_pos.distance_squared_to(b.position)
		)
		_screen_pass_stars.resize(_screen_pass_max_stars)
		n = _screen_pass_max_stars

	for i in n:
		var star: StarRecord = _screen_pass_stars[i]
		var glow_radius: float = star.radius * _glow_world_radius_multiplier
		_u_pos_radius[i] = Vector4(star.position.x, star.position.y, star.position.z, glow_radius)
		_u_color[i]      = Vector4(star.color.r, star.color.g, star.color.b, star.color.a)

	_screen_pass_material.set_shader_parameter("star_count",     n)
	_screen_pass_material.set_shader_parameter("star_pos_radius", _u_pos_radius)
	_screen_pass_material.set_shader_parameter("star_color",     _u_color)


# ─── LOD 2 Mesh Lifecycle ─────────────────────────────────────────────────────

## Instantiates a StarMesh, configures it from the StarRecord and the cached
## star_mesh tunable block, and parents it to this registry. Idempotent —
## bails if a mesh is already present. Backdrop guard is upstream in
## _update_lod(); no defensive check here.
func _spawn_mesh(star: StarRecord) -> void:
	if star.mesh_node != null and is_instance_valid(star.mesh_node):
		return

	var instance: Node3D = _STAR_MESH_SCENE.instantiate()
	add_child(instance)
	# add_child must run before configure() so the @onready vars resolve.
	(instance as StarMesh).configure(star, _star_mesh_cfg)

	star.mesh_node = instance
	_active_mesh_count += 1


func _despawn_mesh(star: StarRecord) -> void:
	if star.mesh_node:
		star.mesh_node.queue_free()
		star.mesh_node = null
		_active_mesh_count = maxi(_active_mesh_count - 1, 0)


# ─── Public API ───────────────────────────────────────────────────────────────

func get_catalog() -> Array[StarRecord]:
	return _catalog


func get_star(id: int) -> StarRecord:
	if id >= 0 and id < _catalog.size():
		return _catalog[id]
	return null


# ─── Helpers ──────────────────────────────────────────────────────────────────

func _load_world_config() -> Dictionary:
	var file := FileAccess.open("res://data/world_config.json", FileAccess.READ)
	if file == null:
		push_error("[StarRegistry] Cannot open data/world_config.json")
		return {}
	var json := JSON.new()
	var err  := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("[StarRegistry] JSON parse error in world_config.json: %s" % json.get_error_message())
		return {}
	return json.data
