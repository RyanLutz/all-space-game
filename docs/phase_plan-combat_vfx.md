# Phase Plan — Combat VFX System
*All Space Combat MVP — Step 17*

**Spec:** `docs/feature_spec-combat_vfx.md`  
**Status:** 🔲 Ready to execute  
**Model:** Session 1 = **Opus** (new autoload, signal contract changes, cross-system cache). Sessions 2–3 = **Sonnet**.

---

## 0. Architecture Decisions

Resolved critical questions against project principles (modularity, SRP, ECS signal-only communication):

| Question | Decision | Rationale |
|---|---|---|
| **Q1 — `ship_destroyed` explosion_id** | Add `ship_spawned(ship: Node)` to GameEventBus. ShipFactory emits it after assembly. VFXManager caches `ship.get_instance_id() → explosion_id` from ContentRegistry. On `ship_destroyed`, VFXManager looks up its own cache (ship node is still valid in the deferred frame). | ECS-aligned: VFXManager owns its own view. No breaking changes to existing `ship_destroyed` listeners (SelectionState, EscortQueue, StanceController). |
| **Q2 — BeamRenderer `to` endpoint** | WeaponComponent computes `to = from + aim_dir * range_val` and passes it to `BeamRenderer.update(from, to)`. | Local effect stays local. No per-frame signal chatter across the bus. Beam visual is authorative to the weapon entity. |
| **Q3 — ShieldMesh creation** | ShipFactory creates ShieldMesh (MeshInstance3D) + ShieldEffectPlayer.gd programmatically during assembly, under `ShipVisual`. Skipped if `shield_max == 0`. | Assembly is ShipFactory’s single responsibility. Avoids unused nodes on ships without shields. |
| **Q4 — Projectile trails** | **Excluded** from this phase. `trail_ballistic` and `trail_missile_exhaust` effect definitions are created (so ContentRegistry indexes them), but ProjectileManager does not attach them. Wiring deferred to ProjectileManager’s own phase. | One system per session. Spec already defers trails. |

---

## 1. Pre-Conditions

All prior steps in `docs/development_guide.md` must be ✅. Specifically:

