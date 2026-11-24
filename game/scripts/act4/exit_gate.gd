class_name ExitGate
extends Node3D
const Log := preload("res://scripts/core/log.gd")
## 第四幕出口升降门 —— MECHANICS-004C 真实物理升降机构
##
## ============================================================================
## 一、改造前（004A / 004B 已验收版本，已审计）
## ============================================================================
## 门体是 `StaticBody3D`。`open()` 的第一件事是 `_panel_shape.disabled = true`
## —— 开门瞬间关掉碰撞，门在物理世界里直接消失；然后用 Tween 把
## `_panel_root.position.y` 从 0 插值到 4.35，结束时 `is_open = true`。
##
## 也就是说：门没有质量、没有动力、没有重力、没有导向、没有止挡、没有保持。
## 它是一条曲线在动，而且一动就失去碰撞。这正是本轮必须消灭的东西。
##
## ============================================================================
## 二、现在：受约束刚体 + 有限推力电动执行器
## ============================================================================
## 运动方程（每一项都真实存在于运行中的场景里）：
##
##     M · dv/dt = F_motor − M·g − F_resistance + F_contact
##
##   M            门体真实质量 850 kg（RigidBody3D，惯量由 Jolt 按碰撞盒求解）
##   F_motor      电动执行器推力，硬性钳制在 ±F_MOTOR_MAX = 12500 N
##   M·g          Jolt 施加的真实重力（gravity_scale = 1，从不关闭）
##   F_resistance 导轨库仑阻力 1800 N + 粘滞阻力 500 N·s/m
##   F_contact    Jolt 的真实接触反作用（门被障碍挡住时就是它让门停下）
##
## 驱动力由「重力前馈 + 阻力前馈 + 速度反馈」闭环产生（电控伺服），但**唯一的
## 执行手段是 `apply_central_force()`**：从不写速度、从不写 Transform、从不冻结
## 刚体、从不关闭碰撞、从不设置休眠。
##
## 导向：`SliderJoint3D`。本引擎（Godot 4.7.2 + Jolt）实测滑动轴是关节局部 X；
## 关节绕 Z 旋转 90° 后局部 X → 世界 +Y。关节锁死另外 2 个平移自由度和全部 3 个
## 转动自由度，所以门只能竖直走。
##
## 止挡：
##   · 下止挡 = 关节 lower_limit 0 + 门槛钢梁（GateSill）真实碰撞
##   · 上止挡 = 关节 upper_limit JOINT_UPPER 4.75 + 门袋顶板真实碰撞
##
## 顶部保持（两级，都可验证）：
##   1. 机械承接梁：一根带真实碰撞的钢制横梁从走廊侧滑到门底下方，门**真的坐在
##      钢梁上**。此时电机按设计断电（motor_force = 0），门也不会掉。
##   2. 限力保持电机：承接梁收回 / 尚未伸出时，速度环以 F_motor ≤ 12500 N 托住门。
##      一旦 `powered = false`，门立刻按 M·g 自由下落 —— 这就是「失电会掉」的证据。
##
## 门袋：`level_builder.gd` 把原来的整块 `GateWallTop` 按门体净宽切成南北两段，
## 中间留出 4.60 m 宽、4.80 m 高的真实岩体空腔；本文件用带碰撞的钢制壳体把空腔
## 封闭成门袋（西面板 / 东面板 / 南北颊板 / 顶板），不是隐形洞，也不是穿墙。

signal player_entered
signal opened_gate
## 机械状态提示（堵转、门口有人等），供 HUD 使用。
signal gate_notice(text: String)

# ---- 机械几何（全部为门节点局部坐标；门节点在世界 (3.2, 0, -25)） --------
## 门洞与门袋所在的岩壁：世界 x 3.00 … 3.70（厚 0.70），即局部 −0.20 … 0.50。
## 走廊天花板从世界 x 3.50 起（底面 y 5.00），所以门板的最大 x 必须 < 3.48。
## 完全开启时门板底缘的高度。门洞上沿在 4.20 m，所以有 0.40 m 真实余量。
const H_OPEN := 4.60
## 门板碰撞盒（高 4.20 = 门洞净高；厚 0.36，居中在岩壁厚度内）。
const PANEL_SIZE := Vector3(0.36, 4.20, 4.08)
const PANEL_CENTER_Y := 2.10
## 门板横向中心：局部 0.00 → 世界 x 3.02 … 3.38，与两侧封板都有真实间隙。
const PANEL_X := 0.00
## 门板 z 半宽 2.04；门洞净宽 4.30（立柱内表面 z = ±2.15）。
const PANEL_HALF_Z := 2.04
## 门袋内腔（岩体空腔：局部 x −0.20 … 0.50，z −2.30 … 2.30，y 4.20 … 7.20）
const POCKET_HALF_Z := 2.26
## 门袋封板：西板内表面 −0.20（与岩壁西面齐平），东板内表面 +0.50。
const POCKET_WEST_PLATE_X := -0.26
const POCKET_EAST_PLATE_X := 0.56
const POCKET_BOTTOM_Y := 4.26
const POCKET_TOP_Y := 9.00
## 关节上止挡（主限位，也是行程上限）。门正常停在 H_OPEN，不会走到这里。
const JOINT_UPPER := 4.75
## 通行所需净空：门板底缘必须升到门洞上沿 4.20 m 以上，门洞才真的全开。
const REQUIRED_CLEARANCE := 4.20
## 净空达标后需要保持稳定的时间
const STABLE_SECONDS := 0.35

# ---- 动力学参数 -----------------------------------------------------------
## 门体真实质量。惯量由 Jolt 按 BoxShape 自动求解（见 get_diagnostics）。
const M_PANEL := 850.0
## 执行器额定推力上限（N）。自重 M·g = 8330 N，所以只有 1.5 倍余量：
## 这正是「电机真的在托着门」的量级。
const F_MOTOR_MAX := 12500.0
## 速度环增益（N per m/s 误差）
const K_SPEED := 12000.0
## 前馈用的**额定**质量。它不等于实际质量，所以实际负载变化会真实改变加速度
## （超载时甚至托不动），这是被专项测试验证的行为。
const M_NOMINAL := 850.0
const G := 9.8
const V_OPEN := 1.6
const V_CLOSE := 0.9
const F_RESIST_STATIC := 1800.0
const F_RESIST_VISCOUS := 500.0
## 静止判定（m/s）：低于它用静摩擦而不是库仑 + 粘滞
const V_REST := 0.02

