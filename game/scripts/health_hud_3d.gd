extends CanvasLayer
class_name HealthHUD3D

## 写实科幻宇航员头盔面罩 · 动态结霜层 + 生命 / 氧气 / 体温全息遥测面板（左上角）
const FILLED: Color = Color("#34F0B4")
const MID_AMBER: Color = Color("#FFAE42")
const EMPTY: Color = Color(0.06, 0.16, 0.22, 0.45)
const WARNING: Color = Color("#FF594A")

var controller: Main3D
var panel: PanelContainer
var cells: Array[Panel] = []
var downed_panel: PanelContainer
var _bound: SpacePlayer3D
var _flash: float = 0.0
var _last_health: int = SpacePlayer3D.MAX_HEALTH
var _edge_material: ShaderMaterial
var _frost_material: ShaderMaterial
var _frost_smooth: float = 0.0
var _o2_bar: ProgressBar
var _o2_fill: StyleBoxFlat
var _temp_bar: ProgressBar
var _temp_fill: StyleBoxFlat
var _filled_style: StyleBoxFlat
var _mid_style: StyleBoxFlat
var _low_style: StyleBoxFlat
var _empty_style: StyleBoxFlat

func _ready() -> void:
	controller = get_parent() as Main3D
	layer = 33
	visible = false
	_filled_style = _style(FILLED, Color("#7DFFE0"), 3)
	_mid_style = _style(MID_AMBER, Color("#FFD488"), 3)
	_low_style = _style(WARNING, Color("#FFA498"), 3)
	_empty_style = _style(EMPTY, Color(0.24, 0.62, 0.76, 0.34), 3)

	# 1. 头盔面罩动态结霜层（低温暴风雪时边缘凝结冰晶，喝热可可/进温室自动融化）
	var frost_rect: ColorRect = ColorRect.new()
	frost_rect.name = "VisorFrostOverlay"
	frost_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frost_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frost_material = ShaderMaterial.new()
	_frost_material.shader = preload("res://shaders/visor_frost.gdshader")
	_frost_material.set_shader_parameter("frost_amount", 0.0)
	frost_rect.material = _frost_material
	add_child(frost_rect)

	# 2. 受伤/倒地红色警示面罩边缘
	var edge: ColorRect = ColorRect.new()
	edge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge_material = ShaderMaterial.new()
	_edge_material.shader = preload("res://shaders/health_edge.gdshader")
	edge.material = _edge_material
	add_child(edge)

	# 3. 左上角生命体征 + 氧气/体温双微条全息玻璃面板
	panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", UIStyleKit.visor_box(UIStyleKit.VISOR_TEAL, 3, 12, 8))
	add_child(panel)
	controller._place_hud(panel, Control.PRESET_TOP_LEFT, Vector2(20, 18), Vector2(236, 84))

	var col: VBoxContainer = VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 5)
	panel.add_child(col)

	var hdr: Label = Label.new()
	hdr.text = "VITALS // 生命 · 氧 · 温"
	hdr.add_theme_font_override("font", UIStyleKit.FONT_BOLD)
	hdr.add_theme_font_size_override("font_size", 10)
	hdr.add_theme_color_override("font_color", UIStyleKit.VISOR_CYAN)
	hdr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(hdr)

	var row: HBoxContainer = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 6)
	col.add_child(row)
	for index: int in SpacePlayer3D.MAX_HEALTH:
		var cell: Panel = Panel.new()
		cell.name = "HealthCell%d" % (index + 1)
		cell.custom_minimum_size = Vector2(36, 16)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_theme_stylebox_override("panel", _filled_style)
		row.add_child(cell)
		cells.append(cell)

	# 氧气 O2 + 体温 TEMP 双细条遥测
	var vitals_grid: HBoxContainer = HBoxContainer.new()
	vitals_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vitals_grid.add_theme_constant_override("separation", 8)
	col.add_child(vitals_grid)

	var o2_pair: Array = _make_micro_bar("O2", UIStyleKit.VISOR_CYAN)
	vitals_grid.add_child(o2_pair[0] as Control)
	_o2_bar = o2_pair[1] as ProgressBar
	_o2_fill = o2_pair[2] as StyleBoxFlat

	var temp_pair: Array = _make_micro_bar("TEMP", UIStyleKit.VISOR_AMBER)
	vitals_grid.add_child(temp_pair[0] as Control)
	_temp_bar = temp_pair[1] as ProgressBar
	_temp_fill = temp_pair[2] as StyleBoxFlat

	_build_downed()

