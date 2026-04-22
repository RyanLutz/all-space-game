extends Node3D
class_name ChunkStreamer

## Streams rectangular map chunks around the player. Each chunk is a Node3D
## container populated with deterministically-generated asteroids and AI spawn
## point markers. Chunks load/unload as the player crosses chunk boundaries.

var _follow_target: Node3D = null
var _last_center_chunk: Vector2i = Vector2i(999999, 999999)
var _loaded_chunks: Dictionary = {}

# Config — loaded from world_config.json
var _chunk_size: float = 2000.0
var _load_radius: int = 2
var _config: Dictionary = {}

var _event_bus: Node
var _perf: Node


func _ready() -> void:
	var service_locator := Engine.get_singleton("ServiceLocator")
	if service_locator:
		_event_bus = service_locator.GetService("GameEventBus")
		_perf = service_locator.GetService("PerformanceMonitor")

	if _event_bus:
		_event_bus.player_ship_changed.connect(_on_player_ship_changed)

	_load_config()

	# Register perf monitors
	if _perf:
		Performance.add_custom_monitor("AllSpace/chunk_load_ms",
			func(): return _perf.get_avg_ms("ChunkStreamer.load"))
		Performance.add_custom_monitor("AllSpace/chunk_unload_ms",
			func(): return _perf.get_avg_ms("ChunkStreamer.unload"))
		Performance.add_custom_monitor("AllSpace/loaded_chunks",
			func(): return _perf.get_count("ChunkStreamer.loaded_chunks"))


func set_follow_target(target: Node3D) -> void:
	_follow_target = target
	# Force re-evaluation on next physics frame
	_last_center_chunk = Vector2i(999999, 999999)


func _on_player_ship_changed(ship: Node) -> void:
	if ship is Node3D:
		set_follow_target(ship)


func _load_config() -> void:
	var file := FileAccess.open("res://data/world_config.json", FileAccess.READ)
	if file == null:
		push_error("[ChunkStreamer] Failed to open data/world_config.json")
		return

	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("[ChunkStreamer] JSON parse error in world_config.json: %s" % json.get_error_message())
		return

	var data: Dictionary = json.data
	_chunk_size = data.get("chunk_size", 2000.0)
	_load_radius = int(data.get("load_radius", 2))
	_config = data


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_follow_target):
		return

	var current_chunk := _world_to_chunk(_follow_target.global_position)
	if current_chunk == _last_center_chunk:
		return
	_last_center_chunk = current_chunk

	# Build desired neighborhood
	var desired: Dictionary = {}
	for dx in range(-_load_radius, _load_radius + 1):
		for dz in range(-_load_radius, _load_radius + 1):
			var coord := current_chunk + Vector2i(dx, dz)
			desired[coord] = true

	# Load newly in-range chunks
	if _perf:
		_perf.begin("ChunkStreamer.load")
	for coord in desired:
		if not _loaded_chunks.has(coord):
			_load_chunk(coord)
	if _perf:
		_perf.end("ChunkStreamer.load")

	# Unload out-of-range chunks
	if _perf:
		_perf.begin("ChunkStreamer.unload")
	var to_unload: Array[Vector2i] = []
	for coord in _loaded_chunks:
		if not desired.has(coord):
			to_unload.append(coord)
	for coord in to_unload:
		_unload_chunk(coord)
	if _perf:
		_perf.end("ChunkStreamer.unload")

	if _perf:
		_perf.set_count("ChunkStreamer.loaded_chunks", _loaded_chunks.size())


# ─── Coordinate conversion ────────────────────────────────────────────────────

func _world_to_chunk(world_pos: Vector3) -> Vector2i:
	return Vector2i(
		floori(world_pos.x / _chunk_size),
		floori(world_pos.z / _chunk_size)
	)


func _chunk_to_world_origin(coord: Vector2i) -> Vector3:
	return Vector3(coord.x * _chunk_size, 0.0, coord.y * _chunk_size)


# ─── Chunk lifecycle ──────────────────────────────────────────────────────────

func _load_chunk(coord: Vector2i) -> void:
	var origin := _chunk_to_world_origin(coord)

	var chunk_node := Node3D.new()
	chunk_node.name = "Chunk_%d_%d" % [coord.x, coord.y]
	chunk_node.global_position = origin
	add_child(chunk_node)

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(coord)

	_populate_asteroids(chunk_node, rng)
	_populate_spawn_points(chunk_node, rng)

	_loaded_chunks[coord] = chunk_node

	if _event_bus:
		_event_bus.chunk_loaded.emit(coord)


