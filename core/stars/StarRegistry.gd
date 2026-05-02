extends Node3D
class_name StarRegistry

## Owns the galaxy-wide star catalog for the session lifetime.
## Generates all StarRecords from a seed at startup, manages per-star LOD state,
## and drives the MultiMeshInstance3D for LOD 0 (galactic-scale point rendering).
##
## LOD levels:
##   0 — MultiMesh point (all distances > lod1_distance)
##   1 — Screen-space glow pass  [stub: implemented in Phase 2]
##   2 — StarMesh + OmniLight3D  [stub: implemented in Phase 3]
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

# ─── MultiMesh (LOD 0) ───────────────────────────────────────────────────────
var _multimesh_instance: MultiMeshInstance3D = null
var _multimesh: MultiMesh = null

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

	_perf.begin("StarRegistry.generate")
	_catalog = _generate_catalog(_galaxy_seed, _config)
	_perf.end("StarRegistry.generate")

	_lod_dirty.resize(_catalog.size())
	_lod_dirty.fill(1)

	_setup_multimesh()

	print("[StarRegistry] Generated %d stars (seed %d)" % [_catalog.size(), _galaxy_seed])


func _physics_process(_delta: float) -> void:
	# Lazy-resolve camera — GameCamera is placed in the scene, not registered at boot.
	if _camera == null:
		_camera = get_viewport().get_camera_3d()
		if _camera == null:
			return

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


# ─── MultiMesh Setup (LOD 0) ──────────────────────────────────────────────────

func _setup_multimesh() -> void:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(1.0, 1.0)

	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = preload("res://core/stars/star_point.gdshader")
	shader_mat.set_shader_parameter("min_pixel_radius", 2.0)
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

		if dist > _lod1_distance:
			new_lod = 0
		elif dist > _lod2_spawn_distance:
			new_lod = 1
		else:
			if star.tier == &"backdrop":
				continue
			new_lod = 2

		if new_lod != star.lod_state:
			star.lod_state = new_lod
			_lod_dirty[i] = 1

			# Phase 2: spawn/despawn screen-pass entry
			# Phase 3: _spawn_mesh / _despawn_mesh

		if star.lod_state >= 1:
			_screen_pass_stars.append(star)

	_update_multimesh()

	# Phase 2: _update_shader_uniforms(_screen_pass_stars)

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


# ─── Phase 3 Stubs ────────────────────────────────────────────────────────────

func _spawn_mesh(_star: StarRecord) -> void:
	pass  # Implemented in Phase 3


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
