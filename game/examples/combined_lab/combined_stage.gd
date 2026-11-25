extends LISDemoStage
## 示例 7 · 综合机械实验场
##
## 同时存在：多个刚体 / 多人施力（程序化代理）/ 真实车轮 / 一套杠杆 /
##           一扇机械门 / 一套绳索机构。
##
## 目的：检查组合后是否出现物理冲突、异常弹飞、关节失效或脚本错误。
## 这也是自动化测试 integration_combined 对应的可视化场景。

var cart: LISCart
var lever: LISLever
var door: LISMotorDoor
var rope: LISRope
var rope_crate: LISBody
var agents: Array[LISFirstPersonAdapter] = []
var agent_roots: Array[Node3D] = []
var _anomaly_frames: int = 0
var _max_speed: float = 0.0


func _ready() -> void:
	stage_title = "示例 7 · 综合机械实验场"
	stage_help = """左键 抓取 / 松手 · 右键松手 · X 抛掷
F1 添加协力代理（最多 3 名）· F2 移除
E 切换绞盘电机 · R 复位

场景里同时有：推车 / 杠杆 / 电动门 / 缆绳 / 8 个刚体
观察 HUD 的"异常检查"栏是否一直为 0。"""
	spawn_point = Vector3(0.0, 1.2, 14.0)
	stage_half = 24.0
	super()


func _build_scenery() -> void:
	add_static_box("WallL", Vector3(0.5, 3.0, 30.0), Vector3(-14.0, 1.5, 0.0),
		Vector3.ZERO, Color(0.24, 0.27, 0.31))
	add_static_box("WallR", Vector3(0.5, 3.0, 30.0), Vector3(14.0, 1.5, 0.0),
		Vector3.ZERO, Color(0.24, 0.27, 0.31))
	add_static_box("WallBack", Vector3(28.0, 3.0, 0.5), Vector3(0.0, 1.5, -12.0),
		Vector3.ZERO, Color(0.24, 0.27, 0.31))
	# 中央岛台：把各机械分隔开
	add_static_box("Island", Vector3(6.0, 0.4, 6.0), Vector3(0.0, 0.2, 2.0),
		Vector3.ZERO, Color(0.30, 0.32, 0.36))


func _build_content() -> void:
	# --- 推车 ----------------------------------------------------------
	cart = LISCart.new()
	cart.name = "ComboCart"
	add_child(cart)
	cart.global_position = Vector3(9.0, 0.60, 6.0)
	register_reset(cart)

	# --- 杠杆 ----------------------------------------------------------
	lever = LISLever.new()
	lever.name = "ComboLever"
	add_child(lever)
	lever.global_position = Vector3(-9.0, LISLever.PIVOT_HEIGHT, 6.0)
	register_reset(lever)

	# --- 电动门 --------------------------------------------------------
	door = LISMotorDoor.new()
	door.name = "ComboDoor"
	add_child(door)
	door.global_position = Vector3(0.0, 0.0, -8.0)
	door.set_request(true)
	register_reset(door)

	# --- 缆绳 ----------------------------------------------------------
	rope_crate = add_body("ComboRopeCrate", Vector3(-8.0, 0.51, -4.0),
		Vector3(1.0, 1.0, 1.0), 55.0, Color(0.70, 0.60, 0.36),
		{"display_name": "缆绳货箱 55 kg"})
	rope = LISRope.new()
	rope.name = "ComboRope"
	add_child(rope)
	await get_tree().physics_frame
	rope.build(10, 0.34, rope_crate.global_position + Vector3(0.55, 0.2, 0.0),
		Vector3.RIGHT, true, 0.0)
	await get_tree().physics_frame
	rope.anchor_first_to(rope_crate, rope_crate.global_position + Vector3(0.55, 0.2, 0.0))

	# --- 多个刚体 ------------------------------------------------------
	for i in range(8):
		add_body("Combo%d" % i, Vector3(-6.0 + float(i) * 1.4, 0.31, 9.0),
			Vector3(0.5, 0.5, 0.5), 8.0 + float(i) * 4.0,
			Color(0.42 + 0.05 * float(i), 0.62, 0.72),
			{"display_name": "组合箱%d（%.0f kg）" % [i, 8.0 + float(i) * 4.0]})
	# 杠杆用的重物
	add_body("ComboWeight", Vector3(-7.0, 0.46, 9.5), Vector3(0.6, 0.6, 0.6), 26.0,
		Color(0.74, 0.58, 0.32), {"display_name": "配重 26 kg"})


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_F1:
			_add_agent()
		KEY_F2:
			_remove_agent()


