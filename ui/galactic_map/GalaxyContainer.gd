class_name GalaxyContainer
extends Node3D

## Galaxy rendering root. Reads catalog from StarField autoload, manages LOD
## population updates, and drives the procedural field + billboard + mesh tiers.

# ─── Catalog refs ─────────────────────────────────────────────────────────────
var _catalog: Array[SFStarRecord] = []
var _destinations: Array[SFStarRecord] = []

# ─── Preloads ─────────────────────────────────────────────────────────────────
const _GalaxyBillboardFieldScript := preload("res://ui/galactic_map/GalaxyBillboardField.gd")

# ─── Tier managers ────────────────────────────────────────────────────────────
var _billboard_field: GalaxyBillboardField
var _star_container: Node3D
var _procedural_field: MeshInstance3D
var _mesh_star_nodes: Dictionary = {}   # star.id -> GalaxyStar node

# ─── State ────────────────────────────────────────────────────────────────────
var _spawn_check_timer: float = 0.0
var _current_system_pos: Vector3 = Vector3.ZERO
var _active_selection: SFStarRecord = null
var _last_cam_pos: Vector3 = Vector3.INF
var _cam_move_threshold: float = 5.0

# ─── Spatial grid ─────────────────────────────────────────────────────────────
var _spatial_grid: Dictionary = {}   # Vector3i -> Array[SFStarRecord]
var _grid_cell_size: float = 400.0

# ─── Config (loaded from world_config.json) ───────────────────────────────────
var galaxy_scale: float = 100.0
var lod_mesh_distance: float = 80.0
var lod_billboard_distance: float = 400.0
var lod_fade_range: float = 40.0
var spawn_check_interval: float = 0.25
var proc_field_cell_size: float = 800.0
var proc_field_sphere_radius: float = 8000.0

# ─── Services ─────────────────────────────────────────────────────────────────
var _perf: Node = null
var _event_bus: Node = null


func _ready() -> void:
	_load_config()
	_gather_catalog()
	_build_tiers()
	_connect_services()
	_register_monitors()
	_sync_current_system()


func _process(delta: float) -> void:
	# GalaxyContainer follows camera position but keeps world-aligned rotation
	var cam := get_parent()
	if cam is Node3D:
		global_transform = Transform3D(Basis.IDENTITY, cam.global_position)

	_update_procedural_field_uniforms()

	_spawn_check_timer += delta
	if _spawn_check_timer >= spawn_check_interval:
		_spawn_check_timer = 0.0
		_update_star_populations()


# ─── Config loading ───────────────────────────────────────────────────────────

func _load_config() -> void:
	var file := FileAccess.open("res://data/world_config.json", FileAccess.READ)
	if not file:
		push_error("GalaxyContainer: cannot open world_config.json")
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("GalaxyContainer: JSON parse error — %s" % json.get_error_message())
		return

	var data: Dictionary = json.data
	if not data.has("galaxy_map"):
		push_error("GalaxyContainer: world_config.json missing 'galaxy_map' block")
		return

	var cfg: Dictionary = data["galaxy_map"]
	galaxy_scale = float(cfg.get("galaxy_scale", 100.0))
	lod_mesh_distance = float(cfg.get("lod_mesh_distance", 80.0))
	lod_billboard_distance = float(cfg.get("lod_billboard_distance", 400.0))
	lod_fade_range = float(cfg.get("lod_fade_range", 40.0))
	spawn_check_interval = float(cfg.get("star_spawn_check_interval", 0.25))
	proc_field_cell_size = float(cfg.get("proc_field_cell_size", 800.0))
	proc_field_sphere_radius = float(cfg.get("proc_field_sphere_radius", 8000.0))


# ─── Catalog ──────────────────────────────────────────────────────────────────

func _gather_catalog() -> void:
	var starfield := get_node_or_null("/root/StarField")
	if starfield == null:
		push_error("GalaxyContainer: StarField autoload not found")
		return
	_catalog = starfield.get_catalog()
	_destinations = starfield.get_destinations()
	_build_spatial_grid()


func _build_spatial_grid() -> void:
	_spatial_grid.clear()
	for star: SFStarRecord in _catalog:
		var pos := _scaled_pos(star)
		var cell := Vector3i(
			floori(pos.x / _grid_cell_size),
			floori(pos.y / _grid_cell_size),
			floori(pos.z / _grid_cell_size)
		)
		if not _spatial_grid.has(cell):
			_spatial_grid[cell] = []
		_spatial_grid[cell].append(star)


func _get_nearby_stars(center: Vector3, radius: float) -> Array:
	var result: Array = []
	var r := radius
	var cs := _grid_cell_size
	var min_cell := Vector3i(
		floori((center.x - r) / cs),
		floori((center.y - r) / cs),
		floori((center.z - r) / cs)
	)
	var max_cell := Vector3i(
		floori((center.x + r) / cs),
		floori((center.y + r) / cs),
		floori((center.z + r) / cs)
	)
	for x in range(min_cell.x, max_cell.x + 1):
		for y in range(min_cell.y, max_cell.y + 1):
			for z in range(min_cell.z, max_cell.z + 1):
				var cell := Vector3i(x, y, z)
				if _spatial_grid.has(cell):
					result.append_array(_spatial_grid[cell])
	return result


