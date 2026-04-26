# Graph Report - /home/lutz/Projects/All Space  (2026-04-25)

## Corpus Check
- 2 files · ~83,887 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 301 nodes · 422 edges · 47 communities detected
- Extraction: 66% EXTRACTED · 34% INFERRED · 0% AMBIGUOUS · INFERRED: 144 edges (avg confidence: 0.83)
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

## God Nodes (most connected - your core abstractions)
1. `Decisions Log` - 23 edges
2. `ProjectileManager` - 21 edges
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
- `No 2D Nodes Rule` --rationale_for--> `3D Play Plane Contract — All Entities at Y=0, Vector2 Banned`  [EXTRACTED]
  CLAUDE.md → docs/core_spec.md
- `No Hardcoded Values — Tunable Data in JSON` --references--> `Architecture Rules — No Hardcoded Values, No Direct Cross-System Refs`  [EXTRACTED]
  CLAUDE.md → docs/core_spec.md
- `No Hardcoded Values — Tunable Data in JSON` --references--> `Data-Driven Everything — JSON Configuration Files`  [EXTRACTED]
  CLAUDE.md → docs/All_Space_Project_Vision.md

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

### Community 0 - "Community 0"
Cohesion: 0.07
Nodes (35): Agent Brief Build Status, Deviation Protocol, Agent Brief Project Context, Session End Protocol, Decisions Log, 2026-04-16 Pre-implementation Spec Audit, 2026-04-17 DumbProjectile Struct Stores Combat Values, 2026-04-17 Fire Group 1-Based JSON 0-Based Internal (+27 more)

### Community 1 - "Community 1"
Cohesion: 0.12
Nodes (31): Advanced Spacesuit, Backpack Gear, Circular Data Center Environment, Circular Engine Turbine, Cleanroom Environment, Female Engineer in Orange Jumpsuit, Female Engineer in Tan Jumpsuit, Engineer in White EVA Suit (+23 more)

### Community 2 - "Community 2"
Cohesion: 0.12
Nodes (4): Node, Node3D, ProjectileManager, ServiceLocator

### Community 3 - "Community 3"
Cohesion: 0.23
Nodes (26): Holographic Display UI Elements, Sci-Fi Anime Art Style, Spaceship Interior Setting, Captain Character 1 - Blonde Captain on Throne, Captain Character 2 - Red Lit Captain, Captain Character 3 - Purple Hair Captain, Captain Character 4 - White Hair Orange Eye Captain, Captain Character 5 - Silver Hair Green Hologram Captain (+18 more)

### Community 4 - "Community 4"
Cohesion: 0.1
Nodes (21): Aim Prediction — Linear Lead via aim_accuracy Float (0.0–1.0 Difficulty Knob), AI Behavior Profile JSON — ai_profiles.json, all tuning values, Detection System — Area3D SphereShape3D, body_entered Sets _player_detected, ENGAGE State — Maintain preferred_engage_distance, Orbit via Strafe, Fire When Aligned, IDLE State — Wander Within wander_radius of Spawn Position, AI & Patrol Behavior — State Machine, JSON Profiles, NavigationController, PURSUE State — Close on Target at pursue_thrust_fraction, Leash Range Check, AIController State Machine — IDLE→PURSUE→ENGAGE (FLEE/REGROUP/SEARCH reserved) (+13 more)

### Community 5 - "Community 5"
Cohesion: 0.12
Nodes (16): Non-Negotiable Architecture Rules, Quick Rules, Mouse-to-World — Ray-Plane Intersection Against Y=0 (get_cursor_world_position), world_config.json — chunk_size, load_radius, asteroid_fields, debris tuning, No Direct Cross-System Calls — GameEventBus Signals Only, No Hardcoded Values — Tunable Data in JSON, No 2D Nodes Rule, One System Per Session — Do Not Mix Concerns (+8 more)

### Community 6 - "Community 6"
Cohesion: 0.21
Nodes (11): Fleet Command Architecture — InputManager, SelectionState, EscortQueue, FormationController, StanceController, Away-on-Orders Tracking — Slot Reserved but Empty During Tactical Order, Context Menu — Stance Submenu (hidden in escort) + Escort Submenu, Defensive Stance Fan-Out — Escort Queue Member Hit Triggers All Members Attack Attacker, EscortQueue — Ordered Escort Ship IDs, Queue-Shared Stance, Away-on-Orders, FormationController — Pilot-Mode Tick, request_formation_destination Signal, InputManager — Tab Mode Toggle, game_mode_changed Emission, Pilot Input Routing, Fleet Command — RTS Fleet Control, Escort Queue, Stance System (+3 more)

