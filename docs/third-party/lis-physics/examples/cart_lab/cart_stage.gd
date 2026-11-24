extends LISDemoStage
## 示例 4 · 真实推车场
##
## 包含：平地 / 坡道 / 冰面 / 粗糙地面 / 装载货箱 / 墙和障碍物。
## 必须显示**实际车轮角速度与车身速度的关系**（HUD 里的 slip 读数）。
##
## 关键判据：车轮转速 × 半径 ≈ 车身速度（纯滚动），
## 冰面上这条关系会明显破裂 —— 那就是"打滑"。

var cart: LISCart
var _ramp: StaticBody3D
var _ice: StaticBody3D
var _crates: Array[LISBody] = []
var _spawn_crates: Array[Vector3] = []
var _hud_extra: Label


func _ready() -> void:
	stage_title = "示例 4 · 真实推车场"
	stage_help = """WASD 走路 · 顶住推车后栏杆用身体推
鼠标左键抓住车可拖行 · R 复位

地面分区（从近到远）：
  灰 = 平地 μ0.85 · 蓝 = 冰面 μ0.02
  黄 = 粗糙地面 μ0.95 · 前方斜坡 12°

HUD 读数：ω·R（轮缘线速度）与 v（车身速度）
两者接近 = 纯滚动；差距大 = 打滑。"""
	spawn_point = Vector3(0.0, 1.2, 14.0)
	stage_half = 26.0
	super()


func _build_scenery() -> void:
	# 冰面区（左侧）
	_ice = add_static_box("IcePatch", Vector3(9.0, 0.06, 18.0),
		Vector3(-7.0, 0.03, 0.0), Vector3.ZERO, Color(0.42, 0.62, 0.82), 0.02)
	# 粗糙区（右侧）
	add_static_box("RoughPatch", Vector3(9.0, 0.06, 18.0),
		Vector3(7.0, 0.03, 0.0), Vector3.ZERO, Color(0.62, 0.52, 0.30), 0.95)
	# 坡道（正前方，绕过中心）
	_ramp = add_static_box("Ramp", Vector3(5.0, 0.30, 9.0),
		Vector3(0.0, 1.1, -9.0), Vector3(12.0, 0.0, 0.0), Color(0.34, 0.36, 0.40), 0.85)
	# 坡道顶的平台
	add_static_box("Plateau", Vector3(5.0, 0.30, 4.0),
		Vector3(0.0, 2.05, -15.0), Vector3.ZERO, Color(0.30, 0.33, 0.37), 0.85)
	# 墙与障碍
	add_static_box("WallA", Vector3(0.5, 2.4, 26.0), Vector3(-13.0, 1.2, 0.0),
		Vector3.ZERO, Color(0.24, 0.27, 0.31))
	add_static_box("WallB", Vector3(0.5, 2.4, 26.0), Vector3(13.0, 1.2, 0.0),
		Vector3.ZERO, Color(0.24, 0.27, 0.31))
	add_static_box("Block1", Vector3(1.2, 1.0, 1.2), Vector3(-4.0, 0.5, -4.0),
		Vector3.ZERO, Color(0.42, 0.40, 0.36))
	add_static_box("Block2", Vector3(1.0, 0.8, 1.0), Vector3(4.5, 0.4, -3.0),
		Vector3.ZERO, Color(0.42, 0.40, 0.36))


func _build_content() -> void:
	cart = LISCart.new()
	cart.name = "StageCart"
	add_child(cart)
	cart.global_position = Vector3(0.0, 0.60, 4.0)
	register_reset(cart)
	# 货台上的货物
	for i in range(4):
		var c: LISBody = add_body("Cargo%d" % i,
			Vector3(-0.25 + 0.25 * float(i % 2), 0.95 + 0.42 * float(i / 2), 4.0 - 0.3 + 0.6 * float(i % 2)),
			Vector3(0.42, 0.42, 0.42), 12.0,
			Color(0.68, 0.58, 0.38), {"display_name": "货箱%d" % (i + 1)})
		_crates.append(c)
		_spawn_crates.append(c.global_position)
	# 地面上的散货
	for i in range(3):
		add_body("Loose%d" % i, Vector3(-3.0 + float(i) * 3.0, 0.26, 10.0),
			Vector3(0.48, 0.48, 0.48), 9.0, Color(0.60, 0.64, 0.52),
			{"display_name": "散货%d" % (i + 1)})


func _physics_process(_delta: float) -> void:
	if cart == null or not is_instance_valid(cart) or hud == null or not is_instance_valid(hud):
		return
	var v: float = cart.telemetry_forward_speed
	var omega: float = cart.average_wheel_spin()
	var rim: float = omega * LISCart.WHEEL_RADIUS
	var slip: float = cart.slip_ratio()
	var cargo: Array[Node3D] = cart.cargo_on_deck()
	var load_kg: float = 0.0
	for c: Node3D in cargo:
		var rb: RigidBody3D = c as RigidBody3D
		if rb != null:
			load_kg += rb.mass
	var out: PackedStringArray = PackedStringArray()
	out.append("车身速度 v = %+.2f m/s" % v)
	out.append("车轮 ω = %+.2f rad/s   ω·R = %+.2f m/s" % [omega, rim])
	out.append("打滑比 slip = %+.2f   %s" % [slip,
		"纯滚动" if absf(slip) < 0.25 else ("打滑/空转" if slip > 0 else "车轮未转、车身在滑")])
	out.append("触地轮 %d/4 · 倾角 %.1f°" % [
		cart.telemetry_grounded_wheels, cart.telemetry_tilt])
	out.append("货台载重 %.0f kg（%d 件）" % [load_kg, cargo.size()])
	hud.extra_lines = out


func reset_stage() -> void:
	if cart != null and is_instance_valid(cart):
		cart.reset_pose(Vector3(0.0, 0.60, 4.0), 0.0)
	for i in range(_crates.size()):
		var c: LISBody = _crates[i]
		if c == null or not is_instance_valid(c):
			continue
		c.reset_to(Transform3D(Basis.IDENTITY, _spawn_crates[i]))
	super()
