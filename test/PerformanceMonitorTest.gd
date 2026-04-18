extends Node3D

var _frame_counter: int = 0
var _fake_projectiles: int = 0
var _fake_ai_ships: int = 0
var _fake_chunks: int = 0

@onready var _perf: Node = ServiceLocator.GetService("PerformanceMonitor")

func _ready() -> void:
	# Add the performance overlay
	var overlay = preload("res://ui/debug/PerformanceOverlay.tscn").instantiate()
	add_child(overlay)

	print("PerformanceMonitor Test Scene Ready")
	print("Press F3 to toggle the performance overlay")
	print("Watch metrics populate automatically...")

func _process(delta: float) -> void:
	_frame_counter += 1

	# Simulate varying workloads to exercise the rolling average
	_simulate_projectile_manager()
	_simulate_ai_controller()
	_simulate_physics()
	_simulate_chunk_streamer()
	_simulate_navigation()

	# Update count metrics every 30 frames
	if _frame_counter % 30 == 0:
		_fake_projectiles = 100 + int(sin(_frame_counter * 0.01) * 50)
		_fake_ai_ships = 5 + int(cos(_frame_counter * 0.02) * 3)
		_fake_chunks = 9 + int(sin(_frame_counter * 0.005) * 4)

		_perf.set_count("ProjectileManager.active_count", _fake_projectiles)
		_perf.set_count("AIController.active_count", _fake_ai_ships)
		_perf.set_count("ChunkStreamer.loaded_chunks", _fake_chunks)
		_perf.set_count("Ships.active_count", _fake_ai_ships + 1)  # +1 for player

func _simulate_projectile_manager() -> void:
	_perf.begin("ProjectileManager.dumb_update")

	# Simulate work: iterate over fake projectiles
	var total: float = 0.0
	for i in range(_fake_projectiles):
		total += i * 0.0001  # Small amount of work per projectile

	_perf.end("ProjectileManager.dumb_update")

	_perf.begin("ProjectileManager.guided_update")
	# Simulate guided missile tracking (fewer, more expensive)
	for i in range(5):
		total += i * 0.001
	_perf.end("ProjectileManager.guided_update")

	_perf.begin("ProjectileManager.collision_checks")
	# Simulate collision checks
	for i in range(min(_fake_projectiles, 50)):
		total += i * 0.0001
	_perf.end("ProjectileManager.collision_checks")

func _simulate_ai_controller() -> void:
	_perf.begin("AIController.state_updates")

	# Simulate AI state machine work
	for i in range(_fake_ai_ships):
		var state = i % 3  # patrol, chase, attack
		var decision = state * 0.1

	_perf.end("AIController.state_updates")

func _simulate_physics() -> void:
	_perf.begin("Physics.thruster_allocation")

	# Simulate thruster calculations for all ships
	for i in range(_fake_ai_ships + 1):
		var force = Vector3(i * 0.1, 0, i * 0.1)
		var torque = i * 0.01

	_perf.end("Physics.thruster_allocation")

func _simulate_chunk_streamer() -> void:
	# Occasionally simulate chunk load/unload
	if _frame_counter % 120 == 0:
		_perf.begin("ChunkStreamer.load")
		# Simulate chunk loading work
		var data = []
		for i in range(100):
			data.append(i * 0.5)
		_perf.end("ChunkStreamer.load")

	if _frame_counter % 180 == 0:
		_perf.begin("ChunkStreamer.unload")
		# Simulate chunk cleanup
		_perf.end("ChunkStreamer.unload")

func _simulate_navigation() -> void:
	_perf.begin("Navigation.update")

	# Simulate pathfinding for AI ships
	for i in range(_fake_ai_ships):
		var target = Vector3(i * 10, 0, i * 10)
		var distance = target.length()

	_perf.end("Navigation.update")
