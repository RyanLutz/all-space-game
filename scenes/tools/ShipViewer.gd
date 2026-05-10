extends Node3D

var loaded_ship_defs: Array[Dictionary] = []
var current_ship_node: Node3D = null
var current_ship_def: Dictionary = {}

var color_base: Color = Color.WHITE
var color_accent: Color = Color.GRAY
var color_glow: Color = Color(0.0, 0.5, 1.0)
var color_window: Color = Color(0.8, 0.9, 1.0)

var damage_level: float = 0.0
var ship_rotation: Vector3 = Vector3(deg_to_rad(-90.0), 0.0, 0.0)

var _perf: Node = null

@onready var _ship_stage: Node3D = $ShipStage
@onready var _ship_pivot: Node3D = $ShipStage/ShipPivot
@onready var _viewer_camera: Camera3D = $ViewerCamera
@onready var _ship_grid: Control = $ViewerUI/ShipGrid
@onready var _ship_grid_toggle: Button = $ViewerUI/ShipGridToggle
@onready var _control_panel: Control = $ViewerUI/ControlPanel

func _ready() -> void:
    var service_locator := Engine.get_singleton("ServiceLocator")
    if service_locator:
        _perf = service_locator.GetService("PerformanceMonitor")

    _ship_grid_toggle.pressed.connect(_toggle_ship_grid)

    _discover_ships()
    _ship_grid.populate(loaded_ship_defs)
    _ship_grid.ship_selected.connect(_on_ship_selected)
    _control_panel.color_changed.connect(_on_color_changed)
    _control_panel.damage_changed.connect(_on_damage_changed)
    _control_panel.rotation_changed.connect(_on_rotation_changed)
    _control_panel.fire_pressed.connect(_on_fire_pressed)

    if not loaded_ship_defs.is_empty():
        _load_ship(loaded_ship_defs[0])

func _toggle_ship_grid() -> void:
    _ship_grid.visible = not _ship_grid.visible
    _ship_grid_toggle.text = ">" if _ship_grid.visible else "<"

func _discover_ships() -> void:
    var dir := DirAccess.open("res://content/ships/")
    if not dir:
        return
    dir.list_dir_begin()
    var folder := dir.get_next()
    while folder != "":
        if dir.current_is_dir() and not folder.begins_with("."):
            var json_path := "res://content/ships/%s/ship.json" % folder
            if FileAccess.file_exists(json_path):
                var def := _load_json(json_path)
                if def:
                    if not def.has("scene_path"):
                        var candidate := _find_ship_scene("res://content/ships/%s/" % folder)
                        if candidate != "":
                            def["scene_path"] = candidate
                    var scene_path: String = def.get("scene_path", "")
                    if scene_path == "" or not ResourceLoader.exists(scene_path):
                        push_warning("ShipViewer: skipping ship '%s' — no scene file found" % def.get("name", folder))
                        folder = dir.get_next()
                        continue
                    if not def.has("name"):
                        def["name"] = def.get("display_name", folder)
                    if not def.has("thumbnail"):
                        var thumb_path := "res://content/ships/%s/thumbnail.png" % folder
                        if FileAccess.file_exists(thumb_path):
                            def["thumbnail"] = thumb_path
                    loaded_ship_defs.append(def)
        folder = dir.get_next()
    loaded_ship_defs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return a.get("name", "") < b.get("name", "")
    )

func _find_ship_scene(folder_path: String) -> String:
    var d := DirAccess.open(folder_path)
    if not d:
        return ""
    d.list_dir_begin()
    var file := d.get_next()
    var tscn_path := ""
    var parts_glb := ""
    var folder_match_glb := ""
    var first_glb := ""
    var folder_name := folder_path.get_file().to_lower()
    while file != "":
        if not d.current_is_dir():
            var lower := file.to_lower()
            if lower.ends_with(".tscn"):
                tscn_path = folder_path.path_join(file)
            elif lower.ends_with(".glb") or lower.ends_with(".gltf"):
                if lower == "parts.glb":
                    parts_glb = folder_path.path_join(file)
                elif lower.begins_with(folder_name):
                    folder_match_glb = folder_path.path_join(file)
                elif first_glb == "":
                    first_glb = folder_path.path_join(file)
        file = d.get_next()
    d.list_dir_end()
    # Prefer: tscn > parts.glb > folder-matched glb > first glb
    if tscn_path != "":
        return tscn_path
    if parts_glb != "":
        return parts_glb
    if folder_match_glb != "":
        return folder_match_glb
    return first_glb

func _load_json(path: String) -> Dictionary:
    var file := FileAccess.open(path, FileAccess.READ)
    if not file:
        return {}
    var text := file.get_as_text()
    file.close()
    var json := JSON.new()
    var err := json.parse(text)
    if err != OK:
        push_error("JSON parse error in %s: %s" % [path, json.get_error_message()])
        return {}
    var result = json.data
    if result is Dictionary:
        return result
    return {}

func _on_ship_selected(def: Dictionary) -> void:
    _load_ship(def)