# ---- 堵转保护 -------------------------------------------------------------
const STALL_SECONDS := 0.8
## 一个判定窗口内门必须真实前进至少这么多米，否则算堵转。
const STALL_PROGRESS := 0.08
## 堵转后的占空比：断电 0.55 s，再试 0.45 s，循环。平均推力因此降到额定 45%。
const STALL_OFF_SECONDS := 0.55
const STALL_ON_SECONDS := 0.45

# ---- 顶部机械承接梁 -------------------------------------------------------
const CATCH_SIZE := Vector3(0.60, 0.28, 4.00)
## 梁体 y 4.46 … 4.74。完全开启时门底在 4.75（关节上限），所以门只下沉 0.01 m
## 就真的坐在钢梁上 —— 承接是「落座」，不是「掉一段」。
const CATCH_Y := 4.60
const CATCH_X_EXTENDED := PANEL_X     # 0.00，正好在门底下
const CATCH_X_RETRACTED := 1.16       # 收进走廊侧的承接梁外壳
const CATCH_RATE := 2.4
## 门升到这个高度以上才允许伸梁（否则梁会顶到正在上升的门）
const CATCH_ARM_HEIGHT := H_OPEN - 0.30

# ---- 状态 -----------------------------------------------------------------
## 剧情条件已满足（机械驱动许可）。**授予许可本身不移动门。**
var unlocked: bool = false
var unlock_source: String = ""
## 电机获得驱动许可（= unlocked 且未被复位 / 关闭）
var drive_enabled: bool = false
## 失电开关：false 时电机推力恒为 0（用于验证顶部保持与自由下落）
var powered: bool = true
## 执行器额定推力（可下调以验证「欠功率托不动」，默认即 F_MOTOR_MAX）
var motor_force_limit: float = F_MOTOR_MAX

var _state: String = "closed"        # closed | opening | open | releasing | closing
var is_open: bool = false
var is_moving: bool = false
var _opened_emitted: bool = false

# ---- 实时读数（专项测试与报告直接读取） ------------------------------------
var height: float = 0.0              # 门底相对关闭位的实际高度（m）
var velocity: float = 0.0            # 沿导轨方向的速度（m/s）
var motor_force: float = 0.0         # 本物理帧实际施加的电机推力（N）
var resistance_force: float = 0.0    # 本物理帧实际施加的阻力（N）
var gravity_force: float = 0.0       # M·g 的实时值（N）
var joint_error: float = 0.0         # 关节横向偏差（m）
var joint_angular_error: float = 0.0 # 关节角偏差（度）
var contact_count: int = 0
var obstruction: bool = false        # 堵转（有推力但不前进）
var clearance: float = 0.0           # = height 的语义化别名
var exit_allowed: bool = false
var hold_mode: String = "none"       # none | catch | motor
var catch_engaged: bool = false
var motor_cut: bool = false          # 顶部机械承接后电机按设计断电
var _stable_clock: float = 0.0

# ---- 节点 -----------------------------------------------------------------
var _panel: RigidBody3D
var _joint: SliderJoint3D
var _anchor: StaticBody3D
var _catch: StaticBody3D
var _catch_x: float = CATCH_X_RETRACTED
var _catch_target_x: float = CATCH_X_RETRACTED
var _doorway: Area3D
var _trigger: Area3D
var _beacon: OmniLight3D
var _beacon_bulb: MeshInstance3D
var _status_material: StandardMaterial3D
var _audio: Node

var _axis: Vector3 = Vector3.UP
var _joint_origin: Vector3 = Vector3.ZERO
var _stall_clock: float = 0.0
var _stall_timer: float = 0.0
var _stall_on: bool = false
## 堵转判定以「真实行程进度」为准：一个 STALL_SECONDS 窗口内门没前进
## STALL_PROGRESS 就算堵转。瞬时速度会被接触抖动污染，进度不会。
var _progress_ref: float = 0.0
var _progress_clock: float = 0.0
## 方向切换宽限（秒）。门在上升/下降途中被改令反向时，前几百毫秒它仍会沿
## 原方向滑行——那不是堵转。没有这个宽限，堵转保护会把每一次正常反向都判成
## “推不动”，把电机按占空比断电，门于是继续往反方向掉（实测 0.75 s 掉 1.1 m）。
var _reverse_grace: float = 0.0
var _armed: bool = false


func build() -> void:
	name = "ExitGate"
	_audio = get_tree().get_first_node_in_group("audio_director")
	var steel: StandardMaterial3D = MaterialLibrary.metal(Color(0.30, 0.33, 0.36), 0.5, 0.8)
	var dark: StandardMaterial3D = MaterialLibrary.metal(Color(0.12, 0.13, 0.15), 0.6, 0.6)
	var warning: StandardMaterial3D = MaterialLibrary.painted(Color(0.86, 0.56, 0.08), 0.55)
	var rust: StandardMaterial3D = MaterialLibrary.metal(Color(0.36, 0.20, 0.11), 0.82, 0.3)
	var brass: StandardMaterial3D = MaterialLibrary.metal(Color(0.58, 0.42, 0.18), 0.4, 0.8)

	_build_frame(steel, dark, warning, rust, brass)
	_build_pocket(steel, dark, warning, rust)
	_build_panel(steel, dark, warning, rust, brass)
	_build_joint()
	_build_catch(steel, warning, rust)
	_build_sensors()
	_build_dressing(dark, warning, rust)

	_armed = true