func _sync_current_system() -> void:
	var starfield := get_node_or_null("/root/StarField")
	if starfield and starfield.current_system != null:
		_current_system_pos = _scaled_pos(starfield.current_system)


func _scaled_pos(star: SFStarRecord) -> Vector3:
	return star.galaxy_position / galaxy_scale


# ─── Tier construction ────────────────────────────────────────────────────────

func _build_tiers() -> void:
	# Billboard field — use preloaded script to ensure class is loaded at parse time
	if _GalaxyBillboardFieldScript == null:
		push_error("GalaxyContainer: GalaxyBillboardField script preload failed")
		return
	_billboard_field = _GalaxyBillboardFieldScript.new()
	if _billboard_field == null:
		push_error("GalaxyContainer: GalaxyBillboardField.new() returned null")
		return
	_billboard_field.name = "BillboardField"
	_billboard_field.set_galaxy_scale(galaxy_scale)
	add_child(_billboard_field)

	# Procedural field sphere
	_procedural_field = MeshInstance3D.new()
	_procedural_field.name = "ProceduralField"
	var sphere := SphereMesh.new()
	sphere.radius = proc_field_sphere_radius
	sphere.height = proc_field_sphere_radius * 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	_procedural_field.mesh = sphere

	var mat := ShaderMaterial.new()
	mat.shader = preload("res://core/starfield/galaxy_map_field.gdshader")
	mat.set_shader_parameter("galaxy_scale", galaxy_scale)
	mat.set_shader_parameter("proc_field_cell_size", proc_field_cell_size)
	mat.set_shader_parameter("lod_billboard_distance", lod_billboard_distance)
	_procedural_field.material_override = mat
	_procedural_field.layers = 1
	add_child(_procedural_field)

	# Star container for mesh-tier nodes
	_star_container = Node3D.new()
	_star_container.name = "StarContainer"
	add_child(_star_container)


func _update_procedural_field_uniforms() -> void:
	if _procedural_field and _procedural_field.material_override:
		var mat: ShaderMaterial = _procedural_field.material_override
		mat.set_shader_parameter("galaxy_scale", galaxy_scale)
		mat.set_shader_parameter("proc_field_cell_size", proc_field_cell_size)
		mat.set_shader_parameter("lod_billboard_distance", lod_billboard_distance)


# ─── Services & monitors ──────────────────────────────────────────────────────

func _connect_services() -> void:
	var sl := Engine.get_singleton("ServiceLocator")
	if sl:
		_perf = sl.GetService("PerformanceMonitor")
		_event_bus = sl.GetService("GameEventBus")
		if _event_bus:
			_event_bus.connect("game_mode_changed", _on_game_mode_changed)
			_event_bus.connect("system_transition_complete", _on_system_transition_complete)


func _register_monitors() -> void:
	if _perf == null:
		return
	if not Performance.has_custom_monitor("AllSpace/galaxy_mesh_stars"):
		Performance.add_custom_monitor("AllSpace/galaxy_mesh_stars",
			func(): return _perf.get_count("GalaxyMap.mesh_star_nodes"))
	if not Performance.has_custom_monitor("AllSpace/galaxy_billboard_stars"):
		Performance.add_custom_monitor("AllSpace/galaxy_billboard_stars",
			func(): return _perf.get_count("GalaxyMap.billboard_instances"))
	if not Performance.has_custom_monitor("AllSpace/galaxy_population_ms"):
		Performance.add_custom_monitor("AllSpace/galaxy_population_ms",
			func(): return _perf.get_avg_ms("GalaxyMap.population_update"))


# ─── LOD population update ─────────────────────────────────────────────────────

