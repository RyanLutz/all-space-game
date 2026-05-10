extends Camera3D

@export var orbit_distance: float = 10.0
@export var orbit_yaw: float = 0.0
@export var orbit_pitch: float = 20.0
@export var min_distance: float = 2.0
@export var max_distance: float = 40.0
@export var orbit_speed: float = 0.4
@export var zoom_speed: float = 1.0

var _is_orbiting: bool = false

func _ready() -> void:
    _update_camera()

func _input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_RIGHT:
            _is_orbiting = event.pressed
        if event.button_index == MOUSE_BUTTON_WHEEL_UP:
            orbit_distance = max(min_distance, orbit_distance - zoom_speed)
            _update_camera()
        if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            orbit_distance = min(max_distance, orbit_distance + zoom_speed)
            _update_camera()

    if event is InputEventMouseMotion and _is_orbiting:
        orbit_yaw   -= event.relative.x * orbit_speed
        orbit_pitch -= event.relative.y * orbit_speed
        orbit_pitch  = clampf(orbit_pitch, -80.0, 80.0)
        _update_camera()

func _update_camera() -> void:
    var yaw_rad   = deg_to_rad(orbit_yaw)
    var pitch_rad = deg_to_rad(orbit_pitch)
    var offset = Vector3(
        cos(pitch_rad) * sin(yaw_rad),
        sin(pitch_rad),
        cos(pitch_rad) * cos(yaw_rad)
    ) * orbit_distance
    position = offset
    look_at(Vector3.ZERO, Vector3.UP)

func reset_orbit() -> void:
    orbit_yaw = 0.0
    orbit_pitch = 20.0
    orbit_distance = 10.0
    _update_camera()