# ---------------------------------------------------------------------------
# 门框：立柱、导向轨、上下止挡（全部带真实碰撞）
# ---------------------------------------------------------------------------
func _build_frame(steel: StandardMaterial3D, dark: StandardMaterial3D,
		warning: StandardMaterial3D, rust: StandardMaterial3D,
		brass: StandardMaterial3D) -> void:
	# 立柱内表面 z = ±2.15（门洞净宽 4.30），门体 z ±2.04 从中穿过。
	for side: int in range(2):
		var z_offset: float = -2.50 if side == 0 else 2.50
		BuildKit.static_box(self, "GatePillar%d" % side, Vector3(0.55, 5.20, 0.70),
			Vector3(PANEL_X, 2.60, z_offset), steel)
		BuildKit.box_visual(self, "PillarStripe%d" % side, Vector3(0.58, 0.35, 0.72),
			Vector3(PANEL_X, 1.00, z_offset), warning)
		BuildKit.cylinder_visual(self, "PillarBolt%d" % side, 0.09, 0.20,
			Vector3(PANEL_X + 0.32, 4.40, z_offset), rust, Vector3(0.0, 0.0, 90.0))
		# 导向轨：真实 StaticBody，贴在门袋西面板外表面（不侵入门袋内腔）。
		BuildKit.static_box(self, "GateGuideRail%d" % side, Vector3(0.10, 8.60, 0.16),
			Vector3(-0.36, 4.30, -2.22 if side == 0 else 2.22), dark)
		BuildKit.box_visual(self, "GuideRailWear%d" % side, Vector3(0.05, 8.40, 0.10),
			Vector3(-0.42, 4.30, -2.22 if side == 0 else 2.22), brass)

	# 下止挡：门槛钢梁（与地面齐平），门落到这里就是真的落到底。
	BuildKit.static_box(self, "GateSill", Vector3(0.90, 0.14, 4.60),
		Vector3(PANEL_X, -0.07, 0.0), dark)
	BuildKit.box_visual(self, "SillStripe", Vector3(0.92, 0.04, 4.20),
		Vector3(PANEL_X, 0.005, 0.0), warning)


# ---------------------------------------------------------------------------
# 门袋：把 level_builder 在岩体里切出的空腔用钢制壳体封闭
# ---------------------------------------------------------------------------
func _build_pocket(steel: StandardMaterial3D, dark: StandardMaterial3D,
		warning: StandardMaterial3D, rust: StandardMaterial3D) -> void:
	var depth: float = POCKET_TOP_Y - POCKET_BOTTOM_Y       # 4.74
	var mid_y: float = (POCKET_TOP_Y + POCKET_BOTTOM_Y) * 0.5
	var span_z: float = POCKET_HALF_Z * 2.0 + 0.08           # 4.60

	# 西面板（朝最终矿室的一侧）：门升起后就藏在这块板后面，不是穿墙。
	BuildKit.static_box(self, "PocketWestPlate", Vector3(0.10, depth, span_z),
		Vector3(POCKET_WEST_PLATE_X, mid_y, 0.0), steel)
	# 东面板（走廊侧）：下沿让出 0.60 m 承接梁滑槽（梁体 y 4.32…4.60）。
	BuildKit.static_box(self, "PocketEastPlate", Vector3(0.10, depth - 0.34, span_z),
		Vector3(POCKET_EAST_PLATE_X, POCKET_BOTTOM_Y + (depth - 0.34) * 0.5, 0.0), steel)
	# 南北颊板（贴着岩体空腔两侧）
	for side: int in range(2):
		var z: float = -(POCKET_HALF_Z + 0.04) if side == 0 else (POCKET_HALF_Z + 0.04)
		BuildKit.static_box(self, "PocketCheek%d" % side, Vector3(0.96, depth, 0.08),
			Vector3(0.15, mid_y, z), steel)
	# 顶板：既是门袋封顶，也是门的第二道真实上止挡。
	BuildKit.static_box(self, "PocketRoof", Vector3(0.96, 0.20, span_z),
		Vector3(0.15, POCKET_TOP_Y + 0.10, 0.0), steel)

	# 门袋外观：铆钉排、检修铭牌、警示带、内衬液压缸 —— 让它在第一人称里
	# 读作机械门袋，而不是一个洞。
	for index: int in range(9):
		var y: float = 4.55 + float(index) * 0.48
		for side: int in range(2):
			BuildKit.cylinder_visual(self, "PocketRivet%d_%d" % [side, index], 0.035, 0.05,
				Vector3(POCKET_WEST_PLATE_X - 0.06, y, -2.06 if side == 0 else 2.06),
				rust, Vector3(0.0, 0.0, 90.0))
	BuildKit.box_visual(self, "PocketHazardBand", Vector3(0.02, 0.26, 3.40),
		Vector3(POCKET_WEST_PLATE_X - 0.05, 4.44, 0.0), warning)
	BuildKit.box_visual(self, "PocketServicePlate", Vector3(0.02, 0.46, 1.10),
		Vector3(POCKET_WEST_PLATE_X - 0.05, 6.30, -1.10), dark)
	for index: int in range(2):
		BuildKit.cylinder_visual(self, "PocketRam%d" % index, 0.09, 3.60,
			Vector3(POCKET_WEST_PLATE_X - 0.04, 6.60, -1.90 if index == 0 else 1.90), dark)

	var sign_label: Label3D = Label3D.new()
	sign_label.name = "GateSign"
	sign_label.text = "矿区核心  →"
	var sign_font: SystemFont = SystemFont.new()
	sign_font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei",
		"Noto Sans CJK SC", "SimHei", "sans-serif"])
	sign_font.allow_system_fallback = true
	sign_label.font = sign_font
	sign_label.font_size = 64
	sign_label.pixel_size = 0.006
	sign_label.modulate = Color(1.0, 0.78, 0.36)
	sign_label.outline_size = 10
	sign_label.outline_modulate = Color(0.05, 0.04, 0.02, 0.9)
	sign_label.position = Vector3(POCKET_WEST_PLATE_X - 0.07, 4.62, 0.0)
	sign_label.rotation_degrees = Vector3(0.0, -90.0, 0.0)
	add_child(sign_label)


