extends Node3D

## CombatTest — Dedicated combat balancing scene
## Spawns player + multiple AI enemies with varied weapon loadouts
## All ships use axum-fighter-1 (only ship with model)

const EscortQueue := preload("res://gameplay/fleet_command/EscortQueue.gd")
const FormationController := preload("res://gameplay/fleet_command/FormationController.gd")
const StanceController := preload("res://gameplay/fleet_command/StanceController.gd")

## Controls (Pilot mode):
##   W / S / A / D  — thrust
##   Mouse          — aim
##   Scroll         — zoom
##   LMB / RMB      — weapon groups 1 and 2
##   F3             — toggle debug overlay
##
## Controls (Tactical mode — Tab to toggle):
##   WASD           — camera pan
##   Click/Drag     — select ships
##   Right-click    — move/attack order
##   S / Esc        — stop selected
##
## Combat Test Features:
##   [ ] Player: Mixed loadout (port=autocannon LMB, stbd=pulse_laser RMB) - interceptor (2x sharps fixed)
##   [ ] Enemy 1: 2x autocannon (gimbal kinetic) - patrol variant (2x donut gimbal)
##   [ ] Enemy 2: 2x pulse laser (gimbal shield stripper) - patrol variant
##   [ ] Dummy target: Stationary for weapon testing

var _player_ship: Ship = null
var _camera: Camera3D = null
var _ship_factory: ShipFactory = null
var _input_manager: InputManager = null
var _selection_state: SelectionState = null
var _tactical_input: TacticalInputHandler = null
var _stance_controller: StanceController = null
var _cursor_indicator: MeshInstance3D = null
var _debug_visible: bool = false

# Debug UI
var _debug_canvas: CanvasLayer = null
var _debug_labels: Dictionary = {}
var _perf_monitor: Node = null

@export_group("Player Ship")
@export var player_variant: String = "axum_fighter_interceptor"
@export var player_faction: String = "axum"

@export_group("Enemy Ships")
@export var enemy_variant: String = "axum_fighter_patrol"
@export var enemy_faction: String = "pirate"
@export var enemy_profile: String = "default"

@export_group("Dummy Target")
@export var spawn_dummy_target: bool = true
@export var dummy_target_hp: float = 1000.0

func _ready() -> void:
	print("[CombatTest] Initializing combat test scene...")

	var service_locator := Engine.get_singleton("ServiceLocator")
	if service_locator == null:
		push_error("[CombatTest] ServiceLocator not found. Autoload GameBootstrap required.")
		return

	_perf_monitor = service_locator.GetService("PerformanceMonitor")

	# Connect to weapon fire signals for debugging
	var event_bus: Node = service_locator.GetService("GameEventBus")
	if event_bus:
		event_bus.weapon_fired.connect(_on_weapon_fired)
		event_bus.request_spawn_dumb.connect(_on_request_spawn_dumb)
		event_bus.request_fire_hitscan.connect(_on_request_fire_hitscan)

	_camera = $GameCamera as Camera3D
	if _camera == null:
		push_error("[CombatTest] GameCamera child missing.")
		return

	# Cursor indicator
	_cursor_indicator = _create_cursor_indicator()
	add_child(_cursor_indicator)

	# Debug UI (hidden by default)
	_setup_debug_ui()

	# Fleet command components
	_input_manager = InputManager.new()
	_input_manager.name = "InputManager"
	_input_manager.set_camera(_camera)
	add_child(_input_manager)

	_selection_state = SelectionState.new()
	_selection_state.name = "SelectionState"
	add_child(_selection_state)

	_tactical_input = TacticalInputHandler.new()
	_tactical_input.name = "TacticalInputHandler"
	_tactical_input.set_selection_state(_selection_state)
	add_child(_tactical_input)

	_stance_controller = StanceController.new()
	_stance_controller.name = "StanceController"
	add_child(_stance_controller)
	service_locator.Register("StanceController", _stance_controller)

	# Ship factory
	_ship_factory = ShipFactory.new()
	_ship_factory.name = "ShipFactory"
	add_child(_ship_factory)

	# Spawn all combatants
	_spawn_player()
	_spawn_enemies()
	if spawn_dummy_target:
		_spawn_dummy_target()

	print("[CombatTest] Combatants spawned. WASD=thrust | Mouse=aim | LMB/RMB=fire | Tab=Tactical | F3=Debug")
	print("[CombatTest] Enemy 1: 2x autocannon (gimbal) | Enemy 2: 2x pulse (gimbal)")

	# Verify weapons after a frame delay (allow ShipFactory to finish setup)
	call_deferred("_verify_weapons")


