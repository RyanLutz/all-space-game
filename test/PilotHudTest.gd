extends "res://test/PilotLoopTest.gd"

const PilotHUDScript := preload("res://ui/pilot/PilotHUD.gd")

var _pilot_hud


func _ready() -> void:
	super()

	# Reuse PilotLoopTest setup and layer a dedicated pilot HUD on top.
	var pilot_layer := CanvasLayer.new()
	pilot_layer.name = "PilotHUDLayer"
	pilot_layer.layer = 20
	add_child(pilot_layer)

	_pilot_hud = PilotHUDScript.new()
	_pilot_hud.name = "PilotHUD"
	pilot_layer.add_child(_pilot_hud)

	# _player_ship is initialized by PilotLoopTest._ready().
	_pilot_hud.set_player_ship(_player_ship)
