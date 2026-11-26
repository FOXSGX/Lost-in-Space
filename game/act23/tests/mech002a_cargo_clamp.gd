extends Node
## MECHANICS-002A · 第二幕货舱固定座：真实机械锁爪专项
##
## 全部断言在正式第二幕切片 res://act23/moving_cart.tscn 内真实执行：
## 容器是 6 kg 刚体，锁爪是车体上的实体夹钳，任务状态由"锁爪真的压住容器 +
## 容器在固定座里 + 容器真的坐在座板上"推导出来。
##
## 关键量：jaw_x / pressing / stalled / secured / 容器局部位移 / 接触体。
## 失败返回非零退出码。剧情前置（上车、走到固定座）按任务书允许的方式初始化，已注明。

const FORCE_N := 40.0
const FORCE_FRAMES := 60

var stage: Node
var cart: AnimatableBody3D
var device: Node
var flow: Node
var player: CharacterBody3D
var spec: Dictionary = {}
var checks: int = 0
var failures: int = 0


func _ready() -> void:
	var ps: PackedScene = load("res://act23/moving_cart.tscn") as PackedScene
	stage = ps.instantiate()
	add_child(stage)
	await _w(150)
	cart = stage.get("cart") as AnimatableBody3D
	device = stage.get("device")
	flow = stage.get("flow")
	player = stage.get("player") as CharacterBody3D
	if cart == null or device == null or flow == null or player == null:
		_fail("M0", "第二幕切片没有加载出 cart/device/flow/player")
		return _report()
	spec = device.call("clamp_spec") as Dictionary

	await _m01_load()
	await _m02_story_intact()
	await _m03_hardware()
	await _m04_key_does_not_complete()
	await _m05_operation_moves_mechanism()
	await _m06_placement_is_physics()
	await _m07_ab_hold()
	await _m08_c_release()
	await _m09_insufficient_condition()
	await _m10_no_penetration()
	await _m11_recovery()
	await _m12_reset()
	await _m13_three_rounds()
	await _m14_story_continues()
	await _m15_player_regression()
	await _m16_official_entry()
	await _m17_both_cradles()
	_report()


# ---------------------------------------------------------------- 1 加载
func _m01_load() -> void:
	_check("M1 第二幕正式切片正常加载（场景树/脚本无解析错误）",
		stage.is_inside_tree() and cart.is_inside_tree() and device.is_inside_tree()
			and flow.is_inside_tree() and player.is_inside_tree(),
		"stage=%s cart=%s device=%s flow=%s player=%s" % [
			stage.name, cart.name, device.name, flow.name, player.name])


# ---------------------------------------------------------------- 2 剧情结构
func _m02_story_intact() -> void:
	var objective: String = str(flow.get("objective_text"))
	var cargo_slots: Array = device.get("slots") as Array
	var first_objective: String = str(flow.call("_objective_for", "ride"))
	_check("M2 原有剧情结构保留（阶段机起始 board、目标文案、两个固定座、ride 段仍提示处理松散货物）",
		str(flow.get("phase")) == "board" and objective.find("发车") >= 0
			and cargo_slots.size() == 2 and int(device.call("locked_count")) == 0
			and first_objective.find("货物") >= 0,
		"phase=%s objective=%s ride目标=%s slots=%d" % [
			str(flow.get("phase")), objective, first_objective, cargo_slots.size()])


# ---------------------------------------------------------------- 3 硬件
func _m03_hardware() -> void:
	var cargo: Array = device.get("cargo") as Array
	var body: RigidBody3D = cargo[0] as RigidBody3D
	var cradles: Array = device.get("slot_cradle") as Array
	var plate_ok := false
	var rail_ok := 0
	var jaw_ok := 0
	if cradles.size() == 2:
		var h: Dictionary = cradles[0]
		var plate: Node = h.get("plate") as Node
		plate_ok = plate is StaticBody3D and (plate as StaticBody3D).collision_layer == 2
		for r: Node in (h.get("rails") as Array):
			if r is StaticBody3D and (r as StaticBody3D).collision_layer == 2:
				rail_ok += 1
		for j: Dictionary in (h.get("jaws") as Array):
			var jb: Node = j.get("body") as Node
			var pivot: Node3D = j.get("pivot") as Node3D
			if jb is StaticBody3D and absf(pivot.position.x) > 0.4:
				jaw_ok += 1
	_check("M3 任务物体与机械正确生成（2 个 6 kg 容器 + 每个固定座 1 座板/2 边轨/2 锁爪实体）",
		cargo.size() == 2 and body.mass >= 5.0 and body.collision_layer == 8
			and body.contact_monitor and plate_ok and rail_ok == 2 and jaw_ok == 2,
		"容器 mass=%.0f layer=%d；座板=%s 边轨=%d 锁爪=%d" % [
			body.mass, body.collision_layer, str(plate_ok), rail_ok, jaw_ok])


