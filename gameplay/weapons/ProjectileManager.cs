using Godot;
using System.Collections.Generic;

namespace AllSpace;

/// <summary>
/// High-performance projectile pool and hitscan resolver.
/// Manages all non-guided projectiles (ballistic, dumb rockets) and
/// immediate hitscan resolution (beams, pulses).
///
/// C# only — this is the sole C# gameplay system per architecture rules.
/// Communicates with GDScript systems via GameEventBus signals and
/// ServiceLocator lookups.
/// </summary>
public partial class ProjectileManager : Node3D
{
	[Export] public int DumbPoolCapacity = 1024;

	// ── Dumb projectile pool ────────────────────────────────────────────

	private struct DumbProjectile
	{
		public Vector3 Position;
		public Vector3 Velocity;
		public float Lifetime;
		public float Damage;
		public float ComponentDamageRatio;
		public string DamageType;
		public ulong OwnerEntityId;
		public bool Active;
	}

	private DumbProjectile[] _dumbPool;
	private int _activeDumbCount;

	// ── Hitscan queue ───────────────────────────────────────────────────

	private struct HitscanRequest
	{
		public Vector3 Origin;
		public Vector3 Direction;
		public float Range;
		public float Damage;
		public float ComponentDamageRatio;
		public string DamageType;
		public ulong OwnerEntityId;
	}

	private readonly List<HitscanRequest> _hitscanQueue = new();

	// ── Weapon data cache ───────────────────────────────────────────────

	private struct WeaponCacheEntry
	{
		public float Damage;
		public float ComponentDamageRatio;
		public string DamageType;
	}

	private readonly Dictionary<string, WeaponCacheEntry> _weaponCache = new();

	// ── Service references ──────────────────────────────────────────────

	private Node _perf;
	private Node _eventBus;
	private Node _contentRegistry;

	// ── Lifecycle ───────────────────────────────────────────────────────

	public override void _Ready()
	{
		_perf = global::AllSpace.ServiceLocator.Get("PerformanceMonitor");
		_eventBus = global::AllSpace.ServiceLocator.Get("GameEventBus");
		_contentRegistry = global::AllSpace.ServiceLocator.Get("ContentRegistry");

		_dumbPool = new DumbProjectile[DumbPoolCapacity];

		_eventBus.Connect("request_spawn_dumb",
			new Callable(this, MethodName.OnRequestSpawnDumb));
		_eventBus.Connect("request_fire_hitscan",
			new Callable(this, MethodName.OnRequestFireHitscan));

		GD.Print($"[ProjectileManager] Ready — dumb pool capacity: {DumbPoolCapacity}");
	}

	public override void _PhysicsProcess(double delta)
	{
		float dt = (float)delta;

		// Dumb pool update
		_perf.Call("begin", "ProjectileManager.dumb_update");
		UpdateDumbPool(dt);
		_perf.Call("end", "ProjectileManager.dumb_update");

		// Hitscan resolution
		ProcessHitscanQueue();

		// Collision checks (sweep raycasts for dumb projectiles)
		_perf.Call("begin", "ProjectileManager.collision_checks");
		ProcessDumbCollisions();
		_perf.Call("end", "ProjectileManager.collision_checks");

		// Report active count
		_perf.Call("set_count", "ProjectileManager.active_count", _activeDumbCount);
	}

	// ── Dumb pool update ────────────────────────────────────────────────

	private void UpdateDumbPool(float delta)
	{
		int activeCount = 0;

		for (int i = 0; i < _dumbPool.Length; i++)
		{
			ref var proj = ref _dumbPool[i];
			if (!proj.Active)
				continue;

			proj.Lifetime -= delta;
			if (proj.Lifetime <= 0f)
			{
				proj.Active = false;
				continue;
			}

			proj.Position += proj.Velocity * delta;
			proj.Position = new Vector3(proj.Position.X, 0f, proj.Position.Z);
			activeCount++;
		}

		_activeDumbCount = activeCount;
	}

	// ── Dumb collision checks ───────────────────────────────────────────

	private void ProcessDumbCollisions()
	{
		var spaceState = GetWorld3D()?.DirectSpaceState;
		if (spaceState == null)
			return;

		for (int i = 0; i < _dumbPool.Length; i++)
		{
			ref var proj = ref _dumbPool[i];
			if (!proj.Active)
				continue;

			// Sweep raycast: from where the projectile was to where it is now
			var prevPos = proj.Position - proj.Velocity * (float)GetPhysicsProcessDeltaTime();
			prevPos = new Vector3(prevPos.X, 0f, prevPos.Z);

			// Skip zero-length rays (stationary projectile, shouldn't happen)
			if (prevPos.DistanceSquaredTo(proj.Position) < 0.0001f)
				continue;

			var query = PhysicsRayQueryParameters3D.Create(prevPos, proj.Position);

			// Exclude the owner ship from collision
			var ownerNode = GodotObject.InstanceFromId(proj.OwnerEntityId) as PhysicsBody3D;
			if (ownerNode != null)
			{
				query.Exclude = new Godot.Collections.Array<Rid> { ownerNode.GetRid() };
			}

			var result = spaceState.IntersectRay(query);
			if (!result.ContainsKey("collider"))
				continue;

			// Hit detected
			var collider = result["collider"].AsGodotObject() as Node;
			var hitPos = result["position"].AsVector3();
			hitPos = new Vector3(hitPos.X, 0f, hitPos.Z);

			ApplyDamage(collider, proj.Damage, proj.DamageType, hitPos,
				proj.ComponentDamageRatio);

			proj.Active = false;
			_activeDumbCount--;
		}
	}

