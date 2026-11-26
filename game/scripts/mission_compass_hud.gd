extends Control
class_name MissionCompassHUD

## 《迷失太空》写实科幻宇航员头盔面罩全息投影 HUD
## 1. 头盔曲面面罩光学投影弧线边框（极克制暗角与冰青光学刻度，真实戴头盔视角）
## 2. 顶部全息导航条（严格遵从用户要求：不显示距离数字、不显示东南西北，仅显示发光目标符号与名称）
## 3. 右上角透明全息任务指令投影卡（HarmonyOS Sans SC 锐利排版）
## 4. 左下角实时战术雷达小地图（动态显示玩家朝向视锥、全部建筑/船舱格局、探险车与当前主线目标！）

const COMPASS_W: float = 440.0
const COMPASS_H: float = 34.0
const MINIMAP_SIZE: float = 188.0

# 霜烬星 15 栋大型建筑 + 飞船（合计 16 座建筑群）真实平面轮廓数据（左下角实时雷达小地图）
const FROST_MAP_BUILDINGS: Array = [
	["ship", Vector2(0.0, 12.0), Vector2(14.0, 14.0), Color("#ffba5c"), false],
	["main", Vector2(0.0, -110.0), Vector2(60.0, 32.0), Color("#4ce8ff"), false],
	["museum", Vector2(-49.0, -70.0), Vector2(32.0, 38.0), Color("#7ac4d6"), false],
	["living", Vector2(49.0, -63.0), Vector2(32.0, 38.0), Color("#58d6b8"), false],
	["power", Vector2(58.0, -116.0), Vector2(26.0, 28.0), Color("#ffae42"), false],
	["garage", Vector2(46.0, -22.0), Vector2(44.0, 28.0), Color("#d6b472"), false],
	["warehouse", Vector2(-43.0, -22.0), Vector2(40.0, 28.0), Color("#90c0c8"), false],
	["greenhouse", Vector2(-108.0, -112.0), Vector2(32.0, 32.0), Color("#42f09c"), true],
	["comms_hub", Vector2(112.0, -108.0), Vector2(34.0, 30.0), Color("#4ce8ff"), false],
	["cargo_depot", Vector2(-108.0, -32.0), Vector2(42.0, 32.0), Color("#f0a448"), false],
	["mech_hangar", Vector2(112.0, -34.0), Vector2(42.0, 34.0), Color("#f0a448"), false],
	["observatory", Vector2(-164.0, -78.0), Vector2(32.0, 32.0), Color("#58e0ff"), true],
	["reactor_hall", Vector2(166.0, -76.0), Vector2(38.0, 34.0), Color("#ffae42"), false],
	["drill_station", Vector2(-72.0, -166.0), Vector2(36.0, 28.0), Color("#72c5ce"), false],
	["north_fort", Vector2(74.0, -166.0), Vector2(34.0, 28.0), Color("#f0a448"), false],
	["south_hub", Vector2(72.0, 42.0), Vector2(40.0, 30.0), Color("#58d6b8"), false],
	["south_outpost", Vector2(-84.0, 44.0), Vector2(32.0, 32.0), Color("#42f09c"), true],
]

