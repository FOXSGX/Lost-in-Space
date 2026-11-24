class_name LISDemoHUD
extends CanvasLayer
## LIS Physics SDK · 示例通用 HUD
##
## 只显示四类信息（任务书要求的第一人称 HUD）：
##   * 准星（选中时变色）
##   * 手持状态与施力读数
##   * 受阻 / 力不足提示
##   * 场景说明（贴在屏幕角落，不是漂浮在 3D 空间里的文字）
##
## SDK 核心不依赖本类；各星球可以完全用自己的 HUD。

var adapter: LISFirstPersonAdapter
var title_text: String = ""
var help_text: String = ""
## 额外遥测行（由场景填入，例如车轮角速度）。
var extra_lines: PackedStringArray = PackedStringArray()

var _crosshair: Control
var _state: Label
var _extra: Label
var _blocked: Label
var _title: Label
var _help: Label


func _ready() -> void:
	layer = 5
	_build()


func _build() -> void:
	var root: Control = Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_crosshair = Control.new()
	_crosshair.name = "Crosshair"
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.custom_minimum_size = Vector2(18, 18)
	_crosshair.size = Vector2(18, 18)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair.draw.connect(_draw_crosshair)
	root.add_child(_crosshair)

	_title = Label.new()
	_title.name = "Title"
	_title.position = Vector2(24, 18)
	_title.add_theme_font_size_override("font_size", 20)
	_title.add_theme_color_override("font_color", Color(0.86, 0.94, 1.0))
	root.add_child(_title)

	_state = Label.new()
	_state.name = "State"
	_state.position = Vector2(24, 52)
	_state.add_theme_font_size_override("font_size", 15)
	_state.add_theme_color_override("font_color", Color(0.78, 0.88, 0.78))
	root.add_child(_state)

	_extra = Label.new()
	_extra.name = "Extra"
	_extra.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_extra.position = Vector2(24, -120)
	_extra.add_theme_font_size_override("font_size", 14)
	_extra.add_theme_color_override("font_color", Color(0.74, 0.84, 0.96))
	root.add_child(_extra)

	_blocked = Label.new()
	_blocked.name = "Blocked"
	_blocked.set_anchors_preset(Control.PRESET_CENTER)
	_blocked.position = Vector2(-70, 46)
	_blocked.add_theme_font_size_override("font_size", 17)
	_blocked.add_theme_color_override("font_color", Color(1.0, 0.62, 0.36))
	root.add_child(_blocked)

	_help = Label.new()
	_help.name = "Help"
	_help.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_help.position = Vector2(-430, -190)
	_help.custom_minimum_size = Vector2(410, 170)
	_help.size = Vector2(410, 170)
	_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help.add_theme_font_size_override("font_size", 13)
	_help.add_theme_color_override("font_color", Color(0.66, 0.74, 0.82))
	root.add_child(_help)


func _process(_delta: float) -> void:
	_title.text = title_text
	_help.text = help_text
	if adapter == null or not is_instance_valid(adapter):
		_state.text = ""
		_blocked.text = ""
		_extra.text = ""
		return
	var g: LISGrabber = adapter.grabber
	var lines: PackedStringArray = PackedStringArray()
	if g != null and g.is_holding():
		var nm: String = g.held.name
		var lm: LISBody = g.held as LISBody
		if lm != null:
			nm = lm.display_name
		lines.append("手持：%s · %.1f kg · 模式 %s" % [nm, g.held.mass, g.mode])
		lines.append("施力 %.0f / %.0f N   需求 %.0f N" % [g.last_force, g.grip_force, g.last_demand])
		lines.append("掌心力矩 %.0f / %.0f N·m（玩法辅助）" % [g.palm_torque, g.palm_cap])
		if g.saturated_frames > 3:
			lines.append("⚠ 力不足：物体跟不上手（%d 帧饱和）" % g.saturated_frames)
	else:
		if adapter.current_target != null:
			var t: LISBody = adapter.current_target as LISBody
			if t != null:
				lines.append("准星：%s · %.1f kg" % [t.display_name, t.mass])
			else:
				lines.append("准星：%s" % adapter.current_target.name)
		else:
			lines.append("准星：无目标")
	_state.text = "\n".join(lines)

	if g != null and g.is_holding() and g.saturated_frames > 6:
		_blocked.text = "受阻 / 力不足"
	elif adapter.blocked:
		_blocked.text = "受阻"
	else:
		_blocked.text = ""

	var out: PackedStringArray = PackedStringArray()
	for line: String in extra_lines:
		out.append(line)
	_extra.text = "\n".join(out)
	_crosshair.queue_redraw()


func _draw_crosshair() -> void:
	var c: Vector2 = Vector2(9, 9)
	var col: Color = Color(0.92, 0.95, 1.0, 0.85)
	if adapter != null and is_instance_valid(adapter):
		if adapter.is_holding():
			col = Color(1.0, 0.82, 0.36, 0.95)
		elif adapter.current_target != null:
			col = Color(0.55, 0.95, 0.72, 0.95)
	_crosshair.draw_line(c + Vector2(-7, 0), c + Vector2(-2, 0), col, 2.0)
	_crosshair.draw_line(c + Vector2(2, 0), c + Vector2(7, 0), col, 2.0)
	_crosshair.draw_line(c + Vector2(0, -7), c + Vector2(0, -2), col, 2.0)
	_crosshair.draw_line(c + Vector2(0, 2), c + Vector2(0, 7), col, 2.0)
