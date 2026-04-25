extends RefCounted
class_name EffectPool

## Generic ring-buffer pool of GPUParticles3D instances for one effect_id.
## When the pool is exhausted, the oldest instance is silently recycled —
## a missed muzzle flash or impact spark is visually invisible at speed.
##
## Pool members are not parented to a game entity; they live under VFXManager
## as a flat list and are positioned in world-space at acquire time.

var effect_id: String = ""
var _instances: Array[GPUParticles3D] = []
var _next: int = 0


func preload_pool(count: int, parent: Node, effect_def: Dictionary) -> void:
	for i in count:
		var p := _build_instance(effect_def)
		parent.add_child(p)
		_instances.append(p)


func acquire() -> GPUParticles3D:
	if _instances.is_empty():
		return null
	var inst := _instances[_next]
	_next = (_next + 1) % _instances.size()
	return inst


func size() -> int:
	return _instances.size()


func count_active() -> int:
	var n := 0
	for inst in _instances:
		if inst.emitting:
			n += 1
	return n


# ─── Instance Construction ──────────────────────────────────────────────────

func _build_instance(def: Dictionary) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 1.0
	p.lifetime = float(def.get("lifetime", 0.35))
	p.amount = int(def.get("particle_count", 16))
	p.local_coords = false

	var mat := ParticleProcessMaterial.new()
	mat.gravity = Vector3.ZERO
	mat.initial_velocity_min = float(def.get("particle_speed_min", 20.0))
	mat.initial_velocity_max = float(def.get("particle_speed_max", 60.0))
	mat.scale_min = float(def.get("scale", 1.0)) * 0.5
	mat.scale_max = float(def.get("scale", 1.0))

	var emit_dir: String = def.get("emit_direction", "sphere")
	match emit_dir:
		"sphere":
			mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			mat.emission_sphere_radius = 0.05
			mat.direction = Vector3.ZERO
			mat.spread = 180.0
		"normal":
			# Surface normal = local +Y after VFXManager aligns basis
			mat.direction = Vector3.UP
			mat.spread = 35.0
		_:
			mat.direction = Vector3.UP
			mat.spread = 90.0

	var color_primary: Color = _array_to_color(
		def.get("color_primary", [1.0, 1.0, 1.0, 1.0])
	)
	mat.color = color_primary

	p.process_material = mat

	# Default mesh — small quad billboard placeholder; art pass replaces.
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.5, 0.5) * float(def.get("scale", 1.0))
	var draw_mat := StandardMaterial3D.new()
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	draw_mat.albedo_color = color_primary
	draw_mat.emission_enabled = true
	draw_mat.emission = Color(color_primary.r, color_primary.g, color_primary.b)
	draw_mat.emission_energy_multiplier = 2.0
	mesh.material = draw_mat
	p.draw_pass_1 = mesh

	return p


func _array_to_color(arr) -> Color:
	if arr is Array and arr.size() >= 3:
		var a: float = 1.0 if arr.size() < 4 else float(arr[3])
		return Color(float(arr[0]), float(arr[1]), float(arr[2]), a)
	return Color.WHITE
