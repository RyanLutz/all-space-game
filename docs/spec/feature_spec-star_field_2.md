# StarField System Specification
*All Space — Procedural Galaxy, Skybox Rendering, and Galactic Map*

## Overview

The StarField system owns everything galaxy-scale and visual: the procedural generation
of the galaxy's star catalog, the skybox that surrounds every star system, the nebula
volumes that color different regions of space, and the galactic map the player uses to
navigate between destination systems.

Stars in this system are in one of two populations. The vast majority are **backdrop
stars** — purely visual points that give the galaxy its shape and density. They live only
in the skybox shader and are never gameplay objects. A sparse subset are **destination
systems** — also procedurally generated, but flagged as navigable and carrying gameplay
metadata. Both populations are generated from the same galaxy seed and share the same
position catalog, but destination systems are a distinct layer with distinct rendering
treatment in the galactic map.

The skybox is redrawn each time the player warps to a new destination system, shifting
the apparent star field to reflect the player's new position within the galaxy. From
inside any system, the sky looks exactly right for where that system sits in the galaxy.

**This spec does NOT own:**
- The in-system star mesh, lighting, or exclusion zone — see Solar System spec
- Warp mechanics and scene transitions — see Warp spec
- In-system gameplay (planets, stations, asteroid belts) — see Solar System spec

**Design Goals:**
- The galaxy has a real shape — spiral arms, dense core, sparse edges, disc thickness
- The skybox is parallax-free and depth-buffer-free; no Z-fighting at any scale
- Nebula volumes color different regions of space; colors are subtle at full galaxy zoom
  and rich when zoomed in on the galactic map
- Star brightness and size vary by type; blue giants are visually dominant, red dwarfs
  are dim and numerous
- The galactic map is the same star catalog rendered in a navigable UI mode — not a
  separate scene or dataset
- Destination systems are distinguishable in the galactic map without cluttering the
  full galaxy view
- All generation parameters in `world_config.json`; changing the seed produces a
  completely different galaxy

---

## Architecture

```
StarField (Autoload)
    ├── Generates and owns the full star catalog at startup
    ├── Generates and owns the nebula volume catalog at startup
    ├── Rebuilds the skybox when player warps (called by Warp system)
    ├── Provides star/system data to the Galactic Map
    └── Exposes destination system list to navigation systems

GalaxySkybox (WorldEnvironment → Sky → ShaderMaterial)
    ├── Custom sky shader — runs per-fragment, no geometry, no depth buffer
    ├── Receives packed star direction/color/size texture from StarField
    ├── Receives nebula volume uniforms from StarField
    ├── Receives map_zoom uniform for nebula opacity scaling
    └── Redrawn on warp by StarField.rebuild_skybox(new_system_position)

GalacticMap (CanvasLayer — UI mode, toggled by GameEventBus)
    ├── Renders star catalog as a navigable 2D projection of galaxy positions
    ├── Highlights destination systems; dims backdrop stars
    ├── Draws nav paths between reachable systems
    ├── Shows nebula color regions at mid/close zoom levels
    └── Emits warp_destination_selected(system_id) on player selection

StarField
    └── reads → data/world_config.json  (galaxy seed, all generation parameters)
```

`StarField` is an autoload. It generates the catalog once at startup and holds it for
the entire session. The galactic map and the skybox both read from the same catalog —
there is no separate data layer for either.

---

## Star Populations

### Backdrop Stars

Purely visual. They give the galaxy its density, spiral arm structure, and the sense
that you are inside something vast. They are never selectable, never navigable, and
carry no gameplay data. They exist only in the skybox shader as direction vectors and
appearance properties.

At full galaxy zoom in the galactic map, backdrop stars render as a dim monochrome
point cloud forming the galaxy silhouette. They are not individually distinct.

### Destination Systems

A sparse procedural subset of the catalog flagged as navigable. Each destination system
is a real star with a position in the galaxy volume — it may sit above or below the
galactic disc, not just along a flat plane. The Y position in galaxy space is a map
coordinate only; it has no bearing on gameplay inside the system, which always unfolds
on its own local XZ plane.

