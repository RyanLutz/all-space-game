extends Node
class_name NavigationController

## Flight computer: translates a world-space destination into per-frame
## input_forward and input_strafe values for Ship.gd.
##
## Two drive modes:
##   EXTERNAL — legacy behavior. The caller (AIController) drives via
##              set_destination() + set_thrust_fraction() + update() each frame.
##   TACTICAL_ORDER / FORMATION — self-driving via _physics_process after
##              receiving a signal from GameEventBus.
##
## Tactical orders take priority over formation destinations.

enum DriveMode { EXTERNAL, TACTICAL_ORDER, FORMATION, EMERGENCY_STOP }

# ─── Drive state ───────────────────────────────────────────────────────────
var _drive_mode: DriveMode = DriveMode.EXTERNAL
var _tactical_override: bool = false

# ─── Caller-set each frame (before update()) ────────────────────────────────
var _destination: Vector3 = Vector3.ZERO
var _thrust_fraction: float = 1.0

# ─── Arrival state ──────────────────────────────────────────────────────────
var _arrived: bool = false

# ─── Tuning (populated from ship stats in _ready()) ────────────────────────
var arrival_distance: float = 25.0
var brake_safety_margin: float = 1.25

# ─── Cached services ────────────────────────────────────────────────────────
var _perf: Node
var _event_bus: Node


func _ready() -> void:
	var service_locator := Engine.get_singleton("ServiceLocator")
	_perf = service_locator.GetService("PerformanceMonitor")
	_event_bus = service_locator.GetService("GameEventBus")

	# Read tuning from parent ship — get_parent() because this node is added
	# programmatically by ShipFactory (owner is not set automatically)
	var ship := get_parent()
	if ship and "arrival_distance" in ship:
		arrival_distance = ship.arrival_distance
	if ship and "brake_safety_margin" in ship:
		brake_safety_margin = ship.brake_safety_margin

	# Signal connections for self-drive
	if _event_bus:
		_event_bus.connect("request_tactical_move", _on_request_tactical_move)
		_event_bus.connect("request_tactical_stop", _on_request_tactical_stop)
		_event_bus.connect("request_formation_destination", _on_request_formation_destination)


# ─── Public Interface (EXTERNAL mode — AIController) ───────────────────────

func set_destination(pos: Vector3) -> void:
	pos.y = 0.0
	_destination = pos
	_arrived = false


func set_thrust_fraction(f: float) -> void:
	_thrust_fraction = clampf(f, 0.0, 1.0)


func has_arrived() -> bool:
	return _arrived


func has_tactical_order() -> bool:
	return _tactical_override


func update(delta: float) -> void:
	_perf.begin("Navigation.update")
	_update_nav(delta)
	_perf.end("Navigation.update")


# ─── Signal Handlers (self-drive) ──────────────────────────────────────────

func _on_request_tactical_move(ship_ids: Array, destination: Vector3, _queue_mode: String) -> void:
	var my_id := get_parent().get_instance_id()
	if my_id not in ship_ids:
		return
	# If warp is active, queue the move order instead of overriding
	var warp: WarpDrive = get_parent().get_node_or_null("WarpDrive") as WarpDrive
	if warp != null and warp.is_warp_active():
		warp.queue_move(destination)
		return
	_destination = destination
	_destination.y = 0.0
	_arrived = false
	_drive_mode = DriveMode.TACTICAL_ORDER
	_tactical_override = true
	_thrust_fraction = 1.0


func _on_request_tactical_stop(ship_ids: Array) -> void:
	var my_id := get_parent().get_instance_id()
	if my_id not in ship_ids:
		return
	_drive_mode = DriveMode.EXTERNAL
	_tactical_override = false
	_arrived = true
	var ship := get_parent()
	if ship:
		ship.input_forward = 0.0
		ship.input_strafe = 0.0


func _on_request_formation_destination(ship_id: int, destination: Vector3) -> void:
	if get_parent().get_instance_id() != ship_id:
		return
	if _tactical_override:
		return  # tactical order takes priority over formation
	_destination = destination
	_destination.y = 0.0
	_arrived = false
	_drive_mode = DriveMode.FORMATION
	_thrust_fraction = 1.0


# ─── Self-Drive Physics ───────────────────────────────────────────────────

func _physics_process(_delta: float) -> void:
	if _drive_mode == DriveMode.EXTERNAL:
		return

	if _arrived:
		if _drive_mode == DriveMode.TACTICAL_ORDER:
			_drive_mode = DriveMode.EXTERNAL
			_tactical_override = false
			if _event_bus:
				_event_bus.navigation_order_completed.emit(get_parent().get_instance_id())
		# FORMATION: stay arrived, next tick from FormationController will push new dest
		return

	_perf.begin("Navigation.update")
	if _drive_mode == DriveMode.EMERGENCY_STOP:
		_update_emergency_stop()
	else:
		_update_nav(_delta)
	_perf.end("Navigation.update")


# ─── Core Navigation Logic ──────────────────────────────────────────────────

func _update_nav(_delta: float) -> void:
	var ship := get_parent() as RigidBody3D

	var to_dest := _destination - ship.global_position
	to_dest.y = 0.0
	var distance := to_dest.length()

	# --- Arrival ---
	if distance <= arrival_distance:
		ship.input_forward = 0.0
		ship.input_strafe = 0.0
		_arrived = true
		return

	# --- Braking decision ---
	var velocity := ship.linear_velocity
	velocity.y = 0.0
	var speed := velocity.length()

	var max_decel: float = (ship.thruster_force * _thrust_fraction) / maxf(ship.mass, 0.001)
	var braking_distance := 0.0
	if max_decel > 0.0:
		braking_distance = (speed * speed) / (2.0 * max_decel) * brake_safety_margin

	var ship_forward := -ship.transform.basis.z
	var ship_right := ship.transform.basis.x

	if distance <= braking_distance and speed > 0.1:
		# --- Braking: reverse velocity vector projected onto ship axes ---
		var brake_dir := -velocity.normalized()
		ship.input_forward = brake_dir.dot(ship_forward) * _thrust_fraction
		ship.input_strafe = brake_dir.dot(ship_right) * _thrust_fraction
	else:
		# --- Accelerate: destination vector projected onto ship axes ---
		var dest_dir := to_dest.normalized()
		ship.input_forward = dest_dir.dot(ship_forward) * _thrust_fraction
		ship.input_strafe = dest_dir.dot(ship_right) * _thrust_fraction


func _update_emergency_stop() -> void:
	var ship := get_parent() as RigidBody3D
	var velocity := ship.linear_velocity
	velocity.y = 0.0
	var speed := velocity.length()

	if speed < 1.0:
		ship.input_forward = 0.0
		ship.input_strafe = 0.0
		_arrived = true
		return

	var ship_forward := -ship.transform.basis.z
	var ship_right := ship.transform.basis.x
	var brake_dir := -velocity.normalized()
	ship.input_forward = brake_dir.dot(ship_forward)
	ship.input_strafe = brake_dir.dot(ship_right)
