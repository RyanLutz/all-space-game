extends Node2D

# GuidedProjectilePool - Manages guided missiles with different guidance modes
# Modes: track_cursor, auto_lock, click_lock

class GuidedProjectile:
	var position: Vector2
	var velocity: Vector2
	var target: Variant  # Node2D, Vector2, or null
	var guidance_mode: String  # "none", "track_cursor", "auto_lock", "click_lock"
	var turn_rate: float  # degrees per second
	var fuel: float  # seconds remaining
	var weapon_data: Dictionary
	var owner_id: int
	var active: bool = false
	var radius: float = 4.0  # collision radius

	func _init() -> void:
		position = Vector2.ZERO
		velocity = Vector2.ZERO
		target = null
		guidance_mode = "none"
		turn_rate = 90.0
		fuel = 4.0
		weapon_data = {}
		owner_id = 0
		active = false
		radius = 4.0


const MAX_GUIDED_PROJECTILES: int = 32

var _pool: Array[GuidedProjectile] = []
var _active_count: int = 0

var _perf_monitor: Node
var _event_bus: Node
var _collision_mask: int = 1

# Click-lock state (player's currently locked target)
var _player_locked_target: Node = null


func _ready() -> void:
	_perf_monitor = ServiceLocator.GetService("PerformanceMonitor") as Node
	_event_bus = ServiceLocator.GetService("GameEventBus") as Node

	# Weapon requests come through GameEventBus; this pool performs guided missile spawning.
	_event_bus.connect("request_spawn_guided", _on_request_spawn_guided)

	# Pre-allocate pool
	for i in range(MAX_GUIDED_PROJECTILES):
		_pool.append(GuidedProjectile.new())

	# Register custom monitor for guided count
	Performance.add_custom_monitor("AllSpace/projectiles_guided_active",
		func(): return get_active_count())

func _on_request_spawn_guided(pos: Vector2, vel: Vector2, guidance_mode: String, weapon_data: Dictionary, owner_id: int) -> void:
	# Actual spawn logic lives in spawn(); this handler keeps request payload decoupled from pool internals.
	spawn(pos, vel, guidance_mode, weapon_data, owner_id)


func spawn(pos: Vector2, vel: Vector2, guidance_mode: String, weapon_data: Dictionary, owner_id: int, target: Variant = null) -> int:
	# Find free slot
	var index := -1
	for i in range(MAX_GUIDED_PROJECTILES):
		if not _pool[i].active:
			index = i
			break

	if index < 0:
		return -1  # Pool full

	var p := _pool[index]
	p.position = pos
	p.velocity = vel
	p.guidance_mode = guidance_mode
	p.weapon_data = weapon_data
	p.owner_id = owner_id
	p.fuel = weapon_data.get("fuel", 4.0)
	p.turn_rate = weapon_data.get("turn_rate", 90.0)
	p.active = true

	# Resolve target based on guidance mode
	match guidance_mode:
		"auto_lock":
			p.target = _find_nearest_enemy(pos, vel.normalized(), owner_id)
		"click_lock":
			# Use player's currently locked target or find one
			if _player_locked_target != null and is_instance_valid(_player_locked_target):
				p.target = _player_locked_target
			else:
				p.target = _find_nearest_enemy(pos, vel.normalized(), owner_id)
		"track_cursor":
			# Target will be updated each frame to cursor position
			p.target = null
		_:
			p.target = null

	_active_count += 1

	# Debug/VFX hook: emit spawned projectile snapshot via the event bus.
	# Contract: projectile_spawned(position, velocity, weapon_data)
	_event_bus.emit_signal("projectile_spawned", pos, vel, weapon_data)

	_event_bus.emit_signal("missile_launched", weapon_data.get("id", ""), pos, p.target, owner_id)

	return index


func _physics_process(delta: float) -> void:
	if _active_count == 0:
		return

	_perf_monitor.begin("ProjectileManager.guided_update")

	var new_active := 0

	for i in range(MAX_GUIDED_PROJECTILES):
		var p := _pool[i]
		if not p.active:
			continue

		# Update fuel
		p.fuel -= delta
		if p.fuel <= 0:
			p.active = false
			continue

		# Steering
		_update_steering(p, delta)

		# Move
		var old_pos := p.position
		p.position += p.velocity * delta

		# Collision check
		if _check_collision(p, old_pos):
			continue

		new_active += 1

	_active_count = new_active

	# Update combined active count for PerformanceMonitor
	var dumb_count := 0
	if _perf_monitor:
		# Route dumb projectile count through PerformanceMonitor to avoid direct cross-system queries.
		dumb_count = _perf_monitor.get_count("ProjectileManager.active_count")
	_perf_monitor.set_count("ProjectileManager.active_count", dumb_count + _active_count)

	_perf_monitor.end("ProjectileManager.guided_update")


