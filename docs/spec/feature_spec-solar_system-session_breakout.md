# SolarSystem — Implementation Session Breakout

Sessions are ordered by dependency. Each session produces a working, testable artifact
before the next begins. All sessions reference `feature_spec-solar_system.md` as the
authoritative spec.

---

## Session A — System Generator + Flyable Test Scene
**Model: Claude Sonnet** (novel procedural generation, architectural foundation)
**Effort: Large**

The foundation session. Gets the system layout generator correct and produces a
flyable test scene before any other session begins. Everything downstream depends on
the generator output being deterministic and correct.

**Delivers:**
- `SolarSystemGenerator.gd` — pure generation logic; no scene manipulation; returns
  a Dictionary manifest from `system_id` + `galaxy_seed`
- Archetype picker and per-archetype parameter ranges from `solar_system_archetypes.json`
- `_generate_stars()` — single and binary star configs with `star_center_depth` and
  `exclusion_radius` derived from JSON visual block
- `_generate_planets()` — ordered by orbital radius; planet type from archetype weights;
  moon count per planet; `planet_center_depth` and `visual_radius` from JSON ranges
- `_generate_belts()` — belt regions positioned between planet orbital radii;
  `inner_radius`, `outer_radius`, `density_multiplier` from JSON belt block
- Hand-authored override check: if `res://content/systems/<system_id>/system.json`
  exists, load it directly — skip all procedural logic
- `SolarSystem.gd` — reads the manifest and instantiates all nodes into the scene tree:
  `StarGroup`, `PlanetGroup`, `Star.gd` nodes, `Planet.gd` nodes (no physics, visual only)
- `Star.gd` — sphere mesh at `Y = -star_center_depth`; `OmniLight3D`; placeholder
  `ExclusionRingMesh` at Y=0 (visual indicator only, no damage yet)
- `Planet.gd` — sphere mesh at `Y = -planet_center_depth`; orbital drift in `_process`;
  `moon_mode` flag for moons orbiting a parent planet; `add_to_group("physics_bodies")`
  stub (no physics collision on planets)
- `Station.gd` — placement node only; parented to correct planet; default offset;
  docking logic deferred to future Station spec
- `solar_system_archetypes.json` — all archetypes, generation ranges, visual block, belt
  block, warp block (placeholder values; tuning pass is Session D)
- A standalone test scene: player ship spawns in a generated system; all planets visible;
  star visible with exclusion ring; ChunkStreamer not yet connected (empty open space)
- `PerformanceMonitor.begin/end("SolarSystem.generate")` and
  `PerformanceMonitor.set_count("SolarSystem.planet_count", ...)` instrumented

**You validate:** Does the system look like a system? Is the star correctly positioned
below the play plane? Are planets visible as orbs with orbital drift? Do binary stars
generate two exclusion rings? Does the same `system_id` + seed always produce the
same layout?

**Not in scope:** Exclusion zone damage, WarpDrive, OriginShifter, ChunkStreamer belt
integration, `GameEventBus` signals.

---

## Session B — Star Exclusion Zone + WarpDrive State Machine
**Model: Claude Sonnet** (state machine logic, physics integration novelty)
**Effort: Medium**

Wires the star as a danger and gives the player in-system fast travel. Requires
Session A's test scene and the player ship having `apply_damage()`.

**Delivers:**
- `Star.gd` exclusion zone: `_physics_process` checks XZ distance to all ships in
  group `"ships"`; calls `ship.apply_damage(damage_per_second * delta, "heat", pos)`
  for ships inside `exclusion_radius`
- `GameEventBus.exclusion_zone_entered` and `exclusion_zone_exited` emitted when ships
  cross the boundary (add these to `GameEventBus.gd` per the signals spec)
- `WarpDrive.gd` — component attached to the player ship node; reads ship input;
  state machine: `IDLE → SPOOLING → ACTIVE → DECELERATING`
- Spool VFX placeholder (print to console or simple color tint; full VFX deferred)
- `warp_multiplier` property set on the ship's physics component during ACTIVE state;
  review `feature_spec-physics_and_movement.md` and the existing implementation to
  determine the cleanest integration point for speed scaling
- Interrupt conditions: single-hit damage above `interrupt_damage_threshold` (listen
  to `ship_damaged`) and approach within `exclusion_abort_radius` of any star
- `GameEventBus.warp_state_changed` and `warp_interrupted` emitted on transitions
- All warp parameters in `solar_system_archetypes.json` `warp` block — no hardcoded values
- `PerformanceMonitor` — no new hot-path metrics; warp state transitions are rare events

**You validate:** Fly into the exclusion zone — does the ship take continuous heat
damage? Hold warp key for `spool_time` seconds — does warp engage and visibly increase
speed? Take a large hit during ACTIVE warp — does it cancel to DECELERATING? Approach
the star exclusion zone at warp — does auto-abort trigger before crossing the boundary?

**Not in scope:** OriginShifter, ChunkStreamer belt integration, VFX effects.

---

## Session C — OriginShifter + ChunkStreamer Belt Integration
**Model: Claude Haiku** (additive wiring of existing systems, low novelty)
**Effort: Medium**

