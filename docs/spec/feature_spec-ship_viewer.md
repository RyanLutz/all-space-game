# Ship Viewer — Feature Spec

---

## 1. Overview

The Ship Viewer is a standalone developer tool scene for visually inspecting and tuning
all ships in the game. It loads ship definitions dynamically from the content folder,
displays them in a 3D orbit viewer, and exposes controls for live color tuning, weapon
firing, and damage particle preview.

**Design goals:**
- Fast iteration on ship visuals without entering gameplay
- Drive the vertex color material system design
- Test weapon VFX in isolation from gameplay systems
- Test damage particle effects at discrete severity levels
- Serve as the canonical reference for how ships look in-engine

**Non-goals:**
- No stats panel or DPS readout
- No target dummy or hit detection
- No mesh deformation or component degradation
- No player-facing loadout UI (this is a dev tool)

---

## 2. Architecture

The viewer is a self-contained scene (`ShipViewer.tscn`) with no dependency on
`GameEventBus`, `GameBootstrap`, or any gameplay systems. It is not loaded by the
main game — it is launched directly in the editor for dev use.

It has three logical layers:

```
ShipViewer.tscn
├── ViewerCamera         — Camera3D, orbit controller
├── ShipStage            — Node3D, ship is instantiated here
├── ViewerUI             — CanvasLayer
│   ├── ShipGrid         — scrollable thumbnail grid
│   └── ControlPanel     — color pickers, damage slider, fire button
└── ViewerController.gd  — top-level coordinator
```

The `ViewerController` owns all state. The UI panels emit signals upward; the
controller responds and updates the ship instance.

---

## 3. Core Properties / Data Model

### ViewerController state

```gdscript
var loaded_ship_defs: Array[Dictionary] = []   # all ship.json definitions
var current_ship_node: Node3D = null           # instantiated ship in stage
var current_ship_def: Dictionary = {}          # active ship's JSON definition

var color_base: Color = Color.WHITE
var color_accent: Color = Color.GRAY
var color_glow: Color = Color(0.0, 0.5, 1.0)  # blue default
var color_window: Color = Color(0.8, 0.9, 1.0)

var damage_level: float = 0.0  # 0.0 = pristine, 1.0 = critical
```

### Vertex Color Channel Contract

All ship meshes must paint vertex color channels as follows:

| Channel | Semantic     | Shader parameter  |
|---------|--------------|-------------------|
| R       | Base hull    | `color_base`      |
| G       | Accent       | `color_accent`    |
| B       | Glow         | `color_glow`      |
| A       | Window       | `color_window`    |

Channels are continuous (0.0–1.0). Blended regions are intentional and encouraged
for organic transitions. A vertex may contribute to multiple color zones simultaneously.

---

## 4. Key Algorithms

### 4.1 Ship Discovery

On `_ready`, the controller scans the content folder for all ship definitions:

```gdscript
func _discover_ships() -> void:
    var dir = DirAccess.open("res://content/ships/")
    if not dir:
        return
    dir.list_dir_begin()
    var folder = dir.get_next()
    while folder != "":
        var json_path = "res://content/ships/%s/ship.json" % folder
        if FileAccess.file_exists(json_path):
            var def = _load_json(json_path)
            if def:
                loaded_ship_defs.append(def)
        folder = dir.get_next()
    loaded_ship_defs.sort_custom(func(a, b): return a.name < b.name)
```

### 4.2 Ship Loading

When a ship is selected from the grid:

```gdscript
func _load_ship(def: Dictionary) -> void:
    if current_ship_node:
        current_ship_node.queue_free()
        current_ship_node = null
    current_ship_def = def
    var scene: PackedScene = load(def.scene_path)
    current_ship_node = scene.instantiate()
    $ShipStage.add_child(current_ship_node)
    current_ship_node.position = Vector3.ZERO
    _apply_colors()
    _apply_damage(damage_level)
```

### 4.3 Vertex Color Material Application

The ship shader exposes four `uniform` color parameters. The controller writes
them directly to the ship's material at runtime:

```gdscript
func _apply_colors() -> void:
    if not current_ship_node:
        return
    var mesh_instances = _collect_mesh_instances(current_ship_node)
    for mi in mesh_instances:
        var mat = mi.get_active_material(0)
        if mat and mat.has_shader_parameter("color_base"):
            mat = mat.duplicate()  # never mutate shared materials
            mat.set_shader_parameter("color_base", color_base)
            mat.set_shader_parameter("color_accent", color_accent)
            mat.set_shader_parameter("color_glow", color_glow)
            mat.set_shader_parameter("color_window", color_window)
            mi.set_surface_override_material(0, mat)
```

