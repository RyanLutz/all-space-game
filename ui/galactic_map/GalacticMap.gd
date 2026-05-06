extends Control
class_name GalacticMap

## Galactic map overlay — full-viewport Control inside a CanvasLayer (layer 10).
## Toggle via GameEventBus.galactic_map_toggled(open: bool).
## Emits GameEventBus.warp_destination_selected(system_id) when player selects a
## reachable destination system.

# ── Drawing constants ────────────────────────────────────────────────────────
const _BG_COLOR         := Color(0.02, 0.02, 0.06, 0.92)
const _BACKDROP_MONO    := Color(0.50, 0.55, 0.65, 0.35)
const _DEST_COLOR       := Color(0.75, 0.80, 1.00, 0.80)
const _REACHABLE_COLOR  := Color(0.25, 0.82, 1.00, 1.00)
const _CURRENT_COLOR    := Color(1.00, 1.00, 0.30, 1.00)
const _PATH_COLOR_BASE  := Color(0.25, 0.82, 1.00, 0.00)  # alpha set at draw time

const _R_BACKDROP   := 1.0
const _R_DEST       := 2.5
const _R_REACHABLE  := 3.5
const _R_CURRENT    := 5.0

# Isometric Y-weight: galaxy Y-axis contributes slight vertical offset in 2D
const _ISO_Y := 0.15

# ── State ────────────────────────────────────────────────────────────────────
var _starfield: Node = null
var _bus: Node = null

## pixels per galaxy unit
var _scale: float = 0.004
## pan offset in screen pixels (applied after centering)
var _pan: Vector2 = Vector2.ZERO

var _dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _pan_at_drag: Vector2 = Vector2.ZERO

## Normalized zoom level [0..1]. 0 = full galaxy view, 1 = close zoom.
## Drives information-density thresholds and is exposed for S4 nebula wiring.
var map_zoom: float = 0.0

var _current_system: SFStarRecord = null


func _ready() -> void:
	_bus = get_node_or_null("/root/GameEventBus")
	if _bus:
		_bus.galactic_map_toggled.connect(_on_map_toggled)
	_starfield = get_node_or_null("/root/StarField")
	_sync_current_system()
	visible = false
	mouse_filter = MOUSE_FILTER_STOP


## Called by the warp system (or test scene) to tell the map which system the
## player currently occupies. GalacticMap reads this automatically on open.
func set_current_system(record: SFStarRecord) -> void:
	_current_system = record
	if visible:
		queue_redraw()


func _sync_current_system() -> void:
	if _starfield == null:
		return
	if _starfield.current_system != null:
		_current_system = _starfield.current_system
		return
	var dests: Array[SFStarRecord] = _starfield.get_destinations()
	if dests.size() > 0:
		_current_system = dests[0]


func _on_map_toggled(open: bool) -> void:
	visible = open
	if open:
		_sync_current_system()
		_reset_view()
		queue_redraw()


func _reset_view() -> void:
	_scale = (size.y * 0.45) / maxf(_galaxy_radius(), 1.0)
	_pan = Vector2.ZERO
	_recalc_map_zoom()


func _galaxy_radius() -> float:
	if _starfield:
		return float(_starfield.get_config().get("galaxy_radius", 100000.0))
	return 100000.0


func _galaxy_to_screen(p: Vector3) -> Vector2:
	return Vector2(
		p.x * _scale + size.x * 0.5 + _pan.x,
		(p.z - p.y * _ISO_Y) * _scale + size.y * 0.5 + _pan.y)


func _recalc_map_zoom() -> void:
	var base := (size.y * 0.45) / maxf(_galaxy_radius(), 1.0)
	# map_zoom: 0 at base scale, 1 at 10× base
	map_zoom = clampf((_scale / maxf(base, 1e-9) - 1.0) / 9.0, 0.0, 1.0)


# ── Input ────────────────────────────────────────────────────────────────────

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_zoom_at(1.15, event.position)
				accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_at(1.0 / 1.15, event.position)
				accept_event()
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					_dragging = true
					_drag_start = event.position
					_pan_at_drag = _pan
				else:
					_dragging = false
					if event.position.distance_to(_drag_start) < 6.0:
						_try_select(event.position)
				accept_event()
			MOUSE_BUTTON_RIGHT:
				_dragging = event.pressed
				if event.pressed:
					_drag_start = event.position
					_pan_at_drag = _pan
				accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_pan = _pan_at_drag + (event.position - _drag_start)
		queue_redraw()
		accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			if _bus:
				_bus.galactic_map_toggled.emit(false)
			accept_event()


func _zoom_at(factor: float, pivot: Vector2) -> void:
	var base := (size.y * 0.45) / maxf(_galaxy_radius(), 1.0)
	var new_scale := clampf(_scale * factor, base * 0.5, base * 50.0)
	var ratio := new_scale / maxf(_scale, 1e-9)
	var center := size * 0.5
	# Keep the galaxy point under the cursor stationary
	_pan = (pivot - center) * (1.0 - ratio) + _pan * ratio
	_scale = new_scale
	_recalc_map_zoom()
	queue_redraw()