# ---------------------------------------------------------------------------
# 门体：真实 RigidBody3D
# ---------------------------------------------------------------------------
func _build_panel(steel: StandardMaterial3D, dark: StandardMaterial3D,
		warning: StandardMaterial3D, rust: StandardMaterial3D,
		brass: StandardMaterial3D) -> void:
	_panel = RigidBody3D.new()
	_panel.name = "GatePanel"
	_panel.mass = M_PANEL
	_panel.gravity_scale = 1.0
	# 门是机器：自己占 machine 层（4），仍与世界 / 玩家 / 货物真实碰撞。
	_panel.collision_layer = 4
	_panel.collision_mask = 1 | 2 | 4 | 8
	_panel.can_sleep = false            # 绝不靠休眠冻结门体
	_panel.contact_monitor = true
	_panel.max_contacts_reported = 8
	_panel.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	_panel.linear_damp = 0.0            # 阻力由脚本的 F_resistance 显式给出
	_panel.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	_panel.angular_damp = 4.0
	_panel.position = Vector3(PANEL_X, 0.005, 0.0)
	add_child(_panel)

	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.name = "PanelShape"
	var box: BoxShape3D = BoxShape3D.new()
	box.size = PANEL_SIZE
	shape.shape = box
	shape.position = Vector3(0.0, PANEL_CENTER_Y, 0.0)
	_panel.add_child(shape)

	BuildKit.box_visual(_panel, "Panel", Vector3(0.32, 4.20, 4.08),
		Vector3(0.0, 2.10, 0.0), steel)
	for index: int in range(3):
		BuildKit.box_visual(_panel, "PanelRib%d" % index, Vector3(0.36, 0.22, 4.04),
			Vector3(0.0, 0.60 + index * 1.35, 0.0), dark)
	BuildKit.box_visual(_panel, "PanelStripe", Vector3(0.37, 0.30, 4.00),
		Vector3(0.0, 2.05, 0.0), warning)
	BuildKit.cylinder_visual(_panel, "PanelWheel", 0.42, 0.12,
		Vector3(-0.22, 2.40, 0.0), rust, Vector3(0.0, 0.0, 90.0))
	BuildKit.cylinder_visual(_panel, "PanelAxle", 0.08, 0.30,
		Vector3(-0.26, 2.40, 0.0), dark, Vector3(0.0, 0.0, 90.0))

	# 第一人称细节：中缝、铆钉排、轮辐、警示斜纹、状态灯带。
	BuildKit.box_visual(_panel, "PanelSeam", Vector3(0.34, 4.15, 0.035),
		Vector3(0.0, 2.10, 0.0), dark)
	for side: int in range(2):
		var z: float = -0.55 if side == 0 else 0.55
		for index: int in range(7):
			BuildKit.cylinder_visual(_panel, "PanelRivet%d_%d" % [side, index], 0.028, 0.05,
				Vector3(-0.17, 0.35 + float(index) * 0.58, z), rust,
				Vector3(0.0, 0.0, 90.0))
	for index: int in range(2):
		BuildKit.box_visual(_panel, "WheelSpoke%d" % index, Vector3(0.10, 0.74, 0.05),
			Vector3(-0.28, 2.40, 0.0), brass, Vector3(0.0, 0.0, float(index) * 90.0))
	BuildKit.cylinder_visual(_panel, "WheelHub", 0.10, 0.18,
		Vector3(-0.30, 2.40, 0.0), brass, Vector3(0.0, 0.0, 90.0))
	for index: int in range(5):
		BuildKit.box_visual(_panel, "Hazard%d" % index, Vector3(0.018, 0.075, 0.34),
			Vector3(-0.17, 0.62, -1.48 + float(index) * 0.74), warning,
			Vector3(38.0, 0.0, 0.0))

	# 状态灯带：锁闭红、运动琥珀、开启青。
	# 必须 duplicate：MaterialLibrary.emissive() 返回的是按 "颜色+能量" 缓存共享的
	# 实例，_set_status() 每帧改写它，会把缓存条目永久染成当前状态色，之后任何
	# 再取同一个红的网格都会拿到已经变色的材质（跨机关串色）。
	_status_material = (MaterialLibrary.emissive(Color(0.85, 0.16, 0.10), 0.8) as StandardMaterial3D).duplicate()
	BuildKit.box_visual(_panel, "PanelStatus", Vector3(0.34, 0.075, 3.40),
		Vector3(0.0, 3.72, 0.0), _status_material)
	BuildKit.box_visual(_panel, "PanelStatusHood", Vector3(0.36, 0.06, 3.50),
		Vector3(0.0, 3.79, 0.0), dark)

	# 门底承接槽（纯视觉；承力靠真实碰撞）
	BuildKit.box_visual(_panel, "CatchNotchL", Vector3(0.40, 0.10, 0.42),
		Vector3(0.0, 0.05, -1.55), dark)
	BuildKit.box_visual(_panel, "CatchNotchR", Vector3(0.40, 0.10, 0.42),
		Vector3(0.0, 0.05, 1.55), dark)


# ---------------------------------------------------------------------------
# 关节：竖直滑动约束
# ---------------------------------------------------------------------------
func _build_joint() -> void:
	_anchor = StaticBody3D.new()
	_anchor.name = "GateAnchor"
	_anchor.collision_layer = 0
	_anchor.collision_mask = 0
	_anchor.position = _panel.position
	add_child(_anchor)
	var anchor_shape: CollisionShape3D = CollisionShape3D.new()
	var anchor_box: BoxShape3D = BoxShape3D.new()
	anchor_box.size = Vector3(0.10, 0.10, 0.10)
	anchor_shape.shape = anchor_box
	_anchor.add_child(anchor_shape)

	_joint = SliderJoint3D.new()
	_joint.name = "GateSlider"
	# 关节坐标系与刚体初始位姿重合，保证「距离 0」就是关闭位。
	_joint.position = _panel.position
	# 本引擎实测：SliderJoint3D 的滑动轴是关节局部 X。绕 Z 旋转 90° 后
	# 局部 X → 世界 +Y，重力因此沿滑动轴真实参与运动。
	_joint.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	_joint.set("linear_limit/upper_distance", JOINT_UPPER)
	_joint.set("linear_limit/lower_distance", 0.0)
	_joint.set("linear_limit/softness", 1.0)
	_joint.set("linear_limit/damping", 1.0)
	add_child(_joint)
	_joint.node_a = _joint.get_path_to(_anchor)
	_joint.node_b = _joint.get_path_to(_panel)

	_axis = Vector3.UP
	_joint_origin = _panel.global_position


