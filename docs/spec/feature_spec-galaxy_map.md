# Feature Spec — Galaxy Map
*All Space — Seamless Scale Transition, Camera-Attached Galaxy, Free Flight Navigation*

---

## 1. Overview

The galaxy is a physical object in the solar system scene — a `MultiMeshInstance3D`
built from the star catalog, attached to and moving with `GameCamera`. From inside it
the player sees a realistic star field because they are literally inside a scaled-down
galaxy. When the player presses M, the camera detaches from the ship and flies outward
through the galaxy. The solar system geometry recedes. The galaxy surrounds the camera
correctly at every scale because it always has.

There is no separate SubViewport, no overlay scene, no hard cut between pilot view and
galaxy map. It is one continuous 3D scene with one camera that can zoom from cockpit
scale to galactic scale and back.

**Design goals:**
- Seamless continuous zoom from ship cockpit to full galaxy view
- Galaxy feels correct from inside at any scale — you are inside it, not looking at it
- LOD drives star rendering at every camera distance automatically
- Scale is a single tunable value — the galaxy can be made larger or smaller without
  touching code
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
│   │       └── [GalaxyStar nodes — close tier, spawned at runtime]
│   └── [existing camera children]
└── UILayer (CanvasLayer)
    ├── PilotHUD
    ├── ModeSwitch
    └── GalaxyMapUI (CanvasLayer, layer 10 — visible only in galaxy map mode)
        ├── SelectionIndicator (Control)
        └── HUDHints (Label)
```

`GalaxyContainer` is a `Node3D` child of `GameCamera`. It moves with the camera
everywhere. All galaxy rendering lives inside it. The solar system geometry is on a
separate render layer and renders on top.

### Render Layers

```
Layer 1 — Galaxy (BillboardField, ProceduralField, StarContainer)
    depth_draw_never on all materials
    renders first, always behind everything else

Layer 2 — Solar system geometry (ships, planets, asteroids, local star)
    renders on top of layer 1
```

Godot's `Camera3D.cull_mask` controls which layers the camera renders. Both layers are
always rendered — no toggling needed.

### Mode Separation

Two camera modes share the same scene:

| Mode | Camera state | Input |
|---|---|---|
| Pilot | Follows ship, standard follow logic | WASD thrust, mouse aim |
| Galaxy Map | Free flight, detached from ship | WASD move, RF vertical, right mouse rotate |

Mode switch is driven by `GameEventBus.game_mode_changed` — the same signal used for
Tactical mode. `GalaxyContainer` listens and adjusts LOD update frequency accordingly.

---

## 3. Core Properties / Data Model

### GalaxyContainer.gd

Owns the galaxy rendering. Reads catalog from `StarField` autoload. Manages LOD
population updates on a timer.

```gdscript
var _catalog: Array               # StarField.get_catalog()
var _destinations: Array          # StarField.get_destinations()
var _billboard_field: GalaxyBillboardField
var _star_container: Node3D
var _mesh_star_nodes: Dictionary  # star.id → GalaxyStar node
var _spawn_check_timer: float = 0.0
var _current_system_pos: Vector3  # scaled galaxy position of current system

