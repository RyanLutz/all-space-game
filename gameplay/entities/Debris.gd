class_name Debris
extends Node3D

## Short-lived visual debris (no collision). See core_spec §9.

var _lifetime: float = 2.0
var _velocity: Vector3 = Vector3.ZERO


func setup(velocity: Vector3, lifetime: float) -> void:
	_velocity = velocity
	_velocity.y = 0.0
	_lifetime = lifetime


func _process(delta: float) -> void:
	global_position += _velocity * delta
	var p := global_position
	p.y = 0.0
	global_position = p
	_lifetime -= delta
	if _lifetime <= 0.0:
		queue_free()
