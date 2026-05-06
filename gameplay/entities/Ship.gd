extends SpaceBody
class_name Ship

## Ship physics layer. Translates unified input interface into Jolt force/torque
## commands. Never writes velocity or position to produce motion — forces only.
## Stats are populated at spawn time via initialize_stats().

# ─── Identity ─────────────────────────────────────────────────────────────────
var class_id: String = ""
var variant_id: String = ""
var faction: String = ""
var display_name: String = ""
var is_player: bool = false

# ─── Physics (populated from resolved stats) ─────────────────────────────────
var thruster_force: float = 0.0
var torque_thrust_ratio: float = 0.0
var max_torque: float = 0.0
var arrival_distance: float = 25.0
var brake_safety_margin: float = 1.25

# ─── Combat resources ────────────────────────────────────────────────────────
var hull_hp: float = 0.0
var hull_max: float = 0.0
var power_current: float = 0.0
var power_capacity: float = 0.0
var power_regen: float = 0.0
var shield_hp: float = 0.0
var shield_max: float = 0.0
var shield_regen_rate: float = 0.0
var shield_regen_delay: float = 0.0
var shield_regen_power_draw: float = 0.0
var time_since_last_hit: float = 999.0

# ─── Unified Input Interface ─────────────────────────────────────────────────
## Player or AI writes these each frame. Ship.gd reads unconditionally.
var input_forward: float = 0.0      # -1.0 to 1.0
var input_strafe: float = 0.0       # -1.0 to 1.0
var input_aim_target: Vector3 = Vector3.ZERO  # world-space aim point (Y = 0)
var input_fire: Array[bool] = [false, false, false]

# ─── VFX references (set by ShipFactory) ─────────────────────────────────────
var shield_mesh: MeshInstance3D = null

# ─── Cached services ─────────────────────────────────────────────────────────
var _perf: Node
var _event_bus: Node


static var _active_ship_count: int = 0

func _ready() -> void:
	var service_locator := Engine.get_singleton("ServiceLocator")
	_perf = service_locator.GetService("PerformanceMonitor")
	_event_bus = service_locator.GetService("GameEventBus")

	_active_ship_count += 1
	if _perf:
		_perf.set_count("Ships.active_count", _active_ship_count)


func _exit_tree() -> void:
	_active_ship_count -= 1
	if _perf:
		_perf.set_count("Ships.active_count", _active_ship_count)


## Called by ShipFactory (or test scene) after instantiation.
## stats is the resolved Dictionary: base_stats + all part deltas merged.
func initialize_stats(stats: Dictionary) -> void:
	# Physics
	mass = stats.get("mass", 1000.0)
	max_speed = stats.get("max_speed", 300.0)
	linear_damp = stats.get("linear_drag", 0.05)
	angular_damp = stats.get("angular_drag", 3.0)
	alignment_drag_base = stats.get("alignment_drag_base", stats.get("alignment_drag", 0.3))
	alignment_drag_current = alignment_drag_base
	thruster_force = stats.get("thruster_force", 12000.0)
	torque_thrust_ratio = stats.get("torque_thrust_ratio", 0.3)
	max_torque = stats.get("max_torque", 4000.0)
	arrival_distance = stats.get("arrival_distance", 25.0)
	brake_safety_margin = stats.get("brake_safety_margin", 1.25)

	# Combat
	hull_max = stats.get("hp", 100.0)
	hull_hp = hull_max
	power_capacity = stats.get("power_capacity", 100.0)
	power_current = power_capacity
	power_regen = stats.get("power_regen", 10.0)
	shield_max = stats.get("shield_max", 0.0)
	shield_hp = shield_max
	shield_regen_rate = stats.get("shield_regen_rate", 0.0)
	shield_regen_delay = stats.get("shield_regen_delay", 4.0)
	shield_regen_power_draw = stats.get("shield_regen_power_draw", 0.0)


# ─── Physics process ─────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	_perf.begin("Physics.thruster_allocation")
	_apply_thrust_forces()
	_apply_alignment_drag()
	_perf.end("Physics.thruster_allocation")

	# Reset per-frame overrides — anything wanting elevated alignment drag
	# must write it again next frame
	alignment_drag_current = alignment_drag_base

	# Combat resource regen
	_update_shield_regen(delta)
	_update_power_regen(delta)
	time_since_last_hit += delta

	# Y-enforcement backstop
	enforce_play_plane()


# ─── Assisted Steering ────────────────────────────────────────────────────────

