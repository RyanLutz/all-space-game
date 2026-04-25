extends Node
class_name VFXManager

## Autoload owner of world-space effect pools (impacts, sub-explosions).
## Subscribes to GameEventBus combat signals; spawns from pools in world space.
## Local effects (muzzle flashes, beams, shield ripple) are owned by their
## host nodes and called directly by WeaponComponent / VFXManager forwarding.
##
## Explosion lookup model: VFXManager caches `ship.get_instance_id() ->
## explosion_id` on `ship_spawned`. On `ship_destroyed` it looks up its own
## cache without touching the (possibly already-freed) ship node.

var _content_registry: Node
var _event_bus: Node
var _perf: Node

var _pools: Dictionary = {}                 # effect_id (String) -> EffectPool
var _ship_explosion_cache: Dictionary = {}  # int instance_id -> String explosion_id
var _ship_shield_cache: Dictionary = {}     # int instance_id -> String shield_hit_id


func _ready() -> void:
	var service_locator := Engine.get_singleton("ServiceLocator")
	_content_registry = service_locator.GetService("ContentRegistry")
	_event_bus = service_locator.GetService("GameEventBus")
	_perf = service_locator.GetService("PerformanceMonitor")

	_event_bus.projectile_hit.connect(_on_projectile_hit)
	_event_bus.shield_hit.connect(_on_shield_hit)
	_event_bus.ship_destroyed.connect(_on_ship_destroyed)
	_event_bus.missile_detonated.connect(_on_missile_detonated)
	_event_bus.ship_spawned.connect(_on_ship_spawned)

	_build_pools()


func _process(_delta: float) -> void:
	_perf.begin("VFXManager.pool_reclaim")
	# GPUParticles3D self-recycles via one_shot + emitting flag; nothing to
	# manually reclaim. The metric is kept for future ring-buffer audits.
	_perf.end("VFXManager.pool_reclaim")
	_perf.set_count("VFXManager.active_effects", _count_active())


# ─── Pool Construction ──────────────────────────────────────────────────────

func _build_pools() -> void:
	_perf.begin("VFXManager.pool_build")

	var effect_ids: Array = _content_registry.get_all_ids("effects")
	var built := 0
	for id in effect_ids:
		var def: Dictionary = _content_registry.get_effect(id)
		if def.is_empty():
			continue
		var type: String = def.get("type", "")
		var pool_size: int = int(def.get("pool_size", 0))
		if pool_size <= 0:
			continue
		if type != "particle_burst":
			# Only world-space particle bursts are pooled here. Beams, shield
			# ripples, and explosion containers are handled differently.
			continue

		var pool := EffectPool.new()
		pool.effect_id = id
		pool.preload_pool(pool_size, self, def)
		_pools[id] = pool
		built += 1

	_perf.end("VFXManager.pool_build")
	print("[VFXManager] Built %d pools" % built)


func _count_active() -> int:
	var n := 0
	for id in _pools:
		var pool: EffectPool = _pools[id]
		n += pool.count_active()
	return n


# ─── Spawning ───────────────────────────────────────────────────────────────

func spawn_effect(effect_id: String, position: Vector3, normal: Vector3 = Vector3.UP) -> void:
	if not _pools.has(effect_id):
		return
	var instance: GPUParticles3D = _pools[effect_id].acquire()
	if instance == null:
		return
	position.y = 0.0
	instance.global_position = position
	instance.global_transform.basis = _basis_from_normal(normal)
	instance.restart()


func spawn_explosion(explosion_id: String, position: Vector3) -> void:
	position.y = 0.0
	var def: Dictionary = _content_registry.get_effect(explosion_id)
	if def.is_empty():
		return
	if def.get("type", "") != "explosion":
		push_warning("[VFXManager] '%s' is not an explosion" % explosion_id)
		return
	_perf.begin("VFXManager.explosion_spawn")
	_sequence_explosion(def.get("layers", []), position)
	_perf.end("VFXManager.explosion_spawn")


func _sequence_explosion(layers: Array, position: Vector3) -> void:
	for layer in layers:
		var effect_id: String = layer.get("effect", "")
		var delay: float = float(layer.get("delay", 0.0))
		var scale: float = float(layer.get("scale", 1.0))
		if delay > 0.0:
			await get_tree().create_timer(delay).timeout
		if not _pools.has(effect_id):
			continue
		var instance: GPUParticles3D = _pools[effect_id].acquire()
		if instance == null:
			continue
		instance.global_position = position
		instance.scale = Vector3.ONE * scale
		instance.global_transform.basis = Basis()
		instance.restart()


# ─── Signal Handlers ────────────────────────────────────────────────────────

func _on_projectile_hit(position: Vector3, normal: Vector3, surface_type: String) -> void:
	var effect_id := "impact_hull" if surface_type == "hull" else "impact_shield"
	spawn_effect(effect_id, position, normal)


func _on_shield_hit(ship: Node3D, hit_position_local: Vector3) -> void:
	if ship == null or not is_instance_valid(ship):
		return
	# Forward to local ShieldEffectPlayer; ship-local effects own their own
	# state. Skip silently if the host has no shield mesh (e.g., shield_max==0
	# or shield player not yet implemented).
	var shield_player: Node = ship.find_child("ShieldEffectPlayer", true, false)
	if shield_player != null and shield_player.has_method("play_hit"):
		shield_player.play_hit(hit_position_local)


func _on_ship_destroyed(ship: Node, position: Vector3, _faction: String) -> void:
	var id: int = ship.get_instance_id() if ship != null else 0
	var explosion_id: String = _ship_explosion_cache.get(id, "")
	_ship_explosion_cache.erase(id)
	_ship_shield_cache.erase(id)
	if explosion_id.is_empty():
		return
	spawn_explosion(explosion_id, position)


func _on_missile_detonated(position: Vector3, explosion_id: String) -> void:
	if explosion_id.is_empty():
		return
	spawn_explosion(explosion_id, position)


func _on_ship_spawned(ship: Node) -> void:
	if ship == null:
		return
	var class_id: String = ship.get("class_id") if "class_id" in ship else ""
	if class_id.is_empty():
		return
	var class_data: Dictionary = _content_registry.get_ship(class_id)
	var effects: Dictionary = class_data.get("effects", {})
	var explosion_id: String = effects.get("explosion", "")
	if not explosion_id.is_empty():
		_ship_explosion_cache[ship.get_instance_id()] = explosion_id
	var shield_id: String = effects.get("shield_hit", "")
	if not shield_id.is_empty():
		_ship_shield_cache[ship.get_instance_id()] = shield_id


# ─── Helpers ────────────────────────────────────────────────────────────────

func _basis_from_normal(normal: Vector3) -> Basis:
	# Build an orthonormal basis with +Y aligned to the surface normal so that
	# ParticleProcessMaterial.direction (Vector3.UP local) emits along the
	# normal in world space.
	if normal.length_squared() < 0.0001:
		return Basis()
	var n := normal.normalized()
	var ref := Vector3.FORWARD if absf(n.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var x := ref.cross(n).normalized()
	var z := n.cross(x).normalized()
	return Basis(x, n, z)