func _make_micro_bar(tag: String, col: Color) -> Array:
	var hb: HBoxContainer = HBoxContainer.new()
	hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_theme_constant_override("separation", 4)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lb: Label = Label.new()
	lb.text = tag
	lb.add_theme_font_override("font", UIStyleKit.FONT_BOLD)
	lb.add_theme_font_size_override("font_size", 9)
	lb.add_theme_color_override("font_color", col)
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(lb)
	var bar: ProgressBar = ProgressBar.new()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.custom_minimum_size = Vector2(40, 7)
	bar.show_percentage = false
	bar.max_value = 100.0
	bar.value = 100.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg: StyleBoxFlat = StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.14, 0.20, 0.72)
	bg.set_corner_radius_all(3)
	var fl: StyleBoxFlat = StyleBoxFlat.new()
	fl.bg_color = col
	fl.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fl)
	hb.add_child(bar)
	return [hb, bar, fl]

func _style(fill: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(fill.r, fill.g, fill.b, 0.25)
	style.shadow_size = 4
	return style

func _build_downed() -> void:
	downed_panel = PanelContainer.new()
	downed_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	downed_panel.add_theme_stylebox_override("panel", UIStyleKit.visor_box(WARNING, 3, 14, 12))
	add_child(downed_panel)
	controller._place_hud(downed_panel, Control.PRESET_CENTER, Vector2(-100, -40), Vector2(200, 182))
	var column: VBoxContainer = VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 5)
	downed_panel.add_child(column)
	var kneel: TextureRect = _icon("res://assets/ui/health/downed.svg", Vector2(64, 62))
	kneel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(kneel)
	var title: Label = Label.new()
	title.text = "已倒地"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", UIStyleKit.FONT_BOLD)
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", WARNING)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title)
	var icons: HBoxContainer = HBoxContainer.new()
	icons.alignment = BoxContainer.ALIGNMENT_CENTER
	icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icons.add_theme_constant_override("separation", 12)
	column.add_child(icons)
	icons.add_child(_icon("res://assets/ui/health/no_move.svg", Vector2(48, 48)))
	icons.add_child(_icon("res://assets/ui/health/no_attack.svg", Vector2(48, 48)))
	downed_panel.visible = false

func _icon(path: String, dimensions: Vector2) -> TextureRect:
	var icon: TextureRect = TextureRect.new()
	icon.texture = load(path) as Texture2D
	icon.custom_minimum_size = dimensions
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon

func _process(delta: float) -> void:
	var local: SpacePlayer3D = controller.players.get(multiplayer.get_unique_id()) as SpacePlayer3D
	visible = local != null and (controller.ship_active or controller.game_started) and not controller._settings_visible and not controller.market_visible and not controller.is_journal_visible() and not controller._ship_session.has_panel()
	if local != _bound:
		if is_instance_valid(_bound):
			_bound.health_changed.disconnect(_on_health_changed)
		_bound = local
		if local != null:
			_last_health = local.health
			local.health_changed.connect(_on_health_changed)
			_on_health_changed(local.health)
	_flash = maxf(_flash - delta, 0.0)
	var downed: bool = local != null and local.downed
	downed_panel.visible = downed
	_edge_material.set_shader_parameter("strength", 0.34 if downed else _flash * 1.4)
	if local != null:
		# 实时驱动氧气与体温微条
		var o2: float = clampf(float(local.oxygen), 0.0, 100.0)
		var warmth: float = clampf(float(local.warmth), 0.0, 1.5)
		_o2_bar.value = o2
		_o2_fill.bg_color = WARNING if o2 < 25.0 else UIStyleKit.VISOR_CYAN
		_temp_bar.value = clampf(warmth * 100.0, 0.0, 100.0)
		_temp_fill.bg_color = Color("#58d6ff") if warmth < 0.45 else (UIStyleKit.VISOR_AMBER if warmth < 1.05 else Color("#ffcf6e"))
		# 低温动态结霜：在霜烬星寒冷室外随体温下降自动在面罩四周结出冰晶，进温室/喝热可可后丝滑融化！
		var target_frost: float = 0.0
		if controller.game_started and not controller.ship_active:
			target_frost = clampf((0.88 - warmth) / 0.85, 0.0, 1.0)
		_frost_smooth = lerpf(_frost_smooth, target_frost, clampf(delta * 2.5, 0.0, 1.0))
		_frost_material.set_shader_parameter("frost_amount", _frost_smooth)

func _on_health_changed(current: int) -> void:
	if current < _last_health:
		_flash = 0.3
	_last_health = current
	var active_style: StyleBoxFlat = _filled_style if current >= 3 else (_mid_style if current == 2 else _low_style)
	for index: int in cells.size():
		cells[index].add_theme_stylebox_override("panel", active_style if index < current else _empty_style)
