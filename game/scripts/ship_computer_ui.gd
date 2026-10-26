extends Control
class_name ShipComputerUI

const ICON_DIR: String = "res://assets/ship-hub/computer-icons/"
const SKIN_PREVIEW_DIR: String = "res://assets/characters/skins/previews/"
const INK: Color = Color("#dcece5")
const MUTED: Color = Color("#8da9ae")
const ACCENT: Color = Color("#92e3c6")
var session: ShipSession3D
var computer: Dictionary = {}
var selection: Dictionary = {}
var _options: Array = []
var _cards: Dictionary = {}
var _hero: TextureRect
var _hero_title: Label
var _detail: Label
var _wallet: Label
var _action: Button
var _feedback: Label
var _meter: ProgressBar
var _meter_label: Label
var _notes: RichTextLabel
var _status: Label
var _exit_confirm_until: int = 0

static func icon(option: Dictionary) -> Texture2D:
    var kind: String = String(option.get("kind", ""))
    var item: String = String(option.get("item", ""))
    if kind == "skin" and not item.is_empty():
        return load(SKIN_PREVIEW_DIR + "skin_%s.png" % item) as Texture2D
    var key: String = item if not item.is_empty() and kind in ["route", "gear", "craft", "toy"] else kind
    if CrewItems3D.ICONS.has(key):
        return CrewItems3D.ICONS[key] as Texture2D
    return load(ICON_DIR + key + ".svg") as Texture2D

func setup(owner_session: ShipSession3D) -> void:
    session = owner_session
    name = "ShipComputerUI"
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    visible = false
    theme = _theme()

func _style(fill: Color, border: Color) -> StyleBoxFlat:
    var box: StyleBoxFlat = StyleBoxFlat.new()
    box.bg_color = fill
    box.border_color = border
    box.set_border_width_all(1)
    box.set_corner_radius_all(16)
    box.content_margin_left = 24
    box.content_margin_right = 24
    box.content_margin_top = 20
    box.content_margin_bottom = 20
    return box

func _theme() -> Theme:
    var result: Theme = Theme.new()
    result.default_font_size = 18
    result.set_color("font_color", "Label", INK)
    result.set_color("default_color", "RichTextLabel", MUTED)
    result.set_stylebox("panel", "PanelContainer", _style(Color("#142c38"), Color("#3f626b")))
    for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
        var fill: Color = Color("#213e4b")
        var border: Color = Color("#41616b")
        if state in ["hover", "focus", "pressed"]:
            fill = Color("#2d555b")
            border = ACCENT
        if state == "disabled":
            fill = Color("#19313c")
            border = Color("#2b4853")
        result.set_stylebox(state, "Button", _style(fill, border))
        result.set_color("font_" + ("color" if state == "normal" else state + "_color"), "Button", MUTED if state == "disabled" else INK)
    result.set_stylebox("background", "ProgressBar", _style(Color("#0c202c"), Color("#34535e")))
    var bar: StyleBoxFlat = _style(ACCENT, ACCENT)
    bar.content_margin_top = 0
    bar.content_margin_bottom = 0
    result.set_stylebox("fill", "ProgressBar", bar)
    result.set_constant("separation", "VBoxContainer", 12)
    result.set_constant("separation", "HBoxContainer", 16)
    result.set_constant("h_separation", "GridContainer", 12)
    result.set_constant("v_separation", "GridContainer", 12)
    return result

func _label(parent: Node, text: String, font_size: int = 18, color: Color = INK) -> Label:
    var label: Label = Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    parent.add_child(label)
    return label

func _picture(parent: Node, texture: Texture2D, dimensions: Vector2) -> TextureRect:
    var picture: TextureRect = TextureRect.new()
    picture.texture = texture
    picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    picture.custom_minimum_size = dimensions
    picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
    parent.add_child(picture)
    return picture

