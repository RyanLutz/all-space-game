extends Node
class_name HardpointComponent

# Hardpoint configuration
@export var hardpoint_id: String = ""
@export var hardpoint_index: int = 0
@export var offset: Vector2 = Vector2.ZERO
@export var facing: float = 0.0  # degrees
@export var arc_degrees: float = 5.0  # 5 = fixed, 25 = gimbal, 120 = partial turret, 360 = full turret
@export var size: String = "small"  # small, medium, large
@export var allowed_groups: Array[String] = ["primary"]

# Heat system
@export var heat_capacity: float = 100.0
@export var passive_cooling: float = 25.0
@export var overheat_cooldown: float = 2.0

# Damage state
@export var hardpoint_hp_max: float = 50.0
var hardpoint_hp: float = 50.0
var damage_state: String = "nominal"  # nominal, damaged, critical, destroyed

# Runtime state
var heat_current: float = 0.0
var overheat_timer: float = 0.0
var weapon_data: Dictionary = {}
var _last_fire_time: float = 0.0

# Damage state multipliers
const HEAT_MULTIPLIER_DAMAGED: float = 1.5
const HEAT_MULTIPLIER_CRITICAL: float = 2.0
const MISFIRE_CHANCE_CRITICAL: float = 0.3

var _ship: Ship
var _event_bus: Node


func _ready() -> void:
	# HardpointComponent → WeaponComponent → Ship
	_ship = get_parent().get_parent() as Ship
	if _ship == null:
		push_error("HardpointComponent '%s': could not find Ship in parent chain." % hardpoint_id)
	_event_bus = get_node("/root/GameEventBus")
	hardpoint_hp = hardpoint_hp_max


func _physics_process(delta: float) -> void:
	# Passive cooling
	if heat_current > 0:
		var cooling = passive_cooling * delta
		if damage_state == "damaged":
			cooling *= 0.7
		elif damage_state == "critical":
			cooling *= 0.5
		heat_current = maxf(0.0, heat_current - cooling)

	# Overheat countdown
	if overheat_timer > 0:
		overheat_timer -= delta
		if overheat_timer <= 0:
			overheat_timer = 0
			# Still need to cool down before firing again
			_event_bus.emit_signal("overheat_warning", hardpoint_id, heat_current / heat_capacity)


func can_fire(aim_direction: Vector2) -> bool:
	# Check if destroyed
	if damage_state == "destroyed":
		return false

	# Check overheat
	if overheat_timer > 0:
		return false
	if heat_current >= heat_capacity:
		return false

	# Check arc (convert to local space)
	var local_aim = aim_direction.rotated(-_ship.rotation)
	var hardpoint_dir = Vector2.RIGHT.rotated(deg_to_rad(facing))
	var angle_diff = rad_to_deg(local_aim.angle_to(hardpoint_dir))
	if absf(angle_diff) > arc_degrees * 0.5:
		return false

	# Check weapon has data
	if weapon_data.is_empty():
		return false

	return true


func get_world_position() -> Vector2:
	return _ship.position + offset.rotated(_ship.rotation)


func get_world_facing() -> float:
	return _ship.rotation + deg_to_rad(facing)


