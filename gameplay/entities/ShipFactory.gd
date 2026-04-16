class_name ShipFactory
extends RefCounted

const SHIP_SCENE := preload("res://gameplay/entities/Ship.tscn")


static func spawn_ship(content_id: String) -> Ship:
	var cr: Node = ServiceLocator.GetService("ContentRegistry") as Node
	if cr == null:
		push_error("ShipFactory: ContentRegistry missing")
		return null
	var data: Dictionary = cr.call("get_ship", content_id) as Dictionary
	if data.is_empty():
		push_error("ShipFactory: unknown ship '%s'" % content_id)
		return null
	var ship: Ship = SHIP_SCENE.instantiate() as Ship
	ship.configure_from_content(data, content_id)
	var perf: Node = ServiceLocator.GetService("PerformanceMonitor") as Node
	if perf != null:
		perf.begin("ShipFactory.assemble")
	_assemble_hardpoints(ship, data, cr)
	if perf != null:
		perf.end("ShipFactory.assemble")
	return ship


static func _assemble_hardpoints(ship: Ship, ship_data: Dictionary, cr: Node) -> void:
	var visual: Node3D = ship.get_node_or_null("VisualRoot") as Node3D
	if visual == null:
		return
	var hps: Array = ship_data.get("hardpoints", []) as Array
	var loadout: Dictionary = ship_data.get("default_loadout", {}) as Dictionary
	var weapons_map: Dictionary = loadout.get("weapons", {}) as Dictionary
	for hp_entry in hps:
		if typeof(hp_entry) != TYPE_DICTIONARY:
			continue
		var hp_dict: Dictionary = hp_entry
		var hid: String = str(hp_dict.get("id", ""))
		var offset: Array = hp_dict.get("offset", [0, 0]) as Array
		var ox: float = float(offset[0]) if offset.size() > 0 else 0.0
		var oz: float = float(offset[1]) if offset.size() > 1 else 0.0
		var hp_type: String = str(hp_dict.get("type", "gimbal"))
		var groups: Array = hp_dict.get("groups", []) as Array
		var marker := Marker3D.new()
		marker.name = "Hardpoint_%s" % hid
		marker.position = Vector3(ox, 0.0, oz)
		visual.add_child(marker)
		var hpc := HardpointComponent.new()
		hpc.name = "HardpointComponent"
		hpc.setup(hid, hp_type, groups)
		marker.add_child(hpc)
		ship.register_hardpoint_visual(marker)
		var wpn_id: String = str(weapons_map.get(hid, ""))
		if wpn_id.is_empty():
			continue
		var wdata: Dictionary = cr.call("get_weapon", wpn_id) as Dictionary
		if wdata.is_empty():
			continue
		wdata["id"] = wpn_id
		var wpn := WeaponComponent.new()
		wpn.name = "Weapon_%s" % wpn_id
		wpn.setup(ship, wdata, hpc)
		marker.add_child(wpn)
		ship.add_weapon_component(wpn)
