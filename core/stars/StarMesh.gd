extends Node3D
class_name StarMesh

## LOD 2 close-range star representation.
##
## Spawned by StarRegistry._spawn_mesh() when a destination star comes within
## lod2_spawn_distance. Configures three SphereMesh-based MeshInstance3D layers
## (core + two atmospheres) with the shared star_surface shader at different
## scales / flow rates, an additive corona billboard with star_corona shader,
## a fully-configured OmniLight3D that visibly lights nearby ships, and an
## ExclusionArea (Area3D + SphereShape3D) that emits
## GameEventBus.star_exclusion_entered(star_id, ship_id) on breach.
##
## All visual tunables come from `data/world_config.json` -> `galaxy.star_mesh`,
## resolved by StarRegistry once at startup and passed in via configure().
## Backdrop stars NEVER instantiate this scene — see _update_lod() guard.

# ─── Scene wiring ────────────────────────────────────────────────────────────
@onready var _core:           MeshInstance3D = $Core
@onready var _atmo_inner:     MeshInstance3D = $AtmosphereInner
@onready var _atmo_outer:     MeshInstance3D = $AtmosphereOuter
@onready var _corona:         MeshInstance3D = $Corona
@onready var _light:          OmniLight3D    = $StarLight
@onready var _exclusion_area: Area3D         = $ExclusionArea
@onready var _exclusion_shape: CollisionShape3D = $ExclusionArea/Shape

# ─── Runtime state ───────────────────────────────────────────────────────────
var _record: StarRecord = null
var _star_id: int = -1
var _event_bus: Node = null


## Configure the freshly-instantiated StarMesh from a StarRecord and the
## resolved star_mesh tunable block. Called by StarRegistry._spawn_mesh()
## immediately after add_child(). Must be safe to call exactly once per
## node lifetime — there is no reconfigure path; LOD changes despawn and
## re-spawn.
func configure(record: StarRecord, mesh_cfg: Dictionary) -> void:
	_record  = record
	_star_id = record.id

	var sl := Engine.get_singleton("ServiceLocator")
	if sl:
		_event_bus = sl.GetService("GameEventBus")

	global_position = record.position

	_configure_layers(record, mesh_cfg)
	_configure_corona(record, mesh_cfg)
	_configure_light(record, mesh_cfg)
	_configure_exclusion(record)


# ─── Layer configuration ─────────────────────────────────────────────────────

func _configure_layers(record: StarRecord, cfg: Dictionary) -> void:
	# Core: opaque base body — alpha 1, slow rotation, baseline noise scale.
	_apply_surface_material(_core, record, cfg, {
		"scale_key":        "core_radius_scale",
		"scale_default":    1.0,
		"alpha":            1.0,
		"flow_speed_mult":  1.0,
		"rotation_speed":   0.02,
		"noise_scale_mult": 1.0,
	})

	# Inner atmosphere: translucent, faster flow, slightly larger.
	_apply_surface_material(_atmo_inner, record, cfg, {
		"scale_key":        "atmosphere_inner_scale",
		"scale_default":    1.04,
		"alpha":            float(cfg.get("atmosphere_inner_alpha", 0.55)),
		"flow_speed_mult":  float(cfg.get("atmosphere_inner_speed", 0.08)) \
		                  / maxf(float(cfg.get("surface_flow_speed", 0.05)), 0.0001),
		"rotation_speed":   0.05,
		"noise_scale_mult": 0.7,
	})

	# Outer atmosphere: more diffuse, counter-rotated, broader noise.
	_apply_surface_material(_atmo_outer, record, cfg, {
		"scale_key":        "atmosphere_outer_scale",
		"scale_default":    1.10,
		"alpha":            float(cfg.get("atmosphere_outer_alpha", 0.30)),
		"flow_speed_mult":  float(cfg.get("atmosphere_outer_speed", 0.03)) \
		                  / maxf(float(cfg.get("surface_flow_speed", 0.05)), 0.0001),
		"rotation_speed":  -0.03,
		"noise_scale_mult": 0.45,
	})


