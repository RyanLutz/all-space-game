class_name StarFieldAutoload
extends Node

## Full star catalog — backdrop + destination stars. Always in memory.
var _catalog: Array[SFStarRecord] = []
## Filtered subset — destination systems only.
var _destinations: Array[SFStarRecord] = []
## Nebula catalog — always in memory.
var _nebulae: Array[SFNebulaVolume] = []

var _galaxy_seed: int
var _config: Dictionary
## Set by warp system on jump — the system the player currently occupies.
var current_system: SFStarRecord

## Reference to the active sky shader material (wired in Session 3).
var sky_material: ShaderMaterial

var _perf: Node


func _ready() -> void:
	var sl = Engine.get_singleton("ServiceLocator")
	if sl:
		_perf = sl.GetService("PerformanceMonitor")

	var config_file := FileAccess.open("res://data/world_config.json", FileAccess.READ)
	if not config_file:
		push_error("StarField: cannot open world_config.json")
		return
	var json := JSON.new()
	var err := json.parse(config_file.get_as_text())
	config_file.close()
	if err != OK:
		push_error("StarField: JSON parse error — %s" % json.get_error_message())
		return

	var data: Dictionary = json.data
	if not data.has("starfield"):
		push_error("StarField: world_config.json missing 'starfield' block")
		return

	_config = data["starfield"]
	_galaxy_seed = int(_config.get("galaxy_seed", 8675309))
	generate_catalog()


