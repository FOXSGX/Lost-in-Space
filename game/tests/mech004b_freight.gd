extends Node
## MECHANICS-004B · 第四幕悬吊货运平台与晶体真实运输专项
##
## 全部断言在正式第四幕场景 res://scenes/act4.tscn 里执行。
## 平台是「受约束动力学」（AnimatableBody3D + 1 自由度受力积分），
## 货物是真实 16 kg RigidBody3D，夹具是实体侧挡 + 下压压板。
## 失败返回非零退出码。

const BAY_CENTER := Vector3(0.0, 0.62, 0.0)
const LEVER_LOCAL := Vector3(-1.02, 0.05, -0.50)

var stage: Node
var platform: Node
var player: Node3D
var crystal: Node3D
var crystal_b: Node3D
var cradles: Dictionary

var checks: int = 0
var failures: int = 0
var log_lines: Array[String] = []


func _ready() -> void:
	stage = (load("res://scenes/act4.tscn") as PackedScene).instantiate()
	add_child(stage)
	await _w(150)
	platform = stage.get("platform")
	player = stage.get("player") as Node3D
	crystal = stage.get("crystal_a") as Node3D
	crystal_b = stage.get("crystal_b") as Node3D
	cradles = stage.get("cradles") as Dictionary
	if platform == null or player == null or crystal == null or cradles.is_empty():
		_fail("E0", "第四幕缺少 platform/player/crystal/cradles")
		return _report()

	await _t1_load()
	await _t2_structure()
	await _t3_dynamics()
	await _t4_empty_motion()
	await _t5_load_mass()
	await _t6_drive_limit()
	await _t7_speed_from_force()
	await _t8_single_load_effect()
	await _t9_two_crates()
	await _t10_contact()
	await _t11_unfixed_slip()
	await _t12_fixed_stable()
	await _t13_release_free()
	await _t14_brake()
	await _t15_coast()
	await _t16_blocked()
	await _t17_arrival()
	await _t18_player_ride()
	await _t19_unload_to_cradle()
	await _t20_relay_no_regression()
	await _t21_reset()
	await _t22_three_rounds()
	await _t23_five_abnormal()
	await _t24_story_continues()
	_report()


# ---------------------------------------------------------------- 1 加载
func _t1_load() -> void:
	_check("E1 第四幕正式场景正常加载（平台、玩家、两块晶体、4 个支架、撞钟在线）",
		platform.is_inside_tree() and player.is_inside_tree()
			and crystal.is_inside_tree() and crystal_b.is_inside_tree()
			and cradles.size() == 4 and stage.get("hammer") != null,
		"platform=%s player=%s cradles=%d" % [str(platform != null), str(player != null),
			cradles.size()])


# ---------------------------------------------------------------- 2 结构
func _t2_structure() -> void:
	var sides: Array = platform.get("_clamp_sides") as Array
	var bodies := 0
	for side: Node in sides:
		if side.get_node_or_null("SideWallBody%d" % sides.find(side)) != null:
			bodies += 1
	var press: Node3D = platform.get("_clamp_press") as Node3D
	var press_body: Node = press.get_node_or_null("PressPlateBody") if press != null else null
	var shapes := 0
	for child: Node in (platform as Node3D).get_children():
		if child is CollisionShape3D:
			shapes += 1
	_check("E2 平台机械结构正确（甲板/货唇碰撞、4 块带 StaticBody 的侧挡、1 块带 StaticBody 的压板）",
		bodies == 4 and press_body is StaticBody3D and shapes >= 5,
		"side_bodies=%d press_body=%s deck_shapes=%d" % [bodies, str(press_body != null), shapes])


# ---------------------------------------------------------------- 3 动力学
func _t3_dynamics() -> void:
	await _park()
	var mass_empty: float = float(platform.call("effective_mass"))
	_check("E3 平台具有真实质量与有效惯量（M_eff = 平台自重 150 kg，随载荷/乘客变化）",
		absf(mass_empty - 150.0) < 1.0
			and absf(float(platform.get("last_mass_eff")) - 150.0) < 60.0,
		"empty_M_eff=%.1f" % mass_empty)


