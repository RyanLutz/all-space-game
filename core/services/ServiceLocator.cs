using Godot;
using System.Collections.Generic;

namespace AllSpace;

/// <summary>
/// Thin service registry. Systems register themselves at bootstrap;
/// other systems look them up by name. No logic beyond storage.
/// </summary>
public partial class ServiceLocator : Node
{
	private readonly Dictionary<string, Node> _services = new();

	public void Register(string name, Node service)
	{
		_services[name] = service;
		GD.Print($"[ServiceLocator] Registered: {name}");
	}

	public Node GetService(string name)
	{
		if (_services.TryGetValue(name, out var service))
			return service;

		GD.PushWarning($"[ServiceLocator] Service not found: {name}");
		return null;
	}

	public bool Has(string name)
	{
		return _services.ContainsKey(name);
	}
}
