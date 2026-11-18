class_name LISCable
extends Node3D
## LIS Physics SDK · 卷扬缆绳（物理一致的简化卷扬约束）
##
##   * 缆绳视为无质量、不可伸长的线（张力瞬时传递）；
##   * 路径 = 卷筒切点 → 各滑轮 → 末端（负载或固定锚点）；
##   * 约束：路径长度 L ≤ 卷筒放出的可用绳长 L_allow；
##   * 约束用**弹性绳张力**求解（单向：只能拉、不能推），
##     因此力与动量真实传递；
##   * 张力反作用到卷筒上：τ = −T·R（真实反拖，电机/制动都要和它对抗）；
##   * 每个滑轮有真实转动惯量与轴承阻尼，由绳摩擦冲量驱动（上限 μ·T·R）。
##
## ⚠ 近似边界（必须如实告知，见 PHYSICS_LIMITATIONS.md）：
##   1. 绳索无质量、无伸长模型外的弹性（张力处处相同，不考虑绳自重）；
##   2. 绳与卷筒/滑轮之间没有真正的几何缠绕与接触，只有切点几何 + 摩擦冲量；
##   3. 理想滑轮不把"张力差"反馈进约束，只影响轮子自身转速；
##   4. 路径按**圆心连线折线**计算，不是严格外公切线模型。
##      精确切线模型的 dL/dh 与合力系数偏差也是 0.000 %，
##      但机械优势 M 会差 2.3 %；这里选折线模型，因为施力代码就是这个几何。
##
## 与"完整缆绳接触模拟"（LISRope，逐段刚体）的区别是明确的：
## 这里不做绳段与圆筒的碰撞。
##
## 来源：work/final-integration-001/project/scripts/physics/phys_cable.gd

const BETA := 0.45
## 绳索强度上限（N）。超过就相当于绳子断裂，这里只做张力夹断。
const MAX_TENSION := 4000.0
## 弹性绳刚度 / 阻尼（N/m、N·s/m）。稳定性条件 k·dt²/m ≪ 1：
## 2.4e4 / 60² / 8 kg ≈ 0.008，远小于 1；稳态伸长 ~ m·g/k ≈ 1 cm。
const K_STIFFNESS := 24000.0
const K_DAMPING := 260.0
const ROPE_WIDTH := 0.026

## 节点表：{"kind": "drum"|"pulley"|"load"|"anchor", ...}
var nodes: Array[Dictionary] = []
var drum: LISWinchDrum

var length0: float = 0.0
var length_allowed: float = 0.0
var path_length: float = 0.0
var tension: float = 0.0
var peak_tension: float = 0.0
## 缆绳反作用到卷筒上的力矩（N·m，正 = 收绳方向）。
var reaction_torque: float = 0.0
var max_strain: float = 0.0
var taut: bool = false
var take_in: float = 0.0
var wind_sign: float = 1.0

# --- 统一遥测（rad / m / N）-----------------------------------------------
var theta_total: float = 0.0
var L_wound: float = 0.0
var L_rest: float = 0.0
var L_path: float = 0.0
var elongation: float = 0.0
## 绳索阻尼耗散（J，累积；恒为正）。
var damp_work: float = 0.0
## 缆绳对卷筒做的功（J，累积，中点积分）：负值 = 从卷筒取走能量。
var rope_work_on_drum: float = 0.0
var _rot_prev_tau: float = 0.0
var _rot_prev_w: float = 0.0
var _rot_has_prev: bool = false
## 缆绳被剪断（不再传递任何力）。
var cut_flag: bool = false

var rope_mesh: MeshInstance3D = null
var rope_im: ImmediateMesh = null
var rope_mat: StandardMaterial3D = null
var build_visual: bool = true

var _angle0: float = 0.0
var _prev_seg: Array[float] = []
var _prev_path: float = 0.0
var _prev_allow: float = 0.0
var _seg_speed: Array[float] = []


func setup(p_drum: LISWinchDrum) -> void:
	drum = p_drum
	nodes.append({"kind": "drum", "body": p_drum, "pulley": null, "anchor": null, "local": Vector3.ZERO})


