extends Node
class_name ShipFactory

# ShipFactory — the only way to create ships.
# Spawns Ship.tscn and initializes it from content data.
# Returns the configured ship node; caller is responsible for adding it to the scene tree.

const _SHIP_SCENE := "res://gameplay/entities/Ship.tscn"
const _AI_CONTROLLER_SCENE := "res://gameplay/ai/AIController.tscn"


## Spawn a ship from content data.
##   ship_id          — folder name under /content/ships/ (e.g. "fighter_light")
##   pos              — world-space spawn position
##   is_player        — if true, ship is added to "player" group and PlayerState is updated
##   loadout_override — optional: replaces default_loadout.weapons/modules from ship.json
##
## Returns the Ship node (not yet in the scene tree). The caller must add_child() it.
func spawn_ship(ship_id: String, pos: Vector2, is_player: bool = false,
		loadout_override: Dictionary = {}) -> Node:
	var content_registry := ServiceLocator.GetService("ContentRegistry") as Node
	if content_registry == null:
		push_error("ShipFactory: ContentRegistry not registered — cannot spawn '%s'" % ship_id)
		return null

	var ship_data: Dictionary = content_registry.get_ship(ship_id)
	if ship_data.is_empty():
		push_error("ShipFactory: unknown ship id '%s'" % ship_id)
		return null

	if not ResourceLoader.exists(_SHIP_SCENE):
		push_error("ShipFactory: Ship.tscn not found at '%s'" % _SHIP_SCENE)
		return null

	var ship: Node = load(_SHIP_SCENE).instantiate()
	ship.global_position = pos
	ship.initialize(ship_data, loadout_override)

	if is_player:
		ship.is_player_controlled = true
		ship.add_to_group("player")
		var player_state := ServiceLocator.GetService("PlayerState") as Node
		if player_state != null:
			player_state.set_active_ship(ship)
	else:
		ship.is_player_controlled = false
		ship.faction = ship_data.get("faction", "neutral")
		ship.add_to_group("ships")
		ship.add_to_group("ai_ships")

		# Attach AI controller if scene exists
		if ResourceLoader.exists(_AI_CONTROLLER_SCENE):
			var ai: Node = load(_AI_CONTROLLER_SCENE).instantiate()
			var behavior_profile: String = ship_data.get("behavior_profile", "default")
			if ai.has_method("set_profile"):
				ai.set_profile(behavior_profile)
			ship.add_child(ai)

	return ship