func _setup_debug_ui() -> void:
	_debug_canvas = CanvasLayer.new()
	_debug_canvas.name = "DebugCanvas"
	_debug_canvas.visible = false
	add_child(_debug_canvas)

	var panel := Panel.new()
	panel.name = "DebugPanel"
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(10, 10)
	panel.size = Vector2(350, 400)

	# Semi-transparent dark background
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.85)
	style.border_color = Color(0.3, 0.3, 0.3, 1)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	panel.add_theme_stylebox_override("panel", style)
	_debug_canvas.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.name = "DebugVBox"
	vbox.position = Vector2(10, 10)
	vbox.size = Vector2(330, 380)
	panel.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "=== COMBAT DEBUG ==="
	title.add_theme_color_override("font_color", Color(0, 1, 0.5))
	vbox.add_child(title)

	# Separator
	vbox.add_child(HSeparator.new())

	# Player health section
	_add_debug_section(vbox, "PLAYER", Color(0, 0.8, 1))
	_add_debug_label(vbox, "hp", "HP: --")
	_add_debug_label(vbox, "shields", "Shields: --")
	_add_debug_label(vbox, "power", "Power: --")

	vbox.add_child(HSeparator.new())

	# Hardpoint section
	_add_debug_section(vbox, "HARDPOINTS", Color(1, 0.8, 0))
	_add_debug_label(vbox, "hp_port", "Port: --")
	_add_debug_label(vbox, "hp_stbd", "Stbd: --")

	vbox.add_child(HSeparator.new())

	# Projectiles section
	_add_debug_section(vbox, "PROJECTILES", Color(1, 0.5, 0))
	_add_debug_label(vbox, "projectiles", "Active: --")

	vbox.add_child(HSeparator.new())

	# Input section
	_add_debug_section(vbox, "INPUT", Color(0.8, 0.8, 0.8))
	_add_debug_label(vbox, "fire1", "Group 1 (LMB): --")
	_add_debug_label(vbox, "fire2", "Group 2 (RMB): --")
	_add_debug_label(vbox, "aim", "Aim: --")

	vbox.add_child(HSeparator.new())

	# Performance
	_add_debug_section(vbox, "PERF", Color(0.5, 1, 0.5))
	_add_debug_label(vbox, "fps", "FPS: --")


func _add_debug_section(parent: Node, title: String, color: Color) -> void:
	var label := Label.new()
	label.text = title
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)


func _add_debug_label(parent: Node, key: String, text: String) -> void:
	var label := Label.new()
	label.name = "Label_" + key
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	_debug_labels[key] = label
	parent.add_child(label)


func _update_debug_ui() -> void:
	if not _debug_visible or _player_ship == null:
		return

	# Player stats
	_update_label("hp", "HP: %.0f / %.0f" % [_player_ship.hull_hp, _player_ship.hull_max])
	_update_label("shields", "Shields: %.0f / %.0f" % [_player_ship.shield_hp, _player_ship.shield_max])
	_update_label("power", "Power: %.0f / %.0f" % [_player_ship.power_current, _player_ship.power_capacity])

	# Hardpoint status
	_update_hardpoint_debug()

	# Projectile count
	var proj_count := 0
	if _perf_monitor:
		proj_count = _perf_monitor.get_count("ProjectileManager.active_count")
	_update_label("projectiles", "Active: %d" % proj_count)

	# Input state
	var input_fire := _player_ship.input_fire
	_update_label("fire1", "Group 1 (LMB): %s" % ("FIRING" if (input_fire.size() > 0 and input_fire[0]) else "idle"))
	_update_label("fire2", "Group 2 (RMB): %s" % ("FIRING" if (input_fire.size() > 1 and input_fire[1]) else "idle"))

	var aim := _player_ship.input_aim_target
	_update_label("aim", "Aim: (%.0f, %.0f)" % [aim.x, aim.z])

	# FPS
	_update_label("fps", "FPS: %d" % Engine.get_frames_per_second())


func _update_label(key: String, text: String) -> void:
	var label := _debug_labels.get(key) as Label
	if label:
		label.text = text