func request_fire(aim_direction: Vector2, target_pos: Vector2) -> bool:
	if not can_fire(aim_direction):
		return false

	# Critical state misfire chance
	if damage_state == "critical" and randf() < MISFIRE_CHANCE_CRITICAL:
		return false

	var archetype: String = weapon_data.get("archetype", "ballistic")

	# Check fire rate cooldown
	var fire_rate: float = weapon_data.get("fire_rate", 1.0)
	var time_between_shots: float = 1.0 / fire_rate
	if Time.get_ticks_msec() / 1000.0 - _last_fire_time < time_between_shots:
		return false

	# Calculate heat and power costs
	var heat_cost: float = weapon_data.get("heat_per_shot", 0.0)
	var power_cost: float = weapon_data.get("power_per_shot", 0.0)

	# Apply damage state multiplier to heat
	if damage_state == "damaged":
		heat_cost *= HEAT_MULTIPLIER_DAMAGED
	elif damage_state == "critical":
		heat_cost *= HEAT_MULTIPLIER_CRITICAL

	# Check power availability (ship-level pool)
	if not _ship.consume_power(power_cost):
		return false

	# Apply heat
	heat_current += heat_cost

	# Check overheat
	if heat_current >= heat_capacity:
		overheat_timer = overheat_cooldown
		heat_current = heat_capacity

	_last_fire_time = Time.get_ticks_msec() / 1000.0

	# Fire based on archetype
	match archetype:
		"ballistic":
			_fire_ballistic(target_pos)
		"energy_beam":
			_fire_beam(target_pos)
		"energy_pulse":
			_fire_pulse(target_pos)
		"missile_dumb":
			_fire_missile(target_pos, "none")
		"missile_guided":
			var guidance: String = weapon_data.get("guidance", "auto_lock")
			_fire_missile(target_pos, guidance)

	# Align with GameEventBus contract: weapon_fired(ship, weapon_id, position)
	_event_bus.emit_signal("weapon_fired", _ship, weapon_data.get("id", ""), get_world_position())

	return true


func _fire_ballistic(target_pos: Vector2) -> void:
	var world_pos := get_world_position()
	var muzzle_speed: float = weapon_data.get("muzzle_speed", 800.0)
	var lifetime: float = weapon_data.get("projectile_lifetime", 1.5)

	var aim_dir := (target_pos - world_pos).normalized()
	var projectile_vel := aim_dir * muzzle_speed + _ship.velocity

	# Weapon request is handled by ProjectileManager via GameEventBus.
	_event_bus.emit_signal(
		"request_spawn_dumb",
		world_pos,
		projectile_vel,
		lifetime,
		weapon_data.get("id", ""),
		_ship.get_instance_id()
	)


func _fire_beam(target_pos: Vector2) -> void:
	var world_pos := get_world_position()
	var range_val: float = weapon_data.get("range", 500.0)
	var aim_dir := (target_pos - world_pos).normalized()

	# Weapon request is handled by ProjectileManager via GameEventBus.
	_event_bus.emit_signal(
		"request_fire_hitscan",
		world_pos,
		aim_dir,
		range_val,
		weapon_data.get("id", ""),
		_ship.get_instance_id()
	)


func _fire_pulse(target_pos: Vector2) -> void:
	# Pulse uses same hitscan as beam but with discrete damage
	_fire_beam(target_pos)


func _fire_missile(target_pos: Vector2, guidance: String) -> void:
	var world_pos := get_world_position()
	var speed: float = weapon_data.get("speed", 400.0)

	var aim_dir := (target_pos - world_pos).normalized()
	var missile_vel := aim_dir * speed

	# Weapon request is handled by GuidedProjectilePool via GameEventBus.
	_event_bus.emit_signal(
		"request_spawn_guided",
		world_pos,
		missile_vel,
		guidance,
		weapon_data,
		_ship.get_instance_id()
	)


func apply_damage(amount: float) -> void:
	hardpoint_hp -= amount
	_update_damage_state()

	if damage_state == "destroyed":
		_event_bus.emit_signal("hardpoint_destroyed", _ship, hardpoint_index)


func _update_damage_state() -> void:
	var ratio := hardpoint_hp / hardpoint_hp_max
	if ratio <= 0.0:
		damage_state = "destroyed"
	elif ratio < 0.25:
		damage_state = "critical"
	elif ratio < 0.6:
		damage_state = "damaged"
	else:
		damage_state = "nominal"


func set_weapon(weapon_id: String, all_weapons: Dictionary) -> void:
	if all_weapons.has(weapon_id):
		weapon_data = all_weapons[weapon_id]
	else:
		weapon_data = {}
