# Graph Report - /home/lutz/Projects/All Space  (2026-04-20)

## Corpus Check
- 2 files · ~65,292 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 195 nodes · 199 edges · 40 communities detected
- Extraction: 87% EXTRACTED · 13% INFERRED · 0% AMBIGUOUS · INFERRED: 26 edges (avg confidence: 0.76)
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

## God Nodes (most connected - your core abstractions)
1. `ProjectileManager` - 12 edges
2. `Neutral dark gray base color field (~#444444)` - 7 edges
3. `Bright red accent paint on hull markings` - 7 edges
4. `Accent marking color (high-chroma red)` - 7 edges
5. `CLAUDE.md Project Context` - 7 edges
6. `GameEventBus Signal Contract — Cross-System Event Catalog` - 7 edges
7. `EscortQueue — Ordered Escort Ship IDs, Queue-Shared Stance, Away-on-Orders` - 7 edges
8. `AI & Patrol Behavior — State Machine, JSON Profiles, NavigationController` - 7 edges
9. `ServiceLocator` - 6 edges
10. `Fleet Command Architecture — InputManager, SelectionState, EscortQueue, FormationController, StanceController` - 6 edges

## Surprising Connections (you probably didn't know these)
- `No Direct Cross-System Calls — GameEventBus Signals Only` --references--> `GameEventBus Signal Contract — Cross-System Event Catalog`  [EXTRACTED]
  CLAUDE.md → docs/feature_spec-game_event_bus_signals.md
- `CLAUDE.md Project Context` --references--> `Non-Negotiable Architecture Rules`  [EXTRACTED]
  CLAUDE.md → docs/agent_brief.md
- `No 2D Nodes Rule` --rationale_for--> `3D Play Plane Contract — All Entities at Y=0, Vector2 Banned`  [EXTRACTED]
  CLAUDE.md → docs/core_spec.md
- `No Hardcoded Values — Tunable Data in JSON` --references--> `Architecture Rules — No Hardcoded Values, No Direct Cross-System Refs`  [EXTRACTED]
  CLAUDE.md → docs/core_spec.md
- `No Hardcoded Values — Tunable Data in JSON` --references--> `Data-Driven Everything — JSON Configuration Files`  [EXTRACTED]
  CLAUDE.md → docs/All_Space_Project_Vision.md

## Hyperedges (group relationships)
- **Stacked icon composition: panel, mascot fill, eye detail** — icon_rounded_panel, icon_mascot_vector_group, icon_ocular_detail_group [EXTRACTED 1.00]
- **Red UV islands forming a coordinated accent graphic set on the fighter sheet** — fighter_base_color_vertical_stripe_island, fighter_base_color_chevron_trim_islands, fighter_base_color_arc_crescent_island, fighter_base_color_circular_solid_island, fighter_base_color_red_accent_paint [INFERRED 0.83]
- **Fighter hull: flat albedo + implied material stack** — fighter_base_color_albedo_texture_file, fighter_base_color_uniform_charcoal_surface, fighter_base_color_neutral_pbr_foundation [INFERRED 0.72]
- **Red livery graphic elements on hull texture** — model_fighter_base_color_vertical_stripe, model_fighter_base_color_circular_element, model_fighter_base_color_crescent_element, model_fighter_base_color_symmetrical_angled_pairs, model_fighter_base_color_bright_red_markings [INFERRED 0.84]
- **Unified Input Interface: Player, AIController, and NavigationController All Feed Ship Physics** — core_spec_unified_input, physics_spec_three_layers, nav_spec_overview, ai_spec_overview, fleet_command_inputmanager [EXTRACTED 1.00]
- **Fleet Command Subsystems Coordinate Exclusively via GameEventBus Signals** — fleet_command_inputmanager, fleet_command_selectionstate, fleet_command_escortqueue, fleet_command_stancecontroller, fleet_command_formationcontroller, gameventbus_signal_contract [EXTRACTED 1.00]
- **XZ Plane Y=0 Enforcement Applies Across Ships, Projectiles, Asteroids, and Debris** — core_spec_xz_plane_contract, physics_spec_rigidbody_config, weapons_spec_projectile_manager, chunk_spec_asteroid, chunk_spec_debris [EXTRACTED 1.00]
- **All Tunable Values in JSON — ship.json, weapon.json, ai_profiles.json, world_config.json, factions.json** — claude_md_json_tunables_rule, ship_spec_ship_json_schema, weapons_spec_weapon_json, ai_spec_behavior_profile_json, chunk_spec_world_config_json, ship_spec_factions_json [EXTRACTED 1.00]
- **PerformanceMonitor begin/end Required on Every System — Instrumented from Day One** — core_spec_performance_monitor_contract, perf_spec_api, perf_spec_custom_monitors, perf_spec_built_first_rationale, vision_observability [EXTRACTED 1.00]
- **Damage Pipeline: Shield Absorption → Hull → Component Split via damage_type Matrix** — weapons_spec_damage_pipeline, weapons_spec_damage_type_matrix, weapons_spec_shield_system, weapons_spec_heat_system, ship_spec_contentregistry [EXTRACTED 1.00]
- **Tab Mode Switch Signal Chain: InputManager → game_mode_changed → GameCamera + UI** — fleet_command_inputmanager, gameventbus_mode_signals, camera_spec_tactical_extension, fleet_command_selectionstate [EXTRACTED 1.00]