## Sphere radius is set on the SphereMesh.radius / height (not on the parent
## scale) so the mesh's own bounding box stays correct for frustum culling.
## Each layer instances the source SphereMesh so per-layer scaling does not
## bleed across; same pattern for the ShaderMaterial which is duplicated so
## per-layer parameter changes don't stomp each other.
func _apply_surface_material(
		mi: MeshInstance3D, record: StarRecord, cfg: Dictionary, params: Dictionary) -> void:

	var sphere := (mi.mesh as SphereMesh).duplicate() as SphereMesh
	var layer_scale: float = float(cfg.get(params["scale_key"], params["scale_default"]))
	sphere.radius = record.radius * layer_scale
	sphere.height = sphere.radius * 2.0
	mi.mesh = sphere

	var mat := (mi.get_surface_override_material(0) as ShaderMaterial).duplicate() as ShaderMaterial
	mat.set_shader_parameter("base_color",     Vector3(record.color.r, record.color.g, record.color.b))
	mat.set_shader_parameter("layer_alpha",    float(params["alpha"]))
	mat.set_shader_parameter("noise_scale",
		float(cfg.get("surface_noise_scale", 2.5)) * float(params["noise_scale_mult"]))
	mat.set_shader_parameter("flow_speed",
		float(cfg.get("surface_flow_speed",  0.05)) * float(params["flow_speed_mult"]))
	mat.set_shader_parameter("rotation_speed", float(params["rotation_speed"]))
	mat.set_shader_parameter("brightness",     float(cfg.get("surface_brightness", 1.4)))
	mat.set_shader_parameter("contrast",       float(cfg.get("surface_contrast",   1.6)))
	mi.set_surface_override_material(0, mat)


# ─── Corona ──────────────────────────────────────────────────────────────────

func _configure_corona(record: StarRecord, cfg: Dictionary) -> void:
	# QuadMesh size is set in world units; corona_scale × radius covers
	# the desired halo footprint. Quad is camera-facing per the corona
	# shader's billboard vertex stage.
	var quad := (_corona.mesh as QuadMesh).duplicate() as QuadMesh
	var corona_scale: float = float(cfg.get("corona_scale", 3.5))
	var size: float = record.radius * corona_scale * 2.0
	quad.size = Vector2(size, size)
	_corona.mesh = quad

	var mat := (_corona.get_surface_override_material(0) as ShaderMaterial).duplicate() as ShaderMaterial
	mat.set_shader_parameter("base_color",     Vector3(record.color.r, record.color.g, record.color.b))
	mat.set_shader_parameter("intensity",      float(cfg.get("corona_intensity",     1.8)))
	mat.set_shader_parameter("inner_falloff",  float(cfg.get("corona_inner_falloff", 0.18)))
	mat.set_shader_parameter("outer_falloff",  float(cfg.get("corona_outer_falloff", 1.0)))
	_corona.set_surface_override_material(0, mat)


# ─── Light ───────────────────────────────────────────────────────────────────

func _configure_light(record: StarRecord, cfg: Dictionary) -> void:
	_light.light_color  = record.color
	_light.light_energy = record.light_energy
	_light.omni_range   = record.light_range
	_light.omni_attenuation = float(cfg.get("light_attenuation", 1.0))
	_light.shadow_enabled = false   # cosmetic light; shadow cost not justified


# ─── Exclusion ───────────────────────────────────────────────────────────────

## Phase 4: ExclusionArea live — SphereShape3D sized to exclusion_radius, monitoring
## enabled, collision_mask set to detect ships (layer 1). Signal body_entered
## connected to _on_exclusion_body_entered, which checks for Ship type and emits
## GameEventBus.star_exclusion_entered(star_id, ship_id).
## Backdrop stars never instantiate StarMesh, so this area is always on a
## destination star.
## NOTE — boundary-force integration point for physics/nav: those specs must
## listen to star_exclusion_entered and apply a repulsion force. Deferred
## to the physics/nav spec owners; this emitter is complete.
func _configure_exclusion(record: StarRecord) -> void:
	var shape := SphereShape3D.new()
	shape.radius = record.exclusion_radius
	_exclusion_shape.shape = shape

	# Bit 0 (layer 1) is the default collision layer for RigidBody3D ships.
	# The Area3D needs this mask to receive body_entered from ships.
	_exclusion_area.collision_mask = 1
	_exclusion_area.collision_layer = 0   # Area doesn't need to be hit-testable itself.
	_exclusion_area.monitoring  = true
	_exclusion_area.monitorable = false   # Other areas don't need to detect this one.

	_exclusion_area.body_entered.connect(_on_exclusion_body_entered)


func _on_exclusion_body_entered(body: Node3D) -> void:
	# Filter to ships only — asteroids, debris, and other physics bodies share
	# the same collision layer. The Ship class_name check is the canonical guard.
	if not body is Ship:
		return
	if _event_bus == null:
		push_warning("[StarMesh] star_exclusion_entered: event_bus not resolved (star %d)" % _star_id)
		return
	_event_bus.star_exclusion_entered.emit(_star_id, body.get_instance_id())


# ─── Public ──────────────────────────────────────────────────────────────────

func get_star_id() -> int:
	return _star_id
