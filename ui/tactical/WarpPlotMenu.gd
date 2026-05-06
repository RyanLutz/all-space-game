extends PopupMenu
class_name WarpPlotMenu

## Right-click context menu for warp destination plotting.
## Shown when player right-clicks empty space at camera height > threshold.
##
## Items:
##   "Plot Warp Course" — emits GameEventBus.warp_destination_plotted(destination)
##   "Cancel"           — closes menu, does nothing

var _destination: Vector3 = Vector3.ZERO
var _event_bus: Node = null


func _ready() -> void:
	var service_locator := Engine.get_singleton("ServiceLocator")
	if service_locator:
		_event_bus = service_locator.GetService("GameEventBus")

	add_item("Plot Warp Course", 0)
	add_item("Cancel", 1)
	id_pressed.connect(_on_id_pressed)


func show_at(screen_pos: Vector2, world_destination: Vector3) -> void:
	_destination = world_destination
	position = Vector2i(int(screen_pos.x), int(screen_pos.y))
	popup()


func _on_id_pressed(id: int) -> void:
	hide()
	match id:
		0:  # Plot Warp Course
			if _event_bus:
				_event_bus.warp_destination_plotted.emit(_destination)
		1:  # Cancel
			pass