class VisorOverlay extends Control:
	var sweep_clock: float = 0.0

	func _process(delta: float) -> void:
		sweep_clock += delta
		queue_redraw()

	func _draw() -> void:
		var sz: Vector2 = size
		if sz.x < 200.0 or sz.y < 200.0:
			return
		var w: float = sz.x
		var h: float = sz.y
		var col_dim: Color = Color(0.28, 0.85, 0.98, 0.14)
		var col_line: Color = Color(0.32, 0.90, 1.0, 0.26)
		var col_rim: Color = Color(0.01, 0.04, 0.07, 0.34)

		# 1. 头盔四角极微弱的曲面面罩内框阴影（保持 92%+ 中心画面完全通透）
		var corner_r: float = minf(w, h) * 0.18
		draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(corner_r, 0), Vector2(0, corner_r * 0.65)]), col_rim)
		draw_colored_polygon(PackedVector2Array([Vector2(w, 0), Vector2(w - corner_r, 0), Vector2(w, corner_r * 0.65)]), col_rim)
		draw_colored_polygon(PackedVector2Array([Vector2(0, h), Vector2(corner_r * 0.85, h), Vector2(0, h - corner_r * 0.65)]), col_rim)
		draw_colored_polygon(PackedVector2Array([Vector2(w, h), Vector2(w - corner_r * 0.85, h), Vector2(w, h - corner_r * 0.65)]), col_rim)

		# 2. 左右两侧宇航员头盔曲面全息弧线与微刻度（真实面罩投影沉浸感）
		var left_center: Vector2 = Vector2(w * 0.42, h * 0.50)
		var right_center: Vector2 = Vector2(w * 0.58, h * 0.50)
		var arc_r: float = w * 0.405
		draw_arc(left_center, arc_r, PI * 0.84, PI * 1.16, 28, col_dim, 1.4, true)
		draw_arc(right_center, arc_r, -PI * 0.16, PI * 0.16, 28, col_dim, 1.4, true)
		# 左右中段俯仰微刻度短线
		for k: int in range(-4, 5):
			var ang: float = float(k) * 0.032
			var tick_len: float = 10.0 if k == 0 else (6.0 if k % 2 == 0 else 4.0)
			var lp: Vector2 = left_center + Vector2(-cos(ang), sin(ang)) * arc_r
			draw_line(lp, lp + Vector2(tick_len, 0.0), col_line if k == 0 else col_dim, 1.3)
			var rp: Vector2 = right_center + Vector2(cos(ang), sin(ang)) * arc_r
			draw_line(rp, rp - Vector2(tick_len, 0.0), col_line if k == 0 else col_dim, 1.3)

		# 3. 顶部微弧形头盔上沿投影线
		draw_arc(Vector2(w * 0.5, h * 1.35), h * 1.31, -PI * 0.58, -PI * 0.42, 32, col_dim, 1.2, true)
		# 4. 四角极细全息 L 形校准框
		var m: float = 12.0
		var L: float = 18.0
		for pt: Array in [[m, m, 1, 1], [w - m, m, -1, 1], [m, h - m, 1, -1], [w - m, h - m, -1, -1]]:
			var p0: Vector2 = Vector2(float(pt[0]), float(pt[1]))
			draw_line(p0, p0 + Vector2(float(pt[2]) * L, 0.0), col_line, 1.6)
			draw_line(p0, p0 + Vector2(0.0, float(pt[3]) * L), col_line, 1.6)


class CompassTickStrip extends Control:
	var cam_yaw: float = 0.0

	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y
		var col_tick: Color = Color(0.32, 0.88, 1.0, 0.28)
		var col_sub: Color = Color(0.32, 0.88, 1.0, 0.14)
		# 纯科技刻度滑尺（绝无东南西北文字，随转头丝滑滑动）
		var px_per_rad: float = w / (PI * 0.72)
		var step_rad: float = PI / 24.0
		var offset: float = fposmod(-cam_yaw, step_rad)
		var start_x: float = (offset / step_rad) * (step_rad * px_per_rad)
		var x: float = start_x
		var idx: int = 0
		while x < w:
			var tall: bool = (idx % 3 == 0)
			draw_line(Vector2(x, h - (8.0 if tall else 4.0)), Vector2(x, h), col_tick if tall else col_sub, 1.2)
			x += step_rad * px_per_rad
			idx += 1
		# 正中全息准星小三角 ▽
		var mid: float = w * 0.5
		draw_colored_polygon(PackedVector2Array([Vector2(mid - 5.0, 0.0), Vector2(mid + 5.0, 0.0), Vector2(mid, 6.0)]), UIStyleKit.VISOR_CYAN)


