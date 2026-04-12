extends SpaceBody
class_name Ship

@export var thruster_force: float = 15000.0
@export var torque_thrust_ratio: float = 0.4
@export var max_angular_accel: float = 5.0  # radians/sec²
@export var is_player_controlled: bool = true

# Power System (per ship shared pool)
@export var power_capacity: float = 100.0
@export var power_regen: float = 15.0
var power_current: float = 100.0

# Shield System
@export var shield_max: float = 100.0
@export var regen_rate: float = 20.0
@export var regen_delay: float = 3.0
@export var regen_power_draw: float = 10.0
var shield_hp: float = 100.0
var _time_since_last_hit: float = 999.0

# Hull / Combat
@export var hull_max: float = 200.0
var hull_hp: float = 200.0
var is_dead: bool = false

# Used by GameEventBus payloads (e.g. ship_destroyed) and AI/threat integration.
@export var faction: String = "neutral"

# Damage type multipliers loaded from JSON
var _damage_types: Dictionary = {}
var _shield_absorption: float = 0.8
var _hardpoint_radius_by_size: Dictionary = {}
var _hardpoint_radius_hp_scale: float = 0.35

var _weapon_component: WeaponComponent = null
var _ai_controller: Node = null

# Data-driven initialization — set by initialize() before entering the scene tree.
var _pending_ship_data: Dictionary = {}
var _pending_loadout: Dictionary = {}

# Module tracking — slot_id → module_id; updated by LoadoutUI at dock time.
var _active_modules: Dictionary = {}
# Cached ContentRegistry reference for apply_module_stats().
var _content_registry_ref: Node = null

# Guard flag to avoid emitting hull_critical every frame once below threshold.
var _hull_critical_emitted: bool = false

# 3D visual rendering — model is loaded from ship content and synced to 2D physics position.
# PIXELS_PER_UNIT must match hull.marker_scale in ship.json for all ships.
const PIXELS_PER_UNIT := 2.8
var _visual_model: Node3D = null
## Set by the scene after spawning to enable perspective mouse-aim raycast.
## When null, falls back to Camera2D-compatible get_global_mouse_position().
var aim_camera: Camera3D = null

@onready var _event_bus: Node = ServiceLocator.GetService("GameEventBus") as Node


## Called by ShipFactory before the ship enters the scene tree.
## Stores ship data; _ready() applies it once children are available.
func initialize(ship_data: Dictionary, loadout_override: Dictionary = {}) -> void:
	_pending_ship_data = ship_data
	_pending_loadout = loadout_override if not loadout_override.is_empty() \
		else ship_data.get("default_loadout", {})


func _ready() -> void:
	_load_damage_types()
	_content_registry_ref = ServiceLocator.GetService("ContentRegistry") as Node

	# Apply hull stats and weapon loadout if we were initialized from content data.
	if not _pending_ship_data.is_empty():
		_apply_hull_stats(_pending_ship_data.get("hull", {}))

	# Initialize resources after hull stats are set.
	power_current = power_capacity
	shield_hp = shield_max
	hull_hp = hull_max

	# Find child nodes.
	for c in get_children():
		if c is WeaponComponent:
			_weapon_component = c
			break

	_ai_controller = get_node_or_null("AIController")

	# Wire up weapon loadout from content data now that WeaponComponent exists.
	if not _pending_ship_data.is_empty() and _weapon_component != null:
		if _content_registry_ref != null:
			var marker_scale: float = float(_pending_ship_data.get("hull", {}).get("marker_scale", 1.0))
			var model_node: Node = _load_model_markers(_pending_ship_data)
			_weapon_component.initialize_from_ship_data(
				_pending_ship_data.get("hardpoints", []),
				_pending_loadout.get("weapons", {}),
				_content_registry_ref,
				model_node,
				marker_scale
			)
			# Keep the model alive as the visual representation instead of freeing it.
			_visual_model = model_node as Node3D
			if _visual_model != null:
				call_deferred("_attach_visual_model")

	# Initialize module tracking and apply initial module bonuses.
	_active_modules = _pending_loadout.get("modules", {}).duplicate()
	if not _active_modules.is_empty() and _content_registry_ref != null:
		apply_module_stats(true)


