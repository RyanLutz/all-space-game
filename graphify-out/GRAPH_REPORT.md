# Graph Report - /home/lutz/Projects/All Space  (2026-05-04)

## Corpus Check
- 2 files · ~92,510 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 175 nodes · 156 edges · 58 communities detected
- Extraction: 85% EXTRACTED · 15% INFERRED · 0% AMBIGUOUS · INFERRED: 24 edges (avg confidence: 0.77)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Community 0|Community 0]]
- [[_COMMUNITY_Community 1|Community 1]]
- [[_COMMUNITY_Community 2|Community 2]]
- [[_COMMUNITY_Community 3|Community 3]]
- [[_COMMUNITY_Community 4|Community 4]]
- [[_COMMUNITY_Community 5|Community 5]]
- [[_COMMUNITY_Community 6|Community 6]]
- [[_COMMUNITY_Community 7|Community 7]]
- [[_COMMUNITY_Community 8|Community 8]]
- [[_COMMUNITY_Community 9|Community 9]]
- [[_COMMUNITY_Community 10|Community 10]]
- [[_COMMUNITY_Community 11|Community 11]]
- [[_COMMUNITY_Community 12|Community 12]]
- [[_COMMUNITY_Community 13|Community 13]]
- [[_COMMUNITY_Community 14|Community 14]]
- [[_COMMUNITY_Community 15|Community 15]]
- [[_COMMUNITY_Community 16|Community 16]]
- [[_COMMUNITY_Community 17|Community 17]]
- [[_COMMUNITY_Community 18|Community 18]]
- [[_COMMUNITY_Community 19|Community 19]]
- [[_COMMUNITY_Community 20|Community 20]]
- [[_COMMUNITY_Community 21|Community 21]]
- [[_COMMUNITY_Community 22|Community 22]]
- [[_COMMUNITY_Community 23|Community 23]]
- [[_COMMUNITY_Community 24|Community 24]]
- [[_COMMUNITY_Community 25|Community 25]]
- [[_COMMUNITY_Community 26|Community 26]]
- [[_COMMUNITY_Community 27|Community 27]]
- [[_COMMUNITY_Community 28|Community 28]]
- [[_COMMUNITY_Community 29|Community 29]]
- [[_COMMUNITY_Community 30|Community 30]]
- [[_COMMUNITY_Community 31|Community 31]]
- [[_COMMUNITY_Community 32|Community 32]]
- [[_COMMUNITY_Community 33|Community 33]]
- [[_COMMUNITY_Community 34|Community 34]]
- [[_COMMUNITY_Community 35|Community 35]]
- [[_COMMUNITY_Community 36|Community 36]]
- [[_COMMUNITY_Community 37|Community 37]]
- [[_COMMUNITY_Community 38|Community 38]]
- [[_COMMUNITY_Community 39|Community 39]]
- [[_COMMUNITY_Community 40|Community 40]]
- [[_COMMUNITY_Community 41|Community 41]]
- [[_COMMUNITY_Community 42|Community 42]]
- [[_COMMUNITY_Community 43|Community 43]]
- [[_COMMUNITY_Community 44|Community 44]]
- [[_COMMUNITY_Community 45|Community 45]]
- [[_COMMUNITY_Community 46|Community 46]]
- [[_COMMUNITY_Community 47|Community 47]]
- [[_COMMUNITY_Community 48|Community 48]]
- [[_COMMUNITY_Community 49|Community 49]]
- [[_COMMUNITY_Community 50|Community 50]]
- [[_COMMUNITY_Community 51|Community 51]]
- [[_COMMUNITY_Community 52|Community 52]]
- [[_COMMUNITY_Community 53|Community 53]]
- [[_COMMUNITY_Community 54|Community 54]]
- [[_COMMUNITY_Community 55|Community 55]]
- [[_COMMUNITY_Community 56|Community 56]]
- [[_COMMUNITY_Community 57|Community 57]]

## God Nodes (most connected - your core abstractions)
1. `ProjectileManager` - 16 edges
2. `GameEventBus signal contract specification` - 8 edges
3. `Neutral dark gray base color field (~#444444)` - 7 edges
4. `Bright red accent paint on hull markings` - 7 edges
5. `Accent marking color (high-chroma red)` - 7 edges
6. `UI Design Specification — tokens & HUD layouts` - 7 edges
7. `ServiceLocator` - 6 edges
8. `Base color (albedo) texture map` - 5 edges
9. `Axum-class fighter surface livery` - 5 edges
10. `Combat VFX System Specification` - 5 edges

