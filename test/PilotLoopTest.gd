extends Node3D

const EscortQueue := preload("res://gameplay/fleet_command/EscortQueue.gd")
const FormationController := preload("res://gameplay/fleet_command/FormationController.gd")
const StanceController := preload("res://gameplay/fleet_command/StanceController.gd")
const TacticalContextMenu := preload("res://ui/tactical/ContextMenu.gd")
const EscortPanel := preload("res://ui/tactical/EscortPanel.gd")

## Step 12/13/14 — Player vs AI, Pilot + Tactical mode loop, Fleet Command.
##
## Controls (Pilot mode):
##   W / S / A / D  — thrust (InputMap: move_forward, move_backward, move_left, move_right)
##   Mouse          — aim (GameCamera cursor ray → XZ plane)
##   Scroll         — zoom (GameCamera)
##   LMB / RMB      — weapon groups 1 and 2
##
## Controls (Tactical mode — Tab to toggle):
##   W / S / A / D  — camera pan
##   Mouse          — edge-scroll pan
##   Scroll         — zoom
##   Left-click     — select fleet ship (Shift = toggle)
##   Drag           — box select fleet ships
##   Right-click    — move/attack/context menu order
##   Esc / S        — stop selected ships
##
## Manual verification checklist:
##   [ ] Player ship thrusts and rotates toward aim point; Y stays on the play plane
##   [ ] GameCamera follows player; cursor lead and zoom behave as in CameraTest
##   [ ] Tab toggles between Pilot and Tactical mode; camera zooms out/in
##   [ ] In Tactical: WASD pans camera, edge-scroll works, click selects fleet ships
##   [ ] AI ship patrols / engages per ai_profile_id (see data/ai_profiles.json)
##   [ ] Primary and secondary fire spawn projectiles; impacts register
##   [ ] Ships can be destroyed; GameEventBus ship_destroyed / player flow makes sense
##   [ ] Fleet ships receive move orders (right-click empty space)
##   [ ] Fleet ships receive attack orders (right-click enemy)
##   [ ] Right-click fleet ship opens context menu (Stance + Escort submenus)
##   [ ] Add to escort → ship follows player in V-Wing formation (pilot mode)
##   [ ] Escort panel shows queue and stance selector
##   [ ] Stop key halts selected ships

var _player_ship: Ship = null
var _camera: Camera3D = null
var _ship_factory: ShipFactory = null
var _input_manager: InputManager = null
var _selection_state: SelectionState = null
var _tactical_input: TacticalInputHandler = null
var _escort_queue: EscortQueue = null
var _formation_controller: FormationController = null
var _stance_controller: StanceController = null
var _context_menu: TacticalContextMenu = null
var _escort_panel: EscortPanel = null
var _cursor_indicator: MeshInstance3D = null
var _debug_grid: MeshInstance3D = null
var _debug_visible: bool = false

@export_group("Player ship")
@export var player_class_id: String = "axum-fighter-1"
@export var player_variant_id: String = "axum_fighter_interceptor"
@export var player_faction: String = "axum"
@export var player_spawn: Vector3 = Vector3.ZERO

@export_group("AI enemy")
@export var ai_class_id: String = "axum-fighter-1"
@export var ai_variant_id: String = "axum_fighter_patrol"
@export var ai_faction: String = "pirate"
@export var ai_spawn: Vector3 = Vector3(200, 0, 0)
@export var ai_profile_id: String = "default"

@export_group("Fleet ships")
@export var fleet_class_id: String = "axum-fighter-1"
@export var fleet_variant_id: String = "axum_fighter_patrol"
@export var fleet_spawn_1: Vector3 = Vector3(-30, 0, 20)
@export var fleet_spawn_2: Vector3 = Vector3(30, 0, 20)


