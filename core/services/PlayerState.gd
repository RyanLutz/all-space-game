extends Node

# PlayerState — tracks the currently piloted ship.
# Any system that needs to know "who is the player" queries this service.
# Registered with ServiceLocator as "PlayerState".

var active_ship: Node = null

var _event_bus: Node


func _ready() -> void:
	_event_bus = ServiceLocator.GetService("GameEventBus") as Node
	ServiceLocator.Register("PlayerState", self)


## Set the active player ship and broadcast the change.
func set_active_ship(ship: Node) -> void:
	active_ship = ship
	if _event_bus != null:
		_event_bus.emit_signal("player_ship_changed", ship)


## Returns the currently piloted ship, or null if none is set.
func get_active_ship() -> Node:
	return active_ship
