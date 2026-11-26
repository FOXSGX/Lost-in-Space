extends CanvasLayer

var stage: Node3D
var device: Node3D
var actor: CharacterBody3D
var font: Font
var task: Label
var prompt: Label
var feedback: Label
var debug: Label
var panel: PanelContainer
var help: Label
var debug_visible: bool = false
var help_visible: bool = false
var _timer: float = 0.0
var _age: float = 0.0

func configure(owner_stage: Node3D, stage_device: Node3D, player: CharacterBody3D, ui_font: Font) -> void:
    stage = owner_stage
    device = stage_device
    actor = player
    font = ui_font

func _ready() -> void:
    var root: Control = Control.new()
    root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.theme = (load("res://scripts/playtest_theme.gd") as Script).create_theme(font) as Theme
    add_child(root)
    var top: MarginContainer = MarginContainer.new()
    top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
    for edge: String in ["left", "right", "top"]:
        top.add_theme_constant_override("margin_" + edge, 24)
    top.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(top)
    var tasks: VBoxContainer = VBoxContainer.new()
    tasks.mouse_filter = Control.MOUSE_FILTER_IGNORE
    top.add_child(tasks)
    task = _label(tasks, 20)
    help = _label(tasks, 17)
    help.modulate = Color("#acd6dc")
    debug = _label(tasks, 16)
    debug.visible = false
    var bottom: MarginContainer = MarginContainer.new()
    bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
    bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
    bottom.add_theme_constant_override("margin_bottom", 20)
    bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(bottom)
    var center: CenterContainer = CenterContainer.new()
    center.mouse_filter = Control.MOUSE_FILTER_IGNORE
    bottom.add_child(center)
    var stack: VBoxContainer = VBoxContainer.new()
    stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
    center.add_child(stack)
    var meter: Control = (load("res://scripts/calibration_meter.gd") as Script).new() as Control
    meter.custom_minimum_size = Vector2(400, 180)
    meter.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    meter.call("configure", device, actor, font)
    stack.add_child(meter)
    panel = PanelContainer.new()
    panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    panel.custom_minimum_size.x = 600
    stack.add_child(panel)
    var lines: VBoxContainer = VBoxContainer.new()
    lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
    panel.add_child(lines)
    prompt = _label(lines, 19)
    feedback = _label(lines, 16)
    feedback.modulate = Color("#acd6dc")

func _label(parent: Node, points: int) -> Label:
    var node: Label = Label.new()
    node.mouse_filter = Control.MOUSE_FILTER_IGNORE
    node.add_theme_font_size_override("font_size", points)
    node.add_theme_color_override("font_shadow_color", Color.BLACK)
    node.add_theme_constant_override("shadow_offset_x", 1)
    node.add_theme_constant_override("shadow_offset_y", 1)
    parent.add_child(node)
    return node

func toggle_help() -> void:
    help_visible = not help_visible

func _process(delta: float) -> void:
    if not visible: return
    _age += delta
    _timer += delta
    if _timer < 0.1: return
    _timer = 0.0
    task.text = str(device.call("objective")) + "    ·    Esc 菜单 / F1 提示"
    help.visible = help_visible or _age < 12.0
    if help.visible:
        if str(device.get("phase")) in ["locked", "calibrating", "failed"]:
            help.text = "寻找 A 频率与 B 预载；观察刻度与队友的变化。\n" + ("单人：先在 B 调入稳定带，E 锁存后去 A。" if (stage.get("actors") as Dictionary).size() == 1 else "两名船员分别接入不同控制端，交流读数。")
        else:
            help.text = "WASD 移动 · Shift 跑 · 鼠标视角\n沿黄色踏步登车：F 拾取 · X 放下 · G 安装 · E 操作"
    var text: String = str(device.call("prompt", int(actor.get("peer_id"))))
    var transient: String = str(device.get("feedback")) if float(device.get("feedback_until")) > float(device.get("clock")) else ""
    panel.visible = text != "" or transient != ""
    prompt.text = text
    prompt.visible = text != ""
    feedback.text = transient
    feedback.visible = transient != ""
    debug.visible = debug_visible
    if debug_visible:
        debug.text = "DEBUG · F9 隐藏\nphase %s / revision %s / carrier %s\nrole %s / actors %s\n%s\nF6 主机复位 · C 停机 · M 静音" % [device.get("phase"), device.get("revision"), device.get("carrier_id"), actor.get("operating_role"), (device.get("actors") as Dictionary).size(), stage.get("session_status")]
