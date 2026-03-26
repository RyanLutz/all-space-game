using Godot;
using System;

public partial class ProjectileManager : Node
{
    private struct DumbProjectile
    {
        public Vector2 Position;
        public Vector2 Velocity;
        public float Lifetime;
        public int WeaponDataId;
        public ulong OwnerEntityId;
        public bool Active;
    }

    [Export] private int _poolSize = 1000;

    private DumbProjectile[] _pool;
    private int _activeCount = 0;
    private int _lastFreedIndex = 0;

    private Node _perfMonitor;
    private Node _eventBus;
    private Godot.Collections.Dictionary<int, Godot.Collections.Dictionary> _weaponData;

    private uint _collisionMask = 1; // Layer 1 for ships/obstacles

    public override void _Ready()
    {
        _pool = new DumbProjectile[_poolSize];
        for (int i = 0; i < _poolSize; i++)
        {
            _pool[i].Active = false;
        }

        _perfMonitor = GetNode<Node>("/root/GameBootstrap/PerformanceMonitor");
        _eventBus = GetNode<Node>("/root/GameEventBus");

        // Weapon requests come through GameEventBus; ProjectileManager performs the actual spawn/fire.
        _eventBus.Connect("request_spawn_dumb", new Callable(this, nameof(OnRequestSpawnDumb)));
        _eventBus.Connect("request_fire_hitscan", new Callable(this, nameof(OnRequestFireHitscan)));

        LoadWeaponData();

        // Register custom monitors
        Performance.AddCustomMonitor("AllSpace/projectile_dumb_ms",
            new Callable(this, nameof(GetDumbUpdateMs)));
        Performance.AddCustomMonitor("AllSpace/projectile_collision_ms",
            new Callable(this, nameof(GetCollisionMs)));
    }

    private void OnRequestSpawnDumb(Vector2 position, Vector2 velocity, float lifetime, string weaponId, int ownerId)
    {
        // Convert signal int ownerId into the ulong used by the projectile pool for instance comparisons.
        _ = SpawnDumb(position, velocity, lifetime, weaponId, (ulong)ownerId);
    }

    private void OnRequestFireHitscan(Vector2 origin, Vector2 direction, float rangeVal, string weaponId, int ownerId)
    {
        FireHitscan(origin, direction, rangeVal, weaponId, (ulong)ownerId);
    }

    private void LoadWeaponData()
    {
        const string filePath = "res://data/weapons.json";
        _weaponData = new Godot.Collections.Dictionary<int, Godot.Collections.Dictionary>();

        using var file = FileAccess.Open(filePath, FileAccess.ModeFlags.Read);
        if (file == null)
        {
            GD.PushError($"ProjectileManager: Failed to open {filePath}");
            return;
        }

        string text = file.GetAsText();

        var json = new Json();
        var parseErr = json.Parse(text);
        if (parseErr != Error.Ok)
        {
            GD.PushError(
                $"ProjectileManager: JSON parse failed for {filePath}: {json.GetErrorMessage()} (line {json.GetErrorLine()})"
            );
            return;
        }

        var data = json.GetData().As<Godot.Collections.Dictionary>();
        if (data == null)
        {
            GD.PushError($"ProjectileManager: Invalid root in {filePath} (expected Dictionary)");
            return;
        }

        if (!data.ContainsKey("weapons"))
        {
            GD.PushError($"ProjectileManager: Missing 'weapons' key in {filePath}");
            return;
        }

        var weapons = data["weapons"].As<Godot.Collections.Array>();
        if (weapons == null)
        {
            GD.PushError($"ProjectileManager: 'weapons' must be an Array in {filePath}");
            return;
        }

        var seenWeaponIds = new System.Collections.Generic.HashSet<string>();
        int id = 0;
        foreach (var weaponObj in weapons)
        {
            var weapon = weaponObj.As<Godot.Collections.Dictionary>();
            if (weapon == null)
            {
                GD.PushError($"ProjectileManager: Weapon entry must be a Dictionary in {filePath}");
                return;
            }

            if (!weapon.ContainsKey("id"))
            {
                GD.PushError($"ProjectileManager: Weapon entry missing 'id' in {filePath}");
                return;
            }

            string weaponId = weapon["id"].AsString();
            if (string.IsNullOrEmpty(weaponId))
            {
                GD.PushError($"ProjectileManager: Weapon entry has empty 'id' in {filePath}");
                return;
            }

            if (!weapon.ContainsKey("archetype"))
            {
                GD.PushError($"ProjectileManager: Weapon '{weaponId}' missing 'archetype' in {filePath}");
                return;
            }

            string archetype = weapon["archetype"].AsString();

            if (seenWeaponIds.Contains(weaponId))
            {
                GD.PushError($"ProjectileManager: Duplicate weapon id '{weaponId}' in {filePath}");
                return;
            }
            seenWeaponIds.Add(weaponId);

            // Validate keys actually used by ProjectileManager (avoid silent fallback defaults).
            switch (archetype)
            {
                case "ballistic":
                case "missile_dumb":
                case "missile_guided":
                    if (!weapon.ContainsKey("damage"))
                    {
                        GD.PushError($"ProjectileManager: Weapon '{weaponId}' missing required key 'damage' in {filePath}");
                        return;
                    }
                    break;
                case "energy_beam":
                    if (!weapon.ContainsKey("damage_per_second"))
                    {
                        GD.PushError($"ProjectileManager: Weapon '{weaponId}' missing required key 'damage_per_second' in {filePath}");
                        return;
                    }
                    break;
                case "energy_pulse":
                    if (!weapon.ContainsKey("damage"))
                    {
                        GD.PushError($"ProjectileManager: Weapon '{weaponId}' missing required key 'damage' in {filePath}");
                        return;
                    }
                    break;
                default:
                    GD.PushError($"ProjectileManager: Weapon '{weaponId}' has unknown archetype '{archetype}' in {filePath}");
                    return;
            }

            _weaponData[id] = weapon;
            id++;
        }
    }

