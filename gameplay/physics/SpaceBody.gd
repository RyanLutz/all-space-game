extends CharacterBody2D
class_name SpaceBody

@export var mass: float = 100.0
@export var linear_drag: float = 0.5
@export var alignment_drag: float = 0.2
@export var max_speed: float = 300.0

var moment_of_inertia: float = 0.0
var angular_velocity: float = 0.0

# Guard so multiple SpaceBody instances only register the monitor once.
static var _monitors_registered := false

# PerformanceMonitor is registered on GameBootstrap via ServiceLocator.
@onready var _perf: Node = ServiceLocator.GetService("PerformanceMonitor") as Node


func _ready() -> void:
	add_to_group("space_bodies")
	moment_of_inertia = mass * 20.0 * 0.5  # 20.0 = assumed radius_sq placeholder

	if not _monitors_registered:
		_monitors_registered = true
		# AllSpace/physics_ms is already registered inside PerformanceMonitor._ready().
		# Only register the count monitor which is not yet registered there.
		Performance.add_custom_monitor("AllSpace/physics_bodies",
				func(): return _perf.get_count("Physics.active_bodies"))


func _physics_process(delta: float) -> void:
	apply_thrust_forces(delta)
	apply_alignment_drag(delta)
	apply_linear_drag(delta)
	apply_angular_drag(delta)

	rotation += angular_velocity * delta

	_perf.begin("Physics.move_and_slide")
	move_and_slide()
	_perf.end("Physics.move_and_slide")

	_perf.set_count("Physics.active_bodies",
			get_tree().get_nodes_in_group("space_bodies").size())


func apply_alignment_drag(delta: float) -> void:
	var heading := Vector2.RIGHT.rotated(rotation)
	var axial := heading * velocity.dot(heading)
	var lateral := velocity - axial
	lateral *= (1.0 - alignment_drag * delta)
	velocity = axial + lateral


func apply_linear_drag(delta: float) -> void:
	velocity *= (1.0 - linear_drag * delta)


func apply_angular_drag(delta: float) -> void:
	angular_velocity *= (1.0 - linear_drag * delta * 2.0)


# Virtual — override in subclasses. SpaceBody itself has no thrust source.
func apply_thrust_forces(_delta: float) -> void:
	pass


func get_velocity_for_projectile() -> Vector2:
	return velocity
