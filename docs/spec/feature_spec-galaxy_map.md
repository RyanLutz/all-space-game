# Feature Spec — Galaxy Map
*All Space — Camera-Attached Galaxy, Seamless Scale Transition, Free Flight Navigation*

**Status:** Implemented (SDF close-star shader in progress)
**Supersedes:** The galactic map described in `feature_spec-star_field_2.md` §Galactic Map.
That section describes a 2D canvas SubViewport implementation that has been replaced
entirely by this architecture.

---

## 1. Overview

The galaxy is a physical object permanently attached to `GameCamera` in the solar system
scene. It is a scaled-down representation of the full star catalog — a
`MultiMeshInstance3D` containing all 80,400 catalog stars at their correct relative
positions, divided by `galaxy_scale`. Because it is a child of `GameCamera`, it moves
with the camera everywhere. The player is always inside the galaxy. It is always
rendering behind the solar system geometry.

When the player presses M, the camera detaches from the ship and enters free-flight
mode. The player flies the camera outward through the galaxy. The solar system geometry
recedes. The galaxy surrounds the camera at every scale because it always has. There is
no SubViewport, no overlay scene, no hard cut, and no separate coordinate system. It is
one continuous 3D scene.

**What this system is not:**
- Not a 2D canvas map
- Not a SubViewport overlay
- Not a separate scene
- Not a fake background — the stars have real 3D positions in scaled galaxy space

**Design goals:**
- Seamless continuous zoom from ship cockpit to full galaxy view and back
- Galaxy feels correct from inside at any scale — you are inside it
- Single tunable value (`galaxy_scale`) controls how large the galaxy feels
- MultiMesh populated once on galaxy map open — never rebuilt during flight
- Technically correct first, visually polished later

---

## 2. Architecture

```
Main.tscn
├── GameOrchestrator
├── World (Node3D)
│   ├── SolarSystem (instantiated at runtime)
│   └── ChunkStreamer
├── GameCamera (Camera3D — GameCamera.gd)
│   ├── GalaxyContainer (Node3D — GalaxyContainer.gd)
│   │   ├── BillboardField (MultiMeshInstance3D — GalaxyBillboardField.gd)
│   │   ├── ProceduralField (MeshInstance3D — large sphere)
│   │   │   └── galaxy_map_field.gdshader
│   │   └── StarContainer (Node3D)
│   │       └── [GalaxyStar nodes — SDF close tier, galaxy map mode only]
│   └── [existing camera children unchanged]
└── UILayer (CanvasLayer)
    ├── PilotHUD
    ├── ModeSwitch
    └── GalaxyMapUI (CanvasLayer, layer 10)
        ├── SelectionIndicator (Control)
        └── HUDHints (Label)
```

### GalaxyContainer position

`GalaxyContainer.position = Vector3.ZERO` relative to `GameCamera`. It inherits the
camera's world transform. All star positions inside it are expressed in **local scaled
galaxy space** — relative to the camera, not to the world origin.

A star at galaxy position `(50000, 400, 80000)` with `galaxy_scale = 100` sits at
local position `(500, 4, 800)` within `GalaxyContainer`. When the camera moves in
world space, `GalaxyContainer` moves with it and all stars maintain their correct
relative positions automatically.

**Critical: Never use `global_position` to place stars inside GalaxyContainer.
Always use `position` (local). Using `global_position` will cause mesh stars to
remain fixed in world space while the camera moves — they will not track.**

### Render layers

```
Layer 1 — Galaxy rendering
    BillboardField (MultiMeshInstance3D)
    ProceduralField (MeshInstance3D sphere)
    StarContainer children (GalaxyStar nodes)
    All materials: depth_draw_never, blend_add, depth_test_disabled
    Renders first — always behind solar system geometry

Layer 2 — Solar system geometry
    Ships, planets, asteroids, local star, stations
    Renders on top of layer 1
```

Set `layers = 1` on `BillboardField` and `ProceduralField` explicitly in code.
`GameCamera.cull_mask` default (`0xFFFFF`) includes all layers — no changes needed.