func _try_select(screen_pos: Vector2) -> void:
	if _starfield == null or _current_system == null or _bus == null:
		return
	var best_dist := 12.0  # pixels
	var best: SFStarRecord = null
	for star: SFStarRecord in _starfield.get_destinations():
		if star == _current_system:
			continue
		var dist_gal := star.galaxy_position.distance_to(_current_system.galaxy_position)
		if dist_gal > star.warp_range:
			continue
		var sp := _galaxy_to_screen(star.galaxy_position)
		var d := screen_pos.distance_to(sp)
		if d < best_dist:
			best_dist = d
			best = star
	if best != null:
		_bus.warp_destination_selected.emit(best.system_id)


# ── Drawing ──────────────────────────────────────────────────────────────────

func _draw() -> void:
	if _starfield == null:
		return

	draw_rect(Rect2(Vector2.ZERO, size), _BG_COLOR)

	# Information-density thresholds keyed off map_zoom
	var is_mid   := map_zoom > 0.15   # ~2.35× base scale
	var is_close := map_zoom > 0.55   # ~5.95× base scale

	var current_pos: Vector3 = \
		_current_system.galaxy_position if _current_system != null else Vector3.ZERO

	# ── Backdrop stars ───────────────────────────────────────────────────────
	for star: SFStarRecord in _starfield.get_catalog():
		if star.is_destination:
			continue
		var sp := _galaxy_to_screen(star.galaxy_position)
		if sp.x < -4.0 or sp.x > size.x + 4.0 \
				or sp.y < -4.0 or sp.y > size.y + 4.0:
			continue
		var col: Color
		if is_close:
			col = star.color
			col.a = 0.55
		else:
			col = _BACKDROP_MONO
		draw_circle(sp, _R_BACKDROP, col)

	# Galaxy boundary ring (orientation aid)
	var gr := _galaxy_radius()
	var ring_r := gr * _scale
	draw_arc(Vector2(size.x * 0.5, size.y * 0.5) + _pan,
		ring_r, 0.0, TAU, 128, Color(0.3, 0.4, 0.6, 0.12), 1.0)

	# ── Nav paths (mid+ zoom) ────────────────────────────────────────────────
	if is_mid and _current_system != null:
		var path_alpha := clampf((map_zoom - 0.15) / 0.4, 0.0, 1.0) * 0.35
		var csp := _galaxy_to_screen(current_pos)
		for star: SFStarRecord in _starfield.get_destinations():
			if star == _current_system:
				continue
			var dist_gal := star.galaxy_position.distance_to(current_pos)
			if dist_gal <= star.warp_range:
				var esp := _galaxy_to_screen(star.galaxy_position)
				draw_line(csp, esp,
					Color(_REACHABLE_COLOR.r, _REACHABLE_COLOR.g, _REACHABLE_COLOR.b, path_alpha),
					1.0)

	# ── Destination systems ──────────────────────────────────────────────────
	var font := ThemeDB.fallback_font
	for star: SFStarRecord in _starfield.get_destinations():
		var sp := _galaxy_to_screen(star.galaxy_position)
		if sp.x < -24.0 or sp.x > size.x + 24.0 \
				or sp.y < -24.0 or sp.y > size.y + 24.0:
			continue

		var is_current   := star == _current_system
		var dist_gal     := star.galaxy_position.distance_to(current_pos) \
			if _current_system != null else INF
		var is_reachable := not is_current and dist_gal <= star.warp_range

		var col: Color
		var radius: float
		if is_current:
			col    = _CURRENT_COLOR
			radius = _R_CURRENT
		elif is_reachable:
			col    = _REACHABLE_COLOR
			radius = _R_REACHABLE
			draw_circle(sp, radius * 2.4,
				Color(_REACHABLE_COLOR.r, _REACHABLE_COLOR.g, _REACHABLE_COLOR.b, 0.11))
		else:
			col    = _DEST_COLOR
			radius = _R_DEST

		draw_circle(sp, radius, col)

		# Labels at close zoom for current + reachable
		if is_close and (is_current or is_reachable):
			var lpos := sp + Vector2(radius + 4.0, -5.0)
			var lbl  := String(star.system_id)
			if is_reachable:
				lbl += "\n%.0f" % dist_gal
			draw_string(font, lpos, lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, col)

	# Current system pulse ring (drawn on top of everything)
	if _current_system != null:
		var sp := _galaxy_to_screen(current_pos)
		draw_arc(sp, _R_CURRENT + 5.0, 0.0, TAU, 48,
			Color(_CURRENT_COLOR.r, _CURRENT_COLOR.g, _CURRENT_COLOR.b, 0.55), 1.5)

	# ── HUD hint ─────────────────────────────────────────────────────────────
	draw_string(font,
		Vector2(12.0, size.y - 12.0),
		"Scroll=zoom  Drag=pan  Click=warp  Esc=close",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		Color(0.55, 0.65, 0.75, 0.65))
