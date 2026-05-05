# Star Field System Specification
*All Space Combat MVP — Background Star Field*

## Overview

A procedurally generated star field rendered as a large point-cloud `ArrayMesh` using
`PRIMITIVE_POINTS`. Stars are real 3D geometry at genuine depth — the renderer provides
true parallax for free as the camera moves. No fake UV-offset tricks required.

**Design Goals:**
- True parallax from actual 3D positions — near stars shift more than far stars as the
  camera moves, with no shader math to fake it
- One draw call for the entire star field
- Warp-ready — star positions or camera FOV are easily manipulated at warp time
- All tunable values (star count, spread radius, brightness range, point size) in
  `data/world_config.json` under a `"star_field"` block

---

## Architecture

```
StarField (Node3D — child of the world root, sibling of ChunkStreamer)
    └── MeshInstance3D
            └── ArrayMesh (PRIMITIVE_POINTS, generated at _ready())
```

`StarField` is a scene node, not an autoload. It does not follow the player — stars
are placed at world-space positions and the camera's natural perspective projection
handles apparent motion as the player flies. The mesh is generated once at startup
and never rebuilt during gameplay.

The node sits at world origin (`position = Vector3.ZERO`) and never moves. The
`MeshInstance3D` has no shadow casting, no lightmap, and is excluded from all
collision layers.

---

## Core Properties / Data Model

| Property | Type | Description |
|---|---|---|
| `star_count` | `int` | Total point vertices in the mesh |
| `spread_xz` | `float` | Half-extent of star placement on the XZ plane |
| `spread_y` | `float` | Half-extent on the Y axis — slight vertical spread adds depth |
| `point_size` | `float` | Screen-space pixel size of each star point |
| `brightness_min` | `float` | Minimum alpha value baked into vertex colors (0.0–1.0) |
| `brightness_max` | `float` | Maximum alpha value baked into vertex colors (0.0–1.0) |
| `seed` | `int` | RNG seed — same seed always produces the same sky |

Vertex colors are baked into the `ARRAY_COLOR` surface array at generation time.
No per-frame color updates occur. Brightness variation comes entirely from the
baked color array, not from the shader.

---

## Key Algorithms

### Mesh Generation

Run once in `_ready()`. The RNG is seeded from `data/world_config.json` so the
sky is deterministic across sessions.

```gdscript
func _generate_star_mesh() -> ArrayMesh:
    var rng := RandomNumberGenerator.new()
    rng.seed = seed

    var verts  := PackedVector3Array()
    var colors := PackedColorArray()

    for i in star_count:
        var pos := Vector3(
            rng.randf_range(-spread_xz, spread_xz),
            rng.randf_range(-spread_y,  spread_y),
            rng.randf_range(-spread_xz, spread_xz)
        )
        var brightness := rng.randf_range(brightness_min, brightness_max)
        verts.append(pos)
        colors.append(Color(1.0, 1.0, 1.0, brightness))

    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = verts
    arrays[Mesh.ARRAY_COLOR]  = colors

    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays)
    return mesh
```

### Shader

A minimal unlit spatial shader. `gl_PointCoord` draws a soft circular glow inside
each point quad — without this, points render as hard pixel squares.

```glsl
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform float point_size : hint_range(1.0, 16.0) = 2.0;

void vertex() {
    POINT_SIZE = point_size;
}

void fragment() {
    // Soft circular falloff inside the point quad
    vec2 uv    = POINT_COORD - vec2(0.5);
    float dist = length(uv) * 2.0;
    float alpha = smoothstep(1.0, 0.2, dist);

    ALBEDO   = COLOR.rgb;
    ALPHA    = COLOR.a * alpha;
    EMISSION = COLOR.rgb * COLOR.a;
}
```

`depth_draw_never` prevents stars from writing to the depth buffer, so they never
occlude gameplay geometry. `cull_disabled` keeps the inside face visible since the
camera is inside the star sphere.

The shader file lives at `gameplay/world/star_field.gdshader` and is assigned to
the `MeshInstance3D`'s material in `StarField.tscn`.

