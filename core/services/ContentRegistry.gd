extends Node

## Scans /content/ at startup and indexes ships, weapons, and modules.
## Provides lookup by ID and asset path resolution.

var ships: Dictionary = {}
var weapons: Dictionary = {}
var modules: Dictionary = {}
var _factions: Dictionary = {}

func _ready() -> void:
	var perf: Node = ServiceLocator.GetService("PerformanceMonitor")
	perf.begin("ContentRegistry.load")
	_scan_directory("res://content/ships", ships, "ship.json")
	_scan_directory("res://content/weapons", weapons, "weapon.json")
	_scan_directory("res://content/modules", modules, "module.json")
	_load_factions("res://data/factions.json")
	perf.end("ContentRegistry.load")

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
				var data: Variant = _load_json(json_path)
				if data != null:
					data["_id"] = folder
					data["_base_path"] = "%s/%s" % [base_path, folder]
					target[folder] = data
		folder = dir.get_next()

func _load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("ContentRegistry: failed to open %s" % path)
		return null
	var content := file.get_as_text()
	file.close()
	var json := JSON.new()
	var error := json.parse(content)
	if error != OK:
		push_warning("ContentRegistry: JSON parse error in %s: %s" % [path, json.get_error_message()])
		return null
	var result = json.data
	if typeof(result) != TYPE_DICTIONARY:
		push_warning("ContentRegistry: JSON root is not a dictionary in %s" % path)
		return null
	return result

func _load_factions(path: String) -> void:
	var data: Variant = _load_json(path)
	if data == null:
		push_warning("ContentRegistry: failed to load factions from %s" % path)
		return
	if data.has("factions"):
		for faction in data["factions"]:
			if faction.has("id"):
				_factions[faction["id"]] = faction

func get_ship(id: String) -> Dictionary:
	var result: Dictionary = ships.get(id, {})
	if result.is_empty():
		push_warning("ContentRegistry: ship '%s' not found" % id)
	return result

func get_weapon(id: String) -> Dictionary:
	var result: Dictionary = weapons.get(id, {})
	if result.is_empty():
		push_warning("ContentRegistry: weapon '%s' not found" % id)
	return result

func get_module(id: String) -> Dictionary:
	var result: Dictionary = modules.get(id, {})
	if result.is_empty():
		push_warning("ContentRegistry: module '%s' not found" % id)
	return result

func get_faction(id: String) -> Dictionary:
	var result: Dictionary = _factions.get(id, {})
	if result.is_empty():
		push_warning("ContentRegistry: faction '%s' not found" % id)
	return result

func get_asset_path(content_data: Dictionary, asset_key: String) -> String:
	var filename: String = content_data.get("assets", {}).get(asset_key, "")
	if filename.is_empty():
		push_warning("ContentRegistry: asset key '%s' not found in content '%s'" % [asset_key, content_data.get("_id", "unknown")])
		return ""
	return "%s/%s" % [content_data["_base_path"], filename]
