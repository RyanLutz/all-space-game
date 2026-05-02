# Systems catalog

Quick lookup: build step → authoritative spec, JSON ownership, PerformanceMonitor metrics.

## How to update

- Add a row when a new system is specced and built.
- Keep JSON ownership accurate: if you add a new data file, add it here.
- PM metrics: use exactly the canonical strings from [`feature_spec-performance_monitor.md`](feature_spec-performance_monitor.md).
- Signals: do not list them here. See [`feature_spec-game_event_bus_signals.md`](feature_spec-game_event_bus_signals.md).
- This file is navigation only. Specs are authoritative.

## Lookup table

| Step | System | Spec | JSON ownership | PM metrics |
|------|--------|------|----------------|------------|
| 1 | PerformanceMonitor | [`feature_spec-performance_monitor.md`](feature_spec-performance_monitor.md) | — | *(is the monitor)* |
| 2 | ServiceLocator + GameEventBus + GameBootstrap | [`core_spec.md`](core_spec.md) | — | — |
| 3 | ContentRegistry | [`feature_spec-ship_system.md`](feature_spec-ship_system.md) | `/content/**` (scan) | `ContentRegistry.load` |
| 4 | SpaceBody + Ship | [`feature_spec-physics_and_movement.md`](feature_spec-physics_and_movement.md) | — | `Physics.thruster_allocation`, `Physics.active_bodies`, `Ships.active_count` |
| 5 | NavigationController | [`feature_spec-nav_controller.md`](feature_spec-nav_controller.md) | — | `Navigation.update` |
| 6 | ProjectileManager | [`feature_spec-weapons_and_projectiles.md`](feature_spec-weapons_and_projectiles.md) | — | `ProjectileManager.dumb_update`, `ProjectileManager.guided_update`, `ProjectileManager.collision_checks`, `ProjectileManager.active_count` |
| 7 | WeaponComponent + HardpointComponent | [`feature_spec-weapons_and_projectiles.md`](feature_spec-weapons_and_projectiles.md) | `/content/weapons/*/weapon.json` | `HitDetection.component_resolve` |
| 8 | GuidedProjectilePool | [`feature_spec-weapons_and_projectiles.md`](feature_spec-weapons_and_projectiles.md) | — | `ProjectileManager.guided_update` |
| 9 | ShipFactory | [`feature_spec-ship_system.md`](feature_spec-ship_system.md) | `/content/ships/*/ship.json` | `ShipFactory.assemble` |
| 10 | GameCamera | [`feature_spec-camera_system.md`](feature_spec-camera_system.md) | — | `Camera.update` |
| 11 | AIController | [`feature_spec-ai_patrol_behavior.md`](feature_spec-ai_patrol_behavior.md) | `/data/ai_profiles.json` | `AIController.state_updates`, `AIController.active_count` |
| 14 | Fleet Command | [`feature_spec-fleet_command.md`](feature_spec-fleet_command.md) | `/data/factions.json` | — |
| 15 | ChunkStreamer + Asteroid + Debris | [`feature_spec-chunk_streamer.md`](feature_spec-chunk_streamer.md) | `/data/world_config.json` | `ChunkStreamer.load`, `ChunkStreamer.unload`, `ChunkStreamer.loaded_chunks` |
| 17 | Combat VFX | — | `/content/effects/` | — |
| 18–19 | UI Foundation + Pilot HUD | [`feature_spec-ui_design.md`](feature_spec-ui_design.md) | `/data/damage_types.json` (display only) | — |

> Signal contracts are not listed here — see [`feature_spec-game_event_bus_signals.md`](feature_spec-game_event_bus_signals.md) for the full emitter/listener table.
