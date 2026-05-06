class_name SolarSystemGenerator
extends RefCounted

## Pure generation logic — no scene manipulation.
## Returns a Dictionary manifest; SolarSystem reads it and instantiates nodes.
## Deterministic: same system_id + galaxy_seed always produces the same manifest.

func generate(system_id: String, galaxy_seed: int, cfg: Dictionary) -> Dictionary:
	# Hand-authored override takes precedence over procedural generation
	var override_path := "res://content/systems/%s/system.json" % system_id
	if ResourceLoader.exists(override_path):
		return _load_authored(override_path)

	var system_seed := hash(str(galaxy_seed) + system_id)
	var rng := RandomNumberGenerator.new()
	rng.seed = system_seed

	var archetype := _pick_archetype(rng, cfg)
	var stars    := _generate_stars(rng, archetype, cfg)
	var planets  := _generate_planets(rng, archetype, cfg)
	var belts    := _generate_belts(rng, archetype, planets, cfg)

	return {
		"system_id": system_id,
		"seed":      system_seed,
		"archetype": archetype,
		"stars":     stars,
		"planets":   planets,
		"belts":     belts,
	}


# ── Archetype selection ──────────────────────────────────────────────────────

func _pick_archetype(rng: RandomNumberGenerator, cfg: Dictionary) -> String:
	var archetypes: Dictionary = cfg.get("archetypes", {})
	return _pick_weighted(rng, _extract_weights(archetypes, "weight"))


# ── Star generation ──────────────────────────────────────────────────────────

func _generate_stars(rng: RandomNumberGenerator, archetype: String,
		cfg: Dictionary) -> Array:
	var arch: Dictionary = cfg.get("archetypes", {}).get(archetype, {})
	var vis:  Dictionary = cfg.get("visual", {})
	var ez:   Dictionary = cfg.get("exclusion_zone", {})
	var dps: float = float(ez.get("damage_per_second", 150.0))

	var is_binary := rng.randf() < float(arch.get("binary_star_chance", 0.05))

	if is_binary:
		var sep := float(vis.get("binary_star_separation", 5000.0))
		return [
			{
				"star_type":         "binary_primary",
				"position_offset":   [-sep * 0.5, 0.0, 0.0],
				"star_center_depth": float(vis.get("star_center_depth_binary", 1200.0)),
				"visual_radius":     float(vis.get("star_visual_radius_binary", 2200.0)),
				"exclusion_radius":  float(vis.get("star_exclusion_radius_binary", 1800.0)),
				"damage_per_second": dps,
				"light_energy":      1.4,
				"light_range":       80000.0,
			},
			{
				"star_type":         "binary_secondary",
				"position_offset":   [sep * 0.5, 0.0, 0.0],
				"star_center_depth": float(vis.get("star_center_depth_binary", 1200.0)),
				"visual_radius":     float(vis.get("star_visual_radius_binary", 2200.0)),
				"exclusion_radius":  float(vis.get("star_exclusion_radius_binary", 1800.0)),
				"damage_per_second": dps,
				"light_energy":      1.2,
				"light_range":       80000.0,
			},
		]
	else:
		return [
			{
				"star_type":         "yellow_dwarf",
				"position_offset":   [0.0, 0.0, 0.0],
				"star_center_depth": float(vis.get("star_center_depth_single", 2000.0)),
				"visual_radius":     float(vis.get("star_visual_radius_single", 3500.0)),
				"exclusion_radius":  float(vis.get("star_exclusion_radius_single", 2800.0)),
				"damage_per_second": dps,
				"light_energy":      1.2,
				"light_range":       100000.0,
			},
		]


# ── Planet generation ────────────────────────────────────────────────────────