# ---------------------------------------------------------------- 4 E 不直接完成
func _m04_key_does_not_complete() -> void:
	_stage_on_deck(0)
	await _w(10)
	var before: Dictionary = device.call("clamp_state")
	stage.call("request_action", "repair", 1)
	for i in range(160):
		await get_tree().physics_frame
	var after: Dictionary = device.call("clamp_state")
	var jaws_closed: bool = float((after["jaws"] as Array)[0]) <= float(spec["jaw_stop"]) + 0.004
	_check("M4 固定座里没有容器时按 E 不会完成任务（锁爪只合到硬止挡，secured 仍为 false）",
		(not bool((before["secured"] as Array)[0])) and jaws_closed
			and (not bool((after["secured"] as Array)[0])) and int(device.call("locked_count")) == 0,
		"锁爪 %.3f → %.3f，pressing=%s，secured=%s，locked=%d" % [
			float((before["jaws"] as Array)[0]), float((after["jaws"] as Array)[0]),
			str((after["pressing"] as Array)[0]), str((after["secured"] as Array)[0]),
			int(device.call("locked_count"))])
	device.call("open_clamp", 0)
	await _w(20)


# ---------------------------------------------------------------- 5 操作改变机械
func _m05_operation_moves_mechanism() -> void:
	await _place(0)
	var pivot: Node3D = ((device.get("slot_cradle") as Array)[0]["jaws"] as Array)[0]["pivot"] as Node3D
	var x0: float = pivot.position.x
	# 真实按键路径：Input -> moving_stage._physics_process -> request_action
	Input.action_press("repair")
	await _w(2)
	Input.action_release("repair")
	await _w(30)
	var x1: float = pivot.position.x
	await _w(90)
	var state: Dictionary = device.call("clamp_state")
	_check("M5 玩家按 E 真的驱动锁爪（按键路径 + 锁爪实体位置变化 + 棘轮电机有限行程）",
		absf(x1 - x0) > 0.05 and float((state["jaws"] as Array)[0]) <= float(spec["jaw_stop"]) + 0.020
			and bool((state["secured"] as Array)[0]),
		"锁爪 pivot.x %.3f → %.3f → %.3f；pressing=%s secured=%s" % [
			x0, x1, float((state["jaws"] as Array)[0]),
			str((state["pressing"] as Array)[0]), str((state["secured"] as Array)[0])])


# ---------------------------------------------------------------- 6 放置=物理
func _m06_placement_is_physics() -> void:
	device.call("reset_all")
	await _w(40)
	await _place(0)
	var cargo: Array = device.get("cargo") as Array
	var body: RigidBody3D = cargo[0] as RigidBody3D
	var local0: Vector3 = cart.to_local(body.global_position)
	var contacts: Array = body.get_colliding_bodies()
	var touching_cradle := false
	for c: Node in contacts:
		if str(c.name).begins_with("CradlePlate"):
			touching_cradle = true
	# 不是冻结、也不是每帧钉住：给一个外力，它必须真的动。
	for i in range(20):
		body.apply_central_force(Vector3(0, 0, 30.0))
		await get_tree().physics_frame
	var local1: Vector3 = cart.to_local(body.global_position)
	var slot0: Vector3 = (device.get("slots") as Array)[0]
	_check("M6 容器是被真实放下的（未冻结/未钉住，靠座板接触承托，可被外力推动）",
		(not body.freeze) and touching_cradle and local0.distance_to(slot0) < 0.10
			and local1.distance_to(local0) > 0.01,
		"freeze=%s 接触=%s 落点=%s 外力后=%s 位移=%.3f" % [
			str(body.freeze), str(contacts), str(local0.snapped(Vector3(0.001, 0.001, 0.001))),
			str(local1.snapped(Vector3(0.001, 0.001, 0.001))), local0.distance_to(local1)])
	device.call("reset_all")
	await _w(30)


