extends Node
class_name GameOrchestrator

## System coordinator for the main game loop.
## Loads systems, spawns player and enemies, executes warp transitions,
## and wires all fleet-command subsystems.

# ─── Config (loaded from world_config.json) ─────────────────────────────────
var _config: Dictionary = {}
var _solar_cfg: Dictionary = {}

# ─── State ──────────────────────────────────────────────────────────────────
var _is_transitioning: bool = false
var _player_ship: RigidBody3D = null
var _current_system: SolarSystem = null
var _ship_factory: ShipFactory = null

# ─── Sibling references (resolved in _ready) ────────────────────────────────
var _world: Node3D = null
var _game_camera: Camera3D = null
var _fade_rect: ColorRect = null
var _in_galaxy_map: bool = false

# ─── Autoload references ────────────────────────────────────────────────────
var _event_bus: Node = null
var _starfield: Node = null
var _perf: Node = null
var _service_locator: Node = null


func _ready() -> void:
	_service_locator = Engine.get_singleton("ServiceLocator")
	if _service_locator == null:
		push_error("[GameOrchestrator] ServiceLocator not found.")
		return

	_event_bus = _service_locator.GetService("GameEventBus")
	_perf = _service_locator.GetService("PerformanceMonitor")
	_starfield = get_node_or_null("/root/StarField")

	_load_config()
	_resolve_sibling_references()
	_setup_fleet_command()
	_setup_input()

	# Listen for warp selections from the galactic map
	if _event_bus:
		_event_bus.warp_destination_selected.connect(_on_warp_destination_selected)

	# Defer starting system load so all sibling _ready() methods have fired
	# (e.g. GameCamera can find the player ship when it spawns)
	call_deferred("_load_starting_system")


# ─── Configuration ──────────────────────────────────────────────────────────

func _load_config() -> void:
	var file := FileAccess.open("res://data/world_config.json", FileAccess.READ)
	if file == null:
		push_error("[GameOrchestrator] Cannot open world_config.json")
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("[GameOrchestrator] JSON parse error in world_config.json")
		return

	var data: Dictionary = json.data
	_config = data.get("orchestrator", {})
	_solar_cfg = data.get("solar_system", {})


# ─── Scene references ───────────────────────────────────────────────────────

func _resolve_sibling_references() -> void:
	var main := get_parent()
	_world = main.get_node_or_null("World")
	_game_camera = main.get_node_or_null("GameCamera")
	_fade_rect = main.get_node_or_null("TransitionLayer/FadeRect")
	# Galaxy map is now a camera-attached child; GameCamera owns toggle input



# ─── Fleet Command wiring ───────────────────────────────────────────────────

func _setup_fleet_command() -> void:
	# InputManager
	var input_mgr := InputManager.new()
	input_mgr.name = "InputManager"
	if _game_camera:
		input_mgr.set_camera(_game_camera)
	add_child(input_mgr)

	# SelectionState
	var selection_state := SelectionState.new()
	selection_state.name = "SelectionState"
	add_child(selection_state)

	# TacticalInputHandler
	var tactical_input := TacticalInputHandler.new()
	tactical_input.name = "TacticalInputHandler"
	tactical_input.set_selection_state(selection_state)
	add_child(tactical_input)

	# EscortQueue
	var escort_queue := EscortQueue.new()
	escort_queue.name = "EscortQueue"
	add_child(escort_queue)

	# StanceController
	var stance_controller := StanceController.new()
	stance_controller.name = "StanceController"
	add_child(stance_controller)
	_service_locator.Register("StanceController", stance_controller)

	# FormationController
	var formation_controller := FormationController.new()
	formation_controller.name = "FormationController"
	formation_controller.set_escort_queue(escort_queue)
	add_child(formation_controller)

	# ShipFactory
	_ship_factory = ShipFactory.new()
	_ship_factory.name = "ShipFactory"
	add_child(_ship_factory)

	# Tactical UI layer (CanvasLayer)
	var tactical_ui := CanvasLayer.new()
	tactical_ui.name = "TacticalUI"
	tactical_ui.layer = 5
	get_parent().add_child.call_deferred(tactical_ui)

	# ContextMenu
	var context_menu := TacticalContextMenu.new()
	context_menu.name = "ContextMenu"
	context_menu.set_escort_queue(escort_queue)
	tactical_ui.add_child(context_menu)

	# EscortPanel
	var escort_panel := EscortPanel.new()
	escort_panel.name = "EscortPanel"
	escort_panel.anchor_left = 1.0
	escort_panel.anchor_right = 1.0
	escort_panel.anchor_top = 0.0
	escort_panel.anchor_bottom = 0.0
	escort_panel.offset_left = -220
	escort_panel.offset_right = -10
	escort_panel.offset_top = 10
	escort_panel.offset_bottom = 200
	tactical_ui.add_child(escort_panel)