func _apply_hull_stats(hull: Dictionary) -> void:
	if hull.is_empty():
		return
	mass             = float(hull.get("mass",              mass))
	max_speed        = float(hull.get("max_speed",         max_speed))
	linear_drag      = float(hull.get("linear_drag",       linear_drag))
	alignment_drag   = float(hull.get("alignment_drag",    alignment_drag))
	thruster_force   = float(hull.get("thruster_force",    thruster_force))
	torque_thrust_ratio = float(hull.get("torque_thrust_ratio", torque_thrust_ratio))
	hull_max         = float(hull.get("hp",                hull_max))
	power_capacity   = float(hull.get("power_capacity",    power_capacity))
	power_regen      = float(hull.get("power_regen",       power_regen))
	shield_max       = float(hull.get("shield_max",        shield_max))
	regen_rate       = float(hull.get("regen_rate",        regen_rate))
	regen_delay      = float(hull.get("regen_delay",       regen_delay))
	regen_power_draw = float(hull.get("regen_power_draw",  regen_power_draw))


func _load_damage_types() -> void:
	var file_path := "res://data/damage_types.json"
	var damage_file := FileAccess.open(file_path, FileAccess.READ)
	if not damage_file:
		push_error("Ship: Failed to open %s" % file_path)
		return

	var text := damage_file.get_as_text()
	damage_file.close()

	var json := JSON.new()
	var parse_err := json.parse(text)
	if parse_err != OK:
		push_error(
			"Ship: JSON parse failed for %s: %s (line %d)" % [
				file_path, json.get_error_message(), json.get_error_line()
			]
		)
		return

	var data: Dictionary = json.get_data()
	if typeof(data) != TYPE_DICTIONARY:
		push_error("Ship: Invalid root in %s (expected Dictionary)" % file_path)
		return

	if not data.has("_comment") or typeof(data["_comment"]) != TYPE_STRING:
		push_error("Ship: Missing/invalid top-level _comment in %s" % file_path)
		return

	if not data.has("damage_types") or typeof(data["damage_types"]) != TYPE_DICTIONARY:
		push_error("Ship: Missing/invalid 'damage_types' dictionary in %s" % file_path)
		return

	if not data.has("shield_absorption") or typeof(data["shield_absorption"]) != TYPE_DICTIONARY:
		push_error("Ship: Missing/invalid 'shield_absorption' dictionary in %s" % file_path)
		return

	var shield_absorption: Dictionary = data["shield_absorption"]
	if not shield_absorption.has("base_ratio"):
		push_error("Ship: Missing 'shield_absorption.base_ratio' in %s" % file_path)
		return

	var base_ratio_val = shield_absorption["base_ratio"]
	var base_ratio_type := typeof(base_ratio_val)
	if base_ratio_type != TYPE_INT and base_ratio_type != TYPE_FLOAT:
		push_error("Ship: 'shield_absorption.base_ratio' must be a number in %s" % file_path)
		return
	_shield_absorption = float(base_ratio_val)

	var damage_types: Dictionary = data["damage_types"]
	for damage_type in damage_types.keys():
		var type_data = damage_types[damage_type]
		if typeof(type_data) != TYPE_DICTIONARY:
			push_error("Ship: damage_types.%s must be a Dictionary in %s" % [str(damage_type), file_path])
			return
		if not type_data.has("vs_shields") or not type_data.has("vs_hull"):
			push_error("Ship: damage_types.%s missing 'vs_shields' or 'vs_hull' in %s" % [str(damage_type), file_path])
			return

		var vs_shields_val = type_data["vs_shields"]
		var vs_hull_val = type_data["vs_hull"]
		var vs_shields_ok := typeof(vs_shields_val) == TYPE_INT or typeof(vs_shields_val) == TYPE_FLOAT
		var vs_hull_ok := typeof(vs_hull_val) == TYPE_INT or typeof(vs_hull_val) == TYPE_FLOAT
		if not (vs_shields_ok and vs_hull_ok):
			push_error("Ship: damage_types.%s multipliers must be numbers in %s" % [str(damage_type), file_path])
			return

	_damage_types = damage_types

	if not data.has("hardpoint_hit_regions") or typeof(data["hardpoint_hit_regions"]) != TYPE_DICTIONARY:
		push_error("Ship: Missing/invalid 'hardpoint_hit_regions' in %s" % file_path)
		return

	var hhr: Dictionary = data["hardpoint_hit_regions"]
	if not hhr.has("radius_by_size") or typeof(hhr["radius_by_size"]) != TYPE_DICTIONARY:
		push_error("Ship: hardpoint_hit_regions missing 'radius_by_size' in %s" % file_path)
		return

	var rbs: Dictionary = hhr["radius_by_size"]
	for sz in ["small", "medium", "large"]:
		if not rbs.has(sz):
			push_error("Ship: hardpoint_hit_regions.radius_by_size missing '%s' in %s" % [sz, file_path])
			return
		var rv = rbs[sz]
		if typeof(rv) != TYPE_INT and typeof(rv) != TYPE_FLOAT:
			push_error("Ship: hardpoint_hit_regions.radius_by_size.%s must be a number in %s" % [sz, file_path])
			return

	_hardpoint_radius_by_size = rbs.duplicate()
	var hp_scale_val = hhr.get("radius_extra_from_hp_max", 0.35)
	if typeof(hp_scale_val) != TYPE_INT and typeof(hp_scale_val) != TYPE_FLOAT:
		push_error("Ship: hardpoint_hit_regions.radius_extra_from_hp_max must be a number in %s" % file_path)
		return
	_hardpoint_radius_hp_scale = float(hp_scale_val)


