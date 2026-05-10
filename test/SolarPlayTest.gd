extends Node3D

const EscortQueue          := preload("res://gameplay/fleet_command/EscortQueue.gd")
const FormationController  := preload("res://gameplay/fleet_command/FormationController.gd")
const StanceController     := preload("res://gameplay/fleet_command/StanceController.gd")
const TacticalContextMenu  := preload("res://ui/tactical/ContextMenu.gd")
const EscortPanel          := preload("res://ui/tactical/EscortPanel.gd")

## Full-system play scene for SolarSystem session D tuning and ongoing play testing.
##
## Combines: SolarSystem + ChunkStreamer + Pilot mode + Tactical mode + WarpDrive.
## ChunkStreamer automatically waits for system_loaded and applies belt density.
##
## Controls — Pilot mode:
##   WASD / Arrow keys  — thrust
##   Mouse              — aim
##   Scroll             — zoom
##   LMB / RMB          — fire groups 1 / 2
##   Y (hold)           — manual warp charge; release to disengage
##   Right-click        — warp plot menu (when distant from player)
##   Tab                — switch to Tactical mode
##
## Controls — Tactical mode:
##   WASD               — pan camera
##   Scroll             — zoom
##   Left-click / drag  — select fleet ships
##   Right-click        — move / attack / context menu
##   Tab / Esc          — back to Pilot mode
##
## Debug:
##   F3                 — toggle performance overlay

@export_group("System")
@export var galaxy_seed: int = 8675309
@export var start_system_id: String = "sys_00000"

@export_group("Player ship")
@export var player_class_id: String = "axum-fighter-1"
@export var player_variant_id: String = "axum_fighter_interceptor"
@export var player_faction: String = "axum"

@export_group("Fleet ships")
@export var spawn_fleet: bool = true
@export var fleet_class_id: String = "axum-fighter-1"
@export var fleet_variant_id: String = "axum_fighter_patrol"

var _player_ship: Ship = null
var _camera: Camera3D = null
var _solar_system: SolarSystem = null
var _ship_factory: ShipFactory = null
var _chunk_streamer: ChunkStreamer = null
var _input_manager: InputManager = null
var _selection_state: SelectionState = null
var _tactical_input: TacticalInputHandler = null


func _ready() -> void:
	var sl := Engine.get_singleton("ServiceLocator")
	if sl == null:
		push_error("[SolarPlayTest] ServiceLocator not found.")
		return

	_camera = $GameCamera as Camera3D
	if _camera == null:
		push_error("[SolarPlayTest] GameCamera missing.")
		return

	# ─── Solar system ──────────────────────────────────────────────────────────
	var archetype_cfg := _load_archetypes()
	if archetype_cfg.is_empty():
		push_error("[SolarPlayTest] Cannot load solar_system_archetypes.json.")
		return

	_solar_system = SolarSystem.new()
	_solar_system.name = "SolarSystem"
	add_child(_solar_system)
	_solar_system.load_system(start_system_id, galaxy_seed, archetype_cfg)

	# ─── Fleet Command ─────────────────────────────────────────────────────────
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

	var escort_queue := EscortQueue.new()
	escort_queue.name = "EscortQueue"
	add_child(escort_queue)

	var stance_controller := StanceController.new()
	stance_controller.name = "StanceController"
	add_child(stance_controller)
	sl.Register("StanceController", stance_controller)

	var formation_controller := FormationController.new()
	formation_controller.name = "FormationController"
	formation_controller.set_escort_queue(escort_queue)
	add_child(formation_controller)

	var tactical_ui := CanvasLayer.new()
	tactical_ui.name = "TacticalUI"
	tactical_ui.layer = 10
	add_child(tactical_ui)

	var context_menu := TacticalContextMenu.new()
	context_menu.name = "ContextMenu"
	context_menu.set_escort_queue(escort_queue)
	tactical_ui.add_child(context_menu)

	var escort_panel := EscortPanel.new()
	escort_panel.name = "EscortPanel"
	escort_panel.anchor_left   = 1.0
	escort_panel.anchor_right  = 1.0
	escort_panel.anchor_top    = 0.0
	escort_panel.anchor_bottom = 0.0
	escort_panel.offset_left   = -220
	escort_panel.offset_right  = -10
	escort_panel.offset_top    = 10
	escort_panel.offset_bottom = 200
	tactical_ui.add_child(escort_panel)

	# ─── Ships ─────────────────────────────────────────────────────────────────
	_ship_factory = ShipFactory.new()
	_ship_factory.name = "ShipFactory"
	add_child(_ship_factory)

	_player_ship = _ship_factory.spawn_ship(
		player_class_id, player_variant_id,
		Vector3(8000.0, 0.0, 0.0), player_faction, true) as Ship

	if _player_ship == null:
		push_error("[SolarPlayTest] Failed to spawn player ship.")
		return

	if spawn_fleet:
		for offset in [Vector3(7970, 0, 20), Vector3(8030, 0, 20)]:
			var fs := _ship_factory.spawn_ship(
				fleet_class_id, fleet_variant_id,
				offset, player_faction, false, {}, "fleet_default")
			if fs:
				fs.add_to_group("player_fleet")

	# ─── ChunkStreamer (waits for system_loaded automatically) ─────────────────
	_chunk_streamer = ChunkStreamer.new()
	_chunk_streamer.name = "ChunkStreamer"
	add_child(_chunk_streamer)
	_chunk_streamer.set_follow_target(_player_ship)


func _load_archetypes() -> Dictionary:
	var file := FileAccess.open("res://data/solar_system_archetypes.json", FileAccess.READ)
	if not file:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		return {}
	file.close()
	return json.data