    public double GetDumbUpdateMs()
    {
        if (_perfMonitor == null) return 0.0;
        return _perfMonitor.Call("get_avg_ms", "ProjectileManager.dumb_update").AsDouble();
    }

    public double GetCollisionMs()
    {
        if (_perfMonitor == null) return 0.0;
        return _perfMonitor.Call("get_avg_ms", "ProjectileManager.collision_checks").AsDouble();
    }

    public int SpawnDumb(Vector2 position, Vector2 velocity, float lifetime, string weaponId, ulong ownerId)
    {
        int weaponDataId = -1;
        foreach (var kvp in _weaponData)
        {
            var weapon = kvp.Value;
            if (weapon.ContainsKey("id") && weapon["id"].AsString() == weaponId)
            {
                weaponDataId = kvp.Key;
                break;
            }
        }

        if (weaponDataId < 0) return -1;

        // Find free slot starting from last freed index
        int startIndex = _lastFreedIndex;
        int index = -1;

        for (int i = 0; i < _poolSize; i++)
        {
            int checkIndex = (startIndex + i) % _poolSize;
            if (!_pool[checkIndex].Active)
            {
                index = checkIndex;
                break;
            }
        }

        if (index < 0) return -1; // Pool full

        _pool[index] = new DumbProjectile
        {
            Position = position,
            Velocity = velocity,
            Lifetime = lifetime,
            WeaponDataId = weaponDataId,
            OwnerEntityId = ownerId,
            Active = true
        };

        _activeCount++;

        // Debug/VFX hook: emit spawned projectile snapshot via the event bus.
        // Contract: projectile_spawned(position, velocity, weapon_data)
        if (_eventBus != null && _weaponData.TryGetValue(weaponDataId, out var weaponData) && weaponData != null)
            _eventBus.EmitSignal("projectile_spawned", position, velocity, weaponData);

        return index;
    }

    public override void _PhysicsProcess(double delta)
    {
        float deltaF = (float)delta;

        // Dumb pool update
        _perfMonitor?.Call("begin", "ProjectileManager.dumb_update");

        int newActiveCount = 0;

        for (int i = 0; i < _poolSize; i++)
        {
            if (!_pool[i].Active) continue;

            Vector2 oldPos = _pool[i].Position;
            _pool[i].Position += _pool[i].Velocity * deltaF;
            _pool[i].Lifetime -= deltaF;

            // Lifetime check
            if (_pool[i].Lifetime <= 0)
            {
                _pool[i].Active = false;
                _lastFreedIndex = i;
                continue;
            }

            newActiveCount++;
        }

        _perfMonitor?.Call("end", "ProjectileManager.dumb_update");

        // Collision checks (separate timing)
        _perfMonitor?.Call("begin", "ProjectileManager.collision_checks");
        ProcessCollisions();
        _perfMonitor?.Call("end", "ProjectileManager.collision_checks");

        _activeCount = newActiveCount;
        _perfMonitor?.Call("set_count", "ProjectileManager.active_count", _activeCount);
    }