# ---------------------------------------------------------------- 7 A/B
func _m07_ab_hold() -> void:
	var a := await _fore_aft_case(false, "A 未夹紧")
	var b := await _fore_aft_case(true, "B 已夹紧")
	_check("M7 同一纵向外力下：未夹紧会滑出固定座，夹紧后被锁爪挡住（A/B 对照）",
		float(b["dx"]) < 0.02 and float(a["dx"]) > 0.12 and bool(b["secured"]) and not bool(a["secured"]),
		"A dx=%.3f m（secured=%s） / B dx=%.4f m（secured=%s）" % [
			float(a["dx"]), str(a["secured"]), float(b["dx"]), str(b["secured"])])


# ---------------------------------------------------------------- 8 C 释放
func _m08_c_release() -> void:
	# 上一段结束时容器是夹紧的；真实松开需要先停车（按设计）
	cart.call("brake")
	await _w(60)
	_stage_on_deck(0)
	await _w(10)
	stage.call("request_action", "repair", 1)
	await _w(30)
	var opened: Dictionary = device.call("clamp_state")
	var c := await _fore_aft_case(false, "C 松开后", false)
	_check("M8 真实松开锁爪后容器重新可动（C 段与 A 段同量级）",
		float((opened["jaws"] as Array)[0]) >= float(spec["jaw_open"]) - 0.01
			and float(c["dx"]) > 0.08 and not bool(c["secured"]),
		"松开后锁爪=%.3f；C dx=%.3f m" % [float((opened["jaws"] as Array)[0]), float(c["dx"])])
	device.call("reset_all")
	await _w(30)


# ---------------------------------------------------------------- 9 条件不足
func _m09_insufficient_condition() -> void:
	device.call("reset_all")
	await _w(30)
	var cargo: Array = device.get("cargo") as Array
	var body: RigidBody3D = cargo[0] as RigidBody3D
	var slots: Array = device.get("slots") as Array
	var slot0: Vector3 = slots[0]
	# 容器停在固定座外侧 0.6 m（不在座里），锁爪照常合拢，但不得判定为已固定
	body.freeze = true
	body.global_position = cart.to_global(slot0 + Vector3(0.62, 0.05, 0.0))
	body.global_rotation = Vector3.ZERO
	body.reset_physics_interpolation()
	body.freeze = false
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.set("phase", "free")
	body.set("slot", -1)
	await _w(40)
	_stage_on_deck(0)
	await _w(6)
	stage.call("request_action", "repair", 1)
	for i in range(120):
		await get_tree().physics_frame
	var state: Dictionary = device.call("clamp_state")
	_check("M9 条件不足时任务不会完成（容器不在固定座里，锁爪合拢也不算固定）",
		not bool((state["secured"] as Array)[0]) and int(device.call("locked_count")) == 0
			and not bool(device.call("slot_secured", 0)),
		"锁爪=%.3f pressing=%s secured=%s locked=%d" % [
			float((state["jaws"] as Array)[0]), str((state["pressing"] as Array)[0]),
			str((state["secured"] as Array)[0]), int(device.call("locked_count"))])
	device.call("reset_all")
	await _w(30)


# ---------------------------------------------------------------- 10 不穿透
func _m10_no_penetration() -> void:
	device.call("reset_all")
	await _w(30)
	# 先正常放进固定座，再把它横向挪 0.10 m，然后合拢：
	# 锁爪必须停在容器表面之外（最多 2 mm 机械间隙）
	await _place(0)
	var cargo: Array = device.get("cargo") as Array
	var body: RigidBody3D = cargo[0] as RigidBody3D
	var slot0: Vector3 = (device.get("slots") as Array)[0]
	body.freeze = true
	body.global_position = cart.to_global(slot0 + Vector3(0.10, 0.0, 0.0))
	body.reset_physics_interpolation()
	body.freeze = false
	body.linear_velocity = Vector3.ZERO
	await _w(20)
	var worst: float = 0.0
	_stage_on_deck(0)
	await _w(6)
	stage.call("request_action", "repair", 1)
	for i in range(150):
		await get_tree().physics_frame
		var local: Vector3 = cart.to_local(body.global_position)
		var off_x: float = local.x - slot0.x
		var jaw_half: float = float(spec["jaw_half"])
		var jaw_c: float = float(((device.call("clamp_state") as Dictionary)["jaws"] as Array)[0])
		# 越入量 = 容器表面 − 锁爪内表面（正数才是真的穿进容器）
		var pen_plus: float = (off_x + float(spec["crate_r"])) - (jaw_c - jaw_half)
		var pen_minus: float = (float(spec["crate_r"]) - off_x) - (jaw_c - jaw_half)
		worst = maxf(worst, maxf(pen_plus, pen_minus))
	var state: Dictionary = device.call("clamp_state")
	var stopped_at: float = float((state["jaws"] as Array)[0])
	var blocked: bool = bool((state["pressing"] as Array)[0]) and stopped_at > float(spec["jaw_stop"]) + 0.004
	_check("M10 机械受阻时不会穿透（锁爪被容器挡住，内表面不会越入容器表面超过 2 mm）",
		worst <= float(spec["pen"]) + 0.003 and blocked,
		"最大越入=%.4f m（机械间隙 %.3f m）；锁爪停在 %.3f（硬止挡 %.3f，被挡=%s）" % [
			worst, float(spec["pen"]), float(stopped_at), float(spec["jaw_stop"]), str(blocked)])
	device.call("reset_all")
	await _w(30)


