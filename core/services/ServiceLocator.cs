using Godot;
using System.Collections.Generic;

namespace AllSpace;

/// <summary>
/// Global service registry — C# autoload singleton.
/// Provides type-safe service lookup for C# systems (ProjectileManager)
/// and callable methods for GDScript systems.
/// </summary>
public partial class ServiceLocator : Node
{
    private readonly Dictionary<string, Node> _services = new();

    /// <summary>
    /// Registers a service by name. Called by GameBootstrap during startup.
    /// </summary>
    public void Register(string name, Node service)
    {
        if (_services.ContainsKey(name))
        {
            GD.PushWarning($"[ServiceLocator] Service '{name}' already registered — overwriting");
            _services.Remove(name);
        }
        _services[name] = service;
    }

    /// <summary>
    /// Retrieves a service by name. Returns null if not found.
    /// GDScript callable version.
    /// </summary>
    public Node GetService(string name)
    {
        return _services.GetValueOrDefault(name);
    }

    /// <summary>
    /// Static helper for C# systems to get services without instance reference.
    /// Uses Engine.GetSingleton to find the ServiceLocator autoload.
    /// </summary>
    public static Node Get(string name)
    {
        var locator = Engine.GetSingleton("ServiceLocator") as ServiceLocator;
        if (locator == null)
        {
            GD.PushError("[ServiceLocator] Singleton not found — ensure it's registered as autoload");
            return null;
        }
        return locator.GetService(name);
    }

    public override void _Ready()
    {
        GD.Print("[ServiceLocator] Ready — service registry initialized");
    }
}
