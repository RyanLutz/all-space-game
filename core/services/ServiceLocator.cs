using Godot;
using System.Collections.Generic;

namespace AllSpace;

/// <summary>
/// Global service registry. Thin wrapper around a Dictionary.
/// C# only per architecture rules — this is one of two C# files in the project.
///
/// Autoload order: ServiceLocator must be first autoload, before GameBootstrap.
/// </summary>
public partial class ServiceLocator : Node
{
    private readonly Dictionary<string, Node> _services = new();

    /// <summary>
    /// Registers a service. Overwrites if name already exists.
    /// </summary>
    public void Register(string name, Node service)
    {
        _services[name] = service;
    }

    /// <summary>
    /// Gets a registered service, or null if not found.
    /// </summary>
    public Node GetService(string name)
    {
        _services.TryGetValue(name, out var service);
        return service;
    }

    /// <summary>
    /// Static helper for GDScript compatibility: ServiceLocator.GetService("Name")
    /// </summary>
    public static Node GetService(string name)
    {
        var locator = GetInstance();
        if (locator == null)
        {
            GD.PushError("[ServiceLocator] No instance found — is it configured as an autoload?");
            return null;
        }
        return locator.GetService(name);
    }

    /// <summary>
    /// Static helper for GDScript compatibility: ServiceLocator.Register("Name", node)
    /// </summary>
    public static void Register(string name, Node service)
    {
        var locator = GetInstance();
        if (locator == null)
        {
            GD.PushError("[ServiceLocator] No instance found — is it configured as an autoload?");
            return;
        }
        locator.Register(name, service);
    }

    private static ServiceLocator GetInstance()
    {
        // For autoload singletons, Godot adds them to the root
        var root = Engine.GetMainLoop() as SceneTree;
        if (root == null)
            return null;

        // Try to find the autoload by its common names
        var autoload = root.Root.GetNodeOrNull<ServiceLocator>("/root/ServiceLocator");
        if (autoload != null)
            return autoload;

        // Fallback: search for any ServiceLocator in the root
        foreach (var child in root.Root.GetChildren())
        {
            if (child is ServiceLocator sl)
                return sl;
        }

        return null;
    }
}
