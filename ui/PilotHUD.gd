extends Control
class_name PilotHUD

## Pilot mode HUD. Five panels + hit flash overlay.
##
## Listens for:
##   GameEventBus.player_ship_changed  → binds ship, discovers hardpoints
##   GameEventBus.game_mode_changed    → shows/hides self
##   GameEventBus.ship_damaged         → triggers hit flash on player hit
##
## Never holds references to TacticalHUD or ModeSwitch.
## Per-frame ship state is polled directly from the bound Ship node —
## hull_hp, shield_hp, power_current are public properties, not cross-system.
## Hardpoint heat is polled from each HardpointComponent (the ship's own sub-nodes).

# ─── Services ────────────────────────────────────────────────────────────────
var _event_bus: Node
var _perf: Node

# ─── Ship binding ─────────────────────────────────────────────────────────────
var _player_ship: Ship = null
var _hardpoints: Array[HardpointComponent] = []

# ─── Layout constants ─────────────────────────────────────────────────────────
const MARGIN          := 16    # px from screen edge
const TAG_W           := 150   # Mode Tag width
const TAG_H           := 64    # Mode Tag height
const TARGET_W        := 250   # Target Lock width
const TARGET_H        := 92    # Target Lock height
const VESSEL_W        := 248   # Vessel Status width
const VESSEL_H        := 208   # Vessel Status height
const WEAPON_W        := 268   # Weapon Systems width — height is content-driven
const RADAR_SIZE      := 164   # Radar diameter (square container, drawn as circle)

# ─── Hit flash ────────────────────────────────────────────────────────────────
const FLASH_PEAK      := 0.15
const FLASH_DECAY_PS  := 3.3   # alpha units per second (0.055/frame × 60fps)

var _flash_alpha: float = 0.0
var _hit_flash: ColorRect

# ─── Panel nodes ──────────────────────────────────────────────────────────────
var _mode_tag: PanelContainer
var _target_lock: PanelContainer
var _vessel_panel: PanelContainer
var _weapon_panel: PanelContainer
var _radar: Radar

# ─── Mode tag inner nodes ─────────────────────────────────────────────────────
var _mode_sub_label: Label   # "FLIGHT MODE"
var _mode_name_label: Label  # "PILOT"

# ─── Target lock inner nodes ──────────────────────────────────────────────────
var _tgt_name_label: Label
var _tgt_hull_value: Label
var _tgt_dist_value: Label
var _tgt_threat_value: Label

# ─── Vessel status inner nodes ────────────────────────────────────────────────
var _vessel_name_label: Label
var _shield_bar: SegBar
var _hull_bar: StatBar
var _power_bar: StatBar
var _coord_label: Label

# ─── Weapon slots ─────────────────────────────────────────────────────────────
const WEAPON_SLOT_SCENE := preload("res://ui/components/WeaponSlot.tscn")
const RADAR_SCENE       := preload("res://ui/radar/Radar.tscn")
const STATBAR_SCENE     := preload("res://ui/components/StatBar.tscn")
const SEGBAR_SCENE      := preload("res://ui/components/SegBar.tscn")

var _weapon_slots: Array[WeaponSlot] = []
var _weapon_grid: GridContainer = null


# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	var service_locator := Engine.get_singleton("ServiceLocator")
	_event_bus = service_locator.GetService("GameEventBus")
	_perf      = service_locator.GetService("PerformanceMonitor")

	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# Build order matters: hit flash first (lowest z), panels on top
	_build_hit_flash()
	_build_mode_tag()
	_build_target_lock()
	_build_vessel_status()
	_build_weapon_systems()
	_build_radar()

	# Event bus subscriptions
	if _event_bus:
		_event_bus.player_ship_changed.connect(_on_player_ship_changed)
		_event_bus.game_mode_changed.connect(_on_game_mode_changed)
		_event_bus.ship_damaged.connect(_on_ship_damaged)

	# Bind to the player ship if it already exists (HUD added after spawn)
	var player_state: PlayerState = service_locator.GetService("PlayerState") as PlayerState
	if player_state and player_state.active_ship:
		_on_player_ship_changed(player_state.active_ship)


func _process(delta: float) -> void:
	_perf.begin("UI.pilot_hud_update")

	_decay_hit_flash(delta)

	if _player_ship != null and is_instance_valid(_player_ship):
		_update_vessel_status()
		_update_weapon_slots()
		_update_coords()
	elif _player_ship != null:
		# Ship was freed without a player_ship_changed event (e.g. destroyed)
		_player_ship = null
		_hardpoints.clear()

	_perf.end("UI.pilot_hud_update")


# ─── Hit Flash ────────────────────────────────────────────────────────────────