Connects the system to the streaming world. Requires Session A's test scene and the
existing `ChunkStreamer` implementation.

**Delivers:**
- `OriginShifter.gd` — subscribes to `GameEventBus.chunk_loaded`; checks player
  distance from origin against `shift_threshold`; when triggered, shifts all nodes in
  group `"physics_bodies"` and `_solar_system_root` by the offset; emits
  `GameEventBus.origin_shifted(offset)`
- `add_to_group("physics_bodies")` added to `Ship.gd` and `Asteroid.gd` — additive
  change, no behavior changes
- `SolarSystem.get_belt_context_at(world_pos: Vector3) -> Dictionary` implemented:
  converts world pos to system-absolute coords using `_world_origin`; checks
  `_belt_regions`; returns `{ "in_belt": bool, "density_multiplier": float,
  "asteroid_type_weights": Dictionary }`
- `ChunkStreamer._populate_asteroids` modified to call `get_belt_context_at()` before
  generating each chunk's content; applies `density_multiplier` when `in_belt` is true
- `GameEventBus.system_loaded(system_id)` emitted in `SolarSystem._ready()` after
  full instantiation; `ChunkStreamer` waits for this signal before first streaming pass
- `GameEventBus.system_unloaded(system_id)` emitted when `SolarSystem` exits the tree
- `PerformanceMonitor.begin/end("SolarSystem.origin_shift")`,
  `PerformanceMonitor.begin/end("SolarSystem.orbit_update")`,
  `PerformanceMonitor.set_count("SolarSystem.belt_count", ...)`,
  `PerformanceMonitor.set_count("SolarSystem.station_count", ...)`

**You validate:** Fly out far enough to trigger an origin shift — do ships and asteroids
continue behaving correctly afterward (no pop, no jitter)? Fly into a belt region — are
asteroid fields noticeably denser than open space? Does ChunkStreamer wait correctly for
`system_loaded` before spawning content?

**Not in scope:** Interstellar warp (future Warp spec), starfield skybox.

---

## Session D — JSON Tuning Pass + Success Criteria Checklist
**Model: Claude Haiku** (low novelty, wiring and verification)
**Effort: Small**

Polish pass. All systems from Sessions A–C are running. This session tunes values and
closes out the spec's success criteria.

**Delivers:**
- Tuning pass on `solar_system_archetypes.json`:
  - `star_center_depth` / `visual_radius` so the star reads as dangerous from the
    pilot camera view — threatening, not invisible
  - `planet_center_depth` / `visual_radius` ranges so planets read clearly at the
    camera's default shallow angle
  - `warp_speed_multiplier` so a full system crossing takes 30–90 seconds at max warp
  - `exclusion_radius` single and binary values
  - Belt `density_multiplier` range so belts feel meaningfully denser than open space
  - Orbital speed range so planets visibly drift over a 5-minute session
- Hand-authored override path verified: place a `system.json` in
  `res://content/systems/test_authored/`; confirm it loads exactly as written
- All `PerformanceMonitor` metrics verified in the overlay (F3):
  `SolarSystem.orbit_update`, `SolarSystem.origin_shift`, `SolarSystem.planet_count`,
  `SolarSystem.station_count`, `SolarSystem.belt_count`
- Orbit update cost confirmed below 0.1ms with a maximum system (20 planets × 10 moons);
  if above budget, batch planet positions in a single loop in `SolarSystem._process`
  rather than per-Planet `_process`
- Full success criteria checklist from `feature_spec-solar_system.md` run and checked

**You validate:** Run every item in the `feature_spec-solar_system.md` success criteria
checklist. Mark each passing item with `[x]` in the spec.

---

## Dependency Graph

```
Session A (Generator + Flyable Scene)
    └── Session B (Exclusion Zone + WarpDrive)
    └── Session C (OriginShifter + ChunkStreamer)
            └── Session D (Tuning + Success Criteria)
```

Sessions B and C can run in parallel after Session A completes.

---

## Pre-Session Checklist

Before any session begins, confirm the following are available:

- `GameEventBus.gd` — Solar System and Warp signals defined (see
  `feature_spec-game_event_bus_signals.md`; added 2026-05-04)
- `PerformanceMonitor.gd` — registered and available via ServiceLocator
- `ChunkStreamer` implementation — exists and streams asteroid content
- `Ship.apply_damage(amount: float, type: String, position: Vector3)` — method exists
  on Ship.gd (needed by Session B exclusion zone damage)
- `feature_spec-physics_and_movement.md` — read before Session B; determine the correct
  mechanism for `warp_multiplier` integration with the existing physics system
- `data/solar_system_archetypes.json` — created in Session A; must exist before
  Session D tuning begins

---

## Model Assignment Rationale

| Session | Model | Reason |
|---|---|---|
| A | Sonnet | Novel generation math (archetype blending, orbital layout), architectural foundation, high blast radius if generator is wrong |
| B | Sonnet | State machine with physics integration; warp multiplier hookup requires reading existing physics implementation before deciding approach |
| C | Haiku | Additive wiring of existing systems (ChunkStreamer, OriginShifter); low novelty, clear interfaces defined in spec |
| D | Haiku | Numeric tuning + checklist verification; no new architecture |