Destination systems appear in the galactic map as slightly brighter points. Systems
reachable from the player's current position (within warp range) glow distinctly to
signal navigability. Nav paths are drawn between reachable systems at mid-zoom.

---

## Galaxy Shape

The galaxy is built from four structural zones that blend continuously using smoothstep
interpolation. Hard zone boundaries are forbidden — every transition overlaps its
neighbor so no seam is visible. All radii are expressed as percentages of `galaxy_radius`
so the shape scales correctly regardless of absolute galaxy size.

### Four-Zone Architecture

**Zone 1 — Core Center**
A dense spherical nucleus. Stars here are tightly packed and predominantly old Population
II stars — redder, dimmer. Y-spread is at its maximum relative to radius, giving the
core a fat spherical appearance rather than a disc.

**Zone 2 — Core Outer**
Transition region from spherical core to flattened disc. Density falls off along a
tunable curve (`core_falloff_curve`). Y-spread begins compressing toward the disc plane.
Stars blend from core red tones toward intermediate color range.

**Zone 3 — Spiral Arms**
Sites of active star formation. Stars follow logarithmic spiral paths with arm width
and tightness varying continuously from core to edge — arms are broader and more tightly
wound near the core, narrower and more open at the outer edge. Stars here are younger
Population I — bluer and brighter. Arm density falls off with a Gaussian perpendicular
to the arm centerline so arms have soft edges, not hard walls.

Logarithmic spiral formula: `r = e^(b × θ)` where `b` controls tightness. Each arm is
an angular offset of `TAU / arm_count` from the previous. Arm tightness and width
interpolate linearly from `arm_tightness_start` at the core to `arm_tightness_end` at
the outer edge — this is what makes arms look wound near center and open at the rim.

**Zone 4 — Galactic Disc**
Thin background scatter filling the space between and beyond the arms. Low density,
mixed stellar population, very flat Y-spread. Gives the galaxy its extended diffuse glow
at the edges.

### Zone Blending

Stars are not assigned to a single zone by hard probability. Instead, each candidate
position accumulates a weighted contribution from all four zones simultaneously using
smoothstep to interpolate zone influence across overlap boundaries. This eliminates the
detached-region artifact that occurs when zones are sampled independently.

The implementing agent chooses the exact blending implementation. The spec requires:
- No visible hard edges at any zone boundary
- Zone overlap regions specified as percentages in `world_config.json`
- Zone boundary overlap of 10–30% of the transition radius

### Color Gradient

Star color correlates with galactic position — core stars are orange-red, outer arm
stars are blue-white. This matches real stellar population distribution (Population II
in core, Population I in arms) and makes the galaxy read correctly at any star count.
Individual star type modulates this base gradient with Gaussian noise for variation.

### Y-Thickness Profile

Disc thickness decreases with radius. The core is fat and roughly spherical; the outer
disc is very thin. Both `height_max_pct` (at core) and `height_min_pct` (at disc edge)
are tunable percentages of `galaxy_radius`. Y-spread at any radius interpolates between
these values using normalized radius. A uniform Y-thickness is not acceptable — it
produces a pancake, not a spiral galaxy.

---

## Nebula Volumes and Sky Rendering

Nebulae are procedurally placed volumes — a center position in galaxy space, a radius,
a color, and an opacity. They do not have geometry. In the sky shader they serve as
**tint and density inputs** to a layered noise field — they do not get sampled per
fragment as geometric volumes.

### Galaxy-Space Noise Field

The nebula appearance in the skybox is driven by domain-warped noise evaluated in
galaxy space. The key insight is that noise is evaluated along `EYEDIR` offset by the
player's current galaxy position — so the noise field exists in galaxy space, not view
space. Jumping to a nearby system shifts the player's position slightly within the
field, making the nebula look similar but from a subtly different angle. Jumping far
across the galaxy drops the player into a completely different region — the sky looks
genuinely alien.

The shader recipe:
- **Coarse noise layer** — large-scale domain-warped noise along `EYEDIR` in galaxy
  space; produces the large void regions and cloud mass boundaries
- **Fine noise layer** — higher frequency noise layered on top; produces internal
  cloud detail, wisps, and filaments
