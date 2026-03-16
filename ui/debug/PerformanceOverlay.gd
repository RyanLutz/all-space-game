extends CanvasLayer

const _SEP := "─────────────────────────────────────────────────"

var _pm  # PerformanceMonitor — set by GameBootstrap via set_monitor()
var _panel: PanelContainer
var _label: Label


func _ready() -> void:
	layer = 10
	visible = false

	_panel = PanelContainer.new()
	_panel.position = Vector2(10.0, 10.0)
	add_child(_panel)

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 13)
	_panel.add_child(_label)


func set_monitor(pm: Node) -> void:
	_pm = pm


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			visible = not visible
			get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not visible or _pm == null:
		return
	_label.text = _build_text()


func _build_text() -> String:
	const FPS_TARGET := 60.0
	const FRAME_BUDGET := 1000.0 / FPS_TARGET  # 16.6ms

	var proj_dumb_ms    : float = _pm.get_avg_ms("ProjectileManager.dumb_update")
	var proj_dumb_peak  : float = _pm.get_peak_ms("ProjectileManager.dumb_update")
	var proj_dumb_cnt   : int   = _pm.get_count("ProjectileManager.active_count")

	var proj_guided_ms   : float = _pm.get_avg_ms("ProjectileManager.guided_update")
	var proj_guided_peak : float = _pm.get_peak_ms("ProjectileManager.guided_update")

	var ai_ms   : float = _pm.get_avg_ms("AIController.state_updates")
	var ai_peak : float = _pm.get_peak_ms("AIController.state_updates")
	var ai_cnt  : int   = _pm.get_count("AIController.active_count")

	var hit_ms : float = _pm.get_avg_ms("HitDetection.component_resolve")

	var physics_ms  : float = _pm.get_avg_ms("Physics.move_and_slide")
	var physics_cnt : int   = _pm.get_count("Physics.active_bodies")

	var chunk_load_ms : float = _pm.get_avg_ms("ChunkStreamer.load")
	var chunks_loaded : int   = _pm.get_count("ChunkStreamer.loaded_chunks")

	var total_ms   := proj_dumb_ms + proj_guided_ms + ai_ms + hit_ms + physics_ms
	var budget_pct := int((total_ms / FRAME_BUDGET) * 100.0)

	var chunk_str: String
	if chunk_load_ms < 0.01:
		chunk_str = "idle"
	else:
		chunk_str = "last: %.1fms" % chunk_load_ms

	var t := "[ All Space — Performance Monitor ]\n"
	t += _SEP + "\n"
	t += "%-22s  %4d active  %5.2fms avg  %5.2fms peak\n" % [
			"Projectiles (dumb)", proj_dumb_cnt, proj_dumb_ms, proj_dumb_peak]
	# Guided count metric added when GuidedProjectilePool is implemented
	t += "%-22s  %4d active  %5.2fms avg  %5.2fms peak\n" % [
			"Projectiles (guided)", 0, proj_guided_ms, proj_guided_peak]
	t += "%-22s  %4d ships   %5.2fms avg  %5.2fms peak\n" % [
			"AI state updates", ai_cnt, ai_ms, ai_peak]
	t += "%-22s             %5.2fms avg\n" % ["Hit detection", hit_ms]
	t += "%-22s  %4d        %5.2fms avg\n" % ["Physics bodies", physics_cnt, physics_ms]
	t += "%-22s  %-16s %2d chunks\n" % ["Chunk streaming", chunk_str, chunks_loaded]
	t += _SEP + "\n"
	t += "Frame budget used    %.2fms / %.1fms (%d%%)" % [total_ms, FRAME_BUDGET, budget_pct]

	return t
