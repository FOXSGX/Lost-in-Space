extends LISDemoStage
## 示例 6 · 杠杆和机械门场
##
## 玩家可以：搬运配重 → 选择不同力臂位置 → 直接推动杠杆 →
## 触发真实限位开关 → 观察电机驱动门体 → 放置障碍物阻挡门 → 移走配重观察复位。
##
## 物理链条是完整的：
##   货箱压在杠杆载物台 → 杠杆绕真实支点转动 → 杠杆下方的触发杆压下顶杆
##   → 限位开关闭合 → 电动门收到开门指令 → 门被马达推开
## 没有任何一环是脚本直接设状态。

var lever: LISLever
var door: LISMotorDoor
var limit_switch: LISLimitSwitch
var weights: Array[LISBody] = []
var _weight_spawns: Array[Transform3D] = []
var _switch_was_closed: bool = false


func _ready() -> void:
	stage_title = "示例 6 · 杠杆和机械门场"
	stage_help = """左键 抓取 / 松手 · 右键松手 · X 抛掷
把重箱搬到杠杆的载物台上（近端 vs 远端力臂不同）
杠杆压下 → 触发杆压住限位开关 → 电动门自动打开
往门里塞箱子可以观察堵转
R 复位

重箱：12 kg ×3、26 kg ×1
杠杆阈值约 19 kg（远端）。"""
	spawn_point = Vector3(0.0, 1.2, 10.0)
	stage_half = 18.0
	super()


func _build_scenery() -> void:
	# 把杠杆与门分开摆，中间留出走位空间
	add_static_box("WallLeft", Vector3(0.5, 3.0, 20.0), Vector3(-11.0, 1.5, 0.0),
		Vector3.ZERO, Color(0.24, 0.27, 0.31))
	add_static_box("WallRight", Vector3(0.5, 3.0, 20.0), Vector3(11.0, 1.5, 0.0),
		Vector3.ZERO, Color(0.24, 0.27, 0.31))
	# 门后的短廊，让"门开了能过去"看得见
	add_static_box("CorridorL", Vector3(0.4, 2.6, 6.0), Vector3(4.4, 1.3, -8.0),
		Vector3.ZERO, Color(0.22, 0.25, 0.28))
	add_static_box("CorridorR", Vector3(0.4, 2.6, 6.0), Vector3(7.6, 1.3, -8.0),
		Vector3.ZERO, Color(0.22, 0.25, 0.28))


func _build_content() -> void:
	# 杠杆
	lever = LISLever.new()
	lever.name = "StageLever"
	add_child(lever)
	lever.global_position = Vector3(-6.0, LISLever.PIVOT_HEIGHT, 0.0)
	register_reset(lever)

	# 限位开关：装在杠杆触发杆正下方
	limit_switch = LISLimitSwitch.new()
	limit_switch.name = "StageSwitch"
	add_child(limit_switch)
	# 触发杆在支点前方 0.30 m（局部 +Z），所以开关放在同一 z 上
	limit_switch.global_position = lever.global_position + Vector3(0.0, -LISLever.PIVOT_HEIGHT, 0.30)
	await get_tree().physics_frame
	limit_switch.state_changed.connect(_on_switch_changed)

	# 电动门
	door = LISMotorDoor.new()
	door.name = "StageDoor"
	add_child(door)
	door.global_position = Vector3(6.0, 0.0, -4.0)
	register_reset(door)

	# 配重块
	var specs: Array = [
		["W12a", 12.0, Vector3(-8.0, 0.31, 4.0)],
		["W12b", 12.0, Vector3(-6.5, 0.31, 4.0)],
		["W12c", 12.0, Vector3(-5.0, 0.31, 4.0)],
		["W26", 26.0, Vector3(-3.5, 0.46, 4.0)],
	]
	for s: Array in specs:
		var b: LISBody = add_body(str(s[0]), s[2], Vector3(0.6, 0.6, 0.6),
			float(s[1]), Color(0.74, 0.58, 0.32),
			{"display_name": "%s（%.0f kg）" % [str(s[0]), float(s[1])]})
		weights.append(b)
		_weight_spawns.append(b.global_transform)


func _on_switch_changed(closed: bool) -> void:
	if door != null and is_instance_valid(door):
		# 开关闭合 = 请求开门
		door.set_request(closed)


func _physics_process(_delta: float) -> void:
	var out: PackedStringArray = PackedStringArray()
	if lever != null and is_instance_valid(lever):
		out.append("杠杆角度 %+.2f° · 载物 %.0f kg · 力臂 %.2f m" % [
			lever.angle_deg(), lever.pan_load_kg,
			lever.arm_length(lever.pan_world())])
		out.append("重力力矩 %.0f N·m · 货物力矩 %.0f N·m" % [
			lever.gravity_torque(), lever.load_torque(lever.pan_cargo())])
	if limit_switch != null and is_instance_valid(limit_switch):
		out.append("限位开关：%s · 压缩 %.1f mm · 压着它的：%s" % [
			"闭合" if limit_switch.is_closed() else "断开",
			limit_switch.compression * 1000.0,
			limit_switch.pressed_by if limit_switch.pressed_by != "" else "（无）"])
	if door != null and is_instance_valid(door):
		out.append("电动门 %.1f° · %s · 马达力矩 %.0f N·m" % [
			door.angle_deg(), "堵转" if door.blocked else ("开" if door.is_open() else "关"),
			door.motor_torque])
	if hud != null and is_instance_valid(hud):
		hud.extra_lines = out


func reset_stage() -> void:
	for i in range(weights.size()):
		var w: LISBody = weights[i]
		if w != null and is_instance_valid(w):
			w.reset_to(_weight_spawns[i])
	if lever != null and is_instance_valid(lever):
		lever.reset_lever()
	if limit_switch != null and is_instance_valid(limit_switch):
		limit_switch.reset_switch()
	if door != null and is_instance_valid(door):
		door.reset_door()
		door.rearm(false)
	super()