- **Nebula volume tinting** — nebula volumes are passed as shader uniforms; each
  fragment checks proximity of `EYEDIR` against volume centers and blends in the
  volume's color and opacity as a multiplier on the noise result
- **Dark voids** — emerge naturally from noise valleys; no special handling required

The combination produces organic cloud-like regions with genuine dark space between
them — not uniform haze. Color varies across the sky based on which nebula volumes
are dominant in each direction.

### Sky Continuity Across Warps

Because noise is evaluated in galaxy space using the player's galaxy position as an
offset, the nebula sky shifts correctly on warp:

- **Short jump** — sky looks nearly identical, nebula rotates slightly as if the player
  moved through the cloud
- **Long jump** — sky looks substantially different; player is in a new region of the
  noise field with different cloud patterns and nebula colors

This requires passing `player_galaxy_position` as a uniform to the sky shader on each
rebuild. No per-frame update needed — the sky is static within a system.

### Zoom-Dependent Opacity

Nebula opacity is scaled by a `map_zoom` uniform `[0..1]`. At full galaxy map zoom
(`map_zoom = 0`) the nebula contribution is suppressed so the galaxy silhouette reads
cleanly. At close zoom (`map_zoom = 1`) full nebula color and cloud detail are visible.
In normal gameplay the sky renders at a tunable default opacity distinct from the map
zoom path.

Nebula volume count, radii, and color palette are tunable in `world_config.json`. The
implementing agent chooses the domain warp and noise algorithm; the spec requires only
that the result produces visually distinct cloud regions with genuine dark space between
them, and that the sky shifts plausibly between nearby systems.

---

## Skybox Rendering

The skybox uses Godot's `Sky` resource with a custom `ShaderMaterial`. This renders
behind all scene geometry by engine design — no depth buffer involvement, no Z-fighting,
no AABB, no world-space geometry.

### Star Data Upload

`StarField` packs visible star data into two `sampler2D` textures uploaded to the sky
shader each time the skybox is rebuilt:

- **Direction texture** (`rgba32f`) — each texel stores `vec4(normalize(position -
  player_system_position), apparent_size)`. The normalized direction is the star's
  position on the sky dome from the player's current system. Apparent size encodes
  the star's visual dot size in pixels.
- **Color texture** (`rgba8`) — each texel stores `vec4(color.rgb, brightness)`.
  Brightness encodes the star type's luminosity weight (blue giants > 1.0, red
  dwarfs < 0.5).

Textures are sized to accommodate the full backdrop catalog. At 3000 stars a 64×64
texture is sufficient; the shader loops `star_count` texels. No compile-time array
cap, no silent truncation.

The textures are rebuilt once per warp. They do not update during normal gameplay —
the sky is static within a system, which is correct (parallax at stellar distances
from ship movement within a system is imperceptible).

### Sky Shader Logic (per fragment)

