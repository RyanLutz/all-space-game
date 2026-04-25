# Graph Report - .  (2026-04-24)

## Corpus Check
- 65 files · ~344,269 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 303 nodes · 422 edges · 47 communities detected
- Extraction: 66% EXTRACTED · 34% INFERRED · 0% AMBIGUOUS · INFERRED: 143 edges (avg confidence: 0.83)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Project Documentation & Specs|Project Documentation & Specs]]
- [[_COMMUNITY_Game Systems & Specs|Game Systems & Specs]]
- [[_COMMUNITY_Engineer & Navigator Crew Art|Engineer & Navigator Crew Art]]
- [[_COMMUNITY_Captain, Pilot & Soldier Crew Art|Captain, Pilot & Soldier Crew Art]]
- [[_COMMUNITY_ProjectileManager Code|ProjectileManager Code]]
- [[_COMMUNITY_Architecture Rules & Constraints|Architecture Rules & Constraints]]
- [[_COMMUNITY_Fighter Texture Art|Fighter Texture Art]]
- [[_COMMUNITY_Extended Crew & Sci-Fi Concepts|Extended Crew & Sci-Fi Concepts]]
- [[_COMMUNITY_Fighter UV & Livery|Fighter UV & Livery]]
- [[_COMMUNITY_Engineer Crew Portraits 1-4|Engineer Crew Portraits 1-4]]
- [[_COMMUNITY_ServiceLocator Code|ServiceLocator Code]]
- [[_COMMUNITY_Weapons & Damage Systems|Weapons & Damage Systems]]
- [[_COMMUNITY_Performance Monitoring|Performance Monitoring]]
- [[_COMMUNITY_Camera System|Camera System]]
- [[_COMMUNITY_Ship Factory & Content|Ship Factory & Content]]
- [[_COMMUNITY_Godot Icon|Godot Icon]]
- [[_COMMUNITY_Fighter Albedo Texture|Fighter Albedo Texture]]
- [[_COMMUNITY_Ship Blueprint & Stats|Ship Blueprint & Stats]]
- [[_COMMUNITY_Star Field & Constraints|Star Field & Constraints]]
- [[_COMMUNITY_Game Vision|Game Vision]]
- [[_COMMUNITY_Physics Steering|Physics Steering]]
- [[_COMMUNITY_Navigation & Hull|Navigation & Hull]]
- [[_COMMUNITY_MVP Vision|MVP Vision]]
- [[_COMMUNITY_Ship Overview|Ship Overview]]
- [[_COMMUNITY_Weapons Overview|Weapons Overview]]
- [[_COMMUNITY_Chunk Streaming|Chunk Streaming]]
- [[_COMMUNITY_Chunk Coordinates|Chunk Coordinates]]
- [[_COMMUNITY_Ship Factions|Ship Factions]]
- [[_COMMUNITY_Weapon Aim & Hardpoints|Weapon Aim & Hardpoints]]
- [[_COMMUNITY_Weapon Archetypes & Heat|Weapon Archetypes & Heat]]
- [[_COMMUNITY_Physics & Projectiles|Physics & Projectiles]]
- [[_COMMUNITY_Graphify Outputs|Graphify Outputs]]
- [[_COMMUNITY_Physics Vision|Physics Vision]]
- [[_COMMUNITY_Fleet Formation|Fleet Formation]]
- [[_COMMUNITY_Fleet Signals|Fleet Signals]]
- [[_COMMUNITY_Project Structure|Project Structure]]
- [[_COMMUNITY_Build Order|Build Order]]
- [[_COMMUNITY_Chunk Debris|Chunk Debris]]
- [[_COMMUNITY_Chunk Spawns|Chunk Spawns]]
- [[_COMMUNITY_RigidBody Config|RigidBody Config]]
- [[_COMMUNITY_Hardpoint Naming|Hardpoint Naming]]
- [[_COMMUNITY_Thrust Fraction|Thrust Fraction]]
- [[_COMMUNITY_Arrival Behavior|Arrival Behavior]]
- [[_COMMUNITY_Drive Mode|Drive Mode]]
- [[_COMMUNITY_Custom Monitors|Custom Monitors]]
- [[_COMMUNITY_Godot AI Addon|Godot AI Addon]]
- [[_COMMUNITY_Debug Grid|Debug Grid]]