class TacticalMinimap extends Control:
	var mode: String = "frost"
	var player_pos: Vector3 = Vector3.ZERO
	var player_fwd: Vector2 = Vector2(0.0, -1.0)
	var targets: Array = []
	var sweep: float = 0.0

	func _process(delta: float) -> void:
		sweep = fmod(sweep + delta * 1.15, TAU)
		queue_redraw()

	func _draw() -> void:
		var sz: Vector2 = size
		var c: Vector2 = sz * 0.5
		var rad: float = minf(sz.x, sz.y) * 0.48
		# 1. 深空半透明雷达面罩圆盘底 + 双环全息外框 + 同心测距圈
		draw_circle(c, rad, Color(0.025, 0.072, 0.115, 0.72))
		draw_arc(c, rad, 0.0, TAU, 48, Color(0.30, 0.88, 1.0, 0.65), 1.8, true)
		draw_arc(c, rad * 0.66, 0.0, TAU, 40, Color(0.26, 0.78, 0.92, 0.20), 1.0, true)
		draw_arc(c, rad * 0.33, 0.0, TAU, 32, Color(0.26, 0.78, 0.92, 0.16), 1.0, true)
		# 十字准线
		draw_line(c - Vector2(rad, 0.0), c + Vector2(rad, 0.0), Color(0.26, 0.78, 0.92, 0.14), 1.0)
		draw_line(c - Vector2(0.0, rad), c + Vector2(0.0, rad), Color(0.26, 0.78, 0.92, 0.14), 1.0)

		# 2. 动态旋转全息扫描扇面
		var sweep_dir: Vector2 = Vector2(cos(sweep), sin(sweep))
		var sweep_trail: Vector2 = Vector2(cos(sweep - 0.38), sin(sweep - 0.38))
		draw_colored_polygon(PackedVector2Array([c, c + sweep_trail * rad, c + sweep_dir * rad]), Color(0.25, 0.86, 1.0, 0.10))
		draw_line(c, c + sweep_dir * rad, Color(0.38, 0.94, 1.0, 0.45), 1.4)

		# 3. 实时绘制真实场景布局（霜烬星 11 栋建筑群 / 归航号船舱分区）
		var scale_px: float = (rad / 245.0) if mode == "frost" else (rad / 20.0)
		if mode == "frost":
			# 绘制北部巨兽骨架峡谷走廊轮廓
			var canyon_p: Vector2 = _to_map(Vector2(0.0, -250.0), scale_px, c)
			var canyon_sz: Vector2 = Vector2(36.0, 140.0) * scale_px
			var canyon_rect: Rect2 = Rect2(canyon_p - canyon_sz * 0.5, canyon_sz)
			if canyon_p.distance_to(c) < rad + 40.0:
				draw_rect(canyon_rect, Color(0.55, 0.85, 0.95, 0.14), true)
			# 绘制全部 11 栋建筑 + 飞船真实占地
			for b: Array in FROST_MAP_BUILDINGS:
				var bp: Vector2 = _to_map(b[1] as Vector2, scale_px, c)
				if bp.distance_to(c) > rad - 4.0:
					continue
				var bsz: Vector2 = (b[2] as Vector2) * scale_px
				var bcol: Color = b[3] as Color
				var is_dome: bool = bool(b[4])
				if is_dome:
					var dr: float = maxf(bsz.x * 0.5, 4.0)
					draw_circle(bp, dr, Color(bcol.r, bcol.g, bcol.b, 0.34))
					draw_arc(bp, dr, 0.0, TAU, 16, bcol, 1.2, true)
				else:
					var r: Rect2 = Rect2(bp - bsz * 0.5, bsz)
					draw_rect(r, Color(bcol.r, bcol.g, bcol.b, 0.28), true)
					draw_rect(r, Color(bcol.r, bcol.g, bcol.b, 0.78), false, 1.0)
		else:
			# 归航号太空舱船体轮廓 + 舰桥 + 中央星图 + 右舷独立训练舱门 + 尾舱出舱门
			var hull_c: Vector2 = _to_map(Vector2(0.0, 0.0), scale_px, c)
			var hull_sz: Vector2 = Vector2(38.0, 31.0) * scale_px
			draw_rect(Rect2(hull_c - hull_sz * 0.5, hull_sz), Color(0.24, 0.72, 0.88, 0.16), true)
			draw_rect(Rect2(hull_c - hull_sz * 0.5, hull_sz), Color(0.32, 0.88, 1.0, 0.55), false, 1.3)
			# 中央主廊
			var hall_sz: Vector2 = Vector2(13.0, 30.0) * scale_px
			draw_rect(Rect2(hull_c - hall_sz * 0.5, hall_sz), Color(0.30, 0.84, 0.96, 0.14), true)
			# 中央星图台圆标
			draw_circle(_to_map(Vector2(0.0, -0.34), scale_px, c), 5.0, Color("#4ce8ff"))
			# 右舷独立训练舱门（青绿高亮）
			var tr_p: Vector2 = _to_map(Vector2(6.5, 10.18), scale_px, c)
			draw_rect(Rect2(tr_p - Vector2(3.0, 6.0), Vector2(6.0, 12.0)), Color("#34f0b4"), true)
			# 尾舱星球出舱门（珊瑚橙高亮）
			var ex_p: Vector2 = _to_map(Vector2(0.0, 15.4), scale_px, c)
			draw_rect(Rect2(ex_p - Vector2(7.0, 3.0), Vector2(14.0, 6.0)), Color("#ff6a48"), true)

		# 4. 绘制任务主线目标与周边重要点位（超出雷达圈时贴边高亮指示方向！）
		for tgt: Dictionary in targets:
			var tp: Vector3 = tgt.pos
			var rel: Vector2 = Vector2(tp.x - player_pos.x, tp.z - player_pos.z) * scale_px
			var is_main: bool = bool(tgt.get("main", false))
			var col: Color = UIStyleKit.VISOR_AMBER if is_main else (tgt.get("color", UIStyleKit.VISOR_CYAN) as Color)
			var clamped: bool = rel.length() > rad - 7.0
			var mp: Vector2 = c + (rel.normalized() * (rad - 7.0) if clamped else rel)
			if is_main:
				var pulse: float = 1.0 + 0.25 * sin(sweep * 4.0)
				var s: float = 6.0 * pulse
				draw_colored_polygon(PackedVector2Array([
					mp + Vector2(0, -s), mp + Vector2(s, 0), mp + Vector2(0, s), mp + Vector2(-s, 0)
				]), col)
				draw_arc(mp, s + 3.0, 0.0, TAU, 16, Color(col.r, col.g, col.b, 0.5), 1.2)
			else:
				draw_circle(mp, 3.4, col)

		# 5. 中心玩家实时位置 + 朝向视野扇区锥
		var f: Vector2 = player_fwd.normalized() if player_fwd.length_squared() > 0.001 else Vector2(0.0, -1.0)
		var right_v: Vector2 = Vector2(-f.y, f.x)
		var cone_len: float = 28.0
		var cone_half: float = 13.0
		draw_colored_polygon(PackedVector2Array([
			c, c + f * cone_len - right_v * cone_half, c + f * cone_len + right_v * cone_half
		]), Color(0.55, 0.96, 1.0, 0.20))
		# 玩家亮白箭头
		draw_colored_polygon(PackedVector2Array([
			c + f * 8.0,
			c - f * 5.0 + right_v * 5.0,
			c - f * 2.5,
			c - f * 5.0 - right_v * 5.0,
		]), Color("#FFFFFF"))

	func _to_map(world_xz: Vector2, scale_px: float, center: Vector2) -> Vector2:
		return center + (world_xz - Vector2(player_pos.x, player_pos.z)) * scale_px