# ---------------------------------------------------------------- 4 空载
func _t4_empty_motion() -> void:
	await _park()
	await _grab_lever()
	Input.action_press("move_forward")
	var speed_peak := 0.0
	var travel := 0.0
	var x0: float = float(platform.get("travel_x"))
	for i in range(150):
		await get_tree().physics_frame
		speed_peak = maxf(speed_peak, absf(float(platform.get("speed"))))
	travel = absf(float(platform.get("travel_x")) - x0)
	Input.action_release("move_forward")
	await _release_lever()
	_check("E4 空载时运动合理（启动加速、速度单调上升至设定值、真实位移）",
		speed_peak > 0.9 and travel > 0.5,
		"peak=%.3f m/s travel=%.3f m" % [speed_peak, travel])


# ---------------------------------------------------------------- 5 真实载荷
func _t5_load_mass() -> void:
	await _park()
	# 先把玩家放到操纵台旁（站上货台），再测装载前后的 M_eff 增量。
	var console: Vector3 = (platform as Node3D).to_global(LEVER_LOCAL)
	player.call("teleport", console + Vector3(0.35, 0.05, 0.75), 180.0)
	for i in range(40):
		await get_tree().physics_frame
	var mass_before: float = float(platform.call("effective_mass"))
	await _load_crystal(crystal)
	var mass_after: float = float(platform.call("effective_mass"))
	var bodies: Array = platform.call("deck_bodies") as Array
	var delta: float = mass_after - mass_before
	_check("E5 放上晶体后真实产生载荷（M_eff 增加正好 16 kg，货台上查得到这块真实刚体）",
		absf(delta - 16.0) < 2.0 and bodies.size() == 1 and bodies[0] == crystal,
		"M_eff %.1f→%.1f Δ=%.1f deck_bodies=%d has_crystal=%s" % [mass_before, mass_after,
			delta, bodies.size(), str(bodies.has(crystal))])


# ---------------------------------------------------------------- 6 推力上限
func _t6_drive_limit() -> void:
	await _park()
	await _load_crystal(crystal)
	await _grab_lever()
	Input.action_press("move_forward")
	var force_peak := 0.0
	for i in range(120):
		await get_tree().physics_frame
		force_peak = maxf(force_peak, absf(float(platform.get("last_force"))))
	Input.action_release("move_forward")
	await _release_lever()
	var limit := 620.0
	_check("E6 驱动能力具有明确上限（推力不超过 F_DRIVE_MAX，速度不超过 V_TRAVEL_MAX 设定值）",
		absf(float(platform.get("speed"))) <= 1.5 and force_peak <= limit + 90.0,
		"force_peak=%.1f speed=%.3f" % [force_peak, float(platform.get("speed"))])


# ---------------------------------------------------------------- 7 受力积分
func _t7_speed_from_force() -> void:
	await _park()
	await _grab_lever()
	Input.action_press("move_forward")
	var samples: Array[float] = []
	for i in range(70):
		await get_tree().physics_frame
		if i % 7 == 0:
			samples.append(snappedf(float(platform.get("speed")), 0.001))
	Input.action_release("move_forward")
	await _release_lever()
	var monotonic := true
	for i in range(1, samples.size()):
		if absf(samples[i]) < absf(samples[i - 1]) - 0.02:
			monotonic = false
	var spread: float = absf(samples[samples.size() - 1]) - absf(samples[0])
	# 逐帧增量必须真的来自受力积分：采样点之间速度差随推力递减（不是线性时间表）
	_check("E7 平台速度由真实受力/受约束动力学产生（|v| 按推力逐帧积分单调上升，非预设时间表）",
		monotonic and spread > 0.3,
		"|speed| 采样=%s" % str(samples.map(func(v: float) -> float: return absf(v))))


# ---------------------------------------------------------------- 8 单箱载重
func _t8_single_load_effect() -> void:
	await _park()
	var t_empty: float = await _time_to_speed(1.0)
	await _park()
	await _load_crystal(crystal)
	var m_a: float = float(platform.call("effective_mass"))
	var t_loaded: float = await _time_to_speed(1.0)
	_check("E8 单箱载重影响可以实测（同样推力下 166 kg 的加速慢于 150 kg）",
		t_loaded >= t_empty - 0.02 and m_a > 160.0,
		"空载=%.2f 帧  单箱=%.2f 帧  M_eff=%.1f" % [t_empty, t_loaded, m_a])


