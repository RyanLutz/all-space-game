extends CanvasLayer
class_name LoadoutUI

var _ship: Ship = null
var _station: Node2D = null
var _selected_slot_id: String = ""
var _selected_slot_type: String = ""   # "weapon" or "module"
var _selected_slot_filter: String = "" # hardpoint group for weapons, module type for modules

var _event_bus: Node
var _content_registry: Node

# Built once in _ready(); repopulated on each dock.
var _slots_container: VBoxContainer
var _items_container: VBoxContainer
var _selected_label: Label
var _ship_name_label: Label

# Slot button map for quick refresh: slot_id → Button
var _slot_buttons: Dictionary = {}

# Runtime snapshot of what's currently equipped
var _current_weapons: Dictionary = {}  # hardpoint_id → weapon_id
var _current_modules: Dictionary = {}  # slot_id → module_id


func _ready() -> void:
	layer = 5
	visible = false

	_event_bus = ServiceLocator.GetService("GameEventBus") as Node
	_content_registry = ServiceLocator.GetService("ContentRegistry") as Node

	if _event_bus == null:
		push_error("LoadoutUI: GameEventBus not found")
		return

	_event_bus.connect("dock_complete", _on_dock_complete)
	_event_bus.connect("undock_requested", _on_undock_requested)

	_build_base_ui()


func _build_base_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.72)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(880.0, 560.0)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	add_child(panel)

	var margin := MarginContainer.new()
	for side in ["top", "bottom", "left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# Header row
	var header := HBoxContainer.new()
	vbox.add_child(header)

	_ship_name_label = Label.new()
	_ship_name_label.text = "LOADOUT"
	_ship_name_label.add_theme_font_size_override("font_size", 18)
	header.add_child(_ship_name_label)

	var header_spacer := Control.new()
	header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(header_spacer)

	var undock_btn := Button.new()
	undock_btn.text = "UNDOCK  [F]"
	undock_btn.pressed.connect(_on_undock_pressed)
	header.add_child(undock_btn)

	vbox.add_child(HSeparator.new())

	# Content area: slots on left, item list on right
	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	vbox.add_child(content)

	var left_scroll := ScrollContainer.new()
	left_scroll.custom_minimum_size = Vector2(380.0, 0.0)
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(left_scroll)

	_slots_container = VBoxContainer.new()
	_slots_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slots_container.add_theme_constant_override("separation", 4)
	left_scroll.add_child(_slots_container)

	content.add_child(VSeparator.new())

	var right_vbox := VBoxContainer.new()
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_theme_constant_override("separation", 6)
	content.add_child(right_vbox)

	_selected_label = Label.new()
	_selected_label.text = "← Select a slot to see compatible items"
	right_vbox.add_child(_selected_label)

	right_vbox.add_child(HSeparator.new())

	var right_scroll := ScrollContainer.new()
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(right_scroll)

	_items_container = VBoxContainer.new()
	_items_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_items_container.add_theme_constant_override("separation", 4)
	right_scroll.add_child(_items_container)


# --- Dock / Undock ---

func _on_dock_complete(ship: Node2D, station_node: Node2D) -> void:
	_ship = ship as Ship
	_station = station_node

	if _ship == null:
		push_error("LoadoutUI: dock_complete ship is not a Ship node")
		return

	_snapshot_current_loadout()
	_ship_name_label.text = "LOADOUT — %s" % _ship._pending_ship_data.get("display_name", "Ship")
	_populate_slots()
	_clear_items()
	_selected_slot_id = ""
	if _selected_label != null:
		_selected_label.text = "← Select a slot to see compatible items"

	visible = true


func _on_undock_requested(ship: Node2D) -> void:
	if ship != _ship:
		return
	visible = false
	_ship = null
	_station = null
	_selected_slot_id = ""
	_clear_items()


func _on_undock_pressed() -> void:
	if _ship == null:
		return
	_event_bus.emit_signal("undock_requested", _ship as Node2D)


# --- Slot population ---

func _snapshot_current_loadout() -> void:
	_current_weapons.clear()
	_current_modules.clear()

	if _ship._weapon_component != null:
		for node in _ship._weapon_component.get_all_hardpoints():
			var hp := node as HardpointComponent
			if hp != null:
				_current_weapons[hp.hardpoint_id] = hp.weapon_data.get("id",
						hp.weapon_data.get("_id", ""))

	_current_modules = _ship._active_modules.duplicate()


func _populate_slots() -> void:
	for child in _slots_container.get_children():
		child.queue_free()
	_slot_buttons.clear()

	var hardpoints: Array = _ship._pending_ship_data.get("hardpoints", [])
	var module_slots: Array = _ship._pending_ship_data.get("module_slots", [])

	if not hardpoints.is_empty():
		var section := _make_section_label("WEAPONS")
		_slots_container.add_child(section)

		for hp_def in hardpoints:
			var hp_id: String = hp_def.get("id", "")
			var groups: Array = hp_def.get("groups", ["primary"])
			var group_str: String = ", ".join(groups)
			var equipped_name := _weapon_display_name(_current_weapons.get(hp_id, ""))

			var btn := _make_slot_button(
				"[%s]  (%s)\n  %s" % [hp_id, group_str, equipped_name],
				hp_id, "weapon", groups[0] if not groups.is_empty() else "primary"
			)
			_slots_container.add_child(btn)
			_slot_buttons[hp_id] = btn

	if not module_slots.is_empty():
		_slots_container.add_child(HSeparator.new())
		_slots_container.add_child(_make_section_label("MODULES"))

		for slot_def in module_slots:
			var slot_id: String = slot_def.get("id", "")
			var slot_type: String = slot_def.get("type", "")
			var equipped_name := _module_display_name(_current_modules.get(slot_id, ""))

			var btn := _make_slot_button(
				"[%s]  (%s)\n  %s" % [slot_id, slot_type, equipped_name],
				slot_id, "module", slot_type
			)
			_slots_container.add_child(btn)
			_slot_buttons[slot_id] = btn


func _make_section_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 14)
	return lbl