## God Nodes (most connected - your core abstractions)
1. `Decisions Log` - 23 edges
2. `ProjectileManager` - 20 edges
3. `Sci-Fi Anime Art Style` - 18 edges
4. `Spaceship Interior Setting` - 18 edges
5. `Holographic Display UI Elements` - 18 edges
6. `Pixel Art Style` - 10 edges
7. `CLAUDE.md Project Context` - 7 edges
8. `EscortQueue — Ordered Escort Ship IDs, Queue-Shared Stance, Away-on-Orders` - 7 edges
9. `Neutral dark gray base color field (~#444444)` - 7 edges
10. `Bright red accent paint on hull markings` - 7 edges

## Surprising Connections (you probably didn't know these)
- `CLAUDE.md Project Context` --references--> `Non-Negotiable Architecture Rules`  [EXTRACTED]
  CLAUDE.md → docs/agent_brief.md
- `Session End Protocol` --references--> `Decisions Log`  [EXTRACTED]
  AGENTS.md → docs/decisions_log.md
- `GameEventBus Signal Contract` --references--> `core/GameEventBus.gd`  [EXTRACTED]
  docs/feature_spec-game_event_bus_signals.md → core/GameEventBus.gd
- `3D Play Plane Contract — All Entities at Y=0, Vector2 Banned` --rationale_for--> `No 2D Nodes Rule`  [EXTRACTED]
  docs/core_spec.md → CLAUDE.md
- `No Hardcoded Values — Tunable Data in JSON` --references--> `Architecture Rules — No Hardcoded Values, No Direct Cross-System Refs`  [EXTRACTED]
  CLAUDE.md → docs/core_spec.md