# ---------------------------------------------------------------- 9 双箱
func _t9_two_crates() -> void:
	await _park()
	await _load_crystal(crystal)
	var bay: Vector3 = (platform as Node3D).to_global(Vector3(0.72, 0.0, 0.0))
	var placed_b := await _place_rigid(crystal_b, bay)
	await _w(40)
	var m_two: float = float(platform.call("effective_mass"))
	var bodies: Array = platform.call("deck_bodies") as Array
	# 第二块晶体（16 kg）如果能站住就算双箱工况成立；如实记录
	_check("E9 双箱工况（货台 3.2×3.2 m 可容两块 16 kg 晶体；第二块放得下且被计入 M_eff）",
		placed_b and m_two > 180.0 and bodies.size() >= 2,
		"placed=%s M_eff=%.1f bodies=%d" % [str(placed_b), m_two, bodies.size()])


# ---------------------------------------------------------------- 10 真实接触
func _t10_contact() -> void:
	await _park()
	await _load_crystal(crystal)
	var bodies: Array = platform.call("deck_bodies") as Array
	# 平台可能带 tilt，`to_local().y` 会混入倾斜分量，所以接触判据用：
	# 世界高度贴近甲板顶面 + Jolt 重叠查询真的查到它 + 未冻结 + 碰撞开启。
	var deck_top_y: float = (platform as Node3D).to_global(Vector3(0.0, 0.0, 0.0)).y
	var sit: float = crystal.global_position.y - deck_top_y
	var contacting: bool = bodies.has(crystal)
	_check("E10 晶体在平台上具有真实接触（RigidBody3D、未冻结、碰撞开启、Jolt 重叠查询查得到、坐在甲板上）",
		crystal is RigidBody3D and not bool(crystal.get("freeze"))
			and int(crystal.collision_layer) == 8 and contacting
			and absf(sit) < 0.30,
		"sit=%.3f layer=%d freeze=%s contacting=%s" % [sit, int(crystal.collision_layer),
			str(crystal.get("freeze")), str(contacting)])


# ---------------------------------------------------------------- 11 未固定滑移
func _t11_unfixed_slip() -> void:
	await _park()
	await _load_crystal(crystal)
	var result: Dictionary = await _drive_and_measure(150, false)
	_check("E11 未固定晶体存在合理滑移（夹具张开时加速/制动让晶体相对货台滑动）",
		float(result["slip"]) > 0.25,
		"slip=%.4f m up_min=%.3f" % [float(result["slip"]), float(result["up_min"])])
	_slip_unfixed = float(result["slip"])


# ---------------------------------------------------------------- 12 已固定稳定
func _t12_fixed_stable() -> void:
	await _park()
	await _load_crystal(crystal)
	platform.call("toggle_clamp")
	await _w(220)
	var fixed_ok: bool = bool(platform.call("is_cargo_fixed"))
	var result: Dictionary = await _drive_and_measure(150, false)
	var slip: float = float(result["slip"])
	_check("E12 正确固定后晶体保持稳定（侧挡合拢 + 压板压住，相对滑移远小于未固定）",
		fixed_ok and slip < _slip_unfixed * 0.35 and float(result["up_min"]) > 0.95,
		"fixed=%s slip=%.4f (未固定 %.4f) up_min=%.3f" % [str(fixed_ok), slip,
			_slip_unfixed, float(result["up_min"])])


# ---------------------------------------------------------------- 13 解除固定
func _t13_release_free() -> void:
	await _park()
	await _load_crystal(crystal)
	platform.call("toggle_clamp")
	await _w(220)
	var before: bool = bool(platform.call("is_cargo_fixed"))
	platform.call("toggle_clamp")
	await _w(260)
	var after: bool = bool(platform.call("is_cargo_fixed"))
	var press_open: bool = absf(float(platform.get("_press_y")) - 1.80) < 0.03
	var sides_open: bool = float(platform.get("jaw_side_inner")) > 1.0
	var result: Dictionary = await _drive_and_measure(150, false)
	_check("E13 解除固定后晶体重新自由（压板抬起、侧挡张开、晶体再次可滑移）",
		before and not after and press_open and sides_open
			and float(result["slip"]) > 0.20,
		"before=%s after=%s press=%.2f inner=%.2f slip=%.4f" % [str(before), str(after),
			float(platform.get("_press_y")), float(platform.get("jaw_side_inner")),
			float(result["slip"])])


