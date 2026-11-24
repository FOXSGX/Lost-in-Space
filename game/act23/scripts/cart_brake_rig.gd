extends Node3D

# -----------------------------------------------------------------------------
# MECHANICS-002B · 手制动机构（真实行程 → 真实夹紧力 → 真实制动力）
#
# 位置：矿车前甲板近侧（E 发车器左侧）。玩家按 B 把手柄拉过棘轮扇形板：
#   0 档 = 释放（弹簧把闸瓦拉离鼓面 4 mm）
#   1 档 = 常用（手柄 62% 行程，弹簧压紧量 64 mm）
#   2 档 = 紧急（手柄顶到机械止挡，压紧量 120 mm）
#
# 物理链：
#   travel → 闸瓦行程（先走完 4 mm 间隙才接触）→ 闸瓦弹簧压缩量
#   → 法向压紧力 N = SPRING_K · compression
#   → 摩擦制动力矩 T = MU_PAD · N · DRUM_R
#   → 轮缘等效制动力 F = T / WHEEL_R（WHEEL_R 与车体滚轮同源，见 moving_cart）
#
# 这条链上没有任何"按 B 就让速度归零"的捷径；机构停住（受阻）时压紧量为 0，
# 制动力也就是 0，闸不会假装咬合。
# -----------------------------------------------------------------------------

const DRUM_R: float = 0.30          # 制动鼓半径（m）
const WHEEL_R: float = 0.795        # 与 moving_cart 的滚轮半径一致（m）
const MU_PAD: float = 0.40          # 闸瓦摩擦系数（干态有机衬片 / 铸铁鼓）
const SPRING_K: float = 210000.0    # 闸瓦弹簧组刚度（N/m）
const MAX_COMPRESSION: float = 0.120  # 满行程弹簧压缩量（m）
const SHOE_GAP: float = 0.004       # 释放时间隙（m）
const TOUCH_TRAVEL: float = 0.18    # 手柄行程到 18% 才消除间隙
const LEVER_RATE: float = 3.2       # 手柄行程速度（1/s，约 0.3 s 拉满）
const NOTCH_TRAVEL: Array[float] = [0.0, 0.62, 1.0]

# 视觉几何（车体局部坐标）
const PIVOT_AT: Vector3 = Vector3(1.55, 2.24, 1.35)
const DRUM_AT: Vector3 = Vector3(2.70, 1.10, 0.72)
const REST_PITCH: float = -0.32
const PULL_PITCH: float = 0.42

var cart: Node3D
var notch: int = 0
var travel: float = 0.0
var target_travel: float = 0.0
var blocked: bool = false           # 机械受阻（试验用楔块，正常游玩为 false）
var drum_omega: float = 0.0
var drum_angle: float = 0.0

var _lever: Node3D
var _rod: MeshInstance3D
var _shoe: Node3D
var _drum_spin: Node3D
var _pawl: Node3D
var _lever_mat: StandardMaterial3D


func _ready() -> void:
	_build()


