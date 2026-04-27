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

# Pulse beam burst state (energy_pulse uses BeamRenderer for brief bursts)
var _pulse_beam_timer: float = 0.0
var _pulse_beam_duration: float = 0.08

# ─── References ──────────────────────────────────────────────────────────────
var hardpoint: Node = null
var _event_bus: Node = null
var _perf: Node = null
var _muzzle_flash: MuzzleFlashPlayer = null
var _beam_renderer: BeamRenderer = null

# Beam visual endpoint tracking (filled by hitscan_resolved from ProjectileManager)
var _has_beam_endpoint: bool = false
var _last_beam_endpoint: Vector3 = Vector3.ZERO


func _ready() -> void:
	var service_locator := Engine.get_singleton("ServiceLocator")
	_event_bus = service_locator.GetService("GameEventBus")
	_perf = service_locator.GetService("PerformanceMonitor")
	_event_bus.hitscan_resolved.connect(_on_hitscan_resolved)
	call_deferred("_discover_vfx_players")


func _discover_vfx_players() -> void:
	var parent := get_parent()
	if parent == null:
		return
	_muzzle_flash = parent.get_node_or_null("MuzzleFlashPlayer") as MuzzleFlashPlayer
	_beam_renderer = parent.get_node_or_null("BeamRenderer") as BeamRenderer


func _process(delta: float) -> void:
	if hardpoint == null or hardpoint.owner_ship == null:
		return

	# Update cooldown
	if _fire_cooldown > 0.0:
		_fire_cooldown -= delta

	# Update active pulse beam visual
	if _pulse_beam_timer > 0.0:
		_pulse_beam_timer -= delta
		if _beam_renderer != null:
			var from := get_muzzle_pos()
			var to: Vector3
			if _has_beam_endpoint:
				to = _last_beam_endpoint
			else:
				var aim_dir: Vector3 = hardpoint.get_aim_direction()
				aim_dir.y = 0.0
				aim_dir = aim_dir.normalized()
				to = from + aim_dir * range_val
			_beam_renderer.update(from, to)
		if _pulse_beam_timer <= 0.0 and _beam_renderer != null:
			_beam_renderer.stop()
			_has_beam_endpoint = false

	# Check if we should be firing
	var should_fire: bool = hardpoint.should_fire(hardpoint.owner_ship.input_fire)

	match archetype:
		"ballistic", "missile_dumb":
			_fire_discrete(should_fire)
		"energy_pulse":
			_fire_pulse(should_fire)
		"energy_beam":
			_fire_beam(should_fire, delta)
		"missile_guided":
			_fire_guided(should_fire)


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
	if _muzzle_flash != null:
		_muzzle_flash.play()

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

	# Fire hitscan (resolves actual endpoint via hitscan_resolved signal)
	_fire_hitscan()

	# Trigger beam burst visual
	_pulse_beam_timer = _pulse_beam_duration
	if _beam_renderer != null:
		var from := get_muzzle_pos()
		var aim_dir: Vector3 = hardpoint.get_aim_direction()
		aim_dir.y = 0.0
		aim_dir = aim_dir.normalized()
		var to := from + aim_dir * range_val
		_beam_renderer.update(from, to)

	if _muzzle_flash != null:
		_muzzle_flash.play()

	# Set cooldown
	var cooldown: float = 1.0 / (fire_rate * hardpoint.get_fire_rate_multiplier())
	_fire_cooldown = cooldown

	_event_bus.emit_signal("weapon_fired", hardpoint.owner_ship, weapon_id, get_muzzle_pos())


# ─── Beam Firing (Energy Beam - Continuous) ───────────────────────────────────

func _fire_beam(should_fire: bool, delta: float) -> void:
	if not should_fire:
		if _is_firing_beam and _beam_renderer != null:
			_beam_renderer.stop()
		_is_firing_beam = false
		_has_beam_endpoint = false
		return

	if hardpoint.is_overheated:
		if _is_firing_beam and _beam_renderer != null:
			_beam_renderer.stop()
		_is_firing_beam = false
		_has_beam_endpoint = false
		return

	# Check power (continuous drain)
	var power_needed := power_per_second * delta
	if not hardpoint.owner_ship.draw_power(power_needed):
		if _is_firing_beam and _beam_renderer != null:
			_beam_renderer.stop()
		_is_firing_beam = false
		_has_beam_endpoint = false
		return

	# Apply heat (continuous)
	hardpoint.apply_heat(heat_per_second * delta)

	# Fire hitscan every frame
	_fire_hitscan_beam(delta)

	# Update beam visual using actual hitscan endpoint (via hitscan_resolved signal)
	if _beam_renderer != null:
		var from := get_muzzle_pos()
		var to: Vector3
		if _has_beam_endpoint:
			to = _last_beam_endpoint
		else:
			var aim_dir: Vector3 = hardpoint.get_aim_direction()
			aim_dir.y = 0.0
			aim_dir = aim_dir.normalized()
			to = from + aim_dir * range_val
		_beam_renderer.update(from, to)

	if not _is_firing_beam:
		# Just started firing
		_event_bus.emit_signal("weapon_fired", hardpoint.owner_ship, weapon_id, get_muzzle_pos())
		if _muzzle_flash != null:
			_muzzle_flash.play()

	_is_firing_beam = true


