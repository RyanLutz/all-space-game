extends Node

# GameBootstrap is registered as an autoload in project.godot.
# It runs before any scene loads and owns the PerformanceMonitor node for
# the lifetime of the application.
#
# Depends on:
#   ServiceLocator.cs — must be registered as an autoload before this one.
#                       Uncomment the ServiceLocator line once that system exists.

const _OVERLAY_SCENE := preload("res://ui/debug/PerformanceOverlay.tscn")

var perf_monitor: Node


func _ready() -> void:
	_init_performance_monitor()
	_init_debug_overlay()


func _init_performance_monitor() -> void:
	perf_monitor = load("res://core/services/PerformanceMonitor.gd").new()
	perf_monitor.name = "PerformanceMonitor"
	add_child(perf_monitor)

	# Uncomment once ServiceLocator.cs is implemented:
	# ServiceLocator.register("PerformanceMonitor", perf_monitor)


func _init_debug_overlay() -> void:
	var overlay: Node = _OVERLAY_SCENE.instantiate()
	overlay.set_monitor(perf_monitor)
	# Add to root so it survives scene changes — never a child of gameplay nodes.
	get_tree().root.call_deferred("add_child", overlay)