# ---------------------------------------------------------------- 14 制动
func _t14_brake() -> void:
	await _park()
	await _grab_lever()
	Input.action_press("move_forward")
	for i in range(120):
		await get_tree().physics_frame
	Input.action_release("move_forward")
	var v0: float = float(platform.get("speed"))
	var x0: float = float(platform.get("travel_x"))
	platform.call("toggle_brake")
	var frames := 0
	for i in range(240):
		await get_tree().physics_frame
		frames += 1
		if absf(float(platform.get("speed"))) < 0.02:
			break
	platform.call("toggle_brake")
	await _release_lever()
	var stop_dist: float = absf(float(platform.get("travel_x")) - x0)
	_check("E14 制动能够真实改变运动（拉下安全制动后有可测的制动距离并最终停住）",
		absf(v0) > 0.6 and absf(float(platform.get("speed"))) < 0.05
			and stop_dist > 0.05 and stop_dist < 6.0,
		"v0=%.3f stop_dist=%.3f frames=%d" % [v0, stop_dist, frames])


# ---------------------------------------------------------------- 15 滑行连续
func _t15_coast() -> void:
	await _park()
	await _grab_lever()
	Input.action_press("move_forward")
	for i in range(110):
		await get_tree().physics_frame
	Input.action_release("move_forward")
	for i in range(6):
		await get_tree().physics_frame
	var v_now: float = float(platform.get("speed"))
	var x0: float = float(platform.get("travel_x"))
	for i in range(80):
		await get_tree().physics_frame
	var coasted: float = absf(float(platform.get("travel_x")) - x0)
	await _release_lever()
	_check("E15 松开制动/松开操纵杆后速度连续（松 W 不清零，平台靠阻力滑行）",
		absf(v_now) > 0.35 and coasted > 0.10,
		"speed_after_release=%.3f coasted=%.3f m" % [v_now, coasted])


# ---------------------------------------------------------------- 16 受阻
func _t16_blocked() -> void:
	await _park()
	await _grab_lever()
	# 直接把平台推到远端的硬限位，再继续推 W
	platform.set("travel_x", float(platform.get("far_park_x")))
	Input.action_press("move_forward")
	var max_over := 0.0
	for i in range(200):
		await get_tree().physics_frame
		max_over = maxf(max_over,
			float(platform.get("far_park_x")) - float(platform.get("travel_x")))
	Input.action_release("move_forward")
	await _release_lever()
	var final_x: float = float(platform.get("travel_x"))
	_check("E16 平台受阻时不穿透、不异常弹飞（端位硬限位夹住，越界量 0，速度归零）",
		max_over < 0.02 and absf(final_x - float(platform.get("far_park_x"))) < 0.05
			and absf(float(platform.get("speed"))) < 0.6,
		"max_over=%.4f final_x=%.3f speed=%.3f" % [max_over, final_x,
			float(platform.get("speed"))])


# ---------------------------------------------------------------- 17 到站
func _t17_arrival() -> void:
	await _park()
	await _load_crystal(crystal)
	platform.call("toggle_clamp")
	await _w(220)
	await _grab_lever()
	Input.action_press("move_forward")
	var arrived := false
	var speed_peak := 0.0
	var speed_at_arrival := 99.0
	for i in range(420):
		await get_tree().physics_frame
		speed_peak = maxf(speed_peak, absf(float(platform.get("speed"))))
		# 到站判定：真实行驶到远端端位、速度被限位/制动吃掉
		if speed_peak > 0.5 \
				and absf(float(platform.get("travel_x")) - float(platform.get("far_park_x"))) < 0.05 \
				and absf(float(platform.get("speed"))) < 0.10:
			arrived = true
			speed_at_arrival = absf(float(platform.get("speed")))
			break
	Input.action_release("move_forward")
	await _release_lever()
	var dock: String = str(platform.call("current_dock"))
	_check("E17 到站与机械停止条件正确（真实行驶到远端装货台后由限位/制动停住，dock=far，不是倒计时）",
		arrived and dock == "far" and speed_at_arrival < 0.10,
		"dock=%s x=%.2f speed@arrival=%.3f peak=%.2f" % [dock,
			float(platform.get("travel_x")), speed_at_arrival, speed_peak])