# ---------------------------------------------------------------- 11 误操作恢复
func _m11_recovery() -> void:
	var body: RigidBody3D = (device.get("cargo") as Array)[0] as RigidBody3D
	_stage_on_deck(0)
	await _w(6)
	# 误操作：把容器丢在固定座外侧，再按 E
	body.freeze = true
	body.global_position = cart.to_global((device.get("slots") as Array)[0] + Vector3(0.0, 0.05, -0.75))
	body.reset_physics_interpolation()
	body.freeze = false
	body.set("phase", "free")
	body.set("slot", -1)
	await _w(40)
	stage.call("request_action", "repair", 1)
	await _w(90)
	var bad: bool = not bool(device.call("slot_secured", 0))
	device.call("reset_all")
	await _w(30)
	await _place(0)
	_stage_on_deck(0)
	await _w(6)
	stage.call("request_action", "repair", 1)
	await _w(120)
	var good: bool = bool(device.call("slot_secured", 0))
	_check("M11 误操作后可以恢复（放错位置→不固定；重新摆放→正常固定）",
		bad and good, "误放时 secured=false=%s；重新摆放后 secured=true=%s" % [str(bad), str(good)])
	device.call("reset_all")
	await _w(30)


# ---------------------------------------------------------------- 12 复位
func _m12_reset() -> void:
	await _place(0)
	_stage_on_deck(0)
	await _w(6)
	stage.call("request_action", "repair", 1)
	await _w(120)
	var locked_before: int = int(device.call("locked_count"))
	device.call("reset_all")
	await _w(60)
	var state: Dictionary = device.call("clamp_state")
	var cargo: Array = device.get("cargo") as Array
	var starts: Array = device.get("starts") as Array
	var ok := true
	for i: int in range(cargo.size()):
		var b: RigidBody3D = cargo[i] as RigidBody3D
		var local: Vector3 = cart.to_local(b.global_position)
		if local.distance_to(starts[i] as Vector3) > 0.12 or str(b.get("phase")) != "free":
			ok = false
	_check("M12 复位后机械状态正确（锁爪张开、容器回到初始位、locked_count=0）",
		locked_before == 1 and ok and int(device.call("locked_count")) == 0
			and float((state["jaws"] as Array)[0]) >= float(spec["jaw_open"]) - 0.01,
		"复位前 locked=%d；复位后 locked=%d 锁爪=%.3f 容器相位=%s" % [
			locked_before, int(device.call("locked_count")),
			float((state["jaws"] as Array)[0]), str(_phases(cargo))])


# ---------------------------------------------------------------- 13 连续三轮
func _m13_three_rounds() -> void:
	var rounds: Array = []
	var ok := true
	for n: int in range(3):
		device.call("reset_all")
		await _w(40)
		await _place(0)
		_stage_on_deck(0)
		await _w(6)
		stage.call("request_action", "repair", 1)
		await _w(120)
		var secured: bool = bool(device.call("slot_secured", 0))
		rounds.append("#%d %s" % [n + 1, "ok" if secured else "FAIL"])
		ok = ok and secured
		if not secured:
			break
	_check("M13 所选任务能够连续完成（3 轮 放置→合拢→锁定）", ok, ", ".join(rounds))