## Generates the full galaxy catalog from the seed and config.
func generate_catalog() -> void:
	_catalog.clear()
	_destinations.clear()
	_nebulae.clear()

	if _perf:
		_perf.begin("StarField.generate")

	var cfg := _config
	var galaxy_radius: float = cfg.get("galaxy_radius", 100000.0)

	# --- Zone parameters ---
	var zone_core_center: Dictionary = cfg.get("zone_core_center", {})
	var zone_core_outer: Dictionary = cfg.get("zone_core_outer", {})
	var zone_arms: Dictionary = cfg.get("zone_arms", {})
	var zone_disc: Dictionary = cfg.get("zone_disc", {})
	var zone_overlap_pct: float = cfg.get("zone_overlap_pct", 15.0)

	var star_type_weights: Dictionary = cfg.get("star_type_weights", {})
	var star_types: Dictionary = cfg.get("star_types", {})
	var color_core := _arr_to_color(cfg.get("color_core", [1.0, 0.6, 0.4]))
	var color_outer := _arr_to_color(cfg.get("color_outer", [0.6, 0.8, 1.0]))
	var color_variation: float = cfg.get("color_variation", 0.25)

	# Pre-bake zone radii from percentages
	var core_center_r: float = zone_core_center.get("radius_pct", 8.0) / 100.0 * galaxy_radius
	var core_center_h: float = zone_core_center.get("height_pct", 6.0) / 100.0 * galaxy_radius
	var core_center_density: float = zone_core_center.get("density", 0.5)

	var core_outer_r: float = zone_core_outer.get("radius_pct", 25.0) / 100.0 * galaxy_radius
	var core_outer_h: float = zone_core_outer.get("height_pct", 12.0) / 100.0 * galaxy_radius
	var core_outer_density: float = zone_core_outer.get("density", 0.3)
	var core_falloff: float = zone_core_outer.get("falloff_curve", 1.2)

	var arm_start_r: float = zone_arms.get("start_radius_pct", 10.0) / 100.0 * galaxy_radius
	var arm_end_r: float = zone_arms.get("end_radius_pct", 90.0) / 100.0 * galaxy_radius
	var arm_count: int = int(zone_arms.get("arm_count", 2))
	var arm_tightness_start: float = zone_arms.get("arm_tightness_start", 0.3)
	var arm_tightness_end: float = zone_arms.get("arm_tightness_end", 0.1)
	var arm_width_start: float = zone_arms.get("arm_width_start", 0.35)
	var arm_width_end: float = zone_arms.get("arm_width_end", 0.15)
	var arm_density: float = zone_arms.get("density", 0.6)

	var disc_r: float = zone_disc.get("radius_pct", 100.0) / 100.0 * galaxy_radius
	var disc_h_min: float = zone_disc.get("height_min_pct", 1.0) / 100.0 * galaxy_radius
	var disc_h_max: float = zone_disc.get("height_max_pct", 8.0) / 100.0 * galaxy_radius
	var disc_density: float = zone_disc.get("density", 0.2)
	var disc_falloff: float = zone_disc.get("falloff_curve", 2.0)

	var overlap: float = zone_overlap_pct / 100.0

	# Bake cumulative type weights for weighted random selection
	var type_keys: Array = star_type_weights.keys()
	var type_cdf: PackedFloat64Array = _build_cdf(star_type_weights, type_keys)

	# Pack zone params into a dictionary for the position sampler
	var zp := {
		"galaxy_radius": galaxy_radius,
		"core_center_r": core_center_r, "core_center_h": core_center_h,
		"core_center_density": core_center_density,
		"core_outer_r": core_outer_r, "core_outer_h": core_outer_h,
		"core_outer_density": core_outer_density, "core_falloff": core_falloff,
		"arm_start_r": arm_start_r, "arm_end_r": arm_end_r,
		"arm_count": arm_count,
		"arm_tightness_start": arm_tightness_start, "arm_tightness_end": arm_tightness_end,
		"arm_width_start": arm_width_start, "arm_width_end": arm_width_end,
		"arm_density": arm_density,
		"disc_r": disc_r, "disc_h_min": disc_h_min, "disc_h_max": disc_h_max,
		"disc_density": disc_density, "disc_falloff": disc_falloff,
		"overlap": overlap,
	}

	# --- Backdrop stars (own RNG branch) ---
	var backdrop_count: int = int(cfg.get("backdrop_star_count", 8000))
	var rng := RandomNumberGenerator.new()
	rng.seed = _galaxy_seed

	for i in backdrop_count:
		var record := SFStarRecord.new()
		record.id = i
		record.is_destination = false
		record.galaxy_position = _sample_galaxy_position(rng, zp)
		record.star_type = _pick_star_type(rng, type_keys, type_cdf)
		_apply_type_appearance(record, star_types, color_core, color_outer,
				color_variation, galaxy_radius, rng)
		_catalog.append(record)

	# --- Destination systems (separate RNG so count doesn't affect backdrop) ---
	var dest_count: int = int(cfg.get("destination_system_count", 400))
	var dest_rng := RandomNumberGenerator.new()
	dest_rng.seed = _galaxy_seed ^ 0xDEADBEEF
	var warp_min: float = cfg.get("warp_range_min", 8000.0)
	var warp_max: float = cfg.get("warp_range_max", 20000.0)

	for i in dest_count:
		var record := SFStarRecord.new()
		record.id = _catalog.size()
		record.is_destination = true
		record.galaxy_position = _sample_galaxy_position(dest_rng, zp)
		record.system_id = StringName("sys_%05d" % i)
		record.star_type = _pick_star_type(dest_rng, type_keys, type_cdf)
		_apply_type_appearance(record, star_types, color_core, color_outer,
				color_variation, galaxy_radius, dest_rng)
		record.warp_range = dest_rng.randf_range(warp_min, warp_max)
		_catalog.append(record)
		_destinations.append(record)

	# --- Nebulae (separate RNG branch) ---
	var neb_count: int = int(cfg.get("nebula_count", 24))
	var neb_rng := RandomNumberGenerator.new()
	neb_rng.seed = _galaxy_seed ^ 0xCAFEBABE
	var neb_r_min: float = cfg.get("nebula_radius_min", 8000.0)
	var neb_r_max: float = cfg.get("nebula_radius_max", 28000.0)
	var neb_colors_raw: Array = cfg.get("nebula_colors", [])

	for i in neb_count:
		var vol := SFNebulaVolume.new()
		vol.id = i
		vol.galaxy_position = _sample_nebula_position(neb_rng, galaxy_radius)
		vol.radius = neb_rng.randf_range(neb_r_min, neb_r_max)
		vol.color = _pick_nebula_color(neb_rng, neb_colors_raw)
		vol.opacity = neb_rng.randf_range(0.3, 0.8)
		_nebulae.append(vol)

	if _perf:
		_perf.end("StarField.generate")
		_perf.set_count("StarField.backdrop_count",
				_catalog.size() - _destinations.size())
		_perf.set_count("StarField.destination_count", _destinations.size())