func _make_slot_button(label_text: String, slot_id: String,
		slot_type: String, slot_filter: String) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0.0, 52.0)
	btn.pressed.connect(_on_slot_pressed.bind(slot_id, slot_type, slot_filter))
	return btn


# --- Slot selection ---

func _on_slot_pressed(slot_id: String, slot_type: String, slot_filter: String) -> void:
	_selected_slot_id = slot_id
	_selected_slot_type = slot_type
	_selected_slot_filter = slot_filter

	for sid in _slot_buttons:
		_slot_buttons[sid].modulate = Color.WHITE
	if _slot_buttons.has(slot_id):
		_slot_buttons[slot_id].modulate = Color(0.45, 0.85, 1.0)

	_populate_items(slot_type, slot_filter, slot_id)


# --- Item list ---

func _populate_items(slot_type: String, slot_filter: String, slot_id: String) -> void:
	_clear_items()

	if _content_registry == null:
		return

	if slot_type == "weapon":
		var hp_size := "small"
		for hp_def in _ship._pending_ship_data.get("hardpoints", []):
			if hp_def.get("id", "") == slot_id:
				hp_size = hp_def.get("size", "small")
				break
		_selected_label.text = "WEAPONS  (slot: %s  |  max size: %s)" % [slot_id, hp_size]

		for weapon_id in _content_registry.weapons.keys():
			var wdata: Dictionary = _content_registry.get_weapon(weapon_id)
			if not _weapon_size_fits(wdata.get("size", "small"), hp_size):
				continue
			var desc := "%s  [%s]" % [wdata.get("display_name", weapon_id),
					wdata.get("archetype", "")]
			_add_item_button(weapon_id, desc, slot_type)

	elif slot_type == "module":
		_selected_label.text = "MODULES  (slot: %s  |  type: %s)" % [slot_id, slot_filter]

		var empty_btn := Button.new()
		empty_btn.text = "(remove module)"
		empty_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		empty_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		empty_btn.custom_minimum_size = Vector2(0.0, 40.0)
		empty_btn.pressed.connect(_on_item_selected.bind("", slot_type))
		_items_container.add_child(empty_btn)

		for module_id in _content_registry.modules.keys():
			var mdata: Dictionary = _content_registry.get_module(module_id)
			if mdata.get("type", "") != slot_filter:
				continue
			var desc := "%s" % mdata.get("display_name", module_id)
			_add_item_button(module_id, desc, slot_type)


