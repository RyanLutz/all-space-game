extends Node

# GameEventBus — global signal bus for cross-system communication.
# No gameplay logic; signals only. See docs/feature_spec-game_event_bus_signals.md.
# Self-registers with ServiceLocator in _ready().

# ─── Combat ────────────────────────────────────────────────────────────────────
signal projectile_hit(target: Node, damage: float, damage_type: String,
		position: Vector3, component_ratio: float)
signal ship_destroyed(ship: Node, position: Vector3, faction: String)
signal weapon_fired(ship: Node, weapon_id: String, position: Vector3)
signal hardpoint_state_changed(ship: Node, hardpoint_id: String, new_state: String)
signal projectile_spawned(position: Vector3, velocity: Vector3, weapon_data: Dictionary)

# ─── Requests ──────────────────────────────────────────────────────────────────
signal request_spawn_dumb(position: Vector3, velocity: Vector3, lifetime: float,
		weapon_id: String, owner_id: int)
signal request_fire_hitscan(origin: Vector3, direction: Vector3, range_val: float,
		weapon_id: String, owner_id: int)
signal request_spawn_guided(position: Vector3, velocity: Vector3,
		guidance_mode: String, weapon_data: Dictionary, owner_id: int)

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
signal request_tactical_move(ship_ids: Array, destination: Vector3)
signal request_tactical_attack(ship_ids: Array, target_id: int)
signal request_tactical_mine(ship_ids: Array, asteroid_id: int)
signal request_tactical_dock(ship_ids: Array, station_id: int)
signal tactical_selection_changed(ship_ids: Array)

# ─── Station ───────────────────────────────────────────────────────────────────
signal dock_requested(ship: Node, station: Node)
signal dock_complete(ship: Node, station: Node)
signal undock_requested(ship: Node)
signal loadout_changed(ship: Node, slot_id: String, item_id: String)

# ─── Player State ──────────────────────────────────────────────────────────────
signal player_ship_changed(ship: Node)


func _ready() -> void:
	ServiceLocator.Register("GameEventBus", self)
