# All Space MVP — Claude Code Context

## Project
Godot 4.6, GDScript primary, C# for ProjectileManager only.
Jolt physics enabled. CharacterBody2D with manual velocity for ships.

## Architecture
- ServiceLocator.cs — global service registry
- GameEventBus.gd — all cross-system communication goes through here
- PerformanceMonitor.gd — instrument every system per spec

## Specs
All system specs are in /docs/. Read the relevant spec before 
implementing any system. Follow it precisely.

## Rules
- Never hardcode values that belong in JSON
- Always add PerformanceMonitor instrumentation per spec
- Cross-system calls go through GameEventBus, not direct references
- One system per Claude Code session