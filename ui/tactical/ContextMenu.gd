extends PopupMenu
class_name TacticalContextMenu

## Right-click context menu for fleet ships. Two top-level submenus:
##   Stance — Hold Fire / Defensive / Aggressive (hidden if ship is in escort)
##   Escort — Add to escort / Remove from escort
##
## Listens to context_menu_requested. Emits stance/escort signals.

var _target_ship_id: int = 0

# Submenu instances
var _stance_menu: PopupMenu
var _escort_menu: PopupMenu

# ─── Cached services ──────────────────────────────────────────────────────
var _event_bus: Node
var _escort_queue: EscortQueue
var _player_state: Node


func _ready() -> void:
	var service_locator := Engine.get_singleton("ServiceLocator")
	_event_bus = service_locator.GetService("GameEventBus")
	_player_state = service_locator.GetService("PlayerState")

	# Build Stance submenu
	_stance_menu = PopupMenu.new()
	_stance_menu.name = "StanceMenu"
	_stance_menu.add_item("Hold Fire", 0)
	_stance_menu.add_item("Defensive", 1)
	_stance_menu.add_item("Aggressive", 2)
	_stance_menu.id_pressed.connect(_on_stance_selected)
	add_child(_stance_menu)

	# Build Escort submenu
	_escort_menu = PopupMenu.new()
	_escort_menu.name = "EscortMenu"
	# Items are populated dynamically based on queue membership
	_escort_menu.id_pressed.connect(_on_escort_selected)
	add_child(_escort_menu)

	# Add submenus to this menu
	add_submenu_item("Stance", "StanceMenu")
	add_submenu_item("Escort", "EscortMenu")

	if _event_bus:
		_event_bus.connect("context_menu_requested", _on_context_menu_requested)


func set_escort_queue(eq: EscortQueue) -> void:
	_escort_queue = eq


func _on_context_menu_requested(ship_id: int, screen_pos: Vector2) -> void:
	_target_ship_id = ship_id

	# Don't show context menu for the player's own ship (can't escort yourself)
	if _player_state:
		var player_ship: Node = _player_state.get_active_ship()
		if player_ship and player_ship.get_instance_id() == ship_id:
			# Player ship — only show stance if not in escort
			pass  # Still show the menu for stance changes

	var in_queue := false
	if _escort_queue:
		in_queue = _escort_queue.is_in_queue(ship_id)

	# Stance submenu: hidden when ship is in the escort queue
	var stance_idx := get_item_index(0)
	if stance_idx >= 0:
		# We use item index based on order — Stance is first (index 0)
		set_item_disabled(0, in_queue)

	# Escort submenu: populate dynamically
	_escort_menu.clear()
	if _player_state:
		var player_ship: Node = _player_state.get_active_ship()
		# Don't allow adding the player ship to its own escort
		if player_ship and player_ship.get_instance_id() == ship_id:
			_escort_menu.add_item("(Player ship)", -1)
			_escort_menu.set_item_disabled(0, true)
		elif in_queue:
			_escort_menu.add_item("Remove from escort", 1)
		else:
			_escort_menu.add_item("Add to escort", 0)

	# Show menu at cursor position
	position = Vector2i(int(screen_pos.x), int(screen_pos.y))
	popup()


func _on_stance_selected(id: int) -> void:
	if _target_ship_id == 0:
		return
	_event_bus.request_tactical_set_stance.emit(_target_ship_id, id)


func _on_escort_selected(id: int) -> void:
	if _target_ship_id == 0:
		return
	match id:
		0:  # Add to escort
			_event_bus.request_tactical_add_to_escort.emit(_target_ship_id)
		1:  # Remove from escort
			_event_bus.request_tactical_remove_from_escort.emit(_target_ship_id)
