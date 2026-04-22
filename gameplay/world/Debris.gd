extends Node3D
class_name Debris

## Lightweight visual fragment spawned when an asteroid is destroyed.
## No physics body — integrates velocity manually. Fades alpha over lifetime,
## then queue_frees itself.

var velocity: Vector3 = Vector3.ZERO
var lifetime: float = 3.5
var _elapsed: float = 0.0

@onready var _mesh: MeshInstance3D = $MeshInstance3D


func _process(delta: float) -> void:
	position += velocity * delta
	_elapsed += delta

	var t := clampf(_elapsed / lifetime, 0.0, 1.0)
	var mat := _mesh.get_active_material(0)
	if mat is StandardMaterial3D:
		mat.albedo_color.a = 1.0 - t

	if _elapsed >= lifetime:
		queue_free()
