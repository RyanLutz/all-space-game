extends Node2D

var _ship: Ship
var _label: Label
var _weapon_component: WeaponComponent

# Target ships for combat testing
var _targets: Array[Ship] = []

# Stress test state
var _stress_test_active: bool = false
var _stress_test_rounds: int = 0
const STRESS_TEST_MAX: int = 200

var _event_bus: Node
var _perf_monitor: Node


func _ready() -> void:
	_event_bus = ServiceLocator.GetService("GameEventBus") as Node
	_perf_monitor = ServiceLocator.GetService("PerformanceMonitor") as Node

	_setup_background()
	_setup_ship()
	_setup_targets()
	_setup_obstacles()
	_setup_hud()

	# Connect to ship destruction for cleanup
	_event_bus.connect("ship_destroyed", _on_ship_destroyed)


func _setup_background() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.04, 0.08)
	bg.size = Vector2(8000.0, 8000.0)
	bg.position = Vector2(-4000.0, -4000.0)
	add_child(bg)


func _setup_ship() -> void:
	_ship = Ship.new()
	_ship.name = "PlayerShip"
	_ship.is_player_controlled = true
	_ship.faction = "player"
	_ship.position = Vector2(0.0, 0.0)
	_ship.add_to_group("ships")
	add_child(_ship)

	# Collision required for move_and_slide.
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 15.0
	col.shape = shape
	_ship.add_child(col)

	# Triangle pointing right (+X = forward at rotation 0).
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([
		Vector2(20.0,  0.0),   # nose
		Vector2(-14.0, -13.0), # port wing
		Vector2(-7.0,   0.0),  # tail centre
		Vector2(-14.0,  13.0), # starboard wing
	])
	poly.color = Color.CYAN
	_ship.add_child(poly)

	# WeaponComponent - attached to ship
	_weapon_component = WeaponComponent.new()
	_weapon_component.name = "WeaponComponent"
	_ship.add_child(_weapon_component)

	# Camera follows ship. Zoom 0.5 shows ~3840m of space at 1920px wide.
	var cam := Camera2D.new()
	cam.name = "PlayerCamera"
	cam.zoom = Vector2(0.5, 0.5)
	_ship.add_child(cam)

	# Projectile renderer — draws all projectiles each frame
	var renderer: Node = load("res://gameplay/weapons/ProjectileRenderer.gd").new()
	renderer.name = "ProjectileRenderer"
	add_child(renderer)


func _setup_targets() -> void:
	# Create 3 dummy target ships
	var target_positions := [
		Vector2(400, -200),
		Vector2(-350, 250),
		Vector2(500, 300)
	]

	var colors := [Color.RED, Color.ORANGE, Color.ORCHID]

	for i in range(target_positions.size()):
		var target := Ship.new()
		target.name = "TargetShip%d" % i
		target.is_player_controlled = false
		target.faction = "enemy"
		target.position = target_positions[i]
		target.hull_max = 200.0
		target.hull_hp = 200.0
		target.shield_max = 100.0
		target.shield_hp = 100.0
		target.add_to_group("ships")
		target.add_to_group("enemy_ships")
		add_child(target)

		# Collision
		var col := CollisionShape2D.new()
		var shape := CircleShape2D.new()
		shape.radius = 15.0
		col.shape = shape
		target.add_child(col)

		# Visual - different color than player
		var poly := Polygon2D.new()
		poly.polygon = PackedVector2Array([
			Vector2(20.0,  0.0),
			Vector2(-14.0, -13.0),
			Vector2(-7.0,   0.0),
			Vector2(-14.0,  13.0),
		])
		poly.color = colors[i]
		target.add_child(poly)

		_targets.append(target)


