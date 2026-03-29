extends SpaceBody
class_name Ship

@export var thruster_force: float = 15000.0
@export var torque_thrust_ratio: float = 0.4
@export var max_angular_accel: float = 5.0  # radians/sec²
@export var is_player_controlled: bool = true

# Power System (per ship shared pool)
@export var power_capacity: float = 100.0
@export var power_regen: float = 15.0
var power_current: float = 100.0

# Shield System
@export var shield_max: float = 100.0
@export var regen_rate: float = 20.0
@export var regen_delay: float = 3.0
@export var regen_power_draw: float = 10.0
var shield_hp: float = 100.0
var _time_since_last_hit: float = 999.0

# Hull / Combat
@export var hull_max: float = 200.0
var hull_hp: float = 200.0

# Used by GameEventBus payloads (e.g. ship_destroyed) and AI/threat integration.
@export var faction: String = "neutral"

# Damage type multipliers loaded from JSON
var _damage_types: Dictionary = {}
var _shield_absorption: float = 0.8
var _hardpoint_radius_by_size: Dictionary = {}
var _hardpoint_radius_hp_scale: float = 0.35

var _weapon_component: WeaponComponent = null

@onready var _event_bus: Node = ServiceLocator.GetService("GameEventBus") as Node


func _ready() -> void:
	# Load damage type data
	var file_path := "res://data/damage_types.json"
	var damage_file = FileAccess.open(file_path, FileAccess.READ)
	if not damage_file:
		push_error("Ship: Failed to open %s" % file_path)
		return

	var text := damage_file.get_as_text()
	damage_file.close()

	var json := JSON.new()
	var parse_err := json.parse(text)
	if parse_err != OK:
		push_error(
			"Ship: JSON parse failed for %s: %s (line %d)" % [
				file_path, json.get_error_message(), json.get_error_line()
			]
		)
		return

	var data: Dictionary = json.get_data()
	if typeof(data) != TYPE_DICTIONARY:
		push_error("Ship: Invalid root in %s (expected Dictionary)" % file_path)
		return

	if not data.has("_comment") or typeof(data["_comment"]) != TYPE_STRING:
		push_error("Ship: Missing/invalid top-level _comment in %s" % file_path)
		return

	if not data.has("damage_types") or typeof(data["damage_types"]) != TYPE_DICTIONARY:
		push_error("Ship: Missing/invalid 'damage_types' dictionary in %s" % file_path)
		return

	if not data.has("shield_absorption") or typeof(data["shield_absorption"]) != TYPE_DICTIONARY:
		push_error("Ship: Missing/invalid 'shield_absorption' dictionary in %s" % file_path)
		return

	var shield_absorption: Dictionary = data["shield_absorption"]
	if not shield_absorption.has("base_ratio"):
		push_error("Ship: Missing 'shield_absorption.base_ratio' in %s" % file_path)
		return

	var base_ratio_val = shield_absorption["base_ratio"]
	var base_ratio_type := typeof(base_ratio_val)
	if base_ratio_type != TYPE_INT and base_ratio_type != TYPE_FLOAT:
		push_error("Ship: 'shield_absorption.base_ratio' must be a number in %s" % file_path)
		return
	_shield_absorption = float(base_ratio_val)

	var damage_types: Dictionary = data["damage_types"]
	for damage_type in damage_types.keys():
		var type_data = damage_types[damage_type]
		if typeof(type_data) != TYPE_DICTIONARY:
			push_error("Ship: damage_types.%s must be a Dictionary in %s" % [str(damage_type), file_path])
			return
		if not type_data.has("vs_shields") or not type_data.has("vs_hull"):
			push_error("Ship: damage_types.%s missing 'vs_shields' or 'vs_hull' in %s" % [str(damage_type), file_path])
			return

		var vs_shields_val = type_data["vs_shields"]
		var vs_hull_val = type_data["vs_hull"]
		var vs_shields_ok := typeof(vs_shields_val) == TYPE_INT or typeof(vs_shields_val) == TYPE_FLOAT
		var vs_hull_ok := typeof(vs_hull_val) == TYPE_INT or typeof(vs_hull_val) == TYPE_FLOAT
		if not (vs_shields_ok and vs_hull_ok):
			push_error("Ship: damage_types.%s multipliers must be numbers in %s" % [str(damage_type), file_path])
			return

	_damage_types = damage_types

	if not data.has("hardpoint_hit_regions") or typeof(data["hardpoint_hit_regions"]) != TYPE_DICTIONARY:
		push_error("Ship: Missing/invalid 'hardpoint_hit_regions' in %s" % file_path)
		return

	var hhr: Dictionary = data["hardpoint_hit_regions"]
	if not hhr.has("radius_by_size") or typeof(hhr["radius_by_size"]) != TYPE_DICTIONARY:
		push_error("Ship: hardpoint_hit_regions missing 'radius_by_size' in %s" % file_path)
		return

	var rbs: Dictionary = hhr["radius_by_size"]
	for sz in ["small", "medium", "large"]:
		if not rbs.has(sz):
			push_error("Ship: hardpoint_hit_regions.radius_by_size missing '%s' in %s" % [sz, file_path])
			return
		var rv = rbs[sz]
		if typeof(rv) != TYPE_INT and typeof(rv) != TYPE_FLOAT:
			push_error("Ship: hardpoint_hit_regions.radius_by_size.%s must be a number in %s" % [sz, file_path])
			return

	_hardpoint_radius_by_size = rbs.duplicate()
	var hp_scale_val = hhr.get("radius_extra_from_hp_max", 0.35)
	if typeof(hp_scale_val) != TYPE_INT and typeof(hp_scale_val) != TYPE_FLOAT:
		push_error("Ship: hardpoint_hit_regions.radius_extra_from_hp_max must be a number in %s" % file_path)
		return
	_hardpoint_radius_hp_scale = float(hp_scale_val)

	# Initialize resources
	power_current = power_capacity
	shield_hp = shield_max
	hull_hp = hull_max

	for c in get_children():
		if c is WeaponComponent:
			_weapon_component = c
			break


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_update_resource_regen(delta)
	_time_since_last_hit += delta


