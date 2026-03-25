extends Node2D

# ProjectileRenderer — Debug visualization for all projectile types
# Uses _draw() for zero-allocation rendering. Reads from autoload pools each frame.

var _projectile_manager: Node
var _guided_pool: Node
var _event_bus: Node

# Beam flash tracking — stores {start: Vector2, end: Vector2, timer: float}
var _beam_flashes: Array[Dictionary] = []
const BEAM_FLASH_DURATION: float = 0.1

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
	_projectile_manager = get_node("/root/ProjectileManager")
	_guided_pool = get_node("/root/GuidedProjectilePool")
	_event_bus = get_node("/root/GameEventBus")

	# Subscribe to beam fired events
	_event_bus.connect("beam_fired", _on_beam_fired)


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

	queue_redraw()


func _draw() -> void:
	_draw_dumb_projectiles()
	_draw_guided_projectiles()
	_draw_beam_flashes()


func _draw_dumb_projectiles() -> void:
	if _projectile_manager == null:
		return

	var data: Array = _projectile_manager.call("GetActiveProjectileData")
	if data == null or data.is_empty():
		return

	for entry in data:
		var pos: Vector2 = entry.get("position", Vector2.ZERO)
		var archetype: String = entry.get("archetype", "ballistic")

		match archetype:
			"ballistic", "missile_dumb":
				var color := COLOR_MISSILE_DUMB if archetype == "missile_dumb" else COLOR_BALLISTIC
				draw_circle(pos, RADIUS_MISSILE if archetype == "missile_dumb" else RADIUS_BALLISTIC, color)
			"energy_pulse":
				draw_circle(pos, RADIUS_PULSE, COLOR_PULSE)
			_:
				# Default fallback
				draw_circle(pos, RADIUS_BALLISTIC, COLOR_BALLISTIC)


func _draw_guided_projectiles() -> void:
	if _guided_pool == null:
		return

	# Access the internal pool array directly
	var pool = _guided_pool._pool
	if pool == null or pool.is_empty():
		return

	for p in pool:
		if not p.active:
			continue

		# Draw missile as circle + velocity line
		draw_circle(p.position, RADIUS_MISSILE, COLOR_MISSILE_GUIDED)

		# Small line showing velocity direction (10 px)
		if p.velocity.length() > 0.1:
			var end_pos: Vector2 = p.position + p.velocity.normalized() * 10.0
			draw_line(p.position, end_pos, COLOR_MISSILE_GUIDED, 1.0)


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
