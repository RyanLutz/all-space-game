extends Node
class_name WeaponComponent

# Hardpoint definitions - can be loaded from ship JSON in future
@export var hardpoint_configs: Array[Dictionary] = []

# Group mappings for fire control
var _primary_hardpoints: Array[HardpointComponent] = []
var _secondary_hardpoints: Array[HardpointComponent] = []
var _missile_hardpoints: Array[HardpointComponent] = []

var _ship: Ship
var _event_bus: Node

var _weapons_data: Dictionary = {}

# Beam weapon continuous fire state
var _active_beams: Array[HardpointComponent] = []


func _ready() -> void:
	_ship = get_parent() as Ship
	_event_bus = ServiceLocator.GetService("GameEventBus") as Node

	_load_weapons_data()
	_spawn_hardpoints()


func _load_weapons_data() -> void:
	var content_registry: Node = ServiceLocator.GetService("ContentRegistry") as Node
	if content_registry == null:
		push_error("WeaponComponent: ContentRegistry not registered — weapons unavailable")
		return
	var all_weapons = content_registry.get("weapons")
	if typeof(all_weapons) != TYPE_DICTIONARY:
		push_error("WeaponComponent: ContentRegistry.weapons is not a Dictionary")
		return
	_weapons_data = (all_weapons as Dictionary).duplicate()


func _spawn_hardpoints() -> void:
	# If no configs provided, use defaults for testing
	if hardpoint_configs.is_empty():
		hardpoint_configs = [
		{
			"id": "hp_nose",
			"offset": Vector2(32, 0),
			"facing": 0.0,
			"arc_degrees": 45.0,
			"size": "medium",
			"groups": ["primary"],
			"weapon_id": "autocannon_light"
		},
		{
			"id": "hp_port",
			"offset": Vector2(-8, -20),
			"facing": 0.0,
			"arc_degrees": 90.0,
			"size": "small",
			"groups": ["secondary"],
			"weapon_id": "pulse_laser"
		},
		{
			"id": "hp_starboard",
			"offset": Vector2(-8, 20),
			"facing": 0.0,
			"arc_degrees": 90.0,
			"size": "small",
			"groups": ["secondary"],
			"weapon_id": "pulse_laser"
		},
		{
			"id": "hp_missile",
			"offset": Vector2(-16, 0),
			"facing": 0.0,
			"arc_degrees": 45.0,
			"size": "small",
			"groups": ["missile"],
			"weapon_id": "rocket_dumb"
		}
		]

	for i in range(hardpoint_configs.size()):
		var config = hardpoint_configs[i]
		var hp := HardpointComponent.new()
		hp.name = config.get("id", "hardpoint")
		hp.hardpoint_id = config.get("id", "")
		hp.hardpoint_index = config.get("hardpoint_index", i)
		hp.offset = config.get("offset", Vector2.ZERO)
		hp.facing = config.get("facing", 0.0)
		hp.arc_degrees = config.get("arc_degrees", 5.0)
		hp.size = config.get("size", "small")
		hp.allowed_groups = Array(config.get("groups", ["primary"]), TYPE_STRING, "", null)

		var weapon_id: String = config.get("weapon_id", "")
		if not weapon_id.is_empty() and _weapons_data.has(weapon_id):
			hp.set_weapon(weapon_id, _weapons_data)

		add_child(hp)

		# Sort into groups
		for group in hp.allowed_groups:
			match group:
				"primary":
					_primary_hardpoints.append(hp)
				"secondary":
					_secondary_hardpoints.append(hp)
				"missile":
					_missile_hardpoints.append(hp)


func _input(event: InputEvent) -> void:
	if not _ship.is_player_controlled:
		return

	# Primary fire (ballistics, pulses)
	if event.is_action_pressed("fire_primary"):
		_start_firing("primary")
	if event.is_action_released("fire_primary"):
		_stop_firing("primary")

	# Secondary fire (beams - held)
	if event.is_action_pressed("fire_secondary"):
		_start_firing("secondary")
	if event.is_action_released("fire_secondary"):
		_stop_firing("secondary")

	# Missile fire (single shots)
	if event.is_action_pressed("fire_missile"):
		_fire_missile_group()