## Communities

### Community 0 - "Community 0"
Cohesion: 0.08
Nodes (27): Non-Negotiable Architecture Rules, Deviation Protocol — Written Report Before Code, Mouse-to-World — Ray-Plane Intersection Against Y=0 (get_cursor_world_position), world_config.json — chunk_size, load_radius, asteroid_fields, debris tuning, No Direct Cross-System Calls — GameEventBus Signals Only, No Hardcoded Values — Tunable Data in JSON, No 2D Nodes Rule, One System Per Session — Do Not Mix Concerns (+19 more)

### Community 1 - "Community 1"
Cohesion: 0.09
Nodes (24): Aim Prediction — Linear Lead via aim_accuracy Float (0.0–1.0 Difficulty Knob), AI Behavior Profile JSON — ai_profiles.json, all tuning values, Detection System — Area3D SphereShape3D, body_entered Sets _player_detected, ENGAGE State — Maintain preferred_engage_distance, Orbit via Strafe, Fire When Aligned, IDLE State — Wander Within wander_radius of Spawn Position, AI & Patrol Behavior — State Machine, JSON Profiles, NavigationController, PURSUE State — Close on Target at pursue_thrust_fraction, Leash Range Check, AIController State Machine — IDLE→PURSUE→ENGAGE (FLEE/REGROUP/SEARCH reserved) (+16 more)

### Community 2 - "Community 2"
Cohesion: 0.12
Nodes (17): ChunkStreamer — Deterministic Procedural Chunk Streaming, Bounded Memory, AI Spawn Point Markers — Node3D in ai_spawn_points Group, ChunkStreamer Agnostic of AI, Content Architecture — Folder-Per-Item Under /content/, World Streaming Summary — Deterministic Chunk Grid, GameEventBus chunk_loaded, Decision 2026-04-18 — Phase 9 ShipFactory + Ship Visual Assembly Implementation, New Fleet Command Signals — request_tactical_stop, set_stance, escort_queue_changed, ship_damaged, request_formation_destination, Combat Signals — projectile_hit, ship_destroyed, weapon_fired, hardpoint_state_changed, Player State Signals — player_ship_changed(ship: Node) (+9 more)

