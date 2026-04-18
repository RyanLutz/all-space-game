using Godot;
using System.Collections.Generic;

namespace AllSpace;

/// <summary>
/// Global service registry. Thin wrapper around a static Dictionary.
/// C# only per architecture rules — this is one of two C# files in the project.
///
/// Autoload order: ServiceLocator must be first autoload, before GameBootstrap.
/// </summary>
public partial class ServiceLocator : Node
{
    private static readonly Dictionary<string, Node> _services = new();

    /// <summary>
    /// Registers a service. Overwrites if name already exists.
    /// </summary>
    public static void Register(string name, Node service)
    {
        _services[name] = service;
    }

    /// <summary>
    /// Gets a registered service, or null if not found.
    /// </summary>
    public static Node GetService(string name)
    {
        _services.TryGetValue(name, out var service);
        return service;
    }
}