func _update_hardpoint_debug() -> void:
	if _player_ship == null:
		return

	var ship_visual := _player_ship.get_node_or_null("ShipVisual")
	if ship_visual == null:
		return

	var port_status := "Port: "
	var stbd_status := "Stbd: "
	var hardpoint_count := 0

	# Search recursively for hardpoints (they're nested under part nodes)
	var all_hardpoints := _find_all_hardpoints(ship_visual)

	for hp_node in all_hardpoints:
		hardpoint_count += 1
		var hp_comp := hp_node.get_node_or_null("HardpointComponent") as HardpointComponent
		if hp_comp == null:
			continue

		var weapon_model := hp_comp.get_weapon_model()
		var heat := hp_comp.heat_current
		var max_heat := hp_comp.heat_capacity
		var overheated := hp_comp.is_overheated

		var status := ""
		if weapon_model:
			# Get weapon name from WeaponComponent
			var weapon_comp := weapon_model.get_node_or_null("WeaponComponent") as WeaponComponent
			var weapon_name := "???"
			if weapon_comp:
				weapon_name = weapon_comp.weapon_id
			# Truncate long names
			if weapon_name.length() > 12:
				weapon_name = weapon_name.substr(0, 12)
			status = "%s %s%.0f%%" % [weapon_name, "[OH] " if overheated else "", (heat / max_heat) * 100]
		else:
			status = "EMPTY"

		var name_lower := hp_node.name.to_lower()
		if "port" in name_lower:
			port_status += status + " | "
		if "stbd" in name_lower or "starboard" in name_lower:
			stbd_status += status + " | "

	# Remove trailing separators
	if port_status.ends_with(" | "):
		port_status = port_status.substr(0, port_status.length() - 3)
	if stbd_status.ends_with(" | "):
		stbd_status = stbd_status.substr(0, stbd_status.length() - 3)

	# If no hardpoints found at all
	if hardpoint_count == 0:
		port_status = "Port: NO HARDPOINTS"
		stbd_status = "Stbd: NO HARDPOINTS"
	else:
		# If specific side not found
		if port_status == "Port: ":
			port_status = "Port: (none)"
		if stbd_status == "Stbd: ":
			stbd_status = "Stbd: (none)"

	_update_label("hp_port", port_status + " (%d found)" % hardpoint_count)
	_update_label("hp_stbd", stbd_status)


func _find_all_hardpoints(node: Node) -> Array[Node]:
	var results: Array[Node] = []
	if node.name.begins_with("HardpointEmpty_"):
		results.append(node)
	for child in node.get_children():
		results.append_array(_find_all_hardpoints(child))
	return results


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.pressed and event.keycode == KEY_F3:
			_debug_visible = not _debug_visible
			if _debug_canvas:
				_debug_canvas.visible = _debug_visible
			# Emit signal to all systems that need to toggle debug visuals
			var service_locator := Engine.get_singleton("ServiceLocator")
			var event_bus: Node = service_locator.GetService("GameEventBus")
			if event_bus:
				event_bus.debug_toggled.emit(_debug_visible)
			print("[CombatTest] Debug overlay: " + ("ON" if _debug_visible else "OFF"))


func _verify_weapons() -> void:
	print("[CombatTest] --- Weapon Verification ---")

	# Check player (hardpoints are nested under part nodes — recursive search)
	if _player_ship:
		var hp_nodes := _find_all_hardpoints(_player_ship.get_node("ShipVisual"))
		var weapon_count := 0
		for hp in hp_nodes:
			var hp_comp = hp.get_node_or_null("HardpointComponent")
			if hp_comp and hp_comp.has_method("has_weapon") and hp_comp.has_weapon():
				weapon_count += 1
				print("[CombatTest] Player hardpoint '%s': WEAPON EQUIPPED (groups=%s)" % [hp.name, str(hp_comp.fire_groups)])
			else:
				print("[CombatTest] Player hardpoint '%s': EMPTY" % hp.name)
		print("[CombatTest] Player total equipped weapons: %d" % weapon_count)

	# Check enemies
	var enemies = get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		var hp_nodes := _find_all_hardpoints(enemy.get_node("ShipVisual"))
		var weapon_count := 0
		for hp in hp_nodes:
			var hp_comp = hp.get_node_or_null("HardpointComponent")
			if hp_comp and hp_comp.has_method("has_weapon") and hp_comp.has_weapon():
				weapon_count += 1
		print("[CombatTest] Enemy '%s': %d weapons equipped" % [enemy.name, weapon_count])


func _process(_delta: float) -> void:
	if _cursor_indicator and _camera:
		var cursor_pos: Vector3 = _camera.get_cursor_world_position()
		cursor_pos.y = 0.5
		_cursor_indicator.global_position = cursor_pos

	# Update debug UI every frame
	_update_debug_ui()


func _spawn_player() -> void:
	var spawn_pos: Vector3 = $SpawnPoints/PlayerSpawn.global_position

	# Player uses interceptor variant which has SHARPS hardpoints only (2x fixed)
	# Mixed loadout: port = autocannon (group 1), stbd = pulse laser (group 2)
	var loadout := {
		"weapons": {
			"sharps_hp_wing_port": "pulse_laser",
			"sharps_hp_wing_stbd": "beam_laser"
		},
		"fire_groups": {
			"sharps_hp_wing_port": [1],   # Group 1 (LMB): kinetic — 1-based per JSON convention
			"sharps_hp_wing_stbd": [2]    # Group 2 (RMB): energy
		}
	}

	_player_ship = _ship_factory.spawn_ship(
		"axum-fighter-1",
		player_variant,
		spawn_pos,
		player_faction,
		true,           # is_player
		loadout,
		"fleet_default" # AI profile (not used for player but needed)
	) as Ship

	if _player_ship:
		print("[CombatTest] Player spawned: Mixed loadout (port=autocannon LMB, stbd=pulse laser RMB)")
	else:
		push_error("[CombatTest] Failed to spawn player ship")


