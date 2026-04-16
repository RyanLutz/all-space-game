class_name NavigationController
extends Node

var _ship: Ship
var _destination: Vector3 = Vector3.ZERO
var _nav_active: bool = false
var _arrival_distance: float = 35.0

var _perf: Node


func setup(ship: Ship) -> void:
	_ship = ship
	_perf = ServiceLocator.GetService("PerformanceMonitor") as Node


func set_destination(world: Vector3) -> void:
	_destination = world
	_destination.y = 0.0
	_nav_active = true


func clear_destination() -> void:
	_nav_active = false
	if _ship != null:
		_ship.input_forward = 0.0
		_ship.input_strafe = 0.0


func is_navigating() -> bool:
	return _nav_active


func _physics_process(_delta: float) -> void:
	if _ship == null:
		return
	if _ship.control_source == "pilot":
		return
	if not _nav_active:
		return
	if _perf != null:
		_perf.begin("Navigation.update")
	var to_dest := _destination - _ship.global_position
	to_dest.y = 0.0
	if to_dest.length() < _arrival_distance:
		_ship.input_forward = 0.0
		_ship.input_strafe = 0.0
		if _perf != null:
			_perf.end("Navigation.update")
		return
	var world_dir := to_dest.normalized()
	var local_dir := _ship.global_transform.basis.inverse() * world_dir
	var fwd: float = -local_dir.z
	var strafe: float = local_dir.x
	_ship.input_forward = clampf(fwd, -1.0, 1.0)
	_ship.input_strafe = clampf(strafe, -1.0, 1.0)
	if _perf != null:
		_perf.end("Navigation.update")
