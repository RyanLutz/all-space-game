class_name ChunkStreamer
extends Node3D

## Minimal streaming: loads/unloads chunk neighborhood; emits GameEventBus chunk signals.

var _world_cfg: Dictionary = {}
var _chunk_size: float = 2000.0
var _load_radius: int = 2
var _loaded: Dictionary = {}
var _player: Node3D = null
var _perf: Node
var _bus: Node


func _ready() -> void:
	_perf = ServiceLocator.GetService("PerformanceMonitor") as Node
	_bus = ServiceLocator.GetService("GameEventBus") as Node
	_load_world_config()


func _load_world_config() -> void:
	var f := FileAccess.open("res://data/world_config.json", FileAccess.READ)
	if f == null:
		return
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		f.close()
		return
	f.close()
	_world_cfg = json.data as Dictionary
	_chunk_size = float(_world_cfg.get("chunk_size", 2000.0))
	_load_radius = int(_world_cfg.get("load_radius", 2))


func set_follow_target(target: Node3D) -> void:
	_player = target


func _physics_process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var cx := int(floor(_player.global_position.x / _chunk_size))
	var cz := int(floor(_player.global_position.z / _chunk_size))
	var want: Dictionary = {}
	for dz in range(-_load_radius, _load_radius + 1):
		for dx in range(-_load_radius, _load_radius + 1):
			var cc := Vector2i(cx + dx, cz + dz)
			want[cc] = true
	# unload
	for cc in _loaded.keys():
		if not want.has(cc):
			if _perf != null:
				_perf.begin("ChunkStreamer.unload")
			_unload_chunk(cc)
			if _perf != null:
				_perf.end("ChunkStreamer.unload")
			if _bus != null:
				_bus.emit_signal("chunk_unloaded", cc)
			_loaded.erase(cc)
	# load
	for cc in want.keys():
		if not _loaded.has(cc):
			if _perf != null:
				_perf.begin("ChunkStreamer.load")
			_load_chunk(cc)
			if _perf != null:
				_perf.end("ChunkStreamer.load")
			if _bus != null:
				_bus.emit_signal("chunk_loaded", cc)
			_loaded[cc] = true
	if _perf != null:
		_perf.set_count("ChunkStreamer.loaded_chunks", _loaded.size())


func _load_chunk(cc: Vector2i) -> void:
	var seed_val: int = cc.x * 92837111 ^ cc.y * 689287499
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val as int
	var base := Vector3(float(cc.x) * _chunk_size, 0.0, float(cc.y) * _chunk_size)
	var n: int = int(rng.randi_range(1, 3))
	for i in n:
		var ax := base.x + rng.randf_range(50.0, _chunk_size - 50.0)
		var az := base.z + rng.randf_range(50.0, _chunk_size - 50.0)
		var ast := Asteroid.new()
		ast.configure_random(rng)
		ast.set_meta("chunk_coord", cc)
		ast.name = "Asteroid_%d_%d_%d" % [cc.x, cc.y, i]
		add_child(ast)
		ast.global_position = Vector3(ax, 0.0, az)


func _unload_chunk(cc: Vector2i) -> void:
	for c in get_children():
		if c.get_meta("chunk_coord", null) is Vector2i and c.get_meta("chunk_coord") == cc:
			c.queue_free()
