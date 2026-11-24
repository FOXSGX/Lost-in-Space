extends Node3D

# -----------------------------------------------------------------------------
# MECHANICS-003A · 晶体门（03 · 晶体矿区入口）停靠夹钳
#
# 第三幕现有的剧情点是“矿车抵达晶体矿区入口”。改造前这一步是纯自动的：
# cart.arrived 一置位，章节就直接进入 done，再由定时器交接第四幕。
#
# 现在这一步必须由一台真实机械完成：
#
#   1. 玩家把矿车停在晶体门（002B 的调速器停车，位置由 cart.distance 决定）；
#   2. 玩家下到 106 m 站台，站到闸臂拉手旁、面向闸臂，按住 E 把闸臂从竖起
#      拉到横压在车体侧面（E 是“拉”，不是“完成”）；
#   3. 闸臂压到闭合止挡时，棘爪自动落进扇形齿槽（真实棘轮），闸臂被机械保持；
#   4. 只有“车在门区 + 车已停稳 + 闸臂端垫块真的贴住车侧 + 棘爪落位”同时成立，
#      03 停靠才算成立，章节才进入 done，才允许交接第四幕；
#   5. 再按一次 E 抬起棘爪：闸臂被配重抬回竖起位，停靠解除（可重试）。
#
# ---------------------------------------------------------------------------
# 模型边界（必须如实说明）：
#   矿车本体是沿轨道走的 AnimatableBody3D（002B 的受约束动力学），它对夹钳
#   没有反作用力。夹钳自己是一个真实的 1 自由度刚体折算模型：
#
#     I · d²θ/dt² = τ_pull − τ_counterweight − τ_damp − τ_stop
#
#   τ_pull 由玩家按住 E 产生（力来自输入，有上限），
#   τ_counterweight = K_OPEN · sin(θ) 是配重把闸臂抬回去的真实力矩，
#   τ_stop 是开/闭两个机械止挡，棘爪落位后 θ 被齿槽锁死。
#   闸臂对车体的“压住”用真实几何判定（臂端垫块与车体侧面的距离），
#   不是读一个 flag。车与夹钳之间没有 Jolt 力耦合，这点在报告里单列。
# -----------------------------------------------------------------------------

const INERTIA: float = 130.0        # 闸臂 + 配重绕铰轴的转动惯量（kg·m²）
const K_OPEN: float = 330.0         # 配重重力恢复力矩系数（N·m）
const PULL_TORQUE: float = 430.0    # 玩家拉住拉手的最大力矩（N·m）
const DAMP: float = 95.0            # 铰轴阻尼（N·m per rad/s）
const OPEN_ANGLE: float = 0.0       # 竖起（开放）
const CLOSED_ANGLE: float = 1.50    # 横压（闭合，约 86°）
const CAPTURE: float = 0.12         # 棘爪落位窗口（rad，约 6.9°）
const ARM_LEN: float = 1.55
const PIVOT_AT: Vector3 = Vector3(1.00, 1.60, -0.72)   # 站台局部坐标
const REACH: float = 2.0
const DOCK_S: float = 106.0
const DOCK_ZONE: float = 0.35

var stage: Node3D
var cart: AnimatableBody3D
var player: Node3D
var angle: float = OPEN_ANGLE
var omega: float = 0.0
var latched: bool = false
var pawl_progress: float = 0.0
var pulling: bool = false
var pull_torque: float = 0.0
var gravity_torque: float = 0.0
var blocked: bool = false
var last_refusal: String = ""

var _arm: Node3D
var _pawl: Node3D
var _beacon: MeshInstance3D
var _beacon_mat: StandardMaterial3D


func _ready() -> void:
	_build()