# ─── Guided Missile Firing ────────────────────────────────────────────────────

func _fire_guided(should_fire: bool) -> void:
	if not should_fire:
		return
	if _fire_cooldown > 0.0:
		return
	if hardpoint.roll_misfire():
		return  # Critical state misfire

	# Apply heat (launch heat only)
	hardpoint.apply_heat(heat_per_shot)
	if hardpoint.is_overheated:
		return

	# Fire guided missile!
	_spawn_guided_projectile()
	if _muzzle_flash != null:
		_muzzle_flash.play()

	# Set cooldown
	var cooldown: float = 1.0 / (fire_rate * hardpoint.get_fire_rate_multiplier())
	_fire_cooldown = cooldown

	_event_bus.emit_signal("weapon_fired", hardpoint.owner_ship, weapon_id, get_muzzle_pos())


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


func _spawn_guided_projectile() -> void:
	var muzzle_pos: Vector3 = get_muzzle_pos()
	var aim_dir: Vector3 = hardpoint.get_aim_direction()
	var inherited_vel: Vector3 = hardpoint.owner_ship.linear_velocity

	# Zero Y components
	muzzle_pos.y = 0.0
	aim_dir.y = 0.0
	aim_dir = aim_dir.normalized()
	inherited_vel.y = 0.0

	var velocity: Vector3 = aim_dir * muzzle_speed + inherited_vel

	# Get guidance mode from weapon data (default to auto_lock)
	var stats: Dictionary = _get_weapon_stats()
	var guidance_mode: String = stats.get("guidance", "auto_lock")

	# Build weapon data dictionary for the pool
	var weapon_data := {
		"archetype": archetype,
		"stats": stats
	}

	_event_bus.emit_signal("request_spawn_guided",
		muzzle_pos,
		velocity,
		guidance_mode,
		weapon_data,
		hardpoint.owner_ship.get_instance_id()
	)


func _get_weapon_stats() -> Dictionary:
	# Reconstruct stats dict from current properties
	return {
		"damage": damage,
		"fire_rate": fire_rate,
		"muzzle_speed": muzzle_speed,
		"range": range_val,
		"heat_per_shot": heat_per_shot,
		"power_per_shot": power_per_shot,
		"projectile_lifetime": projectile_lifetime,
		"component_damage_ratio": component_damage_ratio,
		"turn_rate": 90.0,  # Default guided missile turn rate
		"fuel": 4.0,         # Default guided missile fuel
		"guidance": "auto_lock",
		"lock_cone_degrees": 60.0,
		"blast_radius": 80.0
	}


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
		hardpoint.owner_ship.get_instance_id(),
		hardpoint.hardpoint_id
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
		hardpoint.owner_ship.get_instance_id(),
		hardpoint.hardpoint_id
	)


# ─── Hitscan Response ────────────────────────────────────────────────────────

func _on_hitscan_resolved(origin: Vector3, end: Vector3, hit: bool,
						  w_id: String, owner_id: int, hp_id: String) -> void:
	if hardpoint == null or hardpoint.owner_ship == null:
		return
	if owner_id != hardpoint.owner_ship.get_instance_id():
		return
	if w_id != weapon_id:
		return
	if hp_id != hardpoint.hardpoint_id:
		return
	_last_beam_endpoint = end
	_has_beam_endpoint = true
	if hit and _beam_renderer != null:
		_beam_renderer.trigger_hit_flash()


# ─── Helpers ─────────────────────────────────────────────────────────────────

func get_muzzle_pos() -> Vector3:
	var model := get_parent() as Node3D
	if model == null:
		return Vector3.ZERO

	var muzzle := model.get_node_or_null("Muzzle") as Node3D
	if muzzle == null:
		muzzle = model.get_node_or_null("WeaponModel/Muzzle") as Node3D
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
