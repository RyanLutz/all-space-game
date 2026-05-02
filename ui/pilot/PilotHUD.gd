extends Control
class_name PilotHUD

var _player_ship: Ship = null

var _speed_value: Label
var _hull_bar: ProgressBar
var _shield_bar: ProgressBar


func set_player_ship(player_ship: Ship) -> void:
	_player_ship = player_ship


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var root := Control.new()
	root.name = "HUDRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var crosshair := Label.new()
	crosshair.name = "Crosshair"
	crosshair.text = "+"
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	crosshair.anchor_left = 0.5
	crosshair.anchor_right = 0.5
	crosshair.anchor_top = 0.5
	crosshair.anchor_bottom = 0.5
	crosshair.offset_left = -10
	crosshair.offset_right = 10
	crosshair.offset_top = -10
	crosshair.offset_bottom = 10
	root.add_child(crosshair)

	var speed_label := Label.new()
	speed_label.name = "SpeedLabel"
	speed_label.text = "Speed: --"
	speed_label.anchor_left = 0.02
	speed_label.anchor_top = 0.86
	speed_label.anchor_right = 0.3
	speed_label.anchor_bottom = 0.9
	root.add_child(speed_label)
	_speed_value = speed_label

	var shield_label := Label.new()
	shield_label.name = "ShieldLabel"
	shield_label.text = "Shields"
	shield_label.anchor_left = 0.02
	shield_label.anchor_top = 0.9
	shield_label.anchor_right = 0.2
	shield_label.anchor_bottom = 0.94
	root.add_child(shield_label)

	var shield_bar := ProgressBar.new()
	shield_bar.name = "ShieldBar"
	shield_bar.min_value = 0.0
	shield_bar.max_value = 100.0
	shield_bar.show_percentage = false
	shield_bar.anchor_left = 0.02
	shield_bar.anchor_top = 0.94
	shield_bar.anchor_right = 0.3
	shield_bar.anchor_bottom = 0.97
	root.add_child(shield_bar)
	_shield_bar = shield_bar

	var hull_label := Label.new()
	hull_label.name = "HullLabel"
	hull_label.text = "Hull"
	hull_label.anchor_left = 0.32
	hull_label.anchor_top = 0.9
	hull_label.anchor_right = 0.45
	hull_label.anchor_bottom = 0.94
	root.add_child(hull_label)

	var hull_bar := ProgressBar.new()
	hull_bar.name = "HullBar"
	hull_bar.min_value = 0.0
	hull_bar.max_value = 100.0
	hull_bar.show_percentage = false
	hull_bar.anchor_left = 0.32
	hull_bar.anchor_top = 0.94
	hull_bar.anchor_right = 0.6
	hull_bar.anchor_bottom = 0.97
	root.add_child(hull_bar)
	_hull_bar = hull_bar


func _process(_delta: float) -> void:
	if _player_ship == null or not is_instance_valid(_player_ship):
		return

	var planar_speed: float = _player_ship.linear_velocity.length()
	_speed_value.text = "Speed: %.1f m/s" % planar_speed

	if _player_ship.shield_max > 0.0:
		_shield_bar.value = (_player_ship.shield_hp / _player_ship.shield_max) * 100.0
	else:
		_shield_bar.value = 0.0

	if _player_ship.hull_max > 0.0:
		_hull_bar.value = (_player_ship.hull_hp / _player_ship.hull_max) * 100.0
	else:
		_hull_bar.value = 0.0
