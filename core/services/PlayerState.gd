extends Node
class_name PlayerState

## Tracks the active player ship. Camera, input, and UI all listen to
## player_ship_changed and update accordingly — no hardcoded ship references.

var active_ship: RigidBody3D = null

var _event_bus: Node

func _ready() -> void:
	var service_locator := Engine.get_singleton("ServiceLocator")
	_event_bus = service_locator.GetService("GameEventBus")


func set_active_ship(ship: RigidBody3D) -> void:
	active_ship = ship
	if _event_bus:
		_event_bus.emit_signal("player_ship_changed", ship)
	print("[PlayerState] Active ship set: %s" % (ship.display_name if ship else "null"))


func get_active_ship() -> RigidBody3D:
	return active_ship


func clear_active_ship() -> void:
	active_ship = null
	if _event_bus:
		_event_bus.emit_signal("player_ship_changed", null)
