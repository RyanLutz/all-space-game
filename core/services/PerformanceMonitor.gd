extends Node

const WINDOW_SIZE = 60

var _timers: Dictionary = {}
var _samples: Dictionary = {}
var _counts: Dictionary = {}
var _peaks: Dictionary = {}

func _ready() -> void:
	Performance.add_custom_monitor("AllSpace/projectiles_active",
		func(): return get_count("ProjectileManager.active_count"))
	Performance.add_custom_monitor("AllSpace/ai_ships_active",
		func(): return get_count("AIController.active_count"))
	Performance.add_custom_monitor("AllSpace/chunks_loaded",
		func(): return get_count("ChunkStreamer.loaded_chunks"))
	Performance.add_custom_monitor("AllSpace/projectile_ms",
		func(): return get_avg_ms("ProjectileManager.dumb_update"))
	Performance.add_custom_monitor("AllSpace/ai_ms",
		func(): return get_avg_ms("AIController.state_updates"))
	Performance.add_custom_monitor("AllSpace/physics_ms",
		func(): return get_avg_ms("Physics.thruster_allocation"))

func begin(metric: String) -> void:
	_timers[metric] = Time.get_ticks_usec()

func end(metric: String) -> void:
	if not _timers.has(metric):
		return
	var elapsed_ms = (Time.get_ticks_usec() - _timers[metric]) / 1000.0
	if not _samples.has(metric):
		_samples[metric] = []
	_samples[metric].append(elapsed_ms)
	if _samples[metric].size() > WINDOW_SIZE:
		_samples[metric].pop_front()
	if elapsed_ms > _peaks.get(metric, 0.0):
		_peaks[metric] = elapsed_ms

func set_count(metric: String, value: int) -> void:
	_counts[metric] = value

func get_avg_ms(metric: String) -> float:
	if not _samples.has(metric) or _samples[metric].is_empty():
		return 0.0
	var total = 0.0
	for s in _samples[metric]:
		total += s
	return total / _samples[metric].size()

func get_peak_ms(metric: String) -> float:
	return _peaks.get(metric, 0.0)

func get_count(metric: String) -> int:
	return _counts.get(metric, 0)

func reset_peaks() -> void:
	_peaks.clear()

func get_all_metrics() -> Dictionary:
	var result = {
		"timings": {},
		"counts": {}
	}
	for metric in _samples.keys():
		result["timings"][metric] = {
			"avg_ms": get_avg_ms(metric),
			"peak_ms": get_peak_ms(metric)
		}
	for metric in _counts.keys():
		result["counts"][metric] = get_count(metric)
	return result
