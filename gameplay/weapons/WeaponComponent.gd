extends Node
class_name WeaponComponent

## Firing logic for weapon archetypes. Attached to weapon model node.
## Reads weapon data from JSON and emits GameEventBus signals to spawn projectiles.

# ─── Configuration (set at assembly time) ────────────────────────────────────
var weapon_id: String = ""
var archetype: String = ""  # ballistic, energy_beam, energy_pulse, missile_dumb, missile_guided

# ─── Stats from weapon.json ──────────────────────────────────────────────────
var damage: float = 0.0
var damage_per_second: float = 0.0
var fire_rate: float = 0.0
var muzzle_speed: float = 0.0
var range_val: float = 0.0
var heat_per_shot: float = 0.0
var heat_per_second: float = 0.0
var power_per_shot: float = 0.0
var power_per_second: float = 0.0
var projectile_lifetime: float = 2.0
var component_damage_ratio: float = 0.1

# ─── Firing State ────────────────────────────────────────────────────────────
var _fire_cooldown: float = 0.0
var _is_firing_beam: bool = false

# ─── References ──────────────────────────────────────────────────────────────
var hardpoint: Node = null
var _event_bus: Node = null
var _perf: Node = null


func _ready() -> void:
	_event_bus = ServiceLocator.GetService("GameEventBus")
	_perf = ServiceLocator.GetService("PerformanceMonitor")


func _process(delta: float) -> void:
	if hardpoint == null or hardpoint.owner_ship == null:
		return

	# Update cooldown
	if _fire_cooldown > 0.0:
		_fire_cooldown -= delta

	# Check if we should be firing
	var should_fire: bool = hardpoint.should_fire(hardpoint.owner_ship.input_fire)

	match archetype:
		"ballistic", "missile_dumb":
			_fire_discrete(should_fire)
		"energy_pulse":
			_fire_pulse(should_fire)
		"energy_beam":
			_fire_beam(should_fire, delta)


# ─── Discrete Firing (Ballistic, Missile) ────────────────────────────────────

func _fire_discrete(should_fire: bool) -> void:
	if not should_fire:
		return
	if _fire_cooldown > 0.0:
		return
	if hardpoint.roll_misfire():
		return  # Critical state misfire

	# Check power for ship (not needed for ballistic)
	if power_per_shot > 0.0:
		if not hardpoint.owner_ship.draw_power(power_per_shot):
			return  # Insufficient power

	# Apply heat
	hardpoint.apply_heat(heat_per_shot)
	if hardpoint.is_overheated:
		return

	# Fire!
	_spawn_dumb_projectile()

	# Set cooldown
	var cooldown: float = 1.0 / (fire_rate * hardpoint.get_fire_rate_multiplier())
	_fire_cooldown = cooldown

	_event_bus.emit_signal("weapon_fired", hardpoint.owner_ship, weapon_id, get_muzzle_pos())


# ─── Pulse Firing (Energy Pulse) ────────────────────────────────────────────

func _fire_pulse(should_fire: bool) -> void:
	if not should_fire:
		return
	if _fire_cooldown > 0.0:
		return
	if hardpoint.roll_misfire():
		return

	# Check power
	if power_per_shot > 0.0:
		if not hardpoint.owner_ship.draw_power(power_per_shot):
			return

	# Apply heat
	hardpoint.apply_heat(heat_per_shot)
	if hardpoint.is_overheated:
		return

	# Fire hitscan
	_fire_hitscan()

	# Set cooldown
	var cooldown: float = 1.0 / (fire_rate * hardpoint.get_fire_rate_multiplier())
	_fire_cooldown = cooldown

	_event_bus.emit_signal("weapon_fired", hardpoint.owner_ship, weapon_id, get_muzzle_pos())


# ─── Beam Firing (Energy Beam - Continuous) ───────────────────────────────────

