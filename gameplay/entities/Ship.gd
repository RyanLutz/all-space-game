extends SpaceBody
class_name Ship

@export var thruster_force: float = 15000.0
@export var torque_thrust_ratio: float = 0.4
@export var max_angular_accel: float = 5.0  # radians/sec²
@export var is_player_controlled: bool = true


# SpaceBody._ready() covers group registration, monitor setup, and moment_of_inertia.
# Ship does not need its own _ready().


func apply_thrust_forces(delta: float) -> void:
	# Step 1 — Determine target heading angle.
	var target_angle: float
	if is_player_controlled:
		var mouse_pos := get_global_mouse_position()
		target_angle = position.direction_to(mouse_pos).angle()
	else:
		target_angle = rotation  # AI will write a real target later.

	_perf.begin("Physics.thruster_allocation")

	# Step 2 — Compute torque demand via assisted steering.
	var torque_demand := _update_assisted_steering(target_angle)

	# Step 3 — Read movement input (zero for non-player).
	var forward_input := 0.0
	var strafe_input := 0.0
	if is_player_controlled:
		forward_input = (Input.get_action_strength("thrust_forward")
				- Input.get_action_strength("thrust_reverse"))
		strafe_input = (Input.get_action_strength("strafe_right")
				- Input.get_action_strength("strafe_left"))

	# Step 4 — Allocate thruster budget; turning wins.
	_allocate_thrust(forward_input, strafe_input, torque_demand, delta)

	_perf.end("Physics.thruster_allocation")

	# Step 5 — Soft speed cap.
	if velocity.length() > max_speed:
		velocity = velocity.normalized() * max_speed


func _update_assisted_steering(target_angle: float) -> float:
	var heading_error := angle_difference(rotation, target_angle)
	var stopping_distance := (angular_velocity * angular_velocity) / \
			(2.0 * max_angular_accel + 0.0001)  # epsilon avoids div-by-zero at rest

	var torque_direction: float
	if stopping_distance >= absf(heading_error):
		torque_direction = -signf(angular_velocity)  # brake: we will overshoot
	else:
		torque_direction = signf(heading_error)       # accelerate toward target

	return torque_direction * max_angular_accel


func _allocate_thrust(forward_input: float, strafe_input: float,
		torque_demand: float, delta: float) -> void:
	# Clamp torque demand to what thrusters can deliver (turning wins, but cap it).
	var max_torque_output := thruster_force / torque_thrust_ratio
	var clamped_torque := clampf(torque_demand, -max_torque_output, max_torque_output)

	var torque_cost := absf(clamped_torque) * torque_thrust_ratio
	var remaining := maxf(0.0, thruster_force - torque_cost)

	# Build 2D movement vector in ship-local space (X = forward, Y = strafe).
	# Ship polygon points right (+X), so forward_input maps to +X.
	var movement_input := Vector2(forward_input, strafe_input)
	if movement_input.length() > 1.0:
		movement_input = movement_input.normalized()

	# Apply angular change first (turning wins, but was capped above).
	angular_velocity += clamped_torque * delta

	# Rotate local movement into world space and apply as a force.
	var world_force := movement_input.rotated(rotation) * remaining
	velocity += world_force * delta / mass
