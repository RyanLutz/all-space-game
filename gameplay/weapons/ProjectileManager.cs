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
	[Export] public int DebugMeshCount = 128;  // Max simultaneously rendered projectile spheres
	[Export] public int TracerPoolCapacity = 128;  // Max simultaneous hitscan tracers
	[Export] public float ProjectileRenderRadius = 1.5f;
	[Export] public float TracerWidth = 0.8f;
	[Export] public float TracerLifetimePulse = 0.08f;
	[Export] public float TracerLifetimeBeam = 0.05f;

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

	// ── Projectile/tracer visualization ─────────────────────────────────

	private MultiMesh _projectileMultiMesh;
	private MultiMeshInstance3D _multiMeshInstance;

	private struct TracerEntry
	{
		public Vector3 Origin;
		public Vector3 End;
		public float Lifetime;
		public float MaxLifetime;
		public Color TintColor;
		public bool Active;
	}

	private TracerEntry[] _tracerPool;
	private int _activeTracerCount;
	private MultiMesh _tracerMultiMesh;
	private MultiMeshInstance3D _tracerInstance;

	// ── Lifecycle ───────────────────────────────────────────────────────

	public override void _Ready()
	{
		_perf = global::AllSpace.ServiceLocator.Get("PerformanceMonitor");
		_eventBus = global::AllSpace.ServiceLocator.Get("GameEventBus");
		_contentRegistry = global::AllSpace.ServiceLocator.Get("ContentRegistry");

		_dumbPool = new DumbProjectile[DumbPoolCapacity];
		_tracerPool = new TracerEntry[TracerPoolCapacity];

		_eventBus.Connect("request_spawn_dumb",
			new Callable(this, MethodName.OnRequestSpawnDumb));
		_eventBus.Connect("request_fire_hitscan",
			new Callable(this, MethodName.OnRequestFireHitscan));

		_setup_projectile_visuals();

		GD.Print($"[ProjectileManager] Ready — dumb pool: {DumbPoolCapacity}, render: {DebugMeshCount}, tracers: {TracerPoolCapacity}");
	}

	private void _setup_projectile_visuals()
	{
		// Pooled projectile spheres (ballistic, dumb rocket)
		_multiMeshInstance = new MultiMeshInstance3D();
		_multiMeshInstance.Name = "ProjectileMeshes";
		_multiMeshInstance.CastShadow = GeometryInstance3D.ShadowCastingSetting.Off;
		AddChild(_multiMeshInstance);

		_projectileMultiMesh = new MultiMesh();
		_projectileMultiMesh.TransformFormat = MultiMesh.TransformFormatEnum.Transform3D;
		_projectileMultiMesh.Mesh = _create_projectile_mesh();
		_projectileMultiMesh.InstanceCount = DebugMeshCount;
		_multiMeshInstance.Multimesh = _projectileMultiMesh;

		for (int i = 0; i < DebugMeshCount; i++)
		{
			_projectileMultiMesh.SetInstanceTransform(i,
				new Transform3D(Basis.Identity.Scaled(Vector3.Zero), Vector3.Zero));
		}

		// Pooled hitscan tracers (pulse, beam)
		_tracerInstance = new MultiMeshInstance3D();
		_tracerInstance.Name = "HitscanTracers";
		_tracerInstance.CastShadow = GeometryInstance3D.ShadowCastingSetting.Off;
		AddChild(_tracerInstance);

		_tracerMultiMesh = new MultiMesh();
		_tracerMultiMesh.TransformFormat = MultiMesh.TransformFormatEnum.Transform3D;
		_tracerMultiMesh.UseColors = true;
		_tracerMultiMesh.Mesh = _create_tracer_mesh();
		_tracerMultiMesh.InstanceCount = TracerPoolCapacity;
		_tracerInstance.Multimesh = _tracerMultiMesh;

		for (int i = 0; i < TracerPoolCapacity; i++)
		{
			_tracerMultiMesh.SetInstanceTransform(i,
				new Transform3D(Basis.Identity.Scaled(Vector3.Zero), Vector3.Zero));
			_tracerMultiMesh.SetInstanceColor(i, new Color(1, 1, 1, 0));
		}
	}

	private Mesh _create_projectile_mesh()
	{
		var sphere = new SphereMesh();
		sphere.Radius = ProjectileRenderRadius;
		sphere.Height = ProjectileRenderRadius * 2f;
		sphere.RadialSegments = 8;
		sphere.Rings = 4;

		var mat = new StandardMaterial3D();
		mat.ShadingMode = BaseMaterial3D.ShadingModeEnum.Unshaded;
		mat.AlbedoColor = new Color(1.0f, 0.85f, 0.3f);
		mat.EmissionEnabled = true;
		mat.Emission = new Color(1.0f, 0.7f, 0.2f);
		mat.EmissionEnergyMultiplier = 2.5f;
		sphere.Material = mat;
		return sphere;
	}

	private Mesh _create_tracer_mesh()
	{
		// Unit cube centered at origin, 1 unit in Z. We scale per-instance:
		// scale.z = length, translate to origin, rotate -Z → direction.
		var box = new BoxMesh();
		box.Size = new Vector3(TracerWidth, TracerWidth, 1.0f);

		var mat = new StandardMaterial3D();
		mat.ShadingMode = BaseMaterial3D.ShadingModeEnum.Unshaded;
		mat.Transparency = BaseMaterial3D.TransparencyEnum.Alpha;
		mat.AlbedoColor = new Color(1, 1, 1, 1);
		mat.EmissionEnabled = true;
		mat.Emission = new Color(1, 1, 1);
		mat.EmissionEnergyMultiplier = 2.5f;
		mat.VertexColorUseAsAlbedo = true;
		box.Material = mat;
		return box;
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

		UpdateProjectileVisuals();
		UpdateTracerVisuals(dt);
	}

	// ── Projectile/tracer visualization ────────────────────────────────

	private void UpdateProjectileVisuals()
	{
		int meshIndex = 0;
		for (int i = 0; i < _dumbPool.Length && meshIndex < DebugMeshCount; i++)
		{
			ref var proj = ref _dumbPool[i];
			if (!proj.Active)
				continue;

			var pos = new Vector3(proj.Position.X, 0.5f, proj.Position.Z);
			var transform = new Transform3D(Basis.Identity, pos);
			_projectileMultiMesh.SetInstanceTransform(meshIndex, transform);
			meshIndex++;
		}

		for (int i = meshIndex; i < DebugMeshCount; i++)
		{
			_projectileMultiMesh.SetInstanceTransform(i,
				new Transform3D(Basis.Identity.Scaled(Vector3.Zero), Vector3.Zero));
		}
	}

	private void UpdateTracerVisuals(float dt)
	{
		int active = 0;
		for (int i = 0; i < _tracerPool.Length; i++)
		{
			ref var tr = ref _tracerPool[i];
			if (!tr.Active)
			{
				_tracerMultiMesh.SetInstanceTransform(i,
					new Transform3D(Basis.Identity.Scaled(Vector3.Zero), Vector3.Zero));
				continue;
			}

			tr.Lifetime -= dt;
			if (tr.Lifetime <= 0f)
			{
				tr.Active = false;
				_tracerMultiMesh.SetInstanceTransform(i,
					new Transform3D(Basis.Identity.Scaled(Vector3.Zero), Vector3.Zero));
				continue;
			}

			float alpha = Mathf.Clamp(tr.Lifetime / tr.MaxLifetime, 0f, 1f);
			_tracerMultiMesh.SetInstanceTransform(i, BuildTracerTransform(tr.Origin, tr.End));
			var c = tr.TintColor;
			c.A = alpha;
			_tracerMultiMesh.SetInstanceColor(i, c);
			active++;
		}
		_activeTracerCount = active;
	}

	private static Transform3D BuildTracerTransform(Vector3 origin, Vector3 end)
	{
		var delta = end - origin;
		float length = delta.Length();
		if (length < 0.001f)
			return new Transform3D(Basis.Identity.Scaled(Vector3.Zero), origin);

		var dir = delta / length;
		// Unit box lies along -Z → we want forward = +dir. Use LookingAt from origin.
		var mid = origin + delta * 0.5f;
		mid.Y = 0.5f;

		// Avoid parallel up vector if dir ≈ Y
		var up = Mathf.Abs(dir.Dot(Vector3.Up)) > 0.99f ? Vector3.Forward : Vector3.Up;
		var basis = Basis.LookingAt(-dir, up).Scaled(new Vector3(1f, 1f, length));
		return new Transform3D(basis, mid);
	}

	private void SpawnTracer(Vector3 origin, Vector3 end, Color color, float lifetime)
	{
		for (int i = 0; i < _tracerPool.Length; i++)
		{
			if (_tracerPool[i].Active)
				continue;
			_tracerPool[i].Origin = new Vector3(origin.X, 0f, origin.Z);
			_tracerPool[i].End = new Vector3(end.X, 0f, end.Z);
			_tracerPool[i].Lifetime = lifetime;
			_tracerPool[i].MaxLifetime = lifetime;
			_tracerPool[i].TintColor = color;
			_tracerPool[i].Active = true;
			return;
		}
	}

	private Color TracerColorFor(string archetype)
	{
		return archetype switch
		{
			"energy_beam" => new Color(0.4f, 1.0f, 0.6f, 1f),
			"energy_pulse" => new Color(0.4f, 0.8f, 1.0f, 1f),
			_ => new Color(1.0f, 0.85f, 0.3f, 1f),
		};
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

			var normal = result.ContainsKey("normal") ? result["normal"].AsVector3() : Vector3.Up;
			ApplyDamage(collider, proj.Damage, proj.DamageType, hitPos, normal,
				proj.ComponentDamageRatio, proj.OwnerEntityId);

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
			Vector3 hitNormal = Vector3.Up;
			if (result.ContainsKey("collider"))
			{
				var collider = result["collider"].AsGodotObject() as Node;
				var hitPos = result["position"].AsVector3();
				hitPos = new Vector3(hitPos.X, 0f, hitPos.Z);
				beamEnd = hitPos;
				hitNormal = result.ContainsKey("normal") ? result["normal"].AsVector3() : Vector3.Up;

				ApplyDamage(collider, req.Damage, req.DamageType, hitPos, hitNormal,
					req.ComponentDamageRatio, req.OwnerEntityId);
			}
			else
			{
				beamEnd = endPoint;
			}

			// Tracer VFX — brief visible line from muzzle to hit/endpoint
			float tracerLife = req.DamageType == "energy_beam"
				? TracerLifetimeBeam
				: TracerLifetimePulse;
			SpawnTracer(req.Origin, beamEnd, TracerColorFor(req.DamageType), tracerLife);
		}

		_hitscanQueue.Clear();
	}

	// ── Damage application ──────────────────────────────────────────────

	private string GetSurfaceType(Node target)
	{
		if (target == null) return "hull";
		var shieldHp = target.Get("shield_hp");
		if (shieldHp.VariantType != Variant.Type.Nil)
		{
			float hp = shieldHp.AsSingle();
			if (hp > 0f) return "shield";
		}
		return "hull";
	}

	private void ApplyDamage(Node target, float damage, string damageType,
		Vector3 hitPos, Vector3 normal, float componentRatio, ulong ownerId = 0)
	{
		if (target == null)
			return;

		if (target.HasMethod("apply_damage"))
		{
			target.Call("apply_damage", (double)damage, damageType, hitPos,
				(double)componentRatio, (long)ownerId);
		}

		string surfaceType = GetSurfaceType(target);
		_eventBus.EmitSignal("projectile_hit", hitPos, normal, surfaceType);

		if (surfaceType == "shield" && target is Node3D target3d)
		{
			_eventBus.EmitSignal("shield_hit", target3d, target3d.ToLocal(hitPos));
		}
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