	// ── Hitscan resolution ──────────────────────────────────────────────

	private void ProcessHitscanQueue()
	{
		if (_hitscanQueue.Count == 0)
			return;

		var spaceState = GetWorld3D()?.DirectSpaceState;
		if (spaceState == null)
		{
			_hitscanQueue.Clear();
			return;
		}

		foreach (var req in _hitscanQueue)
		{
			var endPoint = req.Origin + req.Direction * req.Range;
			endPoint = new Vector3(endPoint.X, 0f, endPoint.Z);

			var query = PhysicsRayQueryParameters3D.Create(req.Origin, endPoint);

			var ownerNode = GodotObject.InstanceFromId(req.OwnerEntityId) as PhysicsBody3D;
			if (ownerNode != null)
			{
				query.Exclude = new Godot.Collections.Array<Rid> { ownerNode.GetRid() };
			}

			var result = spaceState.IntersectRay(query);

			Vector3 beamEnd;
			if (result.ContainsKey("collider"))
			{
				var collider = result["collider"].AsGodotObject() as Node;
				var hitPos = result["position"].AsVector3();
				hitPos = new Vector3(hitPos.X, 0f, hitPos.Z);
				beamEnd = hitPos;

				ApplyDamage(collider, req.Damage, req.DamageType, hitPos,
					req.ComponentDamageRatio);
			}
			else
			{
				beamEnd = endPoint;
			}

			// Emit beam VFX endpoints for rendering
			_eventBus.EmitSignal("weapon_fired", (Node)null, "", req.Origin);
		}

		_hitscanQueue.Clear();
	}

	// ── Damage application ──────────────────────────────────────────────

	private void ApplyDamage(Node target, float damage, string damageType,
		Vector3 hitPos, float componentRatio)
	{
		if (target == null)
			return;

		if (target.HasMethod("apply_damage"))
		{
			target.Call("apply_damage", (double)damage, damageType, hitPos,
				(double)componentRatio);
		}

		_eventBus.EmitSignal("projectile_hit", target, (double)damage,
			damageType, hitPos, (double)componentRatio);
	}

	// ── Signal handlers ─────────────────────────────────────────────────

	private void OnRequestSpawnDumb(Vector3 position, Vector3 velocity,
		double lifetime, string weaponId, long ownerId)
	{
		var weaponData = GetOrCacheWeapon(weaponId);

		// Find an inactive slot
		for (int i = 0; i < _dumbPool.Length; i++)
		{
			if (_dumbPool[i].Active)
				continue;

			ref var proj = ref _dumbPool[i];
			proj.Position = new Vector3(position.X, 0f, position.Z);
			proj.Velocity = new Vector3(velocity.X, 0f, velocity.Z);
			proj.Lifetime = (float)lifetime;
			proj.Damage = weaponData.Damage;
			proj.ComponentDamageRatio = weaponData.ComponentDamageRatio;
			proj.DamageType = weaponData.DamageType;
			proj.OwnerEntityId = (ulong)ownerId;
			proj.Active = true;
			_activeDumbCount++;
			return;
		}

		GD.PushWarning("[ProjectileManager] Dumb pool exhausted — projectile dropped");
	}

	private void OnRequestFireHitscan(Vector3 origin, Vector3 direction,
		double rangeVal, string weaponId, long ownerId)
	{
		var weaponData = GetOrCacheWeapon(weaponId);

		_hitscanQueue.Add(new HitscanRequest
		{
			Origin = new Vector3(origin.X, 0f, origin.Z),
			Direction = new Vector3(direction.X, 0f, direction.Z).Normalized(),
			Range = (float)rangeVal,
			Damage = weaponData.Damage,
			ComponentDamageRatio = weaponData.ComponentDamageRatio,
			DamageType = weaponData.DamageType,
			OwnerEntityId = (ulong)ownerId
		});
	}

	// ── Weapon data cache ───────────────────────────────────────────────

	private WeaponCacheEntry GetOrCacheWeapon(string weaponId)
	{
		if (_weaponCache.TryGetValue(weaponId, out var cached))
			return cached;

		var data = _contentRegistry.Call("get_weapon", weaponId)
			.AsGodotDictionary();

		float damage = 0f;
		float componentRatio = 0f;
		string archetype = "";

		if (data != null && data.Count > 0)
		{
			archetype = data.ContainsKey("archetype")
				? data["archetype"].AsString() : "";

			if (data.ContainsKey("stats"))
			{
				var stats = data["stats"].AsGodotDictionary();
				if (stats != null)
				{
					damage = stats.ContainsKey("damage")
						? (float)stats["damage"].AsDouble() : 0f;

					// Beams use damage_per_second — store as-is; caller adjusts per frame
					if (damage == 0f && stats.ContainsKey("damage_per_second"))
						damage = (float)stats["damage_per_second"].AsDouble();

					componentRatio = stats.ContainsKey("component_damage_ratio")
						? (float)stats["component_damage_ratio"].AsDouble() : 0f;
				}
			}
		}

		var entry = new WeaponCacheEntry
		{
			Damage = damage,
			ComponentDamageRatio = componentRatio,
			DamageType = ArchetypeToDamageType(archetype)
		};

		_weaponCache[weaponId] = entry;
		return entry;
	}

	private static string ArchetypeToDamageType(string archetype)
	{
		if (archetype.StartsWith("missile"))
			return "missile";
		return archetype;
	}
}