```glsl
void sky() {
    vec3 rgb = vec3(0.0);

    // --- Nebula and cloud background (evaluated first, behind stars) ---

    // Evaluate noise in galaxy space so the field shifts correctly on warp.
    // player_galaxy_position is a uniform set once per rebuild.
    vec3 sample_dir = EYEDIR + player_galaxy_position * galaxy_noise_influence;

    // Domain-warped noise: warp the sample point before evaluating noise,
    // producing organic cloud shapes rather than regular noise patterns.
    vec3 warped = sample_dir + noise_warp_strength * vec3(
        noise(sample_dir * coarse_frequency),
        noise(sample_dir * coarse_frequency + vec3(5.2, 1.3, 2.8)),
        noise(sample_dir * coarse_frequency + vec3(9.1, 4.7, 6.3))
    );

    float cloud_density = noise(warped * coarse_frequency);         // large voids and masses
    float cloud_detail  = noise(warped * fine_frequency) * 0.4;    // internal wisps
    float cloud         = clamp(cloud_density + cloud_detail, 0.0, 1.0);

    // Nebula volume tinting — blend in color from nearby volumes.
    // Volumes are packed into a uniform array (small count, < 32).
    vec3 nebula_color = vec3(0.0);
    float nebula_weight = 0.0;
    for (int n = 0; n < nebula_count; n++) {
        float proximity = 1.0 - clamp(
            length(EYEDIR - nebula_dirs[n]) / nebula_angular_radii[n], 0.0, 1.0);
        nebula_color  += nebula_colors[n].rgb * proximity * nebula_colors[n].a;
        nebula_weight += proximity;
    }
    if (nebula_weight > 0.0) nebula_color /= nebula_weight;

    // Apply cloud shape to nebula color; scale by map_zoom opacity
    float nebula_opacity = mix(nebula_base_opacity, 1.0, map_zoom);
    rgb += nebula_color * cloud * nebula_opacity;

    // --- Backdrop stars (rendered on top of nebula) ---
    for (int i = 0; i < star_count; i++) {
        vec4 dir_size  = texture(star_directions, texel_coord(i));
        vec4 col_bright = texture(star_colors,    texel_coord(i));

        float alignment = dot(EYEDIR, dir_size.xyz);
        float threshold = dir_size.w;
        if (alignment < 1.0 - threshold) continue;

        float t    = (alignment - (1.0 - threshold)) / threshold;
        float glow = smoothstep(0.0, 1.0, t) * col_bright.a;
        rgb += col_bright.rgb * glow;
    }

    COLOR = vec4(rgb, 1.0);
}
```

`EYEDIR` is Godot's sky shader built-in — per-fragment world-space view direction with
camera translation stripped. `player_galaxy_position` and all nebula uniforms are set
once per skybox rebuild, not per frame.

### Skybox Rebuild

`StarField.rebuild_skybox(system_position: Vector3)` is called by the Warp system after
a jump completes. It:

1. Recomputes direction vectors for all backdrop stars relative to `system_position`
2. Repacks the direction texture
3. Uploads both textures to the sky shader material
4. Recomputes nebula uniforms for the new position

This runs once per warp, not per frame. Cost is proportional to star count; at 3000
stars it is expected to be imperceptible.

---

## Galactic Map

The galactic map is a UI mode toggled via `GameEventBus.galactic_map_toggled`. It
renders as a `CanvasLayer` drawn over the game world — the underlying 3D scene does not
change or unload.

### Projection

Galaxy positions (3D `Vector3` in galaxy space) are projected to 2D screen coordinates
via a configurable top-down orthographic view. The player can pan and zoom within the
map. Y position in galaxy space contributes a slight vertical offset in the 2D
projection, giving a shallow isometric feel so the galaxy disc has visible thickness.

### Zoom Levels and Information Density

| Zoom level | What the player sees |
|---|---|
| **Full out** | Galaxy silhouette as monochrome point cloud; destination systems glow faintly; no nebula color |
| **Mid** | Nebula color regions fade in as soft washes; reachable destination systems brighten; nav paths appear between reachable systems |
| **Zoomed in** | Full nebula color; individual star colors visible; destination systems labeled; nav paths clearly drawn with jump distance |

Zoom level is a normalized float `[0..1]` passed as `map_zoom` to the rendering layer.
Nebula opacity, destination system brightness, and nav path visibility all key off this
single value.

### Destination System Rendering

- All destination systems render as points in the galactic map
- Systems within warp range of the player's current position render brighter and are
  selectable
- Out-of-range systems are visible but dim and not selectable
- Selecting a reachable system emits `GameEventBus.warp_destination_selected(system_id)`
- The player's current system is always highlighted distinctly

### Nav Paths

Nav paths are lines drawn between the player's current system and all reachable systems.
At mid and close zoom, paths extend transitively to show multi-hop routes. Path rendering
is illustrative — routing logic belongs to a future Navigation spec.

---

## Core Data Model

### StarRecord