func _start_firing(group: String) -> void:
	var hardpoints := _get_hardpoints_for_group(group)

	for hp in hardpoints:
		if hp.weapon_data.is_empty():
			continue

		var archetype: String = hp.weapon_data.get("archetype", "ballistic")

		match archetype:
			"energy_beam":
				# Continuous beams - add to active list for _physics_process
				if not _active_beams.has(hp):
					_active_beams.append(hp)
			_:
				# Single fire for missiles, pulse for ballistic
				if archetype == "missile_dumb" or archetype == "missile_guided":
					continue  # Missiles use separate input
				# For ballistic/pulse, fire once and let auto-fire in _physics_process
				if not _active_beams.has(hp):
					_active_beams.append(hp)


func _stop_firing(group: String) -> void:
	var hardpoints := _get_hardpoints_for_group(group)

	for hp in hardpoints:
		if _active_beams.has(hp):
			_active_beams.erase(hp)


func _fire_missile_group() -> void:
	var target_pos := _ship.get_global_mouse_position()

	for hp in _missile_hardpoints:
		var aim_dir := (target_pos - hp.get_world_position()).normalized()
		hp.request_fire(aim_dir, target_pos)


func _get_hardpoints_for_group(group: String) -> Array[HardpointComponent]:
	match group:
		"primary":
			return _primary_hardpoints
		"secondary":
			return _secondary_hardpoints
		"missile":
			return _missile_hardpoints
	return []


func _physics_process(_delta: float) -> void:
	if _active_beams.is_empty():
		return

	var target_pos := _ship.get_global_mouse_position()

	# Process continuous fire for active hardpoints
	for hp in _active_beams:
		var aim_dir := (target_pos - hp.get_world_position()).normalized()

		var archetype: String = hp.weapon_data.get("archetype", "ballistic")

		match archetype:
			"energy_beam":
				# Continuous beam - fire every frame while held
				hp.request_fire(aim_dir, target_pos)
			"ballistic", "energy_pulse":
				# Auto-fire based on fire rate
				hp.request_fire(aim_dir, target_pos)


func get_hardpoint(id: String) -> HardpointComponent:
	for child in get_children():
		if child is HardpointComponent and child.hardpoint_id == id:
			return child
	return null


func get_all_hardpoints() -> Array:
	var result: Array = []
	for child in get_children():
		if child is HardpointComponent:
			result.append(child)
	return result


## Data-driven initialization from ship.json and ContentRegistry.
## Replaces the default hardpoints spawned by _spawn_hardpoints().
## Called by Ship._ready() when the ship was created via ShipFactory.
##
## model_node: optional root of the instantiated 3D model scene. When provided,
## any hardpoint def that omits "offset" (or sets it to null) will have its
## 2D offset read from a Node3D child named after the hardpoint id.
## marker_scale: pixels-per-3D-unit factor, read from hull.marker_scale in ship.json.
func initialize_from_ship_data(
		hardpoint_defs: Array,
		weapon_assignments: Dictionary,
		content_registry: Node,
		model_node: Node = null,
		marker_scale: float = 1.0) -> void:
	# Remove hardpoints already spawned by the default _spawn_hardpoints() path.
	for child in get_children():
		if child is HardpointComponent:
			child.queue_free()
	_primary_hardpoints.clear()
	_secondary_hardpoints.clear()
	_missile_hardpoints.clear()
	_active_beams.clear()

	# Fetch weapon data from ContentRegistry for every assigned weapon id.
	var weapons_data: Dictionary = {}
	for _hp_id in weapon_assignments:
		var weapon_id: String = weapon_assignments[_hp_id]
		if weapon_id.is_empty():
			continue
		var w_data: Dictionary = content_registry.get_weapon(weapon_id)
		if not w_data.is_empty():
			weapons_data[weapon_id] = w_data

	# Hardpoint type → arc_degrees mapping
	const TYPE_TO_ARC: Dictionary = {
		"fixed":         5.0,
		"gimbal":        25.0,
		"partial_turret": 120.0,
		"full_turret":   360.0
	}

	for i in range(hardpoint_defs.size()):
		var def: Dictionary = hardpoint_defs[i]
		var hp := HardpointComponent.new()

		hp.name           = def.get("id", "hardpoint_%d" % i)
		hp.hardpoint_id   = def.get("id", "")
		hp.hardpoint_index = i

		# Resolve offset: explicit [x,y] wins; absent/null triggers model marker lookup.
		var raw_offset = def.get("offset", null)
		if raw_offset != null and typeof(raw_offset) == TYPE_ARRAY:
			var off: Array = raw_offset
			hp.offset = Vector2(float(off[0]), float(off[1]))
		else:
			hp.offset = _offset_from_model(model_node, hp.hardpoint_id, marker_scale)

		hp.facing = float(def.get("facing", 0.0))
		hp.size   = def.get("size", "small")

		var hp_type: String = def.get("type", "fixed")
		hp.arc_degrees = TYPE_TO_ARC.get(hp_type, 5.0)

		hp.allowed_groups = Array(def.get("groups", ["primary"]), TYPE_STRING, "", null)

		var weapon_id: String = weapon_assignments.get(hp.hardpoint_id, "")
		if not weapon_id.is_empty() and weapons_data.has(weapon_id):
			var w_data: Dictionary = weapons_data[weapon_id]
			if hp.can_accept_weapon(w_data):
				hp.set_weapon(weapon_id, weapons_data)
			else:
				push_warning(
					"WeaponComponent: size mismatch — weapon '%s' (%s) cannot mount on hardpoint '%s' (%s); slot left empty" % [
						weapon_id, w_data.get("size", "?"), hp.hardpoint_id, hp.size
					]
				)

		add_child(hp)

		for group in hp.allowed_groups:
			match group:
				"primary":   _primary_hardpoints.append(hp)
				"secondary": _secondary_hardpoints.append(hp)
				"missile":   _missile_hardpoints.append(hp)


