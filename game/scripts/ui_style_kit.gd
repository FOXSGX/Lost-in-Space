extends RefCounted
class_name UIStyleKit

## 《迷失太空》写实科幻宇航员头盔面罩全息投影统一 UI 主题
## - 透明磨砂深空玻璃底板 + 极细冰青全息发光描边 + 工业琥珀橙高优先级警告色
## - 字体：HarmonyOS Sans SC Regular / Bold（现代利落无衬线，在暗舱与亮雪地均清晰锐利）

const FONT_REG: FontFile = preload("res://assets/fonts/HarmonyOS_Sans_SC_Regular.ttf")
const FONT_BOLD: FontFile = preload("res://assets/fonts/HarmonyOS_Sans_SC_Bold.ttf")

# 写实科幻头盔面罩核心色板
const VISOR_GLASS: Color = Color(0.035, 0.085, 0.135, 0.64)
const VISOR_GLASS_DEEP: Color = Color(0.025, 0.062, 0.105, 0.84)
const VISOR_GLASS_LITE: Color = Color(0.060, 0.145, 0.215, 0.56)
const VISOR_BORDER: Color = Color(0.28, 0.84, 0.96, 0.52)
const VISOR_BORDER_BRIGHT: Color = Color(0.36, 0.94, 1.00, 0.92)
const VISOR_BORDER_DIM: Color = Color(0.24, 0.62, 0.76, 0.34)
const VISOR_CYAN: Color = Color("#4CE8FF")
const VISOR_TEAL: Color = Color("#34E0B8")
const VISOR_AMBER: Color = Color("#FFAE42")
const VISOR_CORAL: Color = Color("#FF5E48")
const VISOR_TEXT: Color = Color("#E8F7FF")
const VISOR_MUTED: Color = Color("#8CB4CA")

# 兼容已有引用的语义色常量（全部平滑升级为写实科幻航空深空玻璃配色）
const CREAM_BG: Color = Color(0.045, 0.095, 0.148, 0.92)
const CREAM_PANEL_HUD: Color = VISOR_GLASS
const IVORY_INPUT: Color = Color(0.065, 0.135, 0.200, 0.92)
const SAND_BTN: Color = Color(0.095, 0.185, 0.265, 0.88)
const SAND_HOVER: Color = Color(0.145, 0.275, 0.380, 0.95)
const ORANGE_PRIMARY: Color = Color("#E68D36")
const ORANGE_HOVER: Color = Color("#F5A24C")
const TEAL_ACTION: Color = Color("#1F9DA8")
const TEAL_HOVER: Color = Color("#2BBAC6")
const NAVY_INK: Color = VISOR_TEXT
const MUTED_INK: Color = VISOR_MUTED
const BORDER_SOFT: Color = VISOR_BORDER
const HEALTH_GREEN: Color = Color("#34F0B4")
const HEALTH_EMPTY: Color = Color(0.08, 0.18, 0.25, 0.52)
const WARN_RED: Color = Color("#FF594A")

static func box(fill: Color, border: Color = VISOR_BORDER, radius: int = 8, border_w: int = 1, pad_x: int = 14, pad_y: int = 8, shadow: int = 6) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad_x
	sb.content_margin_right = pad_x
	sb.content_margin_top = pad_y
	sb.content_margin_bottom = pad_y
	if shadow > 0:
		sb.shadow_color = Color(0.01, 0.05, 0.09, 0.38)
		sb.shadow_size = shadow
		sb.shadow_offset = Vector2(0, 2)
	return sb

static func visor_box(accent: Color = VISOR_CYAN, left_bar: int = 3, pad_x: int = 14, pad_y: int = 10) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = VISOR_GLASS
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.56)
	sb.border_width_left = left_bar
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_right = 8
	sb.corner_radius_bottom_left = 4
	sb.content_margin_left = pad_x
	sb.content_margin_right = pad_x
	sb.content_margin_top = pad_y
	sb.content_margin_bottom = pad_y
	sb.shadow_color = Color(0.0, 0.04, 0.08, 0.32)
	sb.shadow_size = 5
	sb.shadow_offset = Vector2(0, 2)
	return sb

static func visor_slot(selected: bool = false, is_equip: bool = false) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	if is_equip:
		sb.bg_color = Color(0.14, 0.16, 0.14, 0.72) if selected else Color(0.05, 0.10, 0.15, 0.58)
		sb.border_color = VISOR_AMBER if selected else Color(0.95, 0.68, 0.30, 0.52)
	else:
		sb.bg_color = Color(0.08, 0.24, 0.34, 0.74) if selected else VISOR_GLASS
		sb.border_color = VISOR_BORDER_BRIGHT if selected else VISOR_BORDER_DIM
	sb.set_border_width_all(2 if selected else 1)
	sb.set_corner_radius_all(6)
	sb.shadow_color = Color(0.0, 0.18, 0.26, 0.28 if selected else 0.10)
	sb.shadow_size = 6 if selected else 2
	return sb

