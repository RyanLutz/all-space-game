extends Node2D
class_name Debris

# Debris — small drifting fragment spawned when an asteroid or ship is destroyed.
# Visual only: no collision, no physics body. Integrates its own velocity and fades
# out over its lifetime, then frees itself.
#
# Caller must set velocity and global_position before adding to scene tree.

var velocity: Vector2 = Vector2.ZERO
var lifetime: float = 3.5

var _elapsed: float = 0.0


func _ready() -> void:
	_build_visual()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= lifetime:
		queue_free()
		return

	global_position += velocity * delta

	var fade_start := lifetime * 0.5
	if _elapsed > fade_start:
		var t := (_elapsed - fade_start) / (lifetime - fade_start)
		modulate.a = 1.0 - t


func _build_visual() -> void:
	var poly := Polygon2D.new()
	# Small irregular triangle shape for debris fragments.
	poly.polygon = PackedVector2Array([
		Vector2(5.0, 0.0),
		Vector2(-3.0, -4.0),
		Vector2(-2.0, 4.0),
	])
	poly.color = Color(0.55, 0.45, 0.35)
	add_child(poly)