var _visor: VisorOverlay
var _compass_box: PanelContainer
var _compass_track: Control
var _tick_strip: CompassTickStrip
var _card: PanelContainer
var _stage_pill: PanelContainer
var _stage_label: Label
var _title_label: Label
var _detail_label: Label
var _side_label: Label
var _minimap_frame: PanelContainer
var _minimap: TacticalMinimap
var _minimap_title: Label
var _markers: Array[Dictionary] = []

func _ready() -> void:
	name = "MissionCompassHUD"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()

func _build_ui() -> void:
	# 0. 全屏头盔面罩曲面投影光学层
	_visor = VisorOverlay.new()
	_visor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_visor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_visor)

	# 1. 顶部居中写实科幻头盔全息导航条（无距离、无东南西北！）
	_compass_box = PanelContainer.new()
	_compass_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_compass_box.add_theme_stylebox_override("panel", UIStyleKit.box(UIStyleKit.VISOR_GLASS, UIStyleKit.VISOR_BORDER, 6, 1, 10, 4, 4))
	_compass_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_compass_box.offset_left = -COMPASS_W * 0.5
	_compass_box.offset_right = COMPASS_W * 0.5
	_compass_box.offset_top = 56.0
	_compass_box.offset_bottom = 56.0 + COMPASS_H
	add_child(_compass_box)

	_compass_track = Control.new()
	_compass_track.clip_contents = true
	_compass_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_compass_track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_compass_track.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_compass_box.add_child(_compass_track)

	_tick_strip = CompassTickStrip.new()
	_tick_strip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tick_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_compass_track.add_child(_tick_strip)

	for i: int in 6:
		var ml: Label = Label.new()
		ml.add_theme_font_override("font", UIStyleKit.FONT_BOLD)
		ml.add_theme_font_size_override("font_size", 14 if i == 0 else 12)
		ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ml.size = Vector2(126.0, 22.0)
		ml.visible = false
		ml.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_compass_track.add_child(ml)
		_markers.append({"label": ml})

	# 2. 右上角透明全息投影任务指令面板
	_card = PanelContainer.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_theme_stylebox_override("panel", UIStyleKit.visor_box(UIStyleKit.VISOR_CYAN, 3, 16, 12))
	_card.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_card.offset_left = -336.0
	_card.offset_right = -20.0
	_card.offset_top = 18.0
	_card.offset_bottom = 240.0
	add_child(_card)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(vbox)

	_stage_pill = PanelContainer.new()
	_stage_pill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_stage_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_pill.add_theme_stylebox_override("panel", UIStyleKit.box(Color(0.95, 0.58, 0.16, 0.24), UIStyleKit.VISOR_AMBER, 4, 1, 9, 2, 0))
	vbox.add_child(_stage_pill)

	_stage_label = Label.new()
	_stage_label.add_theme_font_override("font", UIStyleKit.FONT_BOLD)
	_stage_label.add_theme_font_size_override("font_size", 12)
	_stage_label.add_theme_color_override("font_color", UIStyleKit.VISOR_AMBER)
	_stage_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_pill.add_child(_stage_label)

	_title_label = Label.new()
	_title_label.add_theme_font_override("font", UIStyleKit.FONT_BOLD)
	_title_label.add_theme_font_size_override("font_size", 16)
	_title_label.add_theme_color_override("font_color", UIStyleKit.VISOR_TEXT)
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_title_label)

	_detail_label = Label.new()
	_detail_label.add_theme_font_override("font", UIStyleKit.FONT_REG)
	_detail_label.add_theme_font_size_override("font_size", 12)
	_detail_label.add_theme_color_override("font_color", UIStyleKit.VISOR_MUTED)
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_detail_label)

	var sep: ColorRect = ColorRect.new()
	sep.custom_minimum_size = Vector2(0.0, 1.0)
	sep.color = Color(0.28, 0.84, 0.96, 0.26)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sep)

	_side_label = Label.new()
	_side_label.add_theme_font_override("font", UIStyleKit.FONT_REG)
	_side_label.add_theme_font_size_override("font_size", 12)
	_side_label.add_theme_color_override("font_color", UIStyleKit.VISOR_TEAL)
	_side_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_side_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_side_label)

	# 3. 左下角实时全息战术雷达小地图（与血条、装备栏零重叠！）
	_minimap_frame = PanelContainer.new()
	_minimap_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap_frame.add_theme_stylebox_override("panel", UIStyleKit.visor_box(UIStyleKit.VISOR_CYAN, 2, 8, 8))
	_minimap_frame.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_minimap_frame.offset_left = 20.0
	_minimap_frame.offset_right = 20.0 + MINIMAP_SIZE + 18.0
	_minimap_frame.offset_top = -(MINIMAP_SIZE + 44.0)
	_minimap_frame.offset_bottom = -18.0
	add_child(_minimap_frame)

	var mvbox: VBoxContainer = VBoxContainer.new()
	mvbox.add_theme_constant_override("separation", 4)
	mvbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap_frame.add_child(mvbox)

	_minimap_title = Label.new()
	_minimap_title.text = "TAC-MAP // 霜烬星"
	_minimap_title.add_theme_font_override("font", UIStyleKit.FONT_BOLD)
	_minimap_title.add_theme_font_size_override("font_size", 11)
	_minimap_title.add_theme_color_override("font_color", UIStyleKit.VISOR_CYAN)
	_minimap_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_minimap_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mvbox.add_child(_minimap_title)

	_minimap = TacticalMinimap.new()
	_minimap.custom_minimum_size = Vector2(MINIMAP_SIZE, MINIMAP_SIZE)
	_minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mvbox.add_child(_minimap)

