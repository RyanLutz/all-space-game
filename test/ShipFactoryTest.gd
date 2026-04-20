extends Node3D

## Test scene for ShipFactory. Spawns a player ship and an AI ship
## to verify the full assembly pipeline works correctly.

var _ship_factory: ShipFactory
var _player_state: Node
var _event_bus: Node

@export var test_class_id: String = "axum-fighter-1"
@export var test_variant_id: String = "axum_fighter_interceptor"
@export var test_faction: String = "axum"

func _ready() -> void:
	print("[ShipFactoryTest] Starting test...")

	var service_locator := Engine.get_singleton("ServiceLocator")
	if service_locator == null:
		push_error("[ShipFactoryTest] ServiceLocator not found!")
		return

	_ship_factory = ShipFactory.new()
	_ship_factory.name = "ShipFactory"
	add_child(_ship_factory)

	_player_state = service_locator.GetService("PlayerState")
	_event_bus = service_locator.GetService("GameEventBus")

	if _event_bus:
		_event_bus.connect("ship_destroyed", _on_ship_destroyed)
		_event_bus.connect("player_ship_changed", _on_player_ship_changed)

	# Spawn player ship — axum interceptor
	print("[ShipFactoryTest] Spawning player ship (axum_fighter_interceptor)...")
	var player_ship := _ship_factory.spawn_ship(
		test_class_id,
		test_variant_id,
		Vector3(0, 0, 0),
		test_faction,
		true
	)

	if player_ship:
		print("[ShipFactoryTest] Player ship spawned: %s" % player_ship.display_name)
		print("[ShipFactoryTest]   Class: %s  Variant: %s  Faction: %s" % [
			player_ship.class_id, player_ship.variant_id, player_ship.faction
		])
		print("[ShipFactoryTest]   Hull HP: %.0f / %.0f  Shield: %.0f / %.0f" % [
			player_ship.hull_hp, player_ship.hull_max,
			player_ship.shield_hp, player_ship.shield_max
		])
		_verify_hardpoints(player_ship)
	else:
		push_error("[ShipFactoryTest] Failed to spawn player ship!")

	# Spawn AI patrol variant — different appendage type so donut hardpoints assemble
	print("[ShipFactoryTest] Spawning AI ship (axum_fighter_patrol / pirate)...")
	var ai_ship := _ship_factory.spawn_ship(
		test_class_id,
		"corvette_patrol_heavy",
		Vector3(60, 0, 0),
		"pirate",
		false
	)

	if ai_ship:
		print("[ShipFactoryTest] AI ship spawned: %s" % ai_ship.display_name)
		_verify_hardpoints(ai_ship)
	else:
		push_error("[ShipFactoryTest] Failed to spawn AI ship!")

	print("[ShipFactoryTest] Test complete.")


func _verify_hardpoints(ship: RigidBody3D) -> void:
	var visual := ship.get_node_or_null("ShipVisual")
	if visual == null:
		push_error("[ShipFactoryTest] ShipVisual not found on %s" % ship.display_name)
		return

	var hardpoints: Array[Node] = []
	_collect_hardpoints(visual, hardpoints)

	print("[ShipFactoryTest]   Hardpoints found: %d" % hardpoints.size())
	for hp in hardpoints:
		var hc := hp.get_node_or_null("HardpointComponent")
		if hc:
			print("[ShipFactoryTest]     %s — type: %s  size: %s  weapon: %s" % [
				hp.name, hc.hardpoint_type, hc.size,
				hc.get_weapon_id() if hc.has_method("get_weapon_id") else "n/a"
			])
		else:
			print("[ShipFactoryTest]     %s — no HardpointComponent!" % hp.name)


func _collect_hardpoints(node: Node, result: Array[Node]) -> void:
	if node.name.begins_with("HardpointEmpty_"):
		result.append(node)
	for child in node.get_children():
		_collect_hardpoints(child, result)


func _on_ship_destroyed(ship: Node, destroy_pos: Vector3, faction: String) -> void:
	print("[ShipFactoryTest] Ship destroyed: %s at %s (faction: %s)" % [ship.display_name, destroy_pos, faction])


func _on_player_ship_changed(ship: Node) -> void:
	if ship:
		print("[ShipFactoryTest] Player ship changed to: %s" % ship.display_name)
	else:
		print("[ShipFactoryTest] Player ship cleared")