func _unload_chunk(coord: Vector2i) -> void:
	var chunk_node: Node3D = _loaded_chunks.get(coord)
	if is_instance_valid(chunk_node):
		chunk_node.queue_free()
	_loaded_chunks.erase(coord)

	if _event_bus:
		_event_bus.chunk_unloaded.emit(coord)


# ─── Asteroid field population ────────────────────────────────────────────────

func _populate_asteroids(chunk_node: Node3D, rng: RandomNumberGenerator) -> void:
	var fields_cfg: Dictionary = _config.get("asteroid_fields", {})
	var max_fields: int = int(fields_cfg.get("max_fields_per_chunk", 3))
	var field_count: int = rng.randi_range(0, max_fields)

	var field_radius_min: float = fields_cfg.get("field_radius_min", 80.0)
	var field_radius_max: float = fields_cfg.get("field_radius_max", 300.0)
	var asteroids_min: int = int(fields_cfg.get("asteroids_per_field_min", 3))
	var asteroids_max: int = int(fields_cfg.get("asteroids_per_field_max", 12))
	var size_weights: Dictionary = fields_cfg.get("size_weights",
		{"small": 0.55, "medium": 0.35, "large": 0.10})

	for _f in range(field_count):
		var fc_x := rng.randf_range(0.0, _chunk_size)
		var fc_z := rng.randf_range(0.0, _chunk_size)
		var field_radius := rng.randf_range(field_radius_min, field_radius_max)
		var count := rng.randi_range(asteroids_min, asteroids_max)

		for _a in range(count):
			var angle := rng.randf() * TAU
			var dist := rng.randf() * field_radius
			var local_pos := Vector3(
				fc_x + cos(angle) * dist,
				0.0,
				fc_z + sin(angle) * dist
			)
			var tier := _pick_size_tier(rng, size_weights)
			_spawn_asteroid(chunk_node, local_pos, tier)


func _pick_size_tier(rng: RandomNumberGenerator, weights: Dictionary) -> String:
	var r := rng.randf()
	var small_w: float = weights.get("small", 0.55)
	var medium_w: float = weights.get("medium", 0.35)
	if r < small_w:
		return "small"
	elif r < small_w + medium_w:
		return "medium"
	return "large"


func _spawn_asteroid(chunk_node: Node3D, local_pos: Vector3, tier: String) -> void:
	var asteroid := Asteroid.new()
	asteroid.name = "Asteroid_%d" % chunk_node.get_child_count()
	asteroid.position = local_pos

	# HP from config
	var hp_cfg: Dictionary = _config.get("asteroid_hp", {})
	var hp: float = hp_cfg.get(tier, 100.0)
	asteroid.hull_hp = hp
	asteroid.hull_max = hp
	asteroid.size_tier = tier

	# Debris config
	var debris_cfg: Dictionary = _config.get("debris", {})
	asteroid._debris_count_min = int(debris_cfg.get("count_min", 2))
	asteroid._debris_count_max = int(debris_cfg.get("count_max", 5))
	asteroid._debris_speed_min = debris_cfg.get("speed_min", 40.0)
	asteroid._debris_speed_max = debris_cfg.get("speed_max", 160.0)
	asteroid._debris_lifetime = debris_cfg.get("lifetime", 3.5)

	# Scale from config
	var scale_cfg: Dictionary = _config.get("asteroid_scale", {})
	var scale_factor: float = scale_cfg.get(tier, 1.0)

	chunk_node.add_child(asteroid)
	asteroid.setup_mesh(scale_factor)


# ─── AI spawn point population ────────────────────────────────────────────────

func _populate_spawn_points(chunk_node: Node3D, rng: RandomNumberGenerator) -> void:
	var spawn_cfg: Dictionary = _config.get("ai_spawn_points", {})
	var max_count: int = int(spawn_cfg.get("max_per_chunk", 2))
	var min_dist: float = spawn_cfg.get("min_distance_from_center", 400.0)
	var count: int = rng.randi_range(0, max_count)

	for i in range(count):
		var angle := rng.randf() * TAU
		var dist := rng.randf_range(min_dist, _chunk_size * 0.5)
		var local_pos := Vector3(
			_chunk_size * 0.5 + cos(angle) * dist,
			0.0,
			_chunk_size * 0.5 + sin(angle) * dist
		)
		var marker := Node3D.new()
		marker.name = "SpawnPoint_%d" % i
		marker.position = local_pos
		marker.add_to_group("ai_spawn_points")
		chunk_node.add_child(marker)
