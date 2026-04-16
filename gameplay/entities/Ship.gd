class_name Ship
extends RigidBody3D

## Unified input (core_spec) — populated by pilot, AI, or NavigationController.
var input_forward: float = 0.0
var input_strafe: float = 0.0
var input_aim_target: Vector3 = Vector3.ZERO
var input_fire: Array[bool] = [false, false, false]

var max_speed: float = 400.0
var linear_drag_coeff: float = 0.5
var alignment_drag_base: float = 0.2
var alignment_drag_current: float = 0.2

var thruster_force: float = 15000.0
var torque_thrust_ratio: float = 0.4
var max_torque: float = 6000.0

var _hull: Dictionary = {}
var _ship_id: String = ""
var _faction: String = "neutral"

var hull_hp: float = 100.0
var hull_hp_max: float = 100.0
var _hull_crit_emitted: bool = false

var _perf: Node
var _hardpoint_nodes: Array[Node3D] = []
var _weapon_components: Array[Node] = []

var control_source: String = "pilot" ## "pilot" | "ai" | "tactical"


func get_velocity_xz() -> Vector3:
	var v := linear_velocity
	v.y = 0.0
	return v


func enforce_play_plane() -> void:
	var p := global_position
	p.y = 0.0
	global_position = p
	var v := linear_velocity
	v.y = 0.0
	linear_velocity = v
	var av := angular_velocity
	av.x = 0.0
	av.z = 0.0
	angular_velocity = av
	rotation.x = 0.0
	rotation.z = 0.0


func configure_from_content(ship_data: Dictionary, ship_content_id: String) -> void:
	add_to_group("ships")
	add_to_group("physics_bodies")
	_ship_id = ship_content_id
	_hull = ship_data.get("hull", {}) as Dictionary
	hull_hp_max = float(_hull.get("hp", 100.0))
	hull_hp = hull_hp_max
	mass = float(_hull.get("mass", 800.0))
	max_speed = float(_hull.get("max_speed", 450.0))
	linear_drag_coeff = float(_hull.get("linear_drag", 0.5))
	alignment_drag_base = float(_hull.get("alignment_drag", 0.2))
	alignment_drag_current = alignment_drag_base
	thruster_force = float(_hull.get("thruster_force", 15000.0))
	torque_thrust_ratio = float(_hull.get("torque_thrust_ratio", 0.4))
	max_torque = float(_hull.get("max_torque", thruster_force * torque_thrust_ratio))
	linear_damp = linear_drag_coeff
	angular_damp = float(_hull.get("angular_drag", linear_drag_coeff * 0.6))
	gravity_scale = 0.0
	axis_lock_linear_y = true
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	can_sleep = false
	collision_layer = 1
	collision_mask = 1 | 2 | 3
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	_perf = ServiceLocator.GetService("PerformanceMonitor") as Node


func _ready() -> void:
	if _perf == null:
		_perf = ServiceLocator.GetService("PerformanceMonitor") as Node
	var bus: Node = ServiceLocator.GetService("GameEventBus") as Node
	if bus != null and not bus.is_connected("projectile_hit", Callable(self, "_on_projectile_hit")):
		bus.connect("projectile_hit", Callable(self, "_on_projectile_hit"))


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _perf != null:
		_perf.begin("Physics.thruster_allocation")
	_apply_thruster_forces(state)
	_apply_alignment_drag(state)
	if _perf != null:
		_perf.end("Physics.thruster_allocation")


func _physics_process(_delta: float) -> void:
	enforce_play_plane()
	alignment_drag_current = alignment_drag_base
	var spd: float = get_velocity_xz().length()
	if spd > max_speed:
		var v := get_velocity_xz().normalized() * max_speed
		v.y = 0.0
		linear_velocity = v


func get_heading() -> Vector3:
	return -global_transform.basis.z


func get_heading_error(target_world: Vector3) -> float:
	var to_target := target_world - global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.0001:
		return 0.0
	var target_yaw := atan2(-to_target.x, -to_target.z)
	return wrapf(target_yaw - rotation.y, -PI, PI)


func _compute_steering_torque(state: PhysicsDirectBodyState3D) -> float:
	var heading_error := get_heading_error(input_aim_target)
	var omega := state.get_angular_velocity().y
	var inv_i: float = state.inverse_inertia.y
	if inv_i < 0.0000001:
		inv_i = 0.0000001
	var max_alpha: float = max_torque * inv_i
	var stopping_distance: float = (omega * omega) / (2.0 * maxf(max_alpha, 0.0001))
	if stopping_distance >= absf(heading_error) and signf(omega) == signf(heading_error) and absf(omega) > 0.01:
		return -signf(omega) * max_torque
	return signf(heading_error) * max_torque


func _apply_thruster_forces(state: PhysicsDirectBodyState3D) -> void:
	var torque_demand := _compute_steering_torque(state)
	var torque_cost := absf(torque_demand) * torque_thrust_ratio
	var remaining: float = maxf(0.0, thruster_force - torque_cost)
	var forward_dir := get_heading()
	var right_dir := global_transform.basis.x
	var input_vec := Vector2(input_strafe, -input_forward)
	if input_vec.length() > 1.0:
		input_vec = input_vec.normalized()
	var translation_force: Vector3 = (
		forward_dir * (-input_vec.y) * remaining + right_dir * input_vec.x * remaining
	)
	state.apply_central_force(translation_force)
	state.apply_torque(Vector3(0.0, torque_demand, 0.0))


func _apply_alignment_drag(state: PhysicsDirectBodyState3D) -> void:
	var heading := get_heading()
	var v := state.get_linear_velocity()
	v.y = 0.0
	var axial: Vector3 = heading * v.dot(heading)
	var lateral: Vector3 = v - axial
	var drag_force: Vector3 = -lateral * alignment_drag_current * mass
	state.apply_central_force(drag_force)


func apply_damage(amount: float, damage_type: String, hit_pos: Vector3, component_ratio: float) -> void:
	var hull_part: float = amount * (1.0 - component_ratio)
	hull_hp = maxf(0.0, hull_hp - hull_part)
	if hull_hp <= 0.0:
		var bus: Node = ServiceLocator.GetService("GameEventBus") as Node
		if bus != null:
			bus.emit_signal("ship_destroyed", self, global_position, _faction)
		queue_free()
	elif hull_hp / hull_hp_max < 0.25 and not _hull_crit_emitted:
		_hull_crit_emitted = true
		var bus2: Node = ServiceLocator.GetService("GameEventBus") as Node
		if bus2 != null:
			bus2.emit_signal("hull_critical", self, hull_hp / hull_hp_max)


func _on_projectile_hit(
	target: Node, damage: float, damage_type: String, position: Vector3, component_ratio: float
) -> void:
	if target != self:
		return
	apply_damage(damage, damage_type, position, component_ratio)


func register_hardpoint_visual(node: Node3D) -> void:
	_hardpoint_nodes.append(node)


func get_hardpoint_nodes() -> Array[Node3D]:
	return _hardpoint_nodes


func add_weapon_component(w: Node) -> void:
	_weapon_components.append(w)


func get_ship_content_id() -> String:
	return _ship_id


func set_faction(f: String) -> void:
	_faction = f
