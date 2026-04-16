class_name Asteroid
extends RigidBody3D

var _rng := RandomNumberGenerator.new()


func configure_random(rng: RandomNumberGenerator) -> void:
	_rng = rng
	mass = float(rng.randf_range(400.0, 1200.0))
	gravity_scale = 0.0
	axis_lock_linear_y = true
	linear_damp = 0.1
	angular_damp = 0.2
	collision_layer = 4
	collision_mask = 1 | 4
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE * rng.randf_range(6.0, 14.0)
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = shape.size
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.42, 0.35)
	mesh.material_override = mat
	add_child(mesh)
	add_to_group("physics_bodies")
	angular_velocity = Vector3(0.0, rng.randf_range(-0.4, 0.4), 0.0)


func _physics_process(_delta: float) -> void:
	var p := global_position
	p.y = 0.0
	global_position = p
	var v := linear_velocity
	v.y = 0.0
	linear_velocity = v