# ---------------------------------------------------------------------------
# 顶部机械承接梁（真实 StaticBody，可滑动）
# ---------------------------------------------------------------------------
func _build_catch(steel: StandardMaterial3D, warning: StandardMaterial3D,
		rust: StandardMaterial3D) -> void:
	_catch = StaticBody3D.new()
	_catch.name = "GateCatchBeam"
	_catch.collision_layer = 4
	_catch.collision_mask = 0
	add_child(_catch)
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = CATCH_SIZE
	shape.shape = box
	_catch.add_child(shape)
	BuildKit.box_visual(_catch, "CatchMesh", CATCH_SIZE, Vector3.ZERO, steel)
	for index: int in range(2):
		BuildKit.box_visual(_catch, "CatchStripe%d" % index,
			Vector3(CATCH_SIZE.x + 0.02, 0.07, 0.50),
			Vector3(0.0, 0.0, -1.40 + float(index) * 2.80), warning)
		BuildKit.cylinder_visual(_catch, "CatchBolt%d" % index, 0.05, 0.06,
			Vector3(0.0, 0.16, -1.20 + float(index) * 2.40), rust)
	_catch_x = CATCH_X_RETRACTED
	_catch_target_x = CATCH_X_RETRACTED
	_catch.position = Vector3(_catch_x, CATCH_Y, 0.0)

	# 承接梁外壳（走廊侧，梁收回时藏在这里；纯视觉，不参与碰撞）
	BuildKit.box_visual(self, "CatchHousing", Vector3(1.30, 0.62, 4.30),
		Vector3(1.28, CATCH_Y, 0.0), steel)
	BuildKit.box_visual(self, "CatchHousingStripe", Vector3(1.32, 0.06, 4.32),
		Vector3(1.28, CATCH_Y - 0.28, 0.0), warning)
	for side: int in range(2):
		BuildKit.box_visual(self, "CatchTrack%d" % side, Vector3(1.70, 0.09, 0.14),
			Vector3(0.55, CATCH_Y - 0.18, -1.55 if side == 0 else 1.55), warning)
	# 承接梁导轨的真实支撑（贴在门袋颊板外侧，不侵入门袋内腔）
	for side: int in range(2):
		BuildKit.static_box(self, "CatchBracket%d" % side, Vector3(0.80, 0.24, 0.14),
			Vector3(0.90, CATCH_Y - 0.30, -2.40 if side == 0 else 2.40), steel)


# ---------------------------------------------------------------------------
# 传感器：出口触发 + 门口占用（安全）
# ---------------------------------------------------------------------------
func _build_sensors() -> void:
	_trigger = Area3D.new()
	_trigger.name = "ExitTrigger"
	_trigger.collision_layer = 32
	_trigger.collision_mask = 2
	_trigger.position = Vector3(3.0, 1.8, 0.0)
	var trigger_shape: CollisionShape3D = CollisionShape3D.new()
	var trigger_box: BoxShape3D = BoxShape3D.new()
	trigger_box.size = Vector3(4.0, 3.6, 4.2)
	trigger_shape.shape = trigger_box
	_trigger.add_child(trigger_shape)
	add_child(_trigger)
	_trigger.body_entered.connect(_on_body_entered)

	# 门口占用区：门下方 3.2 m 高，覆盖门板厚度并向前后延伸。
	# 掩码同时包含玩家(2)与可搬运晶体(8)：晶体被门板夹住时同样会被弹飞。
	_doorway = Area3D.new()
	_doorway.name = "DoorwaySensor"
	_doorway.collision_layer = 32
	_doorway.collision_mask = 2 | 8
	_doorway.position = Vector3(PANEL_X, 1.60, 0.0)
	var door_shape: CollisionShape3D = CollisionShape3D.new()
	var door_box: BoxShape3D = BoxShape3D.new()
	door_box.size = Vector3(1.60, 3.20, 4.20)
	door_shape.shape = door_box
	_doorway.add_child(door_shape)
	add_child(_doorway)


func _build_dressing(dark: StandardMaterial3D, warning: StandardMaterial3D,
		rust: StandardMaterial3D) -> void:
	for side: int in range(2):
		var z: float = -2.32 if side == 0 else 2.32
		BuildKit.cylinder_visual(self, "RamBody%d" % side, 0.13, 2.10,
			Vector3(-0.62, 3.40, z), dark, Vector3(14.0, 0.0, 0.0))
		BuildKit.cylinder_visual(self, "RamPin%d" % side, 0.09, 1.90,
			Vector3(-0.62, 4.60, z), rust, Vector3(0.0, 0.0, 90.0))

	BuildKit.cylinder_visual(self, "BeaconPole", 0.07, 1.10, Vector3(-0.60, 9.55, -1.80), dark)
	_beacon_bulb = BuildKit.sphere_visual(self, "BeaconBulb", 0.20,
		Vector3(-0.60, 10.18, -1.80), MaterialLibrary.emissive(Color(0.16, 0.30, 0.32), 0.3))
	_beacon = BuildKit.omni_light(self, "BeaconLight", Vector3(-0.60, 10.10, -1.80),
		Color(0.35, 0.92, 1.0), 0.0, 5.5, false)
	BuildKit.omni_light(self, "GateWarmInner", Vector3(-1.10, 3.30, 0.0),
		Color(1.0, 0.72, 0.40), 2.0, 6.5, false)
	BuildKit.omni_light(self, "CorridorLamp", Vector3(3.20, 3.40, 0.0),
		Color(1.0, 0.76, 0.46), 4.0, 10.0, false)
	BuildKit.omni_light(self, "CorridorFar", Vector3(7.20, 3.20, 0.0),
		Color(0.42, 0.88, 1.0), 3.2, 10.0, false)
	BuildKit.box_visual(self, "CorridorStripA", Vector3(2.60, 0.06, 0.22),
		Vector3(4.40, 4.86, 0.0), MaterialLibrary.emissive(Color(1.0, 0.82, 0.55), 1.4))
	BuildKit.box_visual(self, "CorridorStripB", Vector3(2.60, 0.06, 0.22),
		Vector3(8.20, 4.86, 0.0), MaterialLibrary.emissive(Color(0.55, 0.90, 1.0), 1.4))


