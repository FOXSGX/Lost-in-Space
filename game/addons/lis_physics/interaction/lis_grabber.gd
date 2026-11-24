class_name LISGrabber
extends Node3D
## LIS Physics SDK · 第一人称力驱动抓握器
##
## 每物理帧对被抓物体施加一个**受上限约束的弹簧-阻尼力**，施加点在
## 物体表面离相机最近的那一点上。因此：
##   * 物体越重，抓起来越慢、越下垂（力上限导致的稳态误差）；
##   * 超过力量上限的物体拖得动、举不起（真实手感，不无视质量）；
##   * 被拿着的物体仍然与墙、地面、其他物体真实碰撞；
##   * 松手后物体保留当时的线速度 / 角速度，惯性完全来自物理引擎。
##
## **明确不做**：每帧 global_position = 摄像机前方（传送式持有）。
## 这项被 GAMEPLAY-002A 否决过，SDK 不再提供。
##
## 来源：work/final-integration-001/project/scripts/physics/phys_grabber.gd
## 解耦改动：
##   * 不再依赖 PlayerController。相机、锚点、玩家身份全部由
##     LISFirstPersonAdapter 通过 setup() 注入；
##   * 抓握目标类型从 PhysProp 放宽到 RigidBody3D（用 LISGrabLedger 登记持有者），
##     因此 LISBody / PhysCart / 自定义刚体都能抓；
##   * 所有"人能力"常量改为运行时字段，可被适配器覆盖（不同星球可有不同玩家能力）；
##   * 姿态辅助明确标注为玩法辅助并保留上限与遥测。
##
## ⚠ 姿态辅助的能力边界（必须如实告知，详见 PHYSICS_LIMITATIONS.md）：
##   普通人类单手可施加的接触力矩约 150 N·m（1500 N × 0.10 m 掌垫）。
##   本默认姿态辅助上限 500 N·m ≈ 人体的 3.3 倍。
##   它是**游戏化抓握辅助**，不是人体力学模拟。

signal hold_changed(body: RigidBody3D)
signal grip_slipped(reason: String)
signal force_saturated(body: RigidBody3D, demand: float, cap: float)

# ---------------------------------------------------------------------------
# "人"的能力（可被适配器改写）
# ---------------------------------------------------------------------------

## 单手持续举升力上限（N）。成年人双手提举约 300–500 N；
## 这里取偏游戏化的 1500 N，使 12 kg 箱轻松、40 kg 吃力、220 kg 完全举不动。
@export var lift_force: float = 1500.0
## 贴地拖推力上限（N）。地面支撑了重量，人体主要是水平发力。
@export var drag_force: float = 950.0
## 单人可举起的质量上限（kg）。多人时按人数线性放大（团队上限）。
@export var max_lift_mass: float = 42.0
## 单手掌心力矩上限（N·m）—— **玩法辅助**，不是人体能力（见文件头）。
@export var palm_torque_max: float = 500.0
## 单手可施加的最大角加速度（rad/s²）。按真实转动惯量折算，
## 因此对轻物收紧、对重物放开（旧实现按质量线性放大，等于无限姿态控制权）。
@export var palm_alpha_max: float = 100.0
## 抓握弹簧刚度（1/s）。越大手越"硬"，也越容易抖。
@export var hold_stiffness: float = 15.0
## 跟随速度上限（m/s）。
@export var max_follow_speed: float = 7.0
## 硬脱手距离（m）。手与抓握点被拉开这么远就真的抓不住。
@export var break_distance: float = 3.2
## 打滑判据：手与物体的相对位移持续超过这个距离才算"抓不住"。
@export var slip_distance: float = 0.7
## 拖推模式允许更大的手-物分离（手臂伸展，稳态滞后本就更大）。
@export var slip_distance_drag: float = 1.40
## 打滑持续时间阈值（s）。
@export var slip_limit: float = 0.45
## 抛掷：目标出手速度（m/s）。这是"手臂能把东西甩多快"的上限。
##
## 旧实现写的是 `冲量 = 质量 × 1.9`，那是**按质量等比放大冲量**，
## 于是所有质量的 Δv 恒为 1.9 m/s：130 kg 机柜和 5 kg 木箱飞得一样快，
## 与"轻箱飞得远、重箱几乎挪不动"的说明自相矛盾。
##
## 真实的人手抛掷是**冲量有限**（手臂发力时间有限、能输出的冲量有限），
## 所以 Δv = J / m 随质量反比下降。这里按两条上限建模：
##   * 轻物：出手速度不超过 throw_speed（成年人力所能及的量级）；
##   * 重物：总冲量不超过 throw_max_impulse（手臂能给出的冲量上限）。
## 两者取小，于是 5 kg 木箱能以 ~4.5 m/s 出手、40 kg 货箱只有 ~1.5 m/s、
## 130 kg 机柜几乎挪不动 —— 质量差异因此可见。
@export var throw_speed: float = 4.5
## 抛掷冲量上限（N·s）。约等于成年人短促发力（~300 N × ~0.2 s）的量级。
@export var throw_max_impulse: float = 60.0
## 抛掷的向上分量（相对出手速度的比例）。
@export var throw_lift_ratio: float = 0.28

