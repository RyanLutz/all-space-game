extends Node
class_name ChunkStreamer

# ChunkStreamer — loads and unloads map chunks around the player as they fly.
# Each chunk is a Node2D container populated with procedurally generated asteroids
# and AI spawn-point markers. Content is seeded from the chunk coordinate so the
# same chunk is always identical on re-entry.
#
# Add as a child of the scene root (NOT autoloaded — it creates Node2D children).
# All tunable values come from data/world_config.json.
# See docs/ChunkStreamer_Spec.md.

const _ASTEROID_SCRIPT := "res://gameplay/world/Asteroid.gd"
const _DEBRIS_SCRIPT := "res://gameplay/world/Debris.gd"
const _CONFIG_PATH := "res://data/world_config.json"

# Config loaded from JSON
var _chunk_size: float = 2000.0
var _load_radius: int = 2
var _max_fields_per_chunk: int = 3
var _field_radius_min: float = 80.0
var _field_radius_max: float = 300.0
var _asteroids_per_field_min: int = 3
var _asteroids_per_field_max: int = 12
var _size_weights: Dictionary = {"small": 0.55, "medium": 0.35, "large": 0.10}
var _asteroid_hp: Dictionary = {"small": 40.0, "medium": 100.0, "large": 250.0}
var _asteroid_scale: Dictionary = {"small": 0.6, "medium": 1.0, "large": 1.8}
var _debris_cfg: Dictionary = {"lifetime": 3.5, "speed_min": 40.0, "speed_max": 160.0}

# Runtime state
var _loaded_chunks: Dictionary = {}         # Vector2i → Node2D
var _last_center_chunk: Vector2i = Vector2i(999999, 999999)
var _follow_target: Node2D = null

var _asteroid_script: GDScript = null
var _debris_scene: PackedScene = null

@onready var _perf: Node = ServiceLocator.GetService("PerformanceMonitor") as Node
@onready var _event_bus: Node = ServiceLocator.GetService("GameEventBus") as Node

# Guard so multiple instances don't register the same custom monitors.
static var _monitors_registered := false


func _ready() -> void:
	_load_config()
	_preload_scripts()

	# Find the player ship — fall back to player_ship_changed signal for late spawns.
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player != null:
		_follow_target = player

	if _event_bus != null:
		_event_bus.connect("player_ship_changed", _on_player_ship_changed)

	if not _monitors_registered:
		_monitors_registered = true
		Performance.add_custom_monitor("AllSpace/chunk_load_ms",
			func(): return _perf.get_avg_ms("ChunkStreamer.load") if _perf else 0.0)
		Performance.add_custom_monitor("AllSpace/chunk_unload_ms",
			func(): return _perf.get_avg_ms("ChunkStreamer.unload") if _perf else 0.0)
		Performance.add_custom_monitor("AllSpace/loaded_chunks",
			func(): return _perf.get_count("ChunkStreamer.loaded_chunks") if _perf else 0)


func _on_player_ship_changed(ship: Node2D) -> void:
	_follow_target = ship


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_follow_target):
		return

	var current_chunk := _world_to_chunk(_follow_target.global_position)
	if current_chunk == _last_center_chunk:
		return
	_last_center_chunk = current_chunk

	# Build the desired set of chunk coords.
	var desired: Dictionary = {}
	for dx in range(-_load_radius, _load_radius + 1):
		for dy in range(-_load_radius, _load_radius + 1):
			desired[current_chunk + Vector2i(dx, dy)] = true

	# Load newly in-range chunks.
	_perf.begin("ChunkStreamer.load")
	for coord in desired:
		if not _loaded_chunks.has(coord):
			_load_chunk(coord)
	_perf.end("ChunkStreamer.load")

	# Unload out-of-range chunks.
	_perf.begin("ChunkStreamer.unload")
	var to_unload: Array = []
	for coord in _loaded_chunks:
		if not desired.has(coord):
			to_unload.append(coord)
	for coord in to_unload:
		_unload_chunk(coord)
	_perf.end("ChunkStreamer.unload")

	_perf.set_count("ChunkStreamer.loaded_chunks", _loaded_chunks.size())


# --- Chunk lifecycle ---

func _load_chunk(coord: Vector2i) -> void:
	var chunk_node := Node2D.new()
	chunk_node.name = "Chunk_%d_%d" % [coord.x, coord.y]
	chunk_node.global_position = _chunk_to_world_origin(coord)
	add_child(chunk_node)

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(coord)

	_populate_asteroids(chunk_node, rng)

	_loaded_chunks[coord] = chunk_node

	if _event_bus != null:
		_event_bus.emit_signal("chunk_loaded", coord)


func _unload_chunk(coord: Vector2i) -> void:
	var chunk_node: Node2D = _loaded_chunks.get(coord)
	if is_instance_valid(chunk_node):
		chunk_node.queue_free()
	_loaded_chunks.erase(coord)

	if _event_bus != null:
		_event_bus.emit_signal("chunk_unloaded", coord)


# --- Procedural content ---

