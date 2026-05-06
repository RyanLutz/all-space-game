class_name PlanetBody
extends Node3D

## Planetary body with orbital drift. Visual only — no physics collider.
## When moon_mode = true, orbits its parent PlanetBody instead of system center.
## Mesh center sits at Y = -planet_depth (below play plane); ships fly over.

var planet_type: String   = "terrestrial"
var orbit_radius: float   = 5000.0
var orbit_angle: float    = 0.0
var orbit_speed: float    = 0.005
var planet_depth: float   = 800.0
var visual_radius: float  = 600.0
var moon_mode: bool        = false

var _mesh_instance: MeshInstance3D


func setup(data: Dictionary, is_moon: bool = false) -> void:
	planet_type   = data.get("planet_type", "terrestrial")
	orbit_radius  = float(data.get("orbit_radius", 5000.0))
	orbit_angle   = float(data.get("orbit_angle", 0.0))
	orbit_speed   = float(data.get("orbit_speed", 0.005))
	planet_depth  = float(data.get("planet_depth", 800.0))
	visual_radius = float(data.get("visual_radius", 600.0))
	moon_mode     = is_moon
	_build_visual()


func _build_visual() -> void:
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "PlanetMesh"
	# Mesh center at the planet node's position (node itself sits at Y = -planet_depth)
	_mesh_instance.position = Vector3.ZERO

	var sphere := SphereMesh.new()
	sphere.radius = visual_radius
	sphere.height = visual_radius * 2.0
	sphere.radial_segments = 32
	sphere.rings = 16
	_mesh_instance.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = _planet_color()
	_mesh_instance.material_override = mat
	add_child(_mesh_instance)


func _process(delta: float) -> void:
	orbit_angle += orbit_speed * delta
	var c := _get_orbit_center()
	global_position = Vector3(
		c.x + cos(orbit_angle) * orbit_radius,
		c.y - planet_depth,
		c.z + sin(orbit_angle) * orbit_radius)


func _get_orbit_center() -> Vector3:
	if moon_mode:
		var p := get_parent()
		# Walk up past intermediate group nodes to the parent PlanetBody
		while p != null and not (p is PlanetBody):
			p = p.get_parent()
		if p is PlanetBody:
			var pp: Vector3 = (p as PlanetBody).global_position
			# Y = 0 so the formula `center.y - moon.planet_depth` gives
			# moon.global_pos.y = -moon.planet_depth (below play plane).
			return Vector3(pp.x, 0.0, pp.z)
	return Vector3.ZERO


func _planet_color() -> Color:
	match planet_type:
		"terrestrial": return Color(0.20, 0.50, 0.25)
		"gas_giant":   return Color(0.70, 0.50, 0.20)
		"ice":         return Color(0.72, 0.86, 0.95)
		"barren":      return Color(0.45, 0.40, 0.35)
		"molten":      return Color(0.80, 0.20, 0.05)
		_:             return Color(0.40, 0.40, 0.50)
