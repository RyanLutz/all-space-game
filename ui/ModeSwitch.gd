extends Control
class_name ModeSwitch

## Always-visible mode toggle. Listens for the "toggle_mode" input action (Tab)
## and emits GameEventBus.game_mode_changed(old_mode, new_mode).
##
## ModeSwitch never holds references to PilotHUD or TacticalHUD.
## Those scenes listen for game_mode_changed and show/hide themselves.
##
## Mode strings: "pilot" | "tactical"

const MODE_PILOT    := "pilot"
const MODE_TACTICAL := "tactical"

var _current_mode: String = MODE_PILOT
var _event_bus: Node


func _ready() -> void:
	var service_locator := Engine.get_singleton("ServiceLocator")
	_event_bus = service_locator.GetService("GameEventBus")

	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_mode"):
		_toggle()
		get_viewport().set_input_as_handled()


func _toggle() -> void:
	var old_mode := _current_mode
	_current_mode = MODE_TACTICAL if _current_mode == MODE_PILOT else MODE_PILOT
	if _event_bus:
		_event_bus.game_mode_changed.emit(old_mode, _current_mode)


## Force a specific mode without toggling. Emits game_mode_changed if mode changed.
func set_mode(mode: String) -> void:
	if mode == _current_mode:
		return
	var old_mode := _current_mode
	_current_mode = mode
	if _event_bus:
		_event_bus.game_mode_changed.emit(old_mode, _current_mode)


func get_current_mode() -> String:
	return _current_mode