static func style_button(btn: Button, variant: String = "sand", radius: int = 8) -> void:
	var fill: Color = SAND_BTN
	var hover: Color = SAND_HOVER
	var ink: Color = VISOR_TEXT
	var border_col: Color = VISOR_BORDER_DIM
	if variant == "orange":
		fill = ORANGE_PRIMARY
		hover = ORANGE_HOVER
		ink = Color("#08111A")
		border_col = Color("#FFD08A")
	elif variant == "teal":
		fill = TEAL_ACTION
		hover = TEAL_HOVER
		ink = Color.WHITE
		border_col = VISOR_CYAN
	elif variant == "close":
		fill = Color(0, 0, 0, 0)
		hover = SAND_HOVER
		ink = VISOR_TEXT
		border_col = Color(0, 0, 0, 0)

	btn.add_theme_font_override("font", FONT_BOLD)
	btn.add_theme_stylebox_override("normal", box(fill, border_col, radius, 1 if variant != "close" else 0, 18, 10, 3 if variant != "close" else 0))
	btn.add_theme_stylebox_override("hover", box(hover, VISOR_BORDER_BRIGHT, radius, 2 if variant != "close" else 0, 18, 10, 5 if variant != "close" else 0))
	btn.add_theme_stylebox_override("pressed", box(fill.darkened(0.12), VISOR_CYAN, radius, 2, 18, 10, 0))
	btn.add_theme_stylebox_override("focus", box(hover, VISOR_BORDER_BRIGHT, radius, 2, 18, 10, 4))
	btn.add_theme_stylebox_override("disabled", box(Color(0.05, 0.09, 0.13, 0.55), VISOR_BORDER_DIM, radius, 1, 18, 10, 0))
	btn.add_theme_color_override("font_color", ink)
	btn.add_theme_color_override("font_hover_color", ink)
	btn.add_theme_color_override("font_pressed_color", ink)
	btn.add_theme_color_override("font_focus_color", ink)
	btn.add_theme_color_override("font_disabled_color", Color("#5B7385"))

static func build_app_theme() -> Theme:
	var t: Theme = Theme.new()
	t.default_font = FONT_REG
	t.default_font_size = 16
	t.set_color("font_color", "Label", VISOR_TEXT)
	t.set_color("default_color", "RichTextLabel", VISOR_MUTED)
	t.set_stylebox("panel", "PanelContainer", box(VISOR_GLASS_DEEP, VISOR_BORDER, 10, 1, 20, 16, 10))
	t.set_stylebox("panel", "Panel", box(VISOR_GLASS_DEEP, VISOR_BORDER, 10, 1, 16, 12, 8))
	t.set_font("font", "Button", FONT_BOLD)
	t.set_stylebox("normal", "Button", box(SAND_BTN, VISOR_BORDER_DIM, 8, 1, 16, 10, 2))
	t.set_stylebox("hover", "Button", box(TEAL_ACTION, VISOR_BORDER_BRIGHT, 8, 2, 16, 10, 4))
	t.set_stylebox("pressed", "Button", box(TEAL_ACTION.darkened(0.12), VISOR_CYAN, 8, 2, 16, 10, 0))
	t.set_stylebox("focus", "Button", box(TEAL_ACTION, VISOR_BORDER_BRIGHT, 8, 2, 16, 10, 4))
	t.set_stylebox("disabled", "Button", box(Color(0.05, 0.09, 0.13, 0.55), VISOR_BORDER_DIM, 8, 1, 16, 10, 0))
	t.set_color("font_color", "Button", VISOR_TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color("#5B7385"))
	t.set_stylebox("normal", "LineEdit", box(IVORY_INPUT, VISOR_BORDER_DIM, 8, 1, 14, 10, 0))
	t.set_stylebox("focus", "LineEdit", box(IVORY_INPUT, VISOR_CYAN, 8, 2, 14, 10, 0))
	t.set_color("font_color", "LineEdit", VISOR_TEXT)
	t.set_color("font_placeholder_color", "LineEdit", VISOR_MUTED)
	t.set_stylebox("background", "ProgressBar", box(Color(0.04, 0.10, 0.15, 0.8), VISOR_BORDER_DIM, 4, 1, 0, 0, 0))
	t.set_stylebox("fill", "ProgressBar", box(VISOR_CYAN, VISOR_CYAN, 4, 0, 0, 0, 0))
	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("separation", "HBoxContainer", 12)
	return t