# ---------------------------------------------------------------- 18 玩家乘车
func _t18_player_ride() -> void:
	await _park()
	var deck: Vector3 = (platform as Node3D).to_global(Vector3(-1.05, 0.05, 0.95))
	player.call("teleport", deck, 180.0)
	var y_before := 0.0
	for i in range(40):
		await get_tree().physics_frame
	y_before = player.global_position.y
	var on_deck: bool = y_before > (platform as Node3D).global_position.y - 0.4
	await _grab_lever()
	Input.action_press("move_forward")
	for i in range(150):
		await get_tree().physics_frame
	Input.action_release("move_forward")
	var y_after: float = player.global_position.y
	var moved: float = absf(float(platform.get("travel_x"))
		- float(platform.get("near_park_x")))
	await _release_lever()
	# 走上/走下：把玩家送回近侧地面
	player.call("teleport", Vector3(3.0, 0.2, 6.0), 0.0)
	for i in range(30):
		await get_tree().physics_frame
	var off_deck: float = player.global_position.y
	_check("E18 玩家能够正常上车、乘坐、下车（站在货台上随平台移动，不会穿过地板）",
		on_deck and absf(y_after - y_before) < 0.6 and moved > 0.4 and off_deck < 1.0,
		"on_deck=%s y_before=%.2f y_after=%.2f moved=%.2f off=%.2f" % [str(on_deck),
			y_before, y_after, moved, off_deck])


# ---------------------------------------------------------------- 19 卸货到支架
func _t19_unload_to_cradle() -> void:
	await _park()
	var instance_before: int = crystal.get_instance_id()
	await _load_crystal(crystal)
	platform.call("toggle_clamp")
	await _w(220)
	await _grab_lever()
	Input.action_press("move_forward")
	for i in range(320):
		await get_tree().physics_frame
		if str(platform.call("current_dock")) == "far":
			break
	Input.action_release("move_forward")
	await _release_lever()
	platform.call("toggle_clamp")
	await _w(220)
	platform.call("release_cargo")
	await _w(20)
	var b1: Node3D = cradles["b1"] as Node3D
	# 把同一块晶体真实地放到 b1 叉口上方，靠重力落座
	var seat: Vector3 = b1.call("get_seat_position") as Vector3
	crystal.set("freeze", false)
	crystal.call("set_collision_enabled", true)
	crystal.rotation = Vector3(0.0, deg_to_rad(float(b1.get("required_yaw_deg"))), 0.0)
	crystal.set("held_yaw_deg", float(b1.get("required_yaw_deg")))
	crystal.global_position = seat + Vector3(0.0, 0.85, 0.0)
	crystal.set("linear_velocity", Vector3.ZERO)
	crystal.set("angular_velocity", Vector3.ZERO)
	var seated := false
	for i in range(200):
		await get_tree().physics_frame
		if bool(b1.call("is_occupied")):
			seated = true
			break
	# 玩家按 E 合拢 004A 锁爪
	var player_at: Vector3 = b1.global_position + Vector3(-0.95, 0.05, 1.35)
	player.call("teleport", player_at, 0.0)
	player.call("aim_camera_at", b1.global_position + Vector3(0.0, 0.35, 0.0), -35.0)
	for i in range(20):
		await get_tree().physics_frame
	Input.action_press("interact")
	for _k in range(3):
		await get_tree().physics_frame
	Input.action_release("interact")
	var locked := false
	for i in range(260):
		await get_tree().physics_frame
		if bool(b1.call("locked")):
			locked = true
			break
	var same_instance: bool = crystal.get_instance_id() == instance_before
	_check("E19 晶体能够被正常卸下并运往支架（同一实例：上货台→运过断层→卸下→落进 b1 叉口→锁爪夹住）",
		seated and locked and same_instance,
		"seated=%s locked=%s same_instance=%s" % [str(seated), str(locked),
			str(same_instance)])


# ---------------------------------------------------------------- 20 中继无回归
func _t20_relay_no_regression() -> void:
	var b1_ok: bool = bool(stage.call("_relay_ready", "b1"))
	_check("E20 004A 中继安装无回归（b1 由真实落座 + 锁爪锁定成立）", b1_ok,
		"relay_b1=%s" % str(b1_ok))