func _generate_planets(rng: RandomNumberGenerator, archetype: String,
		cfg: Dictionary) -> Array:
	var arch: Dictionary = cfg.get("archetypes", {}).get(archetype, {})
	var gen:  Dictionary = cfg.get("generation", {})
	var vis:  Dictionary = cfg.get("visual", {})

	var count_range: Array  = arch.get("planet_count", [2, 6])
	var count: int = rng.randi_range(int(count_range[0]), int(count_range[1]))
	count = mini(count, int(gen.get("planet_count_max_absolute", 20)))

	var type_weights: Dictionary = arch.get("planet_type_weights",
		{"barren": 1.0})
	var station_weights: Dictionary = arch.get("station_count_per_planet_weights",
		{"0": 1.0})
	var station_max: int = int(gen.get("station_count_per_planet_max_absolute", 12))

	var moon_range: Array = gen.get("moon_count_per_planet", [0, 4])
	var moon_r_min := float(gen.get("moon_orbit_radius_min", 400.0))
	var moon_r_max := float(gen.get("moon_orbit_radius_max", 1400.0))
	var moon_spd_min := float(gen.get("orbit_speed_min", 0.002)) * 3.0
	var moon_spd_max := float(gen.get("orbit_speed_max", 0.015)) * 3.0
	var moon_vis_min := float(vis.get("moon_visual_radius_min", 60.0))
	var moon_vis_max := float(vis.get("moon_visual_radius_max", 220.0))
	var moon_dep_min := float(vis.get("moon_center_depth_min", 120.0))
	var moon_dep_max := float(vis.get("moon_center_depth_max", 350.0))

	var orbit_r := float(gen.get("orbit_radius_first_planet", 4000.0))
	var step_min := float(gen.get("orbit_radius_step_min", 2000.0))
	var step_max := float(gen.get("orbit_radius_step_max", 6000.0))
	var spd_min  := float(gen.get("orbit_speed_min", 0.002))
	var spd_max  := float(gen.get("orbit_speed_max", 0.015))

	var dep_min := float(vis.get("planet_center_depth_min", 600.0))
	var dep_max := float(vis.get("planet_center_depth_max", 1800.0))
	var vis_min := float(vis.get("planet_visual_radius_min", 300.0))
	var vis_max := float(vis.get("planet_visual_radius_max", 1400.0))
	var gas_vis_min := float(vis.get("gas_giant_visual_radius_min", 900.0))
	var gas_vis_max := float(vis.get("gas_giant_visual_radius_max", 2000.0))

	var planets: Array = []
	for _i in count:
		var ptype := _pick_weighted(rng, type_weights)
		var depth := rng.randf_range(dep_min, dep_max)
		var vr_min := gas_vis_min if ptype == "gas_giant" else vis_min
		var vr_max := gas_vis_max if ptype == "gas_giant" else vis_max
		# Clamp so sphere never intersects play plane (visual_radius < depth)
		var vr := minf(rng.randf_range(vr_min, vr_max), depth * 0.90)

		# Moons
		var moon_count := rng.randi_range(int(moon_range[0]), int(moon_range[1]))
		var moons: Array = []
		for _j in moon_count:
			var m_dep := rng.randf_range(moon_dep_min, moon_dep_max)
			var m_vr  := minf(rng.randf_range(moon_vis_min, moon_vis_max), m_dep * 0.85)
			moons.append({
				"orbit_radius": rng.randf_range(moon_r_min, moon_r_max),
				"orbit_angle":  rng.randf() * TAU,
				"orbit_speed":  rng.randf_range(moon_spd_min, moon_spd_max),
				"visual_radius": m_vr,
				"planet_depth": m_dep,
				"planet_type":  "barren",
			})

		# Stations
		var s_count := _pick_station_count(rng, station_weights, station_max)
		var stations: Array = []
		for _k in s_count:
			stations.append({ "station_type": "generic" })

		planets.append({
			"planet_type":   ptype,
			"orbit_radius":  orbit_r,
			"orbit_angle":   rng.randf() * TAU,
			"orbit_speed":   rng.randf_range(spd_min, spd_max),
			"visual_radius": vr,
			"planet_depth":  depth,
			"moons":         moons,
			"stations":      stations,
		})

		orbit_r += rng.randf_range(step_min, step_max)

	return planets


# ── Belt generation ──────────────────────────────────────────────────────────

func _generate_belts(rng: RandomNumberGenerator, archetype: String,
		planets: Array, cfg: Dictionary) -> Array:
	var arch: Dictionary = cfg.get("archetypes", {}).get(archetype, {})
	var belt: Dictionary = cfg.get("belt", {})

	var count_range: Array = arch.get("belt_count", [0, 2])
	var count: int = rng.randi_range(int(count_range[0]), int(count_range[1]))
	if count == 0:
		return []

	var w_min := float(belt.get("width_min", 3000.0))
	var w_max := float(belt.get("width_max", 8000.0))
	var d_min := float(belt.get("density_multiplier_min", 1.5))
	var d_max := float(belt.get("density_multiplier_max", 4.0))

	# Build candidate center radii: midpoints between planets + beyond last planet
	var candidates: Array[float] = []
	for i in range(1, planets.size()):
		candidates.append((float(planets[i - 1].orbit_radius)
			+ float(planets[i].orbit_radius)) * 0.5)
	var last_r: float = float(planets[-1].orbit_radius) if not planets.is_empty() \
		else 4000.0
	candidates.append(last_r + 3500.0)
	candidates.append(last_r + 9000.0)

	# RNG shuffle via keyed sort
	var keyed: Array = []
	for r in candidates:
		keyed.append({ "r": r, "k": rng.randf() })
	keyed.sort_custom(func(a, b): return a.k < b.k)

	var belts: Array = []
	for i in mini(count, keyed.size()):
		var center_r: float = float(keyed[i].r)
		var width := rng.randf_range(w_min, w_max)
		belts.append({
			"inner_radius":          maxf(0.0, center_r - width * 0.5),
			"outer_radius":          center_r + width * 0.5,
			"density_multiplier":    rng.randf_range(d_min, d_max),
			"asteroid_type_weights": { "small": 0.50, "medium": 0.35, "large": 0.15 },
		})

	return belts


# ── Shared helpers ───────────────────────────────────────────────────────────

func _load_authored(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("SolarSystemGenerator: cannot open %s" % path)
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("SolarSystemGenerator: JSON parse error in %s" % path)
		file.close()
		return {}
	file.close()
	return json.data


## Returns the key with probability proportional to its float value.
func _pick_weighted(rng: RandomNumberGenerator, weights: Dictionary) -> String:
	var total := 0.0
	for v in weights.values():
		total += float(v)
	if total <= 0.0:
		return weights.keys()[0] if not weights.is_empty() else ""
	var roll := rng.randf() * total
	var accum := 0.0
	for key in weights:
		accum += float(weights[key])
		if roll <= accum:
			return key
	return weights.keys()[-1]


## Extracts a sub-dictionary of {key: float(data[key][field])} for weighted picking.
func _extract_weights(data: Dictionary, field: String) -> Dictionary:
	var out: Dictionary = {}
	for key in data:
		if data[key] is Dictionary and data[key].has(field):
			out[key] = float(data[key][field])
	return out


func _pick_station_count(rng: RandomNumberGenerator, weights: Dictionary,
		max_abs: int) -> int:
	var total := 0.0
	for v in weights.values():
		total += float(v)
	if total <= 0.0:
		return 0
	var roll := rng.randf() * total
	var accum := 0.0
	for key in weights:
		accum += float(weights[key])
		if roll <= accum:
			if "+" in key:
				var base := int(key.replace("+", ""))
				return rng.randi_range(base, mini(base + 4, max_abs))
			return mini(int(key), max_abs)
	return 0
