extends PanelContainer
class_name WeaponSlot

## Single weapon slot panel for the Pilot HUD weapon grid.
## Layout: slot number / weapon name / ammo count (header row) + heat bar.
##
## Inactive: surface background, grey-20 border, weapon name in grey-80.
## Active:   surface-raised background, accent-dim border, 2px top accent bar,
##           weapon name shifts to ACCENT.
##
## Empty slot (no weapon): dims all labels, heat bar stays at 0.

var _top_bar: ColorRect        # 2px accent line, visible only when active
var _slot_label: Label         # "01", "02", etc. — grey-50
var _weapon_label: Label       # weapon name — grey-80 / ACCENT when active
var _ammo_label: Label         # ammo count or "∞" — grey-50
var _heat_bar: HeatBar

var _style_inactive: StyleBoxFlat
var _style_active: StyleBoxFlat

const _HEAT_BAR_SCENE := preload("res://ui/components/HeatBar.tscn")


func _ready() -> void:
	_build_styles()
	add_theme_stylebox_override("panel", _style_inactive)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 0)
	add_child(outer)

	# ── Top accent bar (hidden by default) ──────────────────────────────────
	_top_bar = ColorRect.new()
	_top_bar.color = UITokens.ACCENT
	_top_bar.custom_minimum_size = Vector2(0, 2)
	_top_bar.visible = false
	outer.add_child(_top_bar)

	# ── Content margin ────────────────────────────────────────────────────
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	outer.add_child(margin)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)
	margin.add_child(inner)

	# ── Header row: [slot num] [weapon name] [ammo] ─────────────────────
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 6)
	inner.add_child(header_row)

	_slot_label = Label.new()
	_slot_label.add_theme_color_override("font_color", UITokens.GREY_50)
	UITokens.apply_font_label(_slot_label, UITokens.SIZE_PANEL_HDR)
	header_row.add_child(_slot_label)

	_weapon_label = Label.new()
	_weapon_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_weapon_label.add_theme_color_override("font_color", UITokens.GREY_80)
	UITokens.apply_font_label(_weapon_label, UITokens.SIZE_PANEL_HDR)
	header_row.add_child(_weapon_label)

	_ammo_label = Label.new()
	_ammo_label.add_theme_color_override("font_color", UITokens.GREY_50)
	UITokens.apply_font_data(_ammo_label, UITokens.SIZE_DATA_VALUE)
	_ammo_label.text = "--"
	header_row.add_child(_ammo_label)

	# ── Heat bar ─────────────────────────────────────────────────────────
	_heat_bar = _HEAT_BAR_SCENE.instantiate() as HeatBar
	inner.add_child(_heat_bar)


func _build_styles() -> void:
	_style_inactive = StyleBoxFlat.new()
	_style_inactive.bg_color = UITokens.SURFACE
	_style_inactive.border_color = UITokens.GREY_20
	_style_inactive.set_border_width_all(1)
	_style_inactive.set_corner_radius_all(0)

	_style_active = StyleBoxFlat.new()
	_style_active.bg_color = UITokens.SURFACE_RAISED
	_style_active.border_color = UITokens.ACCENT_DIM
	_style_active.set_border_width_all(1)
	_style_active.set_corner_radius_all(0)


## Populate the slot. Call with weapon display name; use "" for an empty slot.
func set_weapon_name(name: String) -> void:
	if _weapon_label:
		_weapon_label.text = name.to_upper() if name != "" else "EMPTY"


## Set the slot index label (1-based display, e.g. slot_index=1 → "01").
func set_slot_index(index: int) -> void:
	if _slot_label:
		_slot_label.text = "%02d" % index


## Switch active/inactive visual state.
func set_active(active: bool) -> void:
	if active:
		add_theme_stylebox_override("panel", _style_active)
		_top_bar.visible = true
		if _weapon_label:
			_weapon_label.add_theme_color_override("font_color", UITokens.ACCENT)
	else:
		add_theme_stylebox_override("panel", _style_inactive)
		_top_bar.visible = false
		if _weapon_label:
			_weapon_label.add_theme_color_override("font_color", UITokens.GREY_80)


## ratio is 0.0–1.0. Delegates to HeatBar.
func set_heat(ratio: float) -> void:
	if _heat_bar:
		_heat_bar.set_heat(ratio)


## Ammo display string. Pass "∞" for energy weapons, "--" for unknown.
func set_ammo_text(text: String) -> void:
	if _ammo_label:
		_ammo_label.text = text


## Dim all labels for an empty/unavailable slot.
func set_empty(is_empty: bool) -> void:
	var alpha := 0.35 if is_empty else 1.0
	modulate.a = alpha