# Loaded from world_config.json — all in scaled galaxy space
var galaxy_scale: float           # THE key tunable — divides all galaxy positions
var lod_mesh_distance: float      # camera distance below which stars get mesh nodes
var lod_billboard_distance: float # camera distance below which stars enter MultiMesh
var lod_fade_range: float         # overlap zone width for crossfade between tiers
var spawn_check_interval: float   # seconds between population update checks
```

### GalaxyBillboardField.gd

Manages the `MultiMeshInstance3D` for all billboard-tier stars. One draw call regardless
of instance count.

```gdscript
var _multimesh: MultiMesh
var _instance_map: Dictionary   # star.id → instance index in multimesh buffer
```

**Per-instance data layout:**

| Channel | Content |
|---|---|
| Transform | Position in scaled galaxy space |
| `Color.rgb` | Star color (red dwarf, yellow, blue-white etc.) |
| `Color.a` | Brightness |
| `INSTANCE_CUSTOM.r` | LOD blend alpha — 1.0 fully visible, 0.0 invisible |
| `INSTANCE_CUSTOM.g` | Is destination flag — 1.0 = navigable system |
| `INSTANCE_CUSTOM.b` | Available |
| `INSTANCE_CUSTOM.a` | Available |

### GalaxyStar.gd

Individual mesh star for the close LOD tier. Selectable via collision shape.

```gdscript
var star_record: StarRecord
var _mesh_instance: MeshInstance3D   # simple emissive sphere
var _collision: CollisionShape3D     # SphereShape3D sized to mesh
var _blend_alpha: float = 1.0
```

No `Sprite3D` component — the billboard tier is handled entirely by `GalaxyBillboardField`.

### GalaxyMapMode

Not a separate class — a state flag on `GameCamera.gd`:

```gdscript
var _galaxy_map_active: bool = false
var _galaxy_map_camera_yaw: float = 0.0
var _galaxy_map_camera_pitch: float = 0.0  # clamped to ±80°
```

---

## 4. Key Algorithms

### 4.1 Galaxy positioning

Every star's galaxy position is divided by `galaxy_scale` before use in the scene.
`GalaxyContainer` stores the current system's scaled position as an offset — the
camera starts centered on it when the map opens.

```gdscript
func _scaled_pos(star: StarRecord) -> Vector3:
    return star.galaxy_position / galaxy_scale

func _on_system_changed(system_record: StarRecord) -> void:
    _current_system_pos = _scaled_pos(system_record)
```

All LOD distance checks, spawn decisions, and MultiMesh transforms use scaled positions.
`galaxy_scale` is the single number that controls how large the galaxy feels.

### 4.2 LOD population update

Runs on a timer (`spawn_check_interval`, default 0.25s). The camera position in scaled
galaxy space drives which stars belong to which tier.

```gdscript
func _update_star_populations() -> void:
    var cam_pos := global_position   # GalaxyContainer moves with camera
    var mesh_stars: Array = []
    var billboard_stars: Array = []

    for star in _catalog:
        var pos  := _scaled_pos(star)
        var dist := cam_pos.distance_to(pos)

        if dist < lod_mesh_distance + lod_fade_range:
            mesh_stars.append(star)
        elif dist < lod_billboard_distance + lod_fade_range:
            billboard_stars.append(star)
        # Beyond lod_billboard_distance — procedural field covers it

    _sync_mesh_nodes(mesh_stars)
    _billboard_field.populate(billboard_stars, cam_pos)
```

### 4.3 Crossfade at tier boundaries

Stars within `lod_fade_range` of `lod_mesh_distance` exist in both tiers simultaneously.
The mesh node fades in as the MultiMesh instance fades out, and vice versa on retreat.

```gdscript
func _compute_blend(dist: float) -> float:
    # Returns mesh alpha — 1.0 at mesh tier, 0.0 at billboard tier
    var boundary := lod_mesh_distance
    var t := (dist - (boundary - lod_fade_range)) / (lod_fade_range * 2.0)
    return 1.0 - clamp(t, 0.0, 1.0)

func _apply_crossfade(star: StarRecord, dist: float) -> void:
    var mesh_alpha := _compute_blend(dist)
    if _mesh_star_nodes.has(star.id):
        _mesh_star_nodes[star.id].set_blend_alpha(mesh_alpha)
    _billboard_field.set_instance_alpha(star.id, 1.0 - mesh_alpha)
```

### 4.4 MultiMesh buffer population

```gdscript
# GalaxyBillboardField.gd
func populate(stars: Array, camera_pos: Vector3) -> void:
    _multimesh.instance_count = stars.size()
    _instance_map.clear()

    for i in stars.size():
        var star := stars[i]
        var pos  := star.galaxy_position / GalaxyContainer.galaxy_scale

        _multimesh.set_instance_transform(i,
            Transform3D(Basis(), pos))
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

### 4.5 Galaxy map camera controls

Active only when `_galaxy_map_active` is true. Overrides normal camera follow logic.