- Step 2 (GameEventBus) — signals are the only cross-system contract.
- Step 3 (ContentRegistry) — already scans `/content/effects/`; currently reports `0 effects`.
- Step 6 (ProjectileManager C#) — already emits `projectile_hit` and `shield_hit`.
- Step 7 (WeaponComponent + HardpointComponent) — archetypes fire; needs VFX hookup.
- Step 9 (ShipFactory) — assembly authority; will gain ShieldMesh creation + `ship_spawned` emission.
- Step 16 (GameEventBus signal audit) — signal catalog is reconciled.

**No other steps may be modified.**

---

## 2. Session Breakdown

### Session 1 — VFX Core Infrastructure *(Opus)*

**Scope:** Signal contract, autoload registration, world-space pool system, performance instrumentation.

**Files to create:**
- `gameplay/vfx/EffectPool.gd`
- `gameplay/vfx/VFXManager.gd`

**Files to modify:**
- `core/GameEventBus.gd` — add `ship_spawned(ship: Node)`
- `gameplay/entities/ShipFactory.gd` — emit `ship_spawned` after adding ship to tree
- `core/GameBootstrap.gd` — register VFXManager + 3 new custom monitors

**Tasks:**
1. Add `ship_spawned` signal to GameEventBus under Ship State category.
2. ShipFactory: after `get_tree().get_root().add_child.call_deferred(ship)`, emit `ship_spawned` via `_event_bus`.
3. Create `EffectPool.gd` — ring-buffer `Array[GPUParticles3D]`, `acquire()` wraps on overflow.
4. Create `VFXManager.gd` — autoload singleton:
   - `_ready()`: connect `projectile_hit`, `shield_hit`, `ship_destroyed`, `missile_detonated`, `ship_spawned`.
   - `_build_pools()`: ask ContentRegistry for all `effects` IDs, skip `pool_size == 0`, skip `type == "explosion"`, preload `particle_burst` pools.
   - `spawn_effect(effect_id, position, normal)`: acquire from pool, set position, align basis to normal, `restart()`.
   - `spawn_explosion(explosion_id, position)`: read layers, sequence via coroutine (`await` per layer), enforce `y = 0.0`.
   - `_on_ship_spawned()`: read `ship.class_id`, query ContentRegistry for `effects.explosion`, cache by `ship.get_instance_id()`.
   - `_on_ship_destroyed()`: look up cached explosion_id, call `spawn_explosion()`, remove cache entry.
   - `_process()`: `PerformanceMonitor.begin/end("VFXManager.pool_reclaim")` + `set_count("VFXManager.active_effects", _count_active())`.
5. GameBootstrap: add `_register_vfx_manager()` after `_register_projectile_manager()`, register as `VFXManager`.
6. GameBootstrap: add 3 custom monitors to `_register_custom_monitors()`:
   - `AllSpace/vfx_active`
   - `AllSpace/vfx_pool_reclaim_ms`
   - `AllSpace/vfx_explosion_spawn_ms`

**Acceptance:**
- `CombatTest.tscn` runs without errors.
- Console shows: `[ContentRegistry] Loaded: 2 ships, 8 weapons, 2 modules, <N> effects, ...`
- Console shows: `[VFXManager] Built <N> pools`.
- Destroying a ship (e.g., dummy target) logs explosion spawn attempt (even if no explosion content exists yet).

---

### Session 2 — Local Effect Players *(Sonnet)*

**Scope:** MuzzleFlashPlayer, BeamRenderer, ShieldEffectPlayer. All are local scripts attached at assembly time; zero GameEventBus interaction (except ShieldEffectPlayer, which is called by VFXManager on `shield_hit`).

**Files to create:**
- `gameplay/vfx/MuzzleFlashPlayer.gd`
- `gameplay/vfx/BeamRenderer.gd`
- `gameplay/vfx/ShieldEffectPlayer.gd`
- `assets/shaders/shield_ripple.gdshader`

**Files to modify:**
- `gameplay/entities/ShipFactory.gd` — attach MuzzleFlashPlayer to weapon model, attach ShieldEffectPlayer to ShieldMesh
- `gameplay/entities/Ship.gd` — add `shield_mesh: MeshInstance3D` reference (optional, for VFXManager lookup)

**Tasks:**
1. **MuzzleFlashPlayer.gd:**
   - Attached as child of WeaponModel node (sibling to WeaponComponent).
   - `_ready()`: read `effect_id` from parent’s WeaponComponent (or weapon.json via ContentRegistry), create `GPUParticles3D`, configure from JSON (`lifetime`, `color_primary`, `particle_count`, `emit_direction`).
   - `play()`: if `_pool_size == 0` (from JSON) return; `_particles.restart()`.
   - Emission direction: `"sphere"` = omni; `"normal"` = forward (for muzzle, forward is weapon aim).
2. **BeamRenderer.gd:**
   - Attached as child of WeaponModel node.
   - `_ready()`: create `MeshInstance3D` with `CapsuleMesh` (or `BoxMesh`), create `ShaderMaterial` with placeholder beam shader (or `StandardMaterial3D` with emission for placeholder), set `visible = false`.
   - `update(from, to)`: set `_mesh_instance.visible = true`, position at midpoint, `look_at(to)`, scale Z to distance, set shader `u_time_offset = randf() * TAU`.
   - `stop()`: `_mesh_instance.visible = false`.
3. **ShieldEffectPlayer.gd:**
   - Attached as child of ShieldMesh.
   - `_ready()`: cache `_material = shield_mesh.material_override` (or `material`).
   - `play_hit(hit_position_local)`: set shader uniforms `u_hit_origin` (local position) and `u_hit_time` (Time.get_time_dict_from_system() or custom timer).
4. **shield_ripple.gdshader:**
   - Placeholder shader with uniforms: `u_hit_origin`, `u_hit_time`, `u_color`, `u_ripple_speed`, `u_ripple_falloff`.
   - Simple ring/distance-based ripple in fragment.
5. **ShipFactory modifications:**
   - In `_attach_weapon()`: after adding WeaponComponent, instantiate MuzzleFlashPlayer, add as child of weapon_model, initialize with weapon’s `effects.muzzle_flash`.
   - In `_assemble_parts()` or after: create ShieldMesh (SphereMesh, scaled to ship bounds from base_stats or heuristic), add as child of ShipVisual, attach ShieldEffectPlayer.
   - If `resolved_stats.shield_max == 0`: skip ShieldMesh creation.

**Acceptance:**
- `CombatTest.tscn` runs. Ships spawn without errors.
- Weapon models have MuzzleFlashPlayer child nodes.
- Ships with `shield_max > 0` have ShieldMesh + ShieldEffectPlayer.
- BeamRenderer node exists on beam weapon models (can be verified via remote scene tree).

---

### Session 3 — Content Data & WeaponComponent Integration *(Sonnet)*

**Scope:** Create all `effect.json` files, add `effects` blocks to weapon/ship JSON, wire WeaponComponent to call local players.

**Files to create:**
- `content/effects/muzzle_autocannon/effect.json`
- `content/effects/muzzle_pulse_laser/effect.json`
- `content/effects/muzzle_beam_ignite/effect.json`
- `content/effects/muzzle_missile_launch/effect.json`
- `content/effects/beam_laser_blue/effect.json`
- `content/effects/beam_laser_red/effect.json`
- `content/effects/impact_hull/effect.json`
- `content/effects/impact_shield/effect.json`
- `content/effects/shield_ripple_light/effect.json`
- `content/effects/shield_ripple_heavy/effect.json`
- `content/effects/explosion_flash/effect.json`
- `content/effects/explosion_fireball/effect.json`
- `content/effects/explosion_shockwave/effect.json`
- `content/effects/explosion_debris/effect.json`
- `content/effects/explosion_small/effect.json`
- `content/effects/explosion_medium/effect.json`
- `content/effects/explosion_large/effect.json`
- `content/effects/trail_ballistic/effect.json` *(content only; wiring deferred)*
- `content/effects/trail_missile_exhaust/effect.json` *(content only; wiring deferred)*

**Files to modify:**
- `content/weapons/autocannon-small/weapon.json` — add `effects` block
- `content/weapons/pulse_laser-small/weapon.json` — add `effects` block
- `content/weapons/beam_laser-small/weapon.json` — add `effects` block
- `content/weapons/torpedo_launcher-small/weapon.json` — add `effects` block
- `content/ships/axum-fighter-1/ship.json` — add `effects` block
- `content/ships/corvette_patrol/ship.json` — add `effects` block
- `gameplay/weapons/WeaponComponent.gd` — cache MuzzleFlashPlayer/BeamRenderer refs, call them in fire functions

**Tasks:**
1. Create all `/content/effects/<id>/effect.json` files using spec schema:
   - `particle_burst` for muzzles, impacts, sub-explosions (with `pool_size: 0` for local muzzles, `pool_size: 8+` for pooled impacts/sub-effects).
   - `beam` for beam_laser_blue/red (no pool_size).
   - `explosion` for small/medium/large (no pool_size; lists layers).
   - `shield_ripple` for shield_ripple_light/heavy (no pool_size).
2. Update all `weapon.json` files to add `effects` block:
   ```json
   "effects": {
       "muzzle_flash": "muzzle_autocannon",
       "projectile_trail": "trail_ballistic"
   }
   ```
   (beam weapons add `"beam": "beam_laser_blue"`; missile weapons add appropriate muzzle/trail.)
3. Update all `ship.json` files to add `effects` block:
   ```json
   "effects": {
       "explosion": "explosion_small",
       "shield_hit": "shield_ripple_light"
   }
   ```
   - `axum-fighter-1` → `explosion_small`
   - `corvette_patrol` → `explosion_medium` (or `explosion_large` if it's a capital; check ship class)
4. Modify `WeaponComponent.gd`:
   - Add `_muzzle_flash: MuzzleFlashPlayer` and `_beam_renderer: BeamRenderer` refs.
   - In `_ready()` (or `initialize_from_data`): discover siblings, cache refs. Use `has_node("MuzzleFlashPlayer")` etc. Do not assume presence.
   - In `_fire_discrete()`, `_fire_pulse()`, `_fire_guided()`: call `_muzzle_flash.play()` if ref exists.
   - In `_fire_beam()`: call `_beam_renderer.update(from, to)` if ref exists.
   - When `should_fire` goes false or overheated: call `_beam_renderer.stop()` if ref exists.

**Acceptance:**
- ContentRegistry loads all new effects: console shows `Loaded: ... 17 effects ...`
- VFXManager builds pools for all `particle_burst` effects with `pool_size > 0`.
- Firing autocannon shows muzzle flash.
- Firing beam laser shows continuous beam mesh.
- Releasing beam fire input hides beam immediately.
- Projectile hits show impact sparks at correct position, oriented to normal.
- Shield hits trigger shield ripple on correct ship.
- Ship destruction spawns multi-layer explosion.
- `PerformanceOverlay` shows `vfx_active` count.

---

## 3. Complete File Inventory

### New GDScript Files
| File | Session | Owner |
|---|---|---|
| `gameplay/vfx/EffectPool.gd` | 1 | VFXManager |
| `gameplay/vfx/VFXManager.gd` | 1 | World-space effects |
| `gameplay/vfx/MuzzleFlashPlayer.gd` | 2 | Local weapon muzzle |
| `gameplay/vfx/BeamRenderer.gd` | 2 | Local weapon beam |
| `gameplay/vfx/ShieldEffectPlayer.gd` | 2 | Local shield ripple |

### New Shader
| File | Session | Purpose |
|---|---|---|
| `assets/shaders/shield_ripple.gdshader` | 2 | Shield hit visual |

### New Content Folders
| Folder | Session | Type | Pool? |
|---|---|---|---|
| `content/effects/muzzle_autocannon/` | 3 | particle_burst | Local (pool_size 0) |
| `content/effects/muzzle_pulse_laser/` | 3 | particle_burst | Local (pool_size 0) |
| `content/effects/muzzle_beam_ignite/` | 3 | particle_burst | Local (pool_size 0) |
| `content/effects/muzzle_missile_launch/` | 3 | particle_burst | Local (pool_size 0) |
| `content/effects/trail_ballistic/` | 3 | particle_burst | Deferred |
| `content/effects/trail_missile_exhaust/` | 3 | particle_burst | Deferred |
| `content/effects/beam_laser_blue/` | 3 | beam | Local |
| `content/effects/beam_laser_red/` | 3 | beam | Local |
| `content/effects/impact_hull/` | 3 | particle_burst | Pooled |
| `content/effects/impact_shield/` | 3 | particle_burst | Pooled |
| `content/effects/shield_ripple_light/` | 3 | shield_ripple | Local |
| `content/effects/shield_ripple_heavy/` | 3 | shield_ripple | Local |
| `content/effects/explosion_flash/` | 3 | particle_burst | Pooled (sub-effect) |
| `content/effects/explosion_fireball/` | 3 | particle_burst | Pooled (sub-effect) |
| `content/effects/explosion_shockwave/` | 3 | particle_burst | Pooled (sub-effect) |
| `content/effects/explosion_debris/` | 3 | particle_burst | Pooled (sub-effect) |
| `content/effects/explosion_small/` | 3 | explosion | Multi-layer |
| `content/effects/explosion_medium/` | 3 | explosion | Multi-layer |
| `content/effects/explosion_large/` | 3 | explosion | Multi-layer |

### Modified Files
| File | Session | Change |
|---|---|---|
| `core/GameEventBus.gd` | 1 | Add `ship_spawned(ship: Node)` signal |
| `core/GameBootstrap.gd` | 1 | Register VFXManager; add 3 custom monitors |
| `gameplay/entities/ShipFactory.gd` | 1, 2 | Emit `ship_spawned`; create ShieldMesh + attach ShieldEffectPlayer; attach MuzzleFlashPlayer to weapon models |
| `gameplay/weapons/WeaponComponent.gd` | 3 | Cache + call MuzzleFlashPlayer / BeamRenderer |
| `content/weapons/*/weapon.json` | 3 | Add `effects` block to all 4 weapons |
| `content/ships/*/ship.json` | 3 | Add `effects` block to all 2 ships |

---

## 4. Signal Contract Changes

### New Signal

```gdscript
# core/GameEventBus.gd — under "Ship State" category
signal ship_spawned(ship: Node)
```

| Signal | Args | Emitted By | Listened By |
|---|---|---|---|
| `ship_spawned` | `ship: Node` | ShipFactory | VFXManager (caches explosion_id) |

### Existing Signals Used by VFXManager (no signature changes)

| Signal | Args | Emitted By | Listened By |
|---|---|---|---|
| `projectile_hit` | `position: Vector3, normal: Vector3, surface_type: String` | ProjectileManager | VFXManager |
| `shield_hit` | `ship: Node3D, hit_position_local: Vector3` | ProjectileManager | VFXManager → ShieldEffectPlayer |
| `ship_destroyed` | `ship: Node, position: Vector3, faction: String` | Ship | VFXManager (looks up cache) |
| `missile_detonated` | `position: Vector3, explosion_id: String` | GuidedProjectilePool (future) / CombatTest (stub) | VFXManager |

---

## 5. Data Schema Quick Reference

### particle_burst (pooled or local)
```json
{
    "type": "particle_burst",
    "pool_size": 8,
    "lifetime": 0.35,
    "color_primary":   [1.0, 0.6, 0.15, 1.0],
    "color_secondary": [1.0, 0.1, 0.0, 0.0],
    "particle_count": 20,
    "particle_speed_min": 30.0,
    "particle_speed_max": 100.0,
    "scale": 1.0,
    "emit_direction": "normal"
}
```
- `pool_size: 0` → disables; silently skipped by VFXManager and local players.
- `emit_direction`: `"normal"` aligns to surface; `"sphere"` emits omni.

### beam
```json
{
    "type": "beam",
    "color_core":   [0.55, 0.85, 1.0, 1.0],
    "color_glow":   [0.2,  0.5,  1.0, 0.4],
    "width_core": 0.08,
    "width_glow":  0.35,
    "flicker_hz":  14.0,
    "impact_flash_color": [1.0, 1.0, 1.0, 1.0],
    "impact_flash_radius": 0.4
}
```

### explosion (multi-layer)
```json
{
    "type": "explosion",
    "layers": [
        { "effect": "explosion_flash",     "delay": 0.0,  "scale": 1.0 },
        { "effect": "explosion_fireball",  "delay": 0.04, "scale": 1.2 },
        { "effect": "explosion_shockwave", "delay": 0.08, "scale": 1.6 },
        { "effect": "explosion_debris",    "delay": 0.04, "scale": 0.9 }
    ]
}
```

### shield_ripple
```json
{
    "type": "shield_ripple",
    "color":          [0.4, 0.7, 1.0, 0.8],
    "ripple_speed":   2.5,
    "ripple_falloff": 1.8,
    "flash_duration": 0.12
}
```

### weapon.json effects block
```json
"effects": {
    "muzzle_flash": "muzzle_autocannon",
    "projectile_trail": "trail_ballistic"
}
```
Beam weapons add `"beam": "beam_laser_blue"`.

### ship.json effects block
```json
"effects": {
    "explosion": "explosion_small",
    "shield_hit": "shield_ripple_light"
}
```

---

## 6. Test & Verification Plan

### Per-Session Tests

**Session 1:**
1. Run `CombatTest.tscn`.
2. Verify console: `[ContentRegistry] Loaded: ... 0 effects` (no content yet).
3. Verify console: `[VFXManager] Built 0 pools` (graceful empty state).
4. Spawn dummy target, damage until destroyed.
5. Verify VFXManager logs cache miss (no explosion_id cached yet — expected).

**Session 2:**
1. Run `CombatTest.tscn`.
2. Inspect remote scene tree: verify `MuzzleFlashPlayer` child under each weapon model.
3. Verify `ShieldMesh` exists under `ShipVisual` on ships with shields.
4. Verify `BeamRenderer` exists under beam weapon models.

**Session 3:**
1. Run `CombatTest.tscn`.
2. **Muzzle flash:** Fire LMB (autocannon) — bright flash at muzzle position. Fire RMB (pulse laser) — softer pop.
3. **Beam:** Switch to beam weapon (if not in default loadout, temporarily override `CombatTest.gd` loadout) — continuous line from muzzle to aim point. Release fire — beam disappears same frame.
4. **Impact:** Shoot dummy target — sparks at hit position, oriented to surface normal.
5. **Shield hit:** Shoot a shielded ship until shields deplete — ripple shader visible on shield mesh.
6. **Explosion:** Destroy a ship — multi-layer explosion plays, each layer delayed per JSON.
7. **Pool exhaustion:** Temporarily set `impact_hull` `pool_size` to 2, fire rapidly — oldest effects recycled silently, no errors.
8. **Disable:** Set any effect `pool_size` to 0 — that effect stops spawning, no errors.
9. **PerformanceOverlay:** Press F3, verify `vfx_active` count is present and updates.
10. **Y-enforcement:** Verify all world-space VFX spawn at `y = 0.0` (check global_position in remote inspector).

### Regression Tests

After each session, run these existing test scenes to ensure no breakage:
- `test/CombatTest.tscn` — full combat loop (pilot + AI + tactical)
- `test/ShipFactoryTest.tscn` — ship assembly integrity
- `test/WeaponTest.tscn` — weapon firing logic

---

## 7. Success Criteria Checklist

Directly from `feature_spec-combat_vfx.md` §10, mapped to sessions:

| # | Criterion | Session | Verification |
|---|---|---|---|
| 1 | Muzzle flash plays at correct world position per archetype | 3 | Visual inspection in CombatTest |
| 2 | Autocannon = bright flash; pulse laser = softer pop | 3 | Visual inspection |
| 3 | Beam renders continuous line from Muzzle to hit point | 3 | Visual inspection |
| 4 | Beam disappears same frame when fire released / overheated | 3 | Frame-step or visual inspection |
| 5 | Hull impact sparks at correct position, oriented to normal | 3 | Visual inspection |
| 6 | Shield ripple activates on correct ship's shield mesh | 3 | Visual inspection |
| 7 | Ship destruction spawns explosion tier from ship.json | 3 | Destroy dummy target in CombatTest |
| 8 | Missile detonation spawns explosion at detonation position | 3 | Spawn guided missile, let it hit |
| 9 | Multi-layer explosion sequences with correct delays | 3 | Visual timing inspection |
| 10 | explosion_small / medium / large visually distinct | 3 | Compare destroy different ship classes |
| 11 | All world-space spawns enforce `y = 0` | 1, 3 | Remote inspector / assert |
| 12 | `pool_size: 0` disables effect with no errors | 3 | Set pool_size to 0, run CombatTest |
| 13 | New effect added by new folder only — no code changes | 3 | Create test effect folder, verify ContentRegistry picks it up |
| 14 | weapon.json `effects` block drives muzzle/trail | 3 | Swap muzzle effect ID, verify visual changes |
| 15 | ship.json `effects` block drives explosion/shield | 3 | Swap explosion ID, verify different visual |
| 16 | 50+ simultaneous instances within 60fps frame budget | 3 | Spawn many ships, observe PerformanceOverlay |
| 17 | `VFXManager.active_effects` visible in PerformanceOverlay | 1 | F3 debug overlay |

---

## 8. Risk Register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| **Signal cache stale on `ship_destroyed`** — ship freed before VFXManager handler runs | Low | High | `queue_free()` is deferred to end-of-frame; signal handlers run in same frame. VFXManager looks up cache immediately in signal handler. Add null-check + cache-remove regardless. |
| **ProjectileManager hitscan emit point ≠ beam visual endpoint** | Medium | Medium | Acceptable: beam visual stretches to `range_val`, damage raycast is independent. Document in code that visual and damage are decoupled by design. |
| **ShieldMesh scale wrong for different ship classes** | Medium | Low | Start with SphereMesh scaled by a heuristic (e.g., `mass * 0.001`). Tune per-ship in JSON later. |
| **GPUParticles3D material creation too heavy for _ready()** | Low | Medium | Create particles at _ready() once per weapon; only restart (lightweight) per shot. If profiling shows issue, defer material creation to pool construction. |
| **C# ProjectileManager signal emission changed in future** | Low | High | VFXManager only listens to GameEventBus; if ProjectileManager changes, only GameEventBus contract matters. Already reconciled in Step 16. |
| **CombatTest main scene regression** | Medium | High | Run `CombatTest.tscn` after every session. No changes to InputManager, GameCamera, or tactical systems. |

---

## 9. Post-Completion

After all 3 sessions are ✅:

1. **Update `docs/development_guide.md`** — add Step 17 row:
   ```
   | 17 | ✅ | Combat VFX System | feature_spec-combat_vfx.md | Opus + Sonnet | Muzzle, beam, impact, shield, explosions. 3 sessions. |
   ```
2. **Update `AGENTS.md`** if directory structure or autoload order changed.
3. **Commit** with message: `feat(vfx): combat visual effects — muzzle, beam, impact, shield, explosions`
4. **Art pass deferred:** Colors, particle process materials, beam shader refinement, shield mesh geometry — all marked placeholder. Future session when combat mechanics are proven.

---

*End of Phase Plan*
