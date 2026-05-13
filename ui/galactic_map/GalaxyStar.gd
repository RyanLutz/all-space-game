class_name GalaxyStar
extends Area3D

## Individual mesh star for the close LOD tier. Selectable via collision shape.

var star_record: SFStarRecord

var _mesh_instance: MeshInstance3D
var _collision: CollisionShape3D
var _blend_alpha: float = 1.0

var _base_color: Color = Color.WHITE
var _reachable: bool = false


func _ready() -> void:
	# Simple emissive sphere
	_mesh_instance = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 2.0
	sphere.height = 4.0
	_mesh_instance.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = _base_color
	mat.disable_receive_shadows = true
	_mesh_instance.material_override = mat
	_mesh_instance.layers = 1
	add_child(_mesh_instance)

	_collision = CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 3.0
	_collision.shape = shape
	add_child(_collision)

	collision_layer = 1
	collision_mask = 0
	input_ray_pickable = true

	_update_appearance()


func setup(record: SFStarRecord) -> void:
	star_record = record
	_base_color = record.color
	if _mesh_instance:
		_update_appearance()


func set_blend_alpha(alpha: float) -> void:
	_blend_alpha = alpha
	if _mesh_instance and _mesh_instance.material_override:
		var mat: StandardMaterial3D = _mesh_instance.material_override
		mat.albedo_color.a = alpha
	_mesh_instance.visible = alpha > 0.01


func set_reachable(reachable: bool) -> void:
	if _reachable == reachable:
		return
	_reachable = reachable
	_update_appearance()


func set_selected(selected: bool) -> void:
	if not _mesh_instance or not _mesh_instance.material_override:
		return
	var mat: StandardMaterial3D = _mesh_instance.material_override
	if selected:
		mat.albedo_color = Color(0.25, 0.82, 1.0, _blend_alpha)
	else:
		_update_appearance()


func _update_appearance() -> void:
	if not _mesh_instance or not _mesh_instance.material_override:
		return
	var mat: StandardMaterial3D = _mesh_instance.material_override
	var c := _base_color
	if _reachable:
		c = c.lerp(Color(0.25, 0.82, 1.0), 0.3)
	mat.albedo_color = Color(c.r, c.g, c.b, _blend_alpha)
