extends Node3D
class_name MuzzleFlashPlayer

## Local muzzle-flash effect player. Attached as child of WeaponModel by ShipFactory.
## Called directly by WeaponComponent — no GameEventBus interaction.
## Creates one GPUParticles3D instance at ready time; restart() per shot.
## pool_size == 0 in effect.json disables this player entirely.

var effect_id: String = ""
var _particles: GPUParticles3D = null
var _pool_size: int = 0
var _muzzle_marker: Node3D = null


func _ready() -> void:
	_muzzle_marker = get_parent().find_child("Muzzle", false, false) as Node3D
	if effect_id.is_empty():
		return
	var sl := Engine.get_singleton("ServiceLocator")
	var content_registry: Node = sl.GetService("ContentRegistry")
	var def: Dictionary = content_registry.get_effect(effect_id)
	if def.is_empty():
		return
	_pool_size = int(def.get("pool_size", 0))
	if _pool_size == 0:
		return
	_particles = _build_particles(def)
	add_child(_particles)


func play() -> void:
	if _pool_size == 0 or _particles == null:
		return
	if _muzzle_marker != null:
		_particles.global_position = _muzzle_marker.global_position
	else:
		_particles.global_position = global_position
	_particles.restart()


func _build_particles(def: Dictionary) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 1.0
	p.lifetime = float(def.get("lifetime", 0.2))
	p.amount = int(def.get("particle_count", 12))
	p.local_coords = false

	var mat := ParticleProcessMaterial.new()
	mat.gravity = Vector3.ZERO
	mat.initial_velocity_min = float(def.get("particle_speed_min", 15.0))
	mat.initial_velocity_max = float(def.get("particle_speed_max", 40.0))
	mat.scale_min = float(def.get("scale", 0.8)) * 0.5
	mat.scale_max = float(def.get("scale", 0.8))

	var emit_dir: String = def.get("emit_direction", "sphere")
	match emit_dir:
		"sphere":
			mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			mat.emission_sphere_radius = 0.05
			mat.direction = Vector3.ZERO
			mat.spread = 180.0
		"normal":
			mat.direction = Vector3.FORWARD
			mat.spread = 45.0
		_:
			mat.direction = Vector3.UP
			mat.spread = 90.0

	var color_primary := _array_to_color(def.get("color_primary", [1.0, 1.0, 0.5, 1.0]))
	mat.color = color_primary
	p.process_material = mat

	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.3, 0.3) * float(def.get("scale", 0.8))
	var draw_mat := StandardMaterial3D.new()
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	draw_mat.albedo_color = color_primary
	draw_mat.emission_enabled = true
	draw_mat.emission = Color(color_primary.r, color_primary.g, color_primary.b)
	draw_mat.emission_energy_multiplier = 3.0
	mesh.material = draw_mat
	p.draw_pass_1 = mesh

	return p


func _array_to_color(arr) -> Color:
	if arr is Array and arr.size() >= 3:
		var a: float = 1.0 if arr.size() < 4 else float(arr[3])
		return Color(float(arr[0]), float(arr[1]), float(arr[2]), a)
	return Color.WHITE
