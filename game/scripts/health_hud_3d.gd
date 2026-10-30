extends CanvasLayer
class_name HealthHUD3D

const FILLED: Color = Color("#69db8c")
const EMPTY: Color = Color("#18343c")
const WARNING: Color = Color("#ff947b")

var controller: Main3D
var panel: PanelContainer
var cells: Array[Panel] = []
var downed_panel: PanelContainer
var _bound: SpacePlayer3D
var _flash: float = 0.0
var _last_health: int = SpacePlayer3D.MAX_HEALTH
var _edge_material: ShaderMaterial
var _filled_style: StyleBoxFlat
var _empty_style: StyleBoxFlat

func _ready() -> void:
    controller = get_parent() as Main3D
    layer = 33
    visible = false
    _filled_style = _style(FILLED, Color("#a3f2b5"), 6)
    _empty_style = _style(EMPTY, Color("#43636c"), 6)
    var edge: ColorRect = ColorRect.new()
    edge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _edge_material = ShaderMaterial.new()
    _edge_material.shader = preload("res://shaders/health_edge.gdshader")
    edge.material = _edge_material
    add_child(edge)
    panel = PanelContainer.new()
    panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    panel.add_theme_stylebox_override("panel", _style(Color(0.06, 0.15, 0.18, 0.94), Color("#a2d8d3"), 15))
    add_child(panel)
    controller._place_hud(panel, Control.PRESET_TOP_LEFT, Vector2(22, 18), Vector2(238, 48))
    var margin: MarginContainer = MarginContainer.new()
    margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
    for side: String in ["left", "right"]:
        margin.add_theme_constant_override("margin_" + side, 12)
    for side: String in ["top", "bottom"]:
        margin.add_theme_constant_override("margin_" + side, 10)
    panel.add_child(margin)
    var row: HBoxContainer = HBoxContainer.new()
    row.mouse_filter = Control.MOUSE_FILTER_IGNORE
    row.add_theme_constant_override("separation", 6)
    margin.add_child(row)
    for index: int in SpacePlayer3D.MAX_HEALTH:
        var cell: Panel = Panel.new()
        cell.name = "HealthCell%d" % (index + 1)
        cell.custom_minimum_size = Vector2(36, 28)
        cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
        cell.add_theme_stylebox_override("panel", _filled_style)
        row.add_child(cell)
        cells.append(cell)
    _build_downed()

func _style(fill: Color, border: Color, radius: int) -> StyleBoxFlat:
    var style: StyleBoxFlat = StyleBoxFlat.new()
    style.bg_color = fill
    style.border_color = border
    style.set_border_width_all(1)
    style.set_corner_radius_all(radius)
    style.shadow_color = Color(0, 0, 0, 0.3)
    style.shadow_size = 5
    return style

func _build_downed() -> void:
    downed_panel = PanelContainer.new()
    downed_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    downed_panel.add_theme_stylebox_override("panel", _style(Color(0.07, 0.12, 0.15, 0.9), WARNING, 15))
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

func _on_health_changed(current: int) -> void:
    if current < _last_health:
        _flash = 0.3
    _last_health = current
    for index: int in cells.size():
        cells[index].add_theme_stylebox_override("panel", _filled_style if index < current else _empty_style)
