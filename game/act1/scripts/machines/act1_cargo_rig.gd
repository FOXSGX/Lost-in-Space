class_name Act1CargoRig
extends Node3D
## MECHANICS-001F · 真实货舱固定带与载重约束
##
## 结构（全部挂在**矿车**上，随矿车运动；矿车仍是 AnimatableBody3D 剧情运输体）：
##   真实货箱刚体（RigidBody3D，默认 100 kg，真实碰撞、真实摩擦）
##   货台四点锚点（两个固定挂钩 + 一个卷筒出口）
##   两条交叉固定带（每条 = 卷筒 → 货箱顶角 → 对角顶角 → 挂钩）
##   棘轮卷筒 + 棘爪 + 释放锁扣（1 自由度机构：力矩平衡 + 齿相位几何）
##
## 张力模型：每条带是一条**只能受拉**的弹性索，几何长度 L 由两端锚点与货物接触点决定，
## 静止长度 R 由卷筒卷绕量（take_up）决定：
##     T = max(0, k·(L − R)) + 阻尼项，并限制在 MAX_TENSION 之内
## 张力在真实接触点上以 `apply_force(force, offset)` 施加到货物刚体（含力矩）。
## 货物**从不**被直接设置位置或速度，也不冻结。
##
## 已知边界（如实记录）：
##   · 矿车是运动学体，固定带对锚点的反作用不会改变矿车轨迹；
##   · 棘轮/棘爪为 1 自由度机构仿真，不参与 Jolt 刚体求解（但它真实决定静止长度 R，
##     而 R 通过上面的受力模型真实影响货物）。

signal secured_changed(value: bool)

# ---------------------------------------------------------------- 几何（矿车局部）
const DECK_Y := 1.51
const CRATE_CENTER := Vector3(2.55, 1.91, -0.20)
const CRATE_HALF := Vector3(0.45, 0.40, 0.45)
const DRUM_ANCHOR := Vector3(3.95, 1.62, -0.20)
const HOOK_A := Vector3(1.50, 1.60, 0.66)
const HOOK_B := Vector3(1.50, 1.60, -1.06)
# 货箱顶四角（相对货箱中心）
const CORNER_NE := Vector3(0.45, 0.40, 0.45)
const CORNER_NW := Vector3(-0.45, 0.40, 0.45)
const CORNER_SE := Vector3(0.45, 0.40, -0.45)
const CORNER_SW := Vector3(-0.45, 0.40, -0.45)

# ---------------------------------------------------------------- 带与张力参数
const SLACK := 0.100            # 初始松弛量（米）：卷绕量小于它时张力恒为 0
const WIND_PER_CLICK := 0.020   # 每个棘轮行程的卷绕量（米）
const MAX_CLICKS := 8
const RELEASE_SLACK := 0.450    # 打开锁扣后额外放出的带长（米）：带子真正松脱
const UNWIND_SPEED := 0.10      # 回卷速度（米/秒）
const PAYOUT_SPEED := 0.50      # 放出带尾速度（米/秒）
const STRAP_K := 30000.0        # 单条带等效刚度 N/m（≈50 mm 聚酯带的量级）
const STRAP_C := 900.0          # 阻尼 N·s/m，仅受拉
const MAX_TENSION := 2600.0     # 额定张力上限（超载时张力被限制，视为屈服，不发散）
const SECURE_TENSION := 700.0   # 判定"已张紧"所需的最小张力（每条带）
const TAUT_EPS := 15.0          # 小于它视为松弛

# ---------------------------------------------------------------- 棘轮机构
const STROKE_SECONDS := 0.55
const STROKE_ANGLE := 1.35      # 手柄行程（弧度）
const PAWL_SECONDS := 0.12
const TOOTH_PITCH := PI / 4.0   # 卷筒 8 齿

const CRATE_MASS := 100.0
const CRATE_FRICTION := 0.16

var stage: Node
var cart: Node3D
var crate: RigidBody3D = null

