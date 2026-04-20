extends Node

# ─── Combat ────────────────────────────────────────────────────────────────────
signal projectile_hit(target: Node, damage: float, damage_type: String,
                      position: Vector3, component_ratio: float)
signal ship_destroyed(ship: Node, position: Vector3, faction: String)
signal weapon_fired(ship: Node, weapon_id: String, position: Vector3)
signal hardpoint_state_changed(ship: Node, hardpoint_id: String, new_state: String)
signal projectile_spawned(position: Vector3, velocity: Vector3,
                          weapon_data: Dictionary)

# ─── Requests ──────────────────────────────────────────────────────────────────
signal request_spawn_dumb(position: Vector3, velocity: Vector3, lifetime: float,
                          weapon_id: String, owner_id: int)
signal request_fire_hitscan(origin: Vector3, direction: Vector3, range_val: float,
                            weapon_id: String, owner_id: int)
signal request_spawn_guided(position: Vector3, velocity: Vector3,
                            guidance_mode: String, weapon_data: Dictionary,
                            owner_id: int)

# ─── Ship State ─────────────────────────────────────────────────────────────────
signal shield_depleted(ship: Node)
signal hull_critical(ship: Node, percent: float)
signal power_depleted(ship: Node)

# ─── AI ────────────────────────────────────────────────────────────────────────
signal ai_state_changed(ship_id: int, old_state: String, new_state: String)
signal ai_target_acquired(ship_id: int, target_id: int)
signal ai_target_lost(ship_id: int)

# ─── World ─────────────────────────────────────────────────────────────────────
signal chunk_loaded(chunk_coords: Vector2i)
signal chunk_unloaded(chunk_coords: Vector2i)
signal explosion_triggered(position: Vector3, radius: float, intensity: float)

# ─── Game Mode ─────────────────────────────────────────────────────────────────
signal game_mode_changed(old_mode: String, new_mode: String)

# ─── Tactical Orders ───────────────────────────────────────────────────────────
signal request_tactical_move(ship_ids: Array, destination: Vector3, queue_mode: String)
signal request_tactical_attack(ship_ids: Array, target_id: int, queue_mode: String)
signal request_tactical_mine(ship_ids: Array, asteroid_id: int, queue_mode: String)
signal request_tactical_dock(ship_ids: Array, station_id: int)
signal request_tactical_stop(ship_ids: Array)
signal request_tactical_set_stance(ship_id: int, stance: int)
signal request_tactical_set_escort_stance(stance: int)
signal request_tactical_add_to_escort(ship_id: int)
signal request_tactical_remove_from_escort(ship_id: int)
signal tactical_selection_changed(ship_ids: Array)
signal context_menu_requested(ship_id: int, screen_pos: Vector2)

# ─── Escort & Formation ───────────────────────────────────────────────────────
signal escort_queue_changed(ship_ids: Array)
signal escort_stance_changed(stance: int)
signal request_formation_destination(ship_id: int, destination: Vector3)

# ─── Damage ───────────────────────────────────────────────────────────────────
signal ship_damaged(victim: Node, attacker: Node)

# ─── Station ───────────────────────────────────────────────────────────────────
signal dock_requested(ship: Node, station: Node)
signal dock_complete(ship: Node, station: Node)
signal undock_requested(ship: Node)
signal loadout_changed(ship: Node, slot_id: String, item_id: String)

# ─── Player State ──────────────────────────────────────────────────────────────
signal player_ship_changed(ship: Node)
