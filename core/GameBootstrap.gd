extends Node

## Orchestrates startup order. Creates core services, adds them to the tree,
## and registers them with ServiceLocator.
##
## Autoload order in project.godot:
##   1. ServiceLocator  (C# — registry only, no dependencies)
##   2. GameBootstrap    (this script — wires everything)

var _service_locator: Node = null

func _ready() -> void:
	# Get C# ServiceLocator singleton via Engine
	_service_locator = Engine.get_singleton("ServiceLocator")
	if _service_locator == null:
		push_error("[GameBootstrap] Failed to get ServiceLocator singleton")
		return

	_register_performance_monitor()
	_register_content_registry()
	_register_game_event_bus()
	_register_projectile_manager()
	_register_custom_monitors()
	print("[GameBootstrap] All core services registered.")


func _register_performance_monitor() -> void:
	var perf = preload("res://core/services/PerformanceMonitor.gd").new()
	perf.name = "PerformanceMonitor"
	add_child(perf)
	_service_locator.Register("PerformanceMonitor", perf)


func _register_content_registry() -> void:
	var registry = preload("res://core/services/ContentRegistry.gd").new()
	registry.name = "ContentRegistry"
	add_child(registry)
	_service_locator.Register("ContentRegistry", registry)

func _register_game_event_bus() -> void:
	var bus = preload("res://core/GameEventBus.gd").new()
	bus.name = "GameEventBus"
	add_child(bus)
	_service_locator.Register("GameEventBus", bus)


func _register_projectile_manager() -> void:
	var pm = load("res://gameplay/weapons/ProjectileManager.cs").new()
	pm.name = "ProjectileManager"
	add_child(pm)
	_service_locator.Register("ProjectileManager", pm)


## All Godot debugger custom monitors are registered here, once, to avoid
## duplicate-registration errors when systems with multiple instances each try
## to register their own monitor in _ready(). Per-call instrumentation
## (PerformanceMonitor.begin/end/set_count) still happens per-instance in the
## owning system.
func _register_custom_monitors() -> void:
	var perf = _service_locator.GetService("PerformanceMonitor")
	Performance.add_custom_monitor("AllSpace/projectiles_active",
		func(): return perf.get_count("ProjectileManager.active_count"))
	Performance.add_custom_monitor("AllSpace/ai_ships_active",
		func(): return perf.get_count("AIController.active_count"))
	Performance.add_custom_monitor("AllSpace/chunks_loaded",
		func(): return perf.get_count("ChunkStreamer.loaded_chunks"))
	Performance.add_custom_monitor("AllSpace/projectile_ms",
		func(): return perf.get_avg_ms("ProjectileManager.dumb_update"))
	Performance.add_custom_monitor("AllSpace/ai_ms",
		func(): return perf.get_avg_ms("AIController.state_updates"))
	Performance.add_custom_monitor("AllSpace/physics_ms",
		func(): return perf.get_avg_ms("Physics.thruster_allocation"))
	Performance.add_custom_monitor("AllSpace/nav_update_ms",
		func(): return perf.get_avg_ms("Navigation.update"))
