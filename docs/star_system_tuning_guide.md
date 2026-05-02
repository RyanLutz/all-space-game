# Star System — Tuning Guide

Everything in the star system is controlled by a single JSON file:
**`data/world_config.json`** → `"galaxy"` block.

No recompile. Change the file, run the scene, see the result.

---

## The Three Layers

Stars have three visual layers depending on how close the camera is.

```
Far away  ──────────────────────────────────────────  Close
          LOD 0 (points)  LOD 1 (glow)  LOD 2 (mesh)
```

- **LOD 0** — the whole galaxy rendered as coloured pixel-points in one draw call. Visible at any distance.
- **LOD 1** — a screen-space glow disc. Takes over from the point when you zoom into a sector.
- **LOD 2** — a real 3D sphere with roiling plasma surface, atmosphere layers, a corona halo, and a dynamic light. Only spawns when you fly close to a destination star.

**Backdrop stars** (stars far off the play plane — high Y) only ever reach LOD 1. They never spawn a 3D mesh regardless of camera distance.

---

## Galaxy Layout

```json
"seed": 8675309
```
Change this integer to generate a completely different galaxy. Every other number stays the same — only the layout changes. Use any integer.

```json
"star_count": 3000
```
Total number of stars. 3000 is the baseline; the system stays under 1 ms per frame at this count. Going higher is possible but should be re-profiled.

```json
"galaxy_radius": 500000.0
"galaxy_thickness": 8000.0
```
Galaxy disc size in world units. `radius` is the XZ spread; `thickness` is the Y spread. Stars with a Y position within `destination_y_threshold` of zero become flyable destination stars; the rest are backdrop.

```json
"destination_y_threshold": 1200.0
```
Stars with `|y| <= 1200` become destination stars (get a 3D mesh + exclusion zone when close). Stars beyond this are backdrop-only.

```json
"exclusion_margin": 1.4
```
Multiplier on a star's visual radius to set the no-fly exclusion zone. `1.4` means the exclusion sphere is 40% larger than the visual star body. Increase to push ships further away; decrease to let ships skim closer.

---

## Star Type Mix

```json
"star_type_weights": {
  "red_dwarf":    0.60,
  "yellow_dwarf": 0.25,
  "blue_giant":   0.08,
  "neutron_star": 0.05,
  "white_dwarf":  0.02
}
```
These weights must add up to 1.0. Shift weight between types to change the galaxy's character — a high `blue_giant` weight gives a bright, blue-tinted galaxy; a high `neutron_star` weight gives a sparse, ghostly look.

---

## Per-Type Properties

Each star type under `"star_types"` has four settings:

```json
"yellow_dwarf": {
  "color": [1.0, 0.9, 0.5, 1.0],
  "radius_range": [1200, 2000],
  "light_energy_range": [2.0, 4.0],
  "light_range_multiplier": 8.0
}
```

| Key | What it controls |
|---|---|
| `color` | RGBA colour of the star. Used at all three LOD levels — point, glow, and mesh surface. |
| `radius_range` | `[min, max]` visual radius in world units. Each star gets a random value in this range at generation. |
| `light_energy_range` | `[min, max]` OmniLight3D intensity when the LOD 2 mesh is active. Higher = brighter local lighting on ships and asteroids nearby. |
| `light_range_multiplier` | OmniLight3D range = `radius × this`. Controls how far the star's light reaches. |

---

## LOD Distances and Crossfade

```json
"lod1_distance": 80000.0
"lod2_spawn_distance": 8000.0
"lod_crossfade_frames": 30
```

| Key | What it controls |
|---|---|
| `lod1_distance` | Camera distance at which a star switches from LOD 0 (point) to LOD 1 (glow). At 80 000 units you're in sector-level zoom. |
| `lod2_spawn_distance` | Camera distance at which the LOD 2 mesh spawns. At 8 000 units you're approaching a star. |
| `lod_crossfade_frames` | How many frames the LOD transition takes. `30` = 0.5 seconds at 60 fps. Set lower (e.g. `10`) for snappier transitions; set higher (e.g. `60`) for a longer dissolve. Setting `1` effectively disables crossfade. |

**Rule of thumb:** `lod2_spawn_distance` should be at least 4× the largest star radius so the mesh never pops in while already filling the screen.

---

## Glow Appearance (LOD 0 + LOD 1)

These control how stars look when they're distant points or glowing discs.

```json
"min_pixel_radius": 2.0
```
Minimum screen size of a star in pixels. This floor applies to **both** the LOD 0 point and the LOD 1 glow, so they match perfectly at the transition distance. Increase to make distant stars more visible; decrease for a sparser, dimmer galaxy.

```json
"glow_world_radius_multiplier": 3.0
```
Scales a star's visual radius into the screen-space glow disc radius. A value of `3.0` means the glow halo is 3× the star's world radius. Increase for puffier, dreamier glows; decrease for tight, point-like stars.

```json
"glow_max_pixel_radius": 64.0
```
Hard cap on how large a glow can get in pixels. Prevents nearby (but not yet LOD 2) stars from flooding the screen with a massive disc. `64` pixels is roughly a thumb-width on a 1080p monitor.

```json
"glow_intensity": 1.5
```
Overall brightness multiplier fed into the bloom pipeline. Increase to make stars flare more aggressively through Godot's post-process bloom; decrease for subtler glows.