## Surprising Connections (you probably didn't know these)
- `GameEventBus cross-system signal bus` --implements--> `GameEventBus signal contract specification`  [EXTRACTED]
  AGENTS.md → docs/feature_spec-game_event_bus_signals.md
- `Star Field System Specification (MVP background)` --semantically_similar_to--> `Star System Specification — galactic LOD stars`  [EXTRACTED] [semantically similar]
  feature_spec-star_field.md → docs/feature_spec-star_system.md
- `CLAUDE.md — Cursor project context` --includes--> `AGENTS.md — project structure notes`  [EXTRACTED]
  CLAUDE.md → AGENTS.md
- `Read docs/agent_brief.md before other work` --references--> `agent_brief.md — read-first agent context`  [EXTRACTED]
  CLAUDE.md → docs/agent_brief.md
- `graphify-first recon: GRAPH_REPORT.md then graph.json` --references--> `GRAPH_REPORT.md — graphify corpus summary`  [EXTRACTED]
  CLAUDE.md → graphify-out/GRAPH_REPORT.md

## Hyperedges (group relationships)
- **Unified Input Interface: Player, AIController, and NavigationController All Feed Ship Physics** — core_spec_unified_input, physics_spec_three_layers, nav_spec_overview, ai_spec_overview, fleet_command_inputmanager [EXTRACTED 1.00]
- **XZ Plane Y=0 Enforcement Applies Across Ships, Projectiles, Asteroids, and Debris** — core_spec_xz_plane_contract, physics_spec_rigidbody_config, weapons_spec_projectile_manager, chunk_spec_asteroid, chunk_spec_debris [EXTRACTED 1.00]
- **All Tunable Values in JSON — ship.json, weapon.json, ai_profiles.json, world_config.json, factions.json** — claude_md_json_tunables_rule, ship_spec_ship_json_schema, weapons_spec_weapon_json, ai_spec_behavior_profile_json, chunk_spec_world_config_json, ship_spec_factions_json [EXTRACTED 1.00]
- **PerformanceMonitor begin/end Required on Every System — Instrumented from Day One** — core_spec_performance_monitor_contract, perf_spec_api, perf_spec_custom_monitors, perf_spec_built_first_rationale, vision_observability [EXTRACTED 1.00]
- **Stacked icon composition: panel, mascot fill, eye detail** — icon_rounded_panel, icon_mascot_vector_group, icon_ocular_detail_group [EXTRACTED 1.00]
- **Red UV islands forming a coordinated accent graphic set on the fighter sheet** — fighter_base_color_vertical_stripe_island, fighter_base_color_chevron_trim_islands, fighter_base_color_arc_crescent_island, fighter_base_color_circular_solid_island, fighter_base_color_red_accent_paint [INFERRED 0.83]
- **Fighter hull: flat albedo + implied material stack** — fighter_base_color_albedo_texture_file, fighter_base_color_uniform_charcoal_surface, fighter_base_color_neutral_pbr_foundation [INFERRED 0.72]
- **Red livery graphic elements on hull texture** — model_fighter_base_color_vertical_stripe, model_fighter_base_color_circular_element, model_fighter_base_color_crescent_element, model_fighter_base_color_symmetrical_angled_pairs, model_fighter_base_color_bright_red_markings [INFERRED 0.84]
- **GameBootstrap autoload cluster — core services through VFX (AGENTS)** — agents_autoload_servicelocator, agents_autoload_gameeventbus, agents_autoload_contentregistry, agents_autoload_projectilemanager, agents_autoload_vfxmanager [INFERRED 1.00]
- **Data-driven tuning: world_config star_field, effect.json types, UITokens constants** — star_field_world_config, combat_vfx_effect_types_table, ui_design_uitokens_autoload [INFERRED 0.72]
- **Graphify output trio — report, HTML viewer, embedded graph data** — graph_report_doc, graph_html_doc, graph_html_vis_raw_embed [INFERRED 1.00]