# ---------------------------------------------------------------------------
#  Public API
# ---------------------------------------------------------------------------

func get_catalog() -> Array[SFStarRecord]:
	return _catalog

func get_destinations() -> Array[SFStarRecord]:
	return _destinations

func get_nebulae() -> Array[SFNebulaVolume]:
	return _nebulae

func get_galaxy_seed() -> int:
	return _galaxy_seed

func get_config() -> Dictionary:
	return _config

## Rebuilds the skybox from the given system position.
##
## Called by the Warp system after a jump completes, and by the test scene
## to simulate warps. Packs star directions into two sampler2D textures and
## uploads all nebula uniforms to sky_material. Runs once per warp — zero
## per-frame CPU cost during gameplay.
##
## sky_material must be set before calling this (see StarFieldTest._setup_skybox).
func rebuild_skybox(system_position: Vector3) -> void:
	if sky_material == null:
		return

	if _perf:
		_perf.begin("StarField.rebuild_skybox")

	# Build the list of stars to pack into the skybox textures.
	# Always include all destination systems so navigable stars appear in the
	# sky. Then fill remaining slots with backdrop stars.
	var sky_cfg: Dictionary = _config.get("nebula_sky_shader", {})
	var skybox_limit: int   = int(sky_cfg.get("skybox_star_limit", 3000))

	var backdrop_slots: int = max(0, skybox_limit - _destinations.size())
	var skybox_stars: Array[SFStarRecord] = []

	var added_backdrops := 0
	for star: SFStarRecord in _catalog:
		if star.is_destination:
			continue
		if added_backdrops >= backdrop_slots:
			break
		skybox_stars.append(star)
		added_backdrops += 1
	# Destinations appended after backdrops so they're always represented
	skybox_stars.append_array(_destinations)

	# Pack into textures — width fixed at 64, height computed from star count
	var count: int = skybox_stars.size()
	var tex_w: int = 64
	var tex_h: int = max(1, int(ceil(float(count) / float(tex_w))))

	var dir_image := Image.create(tex_w, tex_h, false, Image.FORMAT_RGBAF)
	var col_image := Image.create(tex_w, tex_h, false, Image.FORMAT_RGBA8)

	for j in count:
		var star: SFStarRecord = skybox_stars[j]
		star.sky_direction = (star.galaxy_position - system_position).normalized()
		var x: int = j % tex_w
		var y: int = int(float(j) / float(tex_w))
		dir_image.set_pixel(x, y, Color(
			star.sky_direction.x,
			star.sky_direction.y,
			star.sky_direction.z,
			star.apparent_size))
		col_image.set_pixel(x, y, Color(
			star.color.r,
			star.color.g,
			star.color.b,
			star.brightness))

	sky_material.set_shader_parameter("star_directions",
		ImageTexture.create_from_image(dir_image))
	sky_material.set_shader_parameter("star_colors",
		ImageTexture.create_from_image(col_image))
	sky_material.set_shader_parameter("star_count", count)
	sky_material.set_shader_parameter("tex_width",  tex_w)
	sky_material.set_shader_parameter("tex_height", tex_h)

	# Galaxy-space position shifts the noise field so the nebula sky changes
	# plausibly on warp: short jump = subtle shift, long jump = different sky
	sky_material.set_shader_parameter("player_galaxy_position", system_position)
	sky_material.set_shader_parameter("galaxy_noise_influence",
		float(sky_cfg.get("galaxy_noise_influence", 0.00002)))
	sky_material.set_shader_parameter("coarse_frequency",
		float(sky_cfg.get("coarse_frequency", 1.2)))
	sky_material.set_shader_parameter("fine_frequency",
		float(sky_cfg.get("fine_frequency", 4.5)))
	sky_material.set_shader_parameter("noise_warp_strength",
		float(sky_cfg.get("noise_warp_strength", 0.6)))
	sky_material.set_shader_parameter("nebula_base_opacity",
		float(sky_cfg.get("nebula_base_opacity", 0.35)))

	_upload_nebula_uniforms(system_position)

	if _perf:
		_perf.end("StarField.rebuild_skybox")