# ---------------------------------------------------------------------------
# 运行时状态
# ---------------------------------------------------------------------------

## 玩家唯一身份（多人与日志用）。1 = 主机 / 单人。
var player_id: int = 1
## 玩家身体（Node3D）。只用于姿态参考，不做位置传送。
var player: Node3D = null
## 第一人称相机。抓握目标点由它决定。
var camera: Camera3D = null
## 世界空间手部锚点（可选）。为空时用相机前方 hold_distance。
var hand_anchor: Node3D = null
## 本地权威（true）还是远程代理（false）。远程代理同样施真实力，但不由本地输入驱动。
var is_authority: bool = true

## 当前持有的物体。
var held: RigidBody3D = null
## 抓握点在物体局部坐标里的位置。
var hold_local: Vector3 = Vector3.ZERO
## 手到抓握点的距离（m）。
var hold_distance: float = 1.35
## "lift" = 举升， "drag" = 贴地拖推。
var mode: String = "lift"
## 本模式下的实际力上限（N）。
var grip_force: float = 1500.0
## 手动偏航（鼠标 / 按键旋转物体的部分）。
var manual_yaw: float = 0.0
var last_slip_reason: String = ""

# --- 遥测（HUD 与测试读，不参与受力计算）---------------------------------
var last_force: float = 0.0
var last_demand: float = 0.0
var last_clamp_distance: float = 0.0
var palm_torque: float = 0.0
var palm_cap: float = 0.0
var palm_cancel: float = 0.0
var palm_level: float = 0.0
var cancel_demand: float = 0.0
var last_cancel_ratio: float = 0.0
var palm_work: float = 0.0
var saturated_frames: int = 0
## 最近一次抛掷的冲量（N·s）与据此得到的目标出手速度（m/s）。
var last_throw_impulse: float = 0.0
var last_throw_speed: float = 0.0

## 抓住那一刻物体的"上方向"（世界坐标）。姿态辅助的基准是它而不是世界竖直：
## 玩家可以把箱子横过来再搬，手会保持那个姿态。
var grip_up: Vector3 = Vector3.UP

var _slip_time: float = 0.0
var _last_grip_world: Vector3 = Vector3.ZERO


## 由 LISFirstPersonAdapter 调用。player / camera 都可为 null（纯测试代理）。
func setup(p_player: Node3D, p_camera: Camera3D, p_player_id: int = 1) -> void:
	player = p_player
	camera = p_camera
	player_id = p_player_id


## 提供一个世界空间手部锚点。抓握目标点将优先取它的位置。
## 手部视觉模型跟随它即可获得"手贴在物体上"的表现，但真实受力
## 仍然来自弹簧力，不来自手的位置。
func set_hand_anchor(anchor: Node3D) -> void:
	hand_anchor = anchor


func set_capabilities(p_lift: float, p_drag: float, p_lift_mass: float, p_torque: float, p_alpha: float) -> void:
	lift_force = maxf(p_lift, 1.0)
	drag_force = maxf(p_drag, 1.0)
	max_lift_mass = maxf(p_lift_mass, 0.1)
	palm_torque_max = maxf(p_torque, 0.0)
	palm_alpha_max = maxf(p_alpha, 0.0)
	_refresh_mode()


# ---------------------------------------------------------------------------
# 抓握
# ---------------------------------------------------------------------------

