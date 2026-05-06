extends Node3D

## WarpDrive test scene. Extends SolarSystemTest with warp-specific HUD and
## manual warp controls.
##
## Controls (in addition to SolarSystemTest):
##   Y                  — hold to charge/initiate manual warp
##   Right-click (high zoom) — plot warp destination

@export var galaxy_seed: int = 8675309
@export var start_system_id: String = "sys_00000"
@export var ship_class_id: String = "axum-fighter-1"
@export var ship_variant_id: String = "axum_fighter_interceptor"

@onready var _camera: Camera3D = $TopCamera
@onready var _stats_label: Label = $DebugOverlay/Panel/Stats

var _solar_system: SolarSystem = null
var _player_ship: Node3D = null
var _perf: Node = null

var _archetype_cfg: Dictionary = {}
var _system_index: int = 0
var _forced_archetype: String = ""
var _archetypes_cycle: Array[String] = ["", "barren", "inhabited",
	"industrial", "frontier", "anomaly"]
var _archetype_cycle_idx: int = 0

var _cam_target   := Vector3.ZERO
var _cam_height   := 25000.0
var _pan_speed    := 500.0
var _orbit_yaw    := 0.0
var _orbit_pitch  := -PI / 2.0
var _top_down     := true


func _ready() -> void:
	var sl := Engine.get_singleton("ServiceLocator")
	if sl:
		_perf = sl.GetService("PerformanceMonitor")

	_archetype_cfg = _load_archetypes()
	if _archetype_cfg.is_empty():
		push_error("WarpDriveTest: cannot load solar_system_archetypes.json")
		return

	_rebuild_system()
	_try_spawn_ship()
	_spawn_play_plane()
	_update_camera()


func _spawn_play_plane() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "PlayPlane"

	var plane := PlaneMesh.new()
	plane.size = Vector2(220000.0, 220000.0)
	plane.subdivide_width = 0
	plane.subdivide_depth = 0
	mi.mesh = plane

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.3, 0.6, 1.0, 0.08)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	mi.material_override = mat
	mi.position = Vector3.ZERO
	add_child(mi)


func _load_archetypes() -> Dictionary:
	var file := FileAccess.open("res://data/solar_system_archetypes.json", FileAccess.READ)
	if not file:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		return {}
	file.close()
	return json.data


func _rebuild_system() -> void:
	if _solar_system != null:
		_solar_system.queue_free()
		_solar_system = null

	var cfg := _archetype_cfg.duplicate(true)

	if _forced_archetype != "":
		var archs: Dictionary = cfg.get("archetypes", {})
		for key in archs:
			archs[key]["weight"] = 1.0 if key == _forced_archetype else 0.0

	var system_id := "sys_%05d" % _system_index

	_solar_system = SolarSystem.new()
	_solar_system.name = "SolarSystem"
	add_child(_solar_system)
	_solar_system.load_system(system_id, galaxy_seed, cfg)


func _try_spawn_ship() -> void:
	var sl := Engine.get_singleton("ServiceLocator")
	if sl == null:
		return
	var factory = sl.GetService("ShipFactory")
	if factory == null:
		factory = ShipFactory.new()
		factory.name = "ShipFactory"
		add_child(factory)
	_player_ship = factory.spawn_ship(
		ship_class_id, ship_variant_id,
		Vector3(5000.0, 0.0, 0.0),
		"player", true)
	# ShipFactory already adds ship to scene tree via root.add_child.call_deferred
	# Do NOT add it again here


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_cam_height = maxf(_cam_height * 0.85, 800.0)
				_update_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				_cam_height = minf(_cam_height * 1.18, 200000.0)
				_update_camera()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_R:
				galaxy_seed += 1
				_rebuild_system()
				_try_spawn_ship()
			KEY_N:
				_system_index += 1
				_rebuild_system()
				_try_spawn_ship()
			KEY_B:
				_archetype_cycle_idx = (_archetype_cycle_idx + 1) % _archetypes_cycle.size()
				_forced_archetype = _archetypes_cycle[_archetype_cycle_idx]
				_rebuild_system()
				_try_spawn_ship()
			KEY_SPACE:
				_top_down = not _top_down
				if _top_down:
					_orbit_pitch = -PI / 2.0
					_orbit_yaw = 0.0
				else:
					_orbit_pitch = -PI / 4.0
				_update_camera()


func _process(delta: float) -> void:
	_handle_pan(delta)
	_update_overlay()


func _handle_pan(delta: float) -> void:
	var speed := _pan_speed * (_cam_height / 10000.0)
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= 4.0
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):    move.z -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):  move.z += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):  move.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): move.x += 1.0
	if move != Vector3.ZERO:
		_cam_target += move.normalized() * speed * delta
		_update_camera()


func _update_camera() -> void:
	var dir := Vector3(
		cos(_orbit_pitch) * sin(_orbit_yaw),
		sin(-_orbit_pitch),
		cos(_orbit_pitch) * cos(_orbit_yaw))
	_camera.global_position = _cam_target + dir * _cam_height
	_camera.look_at(_cam_target, Vector3.UP)


func _update_overlay() -> void:
	if _solar_system == null or _stats_label == null:
		return

	var manifest := _solar_system.get_manifest()
	var fps      := int(Engine.get_frames_per_second())
	var archtype := _solar_system.archetype
	var sys_id   := _solar_system.system_id
	var n_stars: int  = (manifest.get("stars", []) as Array).size()
	var n_planets: int = _solar_system._planets.size()
	var n_belts: int  = _solar_system._belt_regions.size()

	var gen_ms := 0.0
	var planet_count := 0
	if _perf:
		gen_ms       = float(_perf.get_avg_ms("SolarSystem.generate"))
		planet_count = int(_perf.get_count("SolarSystem.planet_count"))

	var warp_status := ""
	if _player_ship != null:
		var warp := _player_ship.get_node_or_null("WarpDrive") as WarpDrive
		if warp != null and warp.is_warp_active():
			warp_status = " | WARP: %s (%.0f%%)" % [warp.get_state_name(), warp.get_charge_ratio() * 100.0]

	var arch_label := ("forced: %s" % _forced_archetype) \
		if _forced_archetype != "" else "random"
	var seed_label := "seed: %d" % galaxy_seed

	_stats_label.text = (
		"FPS: %d  |  %s  |  %s\n" % [fps, seed_label, arch_label]
		+ "system: %s  |  archetype: %s  |  stars: %d\n" % [sys_id, archtype, n_stars]
		+ "planets: %d  |  belts: %d%s\n" % [n_planets, n_belts, warp_status]
		+ "SolarSystem.generate: %.2f ms\n" % gen_ms
		+ "---\n"
		+ "WASD=pan  Wheel=zoom  Shift=fast\n"
		+ "R=new seed  N=next system  B=cycle archetype  Space=toggle view\n"
		+ "Y=manual warp  Right-click (high zoom)=plot warp"
	)