func _build() -> void:
	var env: Script = preload("res://act23/scripts/cart_environment.gd")
	var steel: StandardMaterial3D = env.material(Color("7c878a"), 0.10)
	var dark: StandardMaterial3D = env.material(Color("3d4549"), 0.10)
	var hazard: StandardMaterial3D = env.material(Color("c98a3f"), 0.05)
	var pad: StandardMaterial3D = env.material(Color("3f6f78"), 0.05)
	_beacon_mat = env.material(Color("ff4a36"), 0.0, 1.8)

	# 站台立柱与铰座
	env.box(self, Vector3(0.22, 1.60, 0.22), dark, Vector3(PIVOT_AT.x, 0.42 + 0.80, PIVOT_AT.z))
	env.box(self, Vector3(0.46, 0.10, 0.30), hazard, Vector3(PIVOT_AT.x, 2.02, PIVOT_AT.z))
	env.box(self, Vector3(0.30, 0.36, 0.30), steel, PIVOT_AT + Vector3(0.0, 0.06, 0.0))

	# 闸臂：绕 x 轴摆动，0 = 竖起，CLOSED = 横压
	_arm = Node3D.new()
	_arm.name = "DockArm"
	_arm.position = PIVOT_AT
	add_child(_arm)
	env.box(_arm, Vector3(0.12, ARM_LEN, 0.12), steel, Vector3(0, -ARM_LEN * 0.5, 0))
	env.box(_arm, Vector3(0.36, 0.10, 0.36), pad, Vector3(0, -ARM_LEN, 0))
	env.box(_arm, Vector3(0.30, 0.16, 0.30), dark, Vector3(0, -0.18, 0))
	# 配重（在铰点上方，靠它把臂抬回去）
	env.box(_arm, Vector3(0.28, 0.28, 0.28), dark, Vector3(0, 0.34, 0.0))
	# 拉手：站在站台上能够到的横杆
	env.box(self, Vector3(0.05, 0.05, 0.52), hazard, Vector3(PIVOT_AT.x - 0.42, PIVOT_AT.y - 0.35, PIVOT_AT.z))
	env.box(self, Vector3(0.05, 0.55, 0.05), steel, Vector3(PIVOT_AT.x - 0.42, PIVOT_AT.y - 0.62, PIVOT_AT.z))
	# 棘爪（抬起 = 松开，落下 = 卡进齿槽）
	_pawl = Node3D.new()
	_pawl.name = "Pawl"
	_pawl.position = PIVOT_AT + Vector3(0.20, 0.0, 0.0)
	add_child(_pawl)
	env.box(_pawl, Vector3(0.10, 0.26, 0.08), steel, Vector3(0, -0.13, 0))
	# 扇形齿槽板
	for k: int in range(5):
		env.box(self, Vector3(0.08, 0.05, 0.14), hazard,
			Vector3(PIVOT_AT.x + 0.20, PIVOT_AT.y - 0.30 - 0.12 * float(k), PIVOT_AT.z - 0.22))
	# 状态灯
	_beacon = env.box(self, Vector3(0.10, 0.10, 0.10), _beacon_mat,
		Vector3(PIVOT_AT.x + 0.20, 2.16, PIVOT_AT.z - 0.20))
	_apply_visuals()


func _physics_process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	pulling = _pull_input()
	pull_torque = PULL_TORQUE if pulling else 0.0
	gravity_torque = -K_OPEN * sin(angle)
	var net: float = pull_torque + gravity_torque - DAMP * omega
	if latched:
		omega = 0.0
		angle = CLOSED_ANGLE
	else:
		omega += net / INERTIA * delta
		omega = clampf(omega, -3.0, 3.0)
		angle += omega * delta
		if angle <= OPEN_ANGLE:
			angle = OPEN_ANGLE
			if omega < 0.0:
				omega = 0.0
		if angle >= CLOSED_ANGLE:
			angle = CLOSED_ANGLE
			if omega > 0.0:
				omega = 0.0
			# 到闭合止挡：只有真的压住车、而且是玩家拉过来的，棘爪才落下
			if pulling and _cart_in_zone() and pressing_cart():
				latched = true
			blocked = not pressing_cart()
	pawl_progress = move_toward(pawl_progress, 1.0 if latched else 0.0, delta * 6.0)
	_apply_visuals()
	_update_beacon()


