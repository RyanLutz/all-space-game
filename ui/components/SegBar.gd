extends Control
class_name SegBar

## Reusable segmented bar for shield display.
## 10 equal segments in a horizontal row, 2px gap between segments.
## Segment height: 8px. Inactive: grey-08 fill, grey-20 border. Active: accent fill.
## set_ratio(0.0–1.0) lights floor(ratio * 10) segments.

const SEGMENT_COUNT  := 10
const SEGMENT_HEIGHT := 8
const SEGMENT_GAP    := 2

var _segments: Array[ColorRect] = []
var _active_color: Color = UITokens.ACCENT


func _ready() -> void:
	custom_minimum_size = Vector2(0, SEGMENT_HEIGHT)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", SEGMENT_GAP)
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hbox)

	for i in SEGMENT_COUNT:
		var seg := ColorRect.new()
		seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		seg.color = UITokens.GREY_08
		hbox.add_child(seg)
		_segments.append(seg)


## ratio is 0.0–1.0. Lights up floor(ratio * SEGMENT_COUNT) segments.
func set_ratio(ratio: float) -> void:
	var lit := floori(clampf(ratio, 0.0, 1.0) * SEGMENT_COUNT)
	for i in SEGMENT_COUNT:
		_segments[i].color = _active_color if i < lit else UITokens.GREY_08


## Override segment active color (default: ACCENT for Pilot, TAC_ACCENT for Tactical).
func set_active_color(color: Color) -> void:
	_active_color = color
