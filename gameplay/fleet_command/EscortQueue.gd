extends Node
class_name EscortQueue

## Ordered list of escort ship ids. Ships in the queue fly in formation with the
## player in Pilot mode. Queue-shared stance overrides per-ship stance.
##
## Slot index is always _queue.find(ship_id). Removing a ship compacts indices.
## A ship "away on orders" retains its slot position (reserved but empty).

enum Stance { HOLD_FIRE, DEFENSIVE, AGGRESSIVE }

# ─── State ─────────────────────────────────────────────────────────────────
var _queue: Array[int] = []
var _away_on_orders: Dictionary = {}    # { ship_instance_id: bool }
var _stance: Stance = Stance.DEFENSIVE

# ─── Cached services ──────────────────────────────────────────────────────
var _event_bus: Node
var _perf: Node


func _ready() -> void:
	var service_locator := Engine.get_singleton("ServiceLocator")
	_event_bus = service_locator.GetService("GameEventBus")
	_perf = service_locator.GetService("PerformanceMonitor")

	if _event_bus:
		# Queue management
		_event_bus.connect("request_tactical_add_to_escort", _on_request_add_to_escort)
		_event_bus.connect("request_tactical_remove_from_escort", _on_request_remove_from_escort)
		_event_bus.connect("request_tactical_set_escort_stance", _on_request_set_escort_stance)

		# Track "away on orders" — mark when queue members receive orders
		_event_bus.connect("request_tactical_move", _on_tactical_order_issued)
		_event_bus.connect("request_tactical_attack", _on_tactical_attack_issued)
		_event_bus.connect("request_tactical_mine", _on_tactical_order_issued)

		# Mark returned when order completes or is stopped
		_event_bus.connect("request_tactical_stop", _on_tactical_stop)
		_event_bus.connect("navigation_order_completed", _on_order_completed)

		# Prune destroyed ships
		_event_bus.connect("ship_destroyed", _on_ship_destroyed)


# ─── Public Getters ────────────────────────────────────────────────────────

func get_queue() -> Array[int]:
	return _queue.duplicate()


func is_in_queue(ship_id: int) -> bool:
	return ship_id in _queue


func slot_index_of(ship_id: int) -> int:
	return _queue.find(ship_id)


func is_away(ship_id: int) -> bool:
	return _away_on_orders.get(ship_id, false)


func get_stance() -> Stance:
	return _stance


# ─── Queue Operations ─────────────────────────────────────────────────────

func _on_request_add_to_escort(ship_id: int) -> void:
	if ship_id in _queue:
		return
	_perf.begin("FleetCommand.escort_queue_op")

	# Cancel any active orders — escort takes priority
	_event_bus.request_tactical_stop.emit([ship_id])

	_queue.append(ship_id)
	_away_on_orders[ship_id] = false

	# Ship adopts queue stance — clear per-ship stance via signal
	_event_bus.request_tactical_set_stance.emit(ship_id, -1)  # -1 = clear

	_event_bus.escort_queue_changed.emit(_queue.duplicate())
	_perf.end("FleetCommand.escort_queue_op")


func _on_request_remove_from_escort(ship_id: int) -> void:
	if ship_id not in _queue:
		return
	_perf.begin("FleetCommand.escort_queue_op")

	_queue.erase(ship_id)
	_away_on_orders.erase(ship_id)

	# Per-ship stance resets to DEFENSIVE when leaving the queue
	_event_bus.request_tactical_set_stance.emit(ship_id, Stance.DEFENSIVE)

	_event_bus.escort_queue_changed.emit(_queue.duplicate())
	_perf.end("FleetCommand.escort_queue_op")


func _on_request_set_escort_stance(stance: int) -> void:
	_perf.begin("FleetCommand.escort_queue_op")
	_stance = stance as Stance
	_event_bus.escort_stance_changed.emit(_stance)
	_perf.end("FleetCommand.escort_queue_op")


# ─── Away-on-Orders Tracking ──────────────────────────────────────────────

func _on_tactical_order_issued(ship_ids: Array, _dest_or_id, _queue_mode: String) -> void:
	for id in ship_ids:
		if id in _queue:
			_away_on_orders[id] = true


func _on_tactical_attack_issued(ship_ids: Array, _target_id: int, _queue_mode: String) -> void:
	for id in ship_ids:
		if id in _queue:
			_away_on_orders[id] = true


func _on_tactical_stop(ship_ids: Array) -> void:
	for id in ship_ids:
		if id in _queue:
			_away_on_orders[id] = false


func _on_order_completed(ship_id: int) -> void:
	if ship_id in _queue:
		_away_on_orders[ship_id] = false


# ─── Cleanup ──────────────────────────────────────────────────────────────

func _on_ship_destroyed(ship: Node, _pos: Vector3, _faction: String) -> void:
	var ship_id := ship.get_instance_id()
	if ship_id in _queue:
		_queue.erase(ship_id)
		_away_on_orders.erase(ship_id)
		_event_bus.escort_queue_changed.emit(_queue.duplicate())