### Mode separation

| Mode | Camera behavior | Galaxy rendering |
|---|---|---|
| Pilot | Follows ship | BillboardField visible but empty, StarContainer hidden |
| Galaxy Map | Free flight, detached from ship | BillboardField populated, StarContainer active |

Mode is driven by `GameEventBus.game_mode_changed`.

---

## 3. Core Properties / Data Model

### GalaxyContainer.gd

```gdscript
# Catalog — loaded from StarField autoload once in _ready()
var _catalog: Array           # StarField.get_catalog() — all 80,400 stars
var _destinations: Array      # StarField.get_destinations() — 400 navigable systems

# Child node references
var _billboard_field: GalaxyBillboardField
var _star_container: Node3D
var _procedural_field: MeshInstance3D

# Active state
var _mesh_star_nodes: Dictionary   # star.id → GalaxyStar node
var _active_selection: StarRecord = null
var _galaxy_map_active: bool = false

# Tuning — loaded from world_config.json "galaxy_map" block
var galaxy_scale: float          # KEY TUNABLE — divide all galaxy positions by this
var lod_mesh_distance: float     # camera distance below which mesh nodes spawn
var lod_fade_range: float        # crossfade overlap zone at mesh/billboard boundary
var star_spawn_check_interval: float
var camera_move_speed: float
var camera_rotation_speed: float
```

### GalaxyBillboardField.gd

Owns and manages the `MultiMeshInstance3D`. One draw call for all stars regardless
of count.

```gdscript
var _multimesh: MultiMesh
var _instance_map: Dictionary   # star.id → instance index in buffer
```

**Per-instance data layout:**

| Channel | Content | Notes |
|---|---|---|
| Transform | Local position in scaled galaxy space | `star.galaxy_position / galaxy_scale` |
| `Color.rgb` | Star color | From `StarRecord.color` |
| `Color.a` | Brightness | From `StarRecord.brightness` |
| `INSTANCE_CUSTOM.r` | LOD blend alpha | 1.0 = fully visible, 0.0 = invisible |
| `INSTANCE_CUSTOM.g` | Is destination flag | 1.0 = navigable, 0.0 = backdrop |
| `INSTANCE_CUSTOM.b` | Available | — |
| `INSTANCE_CUSTOM.a` | Available | — |

**Note:** `INSTANCE_CUSTOM` is only available in the `vertex()` stage of the shader.
Pass it through a `varying` to use in `fragment()`.

### GalaxyStar.gd

Individual SDF star for the close LOD tier. Only exists during galaxy map mode.
Must be a child of `StarContainer` — never the scene root or `World` node.

```gdscript
var star_record: StarRecord
var _mesh_instance: MeshInstance3D   # QuadMesh + galaxy_star_sdf.gdshader
var _collision: CollisionShape3D     # SphereShape3D for raycast selection
var _blend_alpha: float = 1.0

func set_blend_alpha(alpha: float) -> void:
    _blend_alpha = alpha
    if _mesh_instance and _mesh_instance.material_override:
        _mesh_instance.material_override.set_shader_parameter("blend_alpha", alpha)
```

Uses `QuadMesh` with `billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED` and
`galaxy_star_sdf.gdshader`. No `SphereMesh` — SDF produces a smoother result at
lower geometry cost with no polygon faceting.

---

## 4. Key Algorithms

### 4.1 Galaxy coordinate scaling

```gdscript
func _scaled(galaxy_pos: Vector3) -> Vector3:
    return galaxy_pos / galaxy_scale
```

`galaxy_scale` is the single number controlling how large the galaxy feels. All LOD
distances, camera speeds, and procedural field sizes are expressed in this scaled space.
**This is a tuning variable — expect significant adjustment during playtesting.**

### 4.2 MultiMesh population — once per galaxy map session