## Hyperedges (group relationships)
- **Fleet Command Subsystems Coordinate Exclusively via GameEventBus Signals** — fleet_command_inputmanager, fleet_command_selectionstate, fleet_command_escortqueue, fleet_command_stancecontroller, fleet_command_formationcontroller, gameventbus_signal_contract [EXTRACTED 1.00]
- **Tab Mode Switch Signal Chain: InputManager → game_mode_changed → GameCamera + UI** — fleet_command_inputmanager, gameventbus_mode_signals, camera_spec_tactical_extension, fleet_command_selectionstate [EXTRACTED 1.00]
- **Unified Input Interface: Player, AIController, and NavigationController All Feed Ship Physics** — core_spec_unified_input, physics_spec_three_layers, nav_spec_overview, ai_spec_overview, fleet_command_inputmanager [EXTRACTED 1.00]
- **XZ Plane Y=0 Enforcement Applies Across Ships, Projectiles, Asteroids, and Debris** — core_spec_xz_plane_contract, physics_spec_rigidbody_config, weapons_spec_projectile_manager, chunk_spec_asteroid, chunk_spec_debris [EXTRACTED 1.00]
- **All Tunable Values in JSON — ship.json, weapon.json, ai_profiles.json, world_config.json, factions.json** — claude_md_json_tunables_rule, ship_spec_ship_json_schema, weapons_spec_weapon_json, ai_spec_behavior_profile_json, chunk_spec_world_config_json, ship_spec_factions_json [EXTRACTED 1.00]
- **PerformanceMonitor begin/end Required on Every System — Instrumented from Day One** — core_spec_performance_monitor_contract, perf_spec_api, perf_spec_custom_monitors, perf_spec_built_first_rationale, vision_observability [EXTRACTED 1.00]
- **Damage Pipeline: Shield Absorption → Hull → Component Split via damage_type Matrix** — weapons_spec_damage_pipeline, weapons_spec_damage_type_matrix, weapons_spec_shield_system, weapons_spec_heat_system, ship_spec_contentregistry [EXTRACTED 1.00]
- **Stacked icon composition: panel, mascot fill, eye detail** — icon_rounded_panel, icon_mascot_vector_group, icon_ocular_detail_group [EXTRACTED 1.00]
- **Red UV islands forming a coordinated accent graphic set on the fighter sheet** — fighter_base_color_vertical_stripe_island, fighter_base_color_chevron_trim_islands, fighter_base_color_arc_crescent_island, fighter_base_color_circular_solid_island, fighter_base_color_red_accent_paint [INFERRED 0.83]
- **Fighter hull: flat albedo + implied material stack** — fighter_base_color_albedo_texture_file, fighter_base_color_uniform_charcoal_surface, fighter_base_color_neutral_pbr_foundation [INFERRED 0.72]
- **Red livery graphic elements on hull texture** — model_fighter_base_color_vertical_stripe, model_fighter_base_color_circular_element, model_fighter_base_color_crescent_element, model_fighter_base_color_symmetrical_angled_pairs, model_fighter_base_color_bright_red_markings [INFERRED 0.84]
- **Agent Session End Workflow** — agents_session_end_protocol, agent_brief_build_status, decisions_log [EXTRACTED 1.00]
- **Build Progress Tracking** — agent_brief_build_status, development_guide_build_order, development_guide_session_checklist [INFERRED 0.80]
- **April 17 2026 Implementation Decision Cluster** — decisions_log_decision_2026_04_17_physics_spec_auth, decisions_log_decision_2026_04_17_input_forward_sign, decisions_log_decision_2026_04_17_nav_monitor_registration, decisions_log_decision_2026_04_17_monitor_gamebootstrap, decisions_log_decision_2026_04_17_nav_flat_schema, decisions_log_decision_2026_04_17_projectilemanager_node3d, decisions_log_decision_2026_04_17_dumbprojectile_struct, decisions_log_decision_2026_04_17_hitscan_physics_tick, decisions_log_decision_2026_04_17_fire_group_indexing [INFERRED 0.75]
- **Engineer Crew Character Variants** — crew_engineer_1_character, crew_engineer_2_character, crew_engineer_3_character, crew_engineer_4_character [INFERRED 0.90]
- **Engineer Character Archetypes** — crew_engineer_5_character, crew_engineer_6_character, crew_engineer_7_character, crew_engineer_8_character, crew_engineer_9_character [INFERRED 0.80]
- **Spaceship Interior Environments** — engine_room_environment, industrial_corridor_environment, cleanroom_environment, circular_data_center_environment, navigation_room_environment [INFERRED 0.80]
- **Protective Engineer Gear** — tactical_harness_gear, backpack_gear, eva_suit, advanced_spacesuit [INFERRED 0.75]
- **Engineer Crew Members** — crew_engineer_10_character, crew_engineer_11_character, crew_engineer_12_character [EXTRACTED 1.00]
- **Navigator Crew Members** — crew_navigator_12_character, crew_navigator_1_character [EXTRACTED 1.00]
- **Glitch Art Crew Portraits** — crew_engineer_10_character, crew_engineer_11_character, crew_engineer_12_character, crew_navigator_12_character, crew_navigator_1_character [INFERRED 0.85]
- **Crew Navigator Portrait Collection** — crew_navigator_13_portrait, crew_navigator_3_portrait, crew_navigator_2_portrait, crew_navigator_4_portrait, crew_navigator_5_portrait [INFERRED 0.85]
- **Sci-Fi Anime Crew Portrait Collection** — crew_navigator_6, crew_navigator_7, crew_captain_1, crew_captain_2, crew_captain_3, crew_captain_4, crew_captain_5, crew_soldier_1, crew_soldier_2, crew_random_1, crew_random_2, crew_random_3, crew_pilot_1, crew_pilot_2, crew_pilot_3, crew_pilot_4, crew_pilot_5, crew_pilot_6 [INFERRED 0.90]
- **Captain Role Character Variants** — crew_captain_1, crew_captain_2, crew_captain_3, crew_captain_4, crew_captain_5 [EXTRACTED 1.00]
- **Pilot Role Character Variants** — crew_pilot_1, crew_pilot_2, crew_pilot_3, crew_pilot_4, crew_pilot_5, crew_pilot_6 [EXTRACTED 1.00]

## Communities

### Community 0 - "Project Documentation & Specs"
Cohesion: 0.06
Nodes (36): Agent Brief Build Status, Deviation Protocol, Agent Brief Project Context, Session End Protocol, core/GameEventBus.gd, Decisions Log, 2026-04-16 Pre-implementation Spec Audit, 2026-04-17 DumbProjectile Struct Stores Combat Values (+28 more)

