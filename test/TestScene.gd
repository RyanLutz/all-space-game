extends Node2D

var _ship: Ship
var _label: Label


func _ready() -> void:
	_setup_background()
	_setup_ship()
	_setup_obstacles()
	_setup_hud()


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
	_ship.position = Vector2(0.0, 0.0)
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

	# Camera follows ship. Zoom 0.5 shows ~3840m of space at 1920px wide.
	var cam := Camera2D.new()
	cam.name = "PlayerCamera"
	cam.zoom = Vector2(0.5, 0.5)
	_ship.add_child(cam)


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
	hint.text = "WASD — thrust / strafe    Mouse — aim    F3 — perf overlay"
	hint.add_theme_font_size_override("font_size", 12)
	hint.position = Vector2(10.0, 60.0)
	canvas.add_child(hint)


func _process(_delta: float) -> void:
	if _ship == null or _label == null:
		return
	_label.text = (
		"Speed:  %.1f / %.1f u/s\n" % [_ship.velocity.length(), _ship.max_speed]
		+ "AngVel: %.3f rad/s\n" % _ship.angular_velocity
		+ "Bodies: %d" % get_tree().get_nodes_in_group("space_bodies").size()
	)
