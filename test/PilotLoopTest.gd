extends Node3D

## Step 12/13 — Player vs AI, Pilot + Tactical mode loop (integration test).
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

var _player_ship: Ship = null
var _camera: Camera3D = null
var _ship_factory: ShipFactory = null
var _input_manager: InputManager = null
var _selection_state: SelectionState = null
var _tactical_input: TacticalInputHandler = null

@export_group("Player ship")
@export var player_class_id: String = "axum-fighter-1"
@export var player_variant_id: String = "axum_fighter_interceptor"
@export var player_faction: String = "axum"
@export var player_spawn: Vector3 = Vector3.ZERO

@export_group("AI ship")
@export var ai_class_id: String = "axum-fighter-1"
@export var ai_variant_id: String = "axum_fighter_patrol"
@export var ai_faction: String = "pirate"
@export var ai_spawn: Vector3 = Vector3(60, 0, 0)
@export var ai_profile_id: String = "default"


func _ready() -> void:
	print("[PilotLoopTest] Starting — Step 12/13 Pilot + Tactical loop.")

	var service_locator := Engine.get_singleton("ServiceLocator")
	if service_locator == null:
		push_error("[PilotLoopTest] ServiceLocator not found. Autoload GameBootstrap required.")
		return

	_camera = $GameCamera as Camera3D
	if _camera == null:
		push_error("[PilotLoopTest] GameCamera child missing.")
		return

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

	# Ship spawning
	_ship_factory = ShipFactory.new()
	_ship_factory.name = "ShipFactory"
	add_child(_ship_factory)

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

	var ai_ship := _ship_factory.spawn_ship(
		ai_class_id,
		ai_variant_id,
		ai_spawn,
		ai_faction,
		false,
		{},
		ai_profile_id
	)
	if ai_ship == null:
		push_error("[PilotLoopTest] Failed to spawn AI ship.")

	print("[PilotLoopTest] Player: %s  |  AI spawned: %s" % [
		_player_ship.display_name,
		"yes" if ai_ship != null else "no"
	])
	print("[PilotLoopTest] WASD = thrust  |  Mouse = aim  |  Scroll = zoom  |  LMB/RMB = fire  |  Tab = mode toggle")
