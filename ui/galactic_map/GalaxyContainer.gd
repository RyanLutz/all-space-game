class_name GalaxyContainer
extends Node3D

## Galaxy rendering root. Reads catalog from StarField autoload, manages LOD
## population updates, and drives the billboard + mesh tiers.
##
## Billboards are visible in ALL modes. In pilot/tactical, GalaxyContainer
## follows the camera so stars appear fixed in the background. In galaxy map,
## it stays world-aligned so the camera can fly through the galaxy.
## Mesh stars are galaxy-map only.

# ─── Catalog refs ─────────────────────────────────────────────────────────────
var _catalog: Array[SFStarRecord] = []
var _destinations: Array[SFStarRecord] = []

# ─── Preloads ─────────────────────────────────────────────────────────────────
const _GalaxyBillboardFieldScript := preload("res://ui/galactic_map/GalaxyBillboardField.gd")

# ─── Tier managers ────────────────────────────────────────────────────────────
var _billboard_field: GalaxyBillboardField
var _star_container: Node3D
var _mesh_star_nodes: Dictionary = {}   # star.id -> GalaxyStar node

# ─── State ────────────────────────────────────────────────────────────────────
var _spawn_check_timer: float = 0.0
var _current_system_pos: Vector3 = Vector3.ZERO
var _active_selection: SFStarRecord = null
var _last_cam_pos: Vector3 = Vector3.INF
var _cam_move_threshold: float = 5.0
var _follow_camera: bool = true
var _alphas_reset_for_pilot: bool = true

# ─── Spatial grid ─────────────────────────────────────────────────────────────
var _spatial_grid: Dictionary = {}   # Vector3i -> Array[SFStarRecord]
var _grid_cell_size: float = 400.0

# ─── Config (loaded from world_config.json) ───────────────────────────────────
var galaxy_scale: float = 100.0
var lod_mesh_distance: float = 80.0
var lod_fade_range: float = 40.0
var billboard_pixel_size: float = 0.01
var spawn_check_interval: float = 0.25

# ─── Services ─────────────────────────────────────────────────────────────────
var _perf: Node = null
var _event_bus: Node = null
var _camera: Camera3D = null


func _ready() -> void:
	_load_config()
	_gather_catalog()
	_build_tiers()
	_connect_services()
	_register_monitors()
	_sync_current_system()

	# Camera ref for world-aligned queries in galaxy map mode
	_camera = get_node_or_null("/root/Main/GameCamera")
	if _camera == null:
		# Fallback: search by group or by viewport camera
		var viewport := get_viewport()
		if viewport:
			_camera = viewport.get_camera_3d()
		if _camera == null:
			_camera = get_tree().get_first_node_in_group("game_camera")
	if _camera == null:
		push_error("GalaxyContainer: Could not find GameCamera — billboard follow will fail.")

	# Billboards always visible; populate immediately so pilot mode shows stars
	if _billboard_field:
		_billboard_field.visible = true
		_billboard_field.populate(_catalog, Vector3.ZERO)


func _process(delta: float) -> void:
	if _follow_camera:
		# In pilot/tactical mode, follow the camera so stars appear fixed on screen
		if _camera:
			global_transform = Transform3D(Basis.IDENTITY, _camera.global_position)
		# Safety: if we ever enter pilot mode without a clean reset, force alphas back
		if not _alphas_reset_for_pilot and _billboard_field:
			_billboard_field.reset_alphas()
			_alphas_reset_for_pilot = true
	# else: galaxy map mode — stay world-aligned at origin

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
	lod_fade_range = float(cfg.get("lod_fade_range", 40.0))
	billboard_pixel_size = float(cfg.get("billboard_pixel_size", 0.01))
	spawn_check_interval = float(cfg.get("star_spawn_check_interval", 0.25))


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


func get_navigable_stars() -> Array[SFStarRecord]:
	return _destinations.duplicate()


func get_star_world_position(star: SFStarRecord) -> Vector3:
	return _scaled_pos(star)


func get_mesh_star_node(star_id: int) -> GalaxyStar:
	if _mesh_star_nodes.has(star_id):
		return _mesh_star_nodes[star_id]
	return null


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
	_billboard_field.set_billboard_pixel_size(billboard_pixel_size)
	_billboard_field.visible = true
	add_child(_billboard_field)

	# Star container for mesh-tier nodes (galaxy map only)
	_star_container = Node3D.new()
	_star_container.name = "StarContainer"
	_star_container.visible = false
	add_child(_star_container)


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

	# In pilot/tactical mode GalaxyContainer follows the camera, so local origin
	# is the camera position. In galaxy map mode we stay at origin, so we must
	# query from the actual camera world position.
	var cam_pos := Vector3.ZERO
	var check_pos := Vector3.ZERO
	if not _follow_camera and _camera:
		cam_pos = _camera.global_position
		check_pos = cam_pos

	# Skip if camera hasn't moved enough since last update
	if _last_cam_pos.distance_to(check_pos) < _cam_move_threshold:
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
	_last_cam_pos = check_pos

	var mesh_stars: Array = []
	# Crossfade data: star_id -> mesh_alpha (only for stars near boundaries)
	var crossfade_data: Dictionary = {}

	# Use spatial grid to only check stars near camera
	var query_radius := lod_mesh_distance + lod_fade_range
	var nearby_stars := _get_nearby_stars(cam_pos, query_radius)

	for star: SFStarRecord in nearby_stars:
		var pos := _scaled_pos(star)
		var dist := cam_pos.distance_to(pos)
		var in_mesh_zone := dist < lod_mesh_distance + lod_fade_range

		if in_mesh_zone and lod_mesh_distance > 0.0:
			mesh_stars.append(star)
			crossfade_data[star.id] = _compute_blend(dist)

	_sync_mesh_nodes(mesh_stars)

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
			node.position = _scaled_pos(star)
			node.set_reachable(_is_reachable(star))
		else:
			var node: GalaxyStar = preload("res://ui/galactic_map/GalaxyStar.tscn").instantiate()
			node.setup(star)
			node.set_reachable(_is_reachable(star))
			_star_container.add_child(node)
			# Position is LOCAL to StarContainer which is LOCAL to GalaxyContainer
			node.position = _scaled_pos(star)
			_mesh_star_nodes[star.id] = node

	# Remove stars no longer needed
	for id in _mesh_star_nodes.keys():
		if not needed.has(id):
			_mesh_star_nodes[id].queue_free()
			_mesh_star_nodes.erase(id)


# ─── Mesh node cleanup ─────────────────────────────────────────────────────────

func _clear_mesh_nodes() -> void:
	for node in _mesh_star_nodes.values():
		node.queue_free()
	_mesh_star_nodes.clear()


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

func _on_game_mode_changed(old_mode: String, new_mode: String) -> void:
	if new_mode == "galaxy_map":
		_follow_camera = false
		_alphas_reset_for_pilot = false
		global_position = Vector3.ZERO
		_star_container.visible = true
		spawn_check_interval = _get_config_float("star_spawn_check_interval", 0.25)
		lod_mesh_distance = _get_config_float("lod_mesh_distance", 80.0)
		_billboard_field.populate(_catalog, Vector3.ZERO)
		_update_star_populations()
	elif old_mode == "galaxy_map":
		_follow_camera = true
		_star_container.visible = false
		_clear_mesh_nodes()
		spawn_check_interval = _get_config_float("star_spawn_check_interval", 0.25) * 2.0
		lod_mesh_distance = 0.0
		clear_selection()
		if _billboard_field:
			_billboard_field.reset_alphas()
		_alphas_reset_for_pilot = true


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
