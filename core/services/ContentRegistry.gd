extends Node
class_name ContentRegistry

# ContentRegistry — scans /content/ on startup and indexes all ships, weapons, and modules.
# Items are keyed by folder name (which is the item's ID).
# Each entry has all JSON fields plus:
#   "_id"        : String — folder name (the canonical content ID)
#   "_base_path" : String — "res://content/<type>/<id>"

var ships: Dictionary = {}    # id → ship data dict
var weapons: Dictionary = {}  # id → weapon data dict
var modules: Dictionary = {}  # id → module data dict


func _ready() -> void:
	PerformanceMonitor.begin("ContentRegistry.load")
	_scan_directory("res://content/ships",   ships,   "ship.json")
	_scan_directory("res://content/weapons", weapons, "weapon.json")
	_scan_directory("res://content/modules", modules, "module.json")
	PerformanceMonitor.end("ContentRegistry.load")

	print("ContentRegistry: loaded %d ships, %d weapons, %d modules" % [
		ships.size(), weapons.size(), modules.size()
	])


# ─── Public API ──────────────────────────────────────────────────────────────

func get_ship(id: String) -> Dictionary:
	return ships.get(id, {})


func get_weapon(id: String) -> Dictionary:
	return weapons.get(id, {})


func get_module(id: String) -> Dictionary:
	return modules.get(id, {})


func get_all_weapons() -> Dictionary:
	return weapons


func get_asset_path(content_data: Dictionary, asset_key: String) -> String:
	var assets: Dictionary = content_data.get("assets", {})
	var filename: String = assets.get(asset_key, "")
	if filename.is_empty():
		return ""
	var base: String = content_data.get("_base_path", "")
	if base.is_empty():
		return ""
	return "%s/%s" % [base, filename]


# ─── Internal ─────────────────────────────────────────────────────────────────

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
				if not data.is_empty():
					data["_id"] = folder_name
					data["id"] = folder_name  # kept for backward compat with code using weapon_data["id"]
					data["_base_path"] = "%s/%s" % [base_path, folder_name]
					target[folder_name] = data
		folder_name = dir.get_next()


func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("ContentRegistry: cannot open '%s'" % path)
		return {}

	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_error("ContentRegistry: JSON parse failed for '%s': %s (line %d)" % [
			path, json.get_error_message(), json.get_error_line()
		])
		return {}

	var data = json.get_data()
	if typeof(data) != TYPE_DICTIONARY:
		push_error("ContentRegistry: expected Dictionary root in '%s'" % path)
		return {}

	return data