# ─── Input ──────────────────────────────────────────────────────────────────

func _setup_input() -> void:
	# Galaxy map toggle is handled by GameCamera.
	pass


func _input(event: InputEvent) -> void:
	# Galaxy map toggle (M key) is handled by GameCamera._unhandled_input.
	# GameOrchestrator only reacts to the resulting signals (see _ready).
	pass


# ─── System Loading ─────────────────────────────────────────────────────────

func _load_starting_system() -> void:
	var system_id: String = _config.get("starting_system_id", "sol_start")
	var galaxy_seed: int = _starfield.get_galaxy_seed() if _starfield else 8675309

	_load_system(system_id, galaxy_seed, true)


func _load_system(system_id: String, galaxy_seed: int, is_initial: bool = false) -> void:
	if _perf:
		_perf.begin("GameOrchestrator.load_system")

	# 1. Generate manifest
	var gen := SolarSystemGenerator.new()
	var manifest := gen.generate(system_id, galaxy_seed, _load_archetype_config())

	# 2. Instantiate and load SolarSystem
	if _current_system != null and is_instance_valid(_current_system):
		_current_system.queue_free()
		_current_system = null

	var solar_system := SolarSystem.new()
	solar_system.name = "SolarSystem"
	if _world:
		_world.add_child(solar_system)
	else:
		get_parent().add_child(solar_system)

	# Defer load_system so SolarSystem._ready() has fired and child nodes exist
	solar_system.call_deferred("load_system", system_id, galaxy_seed, _load_archetype_config())
	_current_system = solar_system

	# 3. Spawn enemies
	var spawn_zones: Array = manifest.get("spawn_zones", [])
	_spawn_enemies(spawn_zones)
	# 4. Look up / create StarRecord
	var galaxy_pos: Vector3 = _extract_galaxy_position(manifest)
	var record := _find_or_create_star_record(system_id, galaxy_pos)
	if _starfield:
		_starfield.current_system = record

	# 5. Spawn player (initial load only)
	if is_initial:
		var start_pos := Vector3(0.0, 0.0, 5000.0)
		# Ensure start position is outside exclusion radius
		var stars: Array = manifest.get("stars", [])
		if stars.size() > 0:
			var excl: float = float(stars[0].get("exclusion_radius", 2800.0))
			if start_pos.length() < excl + 500.0:
				start_pos = Vector3(0.0, 0.0, excl + 500.0)
		_spawn_player(start_pos)

	if _perf:
		_perf.end("GameOrchestrator.load_system")


func _load_archetype_config() -> Dictionary:
	var file := FileAccess.open("res://data/solar_system_archetypes.json", FileAccess.READ)
	if file == null:
		push_error("[GameOrchestrator] Cannot open solar_system_archetypes.json")
		return {}
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("[GameOrchestrator] JSON parse error in solar_system_archetypes.json")
		return {}
	return json.data


func _extract_galaxy_position(manifest: Dictionary) -> Vector3:
	var gp: Array = manifest.get("galaxy_position", [0.0, 0.0, 0.0])
	if gp.size() >= 3:
		return Vector3(float(gp[0]), float(gp[1]), float(gp[2]))
	return Vector3.ZERO