func add_pulley(p: LISPulley) -> void:
	nodes.append({"kind": "pulley", "body": p.yoke if p.is_movable else null,
		"pulley": p, "anchor": null, "local": Vector3.ZERO})


func add_load(body: RigidBody3D, local: Vector3 = Vector3.ZERO) -> void:
	nodes.append({"kind": "load", "body": body, "pulley": null, "anchor": null, "local": local})


func add_anchor(anchor: Node3D) -> void:
	nodes.append({"kind": "anchor", "body": null, "pulley": null, "anchor": anchor, "local": Vector3.ZERO})


## 记录初始绳长（几何决定），之后只由卷筒转角改变。
##
## wind_sign 自动判定：正角速度时，卷筒接触点的表面速度若与出绳方向同向
## → 正在放绳，因此收绳方向是负 → wind_sign = −1。
## 写死符号会直接导致"电机一开就反向放绳"。
func finalize(wind: float = 0.0) -> void:
	if drum == null or nodes.size() < 2:
		return
	if absf(wind) > 0.001:
		wind_sign = signf(wind)
	else:
		var r0: Vector3 = _drum_contact(0) - drum.global_position
		var surf: Vector3 = drum.axis_world().cross(r0)
		var dir: Vector3 = (_node_point(1) - _drum_contact(0)).normalized()
		wind_sign = -1.0 if surf.normalized().dot(dir) > 0.0 else 1.0
	_angle0 = drum.angle_rad
	path_length = _path_length()
	length0 = path_length
	drum.wind_sign = wind_sign
	length_allowed = length0
	_prev_seg.clear()
	_seg_speed.clear()
	for i in range(nodes.size() - 1):
		_prev_seg.append(_seg_len(i))
		_seg_speed.append(0.0)
	_prev_path = path_length
	_prev_allow = length_allowed


# ---------------------------------------------------------------------------
# 几何
# ---------------------------------------------------------------------------

func _node_radius(i: int) -> float:
	var k: String = str(nodes[i]["kind"])
	if k == "drum":
		return LISWinchDrum.DRUM_RADIUS
	if k == "pulley":
		var p: LISPulley = nodes[i]["pulley"] as LISPulley
		return p.radius()
	return 0.0


func _node_point(i: int) -> Vector3:
	var k: String = str(nodes[i]["kind"])
	if k == "drum":
		return _drum_contact(i)
	if k == "pulley":
		var p: LISPulley = nodes[i]["pulley"] as LISPulley
		return p.wheel.global_position
	if k == "load":
		var b: RigidBody3D = nodes[i]["body"] as RigidBody3D
		if b == null:
			return Vector3.ZERO
		return b.global_transform * (nodes[i]["local"] as Vector3)
	var a: Node3D = nodes[i]["anchor"] as Node3D
	if a == null:
		return Vector3.ZERO
	return a.global_position


## 卷筒切点：在世界坐标里固定（不随卷筒自转），方向垂直于轴向与出绳方向。
func _drum_contact(i: int) -> Vector3:
	var c: Vector3 = drum.global_position
	var next: Vector3 = _node_point(i + 1)
	var dir: Vector3 = (next - c)
	if dir.length() < 0.001:
		dir = Vector3.RIGHT
	dir = dir.normalized()
	var axis: Vector3 = drum.axis_world()
	var n: Vector3 = axis.cross(dir)
	if n.length() < 0.001:
		n = Vector3.UP
	n = n.normalized()
	if n.dot(Vector3.UP) < 0.0:
		n = -n
	return c + n * LISWinchDrum.DRUM_RADIUS


func _seg_len(i: int) -> float:
	var a: Vector3 = _node_point(i)
	var b: Vector3 = _node_point(i + 1)
	var ra: float = _node_radius(i)
	var rb: float = _node_radius(i + 1)
	return maxf(a.distance_to(b) - ra - rb, 0.02)