## 尝试抓住一个刚体。返回 false 表示不满足条件（会写 last_slip_reason）。
func try_grab(body: RigidBody3D) -> bool:
	if body == null or not is_instance_valid(body):
		last_slip_reason = "invalid"
		return false
	if body.freeze:
		last_slip_reason = "frozen"
		return false
	if camera == null or not is_instance_valid(camera):
		last_slip_reason = "no_camera"
		return false
	if held != null and held != body:
		release(false)
	# 多持有者：同一件物体允许多人同时抓，每人一个真实抓握点。
	if not LISGrabLedger.is_held_by(body, self) and LISGrabLedger.count(body) >= LISGrabLedger.MAX_HOLDERS:
		last_slip_reason = "occupied"
		return false

	var grip_world: Vector3 = _grip_point_of(body, camera.global_position)
	hold_local = body.to_local(grip_world)
	var dist: float = camera.global_position.distance_to(grip_world)
	if not LISGrabLedger.add_holder(body, self, player_id):
		last_slip_reason = "occupied"
		return false
	held = body
	# 模式必须先定（举升还是拖推），因为持握距离的算法依赖它。
	_refresh_mode()
	# 持握距离取"抓握点在相机前向上的投影"（拖推）或直线距离（举升）。
	#
	# 拖推用投影：直线距离里包含相机与抓握点的竖直高差（眼高 1.62、
	# 货台面 0.68），投影到前向轴会过冲 —— 抓住瞬间目标点就超过物体，
	# 拖重推车时几十帧内必误判脱手。
	#
	# 举升保留直线距离：举起时物体就在眼前，直线距离才是"手到物"的真实距离。
	var fwd_axis: Vector3 = -camera.global_transform.basis.z
	if mode == "drag":
		hold_distance = clampf((grip_world - camera.global_position).dot(fwd_axis), 1.05, 2.30)
	else:
		hold_distance = clampf(dist, 1.05, 2.30)
	# 已抓着同一物体的其他人，模式也会随人数变化（团队上限 = 单人 × 人数），
	# 必须立刻通知他们，否则第二个人的那一帧里第一个人还是 drag。
	_notify_peers_refresh(body)
	body.sleeping = false
	grip_up = body.global_transform.basis.y.normalized()
	manual_yaw = 0.0
	_slip_time = 0.0
	_last_grip_world = grip_world
	hold_changed.emit(held)
	return true


## 举升 / 拖推模式由"当前有几个人在抓"决定，而不是由第一次抓握时的状态固定。
## 团队举升上限 = 单人上限 × 人数，所以第二个人上手时第一个人自动升为 lift。
func _refresh_mode() -> void:
	if held == null or not is_instance_valid(held):
		return
	var team: int = maxi(1, LISGrabLedger.count(held))
	var capacity: float = max_lift_mass * float(team)
	var liftable: bool = true
	var lm: LISBody = held as LISBody
	if lm != null:
		liftable = lm.liftable
	var is_rope_end: bool = held.has_method("grip_span_distance")
	# 缆绳自由端永远是"拖"模式：手抓的是绳子，货箱靠水平摩擦被拖走，
	# 手并没有把货箱举起来。
	if is_rope_end:
		mode = "drag"
		grip_force = drag_force
		return
	if liftable and held.mass <= capacity:
		mode = "lift"
		grip_force = lift_force
	else:
		mode = "drag"
		grip_force = drag_force


func _notify_peers_refresh(body: RigidBody3D) -> void:
	if body == null:
		return
	var lm: LISBody = body as LISBody
	if lm == null:
		return
	for h: Node3D in lm.holders:
		if h != self and is_instance_valid(h) and h.has_method("_refresh_mode"):
			h.call("_refresh_mode")


## 松手。thrown = true 时给一个按质量缩放的抛掷冲量。
func release(thrown: bool) -> void:
	if held == null or not is_instance_valid(held):
		held = null
		_clear_telemetry()
		hold_changed.emit(null)
		return
	var body: RigidBody3D = held
	held = null
	# 只注销自己这一只手：其他人继续持有（"一人松手，另一人继续抓住"）。
	LISGrabLedger.remove_holder(body, self)
	_notify_peers_refresh(body)
	if thrown:
		var cam: Camera3D = camera
		if cam != null and is_instance_valid(cam):
			var forward: Vector3 = -cam.global_transform.basis.z
			# 冲量有上限（不是按质量等比放大）：Δv = J/m 随质量反比下降，
			# 所以轻箱飞得远、重箱几乎挪不动。见 throw_speed 的说明。
			var j: float = minf(body.mass * throw_speed, throw_max_impulse)
			var impulse: Vector3 = forward * j + Vector3.UP * (j * throw_lift_ratio)
			body.apply_central_impulse(impulse)
			body.apply_torque_impulse(Vector3(0.0, j * 0.04, 0.0))
			last_throw_impulse = j
			last_throw_speed = j / maxf(body.mass, 0.001)
	var lm: LISBody = body as LISBody
	if lm != null:
		lm.released_by.emit(lm, thrown)
	_clear_telemetry()
	hold_changed.emit(null)


