#nullable enable
using Godot;
using System;
using System.Collections.Generic;

/// <summary>
/// Global service registry (autoload). Register services from GameBootstrap before gameplay autoloads run.
/// </summary>
public partial class ServiceLocator : Node
{
    private readonly Dictionary<string, GodotObject> _services = new(StringComparer.Ordinal);

    public void Register(string name, GodotObject? service)
    {
        if (string.IsNullOrEmpty(name))
        {
            GD.PushError("ServiceLocator.Register: name cannot be empty");
            return;
        }

        if (service == null)
        {
            _services.Remove(name);
            return;
        }

        _services[name] = service;
    }

    /// <summary>
    /// Returns the registered service, or null if missing. Named GetService (not Get) so GDScript can call
    /// get_service() without colliding with Object.get(property).
    /// </summary>
    public GodotObject? GetService(string name)
    {
        return _services.TryGetValue(name, out var obj) ? obj : null;
    }

    public bool HasService(string name) => _services.ContainsKey(name);
}
