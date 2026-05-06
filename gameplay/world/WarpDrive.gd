class_name WarpDrive
extends Node

## Dual-mode warp component. Attached to every ship by ShipFactory.
##
## Two modes share one state machine:
##   PLOTTED  — right-click distant point → plot → charge → press Y → autopilot
##   MANUAL   — hold Y to charge → release Y to disengage → manual steering
##
## During ACTIVE: linear_damp overridden, thruster_force boosted, thrust curve
## applies cubic ease-out falloff as velocity approaches max_warp_speed.
## Weapons are disabled. NavigationController emergency-brakes on interrupt.

enum State { IDLE, CHARGING, READY, ACTIVE, DECELERATING }
enum Mode { NONE, PLOTTED, MANUAL }

# ─── Stats (populated by setup() from ship.json + archetype fallback) ───────
var charge_time: float = 2.5
var thrust_multiplier: float = 8.0
var damp_override: float = 0.0
var max_warp_speed: float = 2500.0
var interrupt_damage: float = 20.0
var exclusion_margin: float = 500.0
var min_distance: float = 5000.0
var charge_energy_rate: float = 15.0
var hold_energy_rate: float = 5.0

# ─── Runtime state ───────────────────────────────────────────────────────────
var _state: State = State.IDLE
var _mode: Mode = Mode.NONE
var _charge: float = 0.0
var _plotted_destination: Vector3 = Vector3.ZERO

# ─── Stat backup ─────────────────────────────────────────────────────────────
var _base_thruster_force: float = 0.0
var _base_damp: float = 0.0

# ─── Queued action ───────────────────────────────────────────────────────────
var _queued_destination: Vector3 = Vector3.ZERO
var _has_queued_move: bool = false

# ─── Cached references ───────────────────────────────────────────────────────
var _ship: Ship = null
var _nav: NavigationController = null
var _event_bus: Node = null


func _ready() -> void:
	_ship = get_parent() as Ship
	if _ship:
		_nav = _ship.get_node_or_null("NavigationController") as NavigationController

	var sl := Engine.get_singleton("ServiceLocator")
	if sl:
		_event_bus = sl.GetService("GameEventBus")

	if _event_bus:
		_event_bus.ship_damaged.connect(_on_ship_damaged)
		_event_bus.warp_destination_plotted.connect(_on_destination_plotted)

	# Populate defaults from archetype JSON (overridden by setup() if called)
	_load_archetype_defaults()


func setup(stats: Dictionary) -> void:
	charge_time          = float(stats.get("charge_time",          charge_time))
	thrust_multiplier    = float(stats.get("thrust_multiplier",    thrust_multiplier))
	damp_override        = float(stats.get("damp_override",        damp_override))
	max_warp_speed       = float(stats.get("max_warp_speed",       max_warp_speed))
	interrupt_damage     = float(stats.get("interrupt_damage",     interrupt_damage))
	exclusion_margin     = float(stats.get("exclusion_margin",     exclusion_margin))
	min_distance         = float(stats.get("min_distance",         min_distance))
	charge_energy_rate   = float(stats.get("charge_energy_rate",   charge_energy_rate))
	hold_energy_rate     = float(stats.get("hold_energy_rate",     hold_energy_rate))


# ─── Public query ────────────────────────────────────────────────────────────

func is_warp_active() -> bool:
	return _state == State.ACTIVE or _state == State.CHARGING or _state == State.READY


func get_state_name() -> String:
	return _state_to_string(_state)


func get_charge_ratio() -> float:
	if charge_time <= 0.0:
		return 0.0
	return clampf(_charge / charge_time, 0.0, 1.0)


func queue_move(destination: Vector3) -> void:
	_queued_destination = destination
	_has_queued_move = true


# ─── Input handling ──────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not _ship or not _ship.is_player:
		return

	if event.is_action_pressed("warp_initiate"):
		_on_warp_key_pressed()
	elif event.is_action_released("warp_initiate"):
		_on_warp_key_released()


func _on_warp_key_pressed() -> void:
	match _state:
		State.READY:
			if _mode == Mode.PLOTTED:
				_enter_active()
		State.IDLE:
			# Start manual charge (no destination required)
			_mode = Mode.MANUAL
			_enter_charging()


func _on_warp_key_released() -> void:
	if _mode != Mode.MANUAL:
		return
	match _state:
		State.CHARGING:
			_enter_idle()
		State.ACTIVE:
			_enter_decelerating("key_released")


func _on_destination_plotted(destination: Vector3) -> void:
	if _state != State.IDLE:
		return
	_plotted_destination = destination
	_mode = Mode.PLOTTED
	_enter_charging()


func _on_ship_damaged(victim: Node, _attacker: Node, amount: float) -> void:
	if victim != _ship:
		return
	if amount < interrupt_damage:
		return
	match _state:
		State.CHARGING, State.READY:
			_enter_idle()
		State.ACTIVE:
			_enter_decelerating("damage")


# ─── Per-frame state updates ─────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	match _state:
		State.CHARGING:
			_update_charging(delta)
		State.READY:
			_update_ready(delta)
		State.ACTIVE:
			_update_active(delta)
		State.DECELERATING:
			_update_decelerating()


func _update_charging(delta: float) -> void:
	if not _ship.drain_power(charge_energy_rate, delta):
		_enter_idle()
		return

	_charge += delta
	if _charge >= charge_time:
		if _mode == Mode.PLOTTED:
			_enter_ready()
		else:
			_enter_active()


