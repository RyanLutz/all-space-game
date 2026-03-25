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
var _projectile_manager: Node

var _weapons_data: Dictionary = {}

# Beam weapon continuous fire state
var _active_beams: Array[HardpointComponent] = []


func _ready() -> void:
	_ship = get_parent() as Ship
	_event_bus = get_node("/root/GameEventBus")
	_projectile_manager = get_node("/root/ProjectileManager")

	_load_weapons_data()
	_spawn_hardpoints()


func _load_weapons_data() -> void:
	var file = FileAccess.open("res://data/weapons.json", FileAccess.READ)
	if not file:
		push_error("WeaponComponent: Failed to load weapons.json")
		return

	var json = JSON.new()
	json.parse(file.get_as_text())
	var data = json.get_data()
	file.close()

	if not data or not data.has("weapons"):
		push_error("WeaponComponent: Invalid weapons.json format")
		return

	for weapon in data.weapons:
		_weapons_data[weapon.id] = weapon


func _spawn_hardpoints() -> void:
	# If no configs provided, use defaults for testing
	if hardpoint_configs.is_empty():
		hardpoint_configs = [
			{
				"id": "hp_nose",
				"offset": Vector2(32, 0),
				"facing": 0.0,
				"arc_degrees": 25.0,
				"size": "medium",
				"groups": ["primary"],
				"weapon_id": "autocannon_light"
			},
			{
				"id": "hp_port",
				"offset": Vector2(-8, -20),
				"facing": 270.0,
				"arc_degrees": 120.0,
				"size": "small",
				"groups": ["secondary"],
				"weapon_id": "pulse_laser"
			},
			{
				"id": "hp_starboard",
				"offset": Vector2(-8, 20),
				"facing": 90.0,
				"arc_degrees": 120.0,
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

	for config in hardpoint_configs:
		var hp := HardpointComponent.new()
		hp.name = config.get("id", "hardpoint")
		hp.hardpoint_id = config.get("id", "")
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


func _unhandled_input(event: InputEvent) -> void:
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
