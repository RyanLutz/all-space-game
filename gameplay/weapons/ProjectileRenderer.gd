extends Node2D

# ProjectileRenderer — Debug visualization for all projectile types
# Uses _draw() for zero-allocation rendering. Renders from GameEventBus events (no direct pool access).

var _event_bus: Node

# Beam flash tracking — stores {start: Vector2, end: Vector2, timer: float}
var _beam_flashes: Array[Dictionary] = []
const BEAM_FLASH_DURATION: float = 0.1

# Projectile flash tracking — stores {pos: Vector2, vel: Vector2, timer: float, archetype: String}
var _projectile_flashes: Array[Dictionary] = []
const PROJECTILE_FLASH_DURATION: float = 0.25

# Visual settings by archetype
const COLOR_BALLISTIC := Color.WHITE
const COLOR_PULSE := Color.CYAN
const COLOR_MISSILE_DUMB := Color.ORANGE
const COLOR_MISSILE_GUIDED := Color.RED
const COLOR_BEAM := Color.YELLOW

const RADIUS_BALLISTIC: float = 2.0
const RADIUS_PULSE: float = 3.0
const RADIUS_MISSILE: float = 4.0


func _ready() -> void:
	_event_bus = ServiceLocator.GetService("GameEventBus") as Node

	# Subscribe to projectile/beam events
	_event_bus.connect("beam_fired", _on_beam_fired)
	_event_bus.connect("projectile_spawned", _on_projectile_spawned)


func _on_projectile_spawned(spawn_pos: Vector2, velocity: Vector2, weapon_data: Dictionary) -> void:
	var archetype: String = weapon_data.get("archetype", "ballistic")
	_projectile_flashes.append({
		"pos": spawn_pos,
		"vel": velocity,
		"timer": PROJECTILE_FLASH_DURATION,
		"archetype": archetype
	})


func _on_beam_fired(start_pos: Vector2, end_pos: Vector2, _weapon_data: Dictionary, _owner_id: int) -> void:
	_beam_flashes.append({
		"start": start_pos,
		"end": end_pos,
		"timer": BEAM_FLASH_DURATION
	})


func _process(delta: float) -> void:
	# Tick down beam flash timers
	var i := 0
	while i < _beam_flashes.size():
		_beam_flashes[i]["timer"] -= delta
		if _beam_flashes[i]["timer"] <= 0:
			_beam_flashes.remove_at(i)
		else:
			i += 1

	# Tick down and integrate projectile flashes
	i = 0
	while i < _projectile_flashes.size():
		_projectile_flashes[i]["timer"] -= delta
		if _projectile_flashes[i]["timer"] <= 0:
			_projectile_flashes.remove_at(i)
			continue
		_projectile_flashes[i]["pos"] += _projectile_flashes[i]["vel"] * delta
		i += 1

	queue_redraw()


func _draw() -> void:
	_draw_projectile_flashes()
	_draw_beam_flashes()


func _draw_projectile_flashes() -> void:
	for entry in _projectile_flashes:
		var pos: Vector2 = entry.get("pos", Vector2.ZERO)
		var vel: Vector2 = entry.get("vel", Vector2.ZERO)
		var archetype: String = entry.get("archetype", "ballistic")

		match archetype:
			"ballistic":
				draw_circle(pos, RADIUS_BALLISTIC, COLOR_BALLISTIC)
			"energy_pulse":
				draw_circle(pos, RADIUS_PULSE, COLOR_PULSE)
			"missile_dumb":
				draw_circle(pos, RADIUS_MISSILE, COLOR_MISSILE_DUMB)
			"missile_guided":
				draw_circle(pos, RADIUS_MISSILE, COLOR_MISSILE_GUIDED)
			_:
				draw_circle(pos, RADIUS_BALLISTIC, COLOR_BALLISTIC)

		# Small line showing velocity direction (10 px)
		if vel.length() > 0.1:
			var end_pos: Vector2 = pos + vel.normalized() * 10.0
			draw_line(pos, end_pos, COLOR_BALLISTIC, 1.0)


func _draw_beam_flashes() -> void:
	for flash in _beam_flashes:
		var start: Vector2 = flash.get("start", Vector2.ZERO)
		var end: Vector2 = flash.get("end", Vector2.ZERO)
		var timer: float = flash.get("timer", 0.0)

		# Fade alpha based on remaining time
		var alpha := timer / BEAM_FLASH_DURATION
		var color := COLOR_BEAM
		color.a = alpha

		draw_line(start, end, color, 2.0)