# ===========================================================================
# 对外状态机
# ===========================================================================

## 剧情条件满足：**只授予驱动许可，不移动门**。
func unlock(source: String = "story") -> bool:
	if unlocked:
		return true
	unlocked = true
	unlock_source = source
	drive_enabled = true
	_log("GATE unlock source=%s drive_enabled=true height=%.3f" % [source, height])
	return true


## 撤回驱动许可（不动门；用于调试与条件失效）。
func lock() -> void:
	unlocked = false
	drive_enabled = false
	unlock_source = ""


## 剧情推进到这一步时调用：开始上升。
## 许可不足时**电机根本不会启动**（不会有一帧推力）。
func open() -> void:
	if not unlocked:
		_log("GATE open refused reason=no_story_permission")
		gate_notice.emit("出口仍被封锁：剧情条件未满足。")
		return
	if _state == "opening":
		return
	# 只有“真的到顶、且承接梁已就位”才算开完。旧实现把 `_state == "open"`
	# 一律当作已完成，于是被 close_gate() 折叠成 "open" 的半开门再也无法被
	# 重新驱动（门永久停在 3 m 左右、exit_allowed 恒 false，只能整关重置）。
	if is_open or (_state == "open" and height >= REQUIRED_CLEARANCE - 0.05):
		return
	drive_enabled = true
	powered = true
	_state = "opening"
	_stall_clock = 0.0
	_stall_timer = 0.0
	_stall_on = false
	_reverse_grace = 1.2
	_progress_ref = height
	_progress_clock = 0.0
	_retract_catch()
	_play("gate_open", global_position + Vector3(0.0, 2.0, 0.0), 0.9)
	_set_status(Color(0.95, 0.62, 0.12), 1.2)
	_log("GATE open start height=%.3f motor_limit=%.0f mass=%.0f" % [
		height, motor_force_limit, _panel.mass])


## 命令下降。**门口有人时绝不关门**（防止挤压 / 卡关）。
func close_gate() -> void:
	_opened_emitted = false
	if _doorway_occupied():
		# 状态必须由真实高度决定，不能把“正在上升的半开门”折叠成 "open"：
		# 那会让 open() 此后永久拒绝，门卡在半高、exit_allowed 恒 false。
		if height >= REQUIRED_CLEARANCE - 0.05:
			_state = "open"
		elif height > 0.02:
			_state = "opening"
			drive_enabled = true
			powered = true
		else:
			_state = "closed"
			is_open = false
			hold_mode = "none"
		_retract_catch()
		gate_notice.emit("门口有人，升降门保持开启")
		_log("GATE close refused reason=doorway_occupied height=%.3f" % height)
		return
	if height <= 0.02:
		drive_enabled = false
		unlocked = false
		unlock_source = ""
		_state = "closed"
		exit_allowed = false
		is_open = false
		hold_mode = "none"
		_retract_catch()
		_set_status(Color(0.85, 0.16, 0.10), 0.8)
		return
	drive_enabled = true
	powered = true
	# 承接梁还压着门：先把负载交回电机（releasing），再下降。
	_state = "releasing" if catch_engaged else "closing"
	_retract_catch()
	_stall_clock = 0.0
	_stall_timer = 0.0
	_stall_on = false
	# 从上升切到下降同样是方向切换：给同样的宽限，否则刚起步就被判堵转。
	_reverse_grace = 1.2
	_progress_ref = height
	_progress_clock = 0.0
	_set_status(Color(0.95, 0.62, 0.12), 1.2)


## 硬复位：一次性把门放回关闭位（关卡 R 复位用，不是每帧冻结）。
func reset_gate() -> void:
	drive_enabled = false
	unlocked = false
	unlock_source = ""
	powered = true
	motor_force_limit = F_MOTOR_MAX
	_opened_emitted = false
	is_open = false
	exit_allowed = false
	is_moving = false
	hold_mode = "none"
	motor_cut = false
	obstruction = false
	_stable_clock = 0.0
	_stall_clock = 0.0
	_stall_timer = 0.0
	_stall_on = false
	_state = "closed"
	_catch_x = CATCH_X_RETRACTED
	_catch_target_x = CATCH_X_RETRACTED
	catch_engaged = false
	if _catch != null:
		_catch.position = Vector3(_catch_x, CATCH_Y, 0.0)
	if _panel != null:
		# 单次复位：放回关闭位并清速度。这是复位，不是持续约束。
		_panel.global_transform = Transform3D(Basis(), _joint_origin)
		_panel.linear_velocity = Vector3.ZERO
		_panel.angular_velocity = Vector3.ZERO
	height = 0.0
	velocity = 0.0
	motor_force = 0.0
	resistance_force = 0.0
	clearance = 0.0
	_set_status(Color(0.85, 0.16, 0.10), 0.8)
	if _beacon != null:
		_beacon.light_energy = 0.0
	if _beacon_bulb != null:
		_beacon_bulb.material_override = MaterialLibrary.emissive(
			Color(0.16, 0.30, 0.32), 0.3)