### Community 3 - "Community 3"
Cohesion: 0.19
Nodes (12): Decision 2026-04-20 — Phase 14 Fleet Command Full RTS Command Layer, Fleet Command Architecture — InputManager, SelectionState, EscortQueue, FormationController, StanceController, Away-on-Orders Tracking — Slot Reserved but Empty During Tactical Order, Context Menu — Stance Submenu (hidden in escort) + Escort Submenu, Defensive Stance Fan-Out — Escort Queue Member Hit Triggers All Members Attack Attacker, EscortQueue — Ordered Escort Ship IDs, Queue-Shared Stance, Away-on-Orders, FormationController — Pilot-Mode Tick, request_formation_destination Signal, Fleet Command — RTS Fleet Control, Escort Queue, Stance System (+4 more)

### Community 4 - "Community 4"
Cohesion: 0.29
Nodes (2): Node3D, ProjectileManager

### Community 5 - "Community 5"
Cohesion: 0.33
Nodes (10): Base color (albedo) texture map, Axum-class fighter surface livery, Accent marking color (high-chroma red), Solid circular red hull mark, Crescent or jagged-bottom red marking, Primary hull base color (matte dark gray field), Minimalist high-contrast industrial sci-fi look, Mirrored angled line pairs (lower layout) (+2 more)