func _build_hit_flash() -> void:
	_hit_flash = ColorRect.new()
	_hit_flash.name = "HitFlash"
	_hit_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hit_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hit_flash.color = Color(UITokens.HOSTILE.r, UITokens.HOSTILE.g, UITokens.HOSTILE.b, 0.0)
	add_child(_hit_flash)


func _decay_hit_flash(delta: float) -> void:
	if _flash_alpha <= 0.0:
		return
	_flash_alpha = maxf(0.0, _flash_alpha - FLASH_DECAY_PS * delta)
	_hit_flash.color.a = _flash_alpha


func _trigger_hit_flash() -> void:
	_flash_alpha = FLASH_PEAK
	_hit_flash.color.a = _flash_alpha


# ─── Panel Builders ───────────────────────────────────────────────────────────

func _build_mode_tag() -> void:
	_mode_tag = _make_panel(TAG_W, TAG_H,
			0.0, 0.0, 0.0, 0.0,
			float(MARGIN), float(MARGIN), float(MARGIN + TAG_W), float(MARGIN + TAG_H))

	var margin := _panel_margin(_mode_tag)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	margin.add_child(vbox)

	_mode_sub_label = Label.new()
	_mode_sub_label.text = "FLIGHT MODE"
	_mode_sub_label.add_theme_color_override("font_color", UITokens.GREY_50)
	UITokens.apply_font_label(_mode_sub_label, UITokens.SIZE_PANEL_HDR)
	vbox.add_child(_mode_sub_label)

	_mode_name_label = Label.new()
	_mode_name_label.text = "PILOT"
	_mode_name_label.add_theme_color_override("font_color", UITokens.ACCENT)
	UITokens.apply_font_label_weight(_mode_name_label, UITokens.SIZE_MODE_NAME, 700)
	vbox.add_child(_mode_name_label)


func _build_target_lock() -> void:
	var cx := 0.5
	_target_lock = _make_panel(TARGET_W, TARGET_H,
			cx, 0.0, cx, 0.0,
			-TARGET_W / 2.0, float(MARGIN), TARGET_W / 2.0, float(MARGIN + TARGET_H))
	_target_lock.visible = false  # hidden until targeting system exists

	var margin := _panel_margin(_target_lock)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	var hdr := Label.new()
	hdr.text = "TARGET LOCKED"
	hdr.add_theme_color_override("font_color", UITokens.GREY_50)
	UITokens.apply_font_label(hdr, UITokens.SIZE_PANEL_HDR)
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hdr)

	_tgt_name_label = Label.new()
	_tgt_name_label.add_theme_color_override("font_color", UITokens.HOSTILE)
	UITokens.apply_font_label_weight(_tgt_name_label, 13, 700)
	_tgt_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_tgt_name_label)

	var stat_row := HBoxContainer.new()
	stat_row.add_theme_constant_override("separation", 16)
	stat_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(stat_row)

	_tgt_hull_value  = _make_stat_readout(stat_row, "HULL")
	_tgt_dist_value  = _make_stat_readout(stat_row, "DIST")
	_tgt_threat_value = _make_stat_readout(stat_row, "THREAT")


