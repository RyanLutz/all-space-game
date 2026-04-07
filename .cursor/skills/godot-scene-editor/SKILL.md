---
name: godot-scene-editor
description: Read and write Godot 4 .tscn scene files for the All Space project. Use when creating a new scene, adding nodes to an existing scene, attaching scripts, setting node properties, or wiring up parent/child relationships in a .tscn file.
---

# Godot Scene Editor

Godot 4 `.tscn` files are plain-text scene files. This skill covers reading, writing, and editing them correctly.

**Never guess a UID** — read existing UIDs from project files or omit the `uid=` attribute when creating new scenes (Godot will assign one on first open).

---

## File Structure

```
[gd_scene format=3 uid="uid://abc123"]     ← header (uid optional on new files)

[ext_resource ...]                          ← external file references (scripts, textures, etc.)
[sub_resource ...]                          ← inline resources (materials, shapes, etc.)

[node ...]                                  ← scene nodes (first = root)
property = value
```

### Header
```
[gd_scene format=3]
```
Omit `uid=` on new files — Godot generates it on first load. `load_steps=N` (older files) is optional and counted automatically.

---

## Sections

### `[ext_resource]` — External file reference
```
[ext_resource type="Script" path="res://path/to/file.gd" id="1"]
[ext_resource type="Texture2D" path="res://assets/icon.png" id="2"]
[ext_resource type="PackedScene" path="res://gameplay/entities/Ship.tscn" id="3"]
```
- `id` is referenced later as `ExtResource("1")`
- IDs can be strings: `id="1_script"` — use descriptive IDs for clarity in complex scenes
- Every external file used by this scene needs its own `[ext_resource]` entry

### `[sub_resource]` — Inline resource
```
[sub_resource type="CircleShape2D" id="Shape2D_abc"]
radius = 32.0
```
- Referenced as `SubResource("Shape2D_abc")`
- Use for shapes, materials, and other resources owned by this scene

### `[node]` — Scene node
```
[node name="MyNode" type="Node2D"]
position = Vector2(100, 200)
script = ExtResource("1")
```

**Root node** — no `parent` attribute:
```
[node name="RootNode" type="Node2D"]
```

**Child node** — `parent="."` for direct child of root, `parent="ParentName"` for deeper nesting:
```
[node name="Child" type="Sprite2D" parent="."]
[node name="GrandChild" type="CollisionShape2D" parent="Child"]
```

---

## Value Syntax

| Type | Syntax |
|---|---|
| Float | `1.5` |
| Int | `10` |
| Bool | `true` / `false` |
| String | `"hello"` |
| Vector2 | `Vector2(100.0, 200.0)` |
| Vector2i | `Vector2i(1, 2)` |
| Color | `Color(1, 0.5, 0, 1)` (RGBA 0–1) |
| NodePath | `NodePath("Child/GrandChild")` |
| Array | `[1, 2, 3]` or `Array[float]([1.0, 2.0])` |
| Typed array | `PackedFloat32Array(1.0, 2.0, 3.0)` |
| Null | `null` |
| External ref | `ExtResource("id")` |
| Inline ref | `SubResource("id")` |

---

## Common Patterns for This Project

### Minimal scene with a script
```
[gd_scene format=3]

[ext_resource type="Script" path="res://path/to/MyScript.gd" id="1_script"]

[node name="MyNode" type="Node2D"]
script = ExtResource("1_script")
```

### Node with a CollisionShape2D (Area2D)
```
[gd_scene format=3]

[ext_resource type="Script" path="res://path/to/MyScript.gd" id="1_script"]

[sub_resource type="CircleShape2D" id="Shape_detect"]
radius = 400.0

[node name="DetectionArea" type="Area2D"]
script = ExtResource("1_script")

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("Shape_detect")
```

### Camera2D (project convention — sibling, never child of a ship)
```
[node name="GameCamera" type="Camera2D"]
script = ExtResource("1_camera")
```

### CanvasLayer (e.g. UI/HUD overlay)
```
[node name="HUD" type="CanvasLayer"]
layer = 10

[node name="Label" type="Label" parent="."]
text = "Hello"
```

### Instantiated child scene (using PackedScene ext_resource)
```
[ext_resource type="PackedScene" path="res://gameplay/camera/GameCamera.tscn" id="2_camera"]

[node name="GameCamera" parent="." instance=ExtResource("2_camera")]
```

---

## Adding a Node to an Existing Scene

1. Read the existing `.tscn` file fully first
2. Add an `[ext_resource]` entry if the node needs a new script or asset
3. Add `[sub_resource]` entries if the node needs inline resources (shapes, etc.)
4. Append the `[node]` block after all existing nodes
5. Set `parent=` to the correct path relative to root

**Parent path examples:**
- Root's direct child: `parent="."`
- Child of a node named "Weapons": `parent="Weapons"`
- Grandchild: `parent="Weapons/Hardpoint"`

---

## Naming Conventions (This Project)

| Item | Convention | Example |
|---|---|---|
| Scene file | `PascalCase.tscn` | `Ship.tscn` |
| Root node name | Matches filename | `Ship` |
| Script | `snake_case.gd` | `ship.gd` |
| Ext resource IDs | `"N_descriptive"` | `"1_script"`, `"2_camera"` |
| Sub resource IDs | `"Type_name"` | `"Shape2D_detect"` |

---

## Checklist

- [ ] Read the existing `.tscn` file before editing
- [ ] UIDs: don't invent them — omit `uid=` on new files or copy from existing files
- [ ] Each `[ext_resource]` has a unique `id`
- [ ] Root node has no `parent=` attribute
- [ ] All child nodes have a correct `parent=` path
- [ ] For new scripts: the `.gd` file must exist before the scene references it
- [ ] Camera nodes are **never** children of ship nodes in this project
- [ ] If adding a ship scene: use `ShipFactory.spawn_ship()`, don't instantiate `Ship.tscn` directly from GDScript
