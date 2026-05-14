class_name GalaxyBillboardField
extends MultiMeshInstance3D

## Manages the MultiMeshInstance3D for all billboard-tier stars.

var _multimesh: MultiMesh
var _instance_map: Dictionary = {}   # star.id -> instance index
var _galaxy_scale: float = 100.0
var _billboard_pixel_size: float = 0.01


func _ready() -> void:
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_colors = true
	_multimesh.use_custom_data = true
	multimesh = _multimesh

	var quad := QuadMesh.new()
	quad.size = Vector2(_billboard_pixel_size, _billboard_pixel_size)
	_multimesh.mesh = quad

	var mat := ShaderMaterial.new()
	mat.shader = preload("res://ui/galactic_map/galaxy_billboard.gdshader")
	material_override = mat

	layers = 1


func set_galaxy_scale(scale: float) -> void:
	_galaxy_scale = scale


func set_billboard_pixel_size(size: float) -> void:
	_billboard_pixel_size = size


func populate(stars: Array, _camera_pos: Vector3) -> void:
	_multimesh.instance_count = stars.size()
	_instance_map.clear()

	for i in stars.size():
		var star: SFStarRecord = stars[i]
		var pos := star.galaxy_position / _galaxy_scale

		_multimesh.set_instance_transform(i,
			Transform3D(Basis(), pos))
		_multimesh.set_instance_color(i,
			Color(star.color.r, star.color.g, star.color.b, star.brightness))
		_multimesh.set_instance_custom_data(i,
			Color(1.0, float(star.is_destination), 0.0, 0.0))

		_instance_map[star.id] = i


func set_instance_alpha(star_id: int, alpha: float) -> void:
	if not _instance_map.has(star_id):
		return
	var i: int = _instance_map[star_id]
	var cur := _multimesh.get_instance_custom_data(i)
	cur.r = alpha
	_multimesh.set_instance_custom_data(i, cur)


func clear() -> void:
	if _multimesh:
		_multimesh.instance_count = 0
	_instance_map.clear()


func instance_count() -> int:
	return _multimesh.instance_count if _multimesh else 0
