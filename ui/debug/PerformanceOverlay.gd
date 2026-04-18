extends CanvasLayer

@onready var label: Label = $Label

var _visible: bool = false

const METRIC_DISPLAY_NAMES = {
	"ProjectileManager.dumb_update": "Projectiles (dumb)",
	"ProjectileManager.guided_update": "Projectiles (guided)",
	"ProjectileManager.collision_checks": "Projectile collisions",
	"ProjectileManager.active_count": "Projectiles (dumb)",
	"AIController.state_updates": "AI state updates",
	"AIController.active_count": "AI ships",
	"Navigation.update": "Navigation",
	"Physics.thruster_allocation": "Physics (thrusters)",
	"Physics.active_bodies": "Physics bodies",
	"HitDetection.component_resolve": "Hit detection",
	"ChunkStreamer.load": "Chunk load",
	"ChunkStreamer.unload": "Chunk unload",
	"ChunkStreamer.loaded_chunks": "Chunks loaded",
	"ContentRegistry.load": "Content registry",
	"ShipFactory.assemble": "Ship assembly",
	"Ships.active_count": "Ships",
	"Camera.update": "Camera"
}

func _ready() -> void:
	visible = false
	if label:
		label.position = Vector2(10, 10)

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.pressed and event.keycode == KEY_F3:
			_visible = not _visible
			visible = _visible

func _pad_right(s: String, width: int) -> String:
	while s.length() < width:
		s = s + " "
	return s

func _pad_left(s: String, width: int) -> String:
	while s.length() < width:
		s = " " + s
	return s

func _process(_delta: float) -> void:
	if not _visible:
		return
	if not label:
		return

	var lines: Array[String] = []
	lines.append("[ All Space — Performance Monitor ]")
	lines.append("───────────────────────────────────────────────────")

	var metrics = PerformanceMonitor.get_all_metrics()
	var total_ms = 0.0

	# Timing metrics
	for metric in metrics["timings"]:
		var data = metrics["timings"][metric]
		var display_name = METRIC_DISPLAY_NAMES.get(metric, metric)
		var avg = data["avg_ms"]
		var peak = data["peak_ms"]
		total_ms += avg

		var avg_str = "%.1fms avg" % avg
		var line = _pad_right(display_name, 22) + _pad_left(avg_str, 12)
		if peak > avg * 1.5:
			var peak_str = "%.1fms peak" % peak
			line += _pad_left(peak_str, 14)
		lines.append(line)

	# Count metrics
	for metric in metrics["counts"]:
		var count = metrics["counts"][metric]
		var display_name = METRIC_DISPLAY_NAMES.get(metric, metric)
		var count_str = str(count) + " active"
		var line = _pad_right(display_name, 22) + _pad_left(count_str, 12)
		lines.append(line)

	lines.append("───────────────────────────────────────────────────")

	var target_fps = Engine.max_fps
	if target_fps == 0:
		target_fps = 60
	var budget_ms = 1000.0 / target_fps
	var percent = (total_ms / budget_ms) * 100.0

	var budget_str = "%.1fms / %.1fms (%.0f%%)" % [total_ms, budget_ms, percent]
	lines.append("Frame budget used   " + budget_str)

	label.text = "\n".join(lines)