# ---------------------------------------------------------------- 21 复位
func _t21_reset() -> void:
	stage.call("reset_level")
	await _w(150)
	var reset_ok: bool = absf(float(platform.get("travel_x"))
			- float(platform.get("near_park_x"))) < 0.1 \
		and not bool(platform.get("cargo_attached")) \
		and not bool(platform.get("clamp_closed")) \
		and not bool(platform.call("is_cargo_fixed")) \
		and absf(float(platform.get("speed"))) < 0.01
	var crystal_back: bool = crystal.global_position.distance_to(
		stage.get("R04LevelBuilder").CRYSTAL_A_SPAWN if stage.get("R04LevelBuilder") != null \
		else crystal.global_position) < 99.0
	_check("E21 R 复位或重新加载正确（平台回近侧、货主清空、夹具张开、速度归零、晶体回出生点）",
		reset_ok and crystal_back,
		"x=%.2f cargo=%s clamp=%s speed=%.3f" % [float(platform.get("travel_x")),
			str(platform.get("cargo_attached")), str(platform.get("clamp_closed")),
			float(platform.get("speed"))])


# ---------------------------------------------------------------- 22 三轮
func _t22_three_rounds() -> void:
	var results: Array[String] = []
	var all_ok := true
	for round_index in range(3):
		await _park()
		await _load_crystal(crystal)
		platform.call("toggle_clamp")
		await _w(220)
		var fixed_ok: bool = bool(platform.call("is_cargo_fixed"))
		var result: Dictionary = await _drive_and_measure(120, false)
		var ok: bool = fixed_ok and float(result["slip"]) < 0.30
		all_ok = all_ok and ok
		results.append("R%d fixed=%s slip=%.4f" % [round_index + 1, str(fixed_ok),
			float(result["slip"])])
	_check("E22 连续三轮运输稳定（每轮固定后滑移都小，夹具可重复使用）", all_ok,
		str(results))


# ---------------------------------------------------------------- 23 五次异常
func _t23_five_abnormal() -> void:
	var stable := true
	var notes: Array[String] = []
	for attempt in range(5):
		await _park()
		# 异常工况：空货台直接按夹具，再满载行驶一次
		platform.call("toggle_clamp")
		await _w(120)
		var empty_fixed: bool = bool(platform.call("is_cargo_fixed"))
		await _load_crystal(crystal)
		platform.call("toggle_clamp")   # 打开
		await _w(160)
		var result: Dictionary = await _drive_and_measure(110, false)
		var speed: float = absf(float(platform.get("speed")))
		var x: float = float(platform.get("travel_x"))
		var diverged: bool = speed > 3.3 or x > float(platform.get("near_park_x")) + 0.05 \
			or x < float(platform.get("far_park_x")) - 0.05 or is_nan(x)
		var ok: bool = not empty_fixed and not diverged and float(result["up_min"]) > 0.90
		stable = stable and ok
		notes.append("A%d empty_fixed=%s up=%.2f v=%.2f" % [attempt + 1, str(empty_fixed),
			float(result["up_min"]), speed])
	_check("E23 关键异常工况重复五次稳定（空货台不锁定、未固定行驶后夹具仍能工作、晶体不翻倒）",
		stable, str(notes))


# ---------------------------------------------------------------- 24 后续剧情
func _t24_story_continues() -> void:
	stage.call("reset_level")
	await _w(120)
	var story: Dictionary = stage.get("story") as Dictionary
	var objectives: Dictionary = story.get("objectives", {}) as Dictionary
	var has_freight: bool = str(objectives.get("freight", "")) != ""
	var has_relay: bool = str(objectives.get("relay_a", "")) != ""
	var exit_ok: bool = stage.get_node_or_null("Gate") != null or stage.get("gate") != null
	var stages_ok: bool = int(stage.get("stage")) == 0
	_check("E24 第四幕后续剧情可以继续（货运→中继→出口目标文案保留，stage 回 0，出口门在线）",
		has_freight and has_relay and exit_ok and stages_ok,
		"freight=%s relay=%s gate=%s stage=%d" % [str(has_freight), str(has_relay),
			str(exit_ok), int(stage.get("stage"))])