```gdscript
class StarRecord:
    var id: int                    # Unique catalog index
    var galaxy_position: Vector3   # Position in galaxy space (not world/scene space)
    var sky_direction: Vector3     # normalized(galaxy_position - player_system_position)
                                   # recomputed on each warp; runtime only
    var is_destination: bool       # true = navigable system; false = backdrop only
    var star_type: StringName      # &"red_dwarf", &"yellow_dwarf", &"blue_giant", etc.
    var color: Color               # Derived from star_type at generation
    var apparent_size: float       # Angular size on sky dome; derived from type luminosity
    var brightness: float          # Luminosity weight; blue giants > 1.0, red dwarfs < 0.5

    # Destination systems only:
    var system_id: StringName      # Stable unique name (e.g. "sys_00421")
    var faction_id: StringName     # Deferred to Economy spec
    var warp_range: float          # Max distance from which this system can be jumped to
```

### NebulaVolume

```gdscript
class NebulaVolume:
    var id: int
    var galaxy_position: Vector3
    var radius: float
    var color: Color
    var opacity: float             # Base opacity before map_zoom scaling
```

### StarField (Autoload)

| Property | Type | Description |
|---|---|---|
| `_catalog` | `Array[StarRecord]` | Full star catalog; always in memory |
| `_destinations` | `Array[StarRecord]` | Filtered subset; destination systems only |
| `_nebulae` | `Array[NebulaVolume]` | Nebula catalog; always in memory |
| `_galaxy_seed` | `int` | Master seed from world_config.json |
| `_current_system` | `StarRecord` | The system the player currently occupies |
| `_sky_material` | `ShaderMaterial` | Reference to the active sky shader material |

---

## Key Algorithms

### Galaxy Generation

```gdscript
func generate_catalog(seed: int, config: Dictionary) -> void:
    PerformanceMonitor.begin("StarField.generate")

    var rng := RandomNumberGenerator.new()
    rng.seed = seed

    # --- Backdrop stars ---
    for i in config.backdrop_star_count:
        var record := StarRecord.new()
        record.id = i
        record.is_destination = false
        record.galaxy_position = _sample_galaxy_position(rng, config)
        record.star_type = _pick_star_type(rng, config.star_type_weights)
        _apply_type_appearance(record, config.star_types[record.star_type], rng)
        _catalog.append(record)

    # --- Destination systems ---
    # Use a separate rng branch so destination count doesn't affect backdrop layout
    var dest_rng := RandomNumberGenerator.new()
    dest_rng.seed = seed ^ 0xDEADBEEF
    for i in config.destination_system_count:
        var record := StarRecord.new()
        record.id = _catalog.size()
        record.is_destination = true
        record.galaxy_position = _sample_galaxy_position(dest_rng, config)
        record.system_id = "sys_%05d" % i
        record.star_type = _pick_star_type(dest_rng, config.star_type_weights)
        _apply_type_appearance(record, config.star_types[record.star_type], dest_rng)
        record.warp_range = dest_rng.randf_range(
            config.warp_range_min, config.warp_range_max)
        _catalog.append(record)
        _destinations.append(record)

    # --- Nebulae ---
    var neb_rng := RandomNumberGenerator.new()
    neb_rng.seed = seed ^ 0xCAFEBABE
    for i in config.nebula_count:
        var vol := NebulaVolume.new()
        vol.id = i
        vol.galaxy_position = _sample_nebula_position(neb_rng, config)
        vol.radius = neb_rng.randf_range(config.nebula_radius_min, config.nebula_radius_max)
        vol.color = _pick_nebula_color(neb_rng, config.nebula_colors)
        vol.opacity = neb_rng.randf_range(0.3, 0.8)
        _nebulae.append(vol)

    PerformanceMonitor.end("StarField.generate")
    PerformanceMonitor.set_count("StarField.backdrop_count", _catalog.size() - _destinations.size())
    PerformanceMonitor.set_count("StarField.destination_count", _destinations.size())
```

### Skybox Rebuild

```gdscript
func rebuild_skybox(system_position: Vector3) -> void:
    PerformanceMonitor.begin("StarField.rebuild_skybox")

    var dir_image := Image.create(64, 64, false, Image.FORMAT_RGBAF)
    var col_image := Image.create(64, 64, false, Image.FORMAT_RGBA8)

    for i in _catalog.size():
        var star := _catalog[i]
        star.sky_direction = (star.galaxy_position - system_position).normalized()
        var x := i % 64
        var y := i / 64
        dir_image.set_pixel(x, y, Color(
            star.sky_direction.x,
            star.sky_direction.y,
            star.sky_direction.z,
            star.apparent_size))
        col_image.set_pixel(x, y, Color(
            star.color.r, star.color.g, star.color.b,
            star.brightness))

    _sky_material.set_shader_parameter("star_directions",
        ImageTexture.create_from_image(dir_image))
    _sky_material.set_shader_parameter("star_colors",
        ImageTexture.create_from_image(col_image))
    _sky_material.set_shader_parameter("star_count", _catalog.size())

    # Pass galaxy position so the noise field shifts correctly per system
    _sky_material.set_shader_parameter("player_galaxy_position", system_position)
    _upload_nebula_uniforms(system_position)

    PerformanceMonitor.end("StarField.rebuild_skybox")
```

---

## JSON Data Format

### world_config.json (starfield block)

```json
{
  "starfield": {
    "galaxy_seed": 8675309,
    "backdrop_star_count": 8000,
    "destination_system_count": 400,

    "galaxy_radius": 100000.0,

    "zone_core_center": {
      "radius_pct": 8,
      "height_pct": 6,
      "density": 0.5
    },
    "zone_core_outer": {
      "radius_pct": 25,
      "height_pct": 12,
      "density": 0.3,
      "falloff_curve": 1.2
    },
    "zone_arms": {
      "start_radius_pct": 10,
      "end_radius_pct": 90,
      "arm_count": 2,
      "arm_tightness_start": 0.3,
      "arm_tightness_end": 0.1,
      "arm_width_start": 0.35,
      "arm_width_end": 0.15,
      "density": 0.6
    },
    "zone_disc": {
      "radius_pct": 100,
      "height_min_pct": 1,
      "height_max_pct": 8,
      "density": 0.2
    },
    "zone_overlap_pct": 15,

    "color_core": [1.0, 0.6, 0.4],
    "color_outer": [0.6, 0.8, 1.0],
    "color_variation": 0.25,

    "nebula_count": 24,
    "nebula_radius_min": 8000.0,
    "nebula_radius_max": 28000.0,
    "nebula_colors": [
      [0.8, 0.3, 0.2],
      [0.3, 0.5, 0.9],
      [0.6, 0.8, 0.4],
      [0.9, 0.6, 0.2]
    ],

    "nebula_sky_shader": {
      "galaxy_noise_influence": 0.00002,
      "coarse_frequency": 1.2,
      "fine_frequency": 4.5,
      "noise_warp_strength": 0.6,
      "nebula_base_opacity": 0.35
    },

    "warp_range_min": 8000.0,
    "warp_range_max": 20000.0,

    "star_type_weights": {
      "red_dwarf":    0.60,
      "yellow_dwarf": 0.25,
      "blue_giant":   0.08,
      "neutron_star": 0.05,
      "white_dwarf":  0.02
    },

    "star_types": {
      "red_dwarf":    { "color": [1.0, 0.3, 0.1], "brightness": 0.35, "apparent_size": 0.0004 },
      "yellow_dwarf": { "color": [1.0, 0.9, 0.5], "brightness": 0.70, "apparent_size": 0.0006 },
      "blue_giant":   { "color": [0.5, 0.7, 1.0], "brightness": 1.40, "apparent_size": 0.0012 },
      "neutron_star": { "color": [0.8, 0.9, 1.0], "brightness": 0.90, "apparent_size": 0.0003 },
      "white_dwarf":  { "color": [0.95, 0.97, 1.0],"brightness": 0.50, "apparent_size": 0.0004 }
    }
  }
}
```

---

## Performance Instrumentation

Add these metric names to the `PerformanceMonitor` canonical table:

| Metric | Name |
|---|---|
| Star catalog generation | `StarField.generate` |
| Skybox rebuild | `StarField.rebuild_skybox` |
| Total backdrop stars | `StarField.backdrop_count` |
| Total destination systems | `StarField.destination_count` |

The skybox rebuild is the only hot operation and runs once per warp, not per frame.
Normal gameplay has zero per-frame CPU cost from this system — the sky shader runs
entirely on the GPU.