## Packs nebula volume data into parallel uniform arrays for the sky shader.
## Must be called after star textures are uploaded — both are part of one logical
## rebuild operation. Nebula directions and angular radii are recalculated relative
## to the player's current system position.
func _upload_nebula_uniforms(system_position: Vector3) -> void:
	if sky_material == null:
		return

	const MAX_NEBULAE := 32

	var dirs   := PackedVector3Array()
	var colors := PackedColorArray()
	var radii  := PackedFloat32Array()
	dirs.resize(MAX_NEBULAE)
	colors.resize(MAX_NEBULAE)
	radii.resize(MAX_NEBULAE)

	# Zero-fill (GDScript does not guarantee default init of packed arrays)
	for i in MAX_NEBULAE:
		dirs[i]   = Vector3.ZERO
		colors[i] = Color(0.0, 0.0, 0.0, 0.0)
		radii[i]  = 0.0

	var count := 0
	for vol: SFNebulaVolume in _nebulae:
		if count >= MAX_NEBULAE:
			break
		var offset := vol.galaxy_position - system_position
		var dist   := offset.length()
		if dist < 1.0:
			count += 1
			continue

		dirs[count]  = offset / dist  # normalized direction
		var c        := vol.color
		c.a          = vol.opacity
		colors[count] = c
		# Angular radius: physical radius / distance (chord ≈ radians for small angles).
		# When inside a nebula (dist < vol.radius), angular_r > 1 — the whole sky
		# is tinted by that nebula, which is the correct behavior.
		radii[count] = vol.radius / dist
		count += 1

	sky_material.set_shader_parameter("nebula_count",          count)
	sky_material.set_shader_parameter("nebula_dirs",           dirs)
	sky_material.set_shader_parameter("nebula_colors",         colors)
	sky_material.set_shader_parameter("nebula_angular_radii",  radii)


# ---------------------------------------------------------------------------
#  Galaxy position sampling — four-zone weighted rejection
# ---------------------------------------------------------------------------

## Samples a position within the galaxy volume using four-zone weighted
## accept/reject. Each candidate position computes a blended weight from
## all four zones; the candidate is accepted with probability proportional
## to the total weight. This avoids hard zone boundaries.
func _sample_galaxy_position(rng: RandomNumberGenerator, zp: Dictionary) -> Vector3:
	var galaxy_r: float = zp["galaxy_radius"]
	var max_attempts := 200

	for _attempt in max_attempts:
		# Area-uniform proposal in a cylinder, then shaped by acceptance
		var r: float = sqrt(rng.randf()) * galaxy_r
		var theta: float = rng.randf() * TAU
		var max_h: float = _y_thickness_at_radius(r, zp)
		var y: float = rng.randf_range(-max_h, max_h)

		var pos := Vector3(r * cos(theta), y, r * sin(theta))
		var norm_r: float = r / galaxy_r

		# Accumulate zone weights with smoothstep blending
		var weight := 0.0
		weight += _zone_core_center_weight(norm_r, zp)
		weight += _zone_core_outer_weight(norm_r, zp)
		weight += _zone_arm_weight(r, theta, norm_r, zp)
		weight += _zone_disc_weight(norm_r, zp)

		# Accept/reject — weight is in [0, ~2] range; normalize against max
		if rng.randf() < weight:
			return pos

	# Fallback: shouldn't happen with reasonable densities
	return Vector3(
		rng.randf_range(-galaxy_r * 0.5, galaxy_r * 0.5),
		0.0,
		rng.randf_range(-galaxy_r * 0.5, galaxy_r * 0.5))


