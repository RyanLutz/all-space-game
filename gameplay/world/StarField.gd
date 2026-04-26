extends Node3D
class_name StarField

## Procedurally generated star field rendered as a large point-cloud ArrayMesh.
## Stars are real 3D geometry at genuine depth — the renderer provides true
## parallax for free as the camera moves. Generated once at startup; zero
## per-frame CPU cost after _ready().

var _perf: Node

# Config — loaded from data/world_config.json
var _star_count: int = 8000
var _spread_xz: float = 150000.0
var _spread_y: float = 8000.0
var _point_size: float = 2.0
var _brightness_min: float = 0.2
var _brightness_max: float = 1.0
var _seed: int = 42


func _ready() -> void:
	var service_locator := Engine.get_singleton("ServiceLocator")
	if service_locator:
		_perf = service_locator.GetService("PerformanceMonitor")

	_load_config()

	if _perf:
		_perf.begin("StarField.generate")
	var mesh := _generate_star_mesh()
	$MeshInstance3D.mesh = mesh
	var mat := $MeshInstance3D.material_override as ShaderMaterial
	if mat:
		mat.set_shader_parameter("point_size", _point_size)
	if _perf:
		_perf.end("StarField.generate")
		_perf.set_count("StarField.star_count", _star_count)


func _load_config() -> void:
	var file := FileAccess.open("res://data/world_config.json", FileAccess.READ)
	if file == null:
		push_error("[StarField] Failed to open data/world_config.json")
		return

	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("[StarField] JSON parse error in world_config.json: %s" % json.get_error_message())
		return

	var data: Dictionary = json.data
	var cfg: Dictionary = data.get("star_field", {})
	_star_count      = int(cfg.get("star_count", 8000))
	_spread_xz       = float(cfg.get("spread_xz", 150000.0))
	_spread_y        = float(cfg.get("spread_y", 8000.0))
	_point_size      = float(cfg.get("point_size", 2.0))
	_brightness_min  = float(cfg.get("brightness_min", 0.2))
	_brightness_max  = float(cfg.get("brightness_max", 1.0))
	_seed            = int(cfg.get("seed", 42))


func _generate_star_mesh() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed

	var verts  := PackedVector3Array()
	var colors := PackedColorArray()

	for i in _star_count:
		var pos := Vector3(
			rng.randf_range(-_spread_xz, _spread_xz),
			rng.randf_range(-_spread_y,  _spread_y),
			rng.randf_range(-_spread_xz, _spread_xz)
		)
		var brightness := rng.randf_range(_brightness_min, _brightness_max)
		verts.append(pos)
		colors.append(Color(1.0, 1.0, 1.0, brightness))

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR]  = colors

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays)
	return mesh