func _ready() -> void:
	print("[PilotLoopTest] Starting — Step 14 Fleet Command integration.")

	var service_locator := Engine.get_singleton("ServiceLocator")
	if service_locator == null:
		push_error("[PilotLoopTest] ServiceLocator not found. Autoload GameBootstrap required.")
		return

	_camera = $GameCamera as Camera3D
	if _camera == null:
		push_error("[PilotLoopTest] GameCamera child missing.")
		return

	# ─── Cursor indicator ──────────────────────────────────────────────
	_cursor_indicator = _create_cursor_indicator()
	add_child(_cursor_indicator)

	# ─── Debug grid ────────────────────────────────────────────────────
	_debug_grid = _create_debug_grid()
	_debug_grid.visible = false
	add_child(_debug_grid)

	# ─── Fleet Command components ──────────────────────────────────────
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

	_escort_queue = EscortQueue.new()
	_escort_queue.name = "EscortQueue"
	add_child(_escort_queue)

	_stance_controller = StanceController.new()
	_stance_controller.name = "StanceController"
	add_child(_stance_controller)

	# Register StanceController so AIController can find it
	service_locator.Register("StanceController", _stance_controller)

	_formation_controller = FormationController.new()
	_formation_controller.name = "FormationController"
	_formation_controller.set_escort_queue(_escort_queue)
	add_child(_formation_controller)

	# ─── Tactical UI (CanvasLayer) ─────────────────────────────────────
	var tactical_ui := CanvasLayer.new()
	tactical_ui.name = "TacticalUI"
	tactical_ui.layer = 10
	add_child(tactical_ui)

	_context_menu = TacticalContextMenu.new()
	_context_menu.name = "ContextMenu"
	_context_menu.set_escort_queue(_escort_queue)
	tactical_ui.add_child(_context_menu)

	_escort_panel = EscortPanel.new()
	_escort_panel.name = "EscortPanel"
	# Anchor escort panel to top-right
	_escort_panel.anchor_left = 1.0
	_escort_panel.anchor_right = 1.0
	_escort_panel.anchor_top = 0.0
	_escort_panel.anchor_bottom = 0.0
	_escort_panel.offset_left = -220
	_escort_panel.offset_right = -10
	_escort_panel.offset_top = 10
	_escort_panel.offset_bottom = 200
	tactical_ui.add_child(_escort_panel)

	# ─── Ship spawning ─────────────────────────────────────────────────
	_ship_factory = ShipFactory.new()
	_ship_factory.name = "ShipFactory"
	add_child(_ship_factory)

	# Player ship
	_player_ship = _ship_factory.spawn_ship(
		player_class_id,
		player_variant_id,
		player_spawn,
		player_faction,
		true
	) as Ship

	if _player_ship == null:
		push_error("[PilotLoopTest] Failed to spawn player ship.")
		return

	# Enemy AI ship
	var ai_ship := _ship_factory.spawn_ship(
		ai_class_id,
		ai_variant_id,
		ai_spawn,
		ai_faction,
		false,
		{},
		ai_profile_id
	)
	if ai_ship:
		ai_ship.add_to_group("enemies")
	else:
		push_error("[PilotLoopTest] Failed to spawn AI enemy ship.")

	# Fleet ships (player faction, fleet AI profile)
	var fleet_spawns := [fleet_spawn_1, fleet_spawn_2]
	for i in fleet_spawns.size():
		var fleet_ship := _ship_factory.spawn_ship(
			fleet_class_id,
			fleet_variant_id,
			fleet_spawns[i],
			player_faction,
			false,
			{},
			"fleet_default"
		)
		if fleet_ship:
			fleet_ship.add_to_group("player_fleet")
			print("[PilotLoopTest] Fleet ship %d spawned: %s" % [i + 1, fleet_ship.display_name])
		else:
			push_error("[PilotLoopTest] Failed to spawn fleet ship %d." % (i + 1))

	print("[PilotLoopTest] Player: %s  |  Enemy: %s  |  Fleet ships: 2" % [
		_player_ship.display_name,
		"yes" if ai_ship != null else "no"
	])
	print("[PilotLoopTest] WASD = thrust  |  Mouse = aim  |  Scroll = zoom  |  LMB/RMB = fire  |  Tab = mode toggle")
	print("[PilotLoopTest] Tactical: click/drag select  |  R-click = order  |  R-click fleet ship = context menu")


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.pressed and event.keycode == KEY_F3:
			_debug_visible = not _debug_visible
			if _debug_grid:
				_debug_grid.visible = _debug_visible
			# Emit signal to all systems that need to toggle debug visuals
			var service_locator := Engine.get_singleton("ServiceLocator")
			var event_bus: Node = service_locator.GetService("GameEventBus")
			if event_bus:
				event_bus.debug_toggled.emit(_debug_visible)


func _process(_delta: float) -> void:
	if _cursor_indicator and _camera:
		var cursor_pos: Vector3 = _camera.get_cursor_world_position()
		cursor_pos.y = 0.5
		_cursor_indicator.global_position = cursor_pos


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


func _create_debug_grid() -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "DebugGrid"

	var plane := PlaneMesh.new()
	plane.size = Vector2(10000, 10000)
	mesh_instance.mesh = plane

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1, 1, 1)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	# Load the grid texture
	var texture_path := "res://assets/textures/debug/grid.png"
	if FileAccess.file_exists(texture_path):
		var texture := load(texture_path)
		material.albedo_texture = texture
		material.uv1_scale = Vector3(50, 50, 1)
	else:
		push_warning("Debug grid texture not found at " + texture_path + " — grid will be invisible until texture is provided")

	mesh_instance.material_override = material
	return mesh_instance