## Deferred from _ready() — adds the visual model to the parent scene after the
## ship itself is fully in the scene tree so get_parent() is valid.
func _attach_visual_model() -> void:
	if _visual_model == null:
		return
	var p := get_parent()
	if p == null:
		_visual_model.queue_free()
		_visual_model = null
		return
	p.add_child(_visual_model)
	_sync_visual_model()


func _exit_tree() -> void:
	if _visual_model != null and is_instance_valid(_visual_model):
		_visual_model.queue_free()
		_visual_model = null


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_update_resource_regen(delta)
	_time_since_last_hit += delta
	_sync_visual_model()


func _update_resource_regen(delta: float) -> void:
	# Power regen (always happens unless at max)
	if power_current < power_capacity:
		power_current = minf(power_current + power_regen * delta, power_capacity)

	# Shield regen (only after delay, and only if we have power)
	if shield_hp < shield_max and _time_since_last_hit >= regen_delay:
		var power_cost := regen_power_draw * delta
		if power_current >= power_cost:
			var regen_amount := regen_rate * delta
			shield_hp = minf(shield_hp + regen_amount, shield_max)
			power_current -= power_cost


func apply_damage(amount: float, damage_type: String, hit_position: Vector2, component_damage_ratio: float = 0.0) -> void:
	_time_since_last_hit = 0.0

	# Get damage multipliers
	var type_data: Dictionary = _damage_types.get(damage_type, {})
	var vs_shields: float = float(type_data.get("vs_shields", 1.0))
	var vs_hull: float = float(type_data.get("vs_hull", 1.0))

	# Shield absorption
	var shield_damage: float = amount * vs_shields
	var remaining_damage: float = 0.0

	if shield_hp > 0:
		var absorbed: float = minf(shield_hp, shield_damage)
		shield_hp -= absorbed
		var absorbed_ratio: float = absorbed / shield_damage if shield_damage > 0 else 1.0
		remaining_damage = amount * (1.0 - _shield_absorption * absorbed_ratio)

		if shield_hp <= 0:
			_event_bus.emit_signal("shield_depleted", self)
	else:
		remaining_damage = amount

	if remaining_damage <= 0:
		return

	# Post-shield damage with hull type multiplier, then optional hardpoint split
	var effective_hull: float = remaining_damage * vs_hull
	var to_hull: float = effective_hull
	var to_hardpoint: float = 0.0

	if component_damage_ratio > 0.0 and is_finite(component_damage_ratio):
		var ratio_clamped: float = clampf(component_damage_ratio, 0.0, 1.0)
		if ratio_clamped > 0.0:
			_perf.begin("HitDetection.component_resolve")
			var hp_hit: HardpointComponent = _resolve_hardpoint_at(hit_position)
			if hp_hit != null:
				to_hardpoint = effective_hull * ratio_clamped
				to_hull = effective_hull * (1.0 - ratio_clamped)
				hp_hit.apply_damage(to_hardpoint)
			_perf.end("HitDetection.component_resolve")

	if to_hull > 0:
		hull_hp -= to_hull
		_event_bus.emit_signal("ship_damaged", self, to_hull, damage_type, hit_position)

		# hull_critical signal — once per engage until healed above threshold
		var hull_percent: float = hull_hp / hull_max if hull_max > 0.0 else 0.0
		if hull_percent < 0.25 and not _hull_critical_emitted:
			_hull_critical_emitted = true
			_event_bus.emit_signal("hull_critical", self, hull_percent)
		elif hull_percent >= 0.25:
			_hull_critical_emitted = false

	if hull_hp <= 0 and not is_dead:
		hull_hp = 0
		is_dead = true
		_event_bus.emit_signal("ship_destroyed", self, global_position, faction)


