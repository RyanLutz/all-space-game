extends Node

# GameEventBus - Global signal bus for cross-system communication
# No gameplay logic — only signals; self-registers with ServiceLocator in _ready().

# Projectile / Weapon Events
@warning_ignore("unused_signal")
signal request_spawn_dumb(position: Vector2, velocity: Vector2, lifetime: float, weapon_id: String, owner_id: int)

@warning_ignore("unused_signal")
signal request_fire_hitscan(origin: Vector2, direction: Vector2, range_val: float, weapon_id: String, owner_id: int)

@warning_ignore("unused_signal")
signal request_spawn_guided(position: Vector2, velocity: Vector2, guidance_mode: String, weapon_data: Dictionary, owner_id: int)

@warning_ignore("unused_signal")
signal projectile_hit(target: Node2D, damage: float, type: String, position: Vector2)

@warning_ignore("unused_signal")
signal beam_fired(start_pos: Vector2, end_pos: Vector2, weapon_data: Dictionary, owner_id: int)

@warning_ignore("unused_signal")
signal weapon_fired(ship: Node2D, weapon_id: String, position: Vector2)

@warning_ignore("unused_signal")
signal missile_launched(missile_type: String, position: Vector2, target, owner_id: int)

# Ship / Damage Events
@warning_ignore("unused_signal")
signal ship_destroyed(ship: Node2D, position: Vector2, faction: String)

@warning_ignore("unused_signal")
signal ship_damaged(ship: Node, amount: float, damage_type: String, hit_position: Vector2)

@warning_ignore("unused_signal")
signal shield_depleted(ship: Node)

@warning_ignore("unused_signal")
signal shield_regenerated(ship: Node)

@warning_ignore("unused_signal")
signal hardpoint_destroyed(ship: Node2D, hardpoint_index: int)

# Player State Events
@warning_ignore("unused_signal")
signal player_ship_changed(ship: Node2D)

# VFX / Audio Events (for future VFX system)
@warning_ignore("unused_signal")
signal projectile_spawned(position: Vector2, velocity: Vector2, weapon_data: Dictionary)

@warning_ignore("unused_signal")
signal explosion_triggered(position: Vector2, radius: float, intensity: float)

@warning_ignore("unused_signal")
signal overheat_warning(hardpoint_id: String, heat_percent: float)


func _ready() -> void:
	ServiceLocator.Register("GameEventBus", self)
