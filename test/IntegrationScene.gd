extends Node2D

# IntegrationScene — MVP full-loop scene: fly, fight, dock, customize, repeat.
#
# Controls:
#   WASD       — thrust / strafe
#   Mouse      — aim
#   LMB        — fire primary (autocannon / pulse laser)
#   RMB        — fire secondary (beam)
#   Space      — fire missiles
#   F          — dock (when within 200 px of station)
#   Scroll     — zoom camera
#   F3         — performance overlay

const _PLAYER_SHIP_ID := "fighter_light"
const _AI_SHIP_ID     := "corvette_patrol"

const _AI_SPAWNS: Array = [
	["pirate",  Vector2( 1400.0,  -300.0)],
	["pirate",  Vector2(-1100.0,   500.0)],
	["pirate",  Vector2(  900.0,  1000.0)],
	["militia", Vector2(-1500.0,  -700.0)],
	["militia", Vector2(  400.0, -1300.0)],
]

# Station is positioned a comfortable distance from spawn.
const _STATION_POS := Vector2(600.0, 400.0)

var _player_ship: Ship = null
var _ai_ships: Array[Ship] = []
var _ai_states: Dictionary = {}
var _station: Node2D = null

var _hud_label: Label = null
var _hint_label: Label = null
var _docked: bool = false

var _event_bus: Node


func _ready() -> void:
	_event_bus = ServiceLocator.GetService("GameEventBus") as Node

	_setup_background()
	_setup_station()
	_setup_player()
	_setup_camera()
	_setup_chunk_streamer()
	_setup_ai_ships()
	_setup_hud()

	if _event_bus:
		_event_bus.connect("ai_state_changed",  _on_ai_state_changed)
		_event_bus.connect("ship_destroyed",    _on_ship_destroyed)
		_event_bus.connect("dock_complete",     _on_dock_complete)
		_event_bus.connect("undock_requested",  _on_undock)


func _setup_background() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.04, 0.08)
	bg.size = Vector2(16000.0, 16000.0)
	bg.position = Vector2(-8000.0, -8000.0)
	add_child(bg)


func _setup_station() -> void:
	var station_scene := load("res://gameplay/world/Station.tscn")
	if station_scene == null:
		push_error("IntegrationScene: Station.tscn not found")
		return
	_station = station_scene.instantiate()
	_station.global_position = _STATION_POS
	_station.display_name = "Frontier Station"
	add_child(_station)


func _setup_player() -> void:
	var factory := ShipFactory.new()
	_player_ship = factory.spawn_ship(_PLAYER_SHIP_ID, Vector2.ZERO, true, {}, "player") as Ship
	if _player_ship == null:
		push_error("IntegrationScene: failed to spawn player ship")
		return
	add_child(_player_ship)
	_add_ship_visual(_player_ship, Color.CYAN)

	var renderer: Node = load("res://gameplay/weapons/ProjectileRenderer.gd").new()
	renderer.name = "ProjectileRenderer"
	add_child(renderer)


func _setup_camera() -> void:
	var cam_scene := load("res://gameplay/camera/GameCamera.tscn")
	if cam_scene == null:
		push_error("IntegrationScene: GameCamera.tscn not found")
		return
	var cam: GameCamera = cam_scene.instantiate() as GameCamera
	cam.default_zoom = 0.6
	cam.min_zoom = 0.25
	add_child(cam)


func _setup_chunk_streamer() -> void:
	var streamer_script := load("res://gameplay/world/ChunkStreamer.gd")
	if streamer_script == null:
		push_error("IntegrationScene: ChunkStreamer.gd not found")
		return
	var streamer: Node = streamer_script.new()
	streamer.name = "ChunkStreamer"
	add_child(streamer)