func _populate_asteroids(chunk_node: Node2D, rng: RandomNumberGenerator) -> void:
	if _asteroid_script == null:
		return

	var field_count: int = rng.randi_range(0, _max_fields_per_chunk)
	for _f in range(field_count):
		var field_center := Vector2(
			rng.randf_range(0.0, _chunk_size),
			rng.randf_range(0.0, _chunk_size)
		)
		var field_radius: float = rng.randf_range(_field_radius_min, _field_radius_max)
		var count: int = rng.randi_range(_asteroids_per_field_min, _asteroids_per_field_max)

		for _a in range(count):
			var angle := rng.randf() * TAU
			var dist := rng.randf() * field_radius
			var local_pos := field_center + Vector2(cos(angle), sin(angle)) * dist
			var tier: String = _weighted_tier(rng)
			_spawn_asteroid(chunk_node, local_pos, tier)


func _spawn_asteroid(chunk_node: Node2D, local_pos: Vector2, tier: String) -> void:
	var asteroid: Node2D = _asteroid_script.new()
	var hp_max: float = float(_asteroid_hp.get(tier, 100.0))
	var vis_scale: float = float(_asteroid_scale.get(tier, 1.0))
	asteroid.initialize(tier, hp_max, vis_scale, _debris_scene, _debris_cfg)
	asteroid.position = local_pos
	asteroid.rotation = randf() * TAU
	chunk_node.add_child(asteroid)


func _weighted_tier(rng: RandomNumberGenerator) -> String:
	var roll := rng.randf()
	var small_w: float = float(_size_weights.get("small", 0.55))
	var medium_w: float = float(_size_weights.get("medium", 0.35))
	if roll < small_w:
		return "small"
	elif roll < small_w + medium_w:
		return "medium"
	return "large"


# --- Coordinate math ---

func _world_to_chunk(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		floori(world_pos.x / _chunk_size),
		floori(world_pos.y / _chunk_size)
	)


func _chunk_to_world_origin(coord: Vector2i) -> Vector2:
	return Vector2(float(coord.x) * _chunk_size, float(coord.y) * _chunk_size)


# --- Config loading ---

func _load_config() -> void:
	var file := FileAccess.open(_CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_error("ChunkStreamer: cannot open %s — using defaults" % _CONFIG_PATH)
		return

	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("ChunkStreamer: JSON parse failed for %s: %s (line %d)" % [
			_CONFIG_PATH, json.get_error_message(), json.get_error_line()])
		return

	var data = json.get_data()
	if typeof(data) != TYPE_DICTIONARY:
		push_error("ChunkStreamer: %s root must be a Dictionary" % _CONFIG_PATH)
		return

	if not data.has("_comment"):
		push_error("ChunkStreamer: %s missing '_comment' field" % _CONFIG_PATH)
		return

	_chunk_size = float(data.get("chunk_size", _chunk_size))
	_load_radius = int(data.get("load_radius", _load_radius))

	var af: Dictionary = data.get("asteroid_fields", {})
	if not af.is_empty():
		_max_fields_per_chunk = int(af.get("max_fields_per_chunk", _max_fields_per_chunk))
		_field_radius_min     = float(af.get("field_radius_min", _field_radius_min))
		_field_radius_max     = float(af.get("field_radius_max", _field_radius_max))
		_asteroids_per_field_min = int(af.get("asteroids_per_field_min", _asteroids_per_field_min))
		_asteroids_per_field_max = int(af.get("asteroids_per_field_max", _asteroids_per_field_max))
		var sw = af.get("size_weights", {})
		if typeof(sw) == TYPE_DICTIONARY:
			_size_weights = sw

	var ah = data.get("asteroid_hp", {})
	if typeof(ah) == TYPE_DICTIONARY and not ah.is_empty():
		_asteroid_hp = ah

	var as_ = data.get("asteroid_scale", {})
	if typeof(as_) == TYPE_DICTIONARY and not as_.is_empty():
		_asteroid_scale = as_

	var dc = data.get("debris", {})
	if typeof(dc) == TYPE_DICTIONARY and not dc.is_empty():
		_debris_cfg = dc


func _preload_scripts() -> void:
	if ResourceLoader.exists(_ASTEROID_SCRIPT):
		_asteroid_script = load(_ASTEROID_SCRIPT)
	else:
		push_error("ChunkStreamer: Asteroid.gd not found at '%s'" % _ASTEROID_SCRIPT)

	# Build a PackedScene from Debris.gd programmatically since there is no .tscn file.
	# Debris is lightweight enough that a script-only instantiation is fine.
	if ResourceLoader.exists(_DEBRIS_SCRIPT):
		var debris_gd: GDScript = load(_DEBRIS_SCRIPT)
		var debris_node := Node2D.new()
		debris_node.set_script(debris_gd)
		var packed := PackedScene.new()
		packed.pack(debris_node)
		debris_node.free()
		_debris_scene = packed
	else:
		push_error("ChunkStreamer: Debris.gd not found at '%s'" % _DEBRIS_SCRIPT)