func _build_vessel_status() -> void:
	_vessel_panel = _make_panel(VESSEL_W, VESSEL_H,
			0.0, 1.0, 0.0, 1.0,
			float(MARGIN), float(-MARGIN - VESSEL_H), float(MARGIN + VESSEL_W), float(-MARGIN))

	var margin := _panel_margin(_vessel_panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	# Panel header
	var hdr := Label.new()
	hdr.text = "VESSEL STATUS"
	hdr.add_theme_color_override("font_color", UITokens.GREY_50)
	UITokens.apply_font_label(hdr, UITokens.SIZE_PANEL_HDR)
	vbox.add_child(hdr)

	# Ship name
	_vessel_name_label = Label.new()
	_vessel_name_label.text = "---"
	_vessel_name_label.add_theme_color_override("font_color", UITokens.GREY_100)
	UITokens.apply_font_label_weight(_vessel_name_label, UITokens.SIZE_SHIP_NAME, 700)
	vbox.add_child(_vessel_name_label)

	# Divider
	vbox.add_child(_make_divider())

	# Shields — segmented bar with label
	var shield_row_label := Label.new()
	shield_row_label.text = "SHIELDS"
	shield_row_label.add_theme_color_override("font_color", UITokens.GREY_50)
	UITokens.apply_font_label(shield_row_label, UITokens.SIZE_DATA_LABEL)
	vbox.add_child(shield_row_label)

	_shield_bar = SEGBAR_SCENE.instantiate() as SegBar
	vbox.add_child(_shield_bar)

	# Hull bar
	_hull_bar = STATBAR_SCENE.instantiate() as StatBar
	_hull_bar.set_header("HULL")
	_hull_bar.set_fill_color(UITokens.STATUS_HULL)
	vbox.add_child(_hull_bar)

	# Power bar
	_power_bar = STATBAR_SCENE.instantiate() as StatBar
	_power_bar.set_header("POWER")
	_power_bar.set_fill_color(UITokens.STATUS_POWER)
	vbox.add_child(_power_bar)

	# Coordinate / speed string
	_coord_label = Label.new()
	_coord_label.text = "X:0  Z:0  |  0.0 m/s"
	_coord_label.add_theme_color_override("font_color", UITokens.GREY_50)
	UITokens.apply_font_data(_coord_label, UITokens.SIZE_COORD)
	vbox.add_child(_coord_label)


func _build_weapon_systems() -> void:
	var cx := 0.5
	# anchor_top = anchor_bottom = 1.0, offset_top = offset_bottom = -MARGIN → zero initial height.
	# grow_vertical = GROW_DIRECTION_BEGIN → panel expands upward from bottom edge to fit content.
	_weapon_panel = _make_panel(WEAPON_W, 0,
			cx, 1.0, cx, 1.0,
			-WEAPON_W / 2.0, float(-MARGIN), WEAPON_W / 2.0, float(-MARGIN))
	_weapon_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN

	var margin := _panel_margin(_weapon_panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	var hdr := Label.new()
	hdr.text = "WEAPON SYSTEMS"
	hdr.add_theme_color_override("font_color", UITokens.GREY_50)
	UITokens.apply_font_label(hdr, UITokens.SIZE_PANEL_HDR)
	vbox.add_child(hdr)

	_weapon_grid = GridContainer.new()
	_weapon_grid.columns = 2
	_weapon_grid.add_theme_constant_override("h_separation", 4)
	_weapon_grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(_weapon_grid)


func _build_radar() -> void:
	# Radar sits in a square container anchored to bottom-right
	var container := Control.new()
	container.name = "RadarContainer"
	container.anchor_left   = 1.0
	container.anchor_top    = 1.0
	container.anchor_right  = 1.0
	container.anchor_bottom = 1.0
	container.offset_left   = float(-MARGIN - RADAR_SIZE)
	container.offset_top    = float(-MARGIN - RADAR_SIZE)
	container.offset_right  = float(-MARGIN)
	container.offset_bottom = float(-MARGIN)
	container.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	add_child(container)

	_radar = RADAR_SCENE.instantiate() as Radar
	_radar.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.add_child(_radar)


# ─── Per-Frame Updates ────────────────────────────────────────────────────────

func _update_vessel_status() -> void:
	var ship := _player_ship

	# Shield bar
	if ship.shield_max > 0.0:
		_shield_bar.set_ratio(ship.shield_hp / ship.shield_max)
	else:
		_shield_bar.set_ratio(0.0)

	# Hull bar
	var hull_ratio := ship.hull_hp / maxf(ship.hull_max, 0.001)
	_hull_bar.set_ratio(hull_ratio)
	_hull_bar.mark_critical(hull_ratio < 0.20)

	# Power bar
	_power_bar.set_ratio(ship.power_current / maxf(ship.power_capacity, 0.001))


func _update_weapon_slots() -> void:
	var ship := _player_ship
	for i in _weapon_slots.size():
		var slot: WeaponSlot = _weapon_slots[i]
		if i >= _hardpoints.size():
			slot.set_empty(true)
			slot.set_heat(0.0)
			slot.set_ammo_text("--")
			continue

		var hp: HardpointComponent = _hardpoints[i]
		if not is_instance_valid(hp):
			slot.set_empty(true)
			slot.set_heat(0.0)
			slot.set_ammo_text("--")
			continue

		slot.set_empty(false)

		# Heat
		var heat_ratio := hp.heat_current / maxf(hp.heat_capacity, 0.001)
		slot.set_heat(heat_ratio)

		# Active: any of this hardpoint's fire groups is currently pressed
		var is_active := false
		for group_idx in hp.fire_groups:
			if group_idx < ship.input_fire.size() and ship.input_fire[group_idx]:
				is_active = true
				break
		slot.set_active(is_active)

		# Ammo: no ammo tracking yet — energy weapons show ∞, others show --
		slot.set_ammo_text(_get_ammo_text(hp))


func _update_coords() -> void:
	if _coord_label == null:
		return
	var pos   := _player_ship.global_position
	var speed := Vector2(_player_ship.linear_velocity.x, _player_ship.linear_velocity.z).length()
	_coord_label.text = "X:%.0f  Z:%.0f  |  %.1f m/s" % [pos.x, pos.z, speed]


# ─── Ship Binding ─────────────────────────────────────────────────────────────

func _on_player_ship_changed(ship: Node) -> void:
	_player_ship = ship as Ship
	_hardpoints.clear()

	if _player_ship == null:
		_vessel_name_label.text = "---"
		for slot in _weapon_slots:
			slot.queue_free()
		_weapon_slots.clear()
		if _radar:
			_radar.player_ship = null
		return

	_vessel_name_label.text = _player_ship.display_name.to_upper()

	_collect_hardpoints()
	_populate_weapon_slot_names()

	if _radar:
		_radar.player_ship = _player_ship


func _collect_hardpoints() -> void:
	var visual := _player_ship.get_node_or_null("ShipVisual")
	if visual == null:
		return
	_collect_hardpoints_recursive(visual)
	# Stable ordering by hardpoint_id ensures consistent slot assignment
	_hardpoints.sort_custom(func(a: HardpointComponent, b: HardpointComponent) -> bool:
		return a.hardpoint_id < b.hardpoint_id)


func _collect_hardpoints_recursive(node: Node) -> void:
	if node.name.begins_with("HardpointEmpty_"):
		for child in node.get_children():
			if child is HardpointComponent:
				_hardpoints.append(child as HardpointComponent)
				break
	for child in node.get_children():
		_collect_hardpoints_recursive(child)


func _populate_weapon_slot_names() -> void:
	# Remove all existing slots and rebuild from actual hardpoint count
	for slot in _weapon_slots:
		slot.queue_free()
	_weapon_slots.clear()

	for i in _hardpoints.size():
		var slot: WeaponSlot = WEAPON_SLOT_SCENE.instantiate() as WeaponSlot
		slot.set_slot_index(i + 1)
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_weapon_grid.add_child(slot)
		_weapon_slots.append(slot)

		var hp: HardpointComponent = _hardpoints[i]
		var name_str := _get_weapon_display_name(hp)
		slot.set_weapon_name(name_str)
		slot.set_empty(not hp.has_weapon())


# ─── Event Handlers ───────────────────────────────────────────────────────────

func _on_game_mode_changed(_old_mode: String, new_mode: String) -> void:
	visible = (new_mode == "pilot")


func _on_ship_damaged(victim: Node, _attacker: Node) -> void:
	if victim == _player_ship:
		_trigger_hit_flash()


# ─── Helpers ──────────────────────────────────────────────────────────────────

func _get_weapon_display_name(hp: HardpointComponent) -> String:
	if not hp.has_weapon():
		return ""
	var model := hp.get_weapon_model()
	if model == null:
		return ""
	for child in model.get_children():
		if child is WeaponComponent:
			var wc := child as WeaponComponent
			# Convert weapon_id snake_case to display: "burst_laser" → "BURST LASER"
			return wc.weapon_id.replace("_", " ").to_upper()
	return ""


func _get_ammo_text(hp: HardpointComponent) -> String:
	if not hp.has_weapon():
		return "--"
	var model := hp.get_weapon_model()
	if model == null:
		return "--"
	for child in model.get_children():
		if child is WeaponComponent:
			var archetype := (child as WeaponComponent).archetype
			if archetype in ["energy_beam", "energy_pulse"]:
				return "\u221e"  # ∞
			return "--"          # ballistic/missile ammo deferred
	return "--"


func _make_panel(_w: float, _h: float,
		al: float, at: float, ar: float, ab: float,
		ol: float, ot: float, or_: float, ob: float) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color     = UITokens.SURFACE
	style.border_color = UITokens.GREY_20
	style.set_border_width_all(1)
	style.set_corner_radius_all(0)
	panel.add_theme_stylebox_override("panel", style)

	panel.anchor_left   = al
	panel.anchor_top    = at
	panel.anchor_right  = ar
	panel.anchor_bottom = ab
	panel.offset_left   = ol
	panel.offset_top    = ot
	panel.offset_right  = or_
	panel.offset_bottom = ob
	panel.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	return panel


func _panel_margin(panel: PanelContainer) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left",   UITokens.PANEL_PAD_W)
	m.add_theme_constant_override("margin_right",  UITokens.PANEL_PAD_W)
	m.add_theme_constant_override("margin_top",    UITokens.PANEL_PAD_H)
	m.add_theme_constant_override("margin_bottom", UITokens.PANEL_PAD_H)
	panel.add_child(m)
	return m


func _make_divider() -> HSeparator:
	var sep := HSeparator.new()
	sep.add_theme_color_override("color", UITokens.GREY_20)
	return sep


func _make_stat_readout(parent: HBoxContainer, field_name: String) -> Label:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	parent.add_child(col)

	var lbl := Label.new()
	lbl.text = field_name
	lbl.add_theme_color_override("font_color", UITokens.GREY_50)
	UITokens.apply_font_label(lbl, UITokens.SIZE_DATA_LABEL)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(lbl)

	var val := Label.new()
	val.text = "---"
	val.add_theme_color_override("font_color", UITokens.GREY_80)
	UITokens.apply_font_data(val, UITokens.SIZE_DATA_VALUE)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(val)

	return val