## Communities

### Community 0 - "Community 0"
Cohesion: 0.22
Nodes (2): Node3D, ProjectileManager

### Community 1 - "Community 1"
Cohesion: 0.15
Nodes (15): Full design intent: docs/core_spec.md, Deviation protocol — written report before spec deviation, agent_brief.md — read-first agent context, AGENTS.md — project structure notes, CLAUDE.md — Cursor project context, graphify-first recon: GRAPH_REPORT.md then graph.json, Read docs/agent_brief.md before other work, Session end: update agent_brief build status + decisions_log (+7 more)

### Community 2 - "Community 2"
Cohesion: 0.14
Nodes (14): Step 18 UI Foundation — implemented, Step 19 Pilot HUD — implemented, 2026-04-29 UI Session 2 Pilot HUD + Radar, UI Design Specification — tokens & HUD layouts, player_ship_changed(ship) — PlayerState emitter, Orbitron OFL.txt — SIL Open Font License 1.1, Reserved Font Name: Orbitron, Orbitron README — variable font wght axis (+6 more)

### Community 3 - "Community 3"
Cohesion: 0.18
Nodes (11): Cross-system comms only via GameEventBus signals, GameEventBus cross-system signal bus, WeaponComponent direct calls MuzzleFlashPlayer & BeamRenderer (no bus), Rationale: bus avoided for high-frequency muzzle — latency, Ordered build steps 1–17 with spec references, development_guide.md — build order & session workflow, GameEventBus signal contract specification, Canonical signal definitions for core/GameEventBus.gd (+3 more)

### Community 4 - "Community 4"
Cohesion: 0.2
Nodes (11): Star Field System Specification (MVP background), Star System Specification — galactic LOD stars, StarField sibling of ChunkStreamer under world root, depth_draw_never — stars never occlude gameplay, Stars fixed in world; parallax from perspective only, PRIMITIVE_POINTS one draw call star field, star_field.gdshader — gl_PointCoord soft circular glow, StarField Node3D + MeshInstance3D ArrayMesh (+3 more)

### Community 5 - "Community 5"
Cohesion: 0.33
Nodes (10): Base color (albedo) texture map, Axum-class fighter surface livery, Accent marking color (high-chroma red), Solid circular red hull mark, Crescent or jagged-bottom red marking, Primary hull base color (matte dark gray field), Minimalist high-contrast industrial sci-fi look, Mirrored angled line pairs (lower layout) (+2 more)

### Community 6 - "Community 6"
Cohesion: 0.2
Nodes (10): Step 17 Combat VFX — in progress, VFXManager combat visual effects (Step 17), gameplay/vfx/ EffectPool, VFXManager, local players, VFXManager subscribes to projectile_hit, shield_hit, ship_destroyed, missile_detonated, Distributed ownership: local weapon effects vs VFXManager pools, 2026-04-25 Phase 17 Session 2 local effect players, Step 17 Combat VFX — feature_spec-combat_vfx.md, Combat VFX System Specification (+2 more)

