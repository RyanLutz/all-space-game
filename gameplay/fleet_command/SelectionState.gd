extends Node
class_name SelectionState

## Tracks the current set of selected fleet ships (by instance id).
## Cleared on every mode transition. Prunes destroyed ships automatically.

var _selected_ids: Array[int] = []

var _event_bus: Node


func _ready() -> void:
	var service_locator := Engine.get_singleton("ServiceLocator")
	_event_bus = service_locator.GetService("GameEventBus")

	if _event_bus:
		_event_bus.connect("game_mode_changed", _on_game_mode_changed)
		_event_bus.connect("ship_destroyed", _on_ship_destroyed)


func get_selection() -> Array[int]:
	return _selected_ids.duplicate()


func is_selected(ship_id: int) -> bool:
	return ship_id in _selected_ids


func select_single(ship_id: int) -> void:
	_selected_ids = [ship_id]
	_emit_changed()


func toggle(ship_id: int) -> void:
	if ship_id in _selected_ids:
		_selected_ids.erase(ship_id)
	else:
		_selected_ids.append(ship_id)
	_emit_changed()


func select_multiple(ship_ids: Array[int]) -> void:
	_selected_ids = ship_ids.duplicate()
	_emit_changed()


func clear() -> void:
	if _selected_ids.is_empty():
		return
	_selected_ids.clear()
	_emit_changed()


func _emit_changed() -> void:
	_event_bus.tactical_selection_changed.emit(_selected_ids.duplicate())


func _on_game_mode_changed(_old_mode: String, _new_mode: String) -> void:
	clear()


func _on_ship_destroyed(ship: Node, _pos: Vector3, _faction: String) -> void:
	var id := ship.get_instance_id()
	if id in _selected_ids:
		_selected_ids.erase(id)
		_emit_changed()