**Note:** Materials are always duplicated before mutation so shared materials
across ship instances are never contaminated.

### 4.4 Ship Shader (canonical vertex color blending)

```glsl
shader_type spatial;

uniform vec4 color_base    : source_color = vec4(1.0);
uniform vec4 color_accent  : source_color = vec4(0.5);
uniform vec4 color_glow    : source_color = vec4(0.0, 0.5, 1.0, 1.0);
uniform vec4 color_window  : source_color = vec4(0.8, 0.9, 1.0, 1.0);
uniform sampler2D albedo_texture : source_color, hint_default_white;

void fragment() {
    vec4 albedo = texture(albedo_texture, UV);
    vec3 col = albedo.rgb;
    col = mix(col, color_base.rgb,   COLOR.r);
    col = mix(col, color_accent.rgb, COLOR.g);
    col = mix(col, color_glow.rgb,   COLOR.b);
    col = mix(col, color_window.rgb, COLOR.a);
    ALBEDO = col;
    EMISSION = color_glow.rgb * COLOR.b * 0.6;  // glow zones emit light
}
```

Glow zone vertices also contribute to `EMISSION` so they read as self-lit
in dark environments without needing separate light sources.

### 4.5 Orbit Camera

The camera orbits around `Vector3.ZERO` (ship origin). It never parents itself
to the ship.

```gdscript
var orbit_yaw: float = 0.0
var orbit_pitch: float = 20.0  # degrees, clamped
var orbit_distance: float = 10.0
var is_orbiting: bool = false

func _input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_RIGHT:
            is_orbiting = event.pressed
        if event.button_index == MOUSE_BUTTON_WHEEL_UP:
            orbit_distance = max(2.0, orbit_distance - 1.0)
        if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            orbit_distance = min(40.0, orbit_distance + 1.0)
    if event is InputEventMouseMotion and is_orbiting:
        orbit_yaw   -= event.relative.x * 0.4
        orbit_pitch -= event.relative.y * 0.4
        orbit_pitch  = clamp(orbit_pitch, -80.0, 80.0)

func _update_camera() -> void:
    var yaw_rad   = deg_to_rad(orbit_yaw)
    var pitch_rad = deg_to_rad(orbit_pitch)
    var offset = Vector3(
        cos(pitch_rad) * sin(yaw_rad),
        sin(pitch_rad),
        cos(pitch_rad) * cos(yaw_rad)
    ) * orbit_distance
    $ViewerCamera.position = offset
    $ViewerCamera.look_at(Vector3.ZERO, Vector3.UP)
```

Right-mouse drag to orbit. Scroll wheel to zoom. No keyboard input required.

### 4.6 Damage Particle Preview

The ship scene is expected to contain a `DamageEmitters` node (Node3D) with
named child `GPUParticles3D` nodes: `SparkLight`, `SparkHeavy`, `SmokeLight`,
`SmokeHeavy`. The controller drives their emission rates based on `damage_level`:

```gdscript
func _apply_damage(level: float) -> void:
    damage_level = level
    if not current_ship_node:
        return
    var emitters = current_ship_node.get_node_or_null("DamageEmitters")
    if not emitters:
        return
    # Sparks start at 25% damage; smoke at 50%; heavy variants ramp after 75%
    _set_emitter(emitters, "SparkLight",  remap(level, 0.25, 0.75, 0.0, 1.0))
    _set_emitter(emitters, "SparkHeavy",  remap(level, 0.75, 1.0,  0.0, 1.0))
    _set_emitter(emitters, "SmokeLight",  remap(level, 0.5,  0.9,  0.0, 1.0))
    _set_emitter(emitters, "SmokeHeavy",  remap(level, 0.75, 1.0,  0.0, 1.0))

func _set_emitter(parent: Node3D, name: String, amount: float) -> void:
    var node = parent.get_node_or_null(name)
    if node is GPUParticles3D:
        node.emitting = amount > 0.0
        node.amount_ratio = clamp(amount, 0.0, 1.0)
```

### 4.7 Weapon Firing

The controller calls the ship's weapon system directly since this is a dev tool
with no AI or player input system. Weapons fire at `Vector3.ZERO + ship.forward * 100.0`
as an aim target (straight ahead):

