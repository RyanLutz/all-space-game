extends Control
class_name Radar

## Circular radar display for Pilot HUD.
## Uses _draw() for all rendering. Redraws every frame via _process().
## Player dot at center; enemy dots plotted by world-space XZ delta.
## Direct scene-tree query for enemy positions (read-only; not a cross-system dependency).
##
## Radar orientation: world north-up.
##   X → radar right
##   -Z → radar up

const SWEEP_SPEED        := TAU / 3.0    # full rotation every 3 seconds
const SWEEP_WEDGE_HALF   := PI / 12.0    # 15-degree half-angle for sweep wedge
const WEDGE_STEPS        := 24           # polygon segments for wedge fill
const RING_COUNT         := 2            # inner rings (plus outer border)
const DOT_PLAYER_RADIUS  := 3.0
const DOT_ENEMY_RADIUS   := 2.5

## Set by PilotHUD when the player ship reference changes.
var player_ship: Ship = null

## World-space radius of the radar field. Configurable via world_config.json.
## PilotHUD passes this in after reading config; default here is a safe fallback.
var radar_range: float = 1000.0

var _sweep_angle: float = 0.0

# Cached per-frame from size — avoids recalculating inside _draw()
var _center: Vector2
var _radius: float


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(160, 160)


func _process(delta: float) -> void:
	_sweep_angle = fmod(_sweep_angle + SWEEP_SPEED * delta, TAU)
	_center = size / 2.0
	_radius = minf(size.x, size.y) / 2.0 - 1.5  # 1.5px inset for border stroke
	queue_redraw()


func _draw() -> void:
	if _radius <= 0.0:
		return

	# ── Background ────────────────────────────────────────────────────────────
	draw_circle(_center, _radius, Color(0.016, 0.039, 0.078, 0.96))

	# ── Inner range rings ─────────────────────────────────────────────────────
	for i in RING_COUNT:
		var ring_r := _radius * float(i + 1) / float(RING_COUNT + 1)
		draw_arc(_center, ring_r, 0.0, TAU, 64, UITokens.GREY_20, 1.0)

	# ── Crosshair ─────────────────────────────────────────────────────────────
	draw_line(_center - Vector2(_radius, 0.0), _center + Vector2(_radius, 0.0),
			UITokens.GREY_20, 1.0)
	draw_line(_center - Vector2(0.0, _radius), _center + Vector2(0.0, _radius),
			UITokens.GREY_20, 1.0)

	# ── Sweep wedge ───────────────────────────────────────────────────────────
	var wedge_color := Color(UITokens.ACCENT.r, UITokens.ACCENT.g, UITokens.ACCENT.b, 0.10)
	var pts := PackedVector2Array()
	pts.append(_center)
	for i in WEDGE_STEPS + 1:
		var frac := float(i) / float(WEDGE_STEPS)
		var angle := _sweep_angle - SWEEP_WEDGE_HALF + SWEEP_WEDGE_HALF * 2.0 * frac
		pts.append(_center + Vector2(cos(angle), sin(angle)) * _radius)
	draw_polygon(pts, PackedColorArray([wedge_color]))

	# ── Sweep line ────────────────────────────────────────────────────────────
	var sweep_end := _center + Vector2(cos(_sweep_angle), sin(_sweep_angle)) * _radius
	draw_line(_center, sweep_end, Color(0.133, 0.800, 0.659, 0.65), 1.5)

	# ── Outer border ─────────────────────────────────────────────────────────
	draw_arc(_center, _radius, 0.0, TAU, 128, UITokens.GREY_20, 1.5)

	# ── Player dot ────────────────────────────────────────────────────────────
	draw_circle(_center, DOT_PLAYER_RADIUS, UITokens.ACCENT)

	# ── Enemy dots ────────────────────────────────────────────────────────────
	if player_ship == null or not is_instance_valid(player_ship):
		return

	var player_pos := player_ship.global_position
	var range_sq   := radar_range * radar_range

	for node in get_tree().get_nodes_in_group("ships"):
		if node == player_ship:
			continue
		if not node is Node3D:
			continue
		var target := node as Node3D
		var delta_world := target.global_position - player_pos
		# Cull before coordinate conversion
		var dist_sq := delta_world.x * delta_world.x + delta_world.z * delta_world.z
		if dist_sq > range_sq:
			continue
		# World XZ → radar XY: X right, Z up (screen Y is inverted in draw space)
		var radar_x := delta_world.x / radar_range * _radius
		var radar_y := delta_world.z / radar_range * _radius
		# Clip to circle (already culled by range_sq but floating point safe)
		if radar_x * radar_x + radar_y * radar_y > _radius * _radius:
			continue
		draw_circle(_center + Vector2(radar_x, radar_y), DOT_ENEMY_RADIUS, UITokens.HOSTILE)
