extends Node3D

## PHASE 7 TEST BOOTSTRAPPER — Throwaway scaffolding for Weapon/Hardpoint testing.
## This is temporary test code to be deleted when ShipFactory (Step 9) is implemented.

@export var ship_path: NodePath

var _ship: Ship = null
var _camera: Camera3D = null
var _event_bus: Node = null
var _content_registry: Node = null

func _ready() -> void:
	_event_bus = ServiceLocator.GetService("GameEventBus")
	_content_registry = ServiceLocator.GetService("ContentRegistry")

	_ship = get_node(ship_path) as Ship
	if _ship == null:
		push_error("WeaponTest: No ship found at path %s" % ship_path)
		return

	_camera = get_node("Camera3D") as Camera3D
	if _camera == null:
		push_error("WeaponTest: No Camera3D found")
		return

	# Initialize ship stats
	var ship_data: Dictionary = _content_registry.get_ship("corvette_patrol")
	if not ship_data.is_empty():
		var base_stats: Dictionary = ship_data.get("base_stats", {})
		_ship.initialize_stats(base_stats)
		_ship.class_id = ship_data.get("ship_class", "")

	# Assemble hardpoints and weapons
	_assemble_hardpoints(ship_data)

	print("[WeaponTest] Bootstrap complete — hardpoints assembled")


func _assemble_hardpoints(ship_data: Dictionary) -> void:
	var hardpoint_types: Dictionary = ship_data.get("hardpoint_types", {})
	var default_loadout: Dictionary = ship_data.get("default_loadout", {})
	var weapons: Dictionary = default_loadout.get("weapons", {})
	var fire_groups: Dictionary = default_loadout.get("fire_groups", {})

	for hardpoint_id in hardpoint_types:
		var type: String = hardpoint_types[hardpoint_id]
		var weapon_id: String = weapons.get(hardpoint_id, "")

		# Find the hardpoint empty node
		var empty_name := "HardpointEmpty_%s_small" % hardpoint_id
		if type == "full_turret":
			empty_name = "HardpointEmpty_%s_medium" % hardpoint_id

		var hardpoint_empty := _ship.get_node_or_null("ShipVisual/%s" % empty_name) as Node3D
		if hardpoint_empty == null:
			push_warning("WeaponTest: Hardpoint empty '%s' not found" % empty_name)
			continue

		# Create HardpointComponent
		var hp_comp := preload("res://gameplay/weapons/HardpointComponent.gd").new()
		hp_comp.hardpoint_id = hardpoint_id
		hp_comp.hardpoint_type = type
		hp_comp.owner_ship = _ship

		# Set fire arc based on type
		match type:
			"fixed": hp_comp.fire_arc_degrees = 5.0
			"gimbal": hp_comp.fire_arc_degrees = 25.0
			"partial_turret": hp_comp.fire_arc_degrees = 120.0
			"full_turret": hp_comp.fire_arc_degrees = 360.0

		# Convert 1-based JSON fire groups to 0-based
		var groups: Array = fire_groups.get(hardpoint_id, []) as Array
		for g in groups:
			if g is int and g >= 1:
				hp_comp.fire_groups.append(g - 1)
			elif g is int:
				hp_comp.fire_groups.append(g)

		hardpoint_empty.add_child(hp_comp)

		# Create weapon model and WeaponComponent
		if not weapon_id.is_empty():
			_create_weapon(hp_comp, weapon_id)


func _create_weapon(hardpoint_comp: Node, weapon_id: String) -> void:
	var weapon_data: Dictionary = _content_registry.get_weapon(weapon_id)
	if weapon_data.is_empty():
		push_warning("WeaponTest: Weapon '%s' not found" % weapon_id)
		return

	var archetype: String = weapon_data.get("archetype", "")
	var hardpoint_empty := hardpoint_comp.get_parent() as Node3D

	# Create weapon model (MeshInstance3D or imported model)
	var weapon_model: Node3D = null
	var model_path: String = weapon_data.get("assets", {}).get("model", "")

	if not model_path.is_empty():
		# Try to load the model
		var full_path := "res://content/weapons/%s/%s" % [weapon_id, model_path]
		if ResourceLoader.exists(full_path):
			weapon_model = load(full_path).instantiate() as Node3D

	# If no model loaded, create a placeholder
	if weapon_model == null:
		weapon_model = MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.3, 0.2, 0.6)
		(weapon_model as MeshInstance3D).mesh = mesh

		# Add Muzzle marker
		var muzzle := Marker3D.new()
		muzzle.name = "Muzzle"
		muzzle.position = Vector3(0, 0, -0.4)  # Forward on Z axis
		weapon_model.add_child(muzzle)

	hardpoint_empty.add_child(weapon_model)

	# Create and configure WeaponComponent
	var weapon_comp := preload("res://gameplay/weapons/WeaponComponent.gd").new()
	weapon_comp.weapon_id = weapon_id
	weapon_comp.initialize_from_data(weapon_data)
	weapon_model.add_child(weapon_comp)
	hardpoint_comp.set_weapon_model(weapon_model, weapon_comp)

	print("[WeaponTest] Mounted %s (%s) on %s" % [weapon_id, archetype, hardpoint_comp.hardpoint_id])


func _input(event: InputEvent) -> void:
	if _ship == null:
		return

	# Mouse aim
	if event is InputEventMouseMotion:
		var mouse_pos := get_viewport().get_mouse_position()
		var plane := Plane(Vector3.UP, 0.0)
		var ray_origin := _camera.project_ray_origin(mouse_pos)
		var ray_dir := _camera.project_ray_normal(mouse_pos)
		var intersect: Variant = plane.intersects_ray(ray_origin, ray_dir)
		if intersect != null:
			_ship.input_aim_target = intersect as Vector3

	# Fire groups
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_ship.input_fire[0] = event.pressed  # Group 1 (Primary)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_ship.input_fire[1] = event.pressed  # Group 2 (Secondary)


func _process(_delta: float) -> void:
	# Visual feedback: move aim cursor
	var aim_cursor := get_node_or_null("AimCursor") as MeshInstance3D
	if aim_cursor != null and _ship != null:
		aim_cursor.position = _ship.input_aim_target