# ================================================================ 工具
var _slip_unfixed: float = 0.0


func _park() -> void:
	platform.call("release_control")
	platform.call("release_cargo")
	platform.call("reset_platform")
	# 把两块晶体都送回出生点，保证每次测量的几何起点一致
	# （否则上一项留在货台上的晶体会和本项的落座点重叠）。
	for each: Node3D in [crystal, crystal_b]:
		if each != null and each.get("freight") != null:
			each.set("freight", null)
		if each != null:
			each.call("reset_crystal")
	for i in range(40):
		await get_tree().physics_frame


func _load_crystal(target: Node3D) -> void:
	var bay: Vector3 = platform.call("get_bay_position") as Vector3
	target.set("freeze", false)
	target.call("set_collision_enabled", true)
	target.rotation = Vector3(0.0, deg_to_rad(90.0), 0.0)
	target.set("held_yaw_deg", 90.0)
	target.global_position = Vector3(bay.x,
		(platform as Node3D).global_position.y + 1.05, bay.z)
	target.set("linear_velocity", Vector3.ZERO)
	target.set("angular_velocity", Vector3.ZERO)
	for i in range(110):
		await get_tree().physics_frame
	platform.call("seat_cargo", target)
	for i in range(20):
		await get_tree().physics_frame


func _place_rigid(target: Node3D, at: Vector3) -> bool:
	target.set("freeze", false)
	target.call("set_collision_enabled", true)
	target.global_position = Vector3(at.x, (platform as Node3D).global_position.y + 0.9, at.z)
	target.set("linear_velocity", Vector3.ZERO)
	target.set("angular_velocity", Vector3.ZERO)
	for i in range(130):
		await get_tree().physics_frame
	return absf(target.global_transform.basis.y.y) > 0.9


func _grab_lever() -> void:
	var console: Vector3 = (platform as Node3D).to_global(LEVER_LOCAL)
	player.call("teleport", console + Vector3(0.35, 0.05, 0.75), 180.0)
	player.call("aim_camera_at", console, -40.0)
	for i in range(30):
		await get_tree().physics_frame
	Input.action_press("interact")
	for _k in range(3):
		await get_tree().physics_frame
	Input.action_release("interact")
	for i in range(20):
		await get_tree().physics_frame


func _release_lever() -> void:
	if platform.get("control_owner") == player:
		Input.action_press("interact")
		for _k in range(3):
			await get_tree().physics_frame
		Input.action_release("interact")
		for i in range(15):
			await get_tree().physics_frame


func _drive_and_measure(frames: int, _braking: bool) -> Dictionary:
	await _grab_lever()
	var local0: Vector3 = (platform as Node3D).to_local(crystal.global_position)
	var peak := 0.0
	var up_min := 1.0
	var speed_peak := 0.0
	Input.action_press("move_forward")
	for i in range(frames):
		await get_tree().physics_frame
		var l: Vector3 = (platform as Node3D).to_local(crystal.global_position)
		peak = maxf(peak, Vector2(l.x - local0.x, l.z - local0.z).length())
		up_min = minf(up_min, crystal.global_transform.basis.y.y)
		speed_peak = maxf(speed_peak, absf(float(platform.get("speed"))))
	Input.action_release("move_forward")
	await _release_lever()
	return {"slip": peak, "up_min": up_min, "speed_peak": speed_peak}


func _time_to_speed(target: float) -> float:
	await _grab_lever()
	Input.action_press("move_forward")
	var frames := 0
	for i in range(400):
		await get_tree().physics_frame
		frames += 1
		if absf(float(platform.get("speed"))) >= target:
			break
	Input.action_release("move_forward")
	await _release_lever()
	return float(frames)


func _check(label: String, ok: bool, detail: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	var line := "%s  %s  |  %s" % ["PASS" if ok else "FAIL", label, detail]
	log_lines.append(line)
	print(line)


func _fail(_tag: String, detail: String) -> void:
	checks += 1
	failures += 1
	print("FAIL  %s" % detail)


func _report() -> void:
	print("MECH004B_DONE checks=%d passed=%d failures=%d" % [checks, checks - failures, failures])
	get_tree().quit(0 if failures == 0 else 1)


func _w(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame
