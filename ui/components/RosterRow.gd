extends PanelContainer
class_name RosterRow

## Single row in the Tactical HUD fleet roster.
## Layout: [icon] [ship name + class label] [HP bar] [status string]
##
## HP bar: 3px tall, no track border, color driven by hull ratio:
##   > 0.66  → STATUS_HULL (green)
##   0.33–0.66 → STATUS_POWER (amber)
##   < 0.33  → HOSTILE (red)
##
## Selected: ship name shifts to TAC_ACCENT, icon uses TAC_ACCENT stroke.
## Divider between rows: grey-20 1px bottom border on the PanelContainer.

var _icon_rect: ColorRect      # Simple colored square icon placeholder
var _name_label: Label
var _class_label: Label
var _hp_fill: ColorRect
var _hp_track: Control
var _status_label: Label

var _style_normal: StyleBoxFlat
var _style_selected: StyleBoxFlat

var _ship_id: int = 0


func _ready() -> void:
	_build_styles()
	add_theme_stylebox_override("panel", _style_normal)
	mouse_filter = Control.MOUSE_FILTER_PASS

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	margin.add_child(hbox)

	# ── Ship icon (simple colored square, 16×16) ─────────────────────────
	_icon_rect = ColorRect.new()
	_icon_rect.custom_minimum_size = Vector2(16, 16)
	_icon_rect.color = UITokens.GREY_50
	hbox.add_child(_icon_rect)

	# ── Info column: name + class + HP bar + status ──────────────────────
	var info_col := VBoxContainer.new()
	info_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_col.add_theme_constant_override("separation", 2)
	hbox.add_child(info_col)

	# Name / class row
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	info_col.add_child(name_row)

	_name_label = Label.new()
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.add_theme_color_override("font_color", UITokens.GREY_100)
	UITokens.apply_font_label(_name_label, UITokens.SIZE_ROSTER_NAME)
	name_row.add_child(_name_label)

	_class_label = Label.new()
	_class_label.add_theme_color_override("font_color", UITokens.GREY_50)
	UITokens.apply_font_label(_class_label, UITokens.SIZE_PANEL_HDR)
	name_row.add_child(_class_label)

	# HP bar (3px, no track border)
	_hp_track = Control.new()
	_hp_track.custom_minimum_size = Vector2(0, 3)
	_hp_track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_col.add_child(_hp_track)

	_hp_fill = ColorRect.new()
	_hp_fill.color = UITokens.STATUS_HULL
	_hp_fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hp_track.add_child(_hp_fill)

	# Status string
	_status_label = Label.new()
	_status_label.add_theme_color_override("font_color", UITokens.GREY_50)
	UITokens.apply_font_data(_status_label, UITokens.SIZE_COORD)
	info_col.add_child(_status_label)


func _build_styles() -> void:
	_style_normal = StyleBoxFlat.new()
	_style_normal.bg_color = Color(0, 0, 0, 0)
	_style_normal.border_color = UITokens.GREY_20
	_style_normal.border_width_bottom = 1
	_style_normal.set_corner_radius_all(0)

	_style_selected = StyleBoxFlat.new()
	_style_selected.bg_color = UITokens.TAC_ACCENT_FAINT
	_style_selected.border_color = UITokens.GREY_20
	_style_selected.border_width_bottom = 1
	_style_selected.set_corner_radius_all(0)


## Populate all row fields. hull_ratio is 0.0–1.0.
func set_ship_data(ship_id: int, display_name: String, class_str: String,
		hull_ratio: float, status: String) -> void:
	_ship_id = ship_id

	if _name_label:
		_name_label.text = display_name.to_upper()
	if _class_label:
		_class_label.text = class_str.to_upper()
	if _status_label:
		_status_label.text = status

	_update_hp_bar(hull_ratio)


func _update_hp_bar(ratio: float) -> void:
	if _hp_fill == null or _hp_track == null:
		return
	var clamped := clampf(ratio, 0.0, 1.0)
	# Width is set via size relative to track — tracked in _process
	_hp_fill.size.x = _hp_track.size.x * clamped

	if ratio > 0.66:
		_hp_fill.color = UITokens.STATUS_HULL
	elif ratio > 0.33:
		_hp_fill.color = UITokens.STATUS_POWER
	else:
		_hp_fill.color = UITokens.HOSTILE


## Update HP bar without touching other fields (called on live ship_damaged events).
func update_hull(ratio: float) -> void:
	_update_hp_bar(ratio)


func _process(_delta: float) -> void:
	# Keep HP fill width synced with track size after layout changes
	if _hp_fill and _hp_track and _hp_track.size.x > 0.0:
		var current_ratio := _hp_fill.size.x / _hp_track.size.x
		_hp_fill.size.x = _hp_track.size.x * current_ratio


## Toggle selected visual state.
func set_selected(selected: bool) -> void:
	if selected:
		add_theme_stylebox_override("panel", _style_selected)
		if _name_label:
			_name_label.add_theme_color_override("font_color", UITokens.TAC_ACCENT)
		if _icon_rect:
			_icon_rect.color = UITokens.TAC_ACCENT
	else:
		add_theme_stylebox_override("panel", _style_normal)
		if _name_label:
			_name_label.add_theme_color_override("font_color", UITokens.GREY_100)
		if _icon_rect:
			_icon_rect.color = UITokens.GREY_50


func get_ship_id() -> int:
	return _ship_id
