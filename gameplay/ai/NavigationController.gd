extends Node
class_name NavigationController

## Flight computer: translates a world-space destination into per-frame
## input_forward and input_strafe values for Ship.gd.
##
## This is a tool, not an actor. It has no _physics_process and makes no
## decisions about where to go. The caller (AIController, TacticalInputHandler)
## drives it explicitly via set_destination() + set_thrust_fraction() + update().

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


func _ready() -> void:
	_perf = ServiceLocator.GetService("PerformanceMonitor")

	# Read tuning from parent ship's stats
	var ship := owner
	if ship and "arrival_distance" in ship:
		arrival_distance = ship.arrival_distance
	if ship and "brake_safety_margin" in ship:
		brake_safety_margin = ship.brake_safety_margin


# ─── Public Interface ───────────────────────────────────────────────────────

func set_destination(pos: Vector3) -> void:
	pos.y = 0.0
	_destination = pos
	_arrived = false


func set_thrust_fraction(f: float) -> void:
	_thrust_fraction = clampf(f, 0.0, 1.0)


func has_arrived() -> bool:
	return _arrived


func update(delta: float) -> void:
	_perf.begin("Navigation.update")
	_update_nav(delta)
	_perf.end("Navigation.update")


# ─── Core Navigation Logic ──────────────────────────────────────────────────

func _update_nav(_delta: float) -> void:
	var ship := owner as RigidBody3D

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

	var max_decel := (ship.thruster_force * _thrust_fraction) / maxf(ship.mass, 0.001)
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