func _update_ready(delta: float) -> void:
	if not _ship.drain_power(hold_energy_rate, delta):
		_enter_idle()


func _update_active(delta: float) -> void:
	# Apply acceleration curve: cubic ease-out falloff near max_warp_speed
	var speed := _ship.linear_velocity.length()
	var speed_ratio := clampf(speed / maxf(max_warp_speed, 1.0), 0.0, 1.0)
	var thrust_curve := 1.0 - pow(speed_ratio, 3.0)

	_ship.thruster_force = _base_thruster_force * thrust_multiplier * thrust_curve
	_ship.linear_damp = damp_override

	# Disable weapons during warp
	_ship.input_fire = [false, false, false]

	# Exclusion zone proximity check
	if _check_exclusion_proximity():
		_enter_decelerating("exclusion_zone")
		return

	# PLOTTED mode arrival check
	if _mode == Mode.PLOTTED:
		var to_dest := _plotted_destination - _ship.global_position
		to_dest.y = 0.0
		if to_dest.length() <= _ship.arrival_distance:
			_enter_decelerating("arrived")


func _update_decelerating() -> void:
	if _nav == null:
		_enter_idle()
		return
	if _nav.has_arrived():
		_enter_idle()


# ─── State transitions ───────────────────────────────────────────────────────

func _enter_idle() -> void:
	_restore_stats()
	var old_state := _state_to_string(_state)
	_state = State.IDLE
	_mode = Mode.NONE
	_charge = 0.0
	_plotted_destination = Vector3.ZERO

	if _event_bus:
		_event_bus.warp_state_changed.emit(_ship, old_state, "IDLE")

	# Execute queued move order now that warp is done
	if _has_queued_move:
		_has_queued_move = false
		if _event_bus:
			_event_bus.request_tactical_move.emit(
				[_ship.get_instance_id()], _queued_destination, "replace")


func _enter_charging() -> void:
	_charge = 0.0
	var old_state := _state_to_string(_state)
	_state = State.CHARGING
	if _event_bus:
		_event_bus.warp_state_changed.emit(_ship, old_state, "CHARGING")


func _enter_ready() -> void:
	var old_state := _state_to_string(_state)
	_state = State.READY
	if _event_bus:
		_event_bus.warp_state_changed.emit(_ship, old_state, "READY")


func _enter_active() -> void:
	_base_thruster_force = _ship.thruster_force
	_base_damp = _ship.linear_damp

	var old_state := _state_to_string(_state)
	_state = State.ACTIVE

	if _mode == Mode.PLOTTED and _nav != null:
		_nav.set_destination(_plotted_destination)
		_nav.set_thrust_fraction(1.0)

	if _event_bus:
		_event_bus.warp_state_changed.emit(_ship, old_state, "ACTIVE")


func _enter_decelerating(reason: String) -> void:
	_restore_stats()
	var old_state := _state_to_string(_state)
	_state = State.DECELERATING

	if _nav != null:
		_nav._drive_mode = NavigationController.DriveMode.EMERGENCY_STOP
		_nav._arrived = false

	if _event_bus:
		_event_bus.warp_state_changed.emit(_ship, old_state, "DECELERATING")
		_event_bus.warp_interrupted.emit(_ship, reason)


func _restore_stats() -> void:
	if _base_thruster_force > 0.0:
		_ship.thruster_force = _base_thruster_force
	if _base_damp >= 0.0:
		_ship.linear_damp = _base_damp
	_base_thruster_force = 0.0
	_base_damp = 0.0


# ─── Helpers ─────────────────────────────────────────────────────────────────

func _check_exclusion_proximity() -> bool:
	var stars := get_tree().get_nodes_in_group("stars")
	for star in stars:
		if not is_instance_valid(star):
			continue
		var star_body: StarBody = star as StarBody
		if star_body == null:
			continue
		var flat_dist := Vector2(
			_ship.global_position.x - star.global_position.x,
			_ship.global_position.z - star.global_position.z).length()
		if flat_dist < star_body.exclusion_radius + exclusion_margin:
			return true
	return false


func _state_to_string(s: State) -> String:
	match s:
		State.IDLE:          return "IDLE"
		State.CHARGING:      return "CHARGING"
		State.READY:         return "READY"
		State.ACTIVE:        return "ACTIVE"
		State.DECELERATING:  return "DECELERATING"
	return "IDLE"


func _load_archetype_defaults() -> void:
	var file := FileAccess.open("res://data/solar_system_archetypes.json", FileAccess.READ)
	if not file:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		return
	file.close()
	var data: Dictionary = json.data
	var w: Dictionary = data.get("warp", {})
	charge_time        = float(w.get("charge_time",        charge_time))
	thrust_multiplier  = float(w.get("thrust_multiplier",  thrust_multiplier))
	damp_override      = float(w.get("damp_override",      damp_override))
	max_warp_speed     = float(w.get("max_warp_speed",     max_warp_speed))
	interrupt_damage   = float(w.get("interrupt_damage",   interrupt_damage))
	exclusion_margin   = float(w.get("exclusion_margin",   exclusion_margin))
	min_distance       = float(w.get("min_distance",       min_distance))
	charge_energy_rate = float(w.get("charge_energy_rate", charge_energy_rate))
	hold_energy_rate   = float(w.get("hold_energy_rate",   hold_energy_rate))