func _fire_beam(should_fire: bool, delta: float) -> void:
	if not should_fire:
		_is_firing_beam = false
		return

	if hardpoint.is_overheated:
		return

	# Check power (continuous drain)
	var power_needed := power_per_second * delta
	if not hardpoint.owner_ship.draw_power(power_needed):
		_is_firing_beam = false
		return

	# Apply heat (continuous)
	hardpoint.apply_heat(heat_per_second * delta)

	# Fire hitscan every frame
	_fire_hitscan_beam(delta)

	if not _is_firing_beam:
		# Just started firing
		_event_bus.emit_signal("weapon_fired", hardpoint.owner_ship, weapon_id, get_muzzle_pos())

	_is_firing_beam = true


# ─── Projectile Spawning ─────────────────────────────────────────────────────

func _spawn_dumb_projectile() -> void:
	var muzzle_pos: Vector3 = get_muzzle_pos()
	var aim_dir: Vector3 = hardpoint.get_aim_direction()
	var inherited_vel: Vector3 = hardpoint.owner_ship.linear_velocity

	# Zero Y components
	muzzle_pos.y = 0.0
	aim_dir.y = 0.0
	aim_dir = aim_dir.normalized()
	inherited_vel.y = 0.0

	var velocity: Vector3 = aim_dir * muzzle_speed + inherited_vel

	_event_bus.emit_signal("request_spawn_dumb",
		muzzle_pos,
		velocity,
		projectile_lifetime,
		weapon_id,
		hardpoint.owner_ship.get_instance_id()
	)


# ─── Hitscan Firing ──────────────────────────────────────────────────────────

func _fire_hitscan() -> void:
	var muzzle_pos: Vector3 = get_muzzle_pos()
	var aim_dir: Vector3 = hardpoint.get_aim_direction()

	muzzle_pos.y = 0.0
	aim_dir.y = 0.0
	aim_dir = aim_dir.normalized()

	_event_bus.emit_signal("request_fire_hitscan",
		muzzle_pos,
		aim_dir,
		range_val,
		weapon_id,
		hardpoint.owner_ship.get_instance_id()
	)


func _fire_hitscan_beam(_delta: float) -> void:
	var muzzle_pos: Vector3 = get_muzzle_pos()
	var aim_dir: Vector3 = hardpoint.get_aim_direction()

	muzzle_pos.y = 0.0
	aim_dir.y = 0.0
	aim_dir = aim_dir.normalized()

	# Beam applies damage per second - the hitscan damage is per second value
	_event_bus.emit_signal("request_fire_hitscan",
		muzzle_pos,
		aim_dir,
		range_val,
		weapon_id,
		hardpoint.owner_ship.get_instance_id()
	)


# ─── Helpers ─────────────────────────────────────────────────────────────────

func get_muzzle_pos() -> Vector3:
	var model := get_parent() as Node3D
	if model == null:
		return Vector3.ZERO

	var muzzle := model.get_node_or_null("Muzzle") as Marker3D
	if muzzle != null:
		return muzzle.global_position

	# Fallback: use model position + forward offset
	return model.global_position + (-model.global_transform.basis.z * 0.5)


# ─── Assembly Initialization ─────────────────────────────────────────────────

func initialize_from_data(weapon_data: Dictionary) -> void:
	archetype = weapon_data.get("archetype", "")

	var stats: Dictionary = weapon_data.get("stats", {}) as Dictionary
	damage = stats.get("damage", 0.0)
	damage_per_second = stats.get("damage_per_second", 0.0)
	fire_rate = stats.get("fire_rate", 1.0)
	muzzle_speed = stats.get("muzzle_speed", 600.0)
	range_val = stats.get("range", 500.0)
	heat_per_shot = stats.get("heat_per_shot", 0.0)
	heat_per_second = stats.get("heat_per_second", 0.0)
	power_per_shot = stats.get("power_per_shot", 0.0)
	power_per_second = stats.get("power_per_second", 0.0)
	projectile_lifetime = stats.get("projectile_lifetime", 2.0)
	component_damage_ratio = stats.get("component_damage_ratio", 0.1)