## Y-thickness decreases with radius: fat spherical core, thin outer disc.
func _y_thickness_at_radius(r: float, zp: Dictionary) -> float:
	var norm_r: float = clampf(r / zp["galaxy_radius"], 0.0, 1.0)
	return lerpf(zp["disc_h_max"], zp["disc_h_min"], norm_r)


# ---------------------------------------------------------------------------
#  Zone weight functions — all use smoothstep for soft transitions
# ---------------------------------------------------------------------------

func _zone_core_center_weight(norm_r: float, zp: Dictionary) -> float:
	var edge: float = zp["core_center_r"] / zp["galaxy_radius"]
	var overlap: float = zp["overlap"] * edge
	# Full weight inside core, falls off with smoothstep at boundary
	return zp["core_center_density"] * (1.0 - smoothstep(edge - overlap, edge + overlap, norm_r))


func _zone_core_outer_weight(norm_r: float, zp: Dictionary) -> float:
	var inner: float = zp["core_center_r"] / zp["galaxy_radius"]
	var outer: float = zp["core_outer_r"] / zp["galaxy_radius"]
	var overlap: float = zp["overlap"]
	var inner_blend: float = smoothstep(inner * (1.0 - overlap), inner * (1.0 + overlap), norm_r)
	var outer_blend: float = 1.0 - smoothstep(outer * (1.0 - overlap), outer * (1.0 + overlap), norm_r)
	var radial_falloff: float = pow(1.0 - clampf((norm_r - inner) / maxf(outer - inner, 0.001), 0.0, 1.0), zp["core_falloff"])
	return zp["core_outer_density"] * inner_blend * outer_blend * radial_falloff


func _zone_arm_weight(r: float, theta: float, norm_r: float, zp: Dictionary) -> float:
	var arm_start_nr: float = zp["arm_start_r"] / zp["galaxy_radius"]
	var arm_end_nr: float = zp["arm_end_r"] / zp["galaxy_radius"]
	var overlap: float = zp["overlap"]

	# Radial envelope — arms exist between start and end radius with smooth edges
	var radial: float = smoothstep(arm_start_nr * (1.0 - overlap), arm_start_nr * (1.0 + overlap), norm_r)
	radial *= 1.0 - smoothstep(arm_end_nr * (1.0 - overlap), arm_end_nr * (1.0 + overlap), norm_r)
	if radial < 0.001:
		return 0.0

	# Logarithmic spiral: r = e^(b * theta)
	# Solve for the expected theta at this radius for each arm
	var arm_count: int = zp["arm_count"]
	var t_norm: float = clampf((norm_r - arm_start_nr) / maxf(arm_end_nr - arm_start_nr, 0.001), 0.0, 1.0)
	var b: float = lerpf(zp["arm_tightness_start"], zp["arm_tightness_end"], t_norm)
	var arm_width: float = lerpf(zp["arm_width_start"], zp["arm_width_end"], t_norm)

	# Find closest arm distance (angular)
	var best_proximity := 0.0
	if r > 0.001 and b > 0.001:
		var expected_theta: float = log(r / maxf(zp["arm_start_r"], 1.0)) / b
		for arm_i in arm_count:
			var arm_offset: float = float(arm_i) * TAU / float(arm_count)
			var diff: float = fmod(theta - expected_theta - arm_offset, TAU)
			if diff < 0.0:
				diff += TAU
			if diff > PI:
				diff = TAU - diff
			# Gaussian proximity: exp(-0.5 * (diff / sigma)^2)
			var sigma: float = arm_width
			var proximity: float = exp(-0.5 * (diff / sigma) * (diff / sigma))
			best_proximity = maxf(best_proximity, proximity)

	return zp["arm_density"] * radial * best_proximity


