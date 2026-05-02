class_name StarRecord
extends RefCounted

## Data record for a single star in the galaxy catalog.
## Instances are created by StarRegistry at startup and held for the session lifetime.
## Runtime-only fields (lod_state, mesh_node) are mutated by StarRegistry; all other
## fields are set once at generation time and never changed.

# ─── Catalog Fields (set at generation, immutable after) ────────────────────
var id: int                   # Unique index within the catalog
var position: Vector3         # World-space position; Y = 0 for destination stars
var tier: StringName          # &"backdrop" or &"destination"
var star_type: StringName     # &"red_dwarf", &"yellow_dwarf", &"blue_giant", etc.
var radius: float             # Visual radius in world units
var exclusion_radius: float   # Hard no-fly boundary (always >= radius)
var color: Color              # Derived from star_type at generation time
var light_energy: float       # OmniLight3D intensity when mesh is active

# ─── Runtime State (mutated by StarRegistry) ────────────────────────────────
var lod_state: int = 0        # 0 = point (MultiMesh), 1 = glow (screen-pass), 2 = mesh
var mesh_node: Node3D = null  # Non-null only when LOD 2 mesh is spawned

# ─── Destination Stars Only ──────────────────────────────────────────────────
var faction_id: StringName = &""
var economy_data: Dictionary = {}
