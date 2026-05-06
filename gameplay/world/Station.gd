class_name StationPlacement
extends Node3D

## Station placement stub. Follows its parent planet automatically via scene tree.
## Docking, trading, and combat logic deferred to the Station spec.

var station_type: String = "generic"

var _mesh_instance: MeshInstance3D


func setup(data: Dictionary) -> void:
	station_type = data.get("station_type", "generic")
	_build_visual()


func _build_visual() -> void:
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "StationMesh"
	# Offset from planet surface — sits slightly above the play plane
	_mesh_instance.position = Vector3(800.0, 50.0, 0.0)

	var box := BoxMesh.new()
	box.size = Vector3(120.0, 40.0, 120.0)
	_mesh_instance.mesh = box

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.6, 0.65, 0.7)
	_mesh_instance.material_override = mat
	add_child(_mesh_instance)
