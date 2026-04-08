extends StaticBody2D
class_name Station

@export var station_id: String = "station_01"
@export var display_name: String = "Station"

var _nearby_player: Node2D = null
var _docked_ship: Node2D = null
var _event_bus: Node


func _ready() -> void:
	_event_bus = ServiceLocator.GetService("GameEventBus") as Node
	if _event_bus == null:
		push_error("Station '%s': GameEventBus not found" % station_id)
		return
	_event_bus.connect("dock_requested", _on_dock_requested)
	_event_bus.connect("undock_requested", _on_undock_requested)

	# Connect dock zone body signals to detect player proximity.
	var dock_zone := get_node_or_null("DockZone") as Area2D
	if dock_zone != null:
		dock_zone.connect("body_entered", _on_dock_zone_body_entered)
		dock_zone.connect("body_exited", _on_dock_zone_body_exited)
	else:
		push_error("Station '%s': DockZone Area2D child not found" % station_id)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("dock") and _nearby_player != null and _docked_ship == null:
		_event_bus.emit_signal("dock_requested", _nearby_player, self)


func _on_dock_zone_body_entered(body: Node) -> void:
	if body is Ship and (body as Ship).is_player_controlled:
		_nearby_player = body


func _on_dock_zone_body_exited(body: Node) -> void:
	if body == _nearby_player:
		_nearby_player = null


func _on_dock_requested(ship: Node2D, station: Node2D) -> void:
	if station != self:
		return
	if _docked_ship != null:
		return
	_docked_ship = ship
	# Disable all processing on the ship and its children (WeaponComponent, AIController, etc.)
	ship.process_mode = Node.PROCESS_MODE_DISABLED
	_event_bus.emit_signal("dock_complete", ship, self)


func _on_undock_requested(ship: Node2D) -> void:
	if ship != _docked_ship:
		return
	_docked_ship = null
	ship.process_mode = Node.PROCESS_MODE_INHERIT