func _find_or_create_star_record(system_id: String, galaxy_pos: Vector3) -> SFStarRecord:
	if _starfield:
		for star: SFStarRecord in _starfield.get_destinations():
			if star.system_id == StringName(system_id):
				return star

	# Hand-authored system not in procedural catalog — create a temporary record
	var record := SFStarRecord.new()
	record.system_id = StringName(system_id)
	record.galaxy_position = galaxy_pos
	record.is_destination = true
	record.star_type = StringName("yellow_dwarf")
	record.color = Color(1.0, 0.9, 0.5)
	record.brightness = 0.7
	record.apparent_size = 0.0006
	record.warp_range = 12000.0
	return record


# ─── Player Spawn ───────────────────────────────────────────────────────────

func _spawn_player(pos: Vector3) -> void:
	var class_id: String = _config.get("player_ship_class", "axum-fighter-1")
	var variant_id: String = _config.get("player_ship_variant", "axum_fighter_patrol")
	var faction: String = _config.get("player_faction", "militia")

	_player_ship = _ship_factory.spawn_ship(
		class_id,
		variant_id,
		Vector3(pos.x, 0.0, pos.z),
		faction,
		true
	) as RigidBody3D

	if _player_ship == null:
		push_error("[GameOrchestrator] Failed to spawn player ship.")
		return

	print("[GameOrchestrator] Player spawned at %s" % pos)


# ─── Enemy Spawning ─────────────────────────────────────────────────────────

func _spawn_enemies(spawn_zones: Array) -> void:
	if _ship_factory == null:
		return

	for zone in spawn_zones:
		var center := Vector3(
			float(zone.get("position", [0, 0, 0])[0]),
			0.0,
			float(zone.get("position", [0, 0, 0])[2])
		)
		var radius: float = float(zone.get("radius", 500.0))
		var count: int = int(zone.get("ship_count", 1))
		var ship_class: String = zone.get("ship_class", "axum-fighter-1")
		var variant: String = zone.get("variant", "axum_fighter_patrol")
		var faction: String = zone.get("faction", "pirate")
		var ai_profile: String = zone.get("ai_profile", "default")

		for i in count:
			var angle := randf() * TAU
			var dist := randf() * radius
			var pos := center + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)

			var ship := _ship_factory.spawn_ship(
				ship_class,
				variant,
				pos,
				faction,
				false,
				{},
				ai_profile
			)
			if ship:
				ship.add_to_group("enemies")


# ─── Warp Transition ────────────────────────────────────────────────────────

func _on_warp_destination_selected(system_id: StringName) -> void:
	if _is_transitioning:
		return
	_execute_transition(String(system_id))


