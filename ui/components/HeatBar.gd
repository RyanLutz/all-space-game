extends Control
class_name HeatBar

## Reusable heat bar for per-weapon heat display. Height: 4px.
## Three flat states — no gradient transitions between them:
##   Cool     (< 0.40)  — ACCENT fill, static
##   Warm     (0.40–0.70) — STATUS_WARNING fill, static
##   Critical (> 0.70)  — STATUS_CRITICAL fill, pulse animation (opacity 0.75 → 1.0 at 0.5s)
##
## State is applied as an instant swap each time set_heat() is called.
## Pulse runs in _process() only when state == critical.

const HEIGHT     := 4
const COOL_THRESH    := 0.40
const WARM_THRESH    := 0.70
const PULSE_PERIOD   := 0.5   # seconds for one full opacity cycle
const PULSE_MIN      := 0.75
const PULSE_MAX      := 1.00

enum HeatState { COOL, WARM, CRITICAL }

var _bar: ProgressBar
var _fill_style: StyleBoxFlat
var _current_state: HeatState = HeatState.COOL
var _pulse_time: float = 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(0, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.value = 0.0
	_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var track_style := StyleBoxFlat.new()
	track_style.bg_color = UITokens.GREY_08
	track_style.set_border_width_all(0)
	track_style.set_corner_radius_all(0)
	_bar.add_theme_stylebox_override("background", track_style)

	_fill_style = StyleBoxFlat.new()
	_fill_style.bg_color = UITokens.ACCENT
	_fill_style.set_corner_radius_all(0)
	_bar.add_theme_stylebox_override("fill", _fill_style)

	add_child(_bar)


func _process(delta: float) -> void:
	if _current_state != HeatState.CRITICAL:
		return
	_pulse_time += delta
	# sin mapped from [-1,1] to [PULSE_MIN, PULSE_MAX]
	var t := (sin(_pulse_time * TAU / PULSE_PERIOD) + 1.0) * 0.5
	_bar.modulate.a = lerpf(PULSE_MIN, PULSE_MAX, t)


## ratio is 0.0–1.0. Updates fill width and applies correct state color.
func set_heat(ratio: float) -> void:
	var clamped := clampf(ratio, 0.0, 1.0)
	if _bar:
		_bar.value = clamped

	var new_state: HeatState
	if clamped > WARM_THRESH:
		new_state = HeatState.CRITICAL
	elif clamped > COOL_THRESH:
		new_state = HeatState.WARM
	else:
		new_state = HeatState.COOL

	if new_state != _current_state:
		_current_state = new_state
		_apply_state()


func _apply_state() -> void:
	match _current_state:
		HeatState.COOL:
			_fill_style.bg_color = UITokens.ACCENT
			_bar.modulate.a = 1.0
			_pulse_time = 0.0
		HeatState.WARM:
			_fill_style.bg_color = UITokens.STATUS_WARNING
			_bar.modulate.a = 1.0
			_pulse_time = 0.0
		HeatState.CRITICAL:
			_fill_style.bg_color = UITokens.STATUS_CRITICAL
			_pulse_time = 0.0


## Override cool-state fill color (e.g. TAC_ACCENT in Tactical context).
func set_cool_color(color: Color) -> void:
	if _current_state == HeatState.COOL and _fill_style:
		_fill_style.bg_color = color