# ===========================================================================
# 物理：唯一的执行手段是施力
# ===========================================================================
func _physics_process(delta: float) -> void:
	if not _armed or _panel == null or _joint == null:
		return
	_reverse_grace = maxf(0.0, _reverse_grace - delta)

	var rel: Vector3 = _panel.global_position - _joint_origin
	var along: float = rel.dot(_axis)
	height = along
	clearance = height
	var v: float = _panel.linear_velocity.dot(_axis)
	velocity = v

	# 关节误差：横向偏移 + 姿态偏差 —— 「导向约束真的在起作用」的读数。
	var lateral_vec: Vector3 = rel - _axis * along
	joint_error = lateral_vec.length()
	var up: Vector3 = _panel.global_transform.basis.y.normalized()
	joint_angular_error = rad_to_deg(acos(clampf(absf(up.dot(_axis)), 0.0, 1.0)))

	contact_count = _panel.get_contact_count()
	gravity_force = _panel.mass * G

	# ---- 关门途中门口出现人或晶体：立刻改为上升 ---------------------------
	# close_gate() 只在“下命令那一刻”查一次占用；玩家完全可能在门已经开始
	# 下降之后才走进门洞。不在这里复查，850 kg 门板会直接压在人身上（堵转
	# 保护只会反复断电，HUD 报“导轨被卡住”）。
	if _state == "closing" and _doorway_occupied():
		_state = "opening"
		drive_enabled = true
		powered = true
		_stall_clock = 0.0
		_stall_timer = 0.0
		_stall_on = false
		_reverse_grace = 1.2
		_progress_ref = height
		_progress_clock = 0.0
		_retract_catch()
		_set_status(Color(0.95, 0.62, 0.12), 1.2)
		gate_notice.emit("门口有人，升降门改为上升")

	# ---- 目标速度 --------------------------------------------------------
	var v_target: float = 0.0
	var want_motion: bool = false
	match _state:
		"opening":
			v_target = V_OPEN
			want_motion = true
		"closing":
			v_target = -V_CLOSE
			want_motion = true
		_:
			v_target = 0.0

	# ---- 顶部机械承接后，电机按设计断电 --------------------------------
	motor_cut = _state == "open" and catch_engaged

	# ---- 电机推力：重力前馈 + 阻力前馈 + 速度反馈，硬性钳制 ------------
	var f_requested: float = 0.0
	if drive_enabled and powered and not motor_cut:
		f_requested = (M_NOMINAL * G + F_RESIST_STATIC) + K_SPEED * (v_target - v)
		f_requested = clampf(f_requested, -motor_force_limit, motor_force_limit)

	# ---- 堵转保护：以真实行程进度判定，然后间歇占空比，不无限强推 ------
	# 判据是「这个窗口里门到底有没有真的朝目标前进」，不是瞬时速度（接触抖动会
	# 让瞬时速度反复穿过 0），也不是绝对位移（堵转后电机断电、门被重力拉回，
	# 绝对位移会假装成「有进度」而把保护误清）。
	var motion_dir: float = 0.0
	if want_motion:
		motion_dir = 1.0 if v_target > 0.0 else -1.0
	if want_motion and _reverse_grace <= 0.0:
		_progress_clock += delta
		if _progress_clock >= STALL_SECONDS:
			var advanced: float = (height - _progress_ref) * motion_dir
			_progress_clock = 0.0
			_progress_ref = height
			_stall_clock = 0.0 if advanced >= STALL_PROGRESS else _stall_clock + STALL_SECONDS
	else:
		_progress_clock = 0.0
		_progress_ref = height
		_stall_clock = maxf(_stall_clock - delta * 2.0, 0.0)

	if _stall_clock >= STALL_SECONDS and absf(f_requested) > 1.0:
		if not obstruction:
			obstruction = true
			gate_notice.emit("升降门受阻：电机已达推力上限并进入堵转保护")
			_log("GATE stall height=%.3f contacts=%d" % [height, contact_count])
		_stall_timer += delta
		if not _stall_on and _stall_timer >= STALL_OFF_SECONDS:
			_stall_on = true
			_stall_timer = 0.0
		elif _stall_on and _stall_timer >= STALL_ON_SECONDS:
			_stall_on = false
			_stall_timer = 0.0
		if not _stall_on:
			f_requested = 0.0
	else:
		if obstruction:
			obstruction = false
			_stall_timer = 0.0
			_stall_on = false
			_log("GATE stall cleared height=%.3f" % height)

	motor_force = f_requested

	# ---- 导轨阻力：库仑 + 粘滞，永远反向 --------------------------------
	var r: float = 0.0
	if absf(v) > V_REST:
		r = -signf(v) * (F_RESIST_STATIC + F_RESIST_VISCOUS * absf(v))
	elif absf(f_requested) > F_RESIST_STATIC:
		r = -signf(f_requested) * F_RESIST_STATIC
	else:
		r = -f_requested
	resistance_force = r

	# ---- 施加到刚体（唯一执行手段） -------------------------------------
	_panel.apply_central_force(_axis * f_requested)
	_panel.apply_central_force(_axis * r)

	# ---- 机械承接梁 ------------------------------------------------------
	_update_catch(delta, v)

	# ---- 行程与状态 ------------------------------------------------------
	is_moving = absf(v) > 0.05
	_update_travel_state(delta, v)


func _update_catch(delta: float, v: float) -> void:
	if _catch == null:
		return
	# 门必须真的到顶附近才允许伸梁（否则梁会顶到正在上升的门）。
	# 注意：门口有人只阻止「伸出」，绝不因此「收回」—— 已经承重的梁一旦抽走，
	# 门会直接砸在通行中的玩家身上。
	var may_extend: bool = height > CATCH_ARM_HEIGHT and absf(v) < 0.25 \
		and _state != "closing" and _state != "releasing" and not _doorway_occupied()
	var want_extended: bool = catch_engaged
	if (_state == "open" or _state == "opening") and may_extend:
		want_extended = true
	elif _state == "closing" or _state == "releasing" or _state == "closed":
		want_extended = false
	elif _state == "opening" and height <= CATCH_ARM_HEIGHT:
		want_extended = false
	_catch_target_x = CATCH_X_EXTENDED if want_extended else CATCH_X_RETRACTED

	if not is_equal_approx(_catch_x, _catch_target_x):
		_catch_x = move_toward(_catch_x, _catch_target_x, CATCH_RATE * delta)
		_catch.position = Vector3(_catch_x, CATCH_Y, 0.0)
	catch_engaged = absf(_catch_x - CATCH_X_EXTENDED) < 0.02