func _execute_transition(new_system_id: String) -> void:
	if _is_transitioning:
		return
	if _player_ship == null or not is_instance_valid(_player_ship):
		push_error("[GameOrchestrator] No player ship for transition.")
		return
	if _starfield == null:
		push_error("[GameOrchestrator] StarField not available for transition.")
		return

	_is_transitioning = true

	# Config values
	var entry_distance: float = float(_config.get("entry_distance", 4500.0))
	var exit_thrust_duration: float = float(_config.get("exit_thrust_duration", 2.0))
	var fly_in_duration: float = float(_config.get("fly_in_duration", 2.5))
	var fade_duration: float = float(_config.get("fade_duration", 0.6))
	var cinematic_thrust_fraction: float = float(_config.get("cinematic_thrust_fraction", 1.0))
	var fly_in_thrust_fraction: float = float(_config.get("fly_in_thrust_fraction", 0.7))

	# 3. Close galactic map
	if _event_bus:
		_event_bus.galactic_map_toggled.emit(false)

	# 4. Compute approach direction
	var current_record: SFStarRecord = _starfield.current_system
	if current_record == null:
		push_error("[GameOrchestrator] current_system is null — cannot compute approach direction.")
		_is_transitioning = false
		return

	var dest_record: SFStarRecord = null
	for star: SFStarRecord in _starfield.get_destinations():
		if star.system_id == StringName(new_system_id):
			dest_record = star
			break

	if dest_record == null:
		push_error("[GameOrchestrator] Destination system '%s' not found in StarField." % new_system_id)
		_is_transitioning = false
		return

	var approach_dir: Vector3 = dest_record.galaxy_position - current_record.galaxy_position
	approach_dir.y = 0.0
	if approach_dir.length() < 0.001:
		approach_dir = Vector3.FORWARD
	else:
		approach_dir = approach_dir.normalized()

	# 5. Enable cinematic mode
	if _event_bus:
		_event_bus.cinematic_active_changed.emit(true)

	# Cancel any active tactical orders on the player ship so AIController
	# does not fight the cinematic override.
	var ai: AIController = _player_ship.get_node_or_null("AIController") as AIController
	if ai:
		ai.cancel_flight_override()

	# 6. Drive player ship toward exit
	var exit_dest := _player_ship.global_position + approach_dir * 15000.0
	_player_ship.input_aim_target = exit_dest
	_player_ship.input_forward = cinematic_thrust_fraction

	# 7. Await exit thrust duration
	await get_tree().create_timer(exit_thrust_duration).timeout

	# 8. Fade to black
	if _fade_rect:
		var tween := create_tween()
		tween.tween_property(_fade_rect, "modulate:a", 1.0, fade_duration)
		await tween.finished

	# 9. Free current SolarSystem
	if _current_system != null and is_instance_valid(_current_system):
		_current_system.queue_free()
		_current_system = null

	# 10. Free all AI ships and enemies
	for group in ["ai_ships", "enemies"]:
		for ship in get_tree().get_nodes_in_group(group):
			if is_instance_valid(ship):
				ship.queue_free()

	# 11-12. Generate and load new system
	var galaxy_seed: int = _starfield.get_galaxy_seed()
	_load_system(new_system_id, galaxy_seed, false)

	# 13. Compute entry point
	var entry_point := -approach_dir * entry_distance
	# Ensure outside star exclusion radius
	var manifest: Dictionary = _current_system.get_manifest() if _current_system != null else {}
	var stars: Array = manifest.get("stars", [])
	var exclusion_radius: float = 2800.0
	if stars.size() > 0:
		exclusion_radius = float(stars[0].get("exclusion_radius", 2800.0))
	if entry_point.length() < exclusion_radius + 500.0:
		entry_point = -approach_dir * (exclusion_radius + 500.0)
	entry_point.y = 0.0

	# 14. Reposition player ship
	_player_ship.global_position = entry_point

	# 15. Set rotation to face approach_dir
	_player_ship.rotation.y = atan2(-approach_dir.x, -approach_dir.z)

	# 16. Zero velocity (freeze briefly during black screen)
	_player_ship.freeze = true
	_player_ship.linear_velocity = Vector3.ZERO
	_player_ship.angular_velocity = Vector3.ZERO
	_player_ship.freeze = false
	_player_ship.reset_physics_interpolation()

	# 17. Update StarField already done in _load_system
	# 18. Spawn enemies already done in _load_system

	# 19. Fade from black
	if _fade_rect:
		var tween := create_tween()
		tween.tween_property(_fade_rect, "modulate:a", 0.0, fade_duration)
		await tween.finished

	# 20. Drive player ship forward along approach_dir
	var fly_in_dest := entry_point + approach_dir * 2500.0
	_player_ship.input_aim_target = fly_in_dest
	_player_ship.input_forward = fly_in_thrust_fraction

	# 21. Await fly-in duration
	await get_tree().create_timer(fly_in_duration).timeout

	# 22. Stop nav override — hold position
	_player_ship.input_forward = 0.0
	_player_ship.input_strafe = 0.0

	# 23. Disable cinematic mode
	if _event_bus:
		_event_bus.cinematic_active_changed.emit(false)

	# 24. Emit transition complete
	if _event_bus:
		_event_bus.system_transition_complete.emit(new_system_id)

	# 25. Clear flag
	_is_transitioning = false

	print("[GameOrchestrator] Transition to '%s' complete." % new_system_id)