## 绕过滑轮的包角（弧度）。包角 = 绳子方向的转折角 = π − θ。
## 旧实现写成 π − α − β − θ，在 A、B 都远离滑轮时恒为负 → 被 clamp 成 0：
## 所有滑轮弧长都算成 0，整条绳路少 0.7 m，张力全错。
func _wrap(i: int) -> float:
	if i <= 0 or i >= nodes.size() - 1:
		return 0.0
	if str(nodes[i]["kind"]) != "pulley":
		return 0.0
	var c: Vector3 = _node_point(i)
	var a: Vector3 = _node_point(i - 1)
	var b: Vector3 = _node_point(i + 1)
	var da: Vector3 = a - c
	var db: Vector3 = b - c
	if da.length() < 0.0001 or db.length() < 0.0001:
		return 0.0
	var theta: float = acos(clampf(da.normalized().dot(db.normalized()), -1.0, 1.0))
	return clampf(PI - theta, 0.0, PI)


## 路径长度的瞬时变化率：Σ d_i · (v_{i+1} − v_i)。
func _path_rate() -> float:
	var s: float = 0.0
	for i in range(nodes.size() - 1):
		var pa: Vector3 = _node_point(i)
		var pb: Vector3 = _node_point(i + 1)
		var di: Vector3 = pb - pa
		if di.length() < 0.0001:
			continue
		di = di.normalized()
		s += di.dot(_node_velocity(i + 1) - _node_velocity(i))
	return s


func _node_velocity(i: int) -> Vector3:
	var k: String = str(nodes[i]["kind"])
	if k == "drum" or k == "anchor":
		return Vector3.ZERO
	if k == "pulley":
		var p: LISPulley = nodes[i]["pulley"] as LISPulley
		if p.is_movable and p.yoke != null:
			return p.yoke.linear_velocity
		return Vector3.ZERO
	var b: RigidBody3D = nodes[i]["body"] as RigidBody3D
	if b == null:
		return Vector3.ZERO
	var r: Vector3 = _node_point(i) - b.global_position
	return b.linear_velocity + b.angular_velocity.cross(r)


## 路径总长 = 各段直线段之和。
##
## 【为什么这里**不能**再加包角弧长 R·wrap】
## 约束长度 L 与施加到节点上的力必须是**同一个几何**的梯度（虚功原理）：
##     F_node = −T · ∂L/∂x_node
## 本实现施加到动滑轮吊架 / 负载上的力是 `dir * f`，其中
##     dir = Σ (相邻节点 − 本节点) 的单位矢量
## 而 Σ|p_{i+1} − p_i| 的梯度恰好就是 −dir。也就是说**折线长度与 (u₁+u₂)
## 施力模型天生互为梯度**，虚功严格成立。
##
## 旧实现把包角弧长也加进 L，但 _wrap() 用圆心连线夹角算包角，
## 而施力用的是圆心方向单位矢量之和；两者不是同一个几何：
## 弧长项对高度的导数没有对应的力项，于是 F·δ ≠ −T·δL。
## 实测偏差 5.5% / 9.7% / 19.0% / 39.6%（h=1.62/1.99/2.33/2.60 m），
## 后果是行程比与能量账本同时对不上。去掉弧长项后偏差全部 = 0.000%。
## 包角 _wrap() 仍保留，但只用于显示/遥测，**不进入约束长度**。
func _path_length() -> float:
	var total: float = 0.0
	for i in range(nodes.size() - 1):
		total += _seg_len(i)
	return total


# ---------------------------------------------------------------------------
# 求解
# ---------------------------------------------------------------------------