func update_guidance(viewer_pos: Vector3, viewer_forward: Vector3, stage_text: String, main_title: String, main_detail: String, side_lines: PackedStringArray, targets: Array, map_mode: String = "") -> void:
	_stage_label.text = stage_text
	_title_label.text = main_title
	_detail_label.text = main_detail
	_side_label.text = "\n".join(side_lines)
	_side_label.visible = not side_lines.is_empty()

	var fwd: Vector2 = Vector2(viewer_forward.x, viewer_forward.z)
	if fwd.length_squared() < 0.0001:
		fwd = Vector2(0.0, -1.0)
	else:
		fwd = fwd.normalized()
	var cam_yaw: float = atan2(-fwd.x, -fwd.y)
	_tick_strip.cam_yaw = cam_yaw
	_tick_strip.queue_redraw()

	# 自动识别当前在太空舱还是霜烬星，刷新左下角战术小地图
	var resolved_mode: String = map_mode
	if resolved_mode.is_empty():
		resolved_mode = "ship" if (stage_text.contains("归航") or stage_text.contains("星际") or stage_text.contains("舰体") or stage_text.contains("点火")) else "frost"
	_minimap.mode = resolved_mode
	_minimap.player_pos = viewer_pos
	_minimap.player_fwd = fwd
	_minimap.targets = targets
	_minimap_title.text = "DECK-MAP // 归航号主舱" if resolved_mode == "ship" else "TAC-MAP // 霜烬星盆地"

	# 顶部无距离、无东南西北纯净导航条
	var track_w: float = maxf(_compass_track.size.x, COMPASS_W - 20.0)
	var half_w: float = track_w * 0.5
	var fov_span: float = PI * 0.72
	var occupied_x: Array[float] = []
	for i: int in _markers.size():
		var ml: Label = _markers[i].label as Label
		if i >= targets.size():
			ml.visible = false
			continue
		var tgt: Dictionary = targets[i]
		var tp: Vector3 = tgt.pos
		var delta_xz: Vector2 = Vector2(tp.x - viewer_pos.x, tp.z - viewer_pos.z)
		var dist: float = delta_xz.length()
		var t_yaw: float = atan2(-delta_xz.x, -delta_xz.y) if dist > 0.2 else cam_yaw
		var diff: float = wrapf(t_yaw - cam_yaw, -PI, PI)
		var is_main: bool = bool(tgt.get("main", false))
		var clamped_ratio: float = clampf(-diff / (fov_span * 0.5), -0.88, 0.88)
		var px: float = half_w + clamped_ratio * half_w
		var overlapped: bool = false
		if not is_main:
			for ox: float in occupied_x:
				if absf(px - ox) < 104.0:
					overlapped = true
					break
		ml.visible = (is_main or absf(diff) < fov_span * 0.50) and not overlapped
		if ml.visible:
			occupied_x.append(px)
			var prefix: String = "◆ " if is_main else "▲ "
			if is_main and absf(diff) >= fov_span * 0.46:
				prefix = "◄ ◆ " if diff > 0.0 else "◆ ► "
			# 不显示任何距离数字，也不显示东南西北，只留极简科幻符号与地标名
			ml.text = "%s%s" % [prefix, String(tgt.label)]
			ml.add_theme_color_override("font_color", UIStyleKit.VISOR_AMBER if is_main else UIStyleKit.VISOR_CYAN)
			ml.position = Vector2(clampf(px - 63.0, 4.0, track_w - 130.0), 4.0)