var clicks := 0
var latch_open := false
var pawl_depth := 0.0
var lever_angle := 0.0
var drum_turns := 0.0
## 锁扣打开后从卷筒放出的自由带长（米）。它是"带子真的松脱了"的物理量：
## 只有它为 0（或很小）时，带子才可能在货物移动后立刻受力。
var payout := 0.0
var _stroke_t := 0.0
var _stroke_from := 0
var _unwind := 0.0

var _loops: Array = []          # [{a:Vector3(local), h:Vector3(local), c1:Vector3, c2:Vector3,
                                #   rest0:float, rest:float, tension:float, L:float, L_prev:float}]
var _prev_tension := 0.0
var _secured_now := false
var _pending_teleport := false
var _straps: Array = []         # MeshInstance3D 子段
var _drum_pivot: Node3D
var _pawl_mesh: Node3D
var _lever: Node3D
var _latch_lever: Node3D
var pump_point: Act1Interactable
var latch_point: Act1Interactable
var _mat_web: StandardMaterial3D
var _mat_steel: StandardMaterial3D
var _mat_amber: StandardMaterial3D
var _mat_crate: StandardMaterial3D


func setup(p_stage: Node, p_cart: Node3D) -> void:
	stage = p_stage
	cart = p_cart
	name = "CargoRig"
	p_cart.add_child(self)
	position = Vector3.ZERO
	_make_materials()
	_build_deck_hardware()
	_spawn_crate()
	_build_ratchet()
	_build_straps()
	_measure_rest_lengths()
	_build_interactables()


# ------------------------------------------------------------------ 材质与静态外观
func _make_materials() -> void:
	_mat_web = StandardMaterial3D.new()
	_mat_web.albedo_color = Color(0.10, 0.09, 0.08)
	_mat_web.roughness = 0.92
	_mat_web.metallic = 0.0
	_mat_steel = StandardMaterial3D.new()
	_mat_steel.albedo_color = Color(0.34, 0.35, 0.37)
	_mat_steel.roughness = 0.45
	_mat_steel.metallic = 0.80
	_mat_amber = StandardMaterial3D.new()
	_mat_amber.albedo_color = Color(0.72, 0.48, 0.10)
	_mat_amber.roughness = 0.42
	_mat_amber.metallic = 0.55
	_mat_crate = StandardMaterial3D.new()
	_mat_crate.albedo_color = Color(0.36, 0.30, 0.20)
	_mat_crate.roughness = 0.78


