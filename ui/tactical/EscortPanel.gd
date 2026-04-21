extends PanelContainer
class_name EscortPanel

## Displays the escort queue and provides a stance selector for the queue.
## Visible only when the escort queue is non-empty.
##
## Stance buttons emit request_tactical_set_escort_stance.
## Queue list shows ship names (resolved from instance ids).

var _stance_buttons: Array[Button] = []
var _ship_list: VBoxContainer
var _current_stance: int = 1  # DEFENSIVE

# ─── Cached services ──────────────────────────────────────────────────────
var _event_bus: Node


func _ready() -> void:
	var service_locator := Engine.get_singleton("ServiceLocator")
	_event_bus = service_locator.GetService("GameEventBus")

	visible = false
	_build_ui()

	if _event_bus:
		_event_bus.connect("escort_queue_changed", _on_escort_queue_changed)
		_event_bus.connect("escort_stance_changed", _on_escort_stance_changed)


func _build_ui() -> void:
	custom_minimum_size = Vector2(200, 100)

	var root := VBoxContainer.new()
	root.name = "Root"
	add_child(root)

	# Title
	var title := Label.new()
	title.text = "Escort Queue"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	# Stance selector
	var stance_row := HBoxContainer.new()
	stance_row.name = "StanceRow"
	root.add_child(stance_row)

	var stance_label := Label.new()
	stance_label.text = "Stance:"
	stance_row.add_child(stance_label)

	var stance_names := ["Hold", "Def", "Agg"]
	for i in stance_names.size():
		var btn := Button.new()
		btn.text = stance_names[i]
		btn.toggle_mode = true
		btn.button_pressed = (i == _current_stance)
		btn.pressed.connect(_on_stance_button_pressed.bind(i))
		stance_row.add_child(btn)
		_stance_buttons.append(btn)

	# Separator
	var sep := HSeparator.new()
	root.add_child(sep)

	# Ship list
	_ship_list = VBoxContainer.new()
	_ship_list.name = "ShipList"
	root.add_child(_ship_list)


func _on_stance_button_pressed(stance: int) -> void:
	_event_bus.request_tactical_set_escort_stance.emit(stance)


func _on_escort_queue_changed(ship_ids: Array) -> void:
	visible = not ship_ids.is_empty()

	# Rebuild ship list
	for child in _ship_list.get_children():
		child.queue_free()

	for i in ship_ids.size():
		var ship_id: int = ship_ids[i]
		var ship := instance_from_id(ship_id) as Node
		var label := Label.new()
		if ship and is_instance_valid(ship) and "display_name" in ship:
			label.text = "%d. %s" % [i + 1, ship.display_name]
		else:
			label.text = "%d. Ship #%d" % [i + 1, ship_id]
		_ship_list.add_child(label)


func _on_escort_stance_changed(stance: int) -> void:
	_current_stance = stance
	for i in _stance_buttons.size():
		_stance_buttons[i].button_pressed = (i == stance)