func _zone_disc_weight(norm_r: float, zp: Dictionary) -> float:
	var edge: float = zp["disc_r"] / zp["galaxy_radius"]
	var overlap: float = zp["overlap"] * edge
	var boundary: float = 1.0 - smoothstep(edge - overlap, edge + overlap, norm_r)
	var radial_falloff: float = pow(1.0 - clampf(norm_r / maxf(edge, 0.001), 0.0, 1.0), zp["disc_falloff"])
	return zp["disc_density"] * boundary * radial_falloff


# ---------------------------------------------------------------------------
#  Star type selection and appearance
# ---------------------------------------------------------------------------

func _build_cdf(weights: Dictionary, keys: Array) -> PackedFloat64Array:
	var cdf := PackedFloat64Array()
	var accum := 0.0
	for k in keys:
		accum += float(weights[k])
		cdf.append(accum)
	# Normalize
	if accum > 0.0:
		for i in cdf.size():
			cdf[i] /= accum
	return cdf


func _pick_star_type(rng: RandomNumberGenerator, keys: Array,
		cdf: PackedFloat64Array) -> StringName:
	var roll: float = rng.randf()
	for i in keys.size():
		if roll <= cdf[i]:
			return StringName(keys[i])
	return StringName(keys[keys.size() - 1])


func _apply_type_appearance(record: SFStarRecord, star_types: Dictionary,
		color_core: Color, color_outer: Color, color_variation: float,
		galaxy_radius: float, rng: RandomNumberGenerator) -> void:
	var type_key: String = record.star_type
	var type_data: Dictionary = star_types.get(type_key, {})

	# Base color from star type
	var type_color := _arr_to_color(type_data.get("color", [1.0, 1.0, 1.0]))

	# Galactic position color gradient — core is orange-red, outer is blue-white
	var r: float = record.galaxy_position.length()
	var norm_r: float = clampf(r / galaxy_radius, 0.0, 1.0)
	var gradient_color: Color = color_core.lerp(color_outer, norm_r)

	# Blend type color with gradient (50/50 mix) then add noise
	record.color = type_color.lerp(gradient_color, 0.5)
	record.color.r = clampf(record.color.r + rng.randf_range(-color_variation, color_variation), 0.0, 1.0)
	record.color.g = clampf(record.color.g + rng.randf_range(-color_variation, color_variation), 0.0, 1.0)
	record.color.b = clampf(record.color.b + rng.randf_range(-color_variation, color_variation), 0.0, 1.0)
	record.color.a = 1.0

	record.brightness = float(type_data.get("brightness", 0.5))
	record.apparent_size = float(type_data.get("apparent_size", 0.0005))


# ---------------------------------------------------------------------------
#  Nebula placement
# ---------------------------------------------------------------------------

func _sample_nebula_position(rng: RandomNumberGenerator, galaxy_radius: float) -> Vector3:
	# Nebulae concentrate in the disc area, not the very center
	var r: float = rng.randf_range(galaxy_radius * 0.1, galaxy_radius * 0.85)
	var theta: float = rng.randf() * TAU
	var y: float = rng.randf_range(-galaxy_radius * 0.03, galaxy_radius * 0.03)
	return Vector3(r * cos(theta), y, r * sin(theta))


func _pick_nebula_color(rng: RandomNumberGenerator, palette: Array) -> Color:
	if palette.is_empty():
		return Color(0.5, 0.3, 0.8, 1.0)
	var arr: Array = palette[rng.randi() % palette.size()]
	return _arr_to_color(arr)


# ---------------------------------------------------------------------------
#  Utility
# ---------------------------------------------------------------------------

static func _arr_to_color(arr: Variant) -> Color:
	if arr is Array and arr.size() >= 3:
		return Color(float(arr[0]), float(arr[1]), float(arr[2]),
				float(arr[3]) if arr.size() > 3 else 1.0)
	return Color.WHITE
