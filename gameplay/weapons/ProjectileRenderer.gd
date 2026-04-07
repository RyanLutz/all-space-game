extends Node2D

# ProjectileRenderer — Debug visualization for all projectile types.
# Draws live positions polled from the dumb and guided pools each frame so
# projectiles remain visible for their full lifetime. A brief spawn flash is
# kept for immediate feedback on fire events.

var _event_bus: Node
var _guided_pool: Node   # GuidedProjectilePool autoload
var _dumb_pool: Node     # ProjectileManager autoload (C#)

# Beam flash tracking — {start: Vector2, end: Vector2, timer: float}
var _beam_flashes: Array[Dictionary] = []
const BEAM_FLASH_DURATION: float = 0.1

# Spawn flash tracking — brief pop on first frame only.
# {pos: Vector2, vel: Vector2, timer: float, archetype: String}
var _spawn_flashes: Array[Dictionary] = []
const SPAWN_FLASH_DURATION: float = 0.08

# Live positions queried from pools each frame.
var _live_dumb: Array[Dictionary] = []    # [{position, archetype}]
var _live_guided: Array[Dictionary] = []  # [{position, velocity}]

# Visual settings — sizes are in world units.
# Camera zoom 0.5 means 1 world unit ≈ 0.5 screen pixels, so sizes here are
# roughly 2× what they look like on screen.
const COLOR_BALLISTIC       := Color.WHITE
const COLOR_PULSE           := Color(0.4, 0.8, 1.0)   # light blue
const COLOR_MISSILE_DUMB    := Color.ORANGE
const COLOR_MISSILE_GUIDED  := Color.RED
const COLOR_BEAM            := Color.YELLOW

# Tracer line for ballistics (more visible than a dot at high zoom-out).
const TRACER_LEN: float    = 24.0   # world units → ~12 px on screen at zoom 0.5
const TRACER_WIDTH: float  = 2.0
# Circle radii for energy/missile projectiles.
const RADIUS_PULSE: float   = 8.0   # → ~4 px
const RADIUS_MISSILE: float = 12.0  # → ~6 px


func _ready() -> void:
	_event_bus   = ServiceLocator.GetService("GameEventBus") as Node
	# GuidedProjectilePool and ProjectileManager are autoloads; they don't
	# self-register with ServiceLocator, so fetch them by autoload node path.
	_guided_pool = get_node_or_null("/root/GuidedProjectilePool")
	_dumb_pool   = get_node_or_null("/root/ProjectileManager")

	_event_bus.connect("beam_fired",          _on_beam_fired)
	_event_bus.connect("projectile_spawned",  _on_projectile_spawned)


func _on_projectile_spawned(spawn_pos: Vector2, velocity: Vector2, weapon_data: Dictionary) -> void:
	var archetype: String = weapon_data.get("archetype", "ballistic")
	_spawn_flashes.append({
		"pos":      spawn_pos,
		"vel":      velocity,
		"timer":    SPAWN_FLASH_DURATION,
		"archetype": archetype
	})


func _on_beam_fired(start_pos: Vector2, end_pos: Vector2, _weapon_data: Dictionary, _owner_id: int) -> void:
	_beam_flashes.append({
		"start": start_pos,
		"end":   end_pos,
		"timer": BEAM_FLASH_DURATION
	})


func _process(delta: float) -> void:
	# Poll live pool positions.
	_poll_live_pools()

	# Tick beam flashes.
	var i := 0
	while i < _beam_flashes.size():
		_beam_flashes[i]["timer"] -= delta
		if _beam_flashes[i]["timer"] <= 0:
			_beam_flashes.remove_at(i)
		else:
			i += 1

	# Tick spawn flashes (very brief; just the initial pop).
	i = 0
	while i < _spawn_flashes.size():
		_spawn_flashes[i]["timer"] -= delta
		if _spawn_flashes[i]["timer"] <= 0:
			_spawn_flashes.remove_at(i)
			continue
		_spawn_flashes[i]["pos"] += _spawn_flashes[i]["vel"] * delta
		i += 1

	queue_redraw()


func _poll_live_pools() -> void:
	# --- Dumb pool (C# ProjectileManager) ---
	_live_dumb.clear()
	if _dumb_pool != null:
		var raw = _dumb_pool.call("GetActiveProjectileData")
		if raw != null:
			for entry in raw:
				_live_dumb.append(entry)

	# --- Guided pool (GDScript GuidedProjectilePool) ---
	_live_guided.clear()
	if _guided_pool != null:
		var raw = _guided_pool.call("get_active_projectiles_data")
		if raw != null:
			for entry in raw:
				_live_guided.append(entry)


func _draw() -> void:
	_draw_live_dumb()
	_draw_live_guided()
	_draw_spawn_flashes()
	_draw_beam_flashes()


func _draw_live_dumb() -> void:
	for entry in _live_dumb:
		var pos: Vector2 = entry.get("position", Vector2.ZERO)
		var vel: Vector2 = entry.get("velocity", Vector2.ZERO)
		var archetype: String = entry.get("archetype", "ballistic")
		match archetype:
			"energy_pulse":
				draw_circle(pos, RADIUS_PULSE, COLOR_PULSE)
			_:
				# Tracer line along velocity direction.
				var dir := vel.normalized() if vel.length() > 0.1 else Vector2.RIGHT
				var tip  := pos + dir * TRACER_LEN * 0.6
				var tail := pos - dir * TRACER_LEN * 0.4
				draw_line(tail, tip, COLOR_BALLISTIC, TRACER_WIDTH)


func _draw_live_guided() -> void:
	for entry in _live_guided:
		var pos: Vector2 = entry.get("position", Vector2.ZERO)
		var vel: Vector2 = entry.get("velocity", Vector2.ZERO)
		draw_circle(pos, RADIUS_MISSILE, COLOR_MISSILE_DUMB)
		if vel.length() > 0.1:
			draw_line(pos, pos + vel.normalized() * 14.0, COLOR_MISSILE_DUMB, 1.5)


func _draw_spawn_flashes() -> void:
	for entry in _spawn_flashes:
		var pos: Vector2  = entry.get("pos", Vector2.ZERO)
		var archetype: String = entry.get("archetype", "ballistic")
		var alpha: float  = entry.get("timer", 0.0) / SPAWN_FLASH_DURATION
		var color: Color
		var radius: float
		match archetype:
			"energy_pulse":
				color  = COLOR_PULSE
				radius = RADIUS_PULSE + 4.0
			"missile_dumb", "missile_guided":
				color  = COLOR_MISSILE_DUMB
				radius = RADIUS_MISSILE + 4.0
			_:
				color  = COLOR_BALLISTIC
				radius = TRACER_LEN * 0.5
		color.a = alpha
		draw_circle(pos, radius, color)


func _draw_beam_flashes() -> void:
	for flash in _beam_flashes:
		var start: Vector2 = flash.get("start", Vector2.ZERO)
		var end:   Vector2 = flash.get("end",   Vector2.ZERO)
		var timer: float   = flash.get("timer", 0.0)
		var alpha: float   = timer / BEAM_FLASH_DURATION
		var color: Color   = COLOR_BEAM
		color.a = alpha
		draw_line(start, end, color, 2.0)