### Community 6 - "Community 6"
Cohesion: 0.53
Nodes (9): Small horizontal arc or crescent marking (irregular top edge), Symmetric angled chevron or open-diamond trim pair, Solid circular red island (upper-right), Fighter Base Color diffuse (albedo) texture map, Minimal high-contrast sci-fi vehicle livery (gray + red), Neutral dark gray base color field (~#444444), Bright red accent paint on hull markings, UV island layout on a single base-color sheet (+1 more)

### Community 7 - "Community 7"
Cohesion: 0.22
Nodes (9): Rationale: Height Zoom vs FOV Zoom — Constant Distortion, Natural Feel, Camera System — Perspective Follow, Cursor-Offset, Height Zoom, Camera Is Sibling of Game World — Never Child of Any Ship, Critically Damped Spring Follow — No Overshoot, No Oscillation, Delta-Time Correct, Camera Summary — Camera3D Perspective, Height Zoom, Never Child of Ship, Decision 2026-04-19 — Phase 10 GameCamera Pilot Mode Implementation, Decision 2026-04-19 — Phase 13 Tactical Mode Camera + Input Layer, InputManager — Tab Mode Toggle, game_mode_changed Emission, Pilot Input Routing (+1 more)

### Community 8 - "Community 8"
Cohesion: 0.29
Nodes (2): Node, ServiceLocator

### Community 9 - "Community 9"
Cohesion: 0.29
Nodes (7): Asteroid — RigidBody3D with Jolt Axis Locks, apply_damage, Debris Spawn on Death, SpaceBody Contract — mass, velocity, angular_velocity, apply_damage, apply_impulse, Damage Resolution Pipeline — Shield Absorption → Hull → Component Split via component_damage_ratio, Damage Type Matrix — ballistic 0.4×/1.5×, energy_beam 1.8×/0.5×, missile 0.6×/1.4×, Power System — Per-Ship Shared Pool, Brownout Stops Energy Weapons + Shield Regen, Shield System — shield_hp, regen_delay, regen_power_draw; Regen Pauses on Hit, weapon.json Schema — archetype, stats (damage, fire_rate, heat_per_shot, muzzle_speed, etc.)

### Community 10 - "Community 10"
Cohesion: 0.5
Nodes (5): Semantic association: standard Godot Engine editor / project joystick-robot logo, Scaled path group: robot head, gear crown, blue face plate (#478cbf), white gear outline, Eye layer: two dark gray circles (#414042) for pupils, Rounded rectangle frame (#363d52 fill, #212532 stroke, rx=14), SVG application icon 128×128 (Godot-style brand mark)

### Community 11 - "Community 11"
Cohesion: 0.5
Nodes (5): Fighter Base Color texture (Blender albedo map), Dark utilitarian / industrial hull color direction, Featureless albedo (no gradients, noise, or markings), Neutral base layer for PBR (detail likely in roughness/normal/metallic), Uniform dark charcoal gray surface (~#444444 RGB)

### Community 12 - "Community 12"
Cohesion: 0.5
Nodes (4): Decision 2026-04-17 — input_forward Sign Convention: Positive = Forward, Partial Alignment Drag — alignment_drag_current Per-Frame Reset Pattern, Lateral-Only Bleed, Assisted Steering — Predicted Stopping Distance Controls Brake vs Accelerate Torque, Shared Thruster Budget — Turning Priority Over Translation, Diagonal Clamped to Unit

### Community 13 - "Community 13"
Cohesion: 0.5
Nodes (4): Blueprint Discovery System — variant_id Added to Save Data on Reverse Engineering, ship.json Schema — base_stats, variants, part_stats, hardpoint_types, module_slots, default_loadout, Stat Resolution — base_stats + additive part_stat deltas Applied Once at Spawn, Ship Three Layers — Class (what it is) / Variant (discoverable config) / Loadout (player customizes)

### Community 14 - "Community 14"
Cohesion: 0.67
Nodes (3): Build Status Table, Build Order — 15-Step Dependency Sequence, Development Guide — Session-Ordered Build Checklist with Model Assignments

### Community 15 - "Community 15"
Cohesion: 0.67
Nodes (3): All Space Core Spec — Top-Down 3D on XZ Plane, Core Philosophy: Complexity On Demand, All Space — Top-Down 3D Space Simulation Vision

### Community 16 - "Community 16"
Cohesion: 0.67
Nodes (3): Braking Decision Algorithm — Predicted Stop Distance vs Remaining Distance, Project World-Space Thrust onto Ship Axes — Correct Regardless of Facing, Physics Hull JSON Block — mass, max_speed, linear_drag, thruster_force, etc.

### Community 17 - "Community 17"
Cohesion: 1.0
Nodes (2): Agent Tiers — Opus vs Sonnet Decision Rule, Opus vs Sonnet Decision Rule — Blast Radius and Novelty Drive Model Choice

### Community 18 - "Community 18"
Cohesion: 1.0
Nodes (2): Combat MVP — 3D Top-Down Space Combat Simulator, Streaming Map — Chunk-Based Seamless World

### Community 19 - "Community 19"
Cohesion: 1.0
Nodes (2): Weapons Summary — JSON Stats, Damage Types, Heat Per Hardpoint, Power Per Ship, Weapons & Projectiles — Data-Driven, Dual Heat/Power Resources, Dual Pool

### Community 20 - "Community 20"
Cohesion: 1.0
Nodes (2): Vertex Color Shader — R=Primary, G=Trim, B=Accent, A=Glow; Shared Material Per Ship, factions.json — color_scheme (primary/trim/accent/glow) + name_vocabulary

### Community 21 - "Community 21"
Cohesion: 1.0
Nodes (2): Aim Direction Algorithm — slerp-Clamp to Arc for Gimbal/Partial Turret, Unconstrained Full Turret, Hardpoint Types — fixed (~5°), gimbal (~25°), partial_turret (~120°), full_turret (360°)

### Community 22 - "Community 22"
Cohesion: 1.0
Nodes (2): Weapon Archetypes — Ballistic, Energy Beam, Energy Pulse, Dumb Missile, Guided Missile, Heat System — Per-Hardpoint heat_current, Overheat Lockout, Passive Cooling

### Community 23 - "Community 23"
Cohesion: 1.0
Nodes (2): Chunk Coordinate ↔ World Position — Vector2i Grid Coord → Vector3 World Origin, Deterministic RNG Seeded by Chunk Coord Hash — Same Coord = Same Content Every Visit

### Community 24 - "Community 24"
Cohesion: 1.0
Nodes (2): Decision 2026-04-17 — Custom Monitor Registration Moved to GameBootstrap, Godot Custom Monitors Registered in GameBootstrap to Avoid Duplicate Registration

### Community 25 - "Community 25"
Cohesion: 1.0
Nodes (2): Decision 2026-04-18 — Hardpoint Empty Naming Must Include Part Name for Uniqueness, Hardpoint Empty Naming — HardpointEmpty_{part}_{id}_{size} Uniqueness Convention

### Community 26 - "Community 26"
Cohesion: 1.0
Nodes (1): Tech Stack (Godot 4.6 / GDScript / Jolt / ServiceLocator)

### Community 27 - "Community 27"
Cohesion: 1.0
Nodes (1): Recent Decisions Summary (Phase 10–14)

### Community 28 - "Community 28"
Cohesion: 1.0
Nodes (1): Sim-Lite Physics — Mass, Momentum, Angular Inertia

### Community 29 - "Community 29"
Cohesion: 1.0
Nodes (1): Project Structure — Directory Layout

### Community 30 - "Community 30"
Cohesion: 1.0
Nodes (1): Ship State Signals — shield_depleted, hull_critical, power_depleted

### Community 31 - "Community 31"
Cohesion: 1.0
Nodes (1): AI Signals — ai_state_changed, ai_target_acquired, ai_target_lost

### Community 32 - "Community 32"
Cohesion: 1.0
Nodes (1): Type Contract — All World-Space Positions/Velocities Are Vector3; Vector2 Banned

### Community 33 - "Community 33"
Cohesion: 1.0
Nodes (1): Formation Tick Algorithm — Pilot Mode, Slot Destination = Player Pos + Offset Rotated by Yaw

### Community 34 - "Community 34"
Cohesion: 1.0
Nodes (1): Thrust Fraction Scaling — AI Expresses Intent (patrol vs pursue speed)

### Community 35 - "Community 35"
Cohesion: 1.0
Nodes (1): Arrival Behavior — Zero Thrust Within arrival_distance, Residual Drift Intentional

### Community 36 - "Community 36"
Cohesion: 1.0
Nodes (1): RigidBody3D Configuration — gravity_scale 0, axis_lock_linear_y, DAMP_MODE_REPLACE

### Community 37 - "Community 37"
Cohesion: 1.0
Nodes (1): Debris — Node3D Visual Only, Manual Velocity Integration, Alpha Fade Timer

### Community 38 - "Community 38"
Cohesion: 1.0
Nodes (1): Decision 2026-04-19 — Step 12 Pilot Loop Integration Test Scene

### Community 39 - "Community 39"
Cohesion: 1.0
Nodes (1): Session Checklist — Pre/During/Post Session Discipline

## Knowledge Gaps
- **89 isolated node(s):** `Rounded rectangle frame (#363d52 fill, #212532 stroke, rx=14)`, `Semantic association: standard Godot Engine editor / project joystick-robot logo`, `Dark utilitarian / industrial hull color direction`, `UV island layout (flat painted regions for wrapped mesh)`, `Build Status Table` (+84 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **Thin community `Community 17`** (2 nodes): `Agent Tiers — Opus vs Sonnet Decision Rule`, `Opus vs Sonnet Decision Rule — Blast Radius and Novelty Drive Model Choice`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 18`** (2 nodes): `Combat MVP — 3D Top-Down Space Combat Simulator`, `Streaming Map — Chunk-Based Seamless World`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 19`** (2 nodes): `Weapons Summary — JSON Stats, Damage Types, Heat Per Hardpoint, Power Per Ship`, `Weapons & Projectiles — Data-Driven, Dual Heat/Power Resources, Dual Pool`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 20`** (2 nodes): `Vertex Color Shader — R=Primary, G=Trim, B=Accent, A=Glow; Shared Material Per Ship`, `factions.json — color_scheme (primary/trim/accent/glow) + name_vocabulary`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 21`** (2 nodes): `Aim Direction Algorithm — slerp-Clamp to Arc for Gimbal/Partial Turret, Unconstrained Full Turret`, `Hardpoint Types — fixed (~5°), gimbal (~25°), partial_turret (~120°), full_turret (360°)`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 22`** (2 nodes): `Weapon Archetypes — Ballistic, Energy Beam, Energy Pulse, Dumb Missile, Guided Missile`, `Heat System — Per-Hardpoint heat_current, Overheat Lockout, Passive Cooling`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 23`** (2 nodes): `Chunk Coordinate ↔ World Position — Vector2i Grid Coord → Vector3 World Origin`, `Deterministic RNG Seeded by Chunk Coord Hash — Same Coord = Same Content Every Visit`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 24`** (2 nodes): `Decision 2026-04-17 — Custom Monitor Registration Moved to GameBootstrap`, `Godot Custom Monitors Registered in GameBootstrap to Avoid Duplicate Registration`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 25`** (2 nodes): `Decision 2026-04-18 — Hardpoint Empty Naming Must Include Part Name for Uniqueness`, `Hardpoint Empty Naming — HardpointEmpty_{part}_{id}_{size} Uniqueness Convention`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 26`** (1 nodes): `Tech Stack (Godot 4.6 / GDScript / Jolt / ServiceLocator)`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 27`** (1 nodes): `Recent Decisions Summary (Phase 10–14)`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 28`** (1 nodes): `Sim-Lite Physics — Mass, Momentum, Angular Inertia`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 29`** (1 nodes): `Project Structure — Directory Layout`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 30`** (1 nodes): `Ship State Signals — shield_depleted, hull_critical, power_depleted`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 31`** (1 nodes): `AI Signals — ai_state_changed, ai_target_acquired, ai_target_lost`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 32`** (1 nodes): `Type Contract — All World-Space Positions/Velocities Are Vector3; Vector2 Banned`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 33`** (1 nodes): `Formation Tick Algorithm — Pilot Mode, Slot Destination = Player Pos + Offset Rotated by Yaw`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 34`** (1 nodes): `Thrust Fraction Scaling — AI Expresses Intent (patrol vs pursue speed)`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 35`** (1 nodes): `Arrival Behavior — Zero Thrust Within arrival_distance, Residual Drift Intentional`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 36`** (1 nodes): `RigidBody3D Configuration — gravity_scale 0, axis_lock_linear_y, DAMP_MODE_REPLACE`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 37`** (1 nodes): `Debris — Node3D Visual Only, Manual Velocity Integration, Alpha Fade Timer`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 38`** (1 nodes): `Decision 2026-04-19 — Step 12 Pilot Loop Integration Test Scene`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 39`** (1 nodes): `Session Checklist — Pre/During/Post Session Discipline`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `GameEventBus Signal Contract — Cross-System Event Catalog` connect `Community 2` to `Community 0`, `Community 1`, `Community 7`?**
  _High betweenness centrality (0.099) - this node is a cross-community bridge._
- **Why does `CLAUDE.md Project Context` connect `Community 0` to `Community 1`?**
  _High betweenness centrality (0.089) - this node is a cross-community bridge._
- **Why does `AI & Patrol Behavior — State Machine, JSON Profiles, NavigationController` connect `Community 1` to `Community 3`?**
  _High betweenness centrality (0.059) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `Neutral dark gray base color field (~#444444)` (e.g. with `Bright red accent paint on hull markings` and `Minimal high-contrast sci-fi vehicle livery (gray + red)`) actually correct?**
  _`Neutral dark gray base color field (~#444444)` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `Bright red accent paint on hull markings` (e.g. with `Neutral dark gray base color field (~#444444)` and `Minimal high-contrast sci-fi vehicle livery (gray + red)`) actually correct?**
  _`Bright red accent paint on hull markings` has 2 INFERRED edges - model-reasoned connections that need verification._
- **What connects `Rounded rectangle frame (#363d52 fill, #212532 stroke, rx=14)`, `Semantic association: standard Godot Engine editor / project joystick-robot logo`, `Dark utilitarian / industrial hull color direction` to the rest of the system?**
  _89 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 0` be split into smaller, more focused modules?**
  _Cohesion score 0.08 - nodes in this community are weakly interconnected._