### Community 1 - "Game Systems & Specs"
Cohesion: 0.07
Nodes (32): Aim Prediction — Linear Lead via aim_accuracy Float (0.0–1.0 Difficulty Knob), AI Behavior Profile JSON — ai_profiles.json, all tuning values, Detection System — Area3D SphereShape3D, body_entered Sets _player_detected, ENGAGE State — Maintain preferred_engage_distance, Orbit via Strafe, Fire When Aligned, IDLE State — Wander Within wander_radius of Spawn Position, AI & Patrol Behavior — State Machine, JSON Profiles, NavigationController, PURSUE State — Close on Target at pursue_thrust_fraction, Leash Range Check, AIController State Machine — IDLE→PURSUE→ENGAGE (FLEE/REGROUP/SEARCH reserved) (+24 more)

### Community 2 - "Engineer & Navigator Crew Art"
Cohesion: 0.12
Nodes (31): Advanced Spacesuit, Backpack Gear, Circular Data Center Environment, Circular Engine Turbine, Cleanroom Environment, Female Engineer in Orange Jumpsuit, Female Engineer in Tan Jumpsuit, Engineer in White EVA Suit (+23 more)

### Community 3 - "Captain, Pilot & Soldier Crew Art"
Cohesion: 0.23
Nodes (26): Holographic Display UI Elements, Sci-Fi Anime Art Style, Spaceship Interior Setting, Captain Character 1 - Blonde Captain on Throne, Captain Character 2 - Red Lit Captain, Captain Character 3 - Purple Hair Captain, Captain Character 4 - White Hair Orange Eye Captain, Captain Character 5 - Silver Hair Green Hologram Captain (+18 more)

### Community 4 - "ProjectileManager Code"
Cohesion: 0.17
Nodes (2): Node3D, ProjectileManager

### Community 5 - "Architecture Rules & Constraints"
Cohesion: 0.12
Nodes (16): Non-Negotiable Architecture Rules, Quick Rules, Mouse-to-World — Ray-Plane Intersection Against Y=0 (get_cursor_world_position), world_config.json — chunk_size, load_radius, asteroid_fields, debris tuning, No Direct Cross-System Calls — GameEventBus Signals Only, No Hardcoded Values — Tunable Data in JSON, No 2D Nodes Rule, One System Per Session — Do Not Mix Concerns (+8 more)

### Community 6 - "Fighter Texture Art"
Cohesion: 0.33
Nodes (10): Base color (albedo) texture map, Axum-class fighter surface livery, Accent marking color (high-chroma red), Solid circular red hull mark, Crescent or jagged-bottom red marking, Primary hull base color (matte dark gray field), Minimalist high-contrast industrial sci-fi look, Mirrored angled line pairs (lower layout) (+2 more)

### Community 7 - "Extended Crew & Sci-Fi Concepts"
Cohesion: 0.4
Nodes (10): Cosmic Navigation, Green-skinned Engineer with Holographic Tablet, Blue-skinned Engineer with Energy Sphere, Dark-skinned Engineer with Ring Interface, Navigator at Star Chart Console, White-haired Navigator Observing Cosmos, Engineer Role, Futuristic Spaceship Interior (+2 more)