func open(device: Dictionary) -> void:
    computer = device.duplicate()
    selection = {}
    _exit_confirm_until = 0
    _cards.clear()
    for child: Node in get_children():
        remove_child(child)
        child.queue_free()
    _options = ShipDevices3D.options_for(computer)
    if computer.kind == "store":
        _options = []
        for index: int in CrewItems3D.CAPACITY:
            _options.append({"id": "store_%d" % index, "kind": "store", "item": str(index), "title": "物品 %d" % (index + 1)})
    var dim: ColorRect = ColorRect.new()
    dim.color = Color(0.025, 0.065, 0.10, 0.88)
    add_child(dim)
    dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    var center: CenterContainer = CenterContainer.new()
    add_child(center)
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    center.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var shell: PanelContainer = PanelContainer.new()
    shell.name = "ComputerWindow"
    shell.custom_minimum_size = Vector2(1040, 568)
    center.add_child(shell)
    var column: VBoxContainer = VBoxContainer.new()
    column.add_theme_constant_override("separation", 20)
    shell.add_child(column)
    var heading: HBoxContainer = HBoxContainer.new()
    column.add_child(heading)
    _picture(heading, icon({"kind": computer.kind}), Vector2(40, 40))
    _label(heading, String(computer.title), 27).size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var money: String = "coin" if computer.kind == "skin" else "credits"
    _picture(heading, load(ICON_DIR + money + ".svg") as Texture2D, Vector2(28, 28))
    _wallet = _label(heading, "0", 21, Color("#f4cd83"))
    var close: Button = Button.new()
    close.name = "CloseComputer"
    close.text = "×"
    close.custom_minimum_size = Vector2(52, 48)
    close.pressed.connect(session.close_panel)
    heading.add_child(close)
    var body: HBoxContainer = HBoxContainer.new()
    body.size_flags_vertical = Control.SIZE_EXPAND_FILL
    body.add_theme_constant_override("separation", 24)
    column.add_child(body)
    var hero_panel: PanelContainer = PanelContainer.new()
    hero_panel.custom_minimum_size = Vector2(312, 0)
    hero_panel.add_theme_stylebox_override("panel", _style(Color("#0d2431"), Color("#34545f")))
    body.add_child(hero_panel)
    var hero_column: VBoxContainer = VBoxContainer.new()
    hero_panel.add_child(hero_column)
    _hero = _picture(hero_column, null, Vector2(248, 224))
    _hero.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _hero_title = _label(hero_column, "", 24)
    _hero_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _detail = _label(hero_column, "", 15, MUTED)
    _detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    var choices: VBoxContainer = VBoxContainer.new()
    choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    body.add_child(choices)
    var status_row: HBoxContainer = HBoxContainer.new()
    choices.add_child(status_row)
    _status = _label(status_row, "●  在线", 15, ACCENT)
    _status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _label(status_row, "%02d 项" % _options.size(), 15, MUTED)
    var grid: GridContainer = GridContainer.new()
    grid.columns = 3 if _options.size() >= 3 else _options.size()
    choices.add_child(grid)
    for option: Dictionary in _options:
        var button: Button = Button.new()
        button.name = "Option_" + String(option.id)
        button.custom_minimum_size = Vector2(194 if grid.columns < 3 else 178, 152)
        button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        button.toggle_mode = true
        grid.add_child(button)
        var stack: VBoxContainer = VBoxContainer.new()
        button.add_child(stack)
        stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        stack.offset_left = 12
        stack.offset_top = 10
        stack.offset_right = -12
        stack.offset_bottom = -10
        stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
        var picture: TextureRect = _picture(stack, icon(option) if option.kind != "store" else icon({"kind": "store"}), Vector2(72, 72))
        var title: Label = _label(stack, String(option.title), 16)
        title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        var caption: Label = _label(stack, "", 14, MUTED)
        caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        _cards[option.id] = {"button": button, "picture": picture, "title": title, "caption": caption}
        button.pressed.connect(_select.bind(option))
    _meter_label = _label(choices, "", 17, MUTED)
    _meter = ProgressBar.new()
    _meter.custom_minimum_size = Vector2(0, 12)
    _meter.show_percentage = false
    choices.add_child(_meter)
    _notes = RichTextLabel.new()
    _notes.custom_minimum_size = Vector2(0, 92)
    _notes.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _notes.scroll_active = true
    _notes.add_theme_font_size_override("normal_font_size", 16)
    choices.add_child(_notes)
    var footer: HBoxContainer = HBoxContainer.new()
    column.add_child(footer)
    var feedback_column: VBoxContainer = VBoxContainer.new()
    feedback_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    footer.add_child(feedback_column)
    _feedback = _label(feedback_column, "", 17, ACCENT)
    _feedback.custom_minimum_size.x = 500
    _feedback.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    _label(feedback_column, "Esc 关闭     ·     鼠标选择 / 方向键 + Enter", 13, MUTED)
    _action = Button.new()
    _action.name = "ConfirmComputerAction"
    _action.custom_minimum_size = Vector2(248, 56)
    _action.add_theme_stylebox_override("normal", _style(Color("#376559"), ACCENT))
    _action.pressed.connect(_confirm)
    footer.add_child(_action)
    visible = true
    _select(_options[0])
    (_cards[_options[0].id].button as Button).grab_focus()