### Community 7 - "Community 7"
Cohesion: 0.53
Nodes (9): Small horizontal arc or crescent marking (irregular top edge), Symmetric angled chevron or open-diamond trim pair, Solid circular red island (upper-right), Fighter Base Color diffuse (albedo) texture map, Minimal high-contrast sci-fi vehicle livery (gray + red), Neutral dark gray base color field (~#444444), Bright red accent paint on hull markings, UV island layout on a single base-color sheet (+1 more)

### Community 8 - "Community 8"
Cohesion: 0.29
Nodes (2): Node, ServiceLocator

### Community 9 - "Community 9"
Cohesion: 0.4
Nodes (5): Pilot Mode — Direct Thrust + Mouse Aim, Close Follow Camera, Tactical Mode — Fleet RTS, Drag Select, Right-Click Orders, Three Gameplay Modes — Pilot, Tactical, Galactic, Unified Ship Input Interface (input_forward, input_strafe, input_aim_target, input_fire), Four Phases of Play (Personal Pilot → Fleet → Infrastructure → Galactic)

### Community 10 - "Community 10"
Cohesion: 0.5
Nodes (5): Semantic association: standard Godot Engine editor / project joystick-robot logo, Scaled path group: robot head, gear crown, blue face plate (#478cbf), white gear outline, Eye layer: two dark gray circles (#414042) for pupils, Rounded rectangle frame (#363d52 fill, #212532 stroke, rx=14), SVG application icon 128×128 (Godot-style brand mark)

### Community 11 - "Community 11"
Cohesion: 0.5
Nodes (5): Fighter Base Color texture (Blender albedo map), Dark utilitarian / industrial hull color direction, Featureless albedo (no gradients, noise, or markings), Neutral base layer for PBR (detail likely in roughness/normal/metallic), Uniform dark charcoal gray surface (~#444444 RGB)

### Community 12 - "Community 12"
Cohesion: 0.5
Nodes (4): content/effects/ JSON effect definitions, assets/shaders/shield_ripple.gdshader, Effect types: particle_burst, beam, muzzle_flash, explosion, shield_ripple, Projectile trails excluded from phase — deferred

### Community 13 - "Community 13"
Cohesion: 0.67
Nodes (3): All Space Core Spec — Top-Down 3D on XZ Plane, Core Philosophy: Complexity On Demand, All Space — Top-Down 3D Space Simulation Vision

### Community 14 - "Community 14"
Cohesion: 0.67
Nodes (3): Y=0 play plane for positions and velocities, World-space VFX spawn Y=0 enforcement, All world positions/velocities Vector3 (Y=0)

### Community 15 - "Community 15"
Cohesion: 1.0
Nodes (2): Combat MVP — 3D Top-Down Space Combat Simulator, Streaming Map — Chunk-Based Seamless World

### Community 16 - "Community 16"
Cohesion: 1.0
Nodes (2): 2026-04-16 pre-implementation spec audit & 3D cleanup, Core Spec > Feature Spec > agent assumption

### Community 17 - "Community 17"
Cohesion: 1.0
Nodes (2): game_mode_changed(old_mode, new_mode), PilotHUD / TacticalHUD — no mutual references; bus only

### Community 18 - "Community 18"
Cohesion: 1.0
Nodes (1): Sim-Lite Physics — Mass, Momentum, Angular Inertia

### Community 19 - "Community 19"
Cohesion: 1.0
Nodes (1): Observability From Day One — PerformanceMonitor

### Community 20 - "Community 20"
Cohesion: 1.0
Nodes (1): Data-Driven Everything — JSON Configuration Files

### Community 21 - "Community 21"
Cohesion: 1.0
Nodes (1): Modularity as Development Forcing Function — Agent Sessions Stay Focused

### Community 22 - "Community 22"
Cohesion: 1.0
Nodes (0): 

### Community 23 - "Community 23"
Cohesion: 1.0
Nodes (1): 3D Play Plane Contract — All Entities at Y=0, Vector2 Banned

### Community 24 - "Community 24"
Cohesion: 1.0
Nodes (1): Architecture Rules — No Hardcoded Values, No Direct Cross-System Refs

### Community 25 - "Community 25"
Cohesion: 1.0
Nodes (1): Project Structure — Directory Layout

### Community 26 - "Community 26"
Cohesion: 1.0
Nodes (1): SpaceBody Contract — mass, velocity, angular_velocity, apply_damage, apply_impulse

### Community 27 - "Community 27"
Cohesion: 1.0
Nodes (1): PerformanceMonitor Contract — begin/end pairs required on every system

### Community 28 - "Community 28"
Cohesion: 1.0
Nodes (1): Canonical Metric Names — System.method format table

### Community 29 - "Community 29"
Cohesion: 1.0
Nodes (1): Content Architecture — Folder-Per-Item Under /content/

### Community 30 - "Community 30"
Cohesion: 1.0
Nodes (1): One Ship.tscn for All Ship Types — Configured at Spawn Time

### Community 31 - "Community 31"
Cohesion: 1.0
Nodes (1): Physics Summary — RigidBody3D + Jolt, Assisted Steering, Thruster Budget

### Community 32 - "Community 32"
Cohesion: 1.0
Nodes (1): Weapons Summary — JSON Stats, Damage Types, Heat Per Hardpoint, Power Per Ship

### Community 33 - "Community 33"
Cohesion: 1.0
Nodes (1): AI Summary — State Machine IDLE→PURSUE→ENGAGE, JSON Profiles

### Community 34 - "Community 34"
Cohesion: 1.0
Nodes (1): Camera Summary — Camera3D Perspective, Height Zoom, Never Child of Ship

### Community 35 - "Community 35"
Cohesion: 1.0
Nodes (1): World Streaming Summary — Deterministic Chunk Grid, GameEventBus chunk_loaded

### Community 36 - "Community 36"
Cohesion: 1.0
Nodes (1): Build Order — 15-Step Dependency Sequence

### Community 37 - "Community 37"
Cohesion: 1.0
Nodes (0): 

### Community 38 - "Community 38"
Cohesion: 1.0
Nodes (0): 

### Community 39 - "Community 39"
Cohesion: 1.0
Nodes (0): 

### Community 40 - "Community 40"
Cohesion: 1.0
Nodes (0): 

### Community 41 - "Community 41"
Cohesion: 1.0
Nodes (0): 

### Community 42 - "Community 42"
Cohesion: 1.0
Nodes (0): 

### Community 43 - "Community 43"
Cohesion: 1.0
Nodes (0): 

### Community 44 - "Community 44"
Cohesion: 1.0
Nodes (0): 

### Community 45 - "Community 45"
Cohesion: 1.0
Nodes (1): Star Field System Specification

### Community 46 - "Community 46"
Cohesion: 1.0
Nodes (1): Debug Grid Texture

### Community 47 - "Community 47"
Cohesion: 1.0
Nodes (1): ServiceLocator singleton registry

### Community 48 - "Community 48"
Cohesion: 1.0
Nodes (1): ContentRegistry JSON content loader

### Community 49 - "Community 49"
Cohesion: 1.0
Nodes (1): ProjectileManager C# projectile pool

### Community 50 - "Community 50"
Cohesion: 1.0
Nodes (1): No 2D nodes; Vector2 banned for world-space

### Community 51 - "Community 51"
Cohesion: 1.0
Nodes (1): Ship.gd never writes velocity/position for motion — Jolt only

### Community 52 - "Community 52"
Cohesion: 1.0
Nodes (1): ExclusionArea no-fly radius per destination star

### Community 53 - "Community 53"
Cohesion: 1.0
Nodes (1): pool_size 0 disables effect without errors

### Community 54 - "Community 54"
Cohesion: 1.0
Nodes (1): Session 1 Opus — VFX core, pools, GameBootstrap monitors

### Community 55 - "Community 55"
Cohesion: 1.0
Nodes (1): UITokens.gd autoload — color/font constants

### Community 56 - "Community 56"
Cohesion: 1.0
Nodes (1): UITheme.tres — Panel/Label/Button styles from tokens

### Community 57 - "Community 57"
Cohesion: 1.0
Nodes (1): UI.pilot_hud_update / UI.tactical_hud_update metrics

## Knowledge Gaps
- **81 isolated node(s):** `Core Philosophy: Complexity On Demand`, `Four Phases of Play (Personal Pilot → Fleet → Infrastructure → Galactic)`, `Combat MVP — 3D Top-Down Space Combat Simulator`, `Sim-Lite Physics — Mass, Momentum, Angular Inertia`, `Streaming Map — Chunk-Based Seamless World` (+76 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **Thin community `Community 15`** (2 nodes): `Combat MVP — 3D Top-Down Space Combat Simulator`, `Streaming Map — Chunk-Based Seamless World`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 16`** (2 nodes): `2026-04-16 pre-implementation spec audit & 3D cleanup`, `Core Spec > Feature Spec > agent assumption`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 17`** (2 nodes): `game_mode_changed(old_mode, new_mode)`, `PilotHUD / TacticalHUD — no mutual references; bus only`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 18`** (1 nodes): `Sim-Lite Physics — Mass, Momentum, Angular Inertia`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 19`** (1 nodes): `Observability From Day One — PerformanceMonitor`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 20`** (1 nodes): `Data-Driven Everything — JSON Configuration Files`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 21`** (1 nodes): `Modularity as Development Forcing Function — Agent Sessions Stay Focused`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 22`** (1 nodes): `feature_spec-fleet_command.md`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 23`** (1 nodes): `3D Play Plane Contract — All Entities at Y=0, Vector2 Banned`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 24`** (1 nodes): `Architecture Rules — No Hardcoded Values, No Direct Cross-System Refs`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 25`** (1 nodes): `Project Structure — Directory Layout`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 26`** (1 nodes): `SpaceBody Contract — mass, velocity, angular_velocity, apply_damage, apply_impulse`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 27`** (1 nodes): `PerformanceMonitor Contract — begin/end pairs required on every system`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 28`** (1 nodes): `Canonical Metric Names — System.method format table`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 29`** (1 nodes): `Content Architecture — Folder-Per-Item Under /content/`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 30`** (1 nodes): `One Ship.tscn for All Ship Types — Configured at Spawn Time`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 31`** (1 nodes): `Physics Summary — RigidBody3D + Jolt, Assisted Steering, Thruster Budget`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 32`** (1 nodes): `Weapons Summary — JSON Stats, Damage Types, Heat Per Hardpoint, Power Per Ship`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 33`** (1 nodes): `AI Summary — State Machine IDLE→PURSUE→ENGAGE, JSON Profiles`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 34`** (1 nodes): `Camera Summary — Camera3D Perspective, Height Zoom, Never Child of Ship`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 35`** (1 nodes): `World Streaming Summary — Deterministic Chunk Grid, GameEventBus chunk_loaded`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 36`** (1 nodes): `Build Order — 15-Step Dependency Sequence`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 37`** (1 nodes): `feature_spec-ai_patrol_behavior.md`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 38`** (1 nodes): `feature_spec-camera_system.md`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 39`** (1 nodes): `feature_spec-chunk_streamer.md`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 40`** (1 nodes): `feature_spec-physics_and_movement.md`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 41`** (1 nodes): `feature_spec-ship_system.md`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 42`** (1 nodes): `feature_spec-weapons_and_projectiles.md`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 43`** (1 nodes): `feature_spec-nav_controller.md`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 44`** (1 nodes): `feature_spec-performance_monitor.md`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 45`** (1 nodes): `Star Field System Specification`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 46`** (1 nodes): `Debug Grid Texture`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 47`** (1 nodes): `ServiceLocator singleton registry`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 48`** (1 nodes): `ContentRegistry JSON content loader`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 49`** (1 nodes): `ProjectileManager C# projectile pool`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 50`** (1 nodes): `No 2D nodes; Vector2 banned for world-space`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 51`** (1 nodes): `Ship.gd never writes velocity/position for motion — Jolt only`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 52`** (1 nodes): `ExclusionArea no-fly radius per destination star`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 53`** (1 nodes): `pool_size 0 disables effect without errors`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 54`** (1 nodes): `Session 1 Opus — VFX core, pools, GameBootstrap monitors`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 55`** (1 nodes): `UITokens.gd autoload — color/font constants`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 56`** (1 nodes): `UITheme.tres — Panel/Label/Button styles from tokens`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 57`** (1 nodes): `UI.pilot_hud_update / UI.tactical_hud_update metrics`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `GameEventBus signal contract specification` connect `Community 3` to `Community 1`, `Community 6`?**
  _High betweenness centrality (0.029) - this node is a cross-community bridge._
- **Why does `2026-04-21 Phase 16 GameEventBus spec reconciled with code` connect `Community 1` to `Community 3`?**
  _High betweenness centrality (0.020) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `Neutral dark gray base color field (~#444444)` (e.g. with `Bright red accent paint on hull markings` and `Minimal high-contrast sci-fi vehicle livery (gray + red)`) actually correct?**
  _`Neutral dark gray base color field (~#444444)` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `Bright red accent paint on hull markings` (e.g. with `Neutral dark gray base color field (~#444444)` and `Minimal high-contrast sci-fi vehicle livery (gray + red)`) actually correct?**
  _`Bright red accent paint on hull markings` has 2 INFERRED edges - model-reasoned connections that need verification._
- **What connects `Core Philosophy: Complexity On Demand`, `Four Phases of Play (Personal Pilot → Fleet → Infrastructure → Galactic)`, `Combat MVP — 3D Top-Down Space Combat Simulator` to the rest of the system?**
  _81 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 2` be split into smaller, more focused modules?**
  _Cohesion score 0.14 - nodes in this community are weakly interconnected._