func _spawn_enemies() -> void:
	var spawns := [
		$SpawnPoints/EnemySpawn1,
		$SpawnPoints/EnemySpawn2
	]

	# NOTE: enemy_variant is "axum_fighter_patrol" which has DONUT hardpoints only
	# (sharps hardpoints only exist on interceptor/assault variants)

	# Enemy 1: 2x autocannon on donut hardpoints (gimbal tracking)
	var enemy1_loadout := {
		"weapons": {
			"donut_hp_wing_port": "autocannon_light",
			"donut_hp_wing_stbd": "autocannon_light"
		},
		"fire_groups": {
			"donut_hp_wing_port": [1],
			"donut_hp_wing_stbd": [1]
		}
	}

	# Enemy 2: 2x pulse laser on donut hardpoints (shield stripper with tracking)
	var enemy2_loadout := {
		"weapons": {
			"donut_hp_wing_port": "pulse_laser",
			"donut_hp_wing_stbd": "pulse_laser"
		},
		"fire_groups": {
			"donut_hp_wing_port": [1],
			"donut_hp_wing_stbd": [1]
		}
	}

	var loadouts := [enemy1_loadout, enemy2_loadout]
	var descriptions := [
		"2x autocannon (gimbal)",
		"2x pulse laser (gimbal)"
	]

	for i in spawns.size():
		var spawn_node = spawns[i]
		if spawn_node == null:
			continue

		var enemy_ship := _ship_factory.spawn_ship(
			"axum-fighter-1",
			enemy_variant,  # All use patrol variant with donut hardpoints
			spawn_node.global_position,
			enemy_faction,
			false,          # not player
			loadouts[i],
			enemy_profile
		)

		if enemy_ship:
			enemy_ship.add_to_group("enemies")
			print("[CombatTest] Enemy %d spawned: %s" % [i + 1, descriptions[i]])
		else:
			push_error("[CombatTest] Failed to spawn enemy %d" % (i + 1))


func _spawn_dummy_target() -> void:
	var spawn_pos: Vector3 = $SpawnPoints/DummyTargetSpawn.global_position

	# Spawn a stationary ship with high HP for target practice
	var dummy_ship := _ship_factory.spawn_ship(
		"axum-fighter-1",
		"axum_fighter_patrol",
		spawn_pos,
		"neutral",
		false,
		{},
		"default"
	)

	if dummy_ship:
		dummy_ship.add_to_group("dummy_targets")
		# Disable AI by removing AIController if present
		var ai_ctrl := dummy_ship.get_node_or_null("AIController")
		if ai_ctrl:
			ai_ctrl.queue_free()
		# Make it stationary
		dummy_ship.sleeping = true
		dummy_ship.freeze = true
		print("[CombatTest] Dummy target spawned at (0, 0, 300) — stationary for weapon testing")
	else:
		push_error("[CombatTest] Failed to spawn dummy target")


func _on_weapon_fired(ship: Node, weapon_id: String, pos: Vector3) -> void:
	if ship == _player_ship:
		print("[CombatTest] Player weapon fired: %s at (%.1f, %.1f, %.1f)" % [weapon_id, pos.x, pos.y, pos.z])


func _on_request_spawn_dumb(pos: Vector3, velocity: Vector3, _lifetime: float, weapon_id: String, _owner_id: int) -> void:
	print("[CombatTest] REQUEST spawn dumb: %s at (%.1f, %.1f) vel=(%.1f, %.1f)" % [weapon_id, pos.x, pos.z, velocity.x, velocity.z])


func _on_request_fire_hitscan(origin: Vector3, direction: Vector3, _range_val: float, weapon_id: String, _owner_id: int, _hardpoint_id: String) -> void:
	print("[CombatTest] REQUEST fire hitscan: %s from (%.1f, %.1f) dir=(%.1f, %.1f)" % [weapon_id, origin.x, origin.z, direction.x, direction.z])


func _create_cursor_indicator() -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "CursorIndicator"

	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 5.0
	cylinder.bottom_radius = 5.0
	cylinder.height = 1.0
	mesh_instance.mesh = cylinder

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.0, 0.0)
	material.emission_enabled = true
	material.emission = Color(0.5, 0.0, 0.0)
	mesh_instance.material_override = material

	return mesh_instance