# ---------------------------------------------------------------- 14 后续剧情
func _m14_story_continues() -> void:
	device.call("reset_all")
	await _w(40)
	await _place(0)
	_stage_on_deck(0)
	await _w(6)
	stage.call("request_action", "repair", 1)
	await _w(120)
	var secured: bool = bool(device.call("slot_secured", 0))
	# 站到控制器旁（原有剧情入口；0.25 m 内不需要朝向判定）
	player.global_position = cart.to_global(Vector3(2.48, 2.05, 1.20))
	player.velocity = Vector3.ZERO
	await _w(20)
	var anchor: Vector3 = cart.to_global((stage.get("brake_anchor") as Vector3))
	cap("M14 就位 | 玩家局部=%s 在甲板=%s 到控制器=%.2f 手柄=%s 载货=%d" % [
		str(cart.to_local(player.global_position).snapped(Vector3(0.01, 0.01, 0.01))),
		str(cart.call("contains_point", player.global_position, 0.35)),
		player.global_position.distance_to(anchor),
		str(player.get("grip_id")), int(player.get("carrying"))])
	var pressed: bool = bool(stage.call("request_action", "repair", 1))
	await _w(40)
	cap("M14 按键后 request=%s feedback=%s running=%s" % [
		str(pressed), str(stage.get("feedback")), str(cart.get("running"))])
	var running: bool = bool(cart.get("running"))
	var phase: String = str(flow.get("phase"))
	var distance0: float = float(cart.get("distance"))
	for i in range(180):
		await get_tree().physics_frame
	var moved: float = float(cart.get("distance")) - distance0
	var still: bool = bool(device.call("slot_secured", 0))
	cart.call("brake")
	await _w(60)
	_check("M14 任务完成后后续剧情正常（矿车按原有控制器发车、进入 ride 阶段、货物仍固定）",
		secured and running and phase == "ride" and moved > 1.0 and still,
		"secured=%s running=%s phase=%s 行驶 %.2f m，途中仍固定=%s" % [
			str(secured), str(running), phase, moved, str(still)])
	cart.call("reset_run")
	device.call("reset_all")
	await _w(40)


# ---------------------------------------------------------------- 15 玩家无回归
func _m15_player_regression() -> void:
	# 站到甲板中央的空位再走，避免被固定座挡住
	player.global_position = cart.to_global(Vector3(0.0, 2.05, 2.0))
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	await _w(20)
	var p0: Vector3 = player.global_position
	Input.action_press("move_up")
	await _w(40)
	Input.action_release("move_up")
	await _w(10)
	var p1: Vector3 = player.global_position
	var hud: Node = stage.get("hud")
	var moved: float = Vector2(p1.x - p0.x, p1.z - p0.z).length()
	_check("M15 玩家移动/基础交互无回归（输入仍驱动角色，HUD 仍在）",
		moved > 0.20 and hud != null and player.global_position.is_finite(),
		"位移=%.2f m；hud=%s" % [moved, str(hud != null)])


# ---------------------------------------------------------------- 16 正式入口
func _m16_official_entry() -> void:
	# 正式入口 = res://scenes/act23.tscn（Act01 交接后由 SessionHub 切入的那个包装场景）
	var entry_ps: PackedScene = load("res://scenes/act23.tscn") as PackedScene
	if entry_ps == null:
		_check("M16 第二幕正式入口 res://scenes/act23.tscn 可加载并构建出机械", false, "PackedScene 为空")
		return
	var entry: Node = entry_ps.instantiate()
	add_child(entry)
	await _w(150)
	var sliced: Node3D = null
	for child: Node in entry.get_children():
		if str(child.name) == "Act23Entry":
			for inner: Node in child.get_children():
				if str(inner.name) == "MovingCartSlice":
					sliced = inner as Node3D
	var ok := sliced != null and sliced.get("cart") != null and sliced.get("device") != null \
		and sliced.get("flow") != null
	var locked: int = -1
	if sliced != null and sliced.get("device") != null:
		locked = int((sliced.get("device") as Node).call("locked_count"))
	_check("M16 第二幕正式入口 res://scenes/act23.tscn 正常构建（包装场景 → 切片 → 货舱机械在线）",
		ok and locked == 0,
		"切片=%s cart=%s device=%s flow=%s locked=%d" % [
			str(sliced != null), str(sliced != null and sliced.get("cart") != null),
			str(sliced != null and sliced.get("device") != null),
			str(sliced != null and sliced.get("flow") != null), locked])
	entry.queue_free()
	await _w(10)


