@CLAUDE.md

## Project Structure Notes

### Autoloads (registered in GameBootstrap.gd)
- `ServiceLocator` — singleton registry
- `GameEventBus` — cross-system signal bus
- `ContentRegistry` — JSON content loader
- `ProjectileManager` — C# projectile pool
- `VFXManager` — combat visual effects (added Step 17)

### New Directories (Step 17)
- `gameplay/vfx/` — VFX scripts: EffectPool, VFXManager, MuzzleFlashPlayer, BeamRenderer, ShieldEffectPlayer
- `content/effects/` — effect JSON definitions (19 effect types)
- `assets/shaders/shield_ripple.gdshader` — shield hit ripple shader