func _add_item_button(item_id: String, desc: String, slot_type: String) -> void:
	var btn := Button.new()
	btn.text = desc
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0.0, 40.0)
	btn.pressed.connect(_on_item_selected.bind(item_id, slot_type))
	_items_container.add_child(btn)


func _clear_items() -> void:
	for child in _items_container.get_children():
		child.queue_free()


# --- Equip ---

func _on_item_selected(item_id: String, slot_type: String) -> void:
	if _selected_slot_id.is_empty():
		return

	if slot_type == "weapon":
		_equip_weapon(_selected_slot_id, item_id)
		_current_weapons[_selected_slot_id] = item_id
	elif slot_type == "module":
		_equip_module(_selected_slot_id, item_id)
		_current_modules[_selected_slot_id] = item_id

	_refresh_slot_button(_selected_slot_id, slot_type, item_id)

	if _event_bus != null and _ship != null:
		_event_bus.emit_signal("loadout_changed", _ship as Node2D, _selected_slot_id, item_id)


func _equip_weapon(hardpoint_id: String, weapon_id: String) -> void:
	if _ship == null or _ship._weapon_component == null or weapon_id.is_empty():
		return
	var weapon_data: Dictionary = _content_registry.get_weapon(weapon_id)
	if weapon_data.is_empty():
		return
	_ship._weapon_component.set_hardpoint_weapon(hardpoint_id, weapon_data)


func _equip_module(slot_id: String, module_id: String) -> void:
	if _ship == null:
		return
	if module_id.is_empty():
		_ship._active_modules.erase(slot_id)
	else:
		_ship._active_modules[slot_id] = module_id
	_ship.apply_module_stats(false)


func _refresh_slot_button(slot_id: String, slot_type: String, item_id: String) -> void:
	if not _slot_buttons.has(slot_id):
		return
	var equipped_name: String
	if slot_type == "weapon":
		equipped_name = _weapon_display_name(item_id)
	else:
		equipped_name = _module_display_name(item_id)

	var btn: Button = _slot_buttons[slot_id]
	var lines := btn.text.split("\n")
	if lines.size() >= 2:
		lines[1] = "  %s" % equipped_name
		btn.text = "\n".join(lines)


# --- Helpers ---

func _weapon_display_name(weapon_id: String) -> String:
	if weapon_id.is_empty() or _content_registry == null:
		return "(empty)"
	var data: Dictionary = _content_registry.get_weapon(weapon_id)
	return data.get("display_name", weapon_id) if not data.is_empty() else weapon_id


func _module_display_name(module_id: String) -> String:
	if module_id.is_empty() or _content_registry == null:
		return "(empty)"
	var data: Dictionary = _content_registry.get_module(module_id)
	return data.get("display_name", module_id) if not data.is_empty() else module_id


func _weapon_size_fits(weapon_size: String, slot_size: String) -> bool:
	const SIZE_ORDER := ["small", "medium", "large"]
	var w_rank := SIZE_ORDER.find(weapon_size)
	var s_rank := SIZE_ORDER.find(slot_size)
	if w_rank < 0 or s_rank < 0:
		return true
	return w_rank <= s_rank
