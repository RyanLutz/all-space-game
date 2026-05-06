class_name StarBody
extends Node3D

## Visual star node. Sphere mesh below play plane + OmniLight3D + exclusion ring.
## Damage logic deferred to Session B (Star exclusion zone).
## Position offset from system center is set by SolarSystem before calling setup().

var star_type: String = "yellow_dwarf"
var star_center_depth: float = 2000.0
var visual_radius: float = 3500.0
var exclusion_radius: float = 2800.0
var damage_per_second: float = 150.0
var light_energy: float = 1.2
var light_range: float = 100000.0

var _mesh_instance: MeshInstance3D
var _omni_light: OmniLight3D
var _exclusion_ring: MeshInstance3D


func setup(data: Dictionary) -> void:
	star_type          = data.get("star_type", "yellow_dwarf")
	star_center_depth  = float(data.get("star_center_depth", 2000.0))
	visual_radius      = float(data.get("visual_radius", 3500.0))
	exclusion_radius   = float(data.get("exclusion_radius", 2800.0))
	damage_per_second  = float(data.get("damage_per_second", 150.0))
	light_energy       = float(data.get("light_energy", 1.2))
	light_range        = float(data.get("light_range", 100000.0))
	_build_visuals()


func _build_visuals() -> void:
	# ── Star sphere mesh — center below play plane ───────────────────────────
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "StarMesh"
	_mesh_instance.position = Vector3(0.0, -star_center_depth, 0.0)

	var sphere := SphereMesh.new()
	sphere.radius = visual_radius
	sphere.height = visual_radius * 2.0
	sphere.radial_segments = 48
	sphere.rings = 24
	_mesh_instance.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = _star_color()
	mat.emission_enabled = true
	mat.emission = _star_color()
	mat.emission_energy_multiplier = 3.0
	_mesh_instance.material_override = mat
	add_child(_mesh_instance)

	# ── OmniLight ────────────────────────────────────────────────────────────
	_omni_light = OmniLight3D.new()
	_omni_light.name = "StarLight"
	_omni_light.position = Vector3(0.0, -star_center_depth * 0.1, 0.0)
	_omni_light.light_energy = light_energy
	_omni_light.omni_range = light_range
	_omni_light.light_color = _star_color()
	add_child(_omni_light)

	# ── Exclusion zone ring — flat disc at Y = 0 (visual indicator only) ────
	_exclusion_ring = MeshInstance3D.new()
	_exclusion_ring.name = "ExclusionRingMesh"
	_exclusion_ring.position = Vector3.ZERO

	var disc := CylinderMesh.new()
	disc.top_radius = exclusion_radius
	disc.bottom_radius = exclusion_radius
	disc.height = 6.0
	disc.radial_segments = 64

	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = Color(1.0, 0.25, 0.05, 0.45)
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_exclusion_ring.material_override = ring_mat
	_exclusion_ring.mesh = disc
	add_child(_exclusion_ring)


# ── Exclusion zone tracking ──────────────────────────────────────────────────
var _ships_inside: Dictionary = {}   # { ship_instance_id: bool }
var _event_bus: Node = null

func _ready() -> void:
	add_to_group("stars")
	var sl := Engine.get_singleton("ServiceLocator")
	if sl:
		_event_bus = sl.GetService("GameEventBus")


func _physics_process(delta: float) -> void:
	var ships := get_tree().get_nodes_in_group("ships")
	var my_pos_xz := Vector2(global_position.x, global_position.z)
	var star_idx := get_index()

	for ship in ships:
		if not is_instance_valid(ship):
			continue
		var ship_pos_xz := Vector2(ship.global_position.x, ship.global_position.z)
		var flat_dist := ship_pos_xz.distance_to(my_pos_xz)
		var was_inside: bool = _ships_inside.get(ship.get_instance_id(), false)
		var is_inside := flat_dist < exclusion_radius

		if is_inside:
			ship.apply_damage(damage_per_second * delta, "heat",
				ship.global_position, 0.0, 0)

		if is_inside and not was_inside:
			_ships_inside[ship.get_instance_id()] = true
			if _event_bus:
				_event_bus.exclusion_zone_entered.emit(ship, star_idx)
		elif was_inside and not is_inside:
			_ships_inside.erase(ship.get_instance_id())
			if _event_bus:
				_event_bus.exclusion_zone_exited.emit(ship, star_idx)


func _star_color() -> Color:
	match star_type:
		"yellow_dwarf":     return Color(1.00, 0.90, 0.40)
		"red_giant":        return Color(1.00, 0.30, 0.10)
		"neutron":          return Color(0.80, 0.90, 1.00)
		"white_dwarf":      return Color(0.95, 0.97, 1.00)
		"binary_primary":   return Color(1.00, 0.85, 0.35)
		"binary_secondary": return Color(1.00, 0.55, 0.20)
		_:                  return Color(1.00, 0.90, 0.40)