### Community 8 - "Fighter UV & Livery"
Cohesion: 0.53
Nodes (9): Small horizontal arc or crescent marking (irregular top edge), Symmetric angled chevron or open-diamond trim pair, Solid circular red island (upper-right), Fighter Base Color diffuse (albedo) texture map, Minimal high-contrast sci-fi vehicle livery (gray + red), Neutral dark gray base color field (~#444444), Bright red accent paint on hull markings, UV island layout on a single base-color sheet (+1 more)

### Community 9 - "Engineer Crew Portraits 1-4"
Cohesion: 0.61
Nodes (9): Engineer Character Variant 1 - Welding Repair, Engineer Crew Role, Pixel Art Visual Style, Repair Activity with Energy Tool, Sci-Fi Industrial Environment Theme, Engineer Character Variant 2 - Cylindrical Machinery Welding, Engineer Character Variant 3 - Tool Repair, Engineer Character Variant 4 - Diagnostic Tablet (+1 more)

### Community 10 - "ServiceLocator Code"
Cohesion: 0.33
Nodes (2): Node, ServiceLocator

### Community 11 - "Weapons & Damage Systems"
Cohesion: 0.29
Nodes (7): Asteroid — RigidBody3D with Jolt Axis Locks, apply_damage, Debris Spawn on Death, SpaceBody Contract — mass, velocity, angular_velocity, apply_damage, apply_impulse, Damage Resolution Pipeline — Shield Absorption → Hull → Component Split via component_damage_ratio, Damage Type Matrix — ballistic 0.4×/1.5×, energy_beam 1.8×/0.5×, missile 0.6×/1.4×, Power System — Per-Ship Shared Pool, Brownout Stops Energy Weapons + Shield Regen, Shield System — shield_hp, regen_delay, regen_power_draw; Regen Pauses on Hit, weapon.json Schema — archetype, stats (damage, fire_rate, heat_per_shot, muzzle_speed, etc.)

### Community 12 - "Performance Monitoring"
Cohesion: 0.29
Nodes (7): Canonical Metric Names — System.method format table, PerformanceMonitor Contract — begin/end pairs required on every system, PerformanceMonitor API — begin/end Timing, set_count, get_avg_ms, get_peak_ms, Rationale: PerformanceMonitor Built First — Metrics From Day One Avoids Retrofitting, F3 In-Game Debug Overlay — CanvasLayer, Monospace Font, Frame Budget Display, PerformanceMonitor — Lightweight Always-On Observability Service, Observability From Day One — PerformanceMonitor

### Community 13 - "Camera System"
Cohesion: 0.4
Nodes (5): Rationale: Height Zoom vs FOV Zoom — Constant Distortion, Natural Feel, Camera System — Perspective Follow, Cursor-Offset, Height Zoom, Camera Is Sibling of Game World — Never Child of Any Ship, Critically Damped Spring Follow — No Overshoot, No Oscillation, Delta-Time Correct, Camera Summary — Camera3D Perspective, Height Zoom, Never Child of Ship

### Community 14 - "Ship Factory & Content"
Cohesion: 0.4
Nodes (5): Content Architecture — Folder-Per-Item Under /content/, ContentRegistry — Scans /content at Startup, Indexes Ships/Weapons/Modules by Folder, PlayerState — Tracks Active Player Ship, Emits player_ship_changed, ShipFactory — spawn_ship(), Stat Resolution, Part Assembly, Hardpoint Discovery, Color Material, GuidedProjectilePool GDScript — Missile Steering via slerp, track_cursor/auto_lock/click_lock

### Community 15 - "Godot Icon"
Cohesion: 0.5
Nodes (5): Semantic association: standard Godot Engine editor / project joystick-robot logo, Scaled path group: robot head, gear crown, blue face plate (#478cbf), white gear outline, Eye layer: two dark gray circles (#414042) for pupils, Rounded rectangle frame (#363d52 fill, #212532 stroke, rx=14), SVG application icon 128×128 (Godot-style brand mark)

### Community 16 - "Fighter Albedo Texture"
Cohesion: 0.5
Nodes (5): Fighter Base Color texture (Blender albedo map), Dark utilitarian / industrial hull color direction, Featureless albedo (no gradients, noise, or markings), Neutral base layer for PBR (detail likely in roughness/normal/metallic), Uniform dark charcoal gray surface (~#444444 RGB)

### Community 17 - "Ship Blueprint & Stats"
Cohesion: 0.5
Nodes (4): Blueprint Discovery System — variant_id Added to Save Data on Reverse Engineering, ship.json Schema — base_stats, variants, part_stats, hardpoint_types, module_slots, default_loadout, Stat Resolution — base_stats + additive part_stat deltas Applied Once at Spawn, Ship Three Layers — Class (what it is) / Variant (discoverable config) / Loadout (player customizes)

### Community 18 - "Star Field & Constraints"
Cohesion: 0.5
Nodes (4): data/world_config.json, Star Field System Specification, No 2D Nodes Rule, No Hardcoded Values Rule

### Community 19 - "Game Vision"
Cohesion: 0.67
Nodes (3): All Space Core Spec — Top-Down 3D on XZ Plane, Core Philosophy: Complexity On Demand, All Space — Top-Down 3D Space Simulation Vision

### Community 20 - "Physics Steering"
Cohesion: 0.67
Nodes (3): Partial Alignment Drag — alignment_drag_current Per-Frame Reset Pattern, Lateral-Only Bleed, Assisted Steering — Predicted Stopping Distance Controls Brake vs Accelerate Torque, Shared Thruster Budget — Turning Priority Over Translation, Diagonal Clamped to Unit

### Community 21 - "Navigation & Hull"
Cohesion: 0.67
Nodes (3): Braking Decision Algorithm — Predicted Stop Distance vs Remaining Distance, Project World-Space Thrust onto Ship Axes — Correct Regardless of Facing, Physics Hull JSON Block — mass, max_speed, linear_drag, thruster_force, etc.

### Community 22 - "MVP Vision"
Cohesion: 1.0
Nodes (2): Combat MVP — 3D Top-Down Space Combat Simulator, Streaming Map — Chunk-Based Seamless World

### Community 23 - "Ship Overview"
Cohesion: 1.0
Nodes (2): One Ship.tscn for All Ship Types — Configured at Spawn Time, Ship System — One Ship.tscn, Data-Driven Assembly from ship.json + parts.glb

### Community 24 - "Weapons Overview"
Cohesion: 1.0
Nodes (2): Weapons Summary — JSON Stats, Damage Types, Heat Per Hardpoint, Power Per Ship, Weapons & Projectiles — Data-Driven, Dual Heat/Power Resources, Dual Pool

### Community 25 - "Chunk Streaming"
Cohesion: 1.0
Nodes (2): ChunkStreamer — Deterministic Procedural Chunk Streaming, Bounded Memory, World Streaming Summary — Deterministic Chunk Grid, GameEventBus chunk_loaded

### Community 26 - "Chunk Coordinates"
Cohesion: 1.0
Nodes (2): Chunk Coordinate ↔ World Position — Vector2i Grid Coord → Vector3 World Origin, Deterministic RNG Seeded by Chunk Coord Hash — Same Coord = Same Content Every Visit

### Community 27 - "Ship Factions"
Cohesion: 1.0
Nodes (2): Vertex Color Shader — R=Primary, G=Trim, B=Accent, A=Glow; Shared Material Per Ship, factions.json — color_scheme (primary/trim/accent/glow) + name_vocabulary

### Community 28 - "Weapon Aim & Hardpoints"
Cohesion: 1.0
Nodes (2): Aim Direction Algorithm — slerp-Clamp to Arc for Gimbal/Partial Turret, Unconstrained Full Turret, Hardpoint Types — fixed (~5°), gimbal (~25°), partial_turret (~120°), full_turret (360°)

### Community 29 - "Weapon Archetypes & Heat"
Cohesion: 1.0
Nodes (2): Weapon Archetypes — Ballistic, Energy Beam, Energy Pulse, Dumb Missile, Guided Missile, Heat System — Per-Hardpoint heat_current, Overheat Lockout, Passive Cooling

### Community 30 - "Physics & Projectiles"
Cohesion: 1.0
Nodes (2): Momentum Inheritance — Projectiles Inherit Ship velocity at Spawn, ProjectileManager C# — Dumb Pool (DumbProjectile struct), Hitscan, Swept Raycast

### Community 31 - "Graphify Outputs"
Cohesion: 1.0
Nodes (2): Graph HTML Visualization, Graph Report Summary

### Community 32 - "Physics Vision"
Cohesion: 1.0
Nodes (1): Sim-Lite Physics — Mass, Momentum, Angular Inertia

### Community 33 - "Fleet Formation"
Cohesion: 1.0
Nodes (1): Formation Tick Algorithm — Pilot Mode, Slot Destination = Player Pos + Offset Rotated by Yaw

### Community 34 - "Fleet Signals"
Cohesion: 1.0
Nodes (1): New Fleet Command Signals — request_tactical_stop, set_stance, escort_queue_changed, ship_damaged, request_formation_destination

### Community 35 - "Project Structure"
Cohesion: 1.0
Nodes (1): Project Structure — Directory Layout

### Community 36 - "Build Order"
Cohesion: 1.0
Nodes (1): Build Order — 15-Step Dependency Sequence

### Community 37 - "Chunk Debris"
Cohesion: 1.0
Nodes (1): Debris — Node3D Visual Only, Manual Velocity Integration, Alpha Fade Timer

### Community 38 - "Chunk Spawns"
Cohesion: 1.0
Nodes (1): AI Spawn Point Markers — Node3D in ai_spawn_points Group, ChunkStreamer Agnostic of AI

### Community 39 - "RigidBody Config"
Cohesion: 1.0
Nodes (1): RigidBody3D Configuration — gravity_scale 0, axis_lock_linear_y, DAMP_MODE_REPLACE

### Community 40 - "Hardpoint Naming"
Cohesion: 1.0
Nodes (1): Hardpoint Empty Naming — HardpointEmpty_{part}_{id}_{size} Uniqueness Convention

### Community 41 - "Thrust Fraction"
Cohesion: 1.0
Nodes (1): Thrust Fraction Scaling — AI Expresses Intent (patrol vs pursue speed)

### Community 42 - "Arrival Behavior"
Cohesion: 1.0
Nodes (1): Arrival Behavior — Zero Thrust Within arrival_distance, Residual Drift Intentional

### Community 43 - "Drive Mode"
Cohesion: 1.0
Nodes (1): DriveMode Enum — EXTERNAL / TACTICAL_ORDER / FORMATION Self-Drive (Phase 14)

### Community 44 - "Custom Monitors"
Cohesion: 1.0
Nodes (1): Godot Custom Monitors Registered in GameBootstrap to Avoid Duplicate Registration

### Community 45 - "Godot AI Addon"
Cohesion: 1.0
Nodes (1): Godot AI Addon README

### Community 46 - "Debug Grid"
Cohesion: 1.0
Nodes (1): Debug Grid Texture

## Knowledge Gaps
- **96 isolated node(s):** `No Direct Cross-System Calls — GameEventBus Signals Only`, `Specs Are Authoritative — Deviations Require Report`, `Core Philosophy: Complexity On Demand`, `Four Phases of Play (Personal Pilot → Fleet → Infrastructure → Galactic)`, `Combat MVP — 3D Top-Down Space Combat Simulator` (+91 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **Thin community `MVP Vision`** (2 nodes): `Combat MVP — 3D Top-Down Space Combat Simulator`, `Streaming Map — Chunk-Based Seamless World`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Ship Overview`** (2 nodes): `One Ship.tscn for All Ship Types — Configured at Spawn Time`, `Ship System — One Ship.tscn, Data-Driven Assembly from ship.json + parts.glb`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Weapons Overview`** (2 nodes): `Weapons Summary — JSON Stats, Damage Types, Heat Per Hardpoint, Power Per Ship`, `Weapons & Projectiles — Data-Driven, Dual Heat/Power Resources, Dual Pool`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Chunk Streaming`** (2 nodes): `ChunkStreamer — Deterministic Procedural Chunk Streaming, Bounded Memory`, `World Streaming Summary — Deterministic Chunk Grid, GameEventBus chunk_loaded`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Chunk Coordinates`** (2 nodes): `Chunk Coordinate ↔ World Position — Vector2i Grid Coord → Vector3 World Origin`, `Deterministic RNG Seeded by Chunk Coord Hash — Same Coord = Same Content Every Visit`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Ship Factions`** (2 nodes): `Vertex Color Shader — R=Primary, G=Trim, B=Accent, A=Glow; Shared Material Per Ship`, `factions.json — color_scheme (primary/trim/accent/glow) + name_vocabulary`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Weapon Aim & Hardpoints`** (2 nodes): `Aim Direction Algorithm — slerp-Clamp to Arc for Gimbal/Partial Turret, Unconstrained Full Turret`, `Hardpoint Types — fixed (~5°), gimbal (~25°), partial_turret (~120°), full_turret (360°)`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Weapon Archetypes & Heat`** (2 nodes): `Weapon Archetypes — Ballistic, Energy Beam, Energy Pulse, Dumb Missile, Guided Missile`, `Heat System — Per-Hardpoint heat_current, Overheat Lockout, Passive Cooling`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Physics & Projectiles`** (2 nodes): `Momentum Inheritance — Projectiles Inherit Ship velocity at Spawn`, `ProjectileManager C# — Dumb Pool (DumbProjectile struct), Hitscan, Swept Raycast`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Graphify Outputs`** (2 nodes): `Graph HTML Visualization`, `Graph Report Summary`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Physics Vision`** (1 nodes): `Sim-Lite Physics — Mass, Momentum, Angular Inertia`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Fleet Formation`** (1 nodes): `Formation Tick Algorithm — Pilot Mode, Slot Destination = Player Pos + Offset Rotated by Yaw`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Fleet Signals`** (1 nodes): `New Fleet Command Signals — request_tactical_stop, set_stance, escort_queue_changed, ship_damaged, request_formation_destination`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Project Structure`** (1 nodes): `Project Structure — Directory Layout`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Build Order`** (1 nodes): `Build Order — 15-Step Dependency Sequence`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Chunk Debris`** (1 nodes): `Debris — Node3D Visual Only, Manual Velocity Integration, Alpha Fade Timer`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Chunk Spawns`** (1 nodes): `AI Spawn Point Markers — Node3D in ai_spawn_points Group, ChunkStreamer Agnostic of AI`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `RigidBody Config`** (1 nodes): `RigidBody3D Configuration — gravity_scale 0, axis_lock_linear_y, DAMP_MODE_REPLACE`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Hardpoint Naming`** (1 nodes): `Hardpoint Empty Naming — HardpointEmpty_{part}_{id}_{size} Uniqueness Convention`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Thrust Fraction`** (1 nodes): `Thrust Fraction Scaling — AI Expresses Intent (patrol vs pursue speed)`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Arrival Behavior`** (1 nodes): `Arrival Behavior — Zero Thrust Within arrival_distance, Residual Drift Intentional`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Drive Mode`** (1 nodes): `DriveMode Enum — EXTERNAL / TACTICAL_ORDER / FORMATION Self-Drive (Phase 14)`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Custom Monitors`** (1 nodes): `Godot Custom Monitors Registered in GameBootstrap to Avoid Duplicate Registration`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Godot AI Addon`** (1 nodes): `Godot AI Addon README`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Debug Grid`** (1 nodes): `Debug Grid Texture`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Are the 18 inferred relationships involving `Sci-Fi Anime Art Style` (e.g. with `Navigator Character 6 - Star Map Navigator` and `Navigator Character 7 - Dark Lit Navigator`) actually correct?**
  _`Sci-Fi Anime Art Style` has 18 INFERRED edges - model-reasoned connections that need verification._
- **Are the 18 inferred relationships involving `Spaceship Interior Setting` (e.g. with `Navigator Character 6 - Star Map Navigator` and `Navigator Character 7 - Dark Lit Navigator`) actually correct?**
  _`Spaceship Interior Setting` has 18 INFERRED edges - model-reasoned connections that need verification._
- **Are the 18 inferred relationships involving `Holographic Display UI Elements` (e.g. with `Navigator Character 6 - Star Map Navigator` and `Navigator Character 7 - Dark Lit Navigator`) actually correct?**
  _`Holographic Display UI Elements` has 18 INFERRED edges - model-reasoned connections that need verification._
- **What connects `No Direct Cross-System Calls — GameEventBus Signals Only`, `Specs Are Authoritative — Deviations Require Report`, `Core Philosophy: Complexity On Demand` to the rest of the system?**
  _96 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Project Documentation & Specs` be split into smaller, more focused modules?**
  _Cohesion score 0.06 - nodes in this community are weakly interconnected._
- **Should `Game Systems & Specs` be split into smaller, more focused modules?**
  _Cohesion score 0.07 - nodes in this community are weakly interconnected._
- **Should `Engineer & Navigator Crew Art` be split into smaller, more focused modules?**
  _Cohesion score 0.12 - nodes in this community are weakly interconnected._