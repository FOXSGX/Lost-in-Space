extends LISDemoStage
## 示例 8 · 最小星球接入场景
##
## 这一份是**最小接入样板**：从干净 Godot 工程开始，只导入 SDK，
## 接入一个普通第一人称玩家，然后用尽量少的代码实现：
##   * 一个可抓握箱子
##   * 一扇真实铰链门
##   * 一个能够靠重量触发的杠杆
##
## 全部接入代码就是本文件里的 `_build_content()` 与玩家上的 6 行适配器配置。
## 不依赖共振星任何任务 flag，不依赖任何项目单例。
##
## 对照 `docs/QUICKSTART.md` 阅读效果最好。

var box: LISBody
var door: LISHingeDoor
var lever: LISLever
var counterweight: LISBody
var _box_spawn: Transform3D


func _ready() -> void:
	stage_title = "示例 8 · 最小星球接入场景"
	stage_help = """这是一个**最小接入样板**：
只导入 SDK + 一个普通第一人称玩家，
就得到可抓握箱子、真实铰链门、靠重量触发的杠杆。

左键 抓取 / 松手 · 右键松手 · X 抛掷 · R 复位
把箱子搬到杠杆载物台上，杠杆会把门顶开。"""
	spawn_point = Vector3(0.0, 1.2, 8.0)
	stage_half = 14.0
	super()


func _build_scenery() -> void:
	# 一段走廊，让门有存在的意义
	add_static_box("WallL", Vector3(0.4, 2.6, 10.0), Vector3(-3.2, 1.3, -4.0),
		Vector3.ZERO, Color(0.26, 0.29, 0.33))
	add_static_box("WallR", Vector3(0.4, 2.6, 10.0), Vector3(3.2, 1.3, -4.0),
		Vector3.ZERO, Color(0.26, 0.29, 0.33))
	# 房间后墙
	add_static_box("BackWall", Vector3(0.4, 2.6, 0.4), Vector3(0.0, 1.3, -9.0),
		Vector3.ZERO, Color(0.24, 0.27, 0.31))


func _build_content() -> void:
	# === 1) 一个可抓握箱子（两行代码）=================================
	# LISBodyProfile 决定质量、摩擦、是否可举起等真实参数。
	var prof: LISBodyProfile = LISBodyProfile.new()
	prof.display_name = "可抓握木箱"
	prof.size = Vector3(0.55, 0.55, 0.55)
	prof.mass_kg = 15.0
	prof.friction = 0.7
	prof.liftable = true
	prof.color = Color(0.72, 0.58, 0.34)
	prof.grip_handles = 2
	box = LISBody.new()
	box.name = "Crate"
	box.profile = prof
	box.position = Vector3(-1.6, 0.31, 4.0)
	add_child(box)
	_box_spawn = box.global_transform

	# === 2) 一扇真实铰链门（三行代码）=================================
	door = LISHingeDoor.new()
	door.name = "Door"
	door.position = Vector3(0.0, 0.0, -1.0)
	add_child(door)

	# === 3) 一个靠重量触发的杠杆（三行代码）===========================
	lever = LISLever.new()
	lever.name = "Lever"
	lever.position = Vector3(2.0, LISLever.PIVOT_HEIGHT, -6.0)
	add_child(lever)
	register_reset(lever)
	# 配重：即使没有货物，杠杆也稳定停在平衡角；压上足够重量才下沉
	counterweight = add_body("Counterweight", Vector3(2.0, 1.5, -5.2),
		Vector3(0.5, 0.5, 0.5), 12.0, Color(0.62, 0.62, 0.66),
		{"display_name": "配重块 12 kg"})

	# 门与杠杆之间的联动（最小接线，不引入任何任务 flag）：
	# 在 _physics_process 里读杠杆真实角度即可 —— 角度来自铰链约束与力矩，
	# 不是脚本设定的状态。
func _physics_process(_delta: float) -> void:
	if lever == null or not is_instance_valid(lever) or door == null or not is_instance_valid(door):
		return
	# 杠杆被压下（载物端下沉 → 角度为负）时推门
	if lever.angle_deg() < -4.0 and not door.is_open():
		door.push_along(Vector3(1.0, 0.0, 0.0), 90.0)

	var out: PackedStringArray = PackedStringArray()
	out.append("杠杆角度 %+.1f° · 载物 %.0f kg" % [
		lever.angle_deg(), lever.pan_load_kg])
	out.append("杠杆力矩：自重 %.0f · 货物 %.0f N·m" % [
		lever.gravity_torque(), lever.load_torque(lever.pan_cargo())])
	out.append("门开合 %.1f°（%s）" % [
		door.get_open_degrees(), "开" if door.is_open() else "关"])
	if hud != null and is_instance_valid(hud):
		hud.extra_lines = out


func reset_stage() -> void:
	if box != null and is_instance_valid(box):
		box.reset_to(_box_spawn)
	if lever != null and is_instance_valid(lever):
		lever.reset_lever()
	if door != null and is_instance_valid(door):
		door.reset_door()
	if counterweight != null and is_instance_valid(counterweight):
		counterweight.reset_to(Transform3D(Basis.IDENTITY, Vector3(2.0, 1.5, -5.2)))
	super()