func _slot(option: Dictionary) -> Dictionary:
    return session.controller._items.ensure_bag(multiplayer.get_unique_id()).slots[int(option.item)]

func _texture(option: Dictionary) -> Texture2D:
    if option.kind == "store":
        var held: Dictionary = _slot(option)
        return icon({"kind": "toy", "item": held.kind}) if not held.is_empty() else icon({"kind": "store"})
    return icon(option)

func _select(option: Dictionary) -> void:
    selection = option.duplicate()
    _hero.texture = _texture(selection)
    for id: String in _cards:
        (_cards[id].button as Button).button_pressed = id == selection.id
    refresh()

func _confirm() -> void:
    if computer.kind == "mission":
        session.close_panel()
        return
    if not selection.is_empty() and not _action.disabled:
        if computer.kind == "exit" and Time.get_ticks_msec() >= _exit_confirm_until:
            _exit_confirm_until = Time.get_ticks_msec() + 3000
        session.request("computer_action", String(selection.id))
        refresh()

func refresh() -> void:
    if not visible or selection.is_empty():
        return
    var peer: int = multiplayer.get_unique_id()
    var main: Main3D = session.controller
    var player: SpacePlayer3D = main.players.get(peer) as SpacePlayer3D
    _wallet.text = str(main.credits if computer.kind == "skin" else session.credits)
    _feedback.text = session.notice_text().get_slice("。", 0).get_slice("；", 0)
    _notes.visible = computer.kind == "mission"
    _notes.text = session.last_report if _notes.visible else ""
    _hero_title.text = String(selection.title)
    _detail.text = ""
    _action.disabled = false
    _meter.visible = computer.kind in ["repair", "refill"]
    _meter_label.visible = _meter.visible
    _status.text = "●  在线"
    for option: Dictionary in _options:
        var card: Dictionary = _cards[option.id]
        var caption: String = ""
        match String(option.kind):
            "route": caption = "✓ 已选" if session.selected_destination == option.item else "航线"
            "craft": caption = "◆ %d   /   × %d" % [int(ShipSession3D.ITEM_COSTS[option.item]), int(session.stock[option.item])]
            "gear": caption = "✓ 已拥有" if int(session.gear_stock[option.item]) > 0 else "◆ %d" % int(ShipSession3D.GEAR_COSTS[option.item])
            "skin": caption = "✓ 已拥有" if main.owns_skin(option.item) else "★ %d" % main.skin_price(option.item)
            "toy": caption = "× %d / 2" % main._items.occupied(peer)
            "store":
                var held: Dictionary = _slot(option)
                (card.picture as TextureRect).texture = _texture(option)
                (card.title as Label).text = main._items.item_name(String(held.get("kind", "")))
                var kind: String = String(held.get("kind", ""))
                caption = "空" if held.is_empty() else ("可归还" if kind in ["medical", "oxygen"] or ShipSession3D.GOOFY_ITEMS.has(kind) else "任务货物")
        (card.caption as Label).text = caption
    _hero.texture = _texture(selection)
    match String(computer.kind):
        "route":
            _action.text = "✓ 已选航线" if session.selected_destination == selection.item else "设为航线 →"
            _action.disabled = session.selected_destination == selection.item
            _detail.text = "4 个驾驶席 · 全员就位后出发"
        "craft":
            var cost: int = int(ShipSession3D.ITEM_COSTS[selection.item])
            _action.text = "制作   ◆ %d" % cost
            _action.disabled = session.credits < cost
            _detail.text = "共享库存  × %d" % int(session.stock[selection.item])
        "gear":
            var owned: bool = int(session.gear_stock[selection.item]) > 0
            var equipped: bool = session.has_gear(peer, selection.item) and main._items.available_gear(selection.item) <= 0 and main._items.selected(peer).get("kind", "") != selection.item
            _action.text = "✓ 已装备" if equipped else ("装备 →" if owned else "购买并装备   ◆ %d" % int(ShipSession3D.GEAR_COSTS[selection.item]))
            _action.disabled = equipped or (not owned and session.credits < int(ShipSession3D.GEAR_COSTS[selection.item]))
            _detail.text = String({"thermal_suit": "保温", "wide_scanner": "扫描范围", "signal_stabilizer": "信号稳定"}.get(selection.item, ""))
            if not equipped and not main._items.can_equip(peer, selection.item):
                _action.disabled = true
                _action.text = "装备栏已满"
            elif owned and not equipped and main._items.available_gear(selection.item) <= 0 and main._items.selected(peer).get("kind", "") != selection.item:
                _action.disabled = true
                _action.text = "装备使用中"
        "skin":
            var owned: bool = main.owns_skin(selection.item)
            var equipped: bool = main.player_skins.get(peer, "ranger") == selection.item
            _action.text = "✓ 穿戴中" if equipped else ("换装 →" if owned else "购买并换装   ★ %d" % main.skin_price(selection.item))
            _action.disabled = equipped or (not owned and main.credits < main.skin_price(selection.item))
        "toy":
            _action.text = "领取 →"
            _action.disabled = main._items.occupied(peer) >= CrewItems3D.CAPACITY
            _detail.text = "重复使用 · 无冷却"
        "repair":
            _meter.value = session.hull
            _meter_label.text = "舰体 %d%%     零件 × %d" % [session.hull, int(session.stock.parts)]
            _action.text = "维修   − 1 零件"
            _action.disabled = session.hull >= 100 or int(session.stock.parts) <= 0
            _detail.text = "+20% 舰体"
        "refill":
            _action.text = "恢复 →"
            _detail.text = "生命 · 氧气 · 体温"
            _meter.value = player.oxygen if player != null else 0
            _meter_label.text = "氧气 %d%%     生命 %d / 5" % [int(player.oxygen) if player != null else 0, player.health if player != null else 0]
        "store":
            var held: Dictionary = _slot(selection)
            _hero_title.text = main._items.item_name(String(held.get("kind", "")))
            _action.text = "存回 →"
            _action.disabled = not (held.get("kind", "") in ["medical", "oxygen"] or ShipSession3D.GOOFY_ITEMS.has(held.get("kind", "")))
            _detail.text = "选择携带格"
        "mission":
            _action.text = "关闭记录"
            _detail.text = "舰体 %d%%   ·   ◆ %d" % [session.hull, session.credits]
        "exit":
            _action.text = "确认离开" if Time.get_ticks_msec() < _exit_confirm_until else "离开房间 →"
            _detail.text = "再次确认后离舰"
    if _action.disabled and computer.kind in ["gear", "skin", "craft"] and not _action.text.begins_with("✓") and _action.text not in ["装备栏已满", "装备使用中"]:
        _status.text = "○  余额不足"
