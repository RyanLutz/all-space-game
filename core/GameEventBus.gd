extends Node

# GameEventBus - Global signal bus for cross-system communication
# No logic here - just signals that systems can emit and subscribe to

# Projectile / Weapon Events
@warning_ignore("unused_signal")
signal projectile_hit(position: Vector2, weapon_data: Dictionary, target: Node, owner_id: int)

@warning_ignore("unused_signal")
signal beam_fired(start_pos: Vector2, end_pos: Vector2, weapon_data: Dictionary, owner_id: int)

@warning_ignore("unused_signal")
signal weapon_fired(weapon_id: String, hardpoint_id: String, owner_id: int)

@warning_ignore("unused_signal")
signal missile_launched(missile_type: String, position: Vector2, target, owner_id: int)

# Ship / Damage Events
@warning_ignore("unused_signal")
signal ship_destroyed(ship: Node, destroyer_id: int)

@warning_ignore("unused_signal")
signal ship_damaged(ship: Node, amount: float, damage_type: String, hit_position: Vector2)

@warning_ignore("unused_signal")
signal shield_depleted(ship: Node)

@warning_ignore("unused_signal")
signal shield_regenerated(ship: Node)

@warning_ignore("unused_signal")
signal hardpoint_destroyed(ship: Node, hardpoint_id: String)

# VFX / Audio Events (for future VFX system)
@warning_ignore("unused_signal")
signal projectile_spawned(position: Vector2, velocity: Vector2, weapon_data: Dictionary)

@warning_ignore("unused_signal")
signal explosion_triggered(position: Vector2, radius: float, intensity: float)

@warning_ignore("unused_signal")
signal overheat_warning(hardpoint_id: String, heat_percent: float)
