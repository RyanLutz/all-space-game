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
##   faction_override — optional: overrides the faction field in ship.json (affects both
##                      ship.faction and behavior profile selection from factions.json)
##
## Returns the Ship node (not yet in the scene tree). The caller must add_child() it.
func spawn_ship(ship_id: String, pos: Vector2, is_player: bool = false,
		loadout_override: Dictionary = {}, faction_override: String = "") -> Node:
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
		ship.faction = faction_override if not faction_override.is_empty() \
			else ship_data.get("faction", "player")
		ship.add_to_group("player")
		var player_state := ServiceLocator.GetService("PlayerState") as Node
		if player_state != null:
			player_state.set_active_ship(ship)
	else:
		var effective_faction: String = faction_override if not faction_override.is_empty() \
			else ship_data.get("faction", "neutral")
		ship.is_player_controlled = false
		ship.faction = effective_faction
		ship.add_to_group("ships")
		ship.add_to_group("ai_ships")

		# Attach AI controller if scene exists
		if ResourceLoader.exists(_AI_CONTROLLER_SCENE):
			var ai: Node = load(_AI_CONTROLLER_SCENE).instantiate()
			var behavior_profile: String = ship_data.get("behavior_profile", "")
			if behavior_profile.is_empty():
				behavior_profile = _pick_faction_profile(effective_faction)
			if ai.has_method("set_profile"):
				ai.set_profile(behavior_profile)
			ship.add_child(ai)

	return ship


## Select a behavior profile weighted-randomly from the faction's profile_weights array.
## Falls back to "default" when factions.json is absent or the faction has no weights.
func _pick_faction_profile(faction_id: String) -> String:
	var file_path := "res://data/factions.json"
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return "default"

	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(text) != OK:
		return "default"

	var data = json.get_data()
	if typeof(data) != TYPE_DICTIONARY or not data.has("factions"):
		return "default"

	for faction_entry in data["factions"]:
		if typeof(faction_entry) != TYPE_DICTIONARY:
			continue
		if faction_entry.get("id", "") != faction_id:
			continue
		var weights: Array = faction_entry.get("profile_weights", [])
		if weights.is_empty():
			return "default"
		return _weighted_random_pick(weights)

	return "default"


func _weighted_random_pick(weights: Array) -> String:
	var total := 0.0
	for entry in weights:
		total += float(entry.get("weight", 1.0))

	var roll := randf() * total
	var cumulative := 0.0
	for entry in weights:
		cumulative += float(entry.get("weight", 1.0))
		if roll <= cumulative:
			return str(entry.get("profile", "default"))

	return str(weights[-1].get("profile", "default"))
