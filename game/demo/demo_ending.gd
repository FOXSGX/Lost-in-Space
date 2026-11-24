extends Node

## Demo-only ending screen.
##
## This scene is reached only from the Act05 gate through SessionHub's verified
## chapter hand-off. It mirrors the ledger and never writes completion state.

var _summary: Dictionary = {}
var _verified: bool = false


func _ready() -> void:
	InputSetup.ensure_actions()
	_summary = SessionHub.chapter_history.duplicate(true)
	_verified = _chapter_completed("act23") and _chapter_completed("act04") and _chapter_completed("act05")
	_build_ui()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _chapter_completed(chapter: String) -> bool:
	var value: Variant = _summary.get(chapter, {})
	return value is Dictionary and bool((value as Dictionary).get("completed", false))


func _build_ui() -> void:
	var canvas: CanvasLayer = CanvasLayer.new()
	canvas.name = "DemoEndingCanvas"
	add_child(canvas)

	var background: ColorRect = ColorRect.new()
	background.color = Color("09131c")
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(background)

	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 140)
	margin.add_theme_constant_override("margin_right", 140)
	margin.add_theme_constant_override("margin_top", 75)
	margin.add_theme_constant_override("margin_bottom", 65)
	canvas.add_child(margin)

	var content: VBoxContainer = VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 14)
	margin.add_child(content)

	var eyebrow: Label = Label.new()
	eyebrow.text = "RESONANCE STAR · DEMO END"
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eyebrow.add_theme_font_size_override("font_size", 14)
	eyebrow.add_theme_color_override("font_color", Color("7de8e0"))
	content.add_child(eyebrow)

	var title: Label = Label.new()
	title.text = "演示完成" if _verified else "演示状态未确认"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color("f3f7f4"))
	content.add_child(title)

	var subtitle: Label = Label.new()
	subtitle.text = "Act23 安全刹车与救援  →  Act04《会记忆的晶体》  →  Act05 真实章节交接"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_size_override("font_size", 17)
	subtitle.add_theme_color_override("font_color", Color("c7d8d8"))
	content.add_child(subtitle)

	content.add_child(_spacer(10))

	var chapters: Label = Label.new()
	chapters.text = _chapter_lines()
	chapters.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chapters.add_theme_font_size_override("font_size", 18)
	content.add_child(chapters)

	var notice: Label = Label.new()
	notice.text = "本次 Resonance Star Demo 已结束。它只展示当前纵切片范围，不代表完整五幕游戏已经完成。"
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.add_theme_font_size_override("font_size", 15)
	notice.add_theme_color_override("font_color", Color("ffc979"))
	content.add_child(notice)

	content.add_child(_spacer(12))

	var menu_button: Button = _make_button("返回演示入口")
	menu_button.pressed.connect(_go_menu)
	content.add_child(menu_button)

	var quit_button: Button = _make_button("退出 Demo")
	quit_button.pressed.connect(_quit_demo)
	content.add_child(quit_button)


func _chapter_lines() -> String:
	var rows: Array[String] = []
	var labels: Dictionary = {
		"act23": "Act23 · 安全刹车与救援",
		"act04": "Act04 · 会记忆的晶体",
		"act05": "Act05 · 章节交接",
	}
	for chapter: String in ["act23", "act04", "act05"]:
		var mark: String = "●" if _chapter_completed(chapter) else "○"
		rows.append("%s  %s" % [mark, labels[chapter]])
	return "\n".join(rows)


func _make_button(text: String) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(360.0, 50.0)
	button.add_theme_font_size_override("font_size", 18)
	return button


func _spacer(height: int) -> Control:
	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(0.0, float(height))
	return spacer


func _go_menu() -> void:
	_close_session()
	get_tree().change_scene_to_file("res://demo/demo_launcher.tscn")


func _quit_demo() -> void:
	_close_session()
	get_tree().quit()


func _close_session() -> void:
	if SessionHub != null and SessionHub.net != null:
		SessionHub.net.shutdown()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit_demo()