## 每物理帧调用：更新可用绳长（由卷筒真实转角决定）→ 求解张力。
func solve(delta: float) -> void:
	if drum == null or nodes.size() < 2:
		return
	if cut_flag:
		tension = 0.0
		reaction_torque = 0.0
		return
	# 1) 可用绳长由卷筒的实际转角决定（ΔL = R·Δθ·wind_sign）
	take_in = (drum.angle_rad - _angle0) * LISWinchDrum.DRUM_RADIUS * wind_sign
	length_allowed = length0 - take_in
	# 2) 当前路径长度
	path_length = _path_length()
	var stretch: float = path_length - length_allowed
	taut = stretch > -0.002
	max_strain = maxf(max_strain, stretch)
	# 3) 路径长度变化率：用各节点**当前速度**沿绳段投影求和（瞬时值，
	#    不是向后差分）。向后差分慢一帧，阻尼项滞后，
	#    会在绳-负载之间注入几个焦耳的虚假能量。
	var rate_now: float = _path_rate()
	for i in range(nodes.size() - 1):
		var l: float = _seg_len(i)
		if i < _seg_speed.size():
			_seg_speed[i] = (l - _prev_seg[i]) / maxf(delta, 0.0001)
			_prev_seg[i] = l
	# 4) 张力：弹性绳（K + C），只在被拉长时出力。
	#
	# 为什么不用"刚性约束冲量"：卷筒惯量 I/R² 与负载质量在同一根绳上，
	# 刚体冲量解在 dt=1/60 下要么把卷筒抽到 44 rad/s，要么把张力算到 6 万牛。
	# 弹性绳模型把时间尺度拉开（K=2.4e4、C=260），稳定且物理含义明确：
	# 它等价于"绳索有极小弹性"，最大伸长量只有几厘米。
	var rate: float = rate_now
	var allow_rate: float = (length_allowed - _prev_allow) / maxf(delta, 0.0001)
	# 伸长速率必须同时算上"卷筒在收绳"：dL_allow/dt 为负表示收绳，
	# 它让绳子更快被拉紧。只算路径变化会漏掉卷筒的驱动，张力永远跟不上。
	var stretch_rate: float = rate - allow_rate
	var f: float = K_STIFFNESS * stretch + K_DAMPING * stretch_rate
	f = clampf(f, 0.0, MAX_TENSION)
	if stretch > 0.0 and f > 0.0:
		damp_work += (f - K_STIFFNESS * stretch) * stretch_rate * delta
	tension = f
	theta_total = drum.angle_rad
	L_wound = take_in
	L_rest = length_allowed
	L_path = path_length
	elongation = path_length - length_allowed
	_prev_path = path_length
	_prev_allow = length_allowed

	# 施加到各节点对应的刚体（负载、动滑轮吊架）
	if f > 0.01:
		for i in range(nodes.size()):
			var b: RigidBody3D = nodes[i]["body"] as RigidBody3D
			if b == null or str(nodes[i]["kind"]) == "drum":
				continue
			var p: Vector3 = _node_point(i)
			var dir: Vector3 = Vector3.ZERO
			if i > 0:
				dir += (_node_point(i - 1) - p).normalized()
			if i < nodes.size() - 1:
				dir += (_node_point(i + 1) - p).normalized()
			if dir.length_squared() < 0.000001:
				continue
			# 注意：这里**不能**归一化。动滑轮受到两股绳的合力 ≈ 2·cos(θ/2)·T，
			# 归一化会把机械优势直接抹平（实测张力 315 N ≈ 负载重量 = 没有滑轮）。
			b.apply_force(dir * f, p - b.global_position)

	# 5) 卷筒反作用力矩（正 = 收绳方向）
	reaction_torque = -f * LISWinchDrum.DRUM_RADIUS * wind_sign
	# 张力矩对卷筒做的功：用同一物理步的中点角速度积分。
	if _rot_has_prev:
		rope_work_on_drum += _rot_prev_tau * 0.5 * (_rot_prev_w + drum.omega) * delta
	_rot_prev_tau = reaction_torque
	_rot_prev_w = drum.omega
	_rot_has_prev = true
	if absf(reaction_torque) > 0.001:
		drum.apply_torque(drum.axis_world() * reaction_torque)
	peak_tension = maxf(peak_tension, tension)
	_draw_rope()

	# 6) 滑轮：绳摩擦驱动（真实惯量 + μT R 上限）
	# 绳速沿绳一致（不可伸长）：v_rope = R_drum · ω_drum（收绳为正）。
	var v_rope: float = rope_speed()
	for i in range(nodes.size()):
		if str(nodes[i]["kind"]) == "pulley":
			var p: LISPulley = nodes[i]["pulley"] as LISPulley
			p.apply_rope_friction(v_rope, tension, delta)