func _setup_ai_ships() -> void:
	var faction_colors := {
		"pirate":  Color(1.0, 0.25, 0.25),
		"militia": Color(0.25, 0.75, 0.4),
	}

	for entry in _AI_SPAWNS:
		var faction: String = entry[0]
		var pos: Vector2    = entry[1]

		var factory := ShipFactory.new()
		var ship := factory.spawn_ship(_AI_SHIP_ID, pos, false, {}, faction) as Ship
		if ship == null:
			push_error("IntegrationScene: failed to spawn AI ship")
			continue

		add_child(ship)
		_add_ship_visual(ship, faction_colors.get(faction, Color.YELLOW))

		_ai_ships.append(ship)
		_ai_states[ship.get_instance_id()] = "IDLE"


func _add_ship_visual(ship: Ship, color: Color) -> void:
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([
		Vector2( 22.0,   0.0),
		Vector2(-15.0, -14.0),
		Vector2( -8.0,   0.0),
		Vector2(-15.0,  14.0),
	])
	poly.color = color
	ship.add_child(poly)


func _setup_hud() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	var panel := PanelContainer.new()
	panel.position = Vector2(10.0, 10.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(panel)

	_hud_label = Label.new()
	_hud_label.add_theme_font_size_override("font_size", 13)
	_hud_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_hud_label)

	# Controls hint at bottom-left
	_hint_label = Label.new()
	_hint_label.add_theme_font_size_override("font_size", 11)
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_hint_label.offset_top = -48.0
	_hint_label.offset_bottom = 0.0
	_hint_label.offset_left = 8.0
	_hint_label.offset_right = 700.0
	canvas.add_child(_hint_label)
	_update_hint(false)


func _update_hint(near_station: bool) -> void:
	if _hint_label == null:
		return
	if near_station:
		_hint_label.text = "WASD — thrust  |  Mouse — aim  |  LMB/RMB — fire  |  F — DOCK  |  F3 — perf"
	else:
		_hint_label.text = "WASD — thrust  |  Mouse — aim  |  LMB/RMB — fire  |  Space — missiles  |  F3 — perf"


# --- Event handlers ---

func _on_ai_state_changed(payload: Dictionary) -> void:
	var id: int = payload.get("ship_id", 0)
	var state: String = payload.get("new_state", "")
	_ai_states[id] = state


func _on_ship_destroyed(ship: Node2D, _pos: Vector2, _faction: String) -> void:
	if ship in _ai_ships:
		_ai_ships.erase(ship)
	if is_instance_valid(ship):
		ship.queue_free()


func _on_dock_complete(_docked_ship: Node2D, _docked_station: Node2D) -> void:
	_docked = true
	_update_hint(false)


func _on_undock(_undocking_ship: Node2D) -> void:
	_docked = false


# --- HUD update ---

func _process(_delta: float) -> void:
	if _hud_label == null:
		return

	var player_ok := is_instance_valid(_player_ship)
	var near_station := false

	var text := "=== ALL SPACE — MVP ===\n"
	if player_ok:
		text += "Speed:  %.0f / %.0f\n" % [_player_ship.velocity.length(), _player_ship.max_speed]
		text += "Shield: %.0f / %.0f\n" % [_player_ship.shield_hp, _player_ship.shield_max]
		text += "Hull:   %.0f / %.0f\n" % [_player_ship.hull_hp, _player_ship.hull_max]
		text += "Power:  %.0f / %.0f\n" % [_player_ship.power_current, _player_ship.power_capacity]

		# Proximity hint
		if not _docked and is_instance_valid(_station):
			var dist := _player_ship.global_position.distance_to(_station.global_position)
			near_station = dist < 210.0
			if near_station:
				text += "\n>>> PRESS F TO DOCK <<<\n"
	else:
		text += "Player ship destroyed\n"

	_update_hint(near_station)

	text += "\n=== ENEMIES (%d) ===\n" % _ai_ships.size()
	for ship in _ai_ships:
		if not is_instance_valid(ship):
			continue
		var state: String = _ai_states.get(ship.get_instance_id(), "?")
		var dist := (_player_ship.global_position.distance_to(ship.global_position)
				if player_ok else 0.0)
		text += "[%s] %s  hp:%.0f  %dm\n" % [
			ship.faction.substr(0, 3).to_upper(), state,
			ship.hull_hp, int(dist),
		]

	_hud_label.text = text