func _update_travel_state(delta: float, v: float) -> void:
	# 到顶：门真的到行程末端且速度归零
	if _state == "opening" and height >= H_OPEN - 0.10 and absf(v) < 0.12:
		_state = "open"
		_play("beacon_ping", global_position + Vector3(0.0, 9.5, 0.0), 0.8)

	# 承接梁收回后，负载交回电机，然后才开始下降
	if _state == "releasing" and absf(_catch_x - CATCH_X_RETRACTED) < 0.02:
		_state = "closing"

	# 到底：门真的落回门槛
	if _state == "closing" and height <= 0.03 and absf(v) < 0.12:
		_state = "closed"
		is_open = false
		exit_allowed = false
		hold_mode = "none"
		drive_enabled = false
		unlocked = false
		unlock_source = ""
		_set_status(Color(0.85, 0.16, 0.10), 0.8)
		if _beacon != null:
			_beacon.light_energy = 0.0
		if _beacon_bulb != null:
			_beacon_bulb.material_override = MaterialLibrary.emissive(
				Color(0.16, 0.30, 0.32), 0.3)

	# ---- 顶部保持 --------------------------------------------------------
	if catch_engaged:
		hold_mode = "catch"      # 门真的坐在钢梁上，电机已按设计断电
	elif drive_enabled and powered and height > REQUIRED_CLEARANCE - 0.05 and absf(v) < 0.12:
		hold_mode = "motor"      # 限力保持电机
	else:
		hold_mode = "none"

	# ---- 通行判定：来自门体实际净空，不是剧情标记 ------------------------
	var stable: bool = height >= REQUIRED_CLEARANCE and absf(v) < 0.08 \
		and not obstruction and hold_mode != "none"
	if stable:
		_stable_clock += delta
	else:
		_stable_clock = 0.0

	var now_allowed: bool = _stable_clock >= STABLE_SECONDS
	if now_allowed != exit_allowed:
		exit_allowed = now_allowed
		is_open = now_allowed
		if now_allowed:
			_set_status(Color(0.30, 0.95, 1.0), 1.8)
			if _beacon != null:
				_beacon.light_energy = 1.4
			if _beacon_bulb != null:
				_beacon_bulb.material_override = MaterialLibrary.emissive(
					Color(0.40, 0.96, 1.0), 2.6)
			if not _opened_emitted:
				_opened_emitted = true
				opened_gate.emit()
				_log("GATE opened height=%.3f clearance=%.3f hold=%s" % [
					height, clearance, hold_mode])
		else:
			is_open = false


func _doorway_occupied() -> bool:
	if _doorway == null:
		return false
	for body: Node3D in _doorway.get_overlapping_bodies():
		# 玩家会被门板压住；晶体被 850 kg 门板与门槛夹住时会被 Jolt 弹飞。
		if body is EchoPlayer or body is PortableCrystal:
			return true
	return false


# ===========================================================================
# 对外读数
# ===========================================================================
func get_diagnostics() -> Dictionary:
	return {
		"mass": _panel.mass if _panel != null else 0.0,
		"inertia_diagonal": _inertia_diagonal(),
		"motor_force": motor_force,
		"motor_limit": motor_force_limit,
		"resistance_force": resistance_force,
		"gravity_force": gravity_force,
		"velocity": velocity,
		"height": height,
		"clearance": clearance,
		"travel": H_OPEN,
		"required_clearance": REQUIRED_CLEARANCE,
		"joint_error": joint_error,
		"joint_angular_error": joint_angular_error,
		"contact_count": contact_count,
		"obstruction": obstruction,
		"hold_mode": hold_mode,
		"catch_engaged": catch_engaged,
		"motor_cut": motor_cut,
		"exit_allowed": exit_allowed,
		"is_open": is_open,
		"state": _state,
		"drive_enabled": drive_enabled,
		"unlocked": unlocked,
		"powered": powered,
		"axis": _axis,
		"joint_axis_world": _joint.global_transform.basis.x.normalized() \
			if _joint != null else Vector3.ZERO,
		"panel_layer": _panel.collision_layer if _panel != null else 0,
		"panel_mask": _panel.collision_mask if _panel != null else 0,
	}


func _inertia_diagonal() -> Vector3:
	if _panel == null:
		return Vector3.ZERO
	var m: float = _panel.mass
	var s: Vector3 = PANEL_SIZE
	return Vector3(
		m * (s.y * s.y + s.z * s.z) / 12.0,
		m * (s.x * s.x + s.z * s.z) / 12.0,
		m * (s.x * s.x + s.y * s.y) / 12.0)


func get_panel() -> RigidBody3D:
	return _panel


func get_joint() -> SliderJoint3D:
	return _joint


func get_catch_beam() -> StaticBody3D:
	return _catch


func get_interaction_position() -> Vector3:
	# 门洞西侧 1.0 m、1.6 m 高：站在门前就能读到提示。
	return to_global(Vector3(-1.00, 1.60, 0.0))


func get_interaction_reach() -> float:
	return 3.4


func _on_body_entered(body: Node3D) -> void:
	if not exit_allowed:
		return
	if body is EchoPlayer:
		player_entered.emit()


func get_interaction_prompt(_player: Node) -> String:
	if exit_allowed:
		return "前往矿区核心"
	if obstruction:
		return "升降门被卡住了。先清空导轨。"
	if _state == "opening":
		return "升降门上升中……等待足够净空"
	if _state == "open":
		return "升降门未锁止，净空不足。"
	return "出口被封锁了。先让最后一段记忆醒来。"


func _set_status(color: Color, energy: float) -> void:
	if _status_material == null:
		return
	_status_material.albedo_color = color
	_status_material.emission = color
	_status_material.emission_energy_multiplier = energy


func _retract_catch() -> void:
	_catch_target_x = CATCH_X_RETRACTED


func _play(cue: String, at: Vector3, volume: float) -> void:
	if _audio != null and _audio.has_method("play_at"):
		_audio.call("play_at", cue, at, volume)


## 发布构建里 Log.enabled 为 false，这些原本常驻的 GATE 日志会退化为一次布尔判断。
func _log(message: String) -> void:
	if Log.enabled:
		print(message)


