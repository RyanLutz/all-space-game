extends Control

signal ship_selected(ship_def: Dictionary)

@export var thumbnail_size: Vector2 = Vector2(96, 96)
@export var columns: int = 3

@onready var _title_label: Label = $TitleLabel
@onready var _scroll: ScrollContainer = $ScrollContainer
@onready var _grid: GridContainer = $ScrollContainer/GridContainer

var _placeholder_icon: Texture2D

func _ready() -> void:
    _grid.columns = columns
    _placeholder_icon = _make_placeholder_icon()
    _title_label.text = "Ships"

func populate(ship_defs: Array[Dictionary]) -> void:
    for child in _grid.get_children():
        child.queue_free()

    for def in ship_defs:
        var container := VBoxContainer.new()
        container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        container.alignment = BoxContainer.ALIGNMENT_CENTER

        var btn := Button.new()
        btn.custom_minimum_size = thumbnail_size
        btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
        btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
        btn.expand_icon = true

        var name_label: String = def.get("name", def.get("display_name", def.get("id", "Unknown")))
        btn.tooltip_text = name_label

        var thumb_path: String = def.get("thumbnail", "")
        if thumb_path != "" and FileAccess.file_exists(thumb_path):
            var tex: Texture2D = load(thumb_path)
            btn.icon = tex
        else:
            btn.icon = _placeholder_icon

        btn.pressed.connect(func() -> void:
            ship_selected.emit(def)
        )

        var lbl := Label.new()
        lbl.text = name_label
        lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        lbl.custom_minimum_size = Vector2(thumbnail_size.x, 0)

        container.add_child(btn)
        container.add_child(lbl)
        _grid.add_child(container)

func _make_placeholder_icon() -> Texture2D:
    var img := Image.create(int(thumbnail_size.x), int(thumbnail_size.y), false, Image.FORMAT_RGBA8)
    img.fill(Color(0.15, 0.15, 0.18))
    var cx := int(thumbnail_size.x / 2)
    var cy := int(thumbnail_size.y / 2)
    var pts := PackedVector2Array([
        Vector2(cx, cy - 30),
        Vector2(cx - 20, cy + 20),
        Vector2(cx + 20, cy + 20)
    ])
    for y in range(int(thumbnail_size.y)):
        for x in range(int(thumbnail_size.x)):
            if Geometry2D.is_point_in_polygon(Vector2(x, y), pts):
                img.set_pixel(x, y, Color(0.5, 0.55, 0.6))
    return ImageTexture.create_from_image(img)
