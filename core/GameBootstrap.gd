extends Node

## Orchestrates startup order. Creates core services, adds them to the tree,
## and registers them with ServiceLocator.
##
## Autoload order in project.godot:
##   1. ServiceLocator  (C# — registry only, no dependencies)
##   2. GameBootstrap    (this script — wires everything)

func _ready() -> void:
	_register_performance_monitor()
	_register_content_registry()
	_register_game_event_bus()
	print("[GameBootstrap] All core services registered.")


func _register_performance_monitor() -> void:
	var perf = preload("res://core/services/PerformanceMonitor.gd").new()
	perf.name = "PerformanceMonitor"
	add_child(perf)
	ServiceLocator.Register("PerformanceMonitor", perf)


func _register_content_registry() -> void:
	var registry = preload("res://core/services/ContentRegistry.gd").new()
	registry.name = "ContentRegistry"
	add_child(registry)
	ServiceLocator.Register("ContentRegistry", registry)

func _register_game_event_bus() -> void:
	var bus = preload("res://core/GameEventBus.gd").new()
	bus.name = "GameEventBus"
	add_child(bus)
	ServiceLocator.Register("GameEventBus", bus)