func _update_star_populations() -> void:
	if _perf:
		_perf.begin("GalaxyMap.population_update")

	_sync_current_system()

	var cam_pos := global_position

	# Skip if camera hasn't moved enough since last update
	if cam_pos.distance_to(_last_cam_pos) < _cam_move_threshold:
		if _perf:
			_perf.end("GalaxyMap.population_update")
			_perf.set_count("GalaxyMap.mesh_star_nodes", _mesh_star_nodes.size())
			if _billboard_field != null:
				_perf.set_count("GalaxyMap.billboard_instances", _billboard_field.instance_count())
			else:
				_perf.set_count("GalaxyMap.billboard_instances", 0)
		if _perf:
			_perf.begin("GalaxyMap.crossfade_update")
		if _perf:
			_perf.end("GalaxyMap.crossfade_update")
		return
	_last_cam_pos = cam_pos

	var mesh_stars: Array = []
	var billboard_stars: Array = []
	# Crossfade data: star_id -> mesh_alpha (only for stars near boundaries)
	var crossfade_data: Dictionary = {}

	# Use spatial grid to only check stars near camera
	var query_radius := lod_billboard_distance + lod_fade_range
	var nearby_stars := _get_nearby_stars(cam_pos, query_radius)

	for star: SFStarRecord in nearby_stars:
		var pos := _scaled_pos(star)
		var dist := cam_pos.distance_to(pos)
		var in_mesh_zone := dist < lod_mesh_distance + lod_fade_range
		var in_billboard_zone := dist < lod_billboard_distance + lod_fade_range

		if in_mesh_zone:
			mesh_stars.append(star)
			crossfade_data[star.id] = _compute_blend(dist)
		elif in_billboard_zone:
			billboard_stars.append(star)
			# Only compute crossfade if near the outer billboard boundary
			if dist > lod_billboard_distance - lod_fade_range:
				crossfade_data[star.id] = _compute_blend(dist)

	_sync_mesh_nodes(mesh_stars)
	if _billboard_field != null:
		_billboard_field.populate(billboard_stars, cam_pos)
	else:
		push_warning("GalaxyContainer: _billboard_field is null in _update_star_populations")

	if _perf:
		_perf.end("GalaxyMap.population_update")
		_perf.set_count("GalaxyMap.mesh_star_nodes", _mesh_star_nodes.size())
		if _billboard_field != null:
			_perf.set_count("GalaxyMap.billboard_instances", _billboard_field.instance_count())
		else:
			_perf.set_count("GalaxyMap.billboard_instances", 0)

	if _perf:
		_perf.begin("GalaxyMap.crossfade_update")
	if _billboard_field != null:
		_apply_crossfades(crossfade_data)
	if _perf:
		_perf.end("GalaxyMap.crossfade_update")


# ─── Mesh star node sync ───────────────────────────────────────────────────────

func _sync_mesh_nodes(mesh_stars: Array) -> void:
	var needed: Dictionary = {}
	for star: SFStarRecord in mesh_stars:
		needed[star.id] = star
		if _mesh_star_nodes.has(star.id):
			var node: GalaxyStar = _mesh_star_nodes[star.id]
			node.global_position = _scaled_pos(star)
			node.set_reachable(_is_reachable(star))
		else:
			var node: GalaxyStar = preload("res://ui/galactic_map/GalaxyStar.tscn").instantiate()
			node.setup(star)
			node.set_reachable(_is_reachable(star))
			_star_container.add_child(node)
			# Set position AFTER adding to tree to avoid !is_inside_tree() error
			node.global_position = _scaled_pos(star)
			_mesh_star_nodes[star.id] = node

	# Remove stars no longer needed
	for id in _mesh_star_nodes.keys():
		if not needed.has(id):
			_mesh_star_nodes[id].queue_free()
			_mesh_star_nodes.erase(id)


# ─── Crossfade ─────────────────────────────────────────────────────────────────

func _apply_crossfades(crossfade_data: Dictionary) -> void:
	for star_id in crossfade_data.keys():
		var mesh_alpha: float = crossfade_data[star_id]
		if _mesh_star_nodes.has(star_id):
			_mesh_star_nodes[star_id].set_blend_alpha(mesh_alpha)
		_billboard_field.set_instance_alpha(star_id, 1.0 - mesh_alpha)


func _compute_blend(dist: float) -> float:
	var boundary := lod_mesh_distance
	var t := (dist - (boundary - lod_fade_range)) / (lod_fade_range * 2.0)
	return 1.0 - clamp(t, 0.0, 1.0)


# ─── Selection & reachability ─────────────────────────────────────────────────

func _is_reachable(star: SFStarRecord) -> bool:
	var starfield := get_node_or_null("/root/StarField")
	if starfield == null or starfield.current_system == null:
		return false
	var current: SFStarRecord = starfield.current_system
	var dist := current.galaxy_position.distance_to(star.galaxy_position)
	return dist <= star.warp_range


func select_star(star: SFStarRecord) -> void:
	if _active_selection != null and _mesh_star_nodes.has(_active_selection.id):
		_mesh_star_nodes[_active_selection.id].set_selected(false)
	_active_selection = star
	if star != null and _mesh_star_nodes.has(star.id):
		_mesh_star_nodes[star.id].set_selected(true)


func get_active_selection() -> SFStarRecord:
	return _active_selection


func clear_selection() -> void:
	select_star(null)


# ─── Event bus handlers ───────────────────────────────────────────────────────

func _on_game_mode_changed(_old_mode: String, new_mode: String) -> void:
	if new_mode == "galaxy_map":
		spawn_check_interval = _get_config_float("star_spawn_check_interval", 0.25)
	else:
		spawn_check_interval = _get_config_float("star_spawn_check_interval", 0.25) * 2.0
		clear_selection()


func _on_system_transition_complete(_system_id: String) -> void:
	_sync_current_system()


func _get_config_float(key: String, default: float) -> float:
	var file := FileAccess.open("res://data/world_config.json", FileAccess.READ)
	if not file:
		return default
	var json := JSON.new()
	json.parse(file.get_as_text())
	file.close()
	var data: Dictionary = json.data
	if data.has("galaxy_map"):
		return float(data["galaxy_map"].get(key, default))
	return default
