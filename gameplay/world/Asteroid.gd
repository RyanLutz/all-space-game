extends SpaceBody
class_name Asteroid

## A destructible asteroid. Extends SpaceBody (RigidBody3D) with Jolt axis locks
## to stay on the XZ play plane. Procedurally created by ChunkStreamer — no .tscn needed.
## apply_damage signature matches Ship so the projectile hit pipeline works without branching.

const _DEBRIS_SCENE: PackedScene = preload("res://gameplay/world/Debris.tscn")

var hull_hp: float = 100.0
var hull_max: float = 100.0
var size_tier: String = "medium"

# Debris config — set by ChunkStreamer from world_config.json
var _debris_count_min: int = 2
var _debris_count_max: int = 5
var _debris_speed_min: float = 40.0
var _debris_speed_max: float = 160.0
var _debris_lifetime: float = 3.5

var _event_bus: Node
var _mesh: MeshInstance3D


func _ready() -> void:
	# Jolt axis locks — stay on XZ play plane
	axis_lock_linear_y = true
	axis_lock_angular_x = true
	axis_lock_angular_z = true

	# Random slow yaw spin for visual variety
	angular_velocity = Vector3(0.0, randf_range(-0.3, 0.3), 0.0)

	add_to_group("asteroids")

	var service_locator := Engine.get_singleton("ServiceLocator")
	if service_locator:
		_event_bus = service_locator.GetService("GameEventBus")


func _physics_process(_delta: float) -> void:
	enforce_play_plane()


func apply_damage(amount: float, _damage_type: String = "",
				  _hit_pos: Vector3 = Vector3.ZERO,
				  _component_ratio: float = 0.0,
				  _attacker_id: int = 0) -> void:
	hull_hp = maxf(0.0, hull_hp - amount)
	if hull_hp <= 0.0:
		_destroy()


func setup_mesh(scale_factor: float) -> void:
	_mesh = MeshInstance3D.new()
	_mesh.name = "MeshInstance3D"

	var sphere := SphereMesh.new()
	sphere.radius = 5.0 * scale_factor
	sphere.height = 10.0 * scale_factor
	_mesh.mesh = sphere

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.45, 0.4, 0.35)
	material.roughness = 0.9
	_mesh.material_override = material

	add_child(_mesh)

	# Collision shape sized to match the mesh
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := SphereShape3D.new()
	shape.radius = 5.0 * scale_factor
	collision.shape = shape
	add_child(collision)

	# Mass scales with size
	mass = 10.0 * scale_factor * scale_factor


func _destroy() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = Time.get_ticks_usec()

	var debris_count := rng.randi_range(_debris_count_min, _debris_count_max)

	for _i in range(debris_count):
		var debris: Node3D = _DEBRIS_SCENE.instantiate()
		var angle := rng.randf() * TAU
		var speed := rng.randf_range(_debris_speed_min, _debris_speed_max)
		debris.velocity = Vector3(cos(angle), 0.0, sin(angle)) * speed \
						+ linear_velocity * 0.3
		debris.velocity.y = 0.0
		debris.lifetime = _debris_lifetime
		debris.global_position = global_position
		# Add as sibling under chunk node
		get_parent().add_child(debris)

	if _event_bus:
		_event_bus.explosion_triggered.emit(
			global_position, _explosion_radius_by_tier(), 0.6)

	queue_free()


func _explosion_radius_by_tier() -> float:
	match size_tier:
		"small":
			return 8.0
		"medium":
			return 15.0
		"large":
			return 25.0
	return 15.0