func _resolve_hardpoint_at(world_pos: Vector2) -> HardpointComponent:
	if _weapon_component == null:
		return null

	var best: HardpointComponent = null
	var best_dist: float = INF

	for node in _weapon_component.get_all_hardpoints():
		var hp: HardpointComponent = node as HardpointComponent
		if hp == null:
			continue
		if hp.damage_state == "destroyed":
			continue

		var threshold: float = _hardpoint_threshold(hp)
		var dist: float = world_pos.distance_to(hp.get_world_position())
		if dist <= threshold and dist < best_dist:
			best = hp
			best_dist = dist

	return best


func _hardpoint_threshold(hp: HardpointComponent) -> float:
	var base: Variant = _hardpoint_radius_by_size.get(hp.size, _hardpoint_radius_by_size.get("medium", 40.0))
	var base_f: float = float(base)
	return maxf(base_f, hp.hardpoint_hp_max * _hardpoint_radius_hp_scale)


## Recompute all hull stats from base JSON then stack installed module bonuses.
## Call with refill=true at spawn to fill all HP pools; false at loadout to clamp
## current values to new maxima without healing.
func apply_module_stats(refill: bool = false) -> void:
	if _content_registry_ref == null or _pending_ship_data.is_empty():
		return

	# Reset to base hull stats before summing module bonuses.
	_apply_hull_stats(_pending_ship_data.get("hull", {}))

	# Stack additive/multiplicative bonuses from each installed module.
	for slot_id in _active_modules.keys():
		var module_id: String = _active_modules[slot_id]
		if module_id.is_empty():
			continue
		var mdata: Dictionary = _content_registry_ref.get_module(module_id)
		if mdata.is_empty():
			continue
		var stats: Dictionary = mdata.get("stats", {})
		# Shield module stats
		shield_max     += float(stats.get("shield_hp",        0.0))
		regen_rate     += float(stats.get("regen_rate",       0.0))
		regen_power_draw += float(stats.get("regen_power_draw", 0.0))
		if stats.has("regen_delay"):
			regen_delay = minf(regen_delay, float(stats["regen_delay"]))
		# Engine module stats (thrust_multiplier of 1.3 = 30% increase over base)
		thruster_force *= float(stats.get("thrust_multiplier", 1.0))
		max_speed      += float(stats.get("max_speed_bonus",  0.0))
		max_speed      -= float(stats.get("speed_penalty",    0.0))
		# Powerplant module stats
		power_capacity += float(stats.get("power_capacity",   0.0))
		power_regen    += float(stats.get("power_regen",      0.0))
		# Armor module stats
		hull_max       += float(stats.get("hull_hp_bonus",    0.0))
		# Mass is shared — a heavier ship turns and accelerates slower
		mass           += float(stats.get("mass_addition",    0.0))

	# Clamp max values to be at least 1
	shield_max = maxf(shield_max, 0.0)
	hull_max = maxf(hull_max, 1.0)
	power_capacity = maxf(power_capacity, 1.0)

	if refill:
		power_current = power_capacity
		shield_hp = shield_max
		hull_hp = hull_max
	else:
		power_current = minf(power_current, power_capacity)
		shield_hp = minf(shield_hp, shield_max)
		hull_hp = minf(hull_hp, hull_max)


## Load the ship's 3D model scene and return its root node (not in the scene tree).
## The caller is responsible for calling .free() on the returned node when done.
## Returns null if no model is defined, the path is invalid, or loading fails.
func _load_model_markers(ship_data: Dictionary) -> Node:
	var base_path: String = ship_data.get("_base_path", "")
	var assets: Dictionary = ship_data.get("assets", {})
	var model_file: String = assets.get("model", "")
	if base_path.is_empty() or model_file.is_empty():
		return null

	var model_path: String = "%s/%s" % [base_path, model_file]
	if not ResourceLoader.exists(model_path):
		return null

	var packed: PackedScene = load(model_path) as PackedScene
	if packed == null:
		push_warning("Ship: failed to load model scene '%s' for marker extraction" % model_path)
		return null

	return packed.instantiate()


