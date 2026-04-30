extends Node
class_name ShipFactory

## Spawns ships from JSON data. One Ship.tscn for all types — configuration
## happens entirely at spawn time from class/variant data.

var _content_registry: Node
var _player_state: Node
var _perf: Node
var _event_bus: Node

func _ready() -> void:
	var service_locator := Engine.get_singleton("ServiceLocator")
	_content_registry = service_locator.GetService("ContentRegistry")
	_player_state = service_locator.GetService("PlayerState")
	_perf = service_locator.GetService("PerformanceMonitor")
	_event_bus = service_locator.GetService("GameEventBus")


# ─── Public API ─────────────────────────────────────────────────────────────

func spawn_ship(
	class_id: String,
	variant_id: String,
	pos: Vector3,
	faction: String,
	is_player: bool = false,
	weapon_loadout_override: Dictionary = {},
	ai_profile_id: String = "default"
) -> RigidBody3D:
	var class_data: Dictionary = _content_registry.get_ship(class_id)
	if class_data.is_empty():
		push_error("ShipFactory: unknown class '%s'" % class_id)
		return null

	if not class_data["variants"].has(variant_id):
		push_error("ShipFactory: unknown variant '%s' for class '%s'" % [variant_id, class_id])
		return null

	_perf.begin("ShipFactory.assemble")

	# 1. Resolve stats
	var resolved_stats := _resolve_stats(class_data, variant_id)

	# 2. Instantiate base scene
	var ship_scene := preload("res://gameplay/entities/Ship.tscn")
	var ship: RigidBody3D = ship_scene.instantiate()
	ship.position = pos
	ship.position.y = 0.0

	# 3. Resolve loadout
	var loadout: Dictionary = class_data["default_loadout"].duplicate(true)
	if weapon_loadout_override.has("weapons"):
		loadout["weapons"].merge(weapon_loadout_override["weapons"], true)
	if weapon_loadout_override.has("fire_groups"):
		loadout["fire_groups"].merge(weapon_loadout_override["fire_groups"], true)

	# 4. Assemble parts from GLB
	var variant_data: Dictionary = class_data["variants"][variant_id]
	var ship_visual := ship.get_node("ShipVisual")

	# Clear placeholder hardpoints from base scene
	for child in ship_visual.get_children():
		child.queue_free()

	var parts_path: String = _content_registry.get_asset_path(class_data, "parts")
	if not parts_path.is_empty() and FileAccess.file_exists(parts_path):
		_assemble_parts(ship, ship_visual, variant_data, parts_path)
	else:
		push_warning("ShipFactory: no parts.glb found for %s" % class_id)

	# 5. Discover and configure hardpoints
	var discovered := _discover_hardpoints(ship_visual)
	_configure_hardpoints(ship, discovered, class_data, loadout)

	var ship_script: Ship = ship as Ship

	# 6. Shield mesh — only for ships with shields
	if resolved_stats.get("shield_max", 0.0) > 0.0:
		var class_effects: Dictionary = class_data.get("effects", {})
		_create_shield_mesh(ship_script, ship_visual,
				class_effects.get("shield_hit", ""),
				resolved_stats.get("mass", 1000.0))

	# 7. Resolve name
	var display_name := _resolve_display_name(variant_data, class_data["class"], faction, variant_id)

	# 8. Apply color material
	_apply_color_material(ship, class_data, faction)

	# 9. Apply resolved stats
	ship_script.initialize_stats(resolved_stats)

	# Set identity
	ship_script.class_id = class_id
	ship_script.variant_id = variant_id
	ship_script.faction = faction
	ship_script.display_name = display_name
	ship_script.is_player = is_player

	_perf.end("ShipFactory.assemble")

	# 10. Identity and groups
	if is_player:
		ship.add_to_group("player")
		ship.add_to_group("player_fleet")
		_player_state.set_active_ship(ship)

		# Player ship gets a NavigationController for tactical move orders
		var nav := NavigationController.new()
		nav.name = "NavigationController"
		ship.add_child(nav)
	else:
		ship.add_to_group("ai_ships")
		_attach_ai_components(ship, ai_profile_id)

	ship.add_to_group("ships")

	# Add to scene tree
	get_tree().get_root().add_child.call_deferred(ship)
	_event_bus.emit_signal.call_deferred("ship_spawned", ship)

	print("[ShipFactory] Spawned %s (%s) for %s at %s" % [display_name, variant_id, faction, pos])
	return ship


# ─── AI Component Attachment ────────────────────────────────────────────────

