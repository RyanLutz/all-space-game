class_name HardpointComponent
extends Node3D

var hardpoint_id: String = ""
var fire_group_indices: Array[int] = []
var arc_deg: float = 25.0
var hardpoint_type: String = "gimbal"
var hp_state: String = "nominal"


func setup(p_id: String, p_type: String, groups_from_json: Array) -> void:
	hardpoint_id = p_id
	hardpoint_type = p_type
	fire_group_indices.clear()
	for g in groups_from_json:
		if str(g) == "primary":
			fire_group_indices.append(0)
		elif str(g) == "secondary":
			fire_group_indices.append(1)
		elif str(g) == "missile" or str(g) == "tertiary":
			fire_group_indices.append(2)
	arc_deg = _default_arc_for_type(p_type)


func _default_arc_for_type(t: String) -> float:
	match t:
		"fixed":
			return 5.0
		"gimbal":
			return 25.0
		"partial_turret":
			return 120.0
		"full_turret":
			return 360.0
		_:
			return 25.0


func is_group_active(fire: Array[bool]) -> bool:
	for idx in fire_group_indices:
		if idx >= 0 and idx < fire.size() and fire[idx]:
			return true
	return false
