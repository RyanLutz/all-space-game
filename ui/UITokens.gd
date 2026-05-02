extends Node

## All color, typography, and surface design tokens for All Space UI.
## Every UI file must reference these constants — no hardcoded values elsewhere.
## Registered as autoload "UITokens" in project.godot.

# ─── Grey Scale — Primary Text System ─────────────────────────────────────────
# Base: rgb(210, 218, 224) — slightly cool light grey, never pure white.

const GREY_100 := Color(0.824, 0.855, 0.878, 0.95)   # Primary text — names, active values
const GREY_80  := Color(0.824, 0.855, 0.878, 0.70)   # Secondary text — data readouts
const GREY_50  := Color(0.824, 0.855, 0.878, 0.42)   # Tertiary — labels, keys, hints
const GREY_20  := Color(0.824, 0.855, 0.878, 0.16)   # Borders, dividers, bar tracks
const GREY_08  := Color(0.824, 0.855, 0.878, 0.06)   # Subtle fills — inactive slots, bg

# ─── Accent Colors — Mode Identity ────────────────────────────────────────────

const ACCENT        := Color(0.133, 0.800, 0.659, 1.00)  # #22cca8 — Pilot mode
const ACCENT_DIM    := Color(0.133, 0.800, 0.659, 0.42)  # Selection rings, bar borders
const ACCENT_FAINT  := Color(0.133, 0.800, 0.659, 0.12)  # Active slot background fill

const TAC_ACCENT       := Color(0.165, 0.722, 0.800, 1.00)  # #2ab8cc — Tactical mode
const TAC_ACCENT_DIM   := Color(0.165, 0.722, 0.800, 0.42)  # Tactical selection rings
const TAC_ACCENT_FAINT := Color(0.165, 0.722, 0.800, 0.12)  # Tactical button background

# ─── Status Colors — Game State ────────────────────────────────────────────────

const HOSTILE       := Color(0.831, 0.298, 0.220, 1.00)  # #d44c38 — Enemy, threats
const HOSTILE_DIM   := Color(0.831, 0.298, 0.220, 0.42)  # Attack vectors, target rings
const HOSTILE_FAINT := Color(0.831, 0.298, 0.220, 0.12)  # Target panel background

const STATUS_HULL     := Color(0.239, 0.722, 0.416, 1.00)  # #3db86a — Hull > 66%
const STATUS_POWER    := Color(0.784, 0.604, 0.157, 1.00)  # #c89a28 — Power bar; hull 33–66%
const STATUS_WARNING  := Color(0.784, 0.471, 0.157, 1.00)  # #c87828 — Heat mid; hull warn
const STATUS_CRITICAL := Color(0.831, 0.220, 0.220, 1.00)  # #d43838 — Heat critical; hull < 20%

# ─── Surfaces ──────────────────────────────────────────────────────────────────

const SURFACE        := Color(0.024, 0.047, 0.086, 0.94)  # All panel backgrounds
const SURFACE_RAISED := Color(0.039, 0.071, 0.125, 0.96)  # Active button/slot backgrounds

# ─── Typography — Font Sizes ───────────────────────────────────────────────────

const SIZE_MODE_NAME   := 20  # Orbitron 700 — mode name ("PILOT", "TACTICAL")
const SIZE_SHIP_NAME   := 16  # Orbitron 700 — ship name in Vessel Status
const SIZE_PANEL_HDR   := 9   # Orbitron 400 — panel section headers
const SIZE_BUTTON_LBL  := 8   # Orbitron 600 — order toolbar button labels
const SIZE_ROSTER_NAME := 9   # Orbitron 600 — fleet roster ship names
const SIZE_DATA_VALUE  := 11  # Share Tech Mono 400 — numeric readouts
const SIZE_DATA_LABEL  := 9   # Orbitron 400 — data field labels
const SIZE_COORD       := 9   # Share Tech Mono 400 — coordinate/speed strings

# ─── Geometry ─────────────────────────────────────────────────────────────────

const CLIP_SIZE       := 14   # Corner-clip polygon size in pixels
const PANEL_PAD_H     := 16   # Standard panel padding — vertical
const PANEL_PAD_W     := 20   # Standard panel padding — horizontal
const COMPACT_PAD_H   := 10   # Compact panel padding — vertical (mode tag, sector)
const COMPACT_PAD_W   := 18   # Compact panel padding — horizontal

# ─── Font Paths ────────────────────────────────────────────────────────────────
# Place Orbitron-Regular.ttf and ShareTechMono-Regular.ttf in assets/fonts/.
# Both are Google Fonts (OFL licensed). Download from fonts.google.com.

const _FONT_LABEL_PATH := "res://assets/fonts/Orbitron-VariableFont_wght.ttf"
const _FONT_DATA_PATH  := "res://assets/fonts/ShareTechMono-Regular.ttf"

var _font_label_cache: Font = null
var _font_data_cache: Font  = null


func get_font_label() -> Font:
	if _font_label_cache != null:
		return _font_label_cache
	if ResourceLoader.exists(_FONT_LABEL_PATH):
		_font_label_cache = load(_FONT_LABEL_PATH) as Font
	return _font_label_cache


func get_font_data() -> Font:
	if _font_data_cache != null:
		return _font_data_cache
	if ResourceLoader.exists(_FONT_DATA_PATH):
		_font_data_cache = load(_FONT_DATA_PATH) as Font
	return _font_data_cache


## Apply label-font override to a Label node. No-op if font not yet imported.
func apply_font_label(label: Label, size: int) -> void:
	var font := get_font_label()
	if font:
		label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)


## Apply label-font with explicit weight (e.g. 700 for bold). Uses FontVariation
## to drive the variable font's wght axis. No-op if font not yet imported.
func apply_font_label_weight(label: Label, size: int, weight: int) -> void:
	var base := get_font_label()
	if base:
		var fv := FontVariation.new()
		fv.base_font = base
		fv.variation_opentype = {"wght": weight}
		label.add_theme_font_override("font", fv)
	label.add_theme_font_size_override("font_size", size)


## Apply data-font override to a Label node. No-op if font not yet imported.
func apply_font_data(label: Label, size: int) -> void:
	var font := get_font_data()
	if font:
		label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