func _attach_ai_components(ship: RigidBody3D, profile_id: String) -> void:
	var profile_data: Dictionary = _content_registry.get_ai_profile(profile_id)
	if profile_data.is_empty():
		push_warning("ShipFactory: AI profile '%s' not found, using empty profile" % profile_id)

	# NavigationController — flight computer
	var nav := NavigationController.new()
	nav.name = "NavigationController"
	ship.add_child(nav)

	# DetectionVolume — Area3D with SphereShape3D for player detection
	var detection := Area3D.new()
	detection.name = "DetectionVolume"
	detection.collision_layer = 0
	detection.collision_mask = 1  # detect player physics layer
	detection.monitoring = true
	detection.monitorable = false

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = profile_data.get("detection_range", 800.0)
	shape.shape = sphere
	detection.add_child(shape)
	ship.add_child(detection)

	# AIController — state machine (must be added after nav + detection)
	var ai := AIController.new()
	ai.name = "AIController"
	ai.profile = profile_data
	ship.add_child(ai)


# ─── Stat Resolution ────────────────────────────────────────────────────────

func _resolve_stats(class_data: Dictionary, variant_id: String) -> Dictionary:
	var stats: Dictionary = class_data["base_stats"].duplicate(true)
	var variant: Dictionary = class_data["variants"][variant_id]
	var part_stats: Dictionary = class_data.get("part_stats", {})

	for category in variant["parts"]:
		var node_name: String = variant["parts"][category]
		var deltas: Dictionary = part_stats.get(node_name, {})
		if deltas.is_empty():
			push_warning("ShipFactory: no part_stats entry for '%s'" % node_name)
		for stat in deltas:
			stats[stat] = stats.get(stat, 0.0) + deltas[stat]

	return stats


# ─── Part Assembly ──────────────────────────────────────────────────────────

func _assemble_parts(ship: RigidBody3D, ship_visual: Node3D, variant_data: Dictionary, parts_path: String) -> void:
	var parts_scene: PackedScene = load(parts_path)
	if parts_scene == null:
		push_error("ShipFactory: failed to load parts from %s" % parts_path)
		return

	var parts_root := parts_scene.instantiate()
	var has_per_part_collision := false

	for category in variant_data["parts"]:
		var node_name: String = variant_data["parts"][category]
		var part_node := parts_root.find_child(node_name, true, false)
		if part_node == null:
			push_error("ShipFactory: part '%s' not found in parts.glb" % node_name)
			continue
		ship_visual.add_child(part_node.duplicate())

		# Look for matching -colonly collision mesh
		var col_name := node_name + "-colonly"
		var col_node := parts_root.find_child(col_name, true, false)
		if col_node != null:
			_extract_and_attach_collision(ship, col_node, category)
			has_per_part_collision = true

	parts_root.queue_free()

	# Remove placeholder collision if we have per-part collisions
	if has_per_part_collision:
		var placeholder_col := ship.get_node_or_null("CollisionShape3D")
		if placeholder_col != null:
			placeholder_col.queue_free()


func _extract_and_attach_collision(ship: RigidBody3D, col_node: Node, category: String) -> void:
	# -colonly exports as StaticBody3D with CollisionShape3D child
	# Extract the CollisionShape3D and attach directly to RigidBody3D
	var collision_shape: CollisionShape3D = null

	if col_node is CollisionShape3D:
		collision_shape = col_node.duplicate() as CollisionShape3D
	elif col_node is StaticBody3D or col_node is Node3D:
		# Find CollisionShape3D inside the imported node
		for child in col_node.get_children():
			if child is CollisionShape3D:
				collision_shape = child.duplicate() as CollisionShape3D
				break

	if collision_shape == null:
		push_warning("ShipFactory: no CollisionShape3D found in '%s'" % col_node.name)
		return

	collision_shape.name = "CollisionShape3D_" + category
	ship.add_child(collision_shape)
	collision_shape.owner = ship

	# Store part category on the shape for hit resolution
	collision_shape.set_meta("part_category", category)


# ─── Hardpoint Discovery ────────────────────────────────────────────────────

func _discover_hardpoints(ship_visual: Node3D) -> Array[Node3D]:
	var found: Array[Node3D] = []
	_find_hardpoints_recursive(ship_visual, found)
	return found


func _find_hardpoints_recursive(node: Node, result: Array[Node3D]) -> void:
	if node.name.begins_with("HardpointEmpty_"):
		result.append(node as Node3D)
	for child in node.get_children():
		_find_hardpoints_recursive(child, result)


func _parse_hardpoint_name(node_name: String) -> Dictionary:
	# "HardpointEmpty_sharps_hp_wing_port_small" → { id: "sharps_hp_wing_port", size: "small" }
	# Format: HardpointEmpty_{part}_{location}_{size} — part prefix ensures uniqueness across tree
	var tokens := node_name.split("_")
	var size := tokens[-1]
	# Remove "HardpointEmpty" prefix and size suffix; everything in between is the id
	var id := "_".join(tokens.slice(1, tokens.size() - 1))
	return { "id": id, "size": size }


