extends Node2D

# AITestScene — self-contained scene to verify the full AI system.
# Spawns a player-controlled fighter and a mix of pirate / militia AI ships.
# Press F3 for PerformanceMonitor overlay.
# Watch: pirates detect and attack the player; militia patrols and ignores player;
# pirates and militia fight each other when in range.

const _PLAYER_SHIP_ID := "fighter_light"
const _AI_SHIP_ID     := "corvette_patrol"

var _player_ship: Ship = null
var _ai_ships: Array[Ship] = []
var _ai_states: Dictionary = {}   # instance_id → state string

var _label: Label = null
var _event_bus: Node = null

# Spawn layout: [faction, position]
const _AI_SPAWNS: Array = [
	["pirate",  Vector2( 1100.0,  -200.0)],
	["pirate",  Vector2( -900.0,   400.0)],
	["pirate",  Vector2(  800.0,   900.0)],
	["militia", Vector2(-1200.0,  -500.0)],
	["militia", Vector2(  300.0, -1100.0)],
]


func _ready() -> void:
	_event_bus = ServiceLocator.GetService("GameEventBus") as Node

	_setup_background()
	_setup_player()
	_setup_ai_ships()
	_setup_hud()

	if _event_bus:
		_event_bus.connect("ai_state_changed", _on_ai_state_changed)
		_event_bus.connect("ship_destroyed",   _on_ship_destroyed)


func _setup_background() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.04, 0.08)
	bg.size = Vector2(8000.0, 8000.0)
	bg.position = Vector2(-4000.0, -4000.0)
	add_child(bg)


func _setup_player() -> void:
	var factory := ShipFactory.new()
	_player_ship = factory.spawn_ship(_PLAYER_SHIP_ID, Vector2.ZERO, true, {}, "player") as Ship
	if _player_ship == null:
		push_error("AITestScene: failed to spawn player ship '%s'" % _PLAYER_SHIP_ID)
		return

	add_child(_player_ship)
	_add_ship_visual(_player_ship, Color.CYAN)

	var cam := Camera2D.new()
	cam.name = "Camera"
	cam.zoom = Vector2(0.4, 0.4)
	_player_ship.add_child(cam)

	var renderer: Node = load("res://gameplay/weapons/ProjectileRenderer.gd").new()
	renderer.name = "ProjectileRenderer"
	add_child(renderer)


func _setup_ai_ships() -> void:
	var faction_colors := {
		"pirate":  Color(1.0, 0.25, 0.25),
		"militia": Color(0.25, 0.75, 0.4),
	}
	var default_color := Color(0.85, 0.85, 0.3)

	for entry in _AI_SPAWNS:
		var faction: String = entry[0]
		var pos: Vector2    = entry[1]

		var factory := ShipFactory.new()
		var ship := factory.spawn_ship(_AI_SHIP_ID, pos, false, {}, faction) as Ship
		if ship == null:
			push_error("AITestScene: failed to spawn AI ship")
			continue

		add_child(ship)

		var color: Color = faction_colors.get(faction, default_color)
		_add_ship_visual(ship, color)

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

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 13)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_label)

	var hint := Label.new()
	hint.text = "WASD — move  |  Mouse — aim  |  LClick — fire  |  F3 — perf overlay"
	hint.add_theme_font_size_override("font_size", 11)
	hint.position = Vector2(10.0, 130.0)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(hint)

	var legend := Label.new()
	legend.text = "Cyan = player  |  Red = pirate (hostile)  |  Green = militia (neutral)"
	legend.add_theme_font_size_override("font_size", 11)
	legend.position = Vector2(10.0, 148.0)
	legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(legend)


func _on_ai_state_changed(payload: Dictionary) -> void:
	var id: int    = payload.get("ship_id", 0)
	var state: String = payload.get("new_state", "")
	_ai_states[id] = state


func _on_ship_destroyed(ship: Node2D, _position: Vector2, _faction: String) -> void:
	if ship in _ai_ships:
		_ai_ships.erase(ship)
	if is_instance_valid(ship):
		ship.queue_free()


func _process(_delta: float) -> void:
	if _label == null:
		return

	var player_ok := is_instance_valid(_player_ship)

	var text := "=== AI TEST SCENE ===\n"
	if player_ok:
		text += "Speed:  %.0f / %.0f\n" % [_player_ship.velocity.length(), _player_ship.max_speed]
		text += "Shield: %.0f / %.0f | Hull: %.0f / %.0f\n" % [
			_player_ship.shield_hp, _player_ship.shield_max,
			_player_ship.hull_hp,   _player_ship.hull_max,
		]
	else:
		text += "Player ship destroyed\n"

	text += "\n=== AI SHIPS (%d active) ===\n" % _ai_ships.size()
	for ship in _ai_ships:
		if not is_instance_valid(ship):
			continue
		var state: String = _ai_states.get(ship.get_instance_id(), "?")
		text += "[%s] %s  hp:%.0f  dist:%.0f\n" % [
			ship.faction.substr(0, 3).to_upper(),
			state,
			ship.hull_hp,
			(_player_ship.position.distance_to(ship.position) if player_ok else 0.0),
		]

	_label.text = text