### No Follow Logic

Stars do not follow the camera. True parallax is free from the perspective projection:
a star at (50000, 200, 30000) naturally shifts on-screen more slowly than one at
(3000, 20, 2000) as the camera moves. No code is needed to produce this effect.

The only caveat: spread_xz must be large enough that stars never visibly "run out"
at the boundary. With `chunk_size = 2000` and `load_radius = 2`, the live arena is
~10,000 units across. A `spread_xz` of 150,000 ensures the boundary is never visible
at any realistic player position or speed.

---

## JSON Data Format

Added as a block inside the existing `data/world_config.json`:

```json
{
  "star_field": {
    "star_count": 8000,
    "spread_xz": 150000.0,
    "spread_y": 8000.0,
    "point_size": 2.0,
    "brightness_min": 0.2,
    "brightness_max": 1.0,
    "seed": 42
  }
}
```

All values are tunable without a code change. Reduce `star_count` first if performance
is a concern — 2,000 stars is still visually dense at this camera angle.

---

## Performance Instrumentation

Generation is a one-time startup cost, not a per-frame operation. Instrument it to
catch slow startup on low-end hardware:

```gdscript
func _ready() -> void:
    PerformanceMonitor.begin("StarField.generate")
    var mesh := _generate_star_mesh()
    $MeshInstance3D.mesh = mesh
    PerformanceMonitor.end("StarField.generate")
```

No per-frame instrumentation is needed — after `_ready()`, `StarField` does nothing.

Register a custom monitor for the star count (static, but useful for debugging):

```gdscript
Performance.add_custom_monitor("AllSpace/star_count",
    func(): return star_count)
```

---

## Files

```
/gameplay/world/
    StarField.gd          ← generates ArrayMesh, loads config, owns no per-frame logic
    StarField.tscn        ← Node3D root + MeshInstance3D child; shader assigned here
    star_field.gdshader   ← unlit point shader with soft circular glow
/data/
    world_config.json     ← add "star_field" block (existing file)
```

---

## Dependencies

- `PerformanceMonitor` — must be registered before `StarField` enters the scene tree
- `data/world_config.json` — must include the `"star_field"` block before first run
- No dependency on `ChunkStreamer`, `Ship`, or any gameplay system — stars are
  entirely cosmetic and communicate with nothing

---

## Assumptions

- `spread_xz` of 150,000 keeps the star boundary well beyond any reachable player
  position. If the game ever supports genuinely large travel distances (warp covering
  millions of units), this may need to increase — or the mesh repositioned on warp.
- `spread_y` of 8,000 gives slight vertical depth. The camera angle means most
  Y-offset stars are off-screen, but a small spread prevents the field from looking
  perfectly flat.
- Star color is white only at MVP. Tinted stars (blue hot, red cool) require adding
  a color selection step to generation — deferred to art pass.
- `depth_draw_never` means stars are always drawn behind all other geometry, which
  is correct. If a future system requires stars to be occluded by a specific object,
  this render mode would need revisiting.
- Point size max is GPU-driver-dependent (typically 64–128px). `point_size` values
  above 8.0 in config are not recommended.

---

## Success Criteria

- [ ] Stars are visible from game start without any additional setup
- [ ] Camera movement produces visible parallax — stars at different Y depths shift
  at visibly different rates
- [ ] The star field has no visible boundary at any reachable player position
- [ ] Stars render behind all ships, projectiles, and UI — never occluding gameplay
- [ ] Point glow is circular and soft, not a hard square pixel
- [ ] `star_count`, `spread_xz`, `point_size`, `brightness_min/max`, and `seed` are
  all read from `data/world_config.json` — no hardcoded values in `.gd` files
- [ ] Changing `seed` in JSON produces a visibly different sky on next launch
- [ ] Generation completes in under 50ms on target hardware (captured by
  `StarField.generate` metric)
- [ ] No `Vector2`, `Node2D`, or 2D physics nodes appear anywhere in this system
- [ ] System has zero per-frame CPU cost after `_ready()` completes