# ─── Hardpoint Configuration ────────────────────────────────────────────────

func _configure_hardpoints(ship: RigidBody3D, discovered: Array[Node3D],
						  class_data: Dictionary, loadout: Dictionary) -> void:
	var type_map: Dictionary = class_data.get("hardpoint_types", {})
	var weapon_map: Dictionary = loadout.get("weapons", {})
	var group_map: Dictionary = loadout.get("fire_groups", {})

	var ship_script: Ship = ship as Ship

	for hp_node in discovered:
		var parsed := _parse_hardpoint_name(hp_node.name)
		var hp_id := parsed["id"] as String

		var component := HardpointComponent.new()
		hp_node.add_child(component)
		component.owner_ship = ship_script
		component.hardpoint_id = hp_id
		component.hardpoint_type = type_map.get(hp_id, "fixed")
		component.size = parsed["size"]

		# Fire groups: convert from 1-based JSON to 0-based internal
		var groups_1based: Array = group_map.get(hp_id, [1])
		component.fire_groups.clear()
		for g in groups_1based:
			component.fire_groups.append(int(g) - 1)

		# Set arc based on type
		match component.hardpoint_type:
			"fixed":
				component.fire_arc_degrees = 5.0
			"gimbal":
				component.fire_arc_degrees = 25.0
			"partial_turret":
				component.fire_arc_degrees = 120.0
			"full_turret":
				component.fire_arc_degrees = 360.0

		# Attach weapon if specified
		var weapon_id: String = weapon_map.get(hp_id, "")
		if not weapon_id.is_empty():
			_attach_weapon(hp_node, component, weapon_id)


func _attach_weapon(hp_node: Node3D, hardpoint: HardpointComponent, weapon_id: String) -> void:
	var weapon_data: Dictionary = _content_registry.get_weapon(weapon_id)
	if weapon_data.is_empty():
		push_warning("ShipFactory: weapon '%s' not found in ContentRegistry" % weapon_id)
		return

	# Load weapon model
	var model_path: String = _content_registry.get_asset_path(weapon_data, "model")
	if model_path.is_empty() or not FileAccess.file_exists(model_path):
		push_warning("ShipFactory: weapon model not found for '%s'" % weapon_id)
		return

	var model_scene: PackedScene = load(model_path)
	if model_scene == null:
		push_warning("ShipFactory: failed to load weapon model for '%s'" % weapon_id)
		return

	var weapon_model: Node3D = model_scene.instantiate()
	hp_node.add_child(weapon_model)

	# Create and configure WeaponComponent
	var weapon_component := WeaponComponent.new()
	weapon_model.add_child(weapon_component)
	weapon_component.weapon_id = weapon_id
	weapon_component.initialize_from_data(weapon_data)

	# Copy heat per shot from weapon data to hardpoint
	var stats: Dictionary = weapon_data.get("stats", {})
	hardpoint.heat_per_shot = stats.get("heat_per_shot", 10.0)

	# Link hardpoint and weapon
	hardpoint.set_weapon_model(weapon_model, weapon_component)

	# MuzzleFlashPlayer — always; graceful no-op if effect_id is empty
	var effects: Dictionary = weapon_data.get("effects", {})
	var muzzle_player := MuzzleFlashPlayer.new()
	muzzle_player.name = "MuzzleFlashPlayer"
	muzzle_player.effect_id = effects.get("muzzle_flash", "")
	weapon_model.add_child(muzzle_player)

	# BeamRenderer — energy_beam and energy_pulse archetypes
	if weapon_data.get("archetype", "") in ["energy_beam", "energy_pulse"]:
		var beam_renderer := BeamRenderer.new()
		beam_renderer.name = "BeamRenderer"
		beam_renderer.effect_id = effects.get("beam", "")
		weapon_model.add_child(beam_renderer)
		# Apply weapon-specific visual overrides
		var visual: Dictionary = weapon_data.get("visual", {})
		var alpha: float = float(visual.get("beam_alpha", 1.0))
		var linger: float = float(visual.get("linger_duration", 0.15))
		beam_renderer.set_visual_params(alpha, linger)


# ─── Name Resolution ────────────────────────────────────────────────────────