func _update_resource_regen(delta: float) -> void:
	# Power regen (always happens unless at max)
	if power_current < power_capacity:
		power_current = minf(power_current + power_regen * delta, power_capacity)

	# Shield regen (only after delay, and only if we have power)
	if shield_hp < shield_max and _time_since_last_hit >= regen_delay:
		var power_cost = regen_power_draw * delta
		if power_current >= power_cost:
			var regen_amount = regen_rate * delta
			shield_hp = minf(shield_hp + regen_amount, shield_max)
			power_current -= power_cost


func apply_damage(amount: float, damage_type: String, hit_position: Vector2, component_damage_ratio: float = 0.0) -> void:
	_time_since_last_hit = 0.0

	# Get damage multipliers
	var type_data: Dictionary = _damage_types.get(damage_type, {})
	var vs_shields: float = float(type_data.get("vs_shields", 1.0))
	var vs_hull: float = float(type_data.get("vs_hull", 1.0))

	# Shield absorption (see Weapons_Projectiles_Spec — shields first; leakage uses vs_shields + absorption curve)
	var shield_damage: float = amount * vs_shields
	var remaining_damage: float = 0.0

	if shield_hp > 0:
		var absorbed: float = minf(shield_hp, shield_damage)
		shield_hp -= absorbed
		var absorbed_ratio: float = absorbed / shield_damage if shield_damage > 0 else 1.0
		remaining_damage = amount * (1.0 - _shield_absorption * absorbed_ratio)

		if shield_hp <= 0:
			_event_bus.emit_signal("shield_depleted", self)
	else:
		remaining_damage = amount

	if remaining_damage <= 0:
		return

	# Post-shield damage budget with hull type multiplier, then optional hardpoint split
	var effective_hull: float = remaining_damage * vs_hull
	var to_hull: float = effective_hull
	var to_hardpoint: float = 0.0

	if component_damage_ratio > 0.0 and is_finite(component_damage_ratio):
		var ratio_clamped: float = clampf(component_damage_ratio, 0.0, 1.0)
		if ratio_clamped > 0.0:
			_perf.begin("HitDetection.component_resolve")
			var hp_hit: HardpointComponent = _resolve_hardpoint_at(hit_position)
			if hp_hit != null:
				to_hardpoint = effective_hull * ratio_clamped
				to_hull = effective_hull * (1.0 - ratio_clamped)
				hp_hit.apply_damage(to_hardpoint)
			_perf.end("HitDetection.component_resolve")

	if to_hull > 0:
		hull_hp -= to_hull
		_event_bus.emit_signal("ship_damaged", self, to_hull, damage_type, hit_position)

	if hull_hp <= 0:
		hull_hp = 0
		_event_bus.emit_signal("ship_destroyed", self, global_position, faction)


func _resolve_hardpoint_at(world_pos: Vector2) -> HardpointComponent:
	if _weapon_component == null:
		return null

	var best: HardpointComponent = null
	var best_dist: float = INF

	for node in _weapon_component.get_all_hardpoints():
		var hp: HardpointComponent = node as HardpointComponent
		if hp == null:
			continue
		if hp.damage_state == "destroyed":
			continue

		var threshold: float = _hardpoint_threshold(hp)
		var dist: float = world_pos.distance_to(hp.get_world_position())
		if dist <= threshold and dist < best_dist:
			best = hp
			best_dist = dist

	return best


func _hardpoint_threshold(hp: HardpointComponent) -> float:
	var base: Variant = _hardpoint_radius_by_size.get(hp.size, _hardpoint_radius_by_size.get("medium", 40.0))
	var base_f: float = float(base)
	return maxf(base_f, hp.hardpoint_hp_max * _hardpoint_radius_hp_scale)


func consume_power(amount: float) -> bool:
	if power_current >= amount:
		power_current -= amount
		return true
	return false


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
