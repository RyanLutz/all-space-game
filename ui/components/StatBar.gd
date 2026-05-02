extends MarginContainer
class_name StatBar

## Reusable filled bar for hull integrity and power level.
## Track: grey-08 fill, grey-20 border, 6px height.
## Fill color is set by the caller (STATUS_HULL or STATUS_POWER).
## Value label shifts to STATUS_CRITICAL when mark_critical() is called.

var _header_label: Label
var _value_label: Label
var _bar: ProgressBar
var _fill_style: StyleBoxFlat


func _ready() -> void:
	add_theme_constant_override("margin_left", 0)
	add_theme_constant_override("margin_right", 0)
	add_theme_constant_override("margin_top", 0)
	add_theme_constant_override("margin_bottom", 0)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	add_child(vbox)

	# ── Header row ──────────────────────────────────────────────────────────
	var row := HBoxContainer.new()
	vbox.add_child(row)

	_header_label = Label.new()
	_header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header_label.add_theme_color_override("font_color", UITokens.GREY_50)
	UITokens.apply_font_label(_header_label, UITokens.SIZE_PANEL_HDR)
	row.add_child(_header_label)

	_value_label = Label.new()
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_value_label.add_theme_color_override("font_color", UITokens.GREY_80)
	UITokens.apply_font_data(_value_label, UITokens.SIZE_DATA_VALUE)
	row.add_child(_value_label)

	# ── Bar ─────────────────────────────────────────────────────────────────
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.value = 1.0
	_bar.custom_minimum_size = Vector2(0, 6)
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var track_style := StyleBoxFlat.new()
	track_style.bg_color = UITokens.GREY_08
	track_style.border_color = UITokens.GREY_20
	track_style.set_border_width_all(1)
	track_style.set_corner_radius_all(0)
	_bar.add_theme_stylebox_override("background", track_style)

	_fill_style = StyleBoxFlat.new()
	_fill_style.bg_color = UITokens.STATUS_HULL
	_fill_style.set_corner_radius_all(0)
	_bar.add_theme_stylebox_override("fill", _fill_style)

	vbox.add_child(_bar)


func set_header(text: String) -> void:
	if _header_label:
		_header_label.text = text.to_upper()


func set_fill_color(color: Color) -> void:
	if _fill_style:
		_fill_style.bg_color = color


## ratio is 0.0–1.0. Updates bar and value label text.
func set_ratio(ratio: float) -> void:
	var clamped := clampf(ratio, 0.0, 1.0)
	if _bar:
		_bar.value = clamped
	if _value_label:
		_value_label.text = "%d%%" % roundi(clamped * 100.0)


## Override the value label text directly (e.g. for power: "84 / 100").
func set_value_text(text: String) -> void:
	if _value_label:
		_value_label.text = text


## Shift value label to STATUS_CRITICAL color when hull is below threshold.
func mark_critical(is_critical: bool) -> void:
	if _value_label:
		_value_label.add_theme_color_override("font_color",
			UITokens.STATUS_CRITICAL if is_critical else UITokens.GREY_80)