func _update_steering(p: GuidedProjectile, delta: float) -> void:
	var target_pos: Vector2

	# Resolve target position based on guidance mode
	match p.guidance_mode:
		"track_cursor":
			# Always track current cursor position
			var player_ship := _get_player_ship()
			if player_ship:
				target_pos = player_ship.get_global_mouse_position()
			else:
				target_pos = p.position + p.velocity.normalized() * 100.0
		"auto_lock", "click_lock":
			if p.target != null:
				if p.target is Node2D and is_instance_valid(p.target):
					target_pos = p.target.position
				elif p.target is Vector2:
					target_pos = p.target
				else:
					# Target lost - fly straight
					target_pos = p.position + p.velocity.normalized() * 100.0
			else:
				target_pos = p.position + p.velocity.normalized() * 100.0
		_:
			# No guidance - fly straight
			return

	# Calculate desired heading
	var desired_dir := (target_pos - p.position).normalized()
	var current_dir := p.velocity.normalized()
	var _current_speed := p.velocity.length()

	# Calculate angle difference
	var angle_diff := current_dir.angle_to(desired_dir)

	# Apply turn rate limit (same approach as ship assisted steering)
	var max_turn := deg_to_rad(p.turn_rate) * delta
	var actual_turn := clampf(angle_diff, -max_turn, max_turn)

	# Rotate velocity direction
	current_dir = current_dir.rotated(actual_turn)

	# Maintain speed from weapon data
	var target_speed: float = p.weapon_data.get("speed", 400.0)
	p.velocity = current_dir * target_speed


func _check_collision(p: GuidedProjectile, old_pos: Vector2) -> bool:
	var space_state: PhysicsDirectSpaceState2D = get_viewport().get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(old_pos, p.position, _collision_mask)
	query.collide_with_bodies = true
	query.collide_with_areas = false

	var result: Dictionary = space_state.intersect_ray(query)

	if not result.is_empty():
		var collider: Node = result.get("collider")
		if collider and collider.get_instance_id() != p.owner_id:
			var hit_point: Vector2 = result.get("position")
			var damage: float = p.weapon_data.get("damage", 100.0)
			var blast_radius: float = p.weapon_data.get("blast_radius", 50.0)

			# Apply damage
			if collider.has_method("apply_damage"):
				# Explosion - apply to all in radius
				_apply_explosion(hit_point, blast_radius, damage, p.owner_id, p.weapon_data)

			# Emit explosion VFX event
			_event_bus.emit_signal("explosion_triggered", hit_point, blast_radius, 1.0)

			p.active = false
			return true

	return false


func _apply_explosion(center: Vector2, blast_radius: float, base_damage: float, owner_id: int, weapon_data: Dictionary) -> void:
	# Find all ships in explosion radius
	var space_state: PhysicsDirectSpaceState2D = get_viewport().get_world_2d().direct_space_state

	# Use shape query for radius check
	var circle := CircleShape2D.new()
	circle.radius = blast_radius

	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.transform = Transform2D(0, center)
	query.collide_with_bodies = true
	query.collision_mask = _collision_mask

	var results: Array[Dictionary] = space_state.intersect_shape(query, 32)

	for res in results:
		var collider: Node = res.get("collider")
		if not collider or collider.get_instance_id() == owner_id:
			continue

		if collider.has_method("apply_damage"):
			# Falloff based on distance from center
			var c2 := collider as Node2D
			var sample_pos: Vector2 = c2.global_position if c2 else center
			var dist := center.distance_to(sample_pos)
			var falloff := 1.0 - clampf(dist / blast_radius, 0.0, 1.0)
			var damage := base_damage * falloff * falloff  # Square falloff
			var cdr: float = float(weapon_data.get("component_damage_ratio", 0.0))

			collider.call("apply_damage", damage, "missile", sample_pos, cdr)


func _find_nearest_enemy(pos: Vector2, forward_dir: Vector2, owner_id: int) -> Node:
	var nearest: Node = null
	var nearest_dist := 999999.0
	var max_range := 800.0
	var max_angle := deg_to_rad(45.0)

	for body in get_tree().get_nodes_in_group("ships"):
		if body.get_instance_id() == owner_id:
			continue

		# Cast to Node2D to access position
		var body2d := body as Node2D
		if body2d == null:
			continue

		var dist := pos.distance_to(body2d.position)
		if dist > max_range or dist > nearest_dist:
			continue

		# Check forward cone
		var dir_to_target: Vector2 = (body2d.position - pos).normalized()
		var angle_to_target := forward_dir.angle_to(dir_to_target)
		if absf(angle_to_target) > max_angle:
			continue

		nearest = body
		nearest_dist = dist

	return nearest


func _get_player_ship() -> Ship:
	for body in get_tree().get_nodes_in_group("ships"):
		if body is Ship and body.is_player_controlled:
			return body
	return null


func set_player_lock_target(target: Node) -> void:
	_player_locked_target = target


func get_active_count() -> int:
	return _active_count


func get_pool_stats() -> Dictionary:
	return {
		"active": _active_count,
		"max": MAX_GUIDED_PROJECTILES
	}


func get_active_projectiles_data() -> Array[Dictionary]:
	# Safe public getter for render/telemetry (no external access to private pool storage).
	var result: Array[Dictionary] = []
	for p in _pool:
		if not p.active:
			continue
		result.append({
			"position": p.position,
			"velocity": p.velocity
		})
	return result
