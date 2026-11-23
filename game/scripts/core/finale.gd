# finale.gd — 五幕冒险完成结算屏
#
# 显示整合后的五幕总参与报告与冒险完成文案，并提供「返回主菜单」/「退出」。
# 在 Act05 完成事件通过 SessionHub.complete_chapter 切入本场景。
extends Node

var _summary: Dictionary = {}

func _ready() -> void:
	InputSetup.ensure_actions()
	_summary = SessionHub.chapter_history.duplicate(true)
	# The settlement screen must not declare itself finished on its own: it
	# mirrors the Act-5 record the chapter actually handed over. A direct launch
	# with no Act-5 completion therefore renders honestly as incomplete.
	var act5: Variant = _summary.get("act05", {})
	var act5_done: bool = act5 is Dictionary and bool((act5 as Dictionary).get("completed", false))
	SessionHub.record_chapter_done("finale", {"completed": act5_done, "from_chapter": "act05"})
	_build_ui()

func _build_ui() -> void:
	var canvas: CanvasLayer = CanvasLayer.new()
	canvas.name = "UICanvas"
	add_child(canvas)
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.02, 0.035, 0.045, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(bg)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 120)
	margin.add_theme_constant_override("margin_right", 120)
	margin.add_theme_constant_override("margin_top", 60)
	margin.add_theme_constant_override("margin_bottom", 60)
	canvas.add_child(margin)
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	var title: Label = Label.new()
	title.text = "=== 冒险完成 ==="
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	vbox.add_child(title)

	var sub: Label = Label.new()
	sub.text = "你们从沉默的矿区出发，穿越被切断的轨道与记忆的晶体，\n禁锢了地心核心的共振，带着最后的星图信号回到了地表。"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 17)
	sub.add_theme_color_override("font_color", Color(0.75, 0.85, 0.9))
	vbox.add_child(sub)

	vbox.add_child(_spacer(10))

	var chapters: Label = Label.new()
	chapters.text = _chapter_lines()
	chapters.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chapters.add_theme_font_size_override("font_size", 16)
	chapters.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(chapters)

	var detail_text: String = _act05_detail()
	if detail_text != "":
		var detail: Label = Label.new()
		detail.text = detail_text
		detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		detail.add_theme_font_size_override("font_size", 14)
		detail.add_theme_color_override("font_color", Color(0.62, 0.78, 0.72))
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(detail)

	vbox.add_child(_spacer(8))

	var hint: Label = Label.new()
	hint.text = "本局为单次启动内的连续冒险：" + ("联机模式" if SessionHub.mode != "solo" else "单人模式")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(hint)

	vbox.add_child(_spacer(12))

	var menu_btn: Button = _make_button("返回主菜单")
	menu_btn.pressed.connect(_go_main_menu)
	vbox.add_child(menu_btn)

	var quit_btn: Button = _make_button("退出游戏")
	quit_btn.pressed.connect(func() -> void: get_tree().quit())
	vbox.add_child(quit_btn)

	if not DisplayServer.get_name() == "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _act05_detail() -> String:
	var act5: Variant = _summary.get("act05", {})
	if not (act5 is Dictionary) or not bool((act5 as Dictionary).get("completed", false)):
		return ""
	var info: Dictionary = act5 as Dictionary
	var seconds: int = int(float(info.get("seconds", 0.0)))
	var participants: Dictionary = info.get("participants", {}) as Dictionary
	var ready: Array = participants.get("ready", []) as Array
	return "第五幕用时 %d:%02d · 锁定尝试 %d 次 · 共振冲击 %d 次 · 参与完成 %d 人" % [
		seconds / 60, seconds % 60, int(info.get("lock_attempts", 0)), int(info.get("surges", 0)), ready.size()]


func _chapter_lines() -> String:
	var lines: Array[String] = []
	var order: Array[String] = ["act01", "act23", "act04", "act05"]
	var labels: Dictionary = {
		"act01": "第一幕 · 沉默的矿区",
		"act23": "第二/三幕 · 最后一班矿车与断轨",
		"act04": "第四幕 · 会记忆的晶体",
		"act05": "第五幕 · 地心的回声",
	}
	for key in order:
		var info: Dictionary = (_summary.get(key, {}) as Dictionary)
		var done: bool = bool(info.get("completed", false))
		var mark: String = "●" if done else "○"
		lines.append("%s  %s" % [mark, str(labels.get(key, key))])
	return "\n".join(lines)

func _go_main_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/launcher.tscn")

func _make_button(text: String) -> Button:
	var btn: Button = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(320, 52)
	btn.add_theme_font_size_override("font_size", 19)
	return btn

func _spacer(h: int) -> Control:
	var c: Control = Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c