```gdscript
func _fire_weapons() -> void:
    if not current_ship_node:
        return
    var aim_target = current_ship_node.global_position \
        + (-current_ship_node.transform.basis.z * 100.0)
    # Assumes WeaponSystem exposes fire_all(aim_target: Vector3)
    var weapon_system = current_ship_node.get_node_or_null("WeaponSystem")
    if weapon_system and weapon_system.has_method("fire_all"):
        weapon_system.fire_all(aim_target)
```

If `WeaponSystem` does not yet exist, the fire button is disabled with a
"WeaponSystem not found" tooltip.

---

## 5. JSON Data Format

The viewer reads existing `ship.json` files — it does not own or modify any
data files. The only field it requires beyond what the ship system already
defines is `scene_path`:

```json
{
  "id": "viper_mk1",
  "name": "Viper Mk I",
  "scene_path": "res://content/ships/viper_mk1/viper_mk1.tscn",
  "thumbnail": "res://content/ships/viper_mk1/thumbnail.png"
}
```

`thumbnail` is optional. If absent, the grid shows a placeholder icon.

---

## 6. Performance Instrumentation

The viewer is a dev tool and is never profiled in production. Minimal
instrumentation is sufficient:

```gdscript
PerformanceMonitor.begin("ShipViewer.load_ship")
# ... instantiate and configure ship ...
PerformanceMonitor.end("ShipViewer.load_ship")
```

This surfaces load time per ship so slow-loading ships can be identified
and optimized before gameplay integration.

---

## 7. Files

| Path | Purpose |
|------|---------|
| `scenes/tools/ShipViewer.tscn` | Root scene — launch directly in editor |
| `scenes/tools/ShipViewer.gd` | ViewerController — top-level coordinator |
| `scenes/tools/ui/ShipGrid.tscn` | Scrollable thumbnail grid panel |
| `scenes/tools/ui/ShipGrid.gd` | Grid population and click signals |
| `scenes/tools/ui/ControlPanel.tscn` | Color pickers, damage slider, fire button |
| `scenes/tools/ui/ControlPanel.gd` | Emits color_changed, damage_changed, fire_pressed |
| `scenes/tools/ViewerCamera.gd` | Orbit camera controller |
| `shaders/ship_vertex_color.gdshader` | Canonical ship material shader |

---

## 8. Dependencies

| Dependency | Status | Notes |
|------------|--------|-------|
| At least one `ship.json` with `scene_path` | Required | Viewer has nothing to load otherwise |
| Ship `.tscn` with a `MeshInstance3D` using `ship_vertex_color.gdshader` | Required | Color controls have no effect otherwise |
| `DamageEmitters` node in ship scene | Optional | Damage slider silently does nothing if absent |
| `WeaponSystem` node in ship scene | Optional | Fire button disabled if absent |
| `PerformanceMonitor` | Required | Must be autoloaded |

---

## 9. Assumptions

- Vertex colors are painted in Blender and baked into the exported mesh.
  The viewer does not provide tools for painting or editing vertex colors.
- All ship scenes share the same `ship_vertex_color.gdshader`. Ships using
  a different shader will not respond to color controls.
- Orbit controls use right-mouse-drag. This is a dev tool; no rebinding needed.
- Damage emitter node names (`SparkLight`, `SparkHeavy`, `SmokeLight`, `SmokeHeavy`)
  are a contract between this spec and the VFX spec. If those names change,
  both specs must be updated together.
- Thumbnail images are 256×256 PNG. Larger images are scaled down by the UI.

---

## 10. Success Criteria

- [ ] Viewer scene launches standalone without autoloads other than PerformanceMonitor
- [ ] All ships discovered dynamically from `res://content/ships/` at startup
- [ ] Clicking a thumbnail loads that ship into the 3D stage within one second
- [ ] Right-mouse drag orbits camera smoothly around ship origin
- [ ] Scroll wheel zooms in and out without camera gimbal lock
- [ ] All four color pickers update ship material in real time with no perceptible lag
- [ ] Material duplication confirmed: changing colors in viewer does not affect
      colors when ship is loaded in gameplay scene
- [ ] Damage slider at 0.0 produces no particle emission
- [ ] Damage slider at 1.0 produces all four emitter types at full rate
- [ ] Intermediate slider values produce proportionally scaled emission rates
- [ ] Fire button triggers weapon VFX when WeaponSystem is present
- [ ] Fire button is visibly disabled (greyed out) when WeaponSystem is absent
- [ ] PerformanceMonitor records `ShipViewer.load_ship` timing for every ship load
- [ ] No gameplay systems (GameEventBus, AI, physics) are required or referenced