The MultiMesh is populated **once** when the player enters galaxy map mode. It is
**never rebuilt during flight**. Rebuilding 80,400 instance transforms is expensive.
Drawing a pre-built buffer is essentially free — this is what MultiMesh is designed for.

```gdscript
# GalaxyBillboardField.gd
func populate(catalog: Array) -> void:
    _multimesh.instance_count = catalog.size()
    _instance_map.clear()

    for i in catalog.size():
        var star := catalog[i]
        # LOCAL position — relative to GalaxyContainer which is at camera
        var pos := star.galaxy_position / GalaxyContainer.galaxy_scale

        _multimesh.set_instance_transform(i, Transform3D(Basis(), pos))
        _multimesh.set_instance_color(i,
            Color(star.color.r, star.color.g, star.color.b, star.brightness))
        _multimesh.set_instance_custom_data(i,
            Color(1.0, float(star.is_destination), 0.0, 0.0))
        _instance_map[star.id] = i

func set_instance_alpha(star_id: int, alpha: float) -> void:
    if not _instance_map.has(star_id):
        return
    var i   := _instance_map[star_id]
    var cur := _multimesh.get_instance_custom_data(i)
    cur.r   = alpha
    _multimesh.set_instance_custom_data(i, cur)
```

### 4.3 Mode transition

```gdscript
func _on_game_mode_changed(old_mode: String, new_mode: String) -> void:
    if new_mode == "galaxy_map":
        _galaxy_map_active = true
        _billboard_field.populate(_catalog)   # only call site for populate()
        _star_container.visible = true
        _update_mesh_star_population()
    elif old_mode == "galaxy_map":
        _galaxy_map_active = false
        _star_container.visible = false
        _clear_mesh_nodes()
```

**`populate()` is never called in pilot mode, never called during free flight,
and never called more than once per galaxy map session open.**

### 4.4 Close LOD mesh star population

The camera is always at `Vector3.ZERO` in `GalaxyContainer` local space (the container
sits at the camera). Distance checks use this fact.

```gdscript
func _update_mesh_star_population() -> void:
    if not _galaxy_map_active:
        return

    var to_keep: Dictionary = {}

    for star in _catalog:
        var local_pos := _scaled(star.galaxy_position)
        var dist      := local_pos.length()   # distance from camera (origin)

        if dist < lod_mesh_distance + lod_fade_range:
            to_keep[star.id] = true
            if not _mesh_star_nodes.has(star.id):
                _spawn_mesh_star(star)

    for star_id in _mesh_star_nodes.keys():
        if not to_keep.has(star_id):
            _mesh_star_nodes[star_id].queue_free()
            _mesh_star_nodes.erase(star_id)

func _spawn_mesh_star(star: StarRecord) -> void:
    var node: GalaxyStar = preload(
        "res://ui/galactic_map/GalaxyStar.tscn").instantiate()
    node.star_record = star
    _star_container.add_child(node)
    node.position = _scaled(star.galaxy_position)  # LOCAL — not global_position
    _mesh_star_nodes[star.id] = node
```

Run on a timer (`star_spawn_check_interval`) during galaxy map mode only.

### 4.5 LOD crossfade

Stars within `lod_fade_range` of `lod_mesh_distance` exist in both tiers simultaneously.

```gdscript
func _update_crossfades() -> void:
    for star_id in _mesh_star_nodes.keys():
        var node: GalaxyStar = _mesh_star_nodes[star_id]
        var dist := node.position.length()   # distance from camera

        var t          := (dist - (lod_mesh_distance - lod_fade_range)) / (lod_fade_range * 2.0)
        var mesh_alpha := 1.0 - clamp(t, 0.0, 1.0)

        node.set_blend_alpha(mesh_alpha)
        _billboard_field.set_instance_alpha(star_id, 1.0 - mesh_alpha)
```

### 4.6 Camera free flight

Active only when `_galaxy_map_active` is true.