func _clear_telemetry() -> void:
	last_force = 0.0
	last_demand = 0.0
	last_clamp_distance = 0.0
	palm_torque = 0.0
	palm_cap = 0.0
	palm_cancel = 0.0
	palm_level = 0.0
	cancel_demand = 0.0
	last_cancel_ratio = 0.0
	_slip_time = 0.0


func is_holding() -> bool:
	return held != null and is_instance_valid(held)


func rotate_held(degrees: float) -> void:
	if not is_holding():
		return
	manual_yaw = fposmod(manual_yaw + deg_to_rad(degrees), TAU)


## 抓握世界坐标（当前帧的物理解算点）。
func grip_world() -> Vector3:
	if not is_holding():
		return Vector3.ZERO
	return held.to_global(hold_local)


## 世界空间的手部目标点。
func hand_target() -> Vector3:
	if hand_anchor != null and is_instance_valid(hand_anchor):
		return hand_anchor.global_position
	if camera == null or not is_instance_valid(camera):
		return Vector3.ZERO
	return camera.global_position + (-camera.global_transform.basis.z) * hold_distance


# ---------------------------------------------------------------------------
# 物理步进
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_holding():
		return
	var body: RigidBody3D = held
	var cam: Camera3D = camera
	if cam == null or not is_instance_valid(cam):
		release(false)
		return
	if body.is_queued_for_deletion():
		held = null
		_clear_telemetry()
		return
	if body.freeze:
		# 被镜像或被外部冻结：不能施力，安全松手。
		last_slip_reason = "frozen"
		release(false)
		return

	# 视角改变对抓握目标的影响：目标点始终是"相机前方 hold_distance"，
	# 因此低头 / 抬头 / 转身都会让手的目标点跟着动，但物体是被力拉过去的，
	# 不是被瞬移过去的。转得太快时力会饱和（真实手感：跟不上手）。
	var forward: Vector3 = -cam.global_transform.basis.z
	var target: Vector3 = hand_target()
	if hand_anchor == null:
		target = cam.global_position + forward * hold_distance
	var grip_pt: Vector3 = body.to_global(hold_local)
	var err: Vector3 = target - grip_pt
	last_clamp_distance = err.length()

	# 打滑 / 脱手判据用的误差必须是**真正在控制的分量**：
	# drag 模式刻意不控制竖直方向（重量交给地面），竖直误差常年在 1 m 以上。
	var slip_err: float = err.length()
	if mode == "drag":
		slip_err = Vector2(err.x, err.z).length()
	if slip_err > break_distance:
		last_slip_reason = "too_far"
		grip_slipped.emit("too_far")
		release(false)
		return

	# 举升 / 拖推模式随人数实时变化。
	_refresh_mode()

	var desired: Vector3 = err * hold_stiffness
	if desired.length() > max_follow_speed:
		desired = desired.normalized() * max_follow_speed
	if mode == "drag":
		# 贴地拖推：不提供升力，只沿水平方向拉。
		# 但允许向下压（提着重物往下按、抓住杠杆往下拉都是真实动作），
		# 只是举不起超过力量上限的重物。
		desired.y = minf(desired.y, 0.0)

	var radius: Vector3 = grip_pt - body.global_position
	var point_vel: Vector3 = body.linear_velocity + body.angular_velocity.cross(radius)
	var dv: Vector3 = desired - point_vel
	# 抓握力 = 质量 × 速度差（被 grip_force 截断）。
	# 用**物体自身的质量**：绳端只有 0.8 kg，若按载荷质量算会变成火箭。
	var force: Vector3 = dv * body.mass / maxf(delta, 0.0001)
	var demand: float = force.length()
	last_demand = demand
	if demand > grip_force:
		force = force.normalized() * grip_force
		saturated_frames += 1
		force_saturated.emit(body, demand, grip_force)
	else:
		saturated_frames = 0
	last_force = force.length()

	# 打滑判据用几何误差：手走了、物体没跟上，持续超限才真的抓不住。
	#
	# 多人持有时的容差必须放大：两个人（或四个人）抓同一件物体时，
	# 每人各自有一个"手的位置"，物体不可能同时贴合每个手 —— 只要两人朝向
	# 稍有差异，各自的手-物误差就会稳定落在 1~2 m 量级。
	# 用单人阈值会把"两人反向拉扯"判成打滑脱手（实测 27 帧就松手），
	# 而真实世界里两个人拉着同一根杆反向用力时是**抓着不放**的。
	var holders_live: int = maxi(1, LISGrabLedger.count(body))
	var slip_threshold: float = slip_distance_drag if mode == "drag" else slip_distance
	slip_threshold *= float(holders_live)
	if slip_err > slip_threshold:
		_slip_time += delta
	else:
		_slip_time = maxf(0.0, _slip_time - delta * 1.5)
	if _slip_time > slip_limit:
		last_slip_reason = "slip"
		grip_slipped.emit("slip")
		release(false)
		return

	body.apply_force(force, radius)
	# Godot 的 apply_force 不会唤醒休眠刚体：静置的货物一旦入睡，
	# 抓握力就完全没有效果（实测位移 0.0007 m）。抓握器必须自己唤醒它。
	body.sleeping = false
	# 上报"有人正向它施力"，供受阻判定使用（静止的箱子不会被误判为受阻）。
	var lis_body: LISBody = body as LISBody
	if lis_body != null:
		lis_body.note_constrained_force(demand, dv.normalized() if dv.length_squared() > 1.0e-6 else Vector3.ZERO)
	_last_grip_world = grip_pt

	# ---- 姿态辅助（游戏化，不是人体力学；边界见文件头）--------------------
	# 多人共同持有按人数均分：两人反向用力时自然抵消，不会互相较劲。
	var holders_now: int = maxi(1, LISGrabLedger.count(body))
	var share: float = 1.0 / float(holders_now)
	#
	# 偏航辅助（"让长箱跟着玩家的朝向转，好过门框"）**只在单人持有时生效**。
	#
	# 物理依据：两只手抓同一根杆时，杆的朝向由两人的相对位置与各自施力决定，
	# 不由任何一个人的肩膀朝向决定。若每只手都坚持"把物体拧到我身体的朝向"，
	# 两个人朝向不同就会互相压制，真实力偶会被辅助直接吃掉 ——
	# 实测：两人在横杆两端反向拉，偏航变化 0.00°，因为两只手各出 250 N·m
	# 的"归位力矩"把力偶抵消了。那不是物理，是控制器在抢。
	#
	# 所以多人时关掉偏航辅助，只保留物理力与（下面 lift 模式的）倾角约束。
	if player != null and is_instance_valid(player) and holders_now == 1:
		var target_yaw: float = player.rotation.y + manual_yaw
		var current_yaw: float = body.rotation.y
		var dyaw: float = wrapf(target_yaw - current_yaw, -PI, PI)
		var torque_y: float = clampf(dyaw * 7.0 - body.angular_velocity.y * 1.4, -16.0, 16.0)
		# 偏航也是掌心力矩，必须走同一个预算：按 yaw 轴的真实转动惯量定上限。
		var axis_y: Vector3 = Vector3.UP
		var yaw_budget: float = _palm_torque_cap(body, grip_force, axis_y)
		var want_y: float = clampf(torque_y * body.mass * share, -yaw_budget, yaw_budget)
		body.apply_torque(Vector3(0.0, want_y, 0.0))

	# 滚转 / 俯仰姿态约束：手掌搭在面的棱上时接触**不是**无摩擦球铰，
	# 手腕能抵抗翻转 —— 这是"抬箱子不会翻"的唯一物理来源。
	#
	# 只在 lift 时生效：贴地拖推时重量由地面承担，手既不需要也不能拧它，
	# 否则杠杆、推车、铰链门的真实转动都会被这个力矩压死。
	if mode == "lift":
		var up_now: Vector3 = body.global_transform.basis.y.normalized()
		var axis_err: Vector3 = up_now.cross(grip_up)
		var w: Vector3 = body.angular_velocity
		# 阻尼只作用在"会改变倾角"的那根轴上。
		# yaw（绕竖直轴）恰好不在其中，否则玩家主动旋转会被姿态约束对抗。
		var tilt_axis: Vector3 = axis_err.normalized()
		var w_tilt: float = w.dot(tilt_axis) if tilt_axis.length_squared() > 0.0001 else 0.0
		# 两类力矩各有自己的物理上限：
		#   配平力矩 t_cancel：掌心把**本手这一份**抓握力在掌区内重新分布。
		#     它的力臂是质心到抓握点（可能 0.9 m），远大于手掌尺寸，
		#     所以不能用掌区几何封顶；真正的上限是腕/前臂能抗住的力矩。
		#   纠偏力矩 t_lev：手腕主动发的力矩，还额外受角加速度上限约束。
		#     它不随质量线性放大，所以一只手无法对小物体施加任意大角加速度。
		var cancel_cap: float = palm_torque_max
		var level_cap: float = minf(palm_torque_max, palm_alpha_max * _inertia_about(body, tilt_axis))
		var t_grip_raw: Vector3 = radius.cross(force) * share
		cancel_demand = radius.cross(force).length() * share
		var t_cancel: Vector3 = LISPhysics.clamp_length(t_grip_raw, cancel_cap * share)
		var t_lev: Vector3 = LISPhysics.clamp_length(
			(axis_err * 20.0 - tilt_axis * w_tilt * 1.5) * body.mass * share,
			level_cap * share)
		body.apply_torque(t_lev - t_cancel)
		palm_torque = (t_lev - t_cancel).length()
		palm_cap = (cancel_cap + level_cap) * share
		palm_cancel = t_cancel.length()
		palm_level = t_lev.length()
		last_cancel_ratio = 1.0 if t_grip_raw.length() < 0.0001 \
			else clampf(t_cancel.length() / t_grip_raw.length(), 0.0, 1.0)
		palm_work += (t_lev - t_cancel).dot(body.angular_velocity) * delta
	else:
		palm_torque = 0.0
		palm_cap = 0.0
		palm_cancel = 0.0
		palm_level = 0.0

	# 轻微水平阻尼，避免长物体在手里像钟摆一样荡（只作用于角速度）。
	body.angular_velocity.y *= 0.985


