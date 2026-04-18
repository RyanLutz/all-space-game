extends Node3D
class_name GuidedProjectilePool

## Pool for guided missiles (heat-seeking, cursor-tracking, click-locked).
## Manages smaller pool of steerable projectiles with guidance modes.
## GDScript implementation — missiles are less numerous than bullets.

# ─── Configuration ───────────────────────────────────────────────────────────
@export var pool_capacity: int = 128
@export var collision_layer_mask: int = 0b1110  # Ship layer + debris + stations

# ─── Guided Projectile Data ────────────────────────────────────────────────────
var _projectiles: Array[GuidedProjectile] = []
var _active_count: int = 0

# ─── Service References ────────────────────────────────────────────────────────
var _event_bus: Node = null
var _perf: Node = null

# ─── Projectile Class ──────────────────────────────────────────────────────────
class GuidedProjectile:
	var position: Vector3         # Y always 0
	var velocity: Vector3         # Y always 0
	var target: Node3D            # Target reference (null for cursor tracking)
	var guidance_mode: String     # "track_cursor", "auto_lock", "click_lock"
	var turn_rate: float          # Degrees per second
	var fuel: float               # Seconds remaining
	var speed: float              # Constant speed magnitude
	var damage: float
	var damage_type: String
	var component_damage_ratio: float
	var owner_id: int
	var active: bool = false
	var lock_cone_degrees: float  # For auto_lock acquisition
	var blast_radius: float       # Area damage radius

# ─── Lifecycle ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	var service_locator := Engine.get_singleton("ServiceLocator")
	_event_bus = service_locator.GetService("GameEventBus")
	_perf = service_locator.GetService("PerformanceMonitor")

	# Pre-allocate pool
	for i in range(pool_capacity):
		_projectiles.append(GuidedProjectile.new())

	# Subscribe to spawn requests
	if _event_bus:
		_event_bus.connect("request_spawn_guided", _on_request_spawn_guided)

	print("[GuidedProjectilePool] Ready — capacity: ", pool_capacity)


func _physics_process(delta: float) -> void:
	_perf.begin("ProjectileManager.guided_update")
	_update_pool(delta)
	_perf.end("ProjectileManager.guided_update")

	_perf.begin("ProjectileManager.collision_checks")
	_process_collisions()
	_perf.end("ProjectileManager.collision_checks")

	_perf.set_count("ProjectileManager.active_count", _active_count)


# ─── Pool Update ───────────────────────────────────────────────────────────────
func _update_pool(delta: float) -> void:
	_active_count = 0

	for proj in _projectiles:
		if not proj.active:
			continue

		# Update fuel
		proj.fuel -= delta
		if proj.fuel <= 0.0:
			_deactivate(proj)
			continue

		# Compute steering
		var target_pos := _resolve_target_position(proj)
		var desired_dir := (target_pos - proj.position).normalized()
		desired_dir.y = 0.0

		var current_dir := proj.velocity.normalized()
		var max_turn_rad := deg_to_rad(proj.turn_rate) * delta

		# Slerp toward desired direction, clamped to turn rate
		var new_dir: Vector3
		if current_dir.dot(desired_dir) > 0.999:
			# Already aligned
			new_dir = desired_dir
		else:
			var turn_factor := clampf(max_turn_rad / current_dir.angle_to(desired_dir), 0.0, 1.0)
			new_dir = current_dir.slerp(desired_dir, turn_factor).normalized()

		new_dir.y = 0.0
		new_dir = new_dir.normalized()

		# Update velocity (maintains constant speed, changes direction)
		proj.velocity = new_dir * proj.speed

		# Update position
		proj.position += proj.velocity * delta
		proj.position.y = 0.0

		_active_count += 1


# ─── Target Resolution ─────────────────────────────────────────────────────────
func _resolve_target_position(proj: GuidedProjectile) -> Vector3:
	match proj.guidance_mode:
		"auto_lock", "click_lock":
			if proj.target != null and is_instance_valid(proj.target):
				var target_pos := proj.target.global_position
				target_pos.y = 0.0
				return target_pos
			# Target lost or null — fall through to cursor tracking

		"track_cursor", _:
			# Default to forward continuation if no target available
			# When PlayerState is implemented, this should query:
			# return PlayerState.get_active_ship().get_aim_world_pos()
			pass

	# Fallback: project forward based on current heading (dumb fire continuation)
	return proj.position + proj.velocity.normalized() * 1000.0


# ─── Collision Detection ───────────────────────────────────────────────────────
func _process_collisions() -> void:
	var space_state := get_world_3d().direct_space_state
	if space_state == null:
		return

	var delta := get_physics_process_delta_time()

	for proj in _projectiles:
		if not proj.active:
			continue

		# Sweep raycast from previous position to current position
		var prev_pos := proj.position - proj.velocity * delta
		prev_pos.y = 0.0

		# Skip zero-length rays
		if prev_pos.distance_squared_to(proj.position) < 0.0001:
			continue

		var query := PhysicsRayQueryParameters3D.new()
		query.from = prev_pos
		query.to = proj.position
		query.collision_mask = collision_layer_mask

		# Exclude owner ship
		var owner_node := instance_from_id(proj.owner_id) as PhysicsBody3D
		if owner_node != null:
			query.exclude = [owner_node.get_rid()]

		var result := space_state.intersect_ray(query)
		if result.is_empty():
			continue

		# Hit detected
		var collider := result.get("collider") as Node
		var hit_pos: Vector3 = result.get("position", proj.position)
		hit_pos.y = 0.0

		_apply_damage(proj, collider, hit_pos)
		_deactivate(proj)