```gdscript
# GalaxyCamera.gd additions
func _galaxy_map_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_RIGHT:
            _rmb_held = event.pressed

    if event is InputEventMouseMotion and _rmb_held:
        _galaxy_map_camera_yaw   -= event.relative.x * rotation_speed
        _galaxy_map_camera_pitch -= event.relative.y * rotation_speed
        _galaxy_map_camera_pitch  = clamp(
            _galaxy_map_camera_pitch,
            deg_to_rad(-80.0),
            deg_to_rad(80.0)
        )
        rotation = Vector3(_galaxy_map_camera_pitch, _galaxy_map_camera_yaw, 0.0)

    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        if event.pressed:
            _try_select(get_viewport().get_mouse_position())

func _galaxy_map_process(delta: float) -> void:
    var move := Vector3.ZERO
    if Input.is_action_pressed("move_forward"):     move -= basis.z
    if Input.is_action_pressed("move_backward"):    move += basis.z
    if Input.is_action_pressed("move_left"):        move -= basis.x
    if Input.is_action_pressed("move_right"):       move += basis.x
    if Input.is_action_pressed("galaxy_map_up"):    move += Vector3.UP
    if Input.is_action_pressed("galaxy_map_down"):  move -= Vector3.UP

    if move.length_squared() > 0.0:
        global_position += move.normalized() * camera_move_speed * delta
```

### 4.6 Star selection

Raycasts from camera through click position against `GalaxyStar` collision shapes.
Only destination stars are selectable — backdrop stars have no collision shape.

```gdscript
func _try_select(screen_pos: Vector2) -> void:
    var space  := get_world_3d().direct_space_state
    var origin := project_ray_origin(screen_pos)
    var end    := origin + project_ray_normal(screen_pos) * 10000.0
    var query  := PhysicsRayQueryParameters3D.create(origin, end)
    var hit    := space.intersect_ray(query)

    if hit and hit.collider is GalaxyStar:
        var star := (hit.collider as GalaxyStar).star_record
        if star.is_destination:
            _active_selection = star
            GameEventBus.tactical_selection_changed.emit([star.system_id])
```

Double-click or confirm key on a reachable selected system:

```gdscript
if _active_selection != null and _is_reachable(_active_selection):
    GameEventBus.warp_destination_selected.emit(_active_selection.system_id)
    _close_galaxy_map()
```

Reachability check:

```gdscript
func _is_reachable(star: StarRecord) -> bool:
    var current := StarField.current_system
    if current == null:
        return false
    var dist := current.galaxy_position.distance_to(star.galaxy_position)
    return dist <= star.warp_range
```

### 4.7 Map open/close transition

On M press, `InputManager` emits `game_mode_changed("pilot", "galaxy_map")`.
`GameCamera` listens and executes:

```gdscript
func _enter_galaxy_map() -> void:
    _galaxy_map_active = true
    # Preserve current rotation as starting galaxy map orientation
    _galaxy_map_camera_yaw   = rotation.y
    _galaxy_map_camera_pitch = rotation.x
    # Release ship follow — camera now free
    release()
    # Show galaxy map UI
    GameEventBus.cinematic_active_changed.emit(false)   # player keeps input

func _exit_galaxy_map() -> void:
    _galaxy_map_active = false
    # Re-follow player ship
    var ship := PlayerState.get_active_ship()
    if ship:
        follow(ship)
```

No fade, no transition effect at MVP. Camera simply releases and the player flies
freely. Visual polish (zoom animation, fade) is deferred.

### 4.8 Procedural field shader

`galaxy_map_field.gdshader` runs on a large `SphereMesh` centered on `GalaxyContainer`
(which is centered on the camera). It evaluates star density based on the fragment's
world position converted back to galaxy coordinates — the same four-zone model as
`galaxy_sky.gdshader` but in 3D position space rather than direction space.

The sphere must be large enough to surround the camera at any position within the
galaxy map. `proc_field_sphere_radius` in `world_config.json` controls this and scales
with `galaxy_scale`.

