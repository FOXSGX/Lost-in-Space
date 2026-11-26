extends LISDemoStage
## 示例 5 · 绳索与滑轮场
##
## 玩家可以用第一人称视角：抓住货物 → 用绳索牵引重物 →
## 观察张力读数 → 查看受阻与复位结果。
##
## 场景里有三种绳索机构：
##   A. 多体缆绳（LISRope，逐段刚体 + 球铰）—— 真实张力、可抓自由端
##   B. 绞盘缆绳（LISCable + LISWinchDrum + LISPulley）—— 卷筒收放绳、近似切线模型

var rope: LISRope
var anchor_crate: LISBody
var winch: LISWinchDrum
var cable: LISCable
var pulley: LISPulley
var load_crate: LISBody

var _rope_spawn: Transform3D
var _load_spawn: Transform3D


func _ready() -> void:
	stage_title = "示例 5 · 绳索与滑轮场"
	stage_help = """左键 抓住缆绳自由端 / 货物 · 右键松手 · X 抛掷
R 复位

左侧：多体缆绳（真实绳段 + 球铰）
  抓住黄色绳头，后退即可牵引货箱。
右侧：绞盘 + 定滑轮
  E 切换电机 · 空格 切换制动（靠近控制台）
  （本示例为演示用，键位见下方状态栏）

HUD 显示真实张力与伸长率。"""
	spawn_point = Vector3(0.0, 1.2, 12.0)
	stage_half = 20.0
	super()


func _build_scenery() -> void:
	# 两侧的锚柱
	add_static_box("AnchorPostA", Vector3(0.5, 4.0, 0.5), Vector3(-9.0, 2.0, -6.0),
		Vector3.ZERO, Color(0.34, 0.36, 0.40))
	add_static_box("AnchorPostB", Vector3(0.5, 4.0, 0.5), Vector3(10.0, 2.0, 2.0),
		Vector3.ZERO, Color(0.34, 0.36, 0.40))
	# 矮墙：货物拖到这里会被挡住
	add_static_box("StopWall", Vector3(6.0, 1.2, 0.4), Vector3(6.0, 0.6, -2.0),
		Vector3.ZERO, Color(0.30, 0.33, 0.37))
	# 地面分区色块
	var mi: MeshInstance3D = MeshInstance3D.new()
	var qm: PlaneMesh = PlaneMesh.new()
	qm.size = Vector2(14.0, 10.0)
	mi.mesh = qm
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = Color(0.20, 0.26, 0.30)
	m.roughness = 0.95
	mi.material_override = m
	mi.position = Vector3(-6.0, 0.005, -2.0)
	add_child(mi)


func _build_content() -> void:
	# --- A. 多体缆绳 ---------------------------------------------------
	anchor_crate = add_body("RopeCrate", Vector3(-7.5, 0.51, 4.0),
		Vector3(1.0, 1.0, 1.0), 60.0, Color(0.72, 0.58, 0.34),
		{"display_name": "缆绳货箱 60 kg", "friction": 0.8})
	_rope_spawn = anchor_crate.global_transform
	rope = LISRope.new()
	rope.name = "StageRope"
	add_child(rope)
	await get_tree().physics_frame
	# 从货箱朝 +X 方向摊开 3.4 m
	rope.build(10, 0.34, anchor_crate.global_position + Vector3(0.55, 0.2, 0.0),
		Vector3.RIGHT, true, 0.0)
	await get_tree().physics_frame
	rope.anchor_first_to(anchor_crate, anchor_crate.global_position + Vector3(0.55, 0.2, 0.0))

	# --- B. 绞盘 + 滑轮 -------------------------------------------------
	winch = LISWinchDrum.new()
	winch.name = "StageWinch"
	add_child(winch)
	winch.global_position = Vector3(8.5, 1.6, 8.0)
	await get_tree().physics_frame

	pulley = LISPulley.new()
	pulley.name = "StagePulley"
	add_child(pulley)
	pulley.global_position = Vector3(10.0, 3.2, 2.4)

	load_crate = add_body("WinchLoad", Vector3(8.5, 0.41, 0.2),
		Vector3(0.8, 0.8, 0.8), 40.0, Color(0.56, 0.48, 0.66),
		{"display_name": "绞盘负载 40 kg", "friction": 0.8})
	_load_spawn = load_crate.global_transform

	cable = LISCable.new()
	cable.name = "StageCable"
	add_child(cable)
	await get_tree().physics_frame
	cable.setup(winch)
	cable.add_pulley(pulley)
	cable.add_load(load_crate, Vector3(0.0, 0.3, 0.0))
	cable.finalize()

	# 控制提示（贴在设备侧面，不是漂浮文字）
	add_sign_plate(Vector3(8.5, 1.35, 7.55), Vector2(0.9, 0.45),
		Color(0.86, 0.66, 0.22), Vector3(-40.0, 0.0, 0.0))


func _physics_process(delta: float) -> void:
	# 绞盘机构必须由场景每帧驱动：先解绳约束、再驱动卷筒（电机/制动），
	# 这样制动器才能用上最新张力做前馈。顺序反了会抖。
	if cable != null and is_instance_valid(cable) and winch != null and is_instance_valid(winch):
		cable.solve(delta)
		winch.drive(delta, cable.reaction_torque)

	var out: PackedStringArray = PackedStringArray()
	if rope != null and is_instance_valid(rope):
		out.append("多体缆绳：伸长 %+.2f%% · 段间误差 %.4f m · %s" % [
			rope.stretch_ratio() * 100.0, rope.max_joint_gap(),
			"绷紧" if rope.is_taut() else "松弛"])
	if cable != null and is_instance_valid(cable):
		out.append("绞盘缆绳：张力 %.0f N · 峰值 %.0f N · 弹性伸长 %.3f m" % [
			cable.tension, cable.peak_tension, cable.elongation])
		out.append("卷筒 %.2f rad/s · 电机 %s · 制动 %s · 收绳 %.2f m" % [
			winch.omega if winch != null and is_instance_valid(winch) else 0.0,
			"开" if winch != null and winch.motor_on else "关",
			"开" if winch != null and winch.brake_on else "关",
			cable.take_in])
	if load_crate != null and is_instance_valid(load_crate):
		out.append("负载位置 y=%.2f m · 速度 %.2f m/s" % [
			load_crate.global_position.y, load_crate.linear_velocity.length()])
	if hud != null and is_instance_valid(hud):
		hud.extra_lines = out


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_E:
			if winch != null and is_instance_valid(winch):
				winch.set_motor(not winch.motor_on, LISWinchDrum.MOTOR_OMEGA)
		KEY_SPACE:
			if winch != null and is_instance_valid(winch):
				winch.set_brake(not winch.brake_on)


func reset_stage() -> void:
	if anchor_crate != null and is_instance_valid(anchor_crate):
		anchor_crate.reset_to(_rope_spawn)
	if load_crate != null and is_instance_valid(load_crate):
		load_crate.reset_to(_load_spawn)
	if rope != null and is_instance_valid(rope):
		rope.reset_rope()
	if winch != null and is_instance_valid(winch):
		winch.reset_drum()
	if cable != null and is_instance_valid(cable):
		cable.reset_cable()
	super()


## 绞盘电机需要每物理帧驱动（演示里由场景直接驱动）。
func _integrate_forces(_state: PhysicsDirectBodyState3D) -> void:
	pass