func _add_agent() -> void:
	if agents.size() >= 3:
		return
	var idx: int = agents.size() + 1
	var target: LISBody = rope_crate
	if target == null or not is_instance_valid(target):
		return
	var eye: Vector3 = target.global_position + Vector3(0.0, 1.3, 2.2 + float(idx) * 0.6)
	var root: Node3D = Node3D.new()
	root.name = "ComboAgent%d" % idx
	add_child(root)
	root.global_position = eye
	var cam: Camera3D = Camera3D.new()
	cam.current = false
	root.add_child(cam)
	cam.global_position = eye
	cam.look_at(target.global_position, Vector3.UP)
	var ad: LISFirstPersonAdapter = LISFirstPersonAdapter.new()
	ad.read_input = false
	ad.player_id = 20 + idx
	root.add_child(ad)
	ad.body = root
	ad.camera = cam
	agent_roots.append(root)
	agents.append(ad)
	ad.grab(target)


func _remove_agent() -> void:
	if agents.is_empty():
		return
	agents.pop_back()
	var root: Node3D = agent_roots.pop_back()
	if root != null and is_instance_valid(root):
		root.queue_free()


func _physics_process(_delta: float) -> void:
	# 异常巡检：NaN / 弹飞 / 穿地
	var speed_max: float = 0.0
	var anomalies: int = 0
	for n: Node in get_children():
		var rb: RigidBody3D = n as RigidBody3D
		if rb == null:
			continue
		if not LISPhysics.is_finite_vec3(rb.global_position) \
				or not LISPhysics.is_finite_vec3(rb.linear_velocity):
			anomalies += 1
			continue
		speed_max = maxf(speed_max, rb.linear_velocity.length())
		if rb.linear_velocity.length() > 30.0 or rb.global_position.y < -2.0:
			anomalies += 1
	if anomalies > 0:
		_anomaly_frames += 1
	_max_speed = maxf(_max_speed, speed_max)

	var out: PackedStringArray = PackedStringArray()
	out.append("刚体最大速度 %.2f m/s · 异常帧 %d" % [_max_speed, _anomaly_frames])
	if cart != null and is_instance_valid(cart):
		out.append("推车：触地 %d/4 · %.1f m/s" % [
			cart.grounded_wheel_count(), cart.telemetry_speed])
	if lever != null and is_instance_valid(lever):
		out.append("杠杆：%+.1f° · 载物 %.0f kg" % [lever.angle_deg(), lever.pan_load_kg])
	if door != null and is_instance_valid(door):
		out.append("门：%.1f°%s" % [door.angle_deg(), "（堵转）" if door.blocked else ""])
	if rope != null and is_instance_valid(rope):
		out.append("缆绳：%s · 伸长 %+.1f%% · 段间 %.4f m" % [
			"绷紧" if rope.is_taut() else "松弛",
			rope.stretch_ratio() * 100.0, rope.max_joint_gap()])
	out.append("协力代理：%d 名" % agents.size())
	if hud != null and is_instance_valid(hud):
		hud.extra_lines = out


func reset_stage() -> void:
	if rope != null and is_instance_valid(rope):
		rope.reset_rope()
	if cart != null and is_instance_valid(cart):
		cart.reset_pose(Vector3(9.0, 0.60, 6.0), 0.0)
	if lever != null and is_instance_valid(lever):
		lever.reset_lever()
	if door != null and is_instance_valid(door):
		door.reset_door()
		door.rearm(false)
	_anomaly_frames = 0
	_max_speed = 0.0
	super()