```json
"glow_core_radius": 0.15
```
The fraction of the glow disc occupied by the tight bright inner core (0 = all soft halo, 1 = all hard core). `0.15` gives a small hot centre with a wide soft halo. Increase (e.g. `0.40`) for a sharper star-like spike; decrease (e.g. `0.05`) for a pure fog-ball look.

```json
"screen_pass_max_stars": 256
```
Maximum number of stars uploaded to the glow shader per frame. Hard-capped at 256 (matches the shader array size). Reducing this improves GPU fragment cost at sector zoom but may cause distant stars to lose their glow if too many are in range.

---

## Close-Range Mesh (LOD 2)

### Sphere sizes

```json
"core_radius_scale": 1.0
"atmosphere_inner_scale": 1.04
"atmosphere_outer_scale": 1.10
"corona_scale": 3.5
```

All scales are multipliers on `StarRecord.radius` (the randomised world-unit radius). The corona must be noticeably larger than the atmosphere layers or it will clip. Keep the ordering: `core < inner < outer < corona`.

### Surface plasma

```json
"surface_noise_scale": 2.5
"surface_flow_speed": 0.05
"surface_brightness": 1.4
"surface_contrast": 1.6
```

| Key | What it controls |
|---|---|
| `surface_noise_scale` | Zoom level of the plasma noise pattern. Lower = larger churning cells; higher = fine granular texture. |
| `surface_flow_speed` | How fast the plasma pattern animates. `0.05` is slow and majestic. `0.3` is visibly churning. |
| `surface_brightness` | Base luminance multiplier. Push above `2.0` to make the star feel blinding when close. |
| `surface_contrast` | Sharpness of dark-to-bright transitions in the plasma. Below `1.0` looks flat; above `2.5` looks very spiky. |

### Atmosphere layers

```json
"atmosphere_inner_alpha": 0.55
"atmosphere_outer_alpha": 0.30
"atmosphere_inner_speed": 0.08
"atmosphere_outer_speed": 0.03
```

The two atmosphere sphere layers wrap the core and rotate independently. `alpha` controls their translucency (0 = invisible, 1 = fully opaque). `speed` controls their individual rotation rate — the counter-rotation between layers gives the parallax depth effect.

### Corona halo

```json
"corona_intensity": 1.8
"corona_inner_falloff": 0.18
"corona_outer_falloff": 1.0
```

The corona is a camera-facing additive billboard. It uses the same two-component model as the LOD 1 glow, so the LOD 1→2 transition is continuous in character.

| Key | What it controls |
|---|---|
| `corona_intensity` | Additive brightness. Feeds directly into post-process bloom. `3.0+` creates dramatic flare; `0.8` is a subtle shimmer. |
| `corona_inner_falloff` | Normalised radius `[0,1]` where the tight bright core ends and the soft halo begins. Keep this smaller than `outer_falloff`. |
| `corona_outer_falloff` | Normalised radius where the corona fades to zero. `1.0` = full quad width. Lower values tighten the disc. |

### Dynamic light

```json
"light_attenuation": 1.0
```

Controls the OmniLight3D falloff curve. `1.0` = physically correct inverse-square (realistic). Lower values (e.g. `0.5`) give a flatter, wider pool of light that reaches ships and asteroids further away. Higher values (e.g. `2.0`) makes the light fall off very sharply right outside the corona.

---

## Quick Recipes

**Denser, more crowded galaxy**
```json
"star_count": 5000,
"galaxy_radius": 400000.0
```

**Sparse, lonely galaxy with dramatic stars**
```json
"star_count": 800,
"blue_giant weight": 0.30,
"glow_intensity": 2.5
```

**Tighter sector zoom — LOD 1 kicks in sooner**
```json
"lod1_distance": 40000.0
```

**Faster crossfade (snappier feel)**
```json
"lod_crossfade_frames": 10
```

**Bigger, puffier glows**
```json
"glow_world_radius_multiplier": 5.0,
"glow_max_pixel_radius": 96.0,
"glow_core_radius": 0.08
```

**More violent plasma surface**
```json
"surface_flow_speed": 0.20,
"surface_contrast": 2.2,
"surface_brightness": 1.8
```

**Dramatic close-range corona**
```json
"corona_scale": 5.0,
"corona_intensity": 3.0,
"corona_inner_falloff": 0.10
```

---

## What Requires Code to Change

Most things do not. The items below do require code changes:

| Change | Why code needed |
|---|---|
| Adding a new star type (e.g. `black_hole`) | Must add an entry to `star_types` **and** re-run `_pick_star_type()` which already handles arbitrary types — actually JSON-only is fine as long as the key matches a `star_type_weights` entry |
| More than 256 stars in the glow shader | `MAX_SCREEN_PASS_STARS` const in `StarRegistry.gd` and `MAX_STARS` const in `star_screen_pass.gdshader` must match and both be changed |
| LOD 3 (even closer detail) | New LOD level in `_update_lod()` |
| Exclusion zone physics (push ship away) | A physics/nav system needs to listen to `GameEventBus.star_exclusion_entered` |
| Galaxy arm spiral bias | `_sample_galaxy_radius()` in `StarRegistry.gd` |