```gdscript
# In GameCamera.gd or GalaxyContainer.gd depending on implementation
# Controls:
#   WASD       — move in local XZ
#   R          — move up (galaxy_map_up action)
#   F          — move down (galaxy_map_down action)
#   Right drag — rotate (yaw and pitch, pitch clamped ±80°)
#   Left click — select star
```

### 4.7 Star selection

Only `is_destination == true` stars are selectable. Backdrop stars have no collision.

Raycast from camera through click position against `GalaxyStar` collision shapes.
On hit, confirm destination status and emit `tactical_selection_changed`.

Double-click or confirm key on a reachable selected star emits
`warp_destination_selected(system_id)` — the same signal `GameOrchestrator` already
listens to. No changes to `GameOrchestrator` required.

```gdscript
func _is_reachable(star: StarRecord) -> bool:
    var current := StarField.current_system
    if current == null:
        return false
    return current.galaxy_position.distance_to(
        star.galaxy_position) <= star.warp_range
```

### 4.8 Procedural density field

`galaxy_map_field.gdshader` on a large `SphereMesh` centered on `GalaxyContainer`.
Evaluates galaxy structure density from 3D world position converted back to galaxy
coordinates. Uses `hash()` and `vnoise()` functions — copy these verbatim from
`galaxy_sky.gdshader`.

Encodes:
- Core density — denser near galaxy center
- Disc thickness — thinner at larger radii
- Spiral arm structure — via arm noise modulation

Fades out near `lod_mesh_distance` so field does not overlap mesh or billboard stars.

---

## 5. Star Rendering — Close LOD (SDF Shader)

Close LOD stars use `galaxy_star_sdf.gdshader` on a `QuadMesh` billboard.

```glsl
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never,
            blend_add, depth_test_disabled;

void fragment() {
    vec2 uv    = UV * 2.0 - 1.0;
    float dist = length(uv);
    float sdf  = dist - star_radius;

    float sphere = 1.0 - smoothstep(-0.02, 0.02, sdf);

    float beyond = max(0.0, sdf);
    float corona = corona_intensity / (1.0 + beyond * beyond * 80.0);
    corona *= 1.0 - smoothstep(0.0, 1.5, beyond);

    // Limb darkening, plasma surface noise, color...
    // See galaxy_star_sdf.gdshader for full implementation

    ALPHA = clamp(sphere + corona, 0.0, 1.0) * blend_alpha;
}
```

`blend_alpha` uniform drives the LOD crossfade. Set via `set_blend_alpha()` on
`GalaxyStar.gd`.

---

## 6. JSON Data Format

```json
"galaxy_map": {
    "galaxy_scale": 100.0,
    "lod_mesh_distance": 10.0,
    "lod_fade_range": 4.0,
    "camera_move_speed": 50.0,
    "camera_rotation_speed": 0.003,
    "star_spawn_check_interval": 0.25,
    "proc_field_cell_size": 800.0,
    "proc_field_sphere_radius": 8000.0,
    "star_sdf": {
        "corona_intensity_scale": 0.4,
        "noise_scale": 3.0,
        "flow_speed": 0.08,
        "surface_brightness": 1.2,
        "limb_darkening": 0.6,
        "star_radius": 0.85
    }
}
```

**`lod_billboard_distance` does not exist in this system.** The MultiMesh contains
all 80,400 catalog stars with no distance filtering. The procedural field provides
density context beyond where individual billboard stars are distinguishable.

---

## 7. Performance Instrumentation

```gdscript
PerformanceMonitor.begin("GalaxyMap.population_update")
_update_mesh_star_population()
PerformanceMonitor.end("GalaxyMap.population_update")

PerformanceMonitor.begin("GalaxyMap.crossfade_update")
_update_crossfades()
PerformanceMonitor.end("GalaxyMap.crossfade_update")

PerformanceMonitor.set_count("GalaxyMap.mesh_star_nodes",
    _mesh_star_nodes.size())
PerformanceMonitor.set_count("GalaxyMap.billboard_instances",
    _billboard_field.instance_count())
```

