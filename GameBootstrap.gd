extends Node

# GameBootstrap is registered as an autoload in project.godot.
# It runs before any scene loads and owns the PerformanceMonitor, ContentRegistry,
# and PlayerState nodes for the lifetime of the application.
#
# Initialization order matters: PerformanceMonitor must exist before ContentRegistry
# (which uses it for the ContentRegistry.load metric), and both must exist before
# ProjectileManager's _ready() runs (autoload order: Bootstrap is #2, ProjectileManager is #4).
#
# Depends on:
#   ServiceLocator (autoload, C#) — registered before this node; call Register / GetService.

const _OVERLAY_SCENE := preload("res://ui/debug/PerformanceOverlay.tscn")

var perf_monitor: Node
var content_registry: Node
var player_state: Node


func _ready() -> void:
	_init_performance_monitor()
	_init_content_registry()
	_init_player_state()
	_init_debug_overlay()


func _init_performance_monitor() -> void:
	perf_monitor = load("res://core/services/PerformanceMonitor.gd").new()
	perf_monitor.name = "PerformanceMonitor"
	add_child(perf_monitor)
	ServiceLocator.Register("PerformanceMonitor", perf_monitor)


func _init_content_registry() -> void:
	content_registry = load("res://core/services/ContentRegistry.gd").new()
	content_registry.name = "ContentRegistry"
	add_child(content_registry)
	ServiceLocator.Register("ContentRegistry", content_registry)


func _init_player_state() -> void:
	player_state = load("res://core/services/PlayerState.gd").new()
	player_state.name = "PlayerState"
	add_child(player_state)
	ServiceLocator.Register("PlayerState", player_state)


func _init_debug_overlay() -> void:
	var overlay: Node = _OVERLAY_SCENE.instantiate()
	overlay.set_monitor(perf_monitor)
	# Add to root so it survives scene changes — never a child of gameplay nodes.
	get_tree().root.call_deferred("add_child", overlay)