## 绳沿自身的速度（m/s，收绳为正）。不可伸长绳上处处相同。
func rope_speed() -> float:
	if drum == null:
		return 0.0
	return LISWinchDrum.DRUM_RADIUS * drum.omega * wind_sign


## 建立可视化绳体（沿真实绳路绘制，纯显示，不参与受力）。
func _ensure_rope() -> void:
	if not build_visual:
		return
	if rope_mesh != null and is_instance_valid(rope_mesh):
		return
	rope_im = ImmediateMesh.new()
	rope_mesh = MeshInstance3D.new()
	rope_mesh.name = "RopeVisual"
	rope_mesh.mesh = rope_im
	rope_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rope_mat = StandardMaterial3D.new()
	rope_mat.albedo_color = Color(0.78, 0.68, 0.42)
	rope_mat.roughness = 0.9
	rope_mesh.material_override = rope_mat
	add_child(rope_mesh)


func _draw_rope() -> void:
	if not build_visual:
		return
	_ensure_rope()
	if rope_im == null:
		return
	rope_im.clear_surfaces()
	if cut_flag:
		return
	var pts: Array[Vector3] = []
	for i in range(nodes.size()):
		pts.append(_node_point(i))
	if pts.size() < 2:
		return
	rope_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in range(pts.size() - 1):
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var dir: Vector3 = b - a
		if dir.length() < 0.0001:
			continue
		var side: Vector3 = dir.normalized().cross(Vector3.UP)
		if side.length() < 0.001:
			side = dir.normalized().cross(Vector3.RIGHT)
		side = side.normalized() * ROPE_WIDTH * 0.5
		rope_im.surface_set_normal(Vector3.UP)
		rope_im.surface_add_vertex(a - side)
		rope_im.surface_set_normal(Vector3.UP)
		rope_im.surface_add_vertex(a + side)
		rope_im.surface_set_normal(Vector3.UP)
		rope_im.surface_add_vertex(b - side)
		rope_im.surface_set_normal(Vector3.UP)
		rope_im.surface_add_vertex(b + side)
	rope_im.surface_end()


## 剪断缆绳：立刻停止传递任何力。
func cut() -> void:
	cut_flag = true
	tension = 0.0
	reaction_torque = 0.0


## 复位：重新记录初始绳长与卷筒参考角。
##
## 这是"重置后重新建立有效约束"的关键 —— 历史 Bug 是复位把关节接线清空后
## 没有任何代码写回去，于是绳子永久断开却仍报告"连接正常"。
func reset_cable() -> void:
	cut_flag = false
	damp_work = 0.0
	rope_work_on_drum = 0.0
	_rot_has_prev = false
	_angle0 = drum.angle_rad if drum != null else 0.0
	take_in = 0.0
	path_length = _path_length()
	length0 = path_length
	if drum != null:
		drum.wind_sign = wind_sign
	length_allowed = length0
	_prev_seg.clear()
	_seg_speed.clear()
	for i in range(nodes.size() - 1):
		_prev_seg.append(_seg_len(i))
		_seg_speed.append(0.0)
	tension = 0.0
	max_strain = 0.0
	peak_tension = 0.0
	_prev_path = path_length
	_prev_allow = length_allowed


## 结构自检：节点是否都还在（供生命周期测试断言"没有残留无效对象"）。
func wiring_report() -> Dictionary:
	var dead: int = 0
	for n: Dictionary in nodes:
		var b: Variant = n["body"]
		if b is Node and not is_instance_valid(b as Node):
			dead += 1
		var a: Variant = n["anchor"]
		if a is Node and not is_instance_valid(a as Node):
			dead += 1
	return {"nodes": nodes.size(), "dead": dead, "drum_ok": drum != null and is_instance_valid(drum)}
