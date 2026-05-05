# StarField — Implementation Session Breakout

Sessions are ordered by dependency. Each session produces a working, testable artifact
before the next begins.

---

## Session 1 — Galaxy Generator + Testable Map Scene
**Model: Claude Sonnet** (high novelty, architectural foundation)
**Effort: Large**

The most important session. Gets the galaxy shape right before anything else is built.
Everything downstream depends on the catalog being correct.

**Delivers:**
- `StarField.gd` — catalog generation only (no skybox, no UI)
- `StarRecord.gd` and `NebulaVolume.gd` data classes
- Four-zone generator with smoothstep blending, logarithmic spiral arms,
  Y-thickness profile, color gradient
- Separate RNG branches for backdrop stars, destination systems, nebulae
- A standalone test scene: top-down `Camera3D` looking at a `MultiMeshInstance3D`
  rendering the full catalog as colored points — this IS the galactic map shape preview
- Pan and zoom in the test scene so you can inspect the galaxy at different scales
- All params wired to `world_config.json`; seed changes regenerate everything

**You validate:** Does the galaxy look like a galaxy? Are spiral arms visible? Is the
core dense and red? Are destination systems reasonably distributed? Tune JSON until happy.

**Not in scope:** Skybox, nebula rendering, UI, warp integration.

---

## Session 2 — Galactic Map UI Layer
**Model: Claude Haiku** (routine UI work, low novelty)
**Effort: Medium**

Takes the test scene camera and wraps it in a proper UI mode. The MultiMesh from
Session 1 stays — this session adds interaction on top.

**Delivers:**
- `GalacticMap.gd` / `GalacticMap.tscn` as a `CanvasLayer`
- Toggle via `GameEventBus.galactic_map_toggled`
- Destination systems highlighted distinctly from backdrop stars
- Reachable systems glow based on warp range from current position
- Pan and zoom controls (mouse wheel, drag)
- System selection emits `warp_destination_selected(system_id)`
- Three zoom levels with information density scaling (nebula color opacity
  placeholder — actual nebula rendering comes in Session 3)

**You validate:** Can you navigate the map, select a system, read the galaxy shape
clearly at full zoom?

**Not in scope:** Nebula color in the map (placeholder only), actual warp execution.

---

## Session 3 — Skybox + Nebula Rendering
**Model: Claude Sonnet** (novel shader work, galaxy-space noise math)
**Effort: Large**

The visual centerpiece. Requires Session 1 catalog to be final — skybox rebuild reads
from it directly.

**Delivers:**
- `galaxy_sky.gdshader` — custom Godot `Sky` shader
- Backdrop stars rendered via `sampler2D` texture upload (direction + color textures)
- Domain-warped noise nebula field in galaxy space using `player_galaxy_position`
- Nebula volume tinting of noise field
- `map_zoom` uniform wiring for nebula opacity scaling
- `StarField.rebuild_skybox(system_position)` implemented and callable
- Wired to a placeholder warp trigger in the test scene so you can simulate jumping
  between systems and see the sky shift

**You validate:** Does the sky look like you're inside a galaxy? Do nebulae have organic
cloud shapes with dark voids? Does the sky shift plausibly on a simulated warp jump?

**Not in scope:** Actual warp scene transition (future Warp spec).

---

## Session 4 — Galactic Map Nebula Color + Polish
**Model: Claude Haiku** (low novelty, wiring existing systems together)
**Effort: Small**

Connects the nebula rendering from Session 3 into the galactic map zoom levels.

**Delivers:**
- Nebula color regions fade in at mid galactic map zoom
- `map_zoom` uniform piped from GalacticMap zoom state to sky shader
- Nav path lines between reachable systems at mid/close zoom
- PerformanceMonitor metrics wired and visible in overlay
- Final pass on all success criteria from the spec

**You validate:** Run the full success criteria checklist from `feature_spec-starfield.md`.

---

## Dependency Graph

```
Session 1 (Generator + Map Preview)
    └── Session 2 (Galactic Map UI)
    └── Session 3 (Skybox + Nebula)
            └── Session 4 (Map Nebula + Polish)
```

Sessions 2 and 3 can run in parallel after Session 1 completes.

---

## Model Assignment Rationale

| Session | Model | Reason |
|---|---|---|
| 1 | Sonnet | Novel math (four-zone blending, logarithmic spirals), architectural foundation, high blast radius if wrong |
| 2 | Haiku | UI wiring, event bus hookup, routine Godot patterns |
| 3 | Sonnet | Novel shader work, galaxy-space noise math, no existing reference in project |
| 4 | Haiku | Connecting already-built systems, polish pass |