```glsl
// Convert world position back to galaxy coordinates
vec3 galaxy_pos = VERTEX * galaxy_scale;

// Same density model as sky shader
float gal_radius  = length(galaxy_pos.xz) / 100000.0;
float core_factor = mix(proc_core_boost, 1.0, clamp(gal_radius, 0.0, 1.0));
float disc_y      = abs(galaxy_pos.y) / 8000.0;
float disc_factor = 1.0 - clamp(disc_y * proc_disc_falloff, 0.0, 0.85);
float arm_noise   = vnoise(normalize(galaxy_pos) * 3.0);
float arm_factor  = mix(0.85, 1.0, arm_noise);

// Hash 3D cell for star presence
vec3 cell_id    = floor(galaxy_pos / proc_field_cell_size);
float cell_hash = hash(cell_id * 7.3 + vec3(13.7, 5.1, 9.3));

float star_prob = (1.0 - proc_star_density) * core_factor * disc_factor * arm_factor;
star_prob       = clamp(star_prob, 0.0, 1.0);

// Fade out near lod_billboard_distance so field doesn't overlap MultiMesh stars
float cam_dist     = length(VERTEX);   // distance from camera in scaled space
float field_alpha  = smoothstep(
    lod_billboard_distance * 0.5,
    lod_billboard_distance,
    cam_dist
);

if (cell_hash < star_prob) {
    // render star glow at this fragment, scaled by field_alpha
}
```

---

## 5. JSON Data Format

Add to `data/world_config.json` under a new `"galaxy_map"` block:

```json
"galaxy_map": {
    "galaxy_scale": 100.0,
    "lod_mesh_distance": 80.0,
    "lod_billboard_distance": 400.0,
    "lod_fade_range": 40.0,
    "camera_move_speed": 50.0,
    "camera_rotation_speed": 0.003,
    "star_spawn_check_interval": 0.25,
    "proc_field_cell_size": 800.0,
    "proc_field_sphere_radius": 8000.0
}
```

**`galaxy_scale` is the primary tuning knob.** Increasing it makes the galaxy feel
larger — stars are further apart, the camera moves through more space to traverse the
galaxy. All LOD distances are in scaled space and adjust automatically. Start with 100,
tune during playtesting.

---

## 6. Performance Instrumentation

```gdscript
# GalaxyContainer.gd
PerformanceMonitor.begin("GalaxyMap.population_update")
_update_star_populations()
PerformanceMonitor.end("GalaxyMap.population_update")

PerformanceMonitor.begin("GalaxyMap.crossfade_update")
_update_crossfades()
PerformanceMonitor.end("GalaxyMap.crossfade_update")

PerformanceMonitor.set_count("GalaxyMap.mesh_star_nodes",   _mesh_star_nodes.size())
PerformanceMonitor.set_count("GalaxyMap.billboard_instances", _billboard_field.instance_count())
```

Register in `_ready()`:

```gdscript
Performance.add_custom_monitor("AllSpace/galaxy_mesh_stars",
    func(): return PerformanceMonitor.get_count("GalaxyMap.mesh_star_nodes"))
Performance.add_custom_monitor("AllSpace/galaxy_billboard_stars",
    func(): return PerformanceMonitor.get_count("GalaxyMap.billboard_instances"))
Performance.add_custom_monitor("AllSpace/galaxy_population_ms",
    func(): return PerformanceMonitor.get_avg_ms("GalaxyMap.population_update"))
```

---

## 7. Files

| File | Status | Purpose |
|---|---|---|
| `ui/galactic_map/GalaxyContainer.gd` | New | Scene root, catalog owner, LOD manager |
| `ui/galactic_map/GalaxyBillboardField.gd` | New | MultiMeshInstance3D manager, billboard tier |
| `ui/galactic_map/GalaxyStar.gd` | New | Individual mesh star, close tier, selectable |
| `ui/galactic_map/GalaxyStar.tscn` | New | MeshInstance3D + CollisionShape3D |
| `core/starfield/galaxy_map_field.gdshader` | New | Procedural density field shader |
| `gameplay/camera/GameCamera.gd` | Modify | Add galaxy map mode, free flight input |
| `ui/galactic_map/GalacticMap.gd` | **Replace** | Old 2D canvas — superseded entirely |
| `ui/galactic_map/GalacticMap.tscn` | **Replace** | Old scene — superseded entirely |
| `Main.tscn` | Modify | Add GalaxyContainer as child of GameCamera |
| `data/world_config.json` | Modify | Add `galaxy_map` block |
| `project.godot` | Modify | Add `galaxy_map_up` (R) and `galaxy_map_down` (F) actions |