func _compute_steering_torque() -> float:
	var heading_error := get_heading_error(input_aim_target)
	var omega := angular_velocity.y

	# How far will we rotate before angular velocity hits zero at max torque?
	# Approximate moment of inertia from inverse inertia tensor.
	var inv_tensor := get_inverse_inertia_tensor()
	var I_yy := 1.0 / maxf(inv_tensor.y.y, 0.001)
	var max_alpha := max_torque / maxf(I_yy, 0.001)
	var stopping_distance := (omega * omega) / (2.0 * maxf(max_alpha, 0.001))

	# If we'll overshoot, brake. Otherwise accelerate toward the target.
	if stopping_distance >= absf(heading_error) and signf(omega) == signf(heading_error):
		return -signf(omega) * max_torque   # brake
	else:
		return signf(heading_error) * max_torque  # accelerate toward target


# ─── Thruster Budget Allocation ───────────────────────────────────────────────

func _apply_thrust_forces() -> void:
	# 1. Compute desired torque from assisted steering
	var torque_demand := _compute_steering_torque()
	var torque_cost := absf(torque_demand) * torque_thrust_ratio
	var remaining := maxf(0.0, thruster_force - torque_cost)

	# 2. Translation gets whatever is left
	var forward_dir := get_heading()
	var right_dir := transform.basis.x
	var fwd := input_forward
	var strafe := input_strafe

	# Clamp diagonal input to unit magnitude — no extra thrust for holding W+D
	var input_len_sq := fwd * fwd + strafe * strafe
	if input_len_sq > 1.0:
		var inv_len := 1.0 / sqrt(input_len_sq)
		fwd *= inv_len
		strafe *= inv_len

	var translation_force := (forward_dir * fwd + right_dir * strafe) * remaining

	# 3. Hand off to Jolt
	apply_central_force(translation_force)
	apply_torque(Vector3(0.0, torque_demand, 0.0))


# ─── Alignment Drag ──────────────────────────────────────────────────────────

func _apply_alignment_drag() -> void:
	var heading := get_heading()
	var v := linear_velocity
	v.y = 0.0

	var axial := heading * v.dot(heading)
	var lateral := v - axial

	# Drag force opposes lateral velocity, scaled by the current coefficient
	var drag_force := -lateral * alignment_drag_current * mass
	apply_central_force(drag_force)


# ─── Combat Resource Regen ────────────────────────────────────────────────────

func _update_shield_regen(delta: float) -> void:
	if shield_max <= 0.0 or shield_hp >= shield_max:
		return
	if time_since_last_hit < shield_regen_delay:
		return
	if power_current < shield_regen_power_draw * delta:
		return
	var regen := shield_regen_rate * delta
	shield_hp = minf(shield_hp + regen, shield_max)
	power_current -= shield_regen_power_draw * delta


func _update_power_regen(delta: float) -> void:
	if power_current < power_capacity:
		power_current = minf(power_current + power_regen * delta, power_capacity)


# ─── Power Draw (for weapons) ────────────────────────────────────────────────

func draw_power(amount: float) -> bool:
	if power_current >= amount:
		power_current -= amount
		return true
	return false


## Drain power per frame (rate in units/sec). Returns true if sufficient energy.
func drain_power(rate: float, delta: float) -> bool:
	var cost := rate * delta
	if power_current >= cost:
		power_current -= cost
		return true
	return false


# ─── Damage (SpaceBody contract) ─────────────────────────────────────────────

func apply_damage(amount: float, damage_type: String,
				  _hit_pos: Vector3, component_ratio: float,
				  attacker_id: int = 0) -> void:
	time_since_last_hit = 0.0

	# Emit ship_damaged for stance system (defensive fan-out)
	var attacker_node: Node = instance_from_id(attacker_id) if attacker_id != 0 else null
	_event_bus.ship_damaged.emit(self, attacker_node, amount)

	# Shield absorption
	if shield_hp > 0.0:
		var factor := _damage_vs_shields(damage_type)
		var absorbed := minf(shield_hp, amount * factor)
		shield_hp -= absorbed
		amount = maxf(0.0, amount - absorbed / factor)
		if shield_hp <= 0.0:
			_event_bus.emit_signal("shield_depleted", self)

	if amount <= 0.0:
		return

	# Hull damage (component_ratio reserved for hardpoint damage in later steps)
	hull_hp -= amount * (1.0 - component_ratio)

	if hull_hp <= 0.0:
		_die()
	elif hull_hp / hull_max < 0.25:
		_event_bus.emit_signal("hull_critical", self, hull_hp / hull_max)


func _damage_vs_shields(_damage_type: String) -> float:
	# Placeholder — damage type multipliers deferred to balancing pass
	return 1.0


func _die() -> void:
	_event_bus.emit_signal("ship_destroyed", self, global_position, faction)
	queue_free()
