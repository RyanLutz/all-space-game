extends Node3D
class_name BeamRenderer

## Local beam-visual renderer. Attached as child of WeaponModel by ShipFactory.
## WeaponComponent calls update() every frame while firing and stop() when done.
## Supports linger/fade-out, distance-based tip fade, and hit-flash.

var effect_id: String = ""
var _core_instance: MeshInstance3D = null
var _glow_instance: MeshInstance3D = null
var _active: bool = false
var _linger_timer: float = 0.0
var _linger_duration: float = 0.15
var _hit_flash_timer: float = 0.0


func _ready() -> void:
	if effect_id.is_empty():
		_build_beam({})
		return
	var sl := Engine.get_singleton("ServiceLocator")
	var content_registry: Node = sl.GetService("ContentRegistry")
	var def: Dictionary = content_registry.get_effect(effect_id)
	_build_beam(def)


func _process(delta: float) -> void:
	if _linger_timer > 0.0:
		_linger_timer -= delta
		var progress := clampf(_linger_timer / _linger_duration, 0.0, 1.0)
		if _core_instance != null:
			_core_instance.visible = progress > 0.0
		if _glow_instance != null:
			_glow_instance.visible = progress > 0.0
		_set_linger_progress(progress)
		if _linger_timer <= 0.0:
			_active = false
			if _core_instance != null:
				_core_instance.visible = false
			if _glow_instance != null:
				_glow_instance.visible = false
	
	if _hit_flash_timer > 0.0:
		_hit_flash_timer -= delta
		if _hit_flash_timer <= 0.0:
			_set_hit_intensity(0.0)


func update(from: Vector3, to: Vector3) -> void:
	if _core_instance == null:
		return
	var length := from.distance_to(to)
	if length < 0.001:
		return
	_active = true
	_core_instance.visible = true
	if _glow_instance != null:
		_glow_instance.visible = true
	var midpoint := (from + to) * 0.5
	midpoint.y = 0.0
	global_position = midpoint
	look_at(to, Vector3.UP)
	_core_instance.scale.z = length
	if _glow_instance != null:
		_glow_instance.scale.z = length
	
	# Reset linger — beam is actively firing
	_linger_timer = 0.0
	_set_linger_progress(1.0)


func stop() -> void:
	if not _active:
		return
	_active = false
	_linger_timer = _linger_duration
	# Don't hide immediately — _process will fade it out


func trigger_hit_flash(duration: float = 0.1) -> void:
	_hit_flash_timer = duration
	_set_hit_intensity(1.0)


func _set_linger_progress(progress: float) -> void:
	var mat := _get_core_material()
	if mat != null:
		mat.set_shader_parameter("u_linger_progress", progress)
	mat = _get_glow_material()
	if mat != null:
		mat.set_shader_parameter("u_linger_progress", progress)


func _set_hit_intensity(intensity: float) -> void:
	var mat := _get_core_material()
	if mat != null:
		mat.set_shader_parameter("u_hit_intensity", intensity)
	mat = _get_glow_material()
	if mat != null:
		mat.set_shader_parameter("u_hit_intensity", intensity)


func _get_core_material() -> ShaderMaterial:
	if _core_instance == null or _core_instance.mesh == null:
		return null
	return _core_instance.mesh.material as ShaderMaterial


func _get_glow_material() -> ShaderMaterial:
	if _glow_instance == null or _glow_instance.mesh == null:
		return null
	return _glow_instance.mesh.material as ShaderMaterial


func set_visual_params(alpha: float, linger_duration: float) -> void:
	_linger_duration = linger_duration
	var core_mat := _get_core_material()
	if core_mat != null:
		var color := core_mat.get_shader_parameter("beam_color") as Color
		if color != null:
			color.a = alpha
			core_mat.set_shader_parameter("beam_color", color)
	var glow_mat := _get_glow_material()
	if glow_mat != null:
		var color := glow_mat.get_shader_parameter("beam_color") as Color
		if color != null:
			color.a = alpha
			glow_mat.set_shader_parameter("beam_color", color)


func _build_beam(def: Dictionary) -> void:
	var color_core := _array_to_color(def.get("color_core", [0.55, 0.85, 1.0, 1.0]))
	var color_glow := _array_to_color(def.get("color_glow", [0.2, 0.5, 1.0, 0.4]))
	var width_core: float = float(def.get("width_core", 0.08))
	var width_glow: float = float(def.get("width_glow", 0.35))
	var flicker_hz: float = float(def.get("flicker_hz", 14.0))
	var alpha: float = float(def.get("alpha", 1.0))
	_linger_duration = float(def.get("linger_duration", 0.15))
	
	color_core.a *= alpha
	color_glow.a *= alpha

	var shader := preload("res://assets/shaders/beam_core.gdshader")

	# Core mesh — narrow, fully opaque
	var core_mesh := BoxMesh.new()
	core_mesh.size = Vector3(width_core, width_core, 1.0)
	var core_mat := ShaderMaterial.new()
	core_mat.shader = shader
	core_mat.set_shader_parameter("beam_color", color_core)
	core_mat.set_shader_parameter("flicker_hz", flicker_hz)
	core_mat.set_shader_parameter("u_linger_progress", 0.0)
	core_mat.set_shader_parameter("u_hit_intensity", 0.0)
	core_mesh.material = core_mat

	_core_instance = MeshInstance3D.new()
	_core_instance.mesh = core_mesh
	_core_instance.visible = false
	add_child(_core_instance)

	# Glow mesh — wider, additive blend, lower alpha
	var glow_mesh := BoxMesh.new()
	glow_mesh.size = Vector3(width_glow, width_glow, 1.0)
	var glow_mat := ShaderMaterial.new()
	glow_mat.shader = shader
	glow_mat.set_shader_parameter("beam_color", color_glow)
	glow_mat.set_shader_parameter("flicker_hz", flicker_hz)
	glow_mat.set_shader_parameter("u_linger_progress", 0.0)
	glow_mat.set_shader_parameter("u_hit_intensity", 0.0)
	glow_mesh.material = glow_mat

	_glow_instance = MeshInstance3D.new()
	_glow_instance.mesh = glow_mesh
	_glow_instance.visible = false
	add_child(_glow_instance)


func _array_to_color(arr) -> Color:
	if arr is Array and arr.size() >= 3:
		var a: float = 1.0 if arr.size() < 4 else float(arr[3])
		return Color(float(arr[0]), float(arr[1]), float(arr[2]), a)
	return Color.WHITE
