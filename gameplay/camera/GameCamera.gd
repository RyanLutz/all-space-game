class_name GameCamera
extends Camera3D

var _follow_target: Node3D = null
var _spring_vel: Vector3 = Vector3.ZERO
var _current_height: float = 520.0
var _target_height: float = 520.0

var _cfg: Dictionary = {}
var _perf: Node


func _ready() -> void:
	_perf = ServiceLocator.GetService("PerformanceMonitor") as Node
	_load_config()
	_current_height = float(_cfg.get("height_default_pilot", 520.0))
	_target_height = _current_height


func _load_config() -> void:
	var f := FileAccess.open("res://data/camera_config.json", FileAccess.READ)
	if f == null:
		_cfg = {}
		return
	var json := JSON.new()
	var err := json.parse(f.get_as_text())
	f.close()
	if err != OK:
		_cfg = {}
		return
	_cfg = json.data as Dictionary


func follow(target: Node3D) -> void:
	_follow_target = target


func set_mode_heights(pilot: bool) -> void:
	if pilot:
		_target_height = float(_cfg.get("height_default_pilot", 520.0))
	else:
		_target_height = float(_cfg.get("height_default_tactical", 900.0))


func _physics_process(delta: float) -> void:
	if _perf != null:
		_perf.begin("Camera.update")
	if _follow_target == null or not is_instance_valid(_follow_target):
		if _perf != null:
			_perf.end("Camera.update")
		return
	var dt := delta
	var angle_deg: float = float(_cfg.get("camera_angle_deg", 26.0))
	var smooth: float = float(_cfg.get("smoothing_speed", 12.0))
	var max_off: float = float(_cfg.get("max_cursor_offset", 140.0))
	var zoom_sm: float = float(_cfg.get("zoom_smoothing", 12.0))

	_current_height = lerpf(_current_height, _target_height, 1.0 - exp(-zoom_sm * dt))

	var mouse := get_viewport().get_mouse_position()
	var plane_hit: Variant = _mouse_to_world_on_plane(self, mouse)
	var target_pos: Vector3 = _follow_target.global_position
	target_pos.y = 0.0
	var cursor_off := Vector3.ZERO
	if plane_hit != null:
		var ph: Vector3 = plane_hit as Vector3
		ph.y = 0.0
		var delta_xz := ph - target_pos
		delta_xz.y = 0.0
		if delta_xz.length() > max_off:
			delta_xz = delta_xz.normalized() * max_off
		cursor_off = delta_xz * 0.35

	var look_target: Vector3 = target_pos + cursor_off
	var depth: float = _current_height * tan(deg_to_rad(angle_deg))
	var desired_cam: Vector3 = target_pos + Vector3(0.0, _current_height, depth)
	desired_cam = _spring_smooth(global_position, desired_cam, dt, smooth)

	global_position = desired_cam
	look_at(look_target, Vector3.UP)
	if _perf != null:
		_perf.end("Camera.update")


func _spring_smooth(from: Vector3, to: Vector3, dt: float, stiffness: float) -> Vector3:
	_spring_vel = _spring_vel.lerp(to - from, 1.0 - exp(-stiffness * dt))
	return from + _spring_vel * dt


func _mouse_to_world_on_plane(cam: Camera3D, screen_pos: Vector2) -> Variant:
	var ray_o := cam.project_ray_origin(screen_pos)
	var ray_d := cam.project_ray_normal(screen_pos)
	var plane := Plane(Vector3.UP, 0.0)
	var inter: Variant = plane.intersects_ray(ray_o, ray_d)
	return inter