## 抓握点：优先物体自己的表面几何（LISBody.grab_point_toward），
## 否则用碰撞体尺寸做同样的最近表面点计算。
func _grip_point_of(body: RigidBody3D, from: Vector3) -> Vector3:
	if body.has_method("grab_point_toward"):
		var v: Variant = body.call("grab_point_toward", from)
		if v is Vector3:
			return v as Vector3
	var size: Vector3 = LISContactProbe.shape_size(body)
	if size == Vector3.ZERO:
		return body.global_position
	var local_from: Vector3 = body.to_local(from)
	var half: Vector3 = size * 0.5
	var clamped: Vector3 = Vector3(
		clampf(local_from.x, -half.x, half.x),
		clampf(local_from.y, -half.y, half.y),
		clampf(local_from.z, -half.z, half.z))
	if clamped.distance_to(local_from) < 0.001:
		clamped = Vector3(half.x * signf(float(local_from.x != 0.0)), 0.0, 0.0)
	return body.to_global(clamped)


## 单只手的掌心力矩预算（N·m）。只用于遥测显示。
func _palm_torque_cap(body: RigidBody3D, force_mag: float, axis: Vector3) -> float:
	var by_contact: float = force_mag * 0.30
	var by_strength: float = palm_torque_max
	var by_alpha: float = palm_alpha_max * _inertia_about(body, axis)
	return minf(by_contact, minf(by_strength, by_alpha))