---

## Files

| Path | Description |
|---|---|
| `core/starfield/StarField.gd` | Autoload; catalog owner, skybox rebuilder, galactic map data provider |
| `core/starfield/StarRecord.gd` | Data class for a single star or destination system |
| `core/starfield/NebulaVolume.gd` | Data class for a nebula volume |
| `core/starfield/galaxy_sky.gdshader` | Custom sky shader; renders backdrop stars and nebulae |
| `ui/galactic_map/GalacticMap.tscn` | CanvasLayer; galactic map UI |
| `ui/galactic_map/GalacticMap.gd` | Map rendering, zoom, pan, system selection |
| `data/world_config.json` | Extended with `starfield` block |

---

## Dependencies

| Dependency | Reason |
|---|---|
| `PerformanceMonitor.gd` | Instrumentation; must be registered before StarField init |
| `GameEventBus.gd` | Receives `galactic_map_toggled`; emits `warp_destination_selected` |
| `data/world_config.json` | Galaxy seed and all generation parameters |
| Warp system | Calls `StarField.rebuild_skybox()` after each jump; Warp spec is a future dependency |

---

## Assumptions

- Galaxy scale values are first-pass estimates; expect significant tuning during
  playtesting to make distances feel right
- `backdrop_star_count: 8000` is a baseline; GPU shader cost at this count is expected
  to be negligible but should be profiled on target hardware
- The four-zone blending algorithm is an implementation detail deferred to the
  implementing agent; the spec requires no visible seams at zone boundaries and a
  recognizable spiral galaxy silhouette
- The logarithmic spiral arm formula is specified; the agent chooses how to distribute
  stars along it (uniform, Gaussian, Poisson — implementation's choice)
- Destination system `faction_id` and economy data format deferred to Economy spec
- Multi-hop route rendering in the galactic map is illustrative only; routing logic
  deferred to a future Navigation spec
- Nebula volumes do not have gameplay effects at MVP (no visibility reduction, no
  hazard); deferred to a future environmental spec
- The galactic map's 2D projection math (pan, zoom, coordinate transforms) is an
  implementation detail deferred to the implementing agent

---

## Success Criteria

- [ ] `StarField` generates a deterministic catalog from the same seed every run
- [ ] Changing `galaxy_seed` produces a completely different galaxy with different
      spiral arm layout, nebula placement, and destination system positions
- [ ] The skybox renders with no depth buffer artifacts, Z-fighting, or clipping at
      any camera angle
- [ ] The skybox visibly shifts star positions after a warp jump (stars in a
      different part of the galaxy are in different screen positions)
- [ ] Blue giants are visually larger and brighter than red dwarfs in the skybox
- [ ] The galaxy core is visibly denser and redder than the outer arms
- [ ] Spiral arms are visible as distinct structures with no hard edges at zone boundaries
- [ ] The galaxy disc is visibly thicker at the core than at the outer edge
- [ ] Nebula volumes produce visible soft color regions in the skybox
- [ ] At full galactic map zoom, the galaxy reads as a clean monochrome silhouette
      with spiral arm structure visible
- [ ] At mid galactic map zoom, nebula color regions fade in without harsh edges
- [ ] Destination systems are visually distinguishable from backdrop stars in the
      galactic map at all zoom levels
- [ ] Reachable destination systems glow distinctly; out-of-range systems are dim
- [ ] The skybox renders nebula regions as organic cloud-like forms with genuine dark
      space between them — not uniform haze or plain noise
- [ ] Nebula colors vary across the sky based on nearby nebula volume tinting
- [ ] Jumping to a nearby system produces a subtly shifted nebula sky; jumping far
      produces a substantially different sky
- [ ] Nebula opacity is suppressed at full galactic map zoom and rich when zoomed in
- [ ] Selecting a reachable system emits `warp_destination_selected` on GameEventBus
- [ ] `StarField.generate` and `StarField.rebuild_skybox` metrics appear in the
      PerformanceMonitor overlay
- [ ] Skybox rebuild completes without a visible frame hitch after a warp jump