func _resolve_display_name(variant_data: Dictionary, class_type: String,
						   faction: String, variant_id: String) -> String:
	# 1. Explicit faction name
	var faction_names: Dictionary = variant_data.get("faction_display_names", {})
	if faction_names.has(faction):
		return faction_names[faction]

	# 2. Faction vocabulary fallback
	var faction_data: Dictionary = _content_registry.get_faction(faction)
	var vocab: Dictionary = faction_data.get("name_vocabulary", {})
	var class_vocab: Dictionary = vocab.get(class_type, {})
	var name_pool: Array = []

	if not class_vocab.is_empty():
		var category := _dominant_part_category(variant_data)
		name_pool = class_vocab.get(category, [])
		if name_pool.is_empty():
			# Fallback to first available category
			var keys := class_vocab.keys()
			if not keys.is_empty():
				name_pool = class_vocab[keys[0]]

	if not name_pool.is_empty():
		# Deterministic selection
		var idx: int = abs(variant_id.hash() + faction.hash()) % name_pool.size()
		return name_pool[idx]

	# 3. Default display_name
	return variant_data.get("display_name", "Unknown Ship")


func _dominant_part_category(variant_data: Dictionary) -> String:
	# Simple heuristic: look at part names for keywords
	var parts: Dictionary = variant_data.get("parts", {})
	for category in parts:
		var part_name: String = parts[category]
		if part_name.find("heavy") != -1:
			return "heavy_hull"
		if part_name.find("fast") != -1 or part_name.find("overdriven") != -1:
			return "fast_engine"

	# Default to standard
	return "standard"


# ─── Color Material Application ─────────────────────────────────────────────

func _apply_color_material(ship: Node3D, class_data: Dictionary, faction: String) -> void:
	var scheme := _resolve_color_scheme(class_data, faction)

	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/shaders/ship_colorize.gdshader")
	material.set_shader_parameter("color_primary", _hex_to_color(scheme["primary"]))
	material.set_shader_parameter("color_trim", _hex_to_color(scheme.get("trim", "#DDDDDD")))
	material.set_shader_parameter("color_accent", _hex_to_color(scheme.get("accent", "#FFD700")))
	material.set_shader_parameter("color_glow", _hex_to_color(scheme.get("glow", scheme["primary"])))

	var ship_visual := ship.get_node("ShipVisual")
	_apply_material_recursive(ship_visual, material)


func _resolve_color_scheme(class_data: Dictionary, faction: String) -> Dictionary:
	# Check for class-level override
	if class_data.has("color_scheme"):
		return class_data["color_scheme"]

	# Get from faction data
	var faction_data: Dictionary = _content_registry.get_faction(faction)
	var scheme: Dictionary = faction_data.get("color_scheme", {})

	# Map faction scheme to expected keys
	return {
		"primary": scheme.get("primary", "#808080"),
		"trim": scheme.get("secondary", "#AAAAAA"),
		"accent": scheme.get("accent", "#FFFFFF"),
		"glow": scheme.get("primary", "#808080")
	}


func _apply_material_recursive(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = material
	for child in node.get_children():
		_apply_material_recursive(child, material)


func _hex_to_color(hex: String) -> Color:
	if hex.begins_with("#"):
		hex = hex.substr(1)
	if hex.length() == 6:
		return Color(
			hex.substr(0, 2).hex_to_int() / 255.0,
			hex.substr(2, 2).hex_to_int() / 255.0,
			hex.substr(4, 2).hex_to_int() / 255.0
		)
	return Color.GRAY


# ─── Shield Mesh Creation ────────────────────────────────────────────────────

func _create_shield_mesh(ship: Ship, ship_visual: Node3D,
		shield_hit_effect_id: String, mass: float) -> void:
	var shader: Shader = load("res://assets/shaders/shield_ripple.gdshader")
	if shader == null:
		push_warning("ShipFactory: shield_ripple.gdshader not found — skipping shield mesh")
		return

	# Radius heuristic: cube-root scale from 1000-unit baseline.
	# Art pass will tune per-ship via JSON later.
	var radius: float = maxf(3.0, pow(mass / 1000.0, 0.33) * 4.0)

	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 16
	sphere.rings = 8

	var shield_mat := ShaderMaterial.new()
	shield_mat.shader = shader
	shield_mat.set_shader_parameter("u_hit_time", -1.0)
	shield_mat.set_shader_parameter("u_color", Color(0.4, 0.7, 1.0, 0.8))
	shield_mat.set_shader_parameter("u_ripple_speed", 2.5)
	shield_mat.set_shader_parameter("u_ripple_falloff", 1.8)

	var shield_mesh := MeshInstance3D.new()
	shield_mesh.name = "ShieldMesh"
	shield_mesh.mesh = sphere
	shield_mesh.material_override = shield_mat
	shield_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var shield_player := ShieldEffectPlayer.new()
	shield_player.name = "ShieldEffectPlayer"
	shield_player.effect_id = shield_hit_effect_id
	shield_mesh.add_child(shield_player)

	ship_visual.add_child(shield_mesh)
	ship.shield_mesh = shield_mesh