func _inertia_about(body: RigidBody3D, axis_world: Vector3) -> float:
	return LISPhysics.inertia_about(body, axis_world, LISContactProbe.shape_size(body))


# ---------------------------------------------------------------------------
# 清理
# ---------------------------------------------------------------------------

## 被抓的物体正在被删除：立刻松手。
##
## 由 `LISBody._notification(NOTIFICATION_PREDELETE)` 调用。
## 目的是在物体**仍然有效**的时刻就断开引用，而不是等抓握器事后用
## `is_instance_valid()` 去猜 —— 那种"事后兜底"在"删除发生在物理帧之间"
## 的时序里会留下一个短暂的悬空引用窗口，表现为间歇性访问冲突。
func on_body_predelete(body: Node3D) -> void:
	if body == null:
		return
	if held == body:
		held = null
		_clear_telemetry()
		hold_changed.emit(null)


## 玩家离开场景 / 节点被移除时，清理抓握引用（不留悬空持有者）。
func _exit_tree() -> void:
	if held != null and is_instance_valid(held):
		LISGrabLedger.remove_holder(held, self)
		_notify_peers_refresh(held)
	held = null


func describe() -> String:
	if not is_holding():
		return "空手"
	var name_txt: String = held.name
	var lm: LISBody = held as LISBody
	if lm != null:
		name_txt = lm.display_name
	return "%s · %s · %.0f kg · 上限 %.0f N" % [name_txt, mode, held.mass, grip_force]