## Sync the 3D visual model position and rotation to match the 2D physics body.
## Convention: 2D(x,y) → 3D(x, 0, -y) / PIXELS_PER_UNIT; model nose faces local +Z.
func _sync_visual_model() -> void:
	if _visual_model == null or not is_instance_valid(_visual_model):
		return
	_visual_model.position = Vector3(global_position.x, 0.0, -global_position.y) / PIXELS_PER_UNIT
	_visual_model.rotation.y = -rotation - PI * 0.5


## Return the 2D world position the mouse is pointing at.
## With aim_camera set: raycasts onto the Y=0 plane for perspective-correct aiming.
## Without aim_camera: falls back to Camera2D-compatible get_global_mouse_position().
func _get_mouse_world_pos() -> Vector2:
	if aim_camera == null or not is_instance_valid(aim_camera):
		return get_global_mouse_position()
	var mouse := get_viewport().get_mouse_position()
	var from := aim_camera.project_ray_origin(mouse)
	var dir  := aim_camera.project_ray_normal(mouse)
	if absf(dir.y) < 0.001:
		return global_position
	var t := -from.y / dir.y
	var hit := from + dir * t
	return Vector2(hit.x, -hit.z) * PIXELS_PER_UNIT


func consume_power(amount: float) -> bool:
	if power_current >= amount:
		power_current -= amount
		if power_current <= 0:
			_event_bus.emit_signal("power_depleted", self)
		return true
	return false


func apply_thrust_forces(delta: float) -> void:
	# Step 1 — Determine target heading angle.
	var target_angle: float
	var forward_input := 0.0
	var strafe_input := 0.0

	if is_player_controlled:
		var mouse_pos := _get_mouse_world_pos()
		target_angle = position.direction_to(mouse_pos).angle()
		forward_input = (Input.get_action_strength("thrust_forward")
				- Input.get_action_strength("thrust_reverse"))
		strafe_input = (Input.get_action_strength("strafe_right")
				- Input.get_action_strength("strafe_left"))
	elif _ai_controller != null:
		var aim: Vector2 = _ai_controller.ai_aim_target
		target_angle = position.direction_to(aim).angle() if aim != Vector2.ZERO else rotation
		forward_input = _ai_controller.ai_forward_input
		strafe_input  = _ai_controller.ai_strafe_input
	else:
		target_angle = rotation

	_perf.begin("Physics.thruster_allocation")

	# Step 2 — Compute torque demand via assisted steering.
	var torque_demand := _update_assisted_steering(target_angle)

	# Step 3 — Allocate thruster budget; turning wins.
	_allocate_thrust(forward_input, strafe_input, torque_demand, delta)

	_perf.end("Physics.thruster_allocation")

	# Step 4 — Soft speed cap.
	if velocity.length() > max_speed:
		velocity = velocity.normalized() * max_speed


func _update_assisted_steering(target_angle: float) -> float:
	var heading_error := angle_difference(rotation, target_angle)
	var stopping_distance := (angular_velocity * angular_velocity) / \
			(2.0 * max_angular_accel + 0.0001)

	var torque_direction: float
	if stopping_distance >= absf(heading_error):
		torque_direction = -signf(angular_velocity)
	else:
		torque_direction = signf(heading_error)

	return torque_direction * max_angular_accel


func _allocate_thrust(forward_input: float, strafe_input: float,
		torque_demand: float, delta: float) -> void:
	var max_torque_output := thruster_force / torque_thrust_ratio
	var clamped_torque := clampf(torque_demand, -max_torque_output, max_torque_output)

	var torque_cost := absf(clamped_torque) * torque_thrust_ratio
	var remaining := maxf(0.0, thruster_force - torque_cost)

	var movement_input := Vector2(forward_input, strafe_input)
	if movement_input.length() > 1.0:
		movement_input = movement_input.normalized()

	angular_velocity += clamped_torque * delta

	var world_force := movement_input.rotated(rotation) * remaining
	velocity += world_force * delta / mass
