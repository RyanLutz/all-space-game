class_name OriginShifter
extends Node3D

## Floating-point origin shifter. Subscribed to chunk_loaded; when the player
## drifts beyond shift_threshold from world origin, shifts all physics_bodies
## and the solar system root back toward origin. Emits origin_shifted(offset).

var shift_threshold: float = 10000.0

var _player: Node3D = null
var _solar_system: SolarSystem = null
var _event_bus: Node = null
var _perf: Node = null


func _ready() -> void:
	var sl := Engine.get_singleton("ServiceLocator")
	if sl:
		_event_bus = sl.GetService("GameEventBus")
		_perf      = sl.GetService("PerformanceMonitor")

	_solar_system = get_parent() as SolarSystem

	_load_threshold()

	if _event_bus:
		_event_bus.chunk_loaded.connect(_on_chunk_loaded)
		_event_bus.player_ship_changed.connect(_on_player_ship_changed)


func _on_player_ship_changed(ship: Node) -> void:
	_player = ship as Node3D


func _on_chunk_loaded(_coord: Vector2i) -> void:
	if not is_instance_valid(_player) or not _player.is_inside_tree():
		return

	var player_xz := Vector2(_player.global_position.x, _player.global_position.z)
	if player_xz.length() < shift_threshold:
		return

	if _perf:
		_perf.begin("SolarSystem.origin_shift")

	var offset := Vector3(_player.global_position.x, 0.0, _player.global_position.z)

	for body in get_tree().get_nodes_in_group("physics_bodies"):
		if is_instance_valid(body):
			(body as Node3D).global_position -= offset

	if _solar_system:
		_solar_system.get_solar_system_root().global_position -= offset
		_solar_system.update_world_origin(-offset)

	if _event_bus:
		_event_bus.origin_shifted.emit(-offset)

	if _perf:
		_perf.end("SolarSystem.origin_shift")


func _load_threshold() -> void:
	var file := FileAccess.open("res://data/world_config.json", FileAccess.READ)
	if not file:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		return
	file.close()
	var data: Dictionary = json.data
	var ss: Dictionary = data.get("solar_system", {})
	shift_threshold = float(ss.get("origin_shift_threshold", shift_threshold))
