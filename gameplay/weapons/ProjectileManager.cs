#nullable enable
using Godot;
using System;

/// <summary>
/// Pooled dumb ballistic projectiles + hitscan dispatch. C# only (core spec).
/// </summary>
public partial class ProjectileManager : Node
{
	private struct DumbProjectile
	{
		public bool Active;
		public Vector3 Position;
		public Vector3 Velocity;
		public float Lifetime;
		public int OwnerId;
		public string WeaponId;
	}

	private DumbProjectile[] _pool = Array.Empty<DumbProjectile>();
	private int _poolSize = 4096;
	private int _activeCount;
	private int _collisionChecks;

	private Node? _eventBus;
	private Node? _contentRegistry;
	private Node? _perf;

	public override void _Ready()
	{
		var sl = GetNodeOrNull("/root/ServiceLocator");
		if (sl != null)
			_perf = sl.Call("GetService", "PerformanceMonitor").As<Node>();

		LoadPoolConfig();
		_pool = new DumbProjectile[_poolSize];
		for (int i = 0; i < _poolSize; i++)
			_pool[i].Active = false;

		_eventBus = GetNodeOrNull("/root/GameEventBus");
		_contentRegistry = GetNodeOrNull("/root/ContentRegistry");
		if (_eventBus != null)
		{
			_eventBus.Connect("request_spawn_dumb",
				new Callable(this, nameof(OnRequestSpawnDumb)));
			_eventBus.Connect("request_fire_hitscan",
				new Callable(this, nameof(OnRequestFireHitscan)));
		}
	}

	private void LoadPoolConfig()
	{
		if (!FileAccess.FileExists("res://data/projectiles_config.json"))
			return;
		var json = new Json();
		var err = json.Parse(FileAccess.GetFileAsString("res://data/projectiles_config.json"));
		if (err != Error.Ok)
			return;
		var dict = json.Data.AsGodotDictionary();
		if (dict.ContainsKey("dumb_pool_size"))
			_poolSize = (int)(float)dict["dumb_pool_size"];
	}

	public override void _PhysicsProcess(double delta)
	{
		_perf?.Call("begin", "ProjectileManager.dumb_update");
		float dt = (float)delta;
		_activeCount = 0;
		_collisionChecks = 0;

		var space = GetWorld3D()?.DirectSpaceState;
		if (space == null)
		{
			_perf?.Call("set_count", "ProjectileManager.active_count", 0);
			_perf?.Call("set_count", "ProjectileManager.collision_checks", 0);
			_perf?.Call("end", "ProjectileManager.dumb_update");
			return;
		}

		for (int i = 0; i < _pool.Length; i++)
		{
			if (!_pool[i].Active)
				continue;
			_activeCount++;
			var p = _pool[i];
			var prev = p.Position;
			p.Velocity = new Vector3(p.Velocity.X, 0f, p.Velocity.Z);
			p.Position += p.Velocity * dt;
			p.Position = new Vector3(p.Position.X, 0f, p.Position.Z);
			p.Lifetime -= dt;
			if (p.Lifetime <= 0f)
			{
				p.Active = false;
				_pool[i] = p;
				continue;
			}

			var rayLen = prev.DistanceTo(p.Position);
			if (rayLen < 0.001f)
			{
				_pool[i] = p;
				continue;
			}

			var query = PhysicsRayQueryParameters3D.Create(prev, p.Position);
			query.CollideWithAreas = false;
			query.CollideWithBodies = true;
			query.CollisionMask = 0xFFFFFFFF;
			_collisionChecks++;
			var hit = space.IntersectRay(query);

			if (hit.Count > 0 && hit.ContainsKey("collider"))
			{
				var colliderObj = hit["collider"].AsGodotObject();
				var pos = p.Position;
				if (hit.ContainsKey("position"))
					pos = hit["position"].AsVector3();
				pos = new Vector3(pos.X, 0f, pos.Z);
				var damage = GetWeaponDamage(p.WeaponId);
				var dmgType = GetWeaponDamageType(p.WeaponId);
				var ratio = GetComponentRatio(p.WeaponId);
				if (colliderObj is Node n && (int)n.GetInstanceId() != p.OwnerId)
				{
					_eventBus?.EmitSignal("projectile_hit", n, damage, dmgType, pos, ratio);
					var wd = GetWeaponDataDict(p.WeaponId);
					_eventBus?.EmitSignal("projectile_spawned", p.Position, p.Velocity, wd);
				}
				p.Active = false;
			}
			_pool[i] = p;
		}

		_perf?.Call("set_count", "ProjectileManager.active_count", _activeCount);
		_perf?.Call("set_count", "ProjectileManager.collision_checks", _collisionChecks);
		_perf?.Call("end", "ProjectileManager.dumb_update");
	}