---

## 8. Dependencies

| Dependency | Why |
|---|---|
| `StarField` autoload | Must expose `get_catalog()`, `get_destinations()`, `current_system` |
| `GameEventBus` | `galactic_map_toggled`, `game_mode_changed`, `warp_destination_selected`, `system_transition_complete` |
| `GameCamera.gd` | Must support `release()` and `follow()` — already implemented |
| `GameOrchestrator.gd` | No changes required — consumes same `warp_destination_selected` signal |
| `galaxy_sky.gdshader` | Reference for `hash()` and `vnoise()` functions to port into field shader |
| `InputManager.gd` | Must not route WASD to player ship during galaxy map mode |

---

## 9. Assumptions

- `galaxy_scale: 100.0` is a starting point. The correct value depends entirely on how
  the zoom transition feels in practice. Expect to tune this significantly.
- At `galaxy_scale: 100.0` and `lod_billboard_distance: 400.0`, stars within 40,000
  galaxy units of the camera enter the MultiMesh. Near the galactic core this could be
  thousands of stars — monitor `GalaxyMap.billboard_instances` and adjust
  `lod_billboard_distance` if the buffer becomes too large.
- The close-tier mesh star uses a simple emissive `SphereMesh` with a flat color
  material, not the full roiling plasma shader from `StarMesh.tscn`. The plasma shader
  is reserved for in-game close approach to the local star.
- No zoom animation or fade on map open/close at MVP. Camera releases and player flies
  freely. Cinematic transition is post-MVP polish.
- `GalaxyStar` collision shapes are sized for comfortable clicking, not physically
  accurate star radii. Tuned during playtesting.
- Backdrop stars have no collision shape and cannot be selected. Only destination
  systems (`star.is_destination == true`) are selectable.
- The procedural field sphere radius must be large enough to surround the camera
  regardless of galaxy map position. `proc_field_sphere_radius * galaxy_scale` should
  exceed `galaxy_radius`.

---

## 10. Success Criteria

- [ ] Pressing M detaches camera from ship and enables free flight
- [ ] WASD moves camera in local XZ plane, R/F moves vertically
- [ ] Right mouse drag rotates camera freely, pitch clamped to ±80°
- [ ] Galaxy stars are visible from pilot view as background without any mode switch
- [ ] Stars within `lod_mesh_distance` render as individual `GalaxyStar` mesh nodes
- [ ] Stars within `lod_billboard_distance` render as MultiMesh instances
- [ ] Transition between mesh and billboard is a smooth crossfade — no pop
- [ ] Stars beyond `lod_billboard_distance` are invisible — covered by procedural field
- [ ] Procedural field shows galaxy structure — core brighter, arms denser, disc thin
- [ ] Flying toward a star watches it emerge from field → billboard → mesh
- [ ] Left click on a destination star selects it with a visual indicator
- [ ] Reachable systems are visually distinct from out-of-range systems
- [ ] Double-click on a reachable selected system emits `warp_destination_selected`
- [ ] Map closes and `GameOrchestrator` transition sequence begins
- [ ] Pressing M again while in galaxy map returns to pilot mode
- [ ] `galaxy_scale` in `world_config.json` changes the apparent galaxy size with no
      code changes required
- [ ] All three metrics visible in PerformanceMonitor overlay:
      `GalaxyMap.mesh_star_nodes`, `GalaxyMap.billboard_instances`,
      `GalaxyMap.population_update`
- [ ] No hardcoded distances, speeds, or counts in any `.gd` file