**Expected values:**
- `GalaxyMap.billboard_instances` — 80,400 (constant, full catalog)
- `GalaxyMap.mesh_star_nodes` — 0 in pilot mode, 0–50 in galaxy map mode
- `GalaxyMap.population_update` — under 2ms (only checks nearby stars)

---

## 8. Files

| File | Status | Purpose |
|---|---|---|
| `ui/galactic_map/GalaxyContainer.gd` | Active | Scene root, catalog, LOD manager |
| `ui/galactic_map/GalaxyBillboardField.gd` | Active | MultiMeshInstance3D, all 80,400 stars |
| `ui/galactic_map/GalaxyStar.gd` | Active | SDF close-tier star, selectable |
| `ui/galactic_map/GalaxyStar.tscn` | Active | QuadMesh + CollisionShape3D |
| `core/starfield/galaxy_map_field.gdshader` | Active | Procedural density field |
| `core/starfield/galaxy_star_sdf.gdshader` | Active | SDF sphere shader for close LOD |
| `gameplay/camera/GameCamera.gd` | Modified | Galaxy map free flight mode |
| `ui/galactic_map/GalacticMap.gd` | **SUPERSEDED** | Old 2D canvas — do not extend |
| `ui/galactic_map/GalacticMap.tscn` | **SUPERSEDED** | Old scene — do not extend |
| `data/world_config.json` | Modified | `galaxy_map` block added |
| `project.godot` | Modified | `galaxy_map_up` (R) and `galaxy_map_down` (F) |

---

## 9. Dependencies

| Dependency | Why |
|---|---|
| `StarField` autoload | `get_catalog()`, `get_destinations()`, `current_system` |
| `GameEventBus` | `game_mode_changed`, `warp_destination_selected`, `tactical_selection_changed` |
| `GameCamera.gd` | `release()` and `follow()` already implemented |
| `GameOrchestrator.gd` | No changes required |
| `InputManager.gd` | Must suppress WASD ship input during galaxy map mode |
| `PlayerState` | `get_active_ship()` on exit to re-follow ship |

---

## 10. Assumptions

- `galaxy_scale: 100.0` is a starting point. Expect significant tuning.
- The MultiMesh always contains all 80,400 catalog stars during galaxy map mode.
  All 80,400 render in one GPU draw call — this is MultiMesh's purpose.
- `populate()` is called exactly once per galaxy map session. Never in pilot mode.
  Never during free flight. The buffer is static once built.
- No zoom animation or fade on map open/close at MVP. Deferred to polish pass.
- Backdrop stars cannot be selected — no collision shape. Only `is_destination == true`
  stars have `CollisionShape3D`.
- `galaxy_star_sdf.gdshader` assumes Godot's default QuadMesh UV where center is (0.5, 0.5).

---

## 11. Success Criteria

- [ ] Galaxy stars visible in pilot mode as background — no mode switch required
- [ ] Stars do not parallax during ship movement — attached to camera correctly
- [ ] M key detaches camera and enables free flight
- [ ] WASD moves in local axes, R/F moves vertically
- [ ] Right mouse drag rotates camera, pitch clamped ±80°
- [ ] `populate()` is never called in pilot mode
- [ ] Mesh star nodes never visible in pilot mode
- [ ] Entering galaxy map calls `populate()` exactly once
- [ ] Mesh stars are children of `StarContainer` and move with camera
- [ ] Mesh star positions use local `position` not `global_position`
- [ ] Mesh/billboard crossfade is smooth — no pop
- [ ] Procedural field shows galaxy structure — core bright, arms visible, disc thin
- [ ] Left click on destination star selects it
- [ ] Reachable systems visually distinct from out-of-range
- [ ] Double-click reachable system emits `warp_destination_selected`
- [ ] M again returns to pilot mode following ship
- [ ] `galaxy_scale` change requires no code changes
- [ ] `GalaxyMap.billboard_instances` reads 80,400 in overlay
- [ ] `GalaxyMap.population_update` reads under 2ms in overlay
- [ ] No hardcoded values in any `.gd` file