	private void OnRequestSpawnDumb(Vector3 position, Vector3 velocity, float lifetime,
		StringName weaponId, int ownerId)
	{
		var wid = weaponId.ToString();
		for (int i = 0; i < _pool.Length; i++)
		{
			if (_pool[i].Active)
				continue;
			_pool[i] = new DumbProjectile
			{
				Active = true,
				Position = new Vector3(position.X, 0f, position.Z),
				Velocity = new Vector3(velocity.X, 0f, velocity.Z),
				Lifetime = lifetime,
				OwnerId = ownerId,
				WeaponId = wid
			};
			return;
		}
	}

	private void OnRequestFireHitscan(Vector3 origin, Vector3 direction, float rangeVal,
		StringName weaponId, int ownerId)
	{
		var space = GetWorld3D()?.DirectSpaceState;
		if (space == null || _eventBus == null)
			return;
		var dir = new Vector3(direction.X, 0f, direction.Z);
		if (dir.LengthSquared() < 0.0001f)
			return;
		dir = dir.Normalized();
		var to = origin + dir * rangeVal;
		var query = PhysicsRayQueryParameters3D.Create(origin, to);
		query.CollideWithBodies = true;
		query.CollideWithAreas = false;
		query.CollisionMask = 0xFFFFFFFF;
		var hit = space.IntersectRay(query);
		if (hit.Count == 0 || !hit.ContainsKey("collider"))
			return;
		var colliderObj = hit["collider"].AsGodotObject();
		if (colliderObj is not Node n)
			return;
		if ((int)n.GetInstanceId() == ownerId)
			return;
		var wid = weaponId.ToString();
		var pos = hit.ContainsKey("position")
			? hit["position"].AsVector3()
			: origin;
		pos = new Vector3(pos.X, 0f, pos.Z);
		var damage = GetWeaponDamage(wid);
		var dmgType = GetWeaponDamageType(wid);
		var ratio = GetComponentRatio(wid);
		_eventBus.EmitSignal("projectile_hit", n, damage, dmgType, pos, ratio);
	}

	private float GetWeaponDamage(string weaponId)
	{
		var cr = _contentRegistry;
		if (cr == null)
			return 10f;
		var w = cr.Call("get_weapon", weaponId).AsGodotDictionary();
		if (w.Count == 0)
			return 10f;
		if (w.ContainsKey("damage"))
			return (float)w["damage"];
		if (w.ContainsKey("damage_per_second"))
			return (float)w["damage_per_second"] * 0.03f;
		return 10f;
	}

	private float GetComponentRatio(string weaponId)
	{
		var cr = _contentRegistry;
		if (cr == null)
			return 0f;
		var w = cr.Call("get_weapon", weaponId).AsGodotDictionary();
		if (w.Count == 0)
			return 0f;
		return w.ContainsKey("component_damage_ratio") ? (float)w["component_damage_ratio"] : 0f;
	}

	private string GetWeaponDamageType(string weaponId)
	{
		var cr = _contentRegistry;
		if (cr == null)
			return "ballistic";
		var w = cr.Call("get_weapon", weaponId).AsGodotDictionary();
		if (w.Count == 0)
			return "ballistic";
		return w.ContainsKey("archetype") ? (string)w["archetype"] : "ballistic";
	}

	private Godot.Collections.Dictionary GetWeaponDataDict(string weaponId)
	{
		var cr = _contentRegistry;
		if (cr == null)
			return new Godot.Collections.Dictionary();
		return cr.Call("get_weapon", weaponId).AsGodotDictionary();
	}
}
