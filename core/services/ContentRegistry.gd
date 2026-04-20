extends Node
class_name ContentRegistry

## Scans /content/ at startup and indexes ships, weapons, and modules by folder name.
## All content is JSON-driven — adding a new ship requires only a new folder.

var ships: Dictionary = {}
var weapons: Dictionary = {}
var modules: Dictionary = {}
var _factions: Dictionary = {}
var _ai_profiles: Dictionary = {}

var _perf: Node

func _ready() -> void:
	var service_locator := Engine.get_singleton("ServiceLocator")
	_perf = service_locator.GetService("PerformanceMonitor")

	_perf.begin("ContentRegistry.load")

	_scan_directory("res://content/ships", ships, "ship.json")
	_scan_directory("res://content/weapons", weapons, "weapon.json")
	_scan_directory("res://content/modules", modules, "module.json")
	_load_factions("res://data/factions.json")
	_load_ai_profiles("res://data/ai_profiles.json")

	_perf.end("ContentRegistry.load")

	print("[ContentRegistry] Loaded: %d ships, %d weapons, %d modules, %d factions, %d AI profiles" % [
		ships.size(), weapons.size(), modules.size(), _factions.size(), _ai_profiles.size()
	])


func _scan_directory(base_path: String, target: Dictionary, filename: String) -> void:
	var dir := DirAccess.open(base_path)
	if dir == null:
		push_warning("ContentRegistry: cannot open %s" % base_path)
		return

	dir.list_dir_begin()
	var folder := dir.get_next()
	while folder != "":
		if dir.current_is_dir() and not folder.begins_with("."):
			var json_path := "%s/%s/%s" % [base_path, folder, filename]
			if FileAccess.file_exists(json_path):
				var data := _load_json(json_path)
				if data != null:
					data["_id"] = folder
					data["_base_path"] = "%s/%s" % [base_path, folder]
					target[folder] = data
		folder = dir.get_next()


func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("ContentRegistry: cannot read %s" % path)
		return {}

	var json_str := file.get_as_text()
	file.close()

	var json := JSON.new()
	var err := json.parse(json_str)
	if err != OK:
		push_error("ContentRegistry: JSON parse error in %s: %s" % [path, json.get_error_message()])
		return {}

	return json.data


func _load_factions(path: String) -> void:
	var data := _load_json(path)
	if data.has("factions"):
		for faction in data["factions"]:
			_factions[faction["id"]] = faction


func _load_ai_profiles(path: String) -> void:
	var data := _load_json(path)
	if data.has("ai_profiles"):
		for profile in data["ai_profiles"]:
			_ai_profiles[profile["id"]] = profile


# ─── Public API ─────────────────────────────────────────────────────────────

func get_ship(id: String) -> Dictionary:
	return ships.get(id, {})


func get_weapon(id: String) -> Dictionary:
	return weapons.get(id, {})


func get_module(id: String) -> Dictionary:
	return modules.get(id, {})


func get_faction(id: String) -> Dictionary:
	return _factions.get(id, {})


func get_ai_profile(id: String) -> Dictionary:
	return _ai_profiles.get(id, {})


func get_asset_path(content_data: Dictionary, asset_key: String) -> String:
	var filename: String = content_data.get("assets", {}).get(asset_key, "")
	if filename.is_empty():
		return ""
	return "%s/%s" % [content_data["_base_path"], filename]


func get_variant(class_id: String, variant_id: String) -> Dictionary:
	var class_data := get_ship(class_id)
	return class_data.get("variants", {}).get(variant_id, {})


func get_class_for_variant(variant_id: String) -> String:
	for class_id in ships:
		if ships[class_id].get("variants", {}).has(variant_id):
			return class_id
	return ""
