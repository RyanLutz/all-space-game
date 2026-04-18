extends Node3D

## Minimal test scene for Ship physics + NavigationController.
##
##   WASD          — manual fly (cancels nav)
##   Mouse         — aim
##   Right-click   — set nav destination (NavigationController flies there)
##   1 / 2 / 3     — switch between fighter / corvette / destroyer presets
##   F3            — toggle the performance overlay

@onready var _ship: Ship = $Ship
@onready var _camera: Camera3D = $Camera3D
@onready var _aim_cursor: MeshInstance3D = $AimCursor
@onready var _dest_marker: MeshInstance3D = $DestMarker

# Camera follows the ship from above
var _camera_height: float = 60.0
var _camera_offset: Vector3 = Vector3.ZERO

# Navigation state
var _nav: NavigationController
var _has_destination: bool = false

# ─── Ship stat presets for testing feel ───────────────────────────────────────

const PRESETS := {
	"fighter": {
		"hp": 120, "mass": 600, "max_speed": 500, "linear_drag": 0.03,
		"angular_drag": 2.0, "alignment_drag_base": 0.2,
		"thruster_force": 9000, "torque_thrust_ratio": 0.25, "max_torque": 2500,
		"arrival_distance": 20.0, "brake_safety_margin": 1.15,
		"power_capacity": 100, "power_regen": 20,
		"shield_max": 60, "shield_regen_rate": 8, "shield_regen_delay": 3.0,
		"shield_regen_power_draw": 10
	},
	"corvette": {
		"hp": 350, "mass": 2000, "max_speed": 320, "linear_drag": 0.05,
		"angular_drag": 3.0, "alignment_drag_base": 0.3,
		"thruster_force": 18000, "torque_thrust_ratio": 0.28, "max_torque": 6000,
		"arrival_distance": 25.0, "brake_safety_margin": 1.25,
		"power_capacity": 280, "power_regen": 55,
		"shield_max": 200, "shield_regen_rate": 14, "shield_regen_delay": 4.0,
		"shield_regen_power_draw": 20
	},
	"destroyer": {
		"hp": 800, "mass": 8000, "max_speed": 180, "linear_drag": 0.08,
		"angular_drag": 4.0, "alignment_drag_base": 0.5,
		"thruster_force": 50000, "torque_thrust_ratio": 0.35, "max_torque": 15000,
		"arrival_distance": 40.0, "brake_safety_margin": 1.4,
		"power_capacity": 500, "power_regen": 80,
		"shield_max": 400, "shield_regen_rate": 20, "shield_regen_delay": 5.0,
		"shield_regen_power_draw": 30
	}
}

var _current_preset: String = "corvette"


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED
	_apply_preset(_current_preset)

	# Attach NavigationController as a child of the ship so it owns the same
	# tree branch and can resolve `owner` to the Ship at _ready() time.
	_nav = NavigationController.new()
	_nav.name = "NavigationController"
	_ship.add_child(_nav)
	_nav.owner = _ship
	# Re-apply tuning now that the nav child exists and can pick up the values.
	# (_nav._ready() already ran on add_child via deferred; pull from ship directly.)
	_nav.arrival_distance = _ship.arrival_distance
	_nav.brake_safety_margin = _ship.brake_safety_margin

	_dest_marker.visible = false

	print("Ship Physics + Nav Test Scene Ready")
	print("  WASD — fly (cancels nav)  |  Mouse — aim  |  Right-click — nav to point")
	print("  1 — Fighter  |  2 — Corvette  |  3 — Destroyer  |  F3 — overlay")
	print("  Current: %s" % _current_preset)


func _process(_delta: float) -> void:
	# Camera follows ship
	_camera.global_position = _ship.global_position + Vector3(0, _camera_height, 0)

	# Update aim cursor position
	var aim_pos := _mouse_to_world()
	_aim_cursor.global_position = aim_pos + Vector3(0, 0.1, 0)


func _physics_process(delta: float) -> void:
	# Aim always comes from the mouse
	_ship.input_aim_target = _mouse_to_world()

	var manual_forward := Input.get_axis("move_backward", "move_forward")
	var manual_strafe := Input.get_axis("move_left", "move_right")

	# Any manual input cancels an active nav destination
	if _has_destination and (manual_forward != 0.0 or manual_strafe != 0.0):
		_clear_destination()

	if _has_destination:
		_nav.set_thrust_fraction(1.0)
		_nav.update(delta)
		# Auto-clear when arrived so drag bleeds residual momentum
		if _nav.has_arrived():
			_clear_destination()
	else:
		_ship.input_forward = manual_forward
		_ship.input_strafe = manual_strafe


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("preset_1"):
		_apply_preset("fighter")
	elif event.is_action_pressed("preset_2"):
		_apply_preset("corvette")
	elif event.is_action_pressed("preset_3"):
		_apply_preset("destroyer")
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_RIGHT:
		_set_destination_at_mouse()


func _apply_preset(preset_name: String) -> void:
	_current_preset = preset_name
	_ship.initialize_stats(PRESETS[preset_name])
	# Propagate new tuning into the nav controller (may be null during first boot
	# if the preset is applied before _nav is constructed).
	if _nav:
		_nav.arrival_distance = _ship.arrival_distance
		_nav.brake_safety_margin = _ship.brake_safety_margin
	print("Switched to %s preset (mass=%d, thrust=%d, arrival=%.1f)" % [
		preset_name,
		PRESETS[preset_name]["mass"],
		PRESETS[preset_name]["thruster_force"],
		PRESETS[preset_name]["arrival_distance"]
	])


func _set_destination_at_mouse() -> void:
	var dest := _mouse_to_world()
	_nav.set_destination(dest)
	_dest_marker.global_position = dest + Vector3(0, 0.1, 0)
	_dest_marker.visible = true
	_has_destination = true


func _clear_destination() -> void:
	_has_destination = false
	_dest_marker.visible = false


func _mouse_to_world() -> Vector3:
	var mouse_pos := get_viewport().get_mouse_position()
	var plane := Plane(Vector3.UP, 0.0)
	var ray_origin := _camera.project_ray_origin(mouse_pos)
	var ray_dir := _camera.project_ray_normal(mouse_pos)
	var hit = plane.intersects_ray(ray_origin, ray_dir)
	if hit != null:
		return hit
	return _ship.global_position
