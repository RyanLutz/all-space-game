class_name SolarSystem
extends Node3D

## Scene manager for a destination star system.
## Call load_system() after adding to the scene tree; it generates the manifest
## and instantiates all visual nodes (stars, planets, moons, stations).
## get_belt_context_at() is the only interface ChunkStreamer calls.

var system_id: String = ""
var system_seed: int  = 0
var archetype: String = ""

var _stars: Array[Node3D]       = []
var _planets: Array[Node3D]     = []
var _belt_regions: Array        = []
var _world_origin: Vector3      = Vector3.ZERO
var _manifest: Dictionary       = {}
var _archetype_cfg: Dictionary  = {}

var _solar_system_root: Node3D
var _star_group: Node3D
var _planet_group: Node3D

var _perf: Node = null


func _ready() -> void:
	var sl := Engine.get_singleton("ServiceLocator")
	if sl:
		_perf = sl.GetService("PerformanceMonitor")

	_solar_system_root = Node3D.new()
	_solar_system_root.name = "SolarSystemRoot"
	add_child(_solar_system_root)

	_star_group = Node3D.new()
	_star_group.name = "StarGroup"
	_solar_system_root.add_child(_star_group)

	_planet_group = Node3D.new()
	_planet_group.name = "PlanetGroup"
	_solar_system_root.add_child(_planet_group)


## Generate and instantiate a system from (system_id, galaxy_seed, archetype_config).
## archetype_cfg is the parsed solar_system_archetypes.json Dictionary.
func load_system(p_system_id: String, galaxy_seed: int,
		archetype_cfg: Dictionary) -> void:
	system_id      = p_system_id
	_archetype_cfg = archetype_cfg

	if _perf:
		_perf.begin("SolarSystem.generate")

	var gen    := SolarSystemGenerator.new()
	_manifest   = gen.generate(system_id, galaxy_seed, archetype_cfg)

	if _perf:
		_perf.end("SolarSystem.generate")

	system_seed = int(_manifest.get("seed",      0))
	archetype   = _manifest.get("archetype", "barren")

	_build_stars()
	_build_planets()
	_belt_regions = _manifest.get("belts", [])

	if _perf:
		_perf.set_count("SolarSystem.planet_count",  _planets.size())
		_perf.set_count("SolarSystem.belt_count",    _belt_regions.size())
		_perf.set_count("SolarSystem.station_count", _count_stations())


# ── Scene construction ───────────────────────────────────────────────────────

func _build_stars() -> void:
	for c in _star_group.get_children():
		c.queue_free()
	_stars.clear()

	var star_datas: Array = _manifest.get("stars", [])
	for i in star_datas.size():
		var data: Dictionary = star_datas[i]
		var star := Node3D.new()
		star.set_script(load("res://gameplay/world/Star.gd"))
		star.name = "Star_%d" % i
		_star_group.add_child(star)

		var off: Array = data.get("position_offset", [0.0, 0.0, 0.0])
		star.position = Vector3(float(off[0]), float(off[1]), float(off[2]))

		(star as StarBody).setup(data)
		_stars.append(star)


func _build_planets() -> void:
	for c in _planet_group.get_children():
		c.queue_free()
	_planets.clear()

	var planet_datas: Array = _manifest.get("planets", [])
	for i in planet_datas.size():
		var data: Dictionary = planet_datas[i]
		var planet := _spawn_planet(data, _planet_group, false)
		planet.name = "Planet_%d" % i
		_planets.append(planet)

		# Moon group
		var moon_group := Node3D.new()
		moon_group.name = "MoonGroup"
		planet.add_child(moon_group)

		var moons: Array = data.get("moons", [])
		for j in moons.size():
			var moon := _spawn_planet(moons[j], moon_group, true)
			moon.name = "Moon_%d" % j

		# Station group
		var station_group := Node3D.new()
		station_group.name = "StationGroup"
		planet.add_child(station_group)

		var stations: Array = data.get("stations", [])
		for k in stations.size():
			var station := Node3D.new()
			station.set_script(load("res://gameplay/world/Station.gd"))
			station.name = "Station_%d" % k
			station_group.add_child(station)
			(station as StationPlacement).setup(stations[k])


func _spawn_planet(data: Dictionary, parent: Node3D, is_moon: bool) -> Node3D:
	var planet := Node3D.new()
	planet.set_script(load("res://gameplay/world/Planet.gd"))
	parent.add_child(planet)
	(planet as PlanetBody).setup(data, is_moon)
	return planet


func _count_stations() -> int:
	var count := 0
	for planet in _planets:
		var sg := planet.get_node_or_null("StationGroup")
		if sg:
			count += sg.get_child_count()
	return count


# ── Public API ───────────────────────────────────────────────────────────────

## Returns belt density context for a given world-space position.
## ChunkStreamer calls this per chunk before generating asteroid content.
func get_belt_context_at(world_pos: Vector3) -> Dictionary:
	var abs_pos   := world_pos + _world_origin
	var flat_dist := Vector2(abs_pos.x, abs_pos.z).length()

	for belt: Dictionary in _belt_regions:
		if flat_dist >= float(belt.get("inner_radius", 0.0)) \
				and flat_dist <= float(belt.get("outer_radius", 0.0)):
			return {
				"in_belt":              true,
				"density_multiplier":   float(belt.get("density_multiplier", 1.0)),
				"asteroid_type_weights": belt.get("asteroid_type_weights", {}),
			}

	return { "in_belt": false, "density_multiplier": 1.0, "asteroid_type_weights": {} }


## Called by OriginShifter (Session C) to track cumulative world offset.
func update_world_origin(offset: Vector3) -> void:
	_world_origin += offset


func get_manifest() -> Dictionary:
	return _manifest


func get_solar_system_root() -> Node3D:
	return _solar_system_root
