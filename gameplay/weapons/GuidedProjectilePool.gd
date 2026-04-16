extends Node

## Minimal guided missile pool — homing toward a target instance id. See weapons spec.

var _bus: Node
var _perf: Node
var _missiles: Array[Dictionary] = []


func _ready() -> void:
	_bus = ServiceLocator.GetService("GameEventBus") as Node
	_perf = ServiceLocator.GetService("PerformanceMonitor") as Node
	if _bus != null:
		_bus.connect("request_spawn_guided", Callable(self, "_on_request_spawn_guided"))


func _physics_process(_delta: float) -> void:
	if _perf != null:
		_perf.begin("ProjectileManager.guided_update")
	var dt := get_physics_process_delta_time()
	var i := 0
	while i < _missiles.size():
		var m: Dictionary = _missiles[i]
		var pos: Vector3 = m["position"]
		var vel: Vector3 = m["velocity"]
		var spd: float = m["speed"]
		var tgt_id: int = m["target_id"]
		var node := instance_from_id(tgt_id) as Node3D
		var tpos: Vector3 = pos + vel * 2.0
		if node != null and is_instance_valid(node):
			tpos = node.global_position
			tpos.y = 0.0
		var to_t: Vector3 = (tpos - pos)
		to_t.y = 0.0
		if to_t.length_squared() > 0.0001:
			vel = to_t.normalized() * spd
		pos += vel * dt
		pos.y = 0.0
		m["position"] = pos
		m["velocity"] = vel
		m["lifetime"] = float(m["lifetime"]) - dt
		if float(m["lifetime"]) <= 0.0:
			_missiles.remove_at(i)
			continue
		# Simple proximity hit
		if node != null and is_instance_valid(node):
			if pos.distance_to(node.global_position) < 8.0:
				var dmg: float = float(m["damage"])
				var wdata: Dictionary = m["weapon_data"]
				var wid: String = str(wdata.get("id", ""))
				if _bus != null:
					_bus.emit_signal(
						"projectile_hit",
						node,
						dmg,
						"missile",
						pos,
						float(wdata.get("component_damage_ratio", 0.2))
					)
				_missiles.remove_at(i)
				continue
		i += 1
	if _perf != null:
		_perf.end("ProjectileManager.guided_update")
		_perf.set_count("ProjectileManager.guided_count", _missiles.size())


func _on_request_spawn_guided(
	pos: Vector3,
	vel: Vector3,
	_guidance_mode: String,
	weapon_data: Dictionary,
	owner_id: int
) -> void:
	var spd: float = float(weapon_data.get("speed", weapon_data.get("muzzle_speed", 400.0)))
	var p := pos
	p.y = 0.0
	var v := vel
	v.y = 0.0
	if v.length_squared() < 0.0001:
		v = Vector3.FORWARD * spd
	else:
		v = v.normalized() * spd
	var tgt_id: int = int(weapon_data.get("lock_target_id", 0))
	_missiles.append(
		{
			"position": p,
			"velocity": v,
			"speed": spd,
			"lifetime": float(weapon_data.get("projectile_lifetime", 4.0)),
			"weapon_data": weapon_data,
			"damage": float(weapon_data.get("damage", 80.0)),
			"owner_id": owner_id,
			"target_id": tgt_id,
		}
	)