func _build() -> void:
	var env: Script = preload("res://act23/scripts/cart_environment.gd")
	# Compatibility 渲染器没有环境反射：金属度高的材质会直接变黑，制动鼓用低金属度。
	var steel: StandardMaterial3D = env.material(Color("8a9396"), 0.10)
	var dark: StandardMaterial3D = env.material(Color("3f484c"), 0.10)
	var brass: StandardMaterial3D = env.material(Color("c9a05a"), 0.35)
	var liner: StandardMaterial3D = env.material(Color("8d6a4b"), 0.10)
	_lever_mat = env.material(Color("d4553f"), 0.25)

	# 底架：一块带加强筋的机座，落在甲板上（同时挡住玩家，不能站进去）。
	env.box(self, Vector3(0.30, 0.26, 0.26), dark, Vector3(PIVOT_AT.x, 2.10, PIVOT_AT.z))
	env.box(self, Vector3(0.42, 0.04, 0.34), steel, Vector3(PIVOT_AT.x, 1.9746, PIVOT_AT.z))
	var base_body: StaticBody3D = StaticBody3D.new()
	base_body.name = "BrakeStandBody"
	base_body.collision_layer = 2
	base_body.collision_mask = 0
	var base_shape: BoxShape3D = BoxShape3D.new()
	base_shape.size = Vector3(0.32, 0.30, 0.28)
	var base_collider: CollisionShape3D = CollisionShape3D.new()
	base_collider.shape = base_shape
	base_collider.position = Vector3(PIVOT_AT.x, 2.105, PIVOT_AT.z)
	base_body.add_child(base_collider)
	add_child(base_body)
	# 扇形棘轮板 + 三个齿槽（0/1/2 档的物理定位）
	var quadrant: Node3D = Node3D.new()
	quadrant.position = PIVOT_AT + Vector3(-0.10, 0.02, 0.0)
	add_child(quadrant)
	env.box(quadrant, Vector3(0.035, 0.28, 0.11), brass, Vector3.ZERO)
	for i: int in range(3):
		var angle: float = REST_PITCH + (PULL_PITCH - REST_PITCH) * NOTCH_TRAVEL[i]
		var tooth: MeshInstance3D = env.box(quadrant, Vector3(0.05, 0.028, 0.13), brass,
			Vector3(0, 0.10 + 0.10 * float(i), 0))
		tooth.rotation.z = angle - REST_PITCH
	# 手柄：绕 PIVOT_AT 的 z 轴摆动
	_lever = Node3D.new()
	_lever.name = "BrakeLever"
	_lever.position = PIVOT_AT
	add_child(_lever)
	env.box(_lever, Vector3(0.06, 0.46, 0.06), steel, Vector3(0, 0.23, 0))
	var hub: MeshInstance3D = env.box(_lever, Vector3(0.10, 0.10, 0.12), dark, Vector3.ZERO)
	hub.rotation = Vector3(0, 0, PI * 0.25)
	env.box(_lever, Vector3(0.075, 0.16, 0.075), _lever_mat, Vector3(0, 0.50, 0))
	# 棘爪（跟随手柄，落在齿槽里）
	_pawl = Node3D.new()
	_pawl.position = PIVOT_AT + Vector3(-0.055, 0.10, 0.0)
	add_child(_pawl)
	env.box(_pawl, Vector3(0.12, 0.03, 0.035), steel, Vector3.ZERO)

	# 制动鼓：与近侧前轮同轴，装在轮外侧的短轴上（真实鼓式制动器常见布置）。
	_drum_spin = Node3D.new()
	_drum_spin.position = DRUM_AT
	add_child(_drum_spin)
	var drum: MeshInstance3D = MeshInstance3D.new()
	var cylinder: CylinderMesh = CylinderMesh.new()
	cylinder.top_radius = DRUM_R
	cylinder.bottom_radius = DRUM_R
	cylinder.height = 0.085
	cylinder.radial_segments = 24
	drum.mesh = cylinder
	drum.material_override = steel
	drum.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	_drum_spin.add_child(drum)
	# 鼓面上的散热筋（转动时肉眼可辨）
	for k: int in range(4):
		var rib: MeshInstance3D = env.box(_drum_spin, Vector3(0.22, 0.02, 0.02), dark,
			Vector3(0, cos(float(k) * PI * 0.5) * DRUM_R * 0.72, sin(float(k) * PI * 0.5) * DRUM_R * 0.72))
		rib.rotation.x = float(k) * PI * 0.5
	# 鼓的支架（固定，不随鼓转）
	var bracket: MeshInstance3D = env.box(self, Vector3(0.16, 0.30, 0.10), dark,
		DRUM_AT + Vector3(-0.06, 0.30, 0.0))
	bracket.rotation = Vector3(0, 0, -0.25)

	# 闸瓦：包住鼓的顶部，行程 0.004 m 到 0（接触后弹簧继续压缩，瓦不动）。
	_shoe = Node3D.new()
	_shoe.name = "BrakeShoe"
	_shoe.position = DRUM_AT + Vector3(0, DRUM_R + SHOE_GAP, 0)
	add_child(_shoe)
	env.box(_shoe, Vector3(0.30, 0.07, 0.12), liner, Vector3.ZERO)
	env.box(_shoe, Vector3(0.34, 0.03, 0.14), steel, Vector3(0, 0.05, 0))

	# 拉杆：从手柄下端连到闸瓦托，随行程伸长/缩短（真实连杆，不是贴图）。
	_rod = MeshInstance3D.new()
	var rod_mesh: BoxMesh = BoxMesh.new()
	rod_mesh.size = Vector3(0.035, 1.0, 0.035)
	_rod.mesh = rod_mesh
	_rod.material_override = steel
	add_child(_rod)