    private void ProcessCollisions()
    {
        for (int i = 0; i < _poolSize; i++)
        {
            if (!_pool[i].Active) continue;

            Vector2 pos = _pool[i].Position;
            Vector2 vel = _pool[i].Velocity;
            float step = 1.0f / 60.0f; // Assume 60fps step for raycast
            Vector2 motion = vel * step;

            var query = PhysicsRayQueryParameters2D.Create(pos - motion, pos, _collisionMask);
            query.CollideWithBodies = true;
            query.CollideWithAreas = false;

            var result = GetViewport().GetWorld2D().DirectSpaceState.IntersectRay(query);

            if (result.Count > 0)
            {
                var collider = result["collider"].As<Node>();
                if (collider != null && collider.GetInstanceId() != _pool[i].OwnerEntityId)
                {
                    // Hit!
                    Vector2 hitPoint = result["position"].AsVector2();
                    _weaponData.TryGetValue(_pool[i].WeaponDataId, out var weapon);

                    if (weapon != null && collider.HasMethod("apply_damage"))
                    {
                        float damage = weapon["damage"].AsSingle();
                        string archetype = weapon["archetype"].AsString();
                        string damageType = archetype == "ballistic" ? "ballistic" : "missile";

                        collider.Call("apply_damage", damage, damageType, hitPoint);

                        // Emit hit signal (GameEventBus contract: projectile_hit(target, damage, type, position))
                        var target2D = collider as Node2D;
                        _eventBus?.EmitSignal("projectile_hit", target2D, damage, damageType, hitPoint);
                    }

                    _pool[i].Active = false;
                    _lastFreedIndex = i;
                }
            }
        }
    }

    public void FireHitscan(Vector2 origin, Vector2 direction, float range, string weaponId, ulong ownerId)
    {
        Godot.Collections.Dictionary weapon = null;
        foreach (var kvp in _weaponData)
        {
            var w = kvp.Value;
            if (w.ContainsKey("id") && w["id"].AsString() == weaponId)
            {
                weapon = w;
                break;
            }
        }

        if (weapon == null)
        {
            GD.PushError($"ProjectileManager: Unknown weapon id '{weaponId}' in request_fire_hitscan");
            return;
        }

        Vector2 end = origin + direction.Normalized() * range;
        var query = PhysicsRayQueryParameters2D.Create(origin, end, _collisionMask);
        query.CollideWithBodies = true;
        query.CollideWithAreas = false;

        var result = GetViewport().GetWorld2D().DirectSpaceState.IntersectRay(query);

        Vector2 hitPoint = end;
        if (result.Count > 0)
        {
            var collider = result["collider"].As<Node>();
            hitPoint = result["position"].AsVector2();

            if (collider != null && collider.GetInstanceId() != ownerId && collider.HasMethod("apply_damage"))
            {
                string archetype = weapon["archetype"].AsString();
                float damage;
                string damageType;

                if (archetype == "energy_beam")
                {
                    damageType = "energy_beam";
                    damage = weapon["damage_per_second"].AsSingle() * (1.0f / 60.0f);
                }
                else if (archetype == "energy_pulse")
                {
                    damageType = "energy_pulse";
                    damage = weapon["damage"].AsSingle();
                }
                else
                {
                    GD.PushError($"ProjectileManager: Unsupported hitscan archetype '{archetype}' for weapon '{weaponId}'");
                    return;
                }

                collider.Call("apply_damage", damage, damageType, hitPoint);
            }
        }

        // Emit beam fired signal for VFX
        _eventBus?.EmitSignal("beam_fired", origin, hitPoint, weapon, ownerId);
    }

    public int GetActiveCount() => _activeCount;

    public Godot.Collections.Array<Godot.Collections.Dictionary> GetActiveProjectileData()
    {
        var result = new Godot.Collections.Array<Godot.Collections.Dictionary>();
        for (int i = 0; i < _poolSize; i++)
        {
            if (!_pool[i].Active) continue;
            Godot.Collections.Dictionary weapon = null;
            if (_weaponData.ContainsKey(_pool[i].WeaponDataId))
                weapon = _weaponData[_pool[i].WeaponDataId];
            var entry = new Godot.Collections.Dictionary();
            entry["position"] = _pool[i].Position;
            if (weapon != null && weapon.ContainsKey("archetype"))
                entry["archetype"] = weapon["archetype"].AsString();
            else
                entry["archetype"] = "unknown";
            result.Add(entry);
        }
        return result;
    }
}