# 玩家按住 E（repair）且站在拉手旁、面向闸臂
func _pull_input() -> bool:
	if latched or player == null:
		return false
	if player.global_position.distance_to(handle_world()) > REACH:
		return false
	var to_arm: Vector3 = arm_tip_world() - player.global_position
	to_arm.y = 0.0
	var forward: Vector3 = -player.global_basis.z
	forward.y = 0.0
	if to_arm.length() > 0.01 and forward.normalized().dot(to_arm.normalized()) < 0.10:
		return false
	return Input.is_action_pressed("repair")


func _apply_visuals() -> void:
	if _arm != null:
		_arm.rotation.x = -angle
	if _pawl != null:
		_pawl.rotation.x = lerpf(-0.55, 0.0, pawl_progress)


func _update_beacon() -> void:
	if _beacon == null or _beacon_mat == null:
		return
	_beacon_mat.emission_energy_multiplier = 2.6 if docked() else 0.0


# --- 判定 -------------------------------------------------------------------

func handle_world() -> Vector3:
	return to_global(Vector3(PIVOT_AT.x - 0.42, PIVOT_AT.y - 0.35, PIVOT_AT.z))


func arm_tip_world() -> Vector3:
	return _arm.to_global(Vector3(0, -ARM_LEN, 0))


func cart_in_zone() -> bool:
	return _cart_in_zone()


func _cart_in_zone() -> bool:
	if cart == null:
		return false
	return absf(float(cart.get("distance")) - DOCK_S) <= DOCK_ZONE and float(cart.get("speed")) < 0.05


# 闸臂端垫块是否真的压在车体侧面上（真实几何，不是 flag）
func pressing_cart() -> bool:
	if cart == null:
		return false
	var local: Vector3 = cart.to_local(arm_tip_world())
	# 车体近侧（z=0.87）的侧板，y 0.55..1.95
	return absf(local.z - 0.87) < 0.18 and local.y > 0.50 and local.y < 1.95 \
		and local.x > -3.2 and local.x < 3.0


func docked() -> bool:
	return latched and _cart_in_zone() and pressing_cart()


func state() -> Dictionary:
	return {
		"inertia": INERTIA,
		"pull_torque_max": PULL_TORQUE,
		"k_open": K_OPEN,
		"closed_deg": snappedf(rad_to_deg(CLOSED_ANGLE), 0.1),
		"angle_deg": snappedf(rad_to_deg(angle), 0.1),
		"omega": snappedf(omega, 0.001),
		"pressed": pressing_cart(),
		"cart_in_zone": _cart_in_zone(),
		"latched": latched,
		"pulling": pulling,
		"pull_torque": snappedf(pull_torque, 1.0),
		"gravity_torque": snappedf(gravity_torque, 1.0),
		"blocked": blocked,
		"docked": docked(),
	}


# --- 交互 -------------------------------------------------------------------

# E：按住 = 拉闸臂（由 tick 每帧读取按键）；已落棘爪时按一下 = 抬棘爪松开。
func operate() -> Dictionary:
	if latched:
		latched = false
		return {"ok": true, "action": "released", "reason": ""}
	if player != null and player.global_position.distance_to(handle_world()) > REACH:
		return {"ok": false, "action": "refused", "reason": "离停靠夹钳太远，走到站台拉手旁"}
	if absf(angle - CLOSED_ANGLE) <= CAPTURE:
		return {"ok": true, "action": "holding", "reason": ""}
	return {"ok": true, "action": "pulling", "reason": ""}


func release() -> void:
	latched = false


func reset() -> void:
	angle = OPEN_ANGLE
	omega = 0.0
	latched = false
	pawl_progress = 0.0
	pulling = false
	blocked = false
	last_refusal = ""
	_apply_visuals()

