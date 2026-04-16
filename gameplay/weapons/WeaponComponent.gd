class_name WeaponComponent
extends Node3D

var _ship: Ship
var _weapon_data: Dictionary = {}
var _hardpoint: HardpointComponent
var _fire_cd: float = 0.0
var _muzzle: Marker3D


func setup(ship: Ship, weapon_data: Dictionary, hp: HardpointComponent) -> void:
	_ship = ship
	_weapon_data = weapon_data
	_hardpoint = hp
	_muzzle = Marker3D.new()
	_muzzle.name = "Muzzle"
	_muzzle.position = Vector3(0, 0, -1.5)
	add_child(_muzzle)


func _physics_process(delta: float) -> void:
	if _ship == null or _hardpoint == null:
		return
	if not _hardpoint.is_group_active(_ship.input_fire):
		return
	var archetype: String = str(_weapon_data.get("archetype", "ballistic"))
	if archetype == "energy_pulse" or archetype == "energy_beam":
		_fire_hitscan(delta, archetype)
		return
	if archetype == "missile_guided":
		_fire_guided(delta)
		return
	if archetype != "ballistic" and archetype != "missile_dumb":
		return
	_fire_cd -= delta
	if _fire_cd > 0.0:
		return
	var rate: float = float(_weapon_data.get("fire_rate", 5.0))
	_fire_cd = 1.0 / maxf(rate, 0.01)
	_fire_projectile()


func _fire_guided(delta: float) -> void:
	_fire_cd -= delta
	if _fire_cd > 0.0:
		return
	var rate: float = float(_weapon_data.get("fire_rate", 1.0))
	_fire_cd = 1.0 / maxf(rate, 0.01)
	var bus: Node = ServiceLocator.GetService("GameEventBus") as Node
	if bus == null:
		return
	var muzzle_pos: Vector3 = _muzzle.global_position
	muzzle_pos.y = 0.0
	var dir: Vector3 = -_muzzle.global_transform.basis.z
	dir.y = 0.0
	dir = dir.normalized()
	var spd: float = float(_weapon_data.get("speed", 400.0))
	var vel: Vector3 = dir * spd + _ship.linear_velocity
	vel.y = 0.0
	var wd: Dictionary = _weapon_data.duplicate()
	wd["id"] = str(_weapon_data.get("id", ""))
	var lock_tgt: Node = _resolve_guidance_target()
	if lock_tgt != null:
		wd["lock_target_id"] = lock_tgt.get_instance_id()
	bus.emit_signal(
		"request_spawn_guided",
		muzzle_pos,
		vel,
		str(_weapon_data.get("guidance", "auto_lock")),
		wd,
		_ship.get_instance_id()
	)


func _resolve_guidance_target() -> Node:
	var player_ship: Node = PlayerState.get_active_ship()
	if player_ship == null:
		return null
	if _ship.get_instance_id() != player_ship.get_instance_id():
		return player_ship
	var ais: Array[Node] = _ship.get_tree().get_nodes_in_group("ai_ships")
	if ais.is_empty():
		return null
	return ais[0] as Node


func _fire_hitscan(delta: float, _archetype: String) -> void:
	_fire_cd -= delta
	if _fire_cd > 0.0:
		return
	var rate: float = float(_weapon_data.get("fire_rate", 5.0))
	_fire_cd = 1.0 / maxf(rate, 0.01)
	var bus: Node = ServiceLocator.GetService("GameEventBus") as Node
	if bus == null:
		return
	var origin: Vector3 = _muzzle.global_position
	origin.y = 0.0
	var dir: Vector3 = -_muzzle.global_transform.basis.z
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = -_ship.global_transform.basis.z
	dir = dir.normalized()
	var range_val: float = float(_weapon_data.get("range", 500.0))
	var weapon_id: String = str(_weapon_data.get("id", ""))
	bus.emit_signal(
		"request_fire_hitscan",
		origin,
		dir,
		range_val,
		weapon_id,
		_ship.get_instance_id()
	)
	bus.emit_signal("weapon_fired", _ship, weapon_id, origin)


func _fire_projectile() -> void:
	var bus: Node = ServiceLocator.GetService("GameEventBus") as Node
	if bus == null or _ship == null:
		return
	var muzzle_pos: Vector3 = _muzzle.global_position
	muzzle_pos.y = 0.0
	var dir: Vector3 = -_muzzle.global_transform.basis.z
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = -_ship.global_transform.basis.z
	dir = dir.normalized()
	var muzzle_speed: float = float(_weapon_data.get("muzzle_speed", 800.0))
	var inherit: Vector3 = _ship.linear_velocity
	inherit.y = 0.0
	var velocity: Vector3 = dir * muzzle_speed + inherit
	var lifetime: float = float(_weapon_data.get("projectile_lifetime", 2.0))
	var weapon_id: String = str(_weapon_data.get("id", ""))
	bus.emit_signal(
		"request_spawn_dumb",
		muzzle_pos,
		velocity,
		lifetime,
		weapon_id,
		_ship.get_instance_id()
	)
	bus.emit_signal("weapon_fired", _ship, weapon_id, muzzle_pos)
