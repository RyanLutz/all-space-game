extends Node
class_name TacticalInputHandler

## Handles mouse and keyboard input in Tactical mode: click-select, shift-click
## toggle, drag-box select, right-click dispatch, and Stop key.
## Inactive in Pilot mode.

var _active: bool = false
var _dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _drag_threshold: float = 8.0  # pixels before a click becomes a drag

var _selection_state: SelectionState
var _event_bus: Node
var _perf: Node


func _ready() -> void:
	var service_locator := Engine.get_singleton("ServiceLocator")
	_event_bus = service_locator.GetService("GameEventBus")
	_perf = service_locator.GetService("PerformanceMonitor")

	if _event_bus:
		_event_bus.connect("game_mode_changed", _on_game_mode_changed)


func set_selection_state(state: SelectionState) -> void:
	_selection_state = state


func _on_game_mode_changed(_old_mode: String, new_mode: String) -> void:
	_active = (new_mode == "tactical")
	_dragging = false


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return

	# Stop key
	if event.is_action_pressed("tactical_stop"):
		_on_stop_key()
		return

	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion and _dragging:
		# Drag is tracked but visual selection box is a UI concern (deferred)
		pass


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_start = event.position
			_dragging = false
		else:
			# Release — was it a click or a drag?
			var drag_distance := event.position.distance_to(_drag_start)
			if drag_distance < _drag_threshold:
				_on_left_click(event.position)
			else:
				_on_drag_select(_drag_start, event.position)
			_dragging = false

	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_on_right_click(event.position)


func _on_left_click(screen_pos: Vector2) -> void:
	var hit_ship := _raycast_fleet_ship(screen_pos)
	if hit_ship != null:
		var ship_id := hit_ship.get_instance_id()
		if Input.is_key_pressed(KEY_SHIFT):
			_selection_state.toggle(ship_id)
		else:
			_selection_state.select_single(ship_id)
	else:
		# Click on empty space — deselect
		if not Input.is_key_pressed(KEY_SHIFT):
			_selection_state.clear()


func _on_drag_select(start: Vector2, end: Vector2) -> void:
	var rect := Rect2(start, end - start).abs()
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	var selected: Array[int] = []
	for ship in get_tree().get_nodes_in_group("player_fleet"):
		var screen_point := camera.unproject_position(ship.global_position)
		if rect.has_point(screen_point):
			selected.append(ship.get_instance_id())

	if selected.is_empty() and not Input.is_key_pressed(KEY_SHIFT):
		_selection_state.clear()
	elif Input.is_key_pressed(KEY_SHIFT):
		# Shift-drag adds to existing selection
		var current := _selection_state.get_selection()
		for id in selected:
			if id not in current:
				current.append(id)
		_selection_state.select_multiple(current)
	else:
		_selection_state.select_multiple(selected)


func _on_right_click(screen_pos: Vector2) -> void:
	_perf.begin("FleetCommand.right_click_dispatch")

	var camera := get_viewport().get_camera_3d()
	if camera == null:
		_perf.end("FleetCommand.right_click_dispatch")
		return

	var ray_origin := camera.project_ray_origin(screen_pos)
	var ray_dir := camera.project_ray_normal(screen_pos)

	# Physics raycast to classify target
	var world: World3D = camera.get_world_3d()
	var space: PhysicsDirectSpaceState3D = world.direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		ray_origin, ray_origin + ray_dir * 10000.0)
	var hit: Dictionary = space.intersect_ray(query)

	if not hit.is_empty():
		var node: Node = hit.collider
		if node.is_in_group("player_fleet"):
			_event_bus.context_menu_requested.emit(
				node.get_instance_id(), screen_pos)
			_perf.end("FleetCommand.right_click_dispatch")
			return
		if node.is_in_group("enemies"):
			_dispatch_order("attack", node.get_instance_id())
			_perf.end("FleetCommand.right_click_dispatch")
			return
		if node.is_in_group("asteroids"):
			_dispatch_order("mine", node.get_instance_id())
			_perf.end("FleetCommand.right_click_dispatch")
			return

	# No target or unclassified — empty-space move order
	var destination := _ray_plane_intersect(ray_origin, ray_dir, 0.0)
	_dispatch_move_order(destination)
	_perf.end("FleetCommand.right_click_dispatch")


func _dispatch_order(order_type: String, target_id: int) -> void:
	if _selection_state.get_selection().is_empty():
		return
	var queue_mode := "append" if Input.is_key_pressed(KEY_SHIFT) else "replace"
	var ship_ids := _selection_state.get_selection()
	match order_type:
		"attack":
			_event_bus.request_tactical_attack.emit(ship_ids, target_id, queue_mode)
		"mine":
			_event_bus.request_tactical_mine.emit(ship_ids, target_id, queue_mode)


func _dispatch_move_order(destination: Vector3) -> void:
	if _selection_state.get_selection().is_empty():
		return
	var queue_mode := "append" if Input.is_key_pressed(KEY_SHIFT) else "replace"
	_event_bus.request_tactical_move.emit(
		_selection_state.get_selection(), destination, queue_mode)


func _on_stop_key() -> void:
	if _selection_state.get_selection().is_empty():
		return
	_event_bus.request_tactical_stop.emit(_selection_state.get_selection())


func _raycast_fleet_ship(screen_pos: Vector2) -> Node:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null

	var ray_origin := camera.project_ray_origin(screen_pos)
	var ray_dir := camera.project_ray_normal(screen_pos)

	var world: World3D = camera.get_world_3d()
	var space: PhysicsDirectSpaceState3D = world.direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		ray_origin, ray_origin + ray_dir * 10000.0)
	var hit: Dictionary = space.intersect_ray(query)

	if not hit.is_empty():
		var node: Node = hit.collider
		if node.is_in_group("player_fleet"):
			return node
	return null


func _ray_plane_intersect(origin: Vector3, direction: Vector3, plane_y: float) -> Vector3:
	if absf(direction.y) < 0.0001:
		return Vector3(origin.x, plane_y, origin.z)
	var t := (plane_y - origin.y) / direction.y
	return origin + direction * t
