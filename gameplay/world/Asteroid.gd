extends SpaceBody
class_name Asteroid

# Asteroid — stationary collidable hazard that populates the streaming world.
# Extends SpaceBody so it registers on physics layer 1 and receives projectile hits
# via the same apply_damage() signature as Ship.gd.
#
# Configured by ChunkStreamer at spawn time via initialize().
# All HP and scale values come from data/world_config.json.
# See docs/ChunkStreamer_Spec.md.

@export var size_tier: String = "medium"
@export var hull_max: float = 100.0

var hull_hp: float = 100.0
var is_dead: bool = false

var _debris_scene: PackedScene = null
var _debris_lifetime: float = 3.5
var _debris_speed_min: float = 40.0
var _debris_speed_max: float = 160.0

@onready var _event_bus: Node = ServiceLocator.GetService("GameEventBus") as Node


## Called by ChunkStreamer before entering the scene tree.
func initialize(tier: String, hp_max: float, visual_scale: float,
		debris_scene: PackedScene, debris_cfg: Dictionary) -> void:
	size_tier = tier
	hull_max = hp_max
	hull_hp = hp_max
	scale = Vector2(visual_scale, visual_scale)
	_debris_scene = debris_scene
	_debris_lifetime = float(debris_cfg.get("lifetime", 3.5))
	_debris_speed_min = float(debris_cfg.get("speed_min", 40.0))
	_debris_speed_max = float(debris_cfg.get("speed_max", 160.0))


func _ready() -> void:
	super._ready()
	add_to_group("asteroids")
	_build_visual()
	_build_collision()


## Asteroids do not thrust — override to prevent SpaceBody from calling the default.
func apply_thrust_forces(_delta: float) -> void:
	pass


## Receives damage from projectile hits. Signature matches Ship.apply_damage so
## ProjectileManager can call it without knowing the node type.
func apply_damage(amount: float, _damage_type: String = "",
		_hit_pos: Vector2 = Vector2.ZERO, _comp_ratio: float = 0.0) -> void:
	if is_dead:
		return
	hull_hp = maxf(0.0, hull_hp - amount)
	if hull_hp <= 0.0:
		_destroy()


func _destroy() -> void:
	if is_dead:
		return
	is_dead = true

	var explosion_radius := _explosion_radius()
	if _event_bus != null:
		_event_bus.emit_signal("explosion_triggered", global_position, explosion_radius, 0.6)

	_spawn_debris()
	queue_free()


func _spawn_debris() -> void:
	if _debris_scene == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = Time.get_ticks_usec()
	var count: int = rng.randi_range(2, 5)
	for _i in range(count):
		var debris: Node2D = _debris_scene.instantiate()
		var angle := rng.randf() * TAU
		var speed := rng.randf_range(_debris_speed_min, _debris_speed_max)
		debris.velocity = Vector2(cos(angle), sin(angle)) * speed
		debris.lifetime = _debris_lifetime
		debris.global_position = global_position
		# Add to the chunk parent so debris doesn't outlive chunk unload.
		get_parent().add_child(debris)


func _explosion_radius() -> float:
	match size_tier:
		"large":  return 80.0
		"medium": return 50.0
		_:        return 30.0


func _build_visual() -> void:
	var poly := Polygon2D.new()
	# Irregular polygon approximating a rock silhouette.
	poly.polygon = PackedVector2Array([
		Vector2( 28.0,  -5.0),
		Vector2( 18.0, -22.0),
		Vector2(  0.0, -30.0),
		Vector2(-20.0, -18.0),
		Vector2(-30.0,   2.0),
		Vector2(-20.0,  22.0),
		Vector2(  5.0,  30.0),
		Vector2( 25.0,  15.0),
	])
	var gray := randf_range(0.35, 0.55)
	poly.color = Color(gray, gray * 0.95, gray * 0.9)
	add_child(poly)


func _build_collision() -> void:
	var body := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 28.0
	body.shape = shape
	add_child(body)
