# Graph Report - .  (2026-04-20)

## Corpus Check
- 25 files · ~57,592 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 195 nodes · 199 edges · 40 communities detected
- Extraction: 87% EXTRACTED · 13% INFERRED · 0% AMBIGUOUS · INFERRED: 26 edges (avg confidence: 0.76)
- Token cost: 85,000 input · 5,200 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Core Architecture Rules|Core Architecture Rules]]
- [[_COMMUNITY_AI Combat Behavior|AI Combat Behavior]]
- [[_COMMUNITY_World Streaming & Content|World Streaming & Content]]
- [[_COMMUNITY_Fleet Command & Tactical Mode|Fleet Command & Tactical Mode]]
- [[_COMMUNITY_Projectile Manager (C)|Projectile Manager (C#)]]
- [[_COMMUNITY_Ship Visual Livery|Ship Visual Livery]]
- [[_COMMUNITY_Ship Surface Markings|Ship Surface Markings]]
- [[_COMMUNITY_Camera System|Camera System]]
- [[_COMMUNITY_ServiceLocator (C)|ServiceLocator (C#)]]
- [[_COMMUNITY_Combat & Damage System|Combat & Damage System]]
- [[_COMMUNITY_Godot Project Icon|Godot Project Icon]]
- [[_COMMUNITY_Ship Base Texture|Ship Base Texture]]
- [[_COMMUNITY_Physics & Steering|Physics & Steering]]
- [[_COMMUNITY_Ship Data Schema|Ship Data Schema]]
- [[_COMMUNITY_Build Status & Dev Guide|Build Status & Dev Guide]]
- [[_COMMUNITY_Project Vision & Core Spec|Project Vision & Core Spec]]
- [[_COMMUNITY_Physics Movement Algorithms|Physics Movement Algorithms]]
- [[_COMMUNITY_AI Model Selection|AI Model Selection]]
- [[_COMMUNITY_Project MVP Goals|Project MVP Goals]]
- [[_COMMUNITY_Weapons System Overview|Weapons System Overview]]
- [[_COMMUNITY_Faction Color System|Faction Color System]]
- [[_COMMUNITY_Weapon Aiming & Hardpoints|Weapon Aiming & Hardpoints]]
- [[_COMMUNITY_Weapon Archetypes & Heat|Weapon Archetypes & Heat]]
- [[_COMMUNITY_Chunk Coordinate System|Chunk Coordinate System]]
- [[_COMMUNITY_Debug Monitoring|Debug Monitoring]]
- [[_COMMUNITY_Hardpoint Naming Convention|Hardpoint Naming Convention]]
- [[_COMMUNITY_Tech Stack|Tech Stack]]
- [[_COMMUNITY_Recent Decisions|Recent Decisions]]
- [[_COMMUNITY_Sim-Lite Physics|Sim-Lite Physics]]
- [[_COMMUNITY_Project Structure|Project Structure]]
- [[_COMMUNITY_Ship State Signals|Ship State Signals]]
- [[_COMMUNITY_AI Signals|AI Signals]]
- [[_COMMUNITY_Type Contract Vector3|Type Contract Vector3]]
- [[_COMMUNITY_Formation Algorithm|Formation Algorithm]]
- [[_COMMUNITY_AI Thrust Scaling|AI Thrust Scaling]]
- [[_COMMUNITY_Arrival Behavior|Arrival Behavior]]
- [[_COMMUNITY_RigidBody3D Config|RigidBody3D Config]]
- [[_COMMUNITY_Debris Visual System|Debris Visual System]]
- [[_COMMUNITY_Phase 12 Decision|Phase 12 Decision]]
- [[_COMMUNITY_Session Discipline|Session Discipline]]

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
- `3D Play Plane Contract — All Entities at Y=0, Vector2 Banned` --rationale_for--> `No 2D Nodes Rule`  [EXTRACTED]
  docs/core_spec.md → CLAUDE.md
- `No Hardcoded Values — Tunable Data in JSON` --references--> `Architecture Rules — No Hardcoded Values, No Direct Cross-System Refs`  [EXTRACTED]
  CLAUDE.md → docs/core_spec.md
- `Data-Driven Everything — JSON Configuration Files` --references--> `No Hardcoded Values — Tunable Data in JSON`  [EXTRACTED]
  docs/All_Space_Project_Vision.md → CLAUDE.md

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

### Community 0 - "Core Architecture Rules"
Cohesion: 0.08
Nodes (27): Non-Negotiable Architecture Rules, Deviation Protocol — Written Report Before Code, Mouse-to-World — Ray-Plane Intersection Against Y=0 (get_cursor_world_position), world_config.json — chunk_size, load_radius, asteroid_fields, debris tuning, No Direct Cross-System Calls — GameEventBus Signals Only, No Hardcoded Values — Tunable Data in JSON, No 2D Nodes Rule, One System Per Session — Do Not Mix Concerns (+19 more)

### Community 1 - "AI Combat Behavior"
Cohesion: 0.09
Nodes (24): Aim Prediction — Linear Lead via aim_accuracy Float (0.0–1.0 Difficulty Knob), AI Behavior Profile JSON — ai_profiles.json, all tuning values, Detection System — Area3D SphereShape3D, body_entered Sets _player_detected, ENGAGE State — Maintain preferred_engage_distance, Orbit via Strafe, Fire When Aligned, IDLE State — Wander Within wander_radius of Spawn Position, AI & Patrol Behavior — State Machine, JSON Profiles, NavigationController, PURSUE State — Close on Target at pursue_thrust_fraction, Leash Range Check, AIController State Machine — IDLE→PURSUE→ENGAGE (FLEE/REGROUP/SEARCH reserved) (+16 more)

### Community 2 - "World Streaming & Content"
Cohesion: 0.12
Nodes (17): ChunkStreamer — Deterministic Procedural Chunk Streaming, Bounded Memory, AI Spawn Point Markers — Node3D in ai_spawn_points Group, ChunkStreamer Agnostic of AI, Content Architecture — Folder-Per-Item Under /content/, World Streaming Summary — Deterministic Chunk Grid, GameEventBus chunk_loaded, Decision 2026-04-18 — Phase 9 ShipFactory + Ship Visual Assembly Implementation, New Fleet Command Signals — request_tactical_stop, set_stance, escort_queue_changed, ship_damaged, request_formation_destination, Combat Signals — projectile_hit, ship_destroyed, weapon_fired, hardpoint_state_changed, Player State Signals — player_ship_changed(ship: Node) (+9 more)

### Community 3 - "Fleet Command & Tactical Mode"
Cohesion: 0.19
Nodes (12): Decision 2026-04-20 — Phase 14 Fleet Command Full RTS Command Layer, Fleet Command Architecture — InputManager, SelectionState, EscortQueue, FormationController, StanceController, Away-on-Orders Tracking — Slot Reserved but Empty During Tactical Order, Context Menu — Stance Submenu (hidden in escort) + Escort Submenu, Defensive Stance Fan-Out — Escort Queue Member Hit Triggers All Members Attack Attacker, EscortQueue — Ordered Escort Ship IDs, Queue-Shared Stance, Away-on-Orders, FormationController — Pilot-Mode Tick, request_formation_destination Signal, Fleet Command — RTS Fleet Control, Escort Queue, Stance System (+4 more)

### Community 4 - "Projectile Manager (C#)"
Cohesion: 0.29
Nodes (2): Node3D, ProjectileManager

### Community 5 - "Ship Visual Livery"
Cohesion: 0.33
Nodes (10): Base color (albedo) texture map, Axum-class fighter surface livery, Accent marking color (high-chroma red), Solid circular red hull mark, Crescent or jagged-bottom red marking, Primary hull base color (matte dark gray field), Minimalist high-contrast industrial sci-fi look, Mirrored angled line pairs (lower layout) (+2 more)

### Community 6 - "Ship Surface Markings"
Cohesion: 0.53
Nodes (9): Small horizontal arc or crescent marking (irregular top edge), Symmetric angled chevron or open-diamond trim pair, Solid circular red island (upper-right), Fighter Base Color diffuse (albedo) texture map, Minimal high-contrast sci-fi vehicle livery (gray + red), Neutral dark gray base color field (~#444444), Bright red accent paint on hull markings, UV island layout on a single base-color sheet (+1 more)

### Community 7 - "Camera System"
Cohesion: 0.22
Nodes (9): Rationale: Height Zoom vs FOV Zoom — Constant Distortion, Natural Feel, Camera System — Perspective Follow, Cursor-Offset, Height Zoom, Camera Is Sibling of Game World — Never Child of Any Ship, Critically Damped Spring Follow — No Overshoot, No Oscillation, Delta-Time Correct, Camera Summary — Camera3D Perspective, Height Zoom, Never Child of Ship, Decision 2026-04-19 — Phase 10 GameCamera Pilot Mode Implementation, Decision 2026-04-19 — Phase 13 Tactical Mode Camera + Input Layer, InputManager — Tab Mode Toggle, game_mode_changed Emission, Pilot Input Routing (+1 more)

### Community 8 - "ServiceLocator (C#)"
Cohesion: 0.29
Nodes (2): Node, ServiceLocator

### Community 9 - "Combat & Damage System"
Cohesion: 0.29
Nodes (7): Asteroid — RigidBody3D with Jolt Axis Locks, apply_damage, Debris Spawn on Death, SpaceBody Contract — mass, velocity, angular_velocity, apply_damage, apply_impulse, Damage Resolution Pipeline — Shield Absorption → Hull → Component Split via component_damage_ratio, Damage Type Matrix — ballistic 0.4×/1.5×, energy_beam 1.8×/0.5×, missile 0.6×/1.4×, Power System — Per-Ship Shared Pool, Brownout Stops Energy Weapons + Shield Regen, Shield System — shield_hp, regen_delay, regen_power_draw; Regen Pauses on Hit, weapon.json Schema — archetype, stats (damage, fire_rate, heat_per_shot, muzzle_speed, etc.)

### Community 10 - "Godot Project Icon"
Cohesion: 0.5
Nodes (5): Semantic association: standard Godot Engine editor / project joystick-robot logo, Scaled path group: robot head, gear crown, blue face plate (#478cbf), white gear outline, Eye layer: two dark gray circles (#414042) for pupils, Rounded rectangle frame (#363d52 fill, #212532 stroke, rx=14), SVG application icon 128×128 (Godot-style brand mark)

### Community 11 - "Ship Base Texture"
Cohesion: 0.5
Nodes (5): Fighter Base Color texture (Blender albedo map), Dark utilitarian / industrial hull color direction, Featureless albedo (no gradients, noise, or markings), Neutral base layer for PBR (detail likely in roughness/normal/metallic), Uniform dark charcoal gray surface (~#444444 RGB)

### Community 12 - "Physics & Steering"
Cohesion: 0.5
Nodes (4): Decision 2026-04-17 — input_forward Sign Convention: Positive = Forward, Partial Alignment Drag — alignment_drag_current Per-Frame Reset Pattern, Lateral-Only Bleed, Assisted Steering — Predicted Stopping Distance Controls Brake vs Accelerate Torque, Shared Thruster Budget — Turning Priority Over Translation, Diagonal Clamped to Unit

### Community 13 - "Ship Data Schema"
Cohesion: 0.5
Nodes (4): Blueprint Discovery System — variant_id Added to Save Data on Reverse Engineering, ship.json Schema — base_stats, variants, part_stats, hardpoint_types, module_slots, default_loadout, Stat Resolution — base_stats + additive part_stat deltas Applied Once at Spawn, Ship Three Layers — Class (what it is) / Variant (discoverable config) / Loadout (player customizes)

### Community 14 - "Build Status & Dev Guide"
Cohesion: 0.67
Nodes (3): Build Status Table, Build Order — 15-Step Dependency Sequence, Development Guide — Session-Ordered Build Checklist with Model Assignments

### Community 15 - "Project Vision & Core Spec"
Cohesion: 0.67
Nodes (3): All Space Core Spec — Top-Down 3D on XZ Plane, Core Philosophy: Complexity On Demand, All Space — Top-Down 3D Space Simulation Vision

### Community 16 - "Physics Movement Algorithms"
Cohesion: 0.67
Nodes (3): Braking Decision Algorithm — Predicted Stop Distance vs Remaining Distance, Project World-Space Thrust onto Ship Axes — Correct Regardless of Facing, Physics Hull JSON Block — mass, max_speed, linear_drag, thruster_force, etc.

### Community 17 - "AI Model Selection"
Cohesion: 1.0
Nodes (2): Agent Tiers — Opus vs Sonnet Decision Rule, Opus vs Sonnet Decision Rule — Blast Radius and Novelty Drive Model Choice

### Community 18 - "Project MVP Goals"
Cohesion: 1.0
Nodes (2): Combat MVP — 3D Top-Down Space Combat Simulator, Streaming Map — Chunk-Based Seamless World

### Community 19 - "Weapons System Overview"
Cohesion: 1.0
Nodes (2): Weapons Summary — JSON Stats, Damage Types, Heat Per Hardpoint, Power Per Ship, Weapons & Projectiles — Data-Driven, Dual Heat/Power Resources, Dual Pool

### Community 20 - "Faction Color System"
Cohesion: 1.0
Nodes (2): Vertex Color Shader — R=Primary, G=Trim, B=Accent, A=Glow; Shared Material Per Ship, factions.json — color_scheme (primary/trim/accent/glow) + name_vocabulary

### Community 21 - "Weapon Aiming & Hardpoints"
Cohesion: 1.0
Nodes (2): Aim Direction Algorithm — slerp-Clamp to Arc for Gimbal/Partial Turret, Unconstrained Full Turret, Hardpoint Types — fixed (~5°), gimbal (~25°), partial_turret (~120°), full_turret (360°)

### Community 22 - "Weapon Archetypes & Heat"
Cohesion: 1.0
Nodes (2): Weapon Archetypes — Ballistic, Energy Beam, Energy Pulse, Dumb Missile, Guided Missile, Heat System — Per-Hardpoint heat_current, Overheat Lockout, Passive Cooling

### Community 23 - "Chunk Coordinate System"
Cohesion: 1.0
Nodes (2): Chunk Coordinate ↔ World Position — Vector2i Grid Coord → Vector3 World Origin, Deterministic RNG Seeded by Chunk Coord Hash — Same Coord = Same Content Every Visit

### Community 24 - "Debug Monitoring"
Cohesion: 1.0
Nodes (2): Decision 2026-04-17 — Custom Monitor Registration Moved to GameBootstrap, Godot Custom Monitors Registered in GameBootstrap to Avoid Duplicate Registration

### Community 25 - "Hardpoint Naming Convention"
Cohesion: 1.0
Nodes (2): Decision 2026-04-18 — Hardpoint Empty Naming Must Include Part Name for Uniqueness, Hardpoint Empty Naming — HardpointEmpty_{part}_{id}_{size} Uniqueness Convention

### Community 26 - "Tech Stack"
Cohesion: 1.0
Nodes (1): Tech Stack (Godot 4.6 / GDScript / Jolt / ServiceLocator)

### Community 27 - "Recent Decisions"
Cohesion: 1.0
Nodes (1): Recent Decisions Summary (Phase 10–14)

### Community 28 - "Sim-Lite Physics"
Cohesion: 1.0
Nodes (1): Sim-Lite Physics — Mass, Momentum, Angular Inertia

### Community 29 - "Project Structure"
Cohesion: 1.0
Nodes (1): Project Structure — Directory Layout

### Community 30 - "Ship State Signals"
Cohesion: 1.0
Nodes (1): Ship State Signals — shield_depleted, hull_critical, power_depleted

### Community 31 - "AI Signals"
Cohesion: 1.0
Nodes (1): AI Signals — ai_state_changed, ai_target_acquired, ai_target_lost

### Community 32 - "Type Contract Vector3"
Cohesion: 1.0
Nodes (1): Type Contract — All World-Space Positions/Velocities Are Vector3; Vector2 Banned

### Community 33 - "Formation Algorithm"
Cohesion: 1.0
Nodes (1): Formation Tick Algorithm — Pilot Mode, Slot Destination = Player Pos + Offset Rotated by Yaw

### Community 34 - "AI Thrust Scaling"
Cohesion: 1.0
Nodes (1): Thrust Fraction Scaling — AI Expresses Intent (patrol vs pursue speed)

### Community 35 - "Arrival Behavior"
Cohesion: 1.0
Nodes (1): Arrival Behavior — Zero Thrust Within arrival_distance, Residual Drift Intentional

### Community 36 - "RigidBody3D Config"
Cohesion: 1.0
Nodes (1): RigidBody3D Configuration — gravity_scale 0, axis_lock_linear_y, DAMP_MODE_REPLACE

### Community 37 - "Debris Visual System"
Cohesion: 1.0
Nodes (1): Debris — Node3D Visual Only, Manual Velocity Integration, Alpha Fade Timer

### Community 38 - "Phase 12 Decision"
Cohesion: 1.0
Nodes (1): Decision 2026-04-19 — Step 12 Pilot Loop Integration Test Scene

### Community 39 - "Session Discipline"
Cohesion: 1.0
Nodes (1): Session Checklist — Pre/During/Post Session Discipline

## Knowledge Gaps
- **89 isolated node(s):** `Rounded rectangle frame (#363d52 fill, #212532 stroke, rx=14)`, `Semantic association: standard Godot Engine editor / project joystick-robot logo`, `Dark utilitarian / industrial hull color direction`, `UV island layout (flat painted regions for wrapped mesh)`, `Build Status Table` (+84 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **Thin community `AI Model Selection`** (2 nodes): `Agent Tiers — Opus vs Sonnet Decision Rule`, `Opus vs Sonnet Decision Rule — Blast Radius and Novelty Drive Model Choice`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Project MVP Goals`** (2 nodes): `Combat MVP — 3D Top-Down Space Combat Simulator`, `Streaming Map — Chunk-Based Seamless World`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Weapons System Overview`** (2 nodes): `Weapons Summary — JSON Stats, Damage Types, Heat Per Hardpoint, Power Per Ship`, `Weapons & Projectiles — Data-Driven, Dual Heat/Power Resources, Dual Pool`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Faction Color System`** (2 nodes): `Vertex Color Shader — R=Primary, G=Trim, B=Accent, A=Glow; Shared Material Per Ship`, `factions.json — color_scheme (primary/trim/accent/glow) + name_vocabulary`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Weapon Aiming & Hardpoints`** (2 nodes): `Aim Direction Algorithm — slerp-Clamp to Arc for Gimbal/Partial Turret, Unconstrained Full Turret`, `Hardpoint Types — fixed (~5°), gimbal (~25°), partial_turret (~120°), full_turret (360°)`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Weapon Archetypes & Heat`** (2 nodes): `Weapon Archetypes — Ballistic, Energy Beam, Energy Pulse, Dumb Missile, Guided Missile`, `Heat System — Per-Hardpoint heat_current, Overheat Lockout, Passive Cooling`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Chunk Coordinate System`** (2 nodes): `Chunk Coordinate ↔ World Position — Vector2i Grid Coord → Vector3 World Origin`, `Deterministic RNG Seeded by Chunk Coord Hash — Same Coord = Same Content Every Visit`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Debug Monitoring`** (2 nodes): `Decision 2026-04-17 — Custom Monitor Registration Moved to GameBootstrap`, `Godot Custom Monitors Registered in GameBootstrap to Avoid Duplicate Registration`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Hardpoint Naming Convention`** (2 nodes): `Decision 2026-04-18 — Hardpoint Empty Naming Must Include Part Name for Uniqueness`, `Hardpoint Empty Naming — HardpointEmpty_{part}_{id}_{size} Uniqueness Convention`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Tech Stack`** (1 nodes): `Tech Stack (Godot 4.6 / GDScript / Jolt / ServiceLocator)`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Recent Decisions`** (1 nodes): `Recent Decisions Summary (Phase 10–14)`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Sim-Lite Physics`** (1 nodes): `Sim-Lite Physics — Mass, Momentum, Angular Inertia`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Project Structure`** (1 nodes): `Project Structure — Directory Layout`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Ship State Signals`** (1 nodes): `Ship State Signals — shield_depleted, hull_critical, power_depleted`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `AI Signals`** (1 nodes): `AI Signals — ai_state_changed, ai_target_acquired, ai_target_lost`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Type Contract Vector3`** (1 nodes): `Type Contract — All World-Space Positions/Velocities Are Vector3; Vector2 Banned`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Formation Algorithm`** (1 nodes): `Formation Tick Algorithm — Pilot Mode, Slot Destination = Player Pos + Offset Rotated by Yaw`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `AI Thrust Scaling`** (1 nodes): `Thrust Fraction Scaling — AI Expresses Intent (patrol vs pursue speed)`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Arrival Behavior`** (1 nodes): `Arrival Behavior — Zero Thrust Within arrival_distance, Residual Drift Intentional`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `RigidBody3D Config`** (1 nodes): `RigidBody3D Configuration — gravity_scale 0, axis_lock_linear_y, DAMP_MODE_REPLACE`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Debris Visual System`** (1 nodes): `Debris — Node3D Visual Only, Manual Velocity Integration, Alpha Fade Timer`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Phase 12 Decision`** (1 nodes): `Decision 2026-04-19 — Step 12 Pilot Loop Integration Test Scene`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Session Discipline`** (1 nodes): `Session Checklist — Pre/During/Post Session Discipline`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `GameEventBus Signal Contract — Cross-System Event Catalog` connect `World Streaming & Content` to `Core Architecture Rules`, `AI Combat Behavior`, `Camera System`?**
  _High betweenness centrality (0.099) - this node is a cross-community bridge._
- **Why does `CLAUDE.md Project Context` connect `Core Architecture Rules` to `AI Combat Behavior`?**
  _High betweenness centrality (0.089) - this node is a cross-community bridge._
- **Why does `AI & Patrol Behavior — State Machine, JSON Profiles, NavigationController` connect `AI Combat Behavior` to `Fleet Command & Tactical Mode`?**
  _High betweenness centrality (0.059) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `Neutral dark gray base color field (~#444444)` (e.g. with `Bright red accent paint on hull markings` and `Minimal high-contrast sci-fi vehicle livery (gray + red)`) actually correct?**
  _`Neutral dark gray base color field (~#444444)` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `Bright red accent paint on hull markings` (e.g. with `Neutral dark gray base color field (~#444444)` and `Minimal high-contrast sci-fi vehicle livery (gray + red)`) actually correct?**
  _`Bright red accent paint on hull markings` has 2 INFERRED edges - model-reasoned connections that need verification._
- **What connects `Rounded rectangle frame (#363d52 fill, #212532 stroke, rx=14)`, `Semantic association: standard Godot Engine editor / project joystick-robot logo`, `Dark utilitarian / industrial hull color direction` to the rest of the system?**
  _89 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Core Architecture Rules` be split into smaller, more focused modules?**
  _Cohesion score 0.08 - nodes in this community are weakly interconnected._