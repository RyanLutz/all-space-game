extends Node
class_name StanceController

## Per-ship stance for non-escort fleet ships. Ships in the escort queue get
## their stance from EscortQueue (cached here via signals to avoid direct refs).
##
## AIController calls get_effective_stance() — the single call site for stance.
## StanceController also handles Defensive fan-out: when a queue member is
## damaged and queue stance is DEFENSIVE, all queue members attack the aggressor.

enum Stance { HOLD_FIRE, DEFENSIVE, AGGRESSIVE }

const DEFAULT_STANCE := Stance.DEFENSIVE

# ─── Per-ship stance (non-escort ships) ────────────────────────────────────
var _stances: Dictionary = {}    # { ship_instance_id: Stance }

# ─── Cached escort state (from signals — no direct EscortQueue reference) ─
var _escort_ship_ids: Array[int] = []
var _escort_stance: Stance = Stance.DEFENSIVE

# ─── Cached services ──────────────────────────────────────────────────────
var _event_bus: Node
var _perf: Node


func _ready() -> void:
	var service_locator := Engine.get_singleton("ServiceLocator")
	_event_bus = service_locator.GetService("GameEventBus")
	_perf = service_locator.GetService("PerformanceMonitor")

	if _event_bus:
		# Per-ship stance changes
		_event_bus.connect("request_tactical_set_stance", _on_request_set_stance)

		# Cache escort membership and stance
		_event_bus.connect("escort_queue_changed", _on_escort_queue_changed)
		_event_bus.connect("escort_stance_changed", _on_escort_stance_changed)

		# Defensive fan-out
		_event_bus.connect("ship_damaged", _on_ship_damaged)

		# Cleanup
		_event_bus.connect("ship_destroyed", _on_ship_destroyed)


# ─── Public API (single call site for AIController) ───────────────────────

func get_effective_stance(ship_id: int) -> int:
	if ship_id in _escort_ship_ids:
		return _escort_stance
	return _stances.get(ship_id, DEFAULT_STANCE)


# ─── Signal Handlers ──────────────────────────────────────────────────────

func _on_request_set_stance(ship_id: int, stance: int) -> void:
	if stance == -1:
		# Clear per-ship stance (ship joining escort queue)
		_stances.erase(ship_id)
		return
	_stances[ship_id] = stance as Stance


func _on_escort_queue_changed(ship_ids: Array) -> void:
	_escort_ship_ids.clear()
	for id in ship_ids:
		_escort_ship_ids.append(id as int)


func _on_escort_stance_changed(stance: int) -> void:
	_escort_stance = stance as Stance


# ─── Defensive Fan-Out ────────────────────────────────────────────────────

func _on_ship_damaged(victim: Node, attacker: Node) -> void:
	_perf.begin("FleetCommand.stance_response")

	if attacker == null:
		_perf.end("FleetCommand.stance_response")
		return
	if not victim.is_in_group("player_fleet"):
		_perf.end("FleetCommand.stance_response")
		return

	var victim_id := victim.get_instance_id()

	# Defensive fan-out only applies to escort queue members
	if victim_id not in _escort_ship_ids:
		_perf.end("FleetCommand.stance_response")
		return
	if _escort_stance != Stance.DEFENSIVE:
		_perf.end("FleetCommand.stance_response")
		return

	var attacker_id := attacker.get_instance_id()
	for member_id in _escort_ship_ids:
		_event_bus.request_tactical_attack.emit(
			[member_id], attacker_id, "replace")

	_perf.end("FleetCommand.stance_response")


# ─── Cleanup ──────────────────────────────────────────────────────────────

func _on_ship_destroyed(ship: Node, _pos: Vector3, _faction: String) -> void:
	var ship_id := ship.get_instance_id()
	_stances.erase(ship_id)