func _physics_process(delta: float) -> void:
	# 机构自身没有独立物理：手柄行程由 cart 每帧调用 tick() 推进，
	# 保证制动力与矿车积分在同一个物理步里。
	pass


# 手柄向目标档位移动；被楔块挡住时停在接触点之前（压紧量 0）。
func tick(delta: float, speed: float) -> void:
	var limit: float = target_travel
	if blocked:
		limit = minf(limit, TOUCH_TRAVEL * 0.92)
	if travel < limit:
		travel = minf(limit, travel + LEVER_RATE * delta)
	elif travel > limit:
		travel = maxf(limit, travel - LEVER_RATE * delta)
	drum_omega = speed / WHEEL_R
	drum_angle = fmod(drum_angle - drum_omega * delta, TAU)
	_apply_visuals()


func _apply_visuals() -> void:
	_lever.rotation.z = REST_PITCH + (PULL_PITCH - REST_PITCH) * travel
	_pawl.rotation.z = (REST_PITCH + (PULL_PITCH - REST_PITCH) * travel) * 0.25
	_drum_spin.rotation.z = drum_angle
	var contact: float = clampf(travel / TOUCH_TRAVEL, 0.0, 1.0)
	_shoe.position = DRUM_AT + Vector3(0, DRUM_R + SHOE_GAP * (1.0 - contact), 0)
	# 连杆：从手柄下端到闸瓦托，按实际两点重算位置/朝向/长度。
	var from: Vector3 = PIVOT_AT + Vector3(0, 0.16, 0)
	from += Vector3(sin(_lever.rotation.z), -cos(_lever.rotation.z), 0) * 0.10
	var to: Vector3 = _shoe.position + Vector3(-0.12, 0.02, 0)
	var mid: Vector3 = (from + to) * 0.5
	var span: float = from.distance_to(to)
	_rod.position = mid
	_rod.scale = Vector3(1, maxf(span, 0.01), 1)
	if span > 0.001:
		_rod.look_at(_rod.to_global(to), Vector3.UP)


# --- 机构状态 ---------------------------------------------------------------

func set_notch(value: int) -> void:
	notch = clampi(value, 0, 2)
	target_travel = NOTCH_TRAVEL[notch]


func cycle_notch() -> int:
	set_notch((notch + 1) % 3)
	return notch


func release() -> void:
	set_notch(0)


func set_blocked(value: bool) -> void:
	blocked = value


func spring_compression() -> float:
	var beyond: float = clampf((travel - TOUCH_TRAVEL) / (1.0 - TOUCH_TRAVEL), 0.0, 1.0)
	if blocked:
		return 0.0
	return beyond * MAX_COMPRESSION


func shoe_force() -> float:
	return SPRING_K * spring_compression()


# 闸瓦作用在鼓面上的摩擦力矩换算到轮缘的等效制动力（N），永远 >= 0。
func brake_force_at_rail() -> float:
	var torque: float = MU_PAD * shoe_force() * DRUM_R
	return torque / WHEEL_R


func drum_surface_speed() -> float:
	return absf(drum_omega) * DRUM_R


func state() -> Dictionary:
	return {
		"notch": notch,
		"travel": snappedf(travel, 0.001),
		"target": snappedf(target_travel, 0.001),
		"compression": snappedf(spring_compression(), 0.0001),
		"shoe_force": snappedf(shoe_force(), 1.0),
		"brake_force": snappedf(brake_force_at_rail(), 1.0),
		"blocked": blocked,
		"drum_omega": snappedf(drum_omega, 0.001),
		"drum_surface": snappedf(drum_surface_speed(), 0.001),
	}