# ─── Damage Application ────────────────────────────────────────────────────────
func _apply_damage(proj: GuidedProjectile, target: Node, hit_pos: Vector3) -> void:
	if target == null:
		return

	# Apply direct hit damage
	if target.has_method("apply_damage"):
		target.call("apply_damage", proj.damage, proj.damage_type, hit_pos, proj.component_damage_ratio)

	# Emit hit signal
	if _event_bus:
		_event_bus.emit_signal("projectile_hit", target, proj.damage, proj.damage_type, hit_pos, proj.component_damage_ratio)

	# Area damage if blast radius > 0
	if proj.blast_radius > 0.0:
		_trigger_explosion(hit_pos, proj)


# ─── Explosion (Area Damage) ───────────────────────────────────────────────────
func _trigger_explosion(explosion_position: Vector3, proj: GuidedProjectile) -> void:
	explosion_position.y = 0.0

	if _event_bus:
		_event_bus.emit_signal("explosion_triggered", explosion_position, proj.blast_radius, 1.0)

	# Query physics for nearby bodies in blast radius
	var space_state := get_world_3d().direct_space_state
	if space_state == null:
		return

	var query := PhysicsShapeQueryParameters3D.new()
	var shape := SphereShape3D.new()
	shape.radius = proj.blast_radius
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, explosion_position)
	query.collision_mask = collision_layer_mask

	var results := space_state.intersect_shape(query)
	for result in results:
		var collider := result.get("collider") as Node
		if collider == null:
			continue

		# Calculate distance-based falloff
		var collider_pos: Vector3
		if collider.has_method("global_position"):
			collider_pos = collider.global_position
		else:
			collider_pos = explosion_position
		var dist := explosion_position.distance_to(collider_pos)
		var falloff := clampf(1.0 - (dist / proj.blast_radius), 0.0, 1.0)
		var area_damage := proj.damage * falloff

		if area_damage > 0.0 and collider.has_method("apply_damage"):
			collider.call("apply_damage", area_damage, proj.damage_type, explosion_position, proj.component_damage_ratio)


# ─── Spawn Handling ──────────────────────────────────────────────────────────────
func _on_request_spawn_guided(
	spawn_position: Vector3,
	velocity: Vector3,
	guidance_mode: String,
	weapon_data: Dictionary,
	owner_id: int
) -> void:
	# Find inactive slot
	for proj in _projectiles:
		if proj.active:
			continue

		_activate_projectile(proj, spawn_position, velocity, guidance_mode, weapon_data, owner_id)
		return

	push_warning("[GuidedProjectilePool] Pool exhausted — guided missile dropped")


func _activate_projectile(
	proj: GuidedProjectile,
	spawn_position: Vector3,
	velocity: Vector3,
	guidance_mode: String,
	weapon_data: Dictionary,
	owner_id: int
) -> void:
	var stats: Dictionary = weapon_data.get("stats", {})

	proj.position = Vector3(spawn_position.x, 0.0, spawn_position.z)
	proj.velocity = Vector3(velocity.x, 0.0, velocity.z)
	proj.guidance_mode = guidance_mode
	proj.turn_rate = stats.get("turn_rate", 90.0)
	proj.fuel = stats.get("fuel", 4.0)
	proj.speed = proj.velocity.length() if velocity.length_squared() > 0.0001 else stats.get("speed", 420.0)
	proj.damage = stats.get("damage", 100.0)
	proj.damage_type = _resolve_damage_type(weapon_data)
	proj.component_damage_ratio = stats.get("component_damage_ratio", 0.2)
	proj.owner_id = owner_id
	proj.blast_radius = stats.get("blast_radius", 0.0)
	proj.lock_cone_degrees = stats.get("lock_cone_degrees", 60.0)
	proj.target = null
	proj.active = true

	# For auto_lock mode, acquire target immediately
	if guidance_mode == "auto_lock":
		_acquire_auto_lock(proj)

	_active_count += 1


func _deactivate(proj: GuidedProjectile) -> void:
	proj.active = false
	proj.target = null


# ─── Target Acquisition ────────────────────────────────────────────────────────
func _acquire_auto_lock(proj: GuidedProjectile) -> void:
	var best_target: Node3D = null
	var best_dot: float = cos(deg_to_rad(proj.lock_cone_degrees * 0.5))
	var launch_forward := proj.velocity.normalized()

	# Query all ships, exclude owner
	var owner_node := instance_from_id(proj.owner_id)
	var ships := get_tree().get_nodes_in_group("ships")
	for ship in ships:
		if not is_instance_valid(ship):
			continue
		if ship == owner_node:
			continue

		var to_ship: Vector3 = (ship.global_position - proj.position).normalized()
		to_ship.y = 0.0

		var dot := launch_forward.dot(to_ship)
		if dot >= best_dot:
			best_dot = dot
			best_target = ship

	proj.target = best_target


# ─── Helpers ───────────────────────────────────────────────────────────────────
func _resolve_damage_type(weapon_data: Dictionary) -> String:
	var archetype: String = weapon_data.get("archetype", "")
	if archetype.begins_with("missile"):
		return "missile"
	return archetype


# ─── Public API ────────────────────────────────────────────────────────────────
func get_active_count() -> int:
	return _active_count


func get_active_projectiles() -> Array[GuidedProjectile]:
	var active: Array[GuidedProjectile] = []
	for proj in _projectiles:
		if proj.active:
			active.append(proj)
	return active
