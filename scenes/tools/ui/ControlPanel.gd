extends Control

signal color_changed(channel: String, color: Color)
signal damage_changed(level: float)
signal rotation_changed(axis: String, value: float)
signal fire_pressed

@onready var _base_picker: ColorPickerButton = $VBoxContainer/BaseColorPicker
@onready var _accent_picker: ColorPickerButton = $VBoxContainer/AccentColorPicker
@onready var _glow_picker: ColorPickerButton = $VBoxContainer/GlowColorPicker
@onready var _window_picker: ColorPickerButton = $VBoxContainer/WindowColorPicker
@onready var _damage_slider: HSlider = $VBoxContainer/DamageSlider
@onready var _rot_x_slider: HSlider = $VBoxContainer/RotXSlider
@onready var _rot_y_slider: HSlider = $VBoxContainer/RotYSlider
@onready var _rot_z_slider: HSlider = $VBoxContainer/RotZSlider
@onready var _fire_button: Button = $VBoxContainer/FireButton

func _ready() -> void:
    _base_picker.color = Color.WHITE
    _accent_picker.color = Color.GRAY
    _glow_picker.color = Color(0.0, 0.5, 1.0)
    _window_picker.color = Color(0.8, 0.9, 1.0)
    _damage_slider.value = 0.0
    _rot_x_slider.value = 0.0
    _rot_y_slider.value = 0.0
    _rot_z_slider.value = 0.0
    _fire_button.disabled = true
    _fire_button.tooltip_text = "WeaponSystem not found"

    _base_picker.color_changed.connect(func(c: Color) -> void: color_changed.emit("base", c))
    _accent_picker.color_changed.connect(func(c: Color) -> void: color_changed.emit("accent", c))
    _glow_picker.color_changed.connect(func(c: Color) -> void: color_changed.emit("glow", c))
    _window_picker.color_changed.connect(func(c: Color) -> void: color_changed.emit("window", c))
    _damage_slider.value_changed.connect(func(v: float) -> void: damage_changed.emit(v))
    _rot_x_slider.value_changed.connect(func(v: float) -> void: rotation_changed.emit("x", v))
    _rot_y_slider.value_changed.connect(func(v: float) -> void: rotation_changed.emit("y", v))
    _rot_z_slider.value_changed.connect(func(v: float) -> void: rotation_changed.emit("z", v))
    _fire_button.pressed.connect(func() -> void: fire_pressed.emit())

func set_fire_enabled(enabled: bool) -> void:
    _fire_button.disabled = not enabled
    if enabled:
        _fire_button.tooltip_text = "Fire all weapons"
    else:
        _fire_button.tooltip_text = "WeaponSystem not found"
