extends Node
class_name FormationController

## Pushes formation slot destinations for escort queue members in Pilot mode.
##
## Runs on a timer (~0.25s). Each tick reads the escort queue, skips ships
## that are away on orders, and emits request_formation_destination for each
## active slot. Slot destination = player ship position + offset rotated by
## player ship's yaw.
##
## The formation definition is loaded from JSON at startup.

# ─── Formation data ────────────────────────────────────────────────────────
var _formation_def: Dictionary = {}
var _slots: Array = []

# ─── Timer ─────────────────────────────────────────────────────────────────
var _tick_timer: Timer
const TICK_INTERVAL: float = 0.25

# ─── State ─────────────────────────────────────────────────────────────────
var _active: bool = true    # active in pilot mode, halted in tactical

# ─── Sibling references (set via setter, same pattern as TacticalInputHandler) ─
var _escort_queue: EscortQueue

# ─── Cached services ──────────────────────────────────────────────────────
var _event_bus: Node
var _perf: Node
var _player_state: Node


func _ready() -> void:
	var service_locator := Engine.get_singleton("ServiceLocator")
	_event_bus = service_locator.GetService("GameEventBus")
	_perf = service_locator.GetService("PerformanceMonitor")
	_player_state = service_locator.GetService("PlayerState")

	if _event_bus:
		_event_bus.connect("game_mode_changed", _on_game_mode_changed)

	_load_default_formation()

	# Set up tick timer
	_tick_timer = Timer.new()
	_tick_timer.wait_time = TICK_INTERVAL
	_tick_timer.autostart = true
	_tick_timer.timeout.connect(_formation_tick)
	add_child(_tick_timer)


func set_escort_queue(eq: EscortQueue) -> void:
	_escort_queue = eq


# ─── Formation Loading ────────────────────────────────────────────────────

func _load_default_formation() -> void:
	var path := "res://content/formations/v_wing/formation.json"
	if not FileAccess.file_exists(path):
		push_error("[FormationController] Default formation not found: %s" % path)
		return

	var file := FileAccess.open(path, FileAccess.READ)
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()

	if err != OK:
		push_error("[FormationController] Failed to parse formation JSON: %s" % json.get_error_message())
		return

	_formation_def = json.data
	_slots = _formation_def.get("slots", [])

	if _slots.is_empty():
		push_warning("[FormationController] Formation has no slots")
	else:
		print("[FormationController] Loaded formation '%s' with %d slots" % [
			_formation_def.get("display_name", "Unknown"), _slots.size()])


# ─── Mode Handling ────────────────────────────────────────────────────────

func _on_game_mode_changed(_old_mode: String, new_mode: String) -> void:
	_active = (new_mode == "pilot")


# ─── Formation Tick ───────────────────────────────────────────────────────

func _formation_tick() -> void:
	if not _active:
		return
	if _escort_queue == null:
		return

	_perf.begin("FleetCommand.formation_tick")

	var player_ship := _player_state.get_active_ship() as Node3D
	if player_ship == null:
		_perf.end("FleetCommand.formation_tick")
		return

	var queue := _escort_queue.get_queue()
	var player_pos := player_ship.global_position
	player_pos.y = 0.0

	# Player ship's yaw rotation for offset transformation
	var player_yaw := -player_ship.transform.basis.z
	player_yaw.y = 0.0
	if player_yaw.length() < 0.001:
		player_yaw = Vector3.FORWARD
	player_yaw = player_yaw.normalized()

	# Build rotation basis from player's forward direction
	var forward := player_yaw
	var right := Vector3.UP.cross(forward).normalized()

	for i in queue.size():
		if i >= _slots.size():
			break    # more ships than slots; surplus ships idle

		var ship_id: int = queue[i]
		if _escort_queue.is_away(ship_id):
			continue    # slot reserved but empty — no destination push

		var ship := instance_from_id(ship_id) as Node3D
		if ship == null or not is_instance_valid(ship):
			continue

		var slot_def: Dictionary = _slots[i]
		var offset_arr: Array = slot_def.get("offset", [0.0, 0.0, 0.0])
		var local_offset := Vector3(offset_arr[0], 0.0, offset_arr[2])

		# Transform local offset by player's facing direction
		# local_offset.x = right, local_offset.z = forward (positive z = behind = +forward in Godot terms)
		var world_offset := right * local_offset.x + forward * local_offset.z
		var destination := player_pos + world_offset
		destination.y = 0.0

		_event_bus.request_formation_destination.emit(ship_id, destination)

	_perf.end("FleetCommand.formation_tick")
