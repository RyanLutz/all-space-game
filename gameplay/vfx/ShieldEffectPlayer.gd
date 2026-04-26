extends Node3D
class_name ShieldEffectPlayer

## Attached as child of ShieldMesh by ShipFactory. Drives shield ripple shader
## on the parent MeshInstance3D's material when VFXManager forwards a shield_hit.
## Reads effect parameters from ContentRegistry; graceful no-op if none found.

var effect_id: String = ""
var _material: ShaderMaterial = null
var _flash_duration: float = 0.12


func _ready() -> void:
	var shield_mesh := get_parent() as MeshInstance3D
	if shield_mesh == null:
		return
	if shield_mesh.material_override is ShaderMaterial:
		_material = shield_mesh.material_override as ShaderMaterial

	if effect_id.is_empty() or _material == null:
		return
	var sl := Engine.get_singleton("ServiceLocator")
	var content_registry: Node = sl.GetService("ContentRegistry")
	var def: Dictionary = content_registry.get_effect(effect_id)
	if def.is_empty():
		return
	_flash_duration = float(def.get("flash_duration", 0.12))
	_apply_static_params(def)


func play_hit(hit_position_local: Vector3) -> void:
	if _material == null:
		return
	_material.set_shader_parameter("u_hit_origin", hit_position_local)
	_material.set_shader_parameter("u_hit_time", Time.get_ticks_msec() * 0.001)


func _apply_static_params(def: Dictionary) -> void:
	var color := _array_to_color(def.get("color", [0.4, 0.7, 1.0, 0.8]))
	_material.set_shader_parameter("u_color", color)
	_material.set_shader_parameter("u_ripple_speed", float(def.get("ripple_speed", 2.5)))
	_material.set_shader_parameter("u_ripple_falloff", float(def.get("ripple_falloff", 1.8)))


func _array_to_color(arr) -> Color:
	if arr is Array and arr.size() >= 3:
		var a: float = 1.0 if arr.size() < 4 else float(arr[3])
		return Color(float(arr[0]), float(arr[1]), float(arr[2]), a)
	return Color.WHITE