func _setup_obstacles() -> void:
	var positions: Array[Vector2] = [
		Vector2( 250.0, -120.0),
		Vector2(-300.0,  200.0),
		Vector2( 450.0,  280.0),
		Vector2(-180.0, -340.0),
		Vector2( 520.0, -230.0),
		Vector2(-420.0,  100.0),
	]

	for pos: Vector2 in positions:
		var body := StaticBody2D.new()
		body.position = pos
		add_child(body)

		var col := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(60.0, 60.0)
		col.shape = rect
		body.add_child(col)

		var vis := ColorRect.new()
		vis.size = Vector2(60.0, 60.0)
		vis.position = Vector2(-30.0, -30.0)
		vis.color = Color(0.32, 0.32, 0.32)
		body.add_child(vis)


func _setup_hud() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	var panel := PanelContainer.new()
	panel.position = Vector2(10.0, 10.0)
	canvas.add_child(panel)

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 14)
	panel.add_child(_label)

	var hint := Label.new()
	hint.text = "WASD — move | Mouse — aim | LClick — primary | RClick — beam | Space — missile | T — stress test | F3 — perf"
	hint.add_theme_font_size_override("font_size", 11)
	hint.position = Vector2(10.0, 120.0)
	canvas.add_child(hint)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_T:
			_start_stress_test()


func _start_stress_test() -> void:
	_stress_test_active = true
	_stress_test_rounds = 0
	print("Stress test started: firing %d rounds..." % STRESS_TEST_MAX)


func _on_ship_destroyed(ship: Node2D, _position: Vector2, _faction: String) -> void:
	if ship in _targets:
		_targets.erase(ship)
		print("Target destroyed!")


func _process(_delta: float) -> void:
	if _ship == null or _label == null:
		return

	# Handle stress test
	if _stress_test_active and _stress_test_rounds < STRESS_TEST_MAX:
		# Fire toward first target or forward if no targets
		var aim_dir := Vector2.RIGHT.rotated(_ship.rotation)
		if not _targets.is_empty() and _targets[0] != null:
			aim_dir = (_targets[0].position - _ship.position).normalized()

		var muzzle_pos := _ship.position + aim_dir * 32.0
		var velocity := aim_dir * 900.0 + _ship.velocity

		_event_bus.emit_signal(
			"request_spawn_dumb",
			muzzle_pos,
			velocity,
			1.5,
			"autocannon_light",
			_ship.get_instance_id()
		)
		_stress_test_rounds += 1

		if _stress_test_rounds >= STRESS_TEST_MAX:
			_stress_test_active = false
			print("Stress test complete. Check F3 overlay for performance stats.")

	# Get first target for HUD display
	var target := _targets[0] if not _targets.is_empty() else null

	# Get projectile count
	var proj_count: int = _perf_monitor.get_count("ProjectileManager.active_count")

	# Build HUD text
	var text := ""
	text += "=== PLAYER ===\n"
	text += "Speed:  %.1f / %.1f u/s\n" % [_ship.velocity.length(), _ship.max_speed]
	text += "Shield: %.0f / %.0f | Hull: %.0f / %.0f\n" % [
		_ship.shield_hp, _ship.shield_max,
		_ship.hull_hp, _ship.hull_max
	]
	text += "Power:  %.0f / %.0f\n" % [_ship.power_current, _ship.power_capacity]

	# Show first hardpoint heat
	if _weapon_component:
		var hps: Array = _weapon_component.get_all_hardpoints()
		if not hps.is_empty():
			text += "Heat:   %.0f / %.0f\n" % [hps[0].heat_current, hps[0].heat_capacity]

	text += "\n=== TARGET ===\n"
	if target != null:
		text += "Dist:   %.0f m\n" % _ship.position.distance_to(target.position)
		text += "Shield: %.0f / %.0f | Hull: %.0f / %.0f\n" % [
			target.shield_hp, target.shield_max,
			target.hull_hp, target.hull_max
		]
	else:
		text += "No targets remaining\n"

	text += "\n=== WORLD ===\n"
	text += "Ships:  %d | Projectiles: %d\n" % [
		get_tree().get_nodes_in_group("ships").size(),
		proj_count
	]

	if _stress_test_active:
		text += "\nSTRESS TEST: %d / %d" % [_stress_test_rounds, STRESS_TEST_MAX]

	_label.text = text
