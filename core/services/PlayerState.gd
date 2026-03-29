extends Node
class_name PlayerState

# PlayerState — single source of truth for the currently piloted ship.
# Any system that needs "the player ship" queries this; nothing holds a hardcoded reference.
# Cross-system notification goes through GameEventBus (player_ship_changed signal).

var active_ship: Node = null

var _event_bus: Node


func _ready() -> void:
	_event_bus = ServiceLocator.GetService("GameEventBus") as Node


func set_active_ship(ship: Node) -> void:
	active_ship = ship
	if _event_bus:
		_event_bus.player_ship_changed.emit(ship)


func get_active_ship() -> Node:
	return active_ship