## Resolve a 2D hardpoint offset from a named Node3D marker in the ship's 3D model.
##
## Coordinate convention (GLTF/Godot 3D → top-down 2D):
##   Model forward = 3D +Z  →  2D +X  (ship faces right on screen)
##   Model port    = 3D +X  →  2D -Y  (port = up on screen)
##   Formula: Vector2(pos3.z, -pos3.x) * marker_scale
##
## Falls back to Vector2.ZERO and logs a warning when the marker node is not found.
func _offset_from_model(model_node: Node, hp_id: String, marker_scale: float) -> Vector2:
	if model_node == null:
		push_warning("WeaponComponent: no model_node provided; offset for '%s' defaults to zero" % hp_id)
		return Vector2.ZERO

	var marker: Node = model_node.find_child(hp_id, true, false)
	if marker == null:
		push_warning("WeaponComponent: marker node '%s' not found in model; offset defaults to zero" % hp_id)
		return Vector2.ZERO

	if not marker is Node3D:
		push_warning("WeaponComponent: marker '%s' is not a Node3D; offset defaults to zero" % hp_id)
		return Vector2.ZERO

	var pos3: Vector3 = (marker as Node3D).position
	return Vector2(pos3.z, -pos3.x) * marker_scale


## Fire all primary hardpoints toward target_pos. Used by AIController.
func fire_primary_at(target_pos: Vector2) -> void:
	for hp in _primary_hardpoints:
		var aim_dir := (target_pos - hp.get_world_position()).normalized()
		hp.request_fire(aim_dir, target_pos)


## Fire all secondary hardpoints toward target_pos. Used by AIController.
func fire_secondary_at(target_pos: Vector2) -> void:
	for hp in _secondary_hardpoints:
		var aim_dir := (target_pos - hp.get_world_position()).normalized()
		hp.request_fire(aim_dir, target_pos)


## Swap the weapon on a specific hardpoint. Called by LoadoutUI at dock time.
## weapon_data must be a full weapon dictionary from ContentRegistry.
## Returns true on success, false if the hardpoint is not found or the weapon size does not match.
func set_hardpoint_weapon(hardpoint_id: String, weapon_data: Dictionary) -> bool:
	var hp := get_hardpoint(hardpoint_id)
	if hp == null:
		push_error("WeaponComponent: hardpoint '%s' not found" % hardpoint_id)
		return false

	if not hp.can_accept_weapon(weapon_data):
		push_warning(
			"WeaponComponent: size mismatch — weapon '%s' (%s) cannot mount on hardpoint '%s' (%s)" % [
				weapon_data.get("display_name", weapon_data.get("_id", "?")),
				weapon_data.get("size", "?"),
				hardpoint_id,
				hp.size
			]
		)
		return false

	# Stop any continuous fire on this hardpoint before swapping.
	_active_beams.erase(hp)
	var weapon_id: String = weapon_data.get("id", weapon_data.get("_id", ""))
	if not weapon_id.is_empty():
		_weapons_data[weapon_id] = weapon_data
		hp.set_weapon(weapon_id, _weapons_data)
	else:
		hp.weapon_data = {}
	return true