### Community 7 - "Community 7"
Cohesion: 0.33
Nodes (10): Base color (albedo) texture map, Axum-class fighter surface livery, Accent marking color (high-chroma red), Solid circular red hull mark, Crescent or jagged-bottom red marking, Primary hull base color (matte dark gray field), Minimalist high-contrast industrial sci-fi look, Mirrored angled line pairs (lower layout) (+2 more)

### Community 8 - "Community 8"
Cohesion: 0.4
Nodes (10): Cosmic Navigation, Green-skinned Engineer with Holographic Tablet, Blue-skinned Engineer with Energy Sphere, Dark-skinned Engineer with Ring Interface, Navigator at Star Chart Console, White-haired Navigator Observing Cosmos, Engineer Role, Futuristic Spaceship Interior (+2 more)

### Community 9 - "Community 9"
Cohesion: 0.53
Nodes (9): Small horizontal arc or crescent marking (irregular top edge), Symmetric angled chevron or open-diamond trim pair, Solid circular red island (upper-right), Fighter Base Color diffuse (albedo) texture map, Minimal high-contrast sci-fi vehicle livery (gray + red), Neutral dark gray base color field (~#444444), Bright red accent paint on hull markings, UV island layout on a single base-color sheet (+1 more)

### Community 10 - "Community 10"
Cohesion: 0.61
Nodes (9): Engineer Character Variant 1 - Welding Repair, Engineer Crew Role, Pixel Art Visual Style, Repair Activity with Energy Tool, Sci-Fi Industrial Environment Theme, Engineer Character Variant 2 - Cylindrical Machinery Welding, Engineer Character Variant 3 - Tool Repair, Engineer Character Variant 4 - Diagnostic Tablet (+1 more)

### Community 11 - "Community 11"
Cohesion: 0.29
Nodes (7): Asteroid — RigidBody3D with Jolt Axis Locks, apply_damage, Debris Spawn on Death, SpaceBody Contract — mass, velocity, angular_velocity, apply_damage, apply_impulse, Damage Resolution Pipeline — Shield Absorption → Hull → Component Split via component_damage_ratio, Damage Type Matrix — ballistic 0.4×/1.5×, energy_beam 1.8×/0.5×, missile 0.6×/1.4×, Power System — Per-Ship Shared Pool, Brownout Stops Energy Weapons + Shield Regen, Shield System — shield_hp, regen_delay, regen_power_draw; Regen Pauses on Hit, weapon.json Schema — archetype, stats (damage, fire_rate, heat_per_shot, muzzle_speed, etc.)

### Community 12 - "Community 12"
Cohesion: 0.29
Nodes (7): Canonical Metric Names — System.method format table, PerformanceMonitor Contract — begin/end pairs required on every system, PerformanceMonitor API — begin/end Timing, set_count, get_avg_ms, get_peak_ms, Rationale: PerformanceMonitor Built First — Metrics From Day One Avoids Retrofitting, F3 In-Game Debug Overlay — CanvasLayer, Monospace Font, Frame Budget Display, PerformanceMonitor — Lightweight Always-On Observability Service, Observability From Day One — PerformanceMonitor

### Community 13 - "Community 13"
Cohesion: 0.4
Nodes (5): Content Architecture — Folder-Per-Item Under /content/, ContentRegistry — Scans /content at Startup, Indexes Ships/Weapons/Modules by Folder, PlayerState — Tracks Active Player Ship, Emits player_ship_changed, ShipFactory — spawn_ship(), Stat Resolution, Part Assembly, Hardpoint Discovery, Color Material, GuidedProjectilePool GDScript — Missile Steering via slerp, track_cursor/auto_lock/click_lock

### Community 14 - "Community 14"
Cohesion: 0.4
Nodes (5): Rationale: Height Zoom vs FOV Zoom — Constant Distortion, Natural Feel, Camera System — Perspective Follow, Cursor-Offset, Height Zoom, Camera Is Sibling of Game World — Never Child of Any Ship, Critically Damped Spring Follow — No Overshoot, No Oscillation, Delta-Time Correct, Camera Summary — Camera3D Perspective, Height Zoom, Never Child of Ship

### Community 15 - "Community 15"
Cohesion: 0.5
Nodes (5): Semantic association: standard Godot Engine editor / project joystick-robot logo, Scaled path group: robot head, gear crown, blue face plate (#478cbf), white gear outline, Eye layer: two dark gray circles (#414042) for pupils, Rounded rectangle frame (#363d52 fill, #212532 stroke, rx=14), SVG application icon 128×128 (Godot-style brand mark)

### Community 16 - "Community 16"
Cohesion: 0.5
Nodes (5): Fighter Base Color texture (Blender albedo map), Dark utilitarian / industrial hull color direction, Featureless albedo (no gradients, noise, or markings), Neutral base layer for PBR (detail likely in roughness/normal/metallic), Uniform dark charcoal gray surface (~#444444 RGB)

### Community 17 - "Community 17"
Cohesion: 0.5
Nodes (4): Blueprint Discovery System — variant_id Added to Save Data on Reverse Engineering, ship.json Schema — base_stats, variants, part_stats, hardpoint_types, module_slots, default_loadout, Stat Resolution — base_stats + additive part_stat deltas Applied Once at Spawn, Ship Three Layers — Class (what it is) / Variant (discoverable config) / Loadout (player customizes)

### Community 18 - "Community 18"
Cohesion: 0.67
Nodes (3): All Space Core Spec — Top-Down 3D on XZ Plane, Core Philosophy: Complexity On Demand, All Space — Top-Down 3D Space Simulation Vision

### Community 19 - "Community 19"
Cohesion: 0.67
Nodes (3): Partial Alignment Drag — alignment_drag_current Per-Frame Reset Pattern, Lateral-Only Bleed, Assisted Steering — Predicted Stopping Distance Controls Brake vs Accelerate Torque, Shared Thruster Budget — Turning Priority Over Translation, Diagonal Clamped to Unit

### Community 20 - "Community 20"
Cohesion: 0.67
Nodes (3): Braking Decision Algorithm — Predicted Stop Distance vs Remaining Distance, Project World-Space Thrust onto Ship Axes — Correct Regardless of Facing, Physics Hull JSON Block — mass, max_speed, linear_drag, thruster_force, etc.

### Community 21 - "Community 21"
Cohesion: 0.67
Nodes (3): Star Field System Specification, No 2D Nodes Rule, No Hardcoded Values Rule

### Community 22 - "Community 22"
Cohesion: 1.0
Nodes (2): Combat MVP — 3D Top-Down Space Combat Simulator, Streaming Map — Chunk-Based Seamless World

### Community 23 - "Community 23"
Cohesion: 1.0
Nodes (2): One Ship.tscn for All Ship Types — Configured at Spawn Time, Ship System — One Ship.tscn, Data-Driven Assembly from ship.json + parts.glb

### Community 24 - "Community 24"
Cohesion: 1.0
Nodes (2): ChunkStreamer — Deterministic Procedural Chunk Streaming, Bounded Memory, World Streaming Summary — Deterministic Chunk Grid, GameEventBus chunk_loaded

### Community 25 - "Community 25"
Cohesion: 1.0
Nodes (2): Chunk Coordinate ↔ World Position — Vector2i Grid Coord → Vector3 World Origin, Deterministic RNG Seeded by Chunk Coord Hash — Same Coord = Same Content Every Visit

### Community 26 - "Community 26"
Cohesion: 1.0
Nodes (2): Vertex Color Shader — R=Primary, G=Trim, B=Accent, A=Glow; Shared Material Per Ship, factions.json — color_scheme (primary/trim/accent/glow) + name_vocabulary

### Community 27 - "Community 27"
Cohesion: 1.0
Nodes (2): Weapons Summary — JSON Stats, Damage Types, Heat Per Hardpoint, Power Per Ship, Weapons & Projectiles — Data-Driven, Dual Heat/Power Resources, Dual Pool

### Community 28 - "Community 28"
Cohesion: 1.0
Nodes (2): Aim Direction Algorithm — slerp-Clamp to Arc for Gimbal/Partial Turret, Unconstrained Full Turret, Hardpoint Types — fixed (~5°), gimbal (~25°), partial_turret (~120°), full_turret (360°)

### Community 29 - "Community 29"
Cohesion: 1.0
Nodes (2): Weapon Archetypes — Ballistic, Energy Beam, Energy Pulse, Dumb Missile, Guided Missile, Heat System — Per-Hardpoint heat_current, Overheat Lockout, Passive Cooling

### Community 30 - "Community 30"
Cohesion: 1.0
Nodes (2): Momentum Inheritance — Projectiles Inherit Ship velocity at Spawn, ProjectileManager C# — Dumb Pool (DumbProjectile struct), Hitscan, Swept Raycast

### Community 31 - "Community 31"
Cohesion: 1.0
Nodes (1): Sim-Lite Physics — Mass, Momentum, Angular Inertia

### Community 32 - "Community 32"
Cohesion: 1.0
Nodes (1): Formation Tick Algorithm — Pilot Mode, Slot Destination = Player Pos + Offset Rotated by Yaw

### Community 33 - "Community 33"
Cohesion: 1.0
Nodes (1): New Fleet Command Signals — request_tactical_stop, set_stance, escort_queue_changed, ship_damaged, request_formation_destination

### Community 34 - "Community 34"
Cohesion: 1.0
Nodes (1): Project Structure — Directory Layout

### Community 35 - "Community 35"
Cohesion: 1.0
Nodes (1): Build Order — 15-Step Dependency Sequence

### Community 36 - "Community 36"
Cohesion: 1.0
Nodes (1): Debris — Node3D Visual Only, Manual Velocity Integration, Alpha Fade Timer

### Community 37 - "Community 37"
Cohesion: 1.0
Nodes (1): AI Spawn Point Markers — Node3D in ai_spawn_points Group, ChunkStreamer Agnostic of AI

### Community 38 - "Community 38"
Cohesion: 1.0
Nodes (1): RigidBody3D Configuration — gravity_scale 0, axis_lock_linear_y, DAMP_MODE_REPLACE

### Community 39 - "Community 39"
Cohesion: 1.0
Nodes (1): Hardpoint Empty Naming — HardpointEmpty_{part}_{id}_{size} Uniqueness Convention

### Community 40 - "Community 40"
Cohesion: 1.0
Nodes (1): Thrust Fraction Scaling — AI Expresses Intent (patrol vs pursue speed)

### Community 41 - "Community 41"
Cohesion: 1.0
Nodes (1): Arrival Behavior — Zero Thrust Within arrival_distance, Residual Drift Intentional

### Community 42 - "Community 42"
Cohesion: 1.0
Nodes (1): DriveMode Enum — EXTERNAL / TACTICAL_ORDER / FORMATION Self-Drive (Phase 14)

### Community 43 - "Community 43"
Cohesion: 1.0
Nodes (1): Godot Custom Monitors Registered in GameBootstrap to Avoid Duplicate Registration

### Community 44 - "Community 44"
Cohesion: 1.0
Nodes (1): Graph Report Summary

### Community 45 - "Community 45"
Cohesion: 1.0
Nodes (1): Godot AI Addon README

### Community 46 - "Community 46"
Cohesion: 1.0
Nodes (1): Debug Grid Texture

## Knowledge Gaps
- **93 isolated node(s):** `No Direct Cross-System Calls — GameEventBus Signals Only`, `Specs Are Authoritative — Deviations Require Report`, `Core Philosophy: Complexity On Demand`, `Four Phases of Play (Personal Pilot → Fleet → Infrastructure → Galactic)`, `Combat MVP — 3D Top-Down Space Combat Simulator` (+88 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **Thin community `Community 22`** (2 nodes): `Combat MVP — 3D Top-Down Space Combat Simulator`, `Streaming Map — Chunk-Based Seamless World`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 23`** (2 nodes): `One Ship.tscn for All Ship Types — Configured at Spawn Time`, `Ship System — One Ship.tscn, Data-Driven Assembly from ship.json + parts.glb`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 24`** (2 nodes): `ChunkStreamer — Deterministic Procedural Chunk Streaming, Bounded Memory`, `World Streaming Summary — Deterministic Chunk Grid, GameEventBus chunk_loaded`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 25`** (2 nodes): `Chunk Coordinate ↔ World Position — Vector2i Grid Coord → Vector3 World Origin`, `Deterministic RNG Seeded by Chunk Coord Hash — Same Coord = Same Content Every Visit`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 26`** (2 nodes): `Vertex Color Shader — R=Primary, G=Trim, B=Accent, A=Glow; Shared Material Per Ship`, `factions.json — color_scheme (primary/trim/accent/glow) + name_vocabulary`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 27`** (2 nodes): `Weapons Summary — JSON Stats, Damage Types, Heat Per Hardpoint, Power Per Ship`, `Weapons & Projectiles — Data-Driven, Dual Heat/Power Resources, Dual Pool`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 28`** (2 nodes): `Aim Direction Algorithm — slerp-Clamp to Arc for Gimbal/Partial Turret, Unconstrained Full Turret`, `Hardpoint Types — fixed (~5°), gimbal (~25°), partial_turret (~120°), full_turret (360°)`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 29`** (2 nodes): `Weapon Archetypes — Ballistic, Energy Beam, Energy Pulse, Dumb Missile, Guided Missile`, `Heat System — Per-Hardpoint heat_current, Overheat Lockout, Passive Cooling`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 30`** (2 nodes): `Momentum Inheritance — Projectiles Inherit Ship velocity at Spawn`, `ProjectileManager C# — Dumb Pool (DumbProjectile struct), Hitscan, Swept Raycast`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 31`** (1 nodes): `Sim-Lite Physics — Mass, Momentum, Angular Inertia`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 32`** (1 nodes): `Formation Tick Algorithm — Pilot Mode, Slot Destination = Player Pos + Offset Rotated by Yaw`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 33`** (1 nodes): `New Fleet Command Signals — request_tactical_stop, set_stance, escort_queue_changed, ship_damaged, request_formation_destination`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 34`** (1 nodes): `Project Structure — Directory Layout`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 35`** (1 nodes): `Build Order — 15-Step Dependency Sequence`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 36`** (1 nodes): `Debris — Node3D Visual Only, Manual Velocity Integration, Alpha Fade Timer`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 37`** (1 nodes): `AI Spawn Point Markers — Node3D in ai_spawn_points Group, ChunkStreamer Agnostic of AI`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 38`** (1 nodes): `RigidBody3D Configuration — gravity_scale 0, axis_lock_linear_y, DAMP_MODE_REPLACE`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 39`** (1 nodes): `Hardpoint Empty Naming — HardpointEmpty_{part}_{id}_{size} Uniqueness Convention`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 40`** (1 nodes): `Thrust Fraction Scaling — AI Expresses Intent (patrol vs pursue speed)`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 41`** (1 nodes): `Arrival Behavior — Zero Thrust Within arrival_distance, Residual Drift Intentional`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 42`** (1 nodes): `DriveMode Enum — EXTERNAL / TACTICAL_ORDER / FORMATION Self-Drive (Phase 14)`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 43`** (1 nodes): `Godot Custom Monitors Registered in GameBootstrap to Avoid Duplicate Registration`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 44`** (1 nodes): `Graph Report Summary`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 45`** (1 nodes): `Godot AI Addon README`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 46`** (1 nodes): `Debug Grid Texture`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `AI & Patrol Behavior — State Machine, JSON Profiles, NavigationController` connect `Community 4` to `Community 6`?**
  _High betweenness centrality (0.015) - this node is a cross-community bridge._
- **Are the 18 inferred relationships involving `Sci-Fi Anime Art Style` (e.g. with `Navigator Character 6 - Star Map Navigator` and `Navigator Character 7 - Dark Lit Navigator`) actually correct?**
  _`Sci-Fi Anime Art Style` has 18 INFERRED edges - model-reasoned connections that need verification._
- **Are the 18 inferred relationships involving `Spaceship Interior Setting` (e.g. with `Navigator Character 6 - Star Map Navigator` and `Navigator Character 7 - Dark Lit Navigator`) actually correct?**
  _`Spaceship Interior Setting` has 18 INFERRED edges - model-reasoned connections that need verification._
- **Are the 18 inferred relationships involving `Holographic Display UI Elements` (e.g. with `Navigator Character 6 - Star Map Navigator` and `Navigator Character 7 - Dark Lit Navigator`) actually correct?**
  _`Holographic Display UI Elements` has 18 INFERRED edges - model-reasoned connections that need verification._
- **What connects `No Direct Cross-System Calls — GameEventBus Signals Only`, `Specs Are Authoritative — Deviations Require Report`, `Core Philosophy: Complexity On Demand` to the rest of the system?**
  _93 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 0` be split into smaller, more focused modules?**
  _Cohesion score 0.07 - nodes in this community are weakly interconnected._
- **Should `Community 1` be split into smaller, more focused modules?**
  _Cohesion score 0.12 - nodes in this community are weakly interconnected._