func _mesh_box(size: Vector3, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return mi


func _mesh_cyl(radius: float, height: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 14
	mi.mesh = cm
	mi.material_override = mat
	return mi


## 货台上的真实锚点硬件：两个 D 形挂环 + 卷筒底座。全部是矿车局部坐标的可见实体。
func _build_deck_hardware() -> void:
	for entry in [[HOOK_A, "AnchorHookA"], [HOOK_B, "AnchorHookB"]]:
		var p: Vector3 = entry[0]
		var base := _mesh_box(Vector3(0.16, 0.06, 0.20), _mat_steel, p - Vector3(0, 0.05, 0))
		add_child(base)
		var ring := _mesh_cyl(0.055, 0.05, _mat_steel)
		ring.rotation.x = PI * 0.5
		ring.position = p
		add_child(ring)
		var bolt := _mesh_box(Vector3(0.05, 0.10, 0.05), _mat_amber, p + Vector3(0, -0.09, 0))
		add_child(bolt)
	# 卷筒底座
	add_child(_mesh_box(Vector3(0.34, 0.12, 0.42), _mat_steel, DRUM_ANCHOR + Vector3(0, -0.10, 0)))
	add_child(_mesh_box(Vector3(0.06, 0.30, 0.06), _mat_steel, DRUM_ANCHOR + Vector3(0.14, 0.02, 0.16)))
	add_child(_mesh_box(Vector3(0.06, 0.30, 0.06), _mat_steel, DRUM_ANCHOR + Vector3(0.14, 0.02, -0.16)))
	# 货舱作业灯：货舱在车厢内部，原场景只有车顶灯，带体细节看不清。
	# 这是真实的车上工作灯（有灯罩实体），不是悬浮提示文字。
	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.albedo_color = Color(0.95, 0.86, 0.62)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1.0, 0.88, 0.60)
	lamp_mat.emission_energy_multiplier = 1.4
	var housing := _mesh_box(Vector3(0.26, 0.10, 0.16), _mat_steel, DRUM_ANCHOR + Vector3(-0.30, 0.62, -0.34))
	add_child(housing)
	var lens := _mesh_box(Vector3(0.22, 0.04, 0.12), lamp_mat, DRUM_ANCHOR + Vector3(-0.30, 0.56, -0.34))
	add_child(lens)
	var work_lamp := OmniLight3D.new()
	work_lamp.name = "CargoWorkLamp"
	work_lamp.position = DRUM_ANCHOR + Vector3(-0.40, 0.52, -0.42)
	work_lamp.light_color = Color(1.0, 0.90, 0.68)
	work_lamp.light_energy = 2.1
	work_lamp.omni_range = 5.0
	work_lamp.shadow_enabled = false
	add_child(work_lamp)


func _spawn_crate() -> void:
	crate = RigidBody3D.new()
	crate.name = "CargoCrate"
	crate.mass = CRATE_MASS
	crate.linear_damp = 0.05
	crate.angular_damp = 0.20
	crate.continuous_cd = true
	# 层：4（与玩家可碰撞的实体层）。掩码刻意**不含**玩家层 2：
	# 实测（001F 第 3 次最小复现）若掩码含玩家层，角色行走会把 100 kg 货箱推走 6.9 m；
	# 不含时角色被货箱真实挡住（dist 0.90 m），货箱纹丝不动。也不含交互点层 8。
	crate.collision_layer = 4
	crate.collision_mask = 1 | 4 | 16
	crate.contact_monitor = true
	crate.max_contacts_reported = 8
	var pm := PhysicsMaterial.new()
	pm.friction = CRATE_FRICTION
	pm.bounce = 0.0
	crate.physics_material_override = pm
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = CRATE_HALF * 2.0
	cs.shape = bs
	crate.add_child(cs)
	var body := _mesh_box(CRATE_HALF * 2.0, _mat_crate, Vector3.ZERO)
	crate.add_child(body)
	# 箱体加固带（视觉，不是固定带本身）
	for sx in [-1.0, 1.0]:
		var rib := _mesh_box(Vector3(0.06, CRATE_HALF.y * 2.02, CRATE_HALF.z * 2.02), _mat_steel, Vector3(sx * (CRATE_HALF.x - 0.10), 0, 0))
		crate.add_child(rib)
	for sz in [-1.0, 1.0]:
		var rib2 := _mesh_box(Vector3(CRATE_HALF.x * 2.02, CRATE_HALF.y * 2.02, 0.06), _mat_steel, Vector3(0, 0, sz * (CRATE_HALF.z - 0.10)))
		crate.add_child(rib2)
	var plate := _mesh_box(Vector3(0.30, 0.16, 0.24), _mat_amber, Vector3(0, 0, CRATE_HALF.z + 0.01))
	crate.add_child(plate)
	stage.add_child(crate)
	crate.global_position = global_transform * CRATE_CENTER


func _build_ratchet() -> void:
	var housing := Node3D.new()
	housing.name = "RatchetHousing"
	housing.position = DRUM_ANCHOR
	add_child(housing)
	housing.add_child(_mesh_box(Vector3(0.26, 0.34, 0.30), _mat_steel, Vector3(0, 0.06, 0)))
	_drum_pivot = Node3D.new()
	_drum_pivot.name = "DrumPivot"
	_drum_pivot.position = Vector3(0, 0.10, 0)
	housing.add_child(_drum_pivot)
	var drum := _mesh_cyl(0.062, 0.22, _mat_steel)
	drum.rotation.z = PI * 0.5
	_drum_pivot.add_child(drum)
	# 卷筒齿盘（8 齿，棘爪落点）
	var disc := _mesh_cyl(0.082, 0.03, _mat_amber)
	disc.rotation.z = PI * 0.5
	disc.position = Vector3(0.09, 0, 0)
	_drum_pivot.add_child(disc)
	for k in range(8):
		var ang := float(k) * TAU / 8.0
		var tooth := _mesh_box(Vector3(0.02, 0.035, 0.022), _mat_amber, Vector3(0.09, cos(ang) * 0.092, sin(ang) * 0.092))
		tooth.rotation.x = -ang
		_drum_pivot.add_child(tooth)
	# 手柄
	_lever = Node3D.new()
	_lever.name = "TensionLever"
	_lever.position = Vector3(0.16, 0.10, 0)
	housing.add_child(_lever)
	_lever.add_child(_mesh_box(Vector3(0.05, 0.42, 0.05), _mat_amber, Vector3(0, 0.21, 0)))
	_lever.add_child(_mesh_box(Vector3(0.08, 0.10, 0.10), _mat_steel, Vector3(0, 0.44, 0)))
	# 棘爪
	_pawl_mesh = Node3D.new()
	_pawl_mesh.name = "Pawl"
	_pawl_mesh.position = Vector3(0.09, 0.16, 0)
	housing.add_child(_pawl_mesh)
	var pawl := _mesh_box(Vector3(0.05, 0.16, 0.035), _mat_amber, Vector3(0, -0.08, 0))
	_pawl_mesh.add_child(pawl)
	# 释放锁扣手柄
	_latch_lever = Node3D.new()
	_latch_lever.name = "LatchRelease"
	_latch_lever.position = Vector3(-0.10, 0.20, 0.14)
	housing.add_child(_latch_lever)
	_latch_lever.add_child(_mesh_box(Vector3(0.05, 0.24, 0.05), _mat_steel, Vector3(0, 0.10, 0)))
	_latch_lever.add_child(_mesh_box(Vector3(0.09, 0.06, 0.06), _mat_amber, Vector3(0, 0.24, 0)))


func _build_straps() -> void:
	# 每条带 3 段 × 3 子段，用细长方体拼出可见带体；形状随张力变化（松弛时下垂）
	for i in range(2):
		var segs: Array = []
		for s in range(3):
			var subs: Array = []
			for k in range(3):
				var mi := _mesh_box(Vector3(0.075, 0.020, 1.0), _mat_web, Vector3.ZERO)
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(mi)
				subs.append(mi)
			segs.append(subs)
		_straps.append(segs)


func _measure_rest_lengths() -> void:
	_loops.clear()
	for spec in [
		[DRUM_ANCHOR, CORNER_SE, CORNER_NW, HOOK_A],
		[DRUM_ANCHOR, CORNER_NE, CORNER_SW, HOOK_B],
	]:
		_loops.append({
			"a": spec[0], "c1": spec[1], "c2": spec[2], "h": spec[3],
			"rest": 0.0, "tension": 0.0, "L": 0.0, "L_prev": 0.0,
		})
	for lp in _loops:
		lp["L"] = _loop_length(lp)
		lp["L_prev"] = lp["L"]
		lp["rest"] = float(lp["L"]) + SLACK


func _world(local_pt: Vector3) -> Vector3:
	return global_transform * local_pt


## 当前几何长度（米）：卷筒 → 顶角1 → 顶角2 → 挂钩
func _loop_length(lp: Dictionary) -> float:
	var a := _world(lp["a"])
	var h := _world(lp["h"])
	if crate == null or not is_instance_valid(crate):
		return a.distance_to(h)
	var xf := crate.global_transform
	var p1: Vector3 = xf * (lp["c1"] as Vector3)
	var p2: Vector3 = xf * (lp["c2"] as Vector3)
	return a.distance_to(p1) + p1.distance_to(p2) + p2.distance_to(h)


func _loop_points(lp: Dictionary) -> Array:
	var a := _world(lp["a"])
	var h := _world(lp["h"])
	if crate == null or not is_instance_valid(crate):
		return [a, a.lerp(h, 0.33), a.lerp(h, 0.67), h]
	var xf := crate.global_transform
	return [a, xf * (lp["c1"] as Vector3), xf * (lp["c2"] as Vector3), h]


# ------------------------------------------------------------------ 机构状态
func take_up() -> float:
	return float(clicks) * WIND_PER_CLICK


## 当前静止长度 R = 初始几何长度 + 初始松弛 + 放出量 − 卷绕量
func rest_length(lp: Dictionary) -> float:
	return float(lp["rest"]) + payout - take_up()


func pawl_engaged() -> bool:
	return pawl_depth > 0.95 and not latch_open


func tension() -> float:
	var t := INF
	if _loops.is_empty():
		return 0.0
	for lp in _loops:
		t = minf(t, float(lp["tension"]))
	return 0.0 if t == INF else t


func loop_tensions() -> Array:
	var out: Array = []
	for lp in _loops:
		out.append(snappedf(float(lp["tension"]), 0.1))
	return out


func lever_busy() -> bool:
	return _stroke_t > 0.0


## 货物是否仍在货台有效固定区域、且没有明显倾倒
func crate_in_zone() -> bool:
	if crate == null or not is_instance_valid(crate):
		return false
	var local := to_local(crate.global_position)
	var flat := Vector2(local.x - CRATE_CENTER.x, local.z - CRATE_CENTER.z).length()
	var up := crate.global_transform.basis.y.normalized()
	return flat < 0.55 and local.y > DECK_Y + 0.25 and local.y < DECK_Y + 1.10 and up.dot(Vector3.UP) > 0.72


func anchors_attached() -> bool:
	# 锚点是矿车上的实体硬件；只要矿车与货箱都在，几何就是有效的
	return cart != null and is_instance_valid(cart) and crate != null and is_instance_valid(crate)


## 发车联锁读取的唯一真值来源
func secured() -> bool:
	if not anchors_attached() or not crate_in_zone():
		return false
	if latch_open or not pawl_engaged():
		return false
	if clicks < 1:
		return false
	if tension() < SECURE_TENSION:
		return false
	return true


# ------------------------------------------------------------------ 玩家操作
## E：启动一个棘轮张紧行程（真实改变卷绕量 → 真实改变静止长度 R）
func pump() -> bool:
	if _stroke_t > 0.0:
		return false
	if clicks >= MAX_CLICKS:
		return false
	if not crate_in_zone():
		return false
	latch_open = false
	pawl_depth = 0.0
	if payout > 0.0:
		# Re-baseline rest lengths to current geometry before clearing payout so
		# releasing then pumping never creates a single-frame 0.45 m snap launch.
		_measure_rest_lengths()
		payout = 0.0
	_unwind = 0.0
	_stroke_from = clicks
	_stroke_t = STROKE_SECONDS
	return true


## E：释放锁扣（棘爪抬起，卷筒在张力下真实回卷）
func open_latch() -> bool:
	if latch_open:
		return false
	if clicks <= 0:
		return false
	latch_open = true
	pawl_depth = 0.0
	_stroke_t = 0.0
	lever_angle = 0.0
	return true


func reset_cargo() -> void:
	clicks = 0
	latch_open = false
	pawl_depth = 1.0
	lever_angle = 0.0
	drum_turns = 0.0
	payout = 0.0
	_stroke_t = 0.0
	_unwind = 0.0
	if crate != null and is_instance_valid(crate):
		crate.linear_velocity = Vector3.ZERO
		crate.angular_velocity = Vector3.ZERO
		crate.global_position = global_transform * CRATE_CENTER
		crate.global_rotation = Vector3.ZERO
		# 刚体的传送必须在物理步内生效，否则会被上一帧的物理状态覆盖
		_pending_teleport = true
	_measure_rest_lengths()
	for lp in _loops:
		lp["tension"] = 0.0
	_prev_tension = 0.0
	_secured_now = false
	_update_visuals()


# ------------------------------------------------------------------ 物理
func _physics_process(delta: float) -> void:
	if crate == null or not is_instance_valid(crate):
		return
	if _pending_teleport:
		_pending_teleport = false
		crate.global_position = global_transform * CRATE_CENTER
		crate.global_rotation = Vector3.ZERO
		crate.linear_velocity = Vector3.ZERO
		crate.angular_velocity = Vector3.ZERO
		_measure_rest_lengths()
	_advance_mechanism(delta)
	_apply_strap_forces(delta)
	_update_visuals()
	var s := secured()
	if s != _secured_now:
		_secured_now = s
		secured_changed.emit(s)


func _advance_mechanism(delta: float) -> void:
	if _stroke_t > 0.0:
		_stroke_t = maxf(0.0, _stroke_t - delta)
		var f: float = 1.0 - _stroke_t / STROKE_SECONDS
		lever_angle = f * STROKE_ANGLE
		drum_turns = (float(_stroke_from) + f) * TOOTH_PITCH
		if _stroke_t <= 0.0:
			clicks = mini(MAX_CLICKS, _stroke_from + 1)
			lever_angle = 0.0
			drum_turns = float(clicks) * TOOTH_PITCH
			pawl_depth = 0.0
	else:
		if latch_open:
			# 锁扣打开：卷筒被张力带着回卷，卷绕量真实减少；回卷到底后带尾被拉出，
			# 额外放出自由带长，带子真正松脱（货物恢复自由）。
			if clicks > 0:
				_unwind += UNWIND_SPEED * delta
				if _unwind >= WIND_PER_CLICK:
					_unwind -= WIND_PER_CLICK
					clicks = maxi(0, clicks - 1)
				if clicks <= 0:
					_unwind = 0.0
			else:
				payout = minf(RELEASE_SLACK, payout + PAYOUT_SPEED * delta)
			drum_turns = (float(clicks) - _unwind / WIND_PER_CLICK) * TOOTH_PITCH
			pawl_depth = 0.0
		else:
			if pawl_depth < 1.0:
				pawl_depth = minf(1.0, pawl_depth + delta / PAWL_SECONDS)
			drum_turns = float(clicks) * TOOTH_PITCH


func _apply_strap_forces(delta: float) -> void:
	if delta <= 0.0:
		return
	for lp in _loops:
		var pts := _loop_points(lp)
		var L: float = pts[0].distance_to(pts[1]) + pts[1].distance_to(pts[2]) + pts[2].distance_to(pts[3])
		var rest: float = rest_length(lp)
		var ext: float = L - rest
		var td := 0.0
		if ext > 0.0:
			var rate: float = (L - float(lp["L_prev"])) / delta
			td = clampf(STRAP_K * ext + STRAP_C * maxf(0.0, rate), 0.0, MAX_TENSION)
		lp["L_prev"] = L
		lp["L"] = L
		lp["tension"] = td
		if td <= TAUT_EPS:
			continue
		if not anchors_attached():
			continue
		# 接触点受力：只受拉，方向由几何决定（不存在"刚性杆推走货物"）
		# 注意：crate_in_zone() 仅作通关/HUD 判定，不切断物理束缚——否则货箱刚滑出一点就彻底松脱。
		var p1: Vector3 = pts[1]
		var p2: Vector3 = pts[2]
		var f1: Vector3 = (pts[0] - p1).normalized() * td + (p2 - p1).normalized() * td
		var f2: Vector3 = (p1 - p2).normalized() * td + (pts[3] - p2).normalized() * td
		crate.apply_force(f1, p1 - crate.global_position)
		crate.apply_force(f2, p2 - crate.global_position)
	_prev_tension = tension()


# ------------------------------------------------------------------ 外观
func _update_visuals() -> void:
	if _lever == null:
		return
	_lever.rotation.x = lever_angle
	_drum_pivot.rotation.x = drum_turns
	_pawl_mesh.position.z = 0.0 + 0.055 * pawl_depth
	_pawl_mesh.rotation.x = deg_to_rad(28.0) * (1.0 - pawl_depth)
	_latch_lever.rotation.z = deg_to_rad(-40.0) if latch_open else 0.0
	for i in range(_loops.size()):
		var pts := _loop_points(_loops[i])
		var slack: float = maxf(0.0, rest_length(_loops[i]) - float(_loops[i]["L"]))
		for s in range(3):
			var p: Vector3 = pts[s]
			var q: Vector3 = pts[s + 1]
			var sag: float = minf(0.22, slack * 1.1)
			for k in range(3):
				_straps[i][s][k].global_transform = _subsegment_xform(p, q, sag, k)


## 把一段带体拆成 3 个子段；松弛时控制点下垂，张紧时拉直
func _subsegment_xform(p: Vector3, q: Vector3, sag: float, k: int) -> Transform3D:
	var a := _bezier(p, q, sag, float(k) / 3.0)
	var b := _bezier(p, q, sag, float(k + 1) / 3.0)
	var mid := (a + b) * 0.5
	var dir := b - a
	var length := dir.length()
	if length < 0.0001:
		return Transform3D(Basis.IDENTITY, mid)
	var y := dir.normalized()
	var ref := Vector3.UP if absf(y.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	var z := x.cross(y).normalized()
	return Transform3D(Basis(x, y, z), mid).scaled_local(Vector3(1.0, 1.0, length))


func _bezier(p: Vector3, q: Vector3, sag: float, t: float) -> Vector3:
	var ctrl := (p + q) * 0.5 + Vector3.DOWN * (sag * 2.0)
	var u := 1.0 - t
	return p * (u * u) + ctrl * (2.0 * u * t) + q * (t * t)


# ------------------------------------------------------------------ 交互点
func _build_interactables() -> void:
	pump_point = Act1Interactable.new()
	pump_point.stage = stage
	pump_point.setup("cargo", "E 操作货舱棘轮张紧固定带", Vector3(0.55, 0.60, 0.55))
	add_child(pump_point)
	pump_point.position = DRUM_ANCHOR + Vector3(0.02, 0.10, 0.0)
	pump_point.prompt_callable = Callable(stage, "_cargo_prompt")
	pump_point.add_focus_marker(0.20)
	stage.interactables["cargo"] = pump_point

	latch_point = Act1Interactable.new()
	latch_point.stage = stage
	latch_point.setup("cargo_latch", "E 释放货舱固定带锁扣", Vector3(0.30, 0.34, 0.30))
	add_child(latch_point)
	latch_point.position = DRUM_ANCHOR + Vector3(-0.10, 0.30, 0.16)
	latch_point.prompt_callable = Callable(stage, "_cargo_latch_prompt")
	latch_point.add_focus_marker(0.14)
	stage.interactables["cargo_latch"] = latch_point
	latch_point.set_interaction_enabled(false)


# ------------------------------------------------------------------ 提示与快照
func prompt_pump() -> String:
	if secured():
		return "E 继续收紧固定带（张力 %d N / 已锁定）" % int(round(tension()))
	if crate == null or not is_instance_valid(crate):
		return "货舱内没有货物"
	if not crate_in_zone():
		return "货物没有摆正在货台上 · 固定带扣不上"
	if lever_busy():
		return "棘轮正在收紧 · 张力 %d N" % int(round(tension()))
	if clicks >= MAX_CLICKS:
		return "棘轮已到行程末端 · 张力 %d N" % int(round(tension()))
	if clicks == 0:
		return "E 操作棘轮张紧固定带（当前松弛）"
	return "E 继续收紧（%d/%d 齿 · 张力 %d N / 需 ≥%d N）" % [
		clicks, MAX_CLICKS, int(round(tension())), int(round(SECURE_TENSION))]


func prompt_latch() -> String:
	if clicks <= 0:
		return ""
	if latch_open:
		return "固定带锁扣已打开 · 带体已放松"
	return "E 释放固定带锁扣（张力 %d N）" % int(round(tension()))


func snapshot() -> Dictionary:
	var pts: Array = []
	if not _loops.is_empty():
		for p in _loop_points(_loops[0]):
			pts.append([snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001)])
	return {
		"mass": CRATE_MASS if crate != null else 0.0,
		"crate_pos": crate.global_position if crate != null else Vector3.ZERO,
		"crate_local": to_local(crate.global_position) if crate != null else Vector3.ZERO,
		"crate_vel": crate.linear_velocity if crate != null else Vector3.ZERO,
		"tension": tension(),
		"tensions": loop_tensions(),
		"clicks": clicks,
		"take_up": take_up(),
		"payout": payout,
		"rest_length": 0.0 if _loops.is_empty() else rest_length(_loops[0]),
		"pawl": pawl_depth,
		"latch_open": latch_open,
		"secured": secured(),
		"anchor": DRUM_ANCHOR,
		"anchor_world": _world(DRUM_ANCHOR),
		"strap0": pts,
	}
