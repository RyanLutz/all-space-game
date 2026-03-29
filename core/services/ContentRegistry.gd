extends Node

# ContentRegistry — scans /content/ on startup and indexes all ships, weapons, and modules.
# Registered with ServiceLocator as "ContentRegistry".
# Every content item is a self-contained folder: folder name IS the item ID.

var ships: Dictionary = {}    # id → data dict (includes _id, _base_path)
var weapons: Dictionary = {}  # id → data dict
var modules: Dictionary = {}  # id → data dict

var _perf: Node


func _ready() -> void:
	_perf = ServiceLocator.GetService("PerformanceMonitor") as Node

	_perf.begin("ContentRegistry.load")
	_scan_directory("res://content/ships", ships, "ship.json")
	_scan_directory("res://content/weapons", weapons, "weapon.json")
	_scan_directory("res://content/modules", modules, "module.json")
	_perf.end("ContentRegistry.load")

	print("ContentRegistry: loaded %d ships, %d weapons, %d modules" % [
		ships.size(), weapons.size(), modules.size()
	])

	ServiceLocator.Register("ContentRegistry", self)


func _scan_directory(base_path: String, target: Dictionary, json_filename: String) -> void:
	var dir := DirAccess.open(base_path)
	if dir == null:
		push_warning("ContentRegistry: cannot open '%s' — skipping" % base_path)
		return

	dir.list_dir_begin()
	var folder_name := dir.get_next()
	while folder_name != "":
		if dir.current_is_dir() and not folder_name.begins_with("."):
			var json_path := "%s/%s/%s" % [base_path, folder_name, json_filename]
			if FileAccess.file_exists(json_path):
				var data := _load_json(json_path)
				if data != null:
					# Inject derived fields so consumers don't need folder-walking logic.
					data["id"] = folder_name
					data["_id"] = folder_name
					data["_base_path"] = "%s/%s" % [base_path, folder_name]
					target[folder_name] = data
		folder_name = dir.get_next()


func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("ContentRegistry: failed to open '%s'" % path)
		return {}

	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_error(
			"ContentRegistry: JSON parse failed for '%s': %s (line %d)" % [
				path, json.get_error_message(), json.get_error_line()
			]
		)
		return {}

	var data = json.get_data()
	if typeof(data) != TYPE_DICTIONARY:
		push_error("ContentRegistry: root must be a Dictionary in '%s'" % path)
		return {}

	return data


# --- Public API ---

func get_ship(id: String) -> Dictionary:
	return ships.get(id, {})


func get_weapon(id: String) -> Dictionary:
	return weapons.get(id, {})


func get_module(id: String) -> Dictionary:
	return modules.get(id, {})


## Returns the res:// path for an asset referenced by a content item.
## content_data must include _base_path (set by _scan_directory).
func get_asset_path(content_data: Dictionary, asset_key: String) -> String:
	var assets: Dictionary = content_data.get("assets", {})
	var filename: String = assets.get(asset_key, "")
	if filename.is_empty():
		return ""
	return "%s/%s" % [content_data.get("_base_path", ""), filename]