# ---------------------------------------------------------------- 17 双座
func _m17_both_cradles() -> void:
	device.call("reset_all")
	await _w(40)
	await _place(0)
	_stage_on_deck(0)
	await _w(6)
	stage.call("request_action", "repair", 1)
	await _w(120)
	var one: bool = bool(device.call("slot_secured", 0))
	# 第二件走同一条玩家通道：站到 2 号固定座旁 F 拿起最近的容器 → G 放到空座 → E 合拢。
	_stage_on_deck(1)
	await _w(10)
	stage.call("request_action", "pickup", 1)
	await _w(20)
	stage.call("request_action", "deposit", 1)
	var seated := false
	for i in range(150):
		await get_tree().physics_frame
		if str(((device.get("cargo") as Array)[1] as Node).get("phase")) in ["seated", "locked"]:
			seated = true
			break
	_stage_on_deck(1)
	await _w(6)
	stage.call("request_action", "repair", 1)
	await _w(140)
	var two: bool = bool(device.call("slot_secured", 1))
	var total: int = int(device.call("locked_count"))
	_check("M17 两个固定座都能各自锁定（第二件同样走 F/G/E，HUD 读同一函数 → 货物 2/2）",
		one and seated and two and total == 2,
		"1 号 secured=%s；2 号 seated=%s secured=%s；locked_count=%d" % [
			str(one), str(seated), str(two), total])
	device.call("reset_all")
	await _w(30)


# ---------------------------------------------------------------- 工具
func _fore_aft_case(clamp_it: bool, tag: String, reset_first := true) -> Dictionary:
	if reset_first:
		device.call("reset_all")
		await _w(40)
		await _place(0)
		if clamp_it:
			_stage_on_deck(0)
			await _w(6)
			stage.call("request_action", "repair", 1)
			await _w(120)
	var body: RigidBody3D = (device.get("cargo") as Array)[0] as RigidBody3D
	var x0: float = cart.to_local(body.global_position).x
	for i in range(FORCE_FRAMES):
		body.apply_central_force(Vector3(FORCE_N, 0.0, 0.0))
		await get_tree().physics_frame
	var x1: float = cart.to_local(body.global_position).x
	var out := {
		"dx": absf(x1 - x0),
		"secured": bool(device.call("slot_secured", 0)),
		"phase": str(body.get("phase")),
	}
	cap("%s | force=%.0fN x %d 帧 dx=%.4fm phase=%s secured=%s clamp=%s" % [
		tag, FORCE_N, FORCE_FRAMES, float(out["dx"]), str(out["phase"]),
		str(out["secured"]), str(device.call("clamp_state"))])
	return out


## 把容器搬到 1 号固定座并放下（走真实的 F 拿起 / G 放下通道）
func _place(index: int, offset := Vector3.ZERO) -> void:
	device.call("reset_all")
	await _w(30)
	_stage_on_deck(index)
	await _w(8)
	stage.call("request_action", "pickup", 1)
	await _w(20)
	if offset != Vector3.ZERO:
		var body: RigidBody3D = (device.get("cargo") as Array)[0] as RigidBody3D
		if str(body.get("phase")) == "held":
			# 手持时把站位偏一点，让容器落在座板偏置位置
			_stage_on_deck(index, offset)
			await _w(20)
	stage.call("request_action", "deposit", 1)
	var ok := false
	for i in range(150):
		await get_tree().physics_frame
		var body: RigidBody3D = (device.get("cargo") as Array)[0] as RigidBody3D
		if str(body.get("phase")) == "seated":
			ok = true
			break
	if not ok:
		cap("PLACE 警告：容器没有进入 seated（phase=%s）" % str(((device.get("cargo") as Array)[0] as Node).get("phase")))
	await _w(30)


func _stage_on_deck(slot_index: int, offset := Vector3.ZERO) -> void:
	var slots: Array = device.get("slots") as Array
	var at: Vector3 = cart.to_global((slots[slot_index] as Vector3) + offset)
	player.global_position = at + cart.global_basis.z * -1.15 + Vector3.UP * 0.35
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()


func _phases(cargo: Array) -> Array:
	var out: Array = []
	for b: Node in cargo:
		out.append(str(b.get("phase")))
	return out


func _w(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame


func cap(text: String) -> void:
	print("CAP " + text)


func _check(name: String, ok: bool, detail: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("PASS  " if ok else "FAIL  ") + name + "  |  " + detail)


func _fail(tag: String, msg: String) -> void:
	checks += 1
	failures += 1
	print("FAIL  " + tag + "  |  " + msg)


func _report() -> void:
	print("MECH002A_DONE checks=%d failures=%d" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)