func _load_ship(def: Dictionary) -> void:
    if _perf:
        _perf.begin("ShipViewer.load_ship")

    if current_ship_node:
        current_ship_node.queue_free()
        current_ship_node = null
    current_ship_def = def

    var scene_path: String = def.get("scene_path", "")
    if scene_path == "" or not ResourceLoader.exists(scene_path):
        push_warning("ShipViewer: scene not found for ship '%s' at path '%s'" % [def.get("name", "?"), scene_path])
        if _perf:
            _perf.end("ShipViewer.load_ship")
        _control_panel.set_fire_enabled(false)
        return

    var scene: PackedScene = load(scene_path)
    if not scene:
        push_warning("ShipViewer: failed to load scene for ship '%s'" % def.get("name", "?"))
        if _perf:
            _perf.end("ShipViewer.load_ship")
        _control_panel.set_fire_enabled(false)
        return

    current_ship_node = scene.instantiate()
    _ship_pivot.add_child(current_ship_node)
    current_ship_node.position = Vector3.ZERO
    current_ship_node.rotation = Vector3.ZERO
    _ship_pivot.rotation = ship_rotation

    _viewer_camera.reset_orbit()
    _apply_colors()
    _apply_damage(damage_level)
    _update_fire_button()

    if _perf:
        _perf.end("ShipViewer.load_ship")

func _collect_mesh_instances(node: Node) -> Array[MeshInstance3D]:
    var result: Array[MeshInstance3D] = []
    if node is MeshInstance3D:
        result.append(node)
    for child in node.get_children():
        result.append_array(_collect_mesh_instances(child))
    return result

const SHIP_SHADER := preload("res://shaders/ship_vertex_color.gdshader")

func _apply_colors() -> void:
    if not current_ship_node:
        return
    var mesh_instances := _collect_mesh_instances(current_ship_node)
    for mi in mesh_instances:
        var mat := mi.get_active_material(0)
        if not mat:
            continue

        var dup: ShaderMaterial = null
        var uses_canonical := true

        if mat is ShaderMaterial and mat.shader != null:
            var sm := mat as ShaderMaterial
            dup = sm.duplicate()
            uses_canonical = _shader_has_param(sm.shader, "color_base")
        elif mat is StandardMaterial3D:
            dup = _convert_standard_material(mat as StandardMaterial3D)

        if dup:
            if uses_canonical:
                dup.set_shader_parameter("color_base", color_base)
                dup.set_shader_parameter("color_accent", color_accent)
                dup.set_shader_parameter("color_glow", color_glow)
                dup.set_shader_parameter("color_window", color_window)
            else:
                dup.set_shader_parameter("color_primary", color_base)
                dup.set_shader_parameter("color_trim", color_accent)
                dup.set_shader_parameter("color_accent", color_glow)
                dup.set_shader_parameter("color_glow", color_window)
            mi.set_surface_override_material(0, dup)

func _shader_has_param(shader: Shader, param_name: String) -> bool:
    if not shader:
        return false
    var code: String = shader.code if shader.code else ""
    return code.find('"' + param_name + '"') != -1 or code.find(param_name + " :") != -1 or code.find(param_name + ";") != -1

func _convert_standard_material(std: StandardMaterial3D) -> ShaderMaterial:
    var sm := ShaderMaterial.new()
    sm.shader = SHIP_SHADER
    var tex := std.albedo_texture
    if tex:
        sm.set_shader_parameter("albedo_texture", tex)
    sm.set_shader_parameter("roughness", std.roughness)
    sm.set_shader_parameter("metallic", std.metallic)
    return sm

func _on_color_changed(channel: String, color: Color) -> void:
    match channel:
        "base":   color_base = color
        "accent": color_accent = color
        "glow":   color_glow = color
        "window": color_window = color
    _apply_colors()

func _on_damage_changed(level: float) -> void:
    _apply_damage(level)

func _on_rotation_changed(axis: String, value: float) -> void:
    match axis:
        "x": ship_rotation.x = deg_to_rad(value)
        "y": ship_rotation.y = deg_to_rad(value)
        "z": ship_rotation.z = deg_to_rad(value)
    if _ship_pivot:
        _ship_pivot.rotation = ship_rotation

func _apply_damage(level: float) -> void:
    damage_level = level
    if not current_ship_node:
        return
    var emitters := current_ship_node.get_node_or_null("DamageEmitters")
    if not emitters:
        return
    _set_emitter(emitters, "SparkLight", remap(level, 0.25, 0.75, 0.0, 1.0))
    _set_emitter(emitters, "SparkHeavy", remap(level, 0.75, 1.0,  0.0, 1.0))
    _set_emitter(emitters, "SmokeLight", remap(level, 0.5,  0.9,  0.0, 1.0))
    _set_emitter(emitters, "SmokeHeavy", remap(level, 0.75, 1.0,  0.0, 1.0))

func _set_emitter(parent: Node3D, name: String, amount: float) -> void:
    var node := parent.get_node_or_null(name)
    if node is GPUParticles3D:
        node.emitting = amount > 0.0
        node.amount_ratio = clampf(amount, 0.0, 1.0)

func _update_fire_button() -> void:
    if not current_ship_node:
        _control_panel.set_fire_enabled(false)
        return
    var ws := current_ship_node.get_node_or_null("WeaponSystem")
    _control_panel.set_fire_enabled(ws != null and ws.has_method("fire_all"))

func _on_fire_pressed() -> void:
    _fire_weapons()

func _fire_weapons() -> void:
    if not current_ship_node:
        return
    var aim_target := _ship_pivot.global_position + (-_ship_pivot.global_transform.basis.z * 100.0)
    var weapon_system := current_ship_node.get_node_or_null("WeaponSystem")
    if weapon_system and weapon_system.has_method("fire_all"):
        weapon_system.fire_all(aim_target)

func _input(event: InputEvent) -> void:
    if event is InputEventMouseButton or event is InputEventMouseMotion:
        var hovered := get_viewport().gui_get_hovered_control()
        if hovered != null:
            return
