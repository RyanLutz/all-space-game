extends Node3D
class_name BeamRenderer

## Local beam-visual renderer. Attached as child of WeaponModel by ShipFactory.
## WeaponComponent calls update() every physics frame while firing and stop() when done.
## Placeholder uses StandardMaterial3D with emission; shader pass upgrades this later.

var effect_id: String = ""
var _mesh_instance: MeshInstance3D = null
var _material: ShaderMaterial = null  # set only if a real ShaderMaterial is used
var _active: bool = false


func _ready() -> void:
	if effect_id.is_empty():
		_build_beam({})
		return
	var sl := Engine.get_singleton("ServiceLocator")
	var content_registry: Node = sl.GetService("ContentRegistry")
	var def: Dictionary = content_registry.get_effect(effect_id)
	_build_beam(def)


func update(from: Vector3, to: Vector3) -> void:
	if _mesh_instance == null:
		return
	var length := from.distance_to(to)
	if length < 0.001:
		return
	_active = true
	_mesh_instance.visible = true
	var midpoint := (from + to) * 0.5
	midpoint.y = 0.0
	global_position = midpoint
	look_at(to, Vector3.UP)
	_mesh_instance.scale.z = length
	if _material != null:
		_material.set_shader_parameter("u_time_offset", randf() * TAU)


func stop() -> void:
	_active = false
	if _mesh_instance != null:
		_mesh_instance.visible = false


func _build_beam(def: Dictionary) -> void:
	var color_core := _array_to_color(def.get("color_core", [0.55, 0.85, 1.0, 1.0]))
	var width_core: float = float(def.get("width_core", 0.08))

	var mesh := BoxMesh.new()
	mesh.size = Vector3(width_core, width_core, 1.0)

	var draw_mat := StandardMaterial3D.new()
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.albedo_color = color_core
	draw_mat.emission_enabled = true
	draw_mat.emission = Color(color_core.r, color_core.g, color_core.b)
	draw_mat.emission_energy_multiplier = 4.0
	mesh.material = draw_mat

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = mesh
	_mesh_instance.visible = false
	add_child(_mesh_instance)


func _array_to_color(arr) -> Color:
	if arr is Array and arr.size() >= 3:
		var a: float = 1.0 if arr.size() < 4 else float(arr[3])
		return Color(float(arr[0]), float(arr[1]), float(arr[2]), a)
	return Color.WHITE
