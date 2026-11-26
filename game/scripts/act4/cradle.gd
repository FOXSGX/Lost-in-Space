class_name ResonanceCradle
extends Node3D
## Mechanical cradle for a carryable resonance crystal.
##
## MECHANICS-004A（本轮改造）：
##   改造前：`seat()` 直接把晶体 `global_position` 设到座位、`freeze = true`、
##   关掉碰撞，然后按 yaw 判一个 `aligned` 布尔。晶体从来没有被任何机构夹住，
##   “安装”是传送 + 冻结。
##
##   现在：底座上有一个真实的承托面（StaticBody），叉口是两只可动的锁爪
##   （各带 StaticBody，沿叉口的局部 x 滑动）。玩家把晶体丢进叉口，它靠重力
##   落座；然后按 E 启动螺杆，两只爪一起向内合拢，停在晶体表面（最多 2 mm 压入），
##   棘爪落位后 `locked()` 才为真。晶体全程是真实刚体（不冻结、碰撞不关闭）。
##
##   机械模型（1 自由度对称夹钳，带明确行程/限位/接触）：
##     jaw_x：0.62（张开）→ 0.26（硬止挡），速率 0.22 m/s
##     接触限位：晶体半径 0.34 + 爪半厚 0.07 − 0.002
##     只有“爪压到晶体 + 晶体在叉口里 + yaw 对位”三条同时成立才锁定。
##
##   边界：爪是运动学执行器（带真实碰撞体的 StaticBody），螺杆没有做柔性扭矩
##   求解；晶体的保持来自接触（爪 + 承托面），不是冻结。

signal seated(cradle: ResonanceCradle, crystal: PortableCrystal, aligned: bool)
signal released(cradle: ResonanceCradle)

const TILT_ANGLE := 0.34
const CRYSTAL_RADIUS := 0.34
const JAW_HALF := 0.07
const JAW_OPEN := 0.62
const JAW_STOP := 0.26
const PEN_ALLOW := 0.002
const JAW_RATE := 0.22
const SEAT_Y := 0.38
const POCKET_XZ := 0.30
const POCKET_Y := 0.26

var cradle_id: String = ""
var target_node_id: String = ""
var required_yaw_deg: float = 0.0
var tolerance_deg: float = 30.0
var occupied: PortableCrystal = null
var aligned: bool = false
var jaw_x: float = JAW_OPEN
var jaw_motor: bool = false
var jaw_floor: float = JAW_STOP
var retracting: bool = false
var pressing: bool = false
var latched: bool = false
var blocked: bool = false

var _indicator: MeshInstance3D
var _indicator_light: OmniLight3D
var _prong_root: Node3D
var _base_material: StandardMaterial3D
var _ring: MeshInstance3D
var _arrow: MeshInstance3D
## 箭头材质的私有副本：只建一次，之后只改颜色。
## 旧写法每物理帧 `duplicate()` 一个新 StandardMaterial3D（60 次/秒）。
var _arrow_material: StandardMaterial3D
var _indicator_color: Color = Color(-1.0, -1.0, -1.0)
var _indicator_energy: float = -1.0
var _jaws: Array[Node3D] = []
var _jaw_bodies: Array[StaticBody3D] = []
var _pawl: Node3D


func build(id_value: String, yaw_degrees: float, target_id: String = "") -> void:
	cradle_id = id_value
	required_yaw_deg = yaw_degrees
	target_node_id = target_id

	_base_material = MaterialLibrary.metal(Color(0.34, 0.37, 0.41), 0.44, 0.82)
	var dark: StandardMaterial3D = MaterialLibrary.metal(Color(0.13, 0.14, 0.16), 0.62, 0.55)
	var brass: StandardMaterial3D = MaterialLibrary.metal(Color(0.60, 0.44, 0.19), 0.38, 0.82)
	var rust: StandardMaterial3D = MaterialLibrary.metal(Color(0.38, 0.21, 0.11), 0.82, 0.3)
	var warning: StandardMaterial3D = MaterialLibrary.painted(Color(0.86, 0.55, 0.10), 0.55)

	# 底座：两层倒角盘 + 螺栓环（原样保留）
	BuildKit.cylinder_visual(self, "BaseLower", 0.74, 0.10, Vector3(0.0, 0.05, 0.0), dark, Vector3.ZERO, 0.68)
	var base_lip: MeshInstance3D = BuildKit.cylinder_visual(self, "BaseLip", 0.66, 0.16, Vector3(0.0, 0.16, 0.0), _base_material, Vector3.ZERO, 0.62)
	base_lip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	BuildKit.cylinder_visual(self, "BaseTrim", 0.60, 0.035, Vector3(0.0, 0.245, 0.0), brass)
	for index: int in range(8):
		var angle: float = TAU * float(index) / 8.0
		BuildKit.cylinder_visual(self, "BaseBolt%d" % index, 0.028, 0.045,
			Vector3(cos(angle) * 0.555, 0.258, sin(angle) * 0.555), rust)
	BuildKit.box_visual(self, "BaseStripe", Vector3(0.40, 0.02, 0.055), Vector3(0.0, 0.255, -0.53), warning)
	BuildKit.cylinder_visual(self, "CableGland", 0.045, 0.14, Vector3(0.0, 0.10, 0.60), dark, Vector3(90.0, 0.0, 0.0))
	BuildKit.cylinder_visual(self, "CableTail", 0.026, 0.45, Vector3(0.0, 0.04, 0.82), dark, Vector3(90.0, 0.0, 0.0))
	BuildKit.cylinder_visual(self, "Collar", 0.40, 0.13, Vector3(0.0, 0.315, 0.0), dark)
	BuildKit.cylinder_visual(self, "CollarLip", 0.34, 0.05, Vector3(0.0, 0.40, 0.0), _base_material)

	# 承托面：真实 StaticBody。晶体靠重力站在这里，而不是被传送到坐标。
	var floor_body: StaticBody3D = StaticBody3D.new()
	floor_body.name = "SeatFloor"
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var floor_shape: BoxShape3D = BoxShape3D.new()
	floor_shape.size = Vector3(0.92, 0.06, 0.92)
	var floor_collider: CollisionShape3D = CollisionShape3D.new()
	floor_collider.shape = floor_shape
	floor_body.add_child(floor_collider)
	add_child(floor_body)
	floor_body.position = Vector3(0.0, SEAT_Y - 0.03, 0.0)

	# 叉口根节点随 required yaw 旋转（视觉朝向与机械夹持方向一致）
	_prong_root = Node3D.new()
	_prong_root.name = "Fork"
	_prong_root.position = Vector3(0.0, 0.38, 0.0)
	add_child(_prong_root)

	# 两只锁爪：枢轴 + 爪体网格 + StaticBody 碰撞体
	for index: int in range(2):
		var side: float = -1.0 if index == 0 else 1.0
		var pivot: Node3D = Node3D.new()
		pivot.name = "Jaw_%d" % index
		pivot.position = Vector3(side * JAW_OPEN, 0.13, -0.22)
		_prong_root.add_child(pivot)
		_jaws.append(pivot)
		var jaw_mesh: MeshInstance3D = BuildKit.box_visual(pivot, "JawBody%d" % index,
			Vector3(0.14, 0.30, 0.52), Vector3.ZERO, _base_material)
		jaw_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		BuildKit.box_visual(pivot, "JawPad%d" % index, Vector3(0.015, 0.16, 0.34),
			Vector3(-side * 0.072, 0.0, -0.02), warning)
		var body: StaticBody3D = StaticBody3D.new()
		body.name = "JawCollider%d" % index
		body.collision_layer = 1
		body.collision_mask = 0
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = Vector3(0.14, 0.30, 0.52)
		var collider: CollisionShape3D = CollisionShape3D.new()
		collider.shape = shape
		body.add_child(collider)
		pivot.add_child(body)
		_jaw_bodies.append(body)

	# 中央导槽 + 地板箭头（原样保留）
	BuildKit.box_visual(_prong_root, "GuideTongue", Vector3(0.085, 0.045, 0.60), Vector3(0.0, 0.055, -0.28), brass)
	BuildKit.box_visual(_prong_root, "GuideGlow", Vector3(0.035, 0.008, 0.52), Vector3(0.0, 0.080, -0.30),
		MaterialLibrary.emissive(Color(0.95, 0.62, 0.20), 0.9))
	_arrow = BuildKit.box_visual(_prong_root, "AimArrow", Vector3(0.20, 0.006, 0.46), Vector3(0.0, -0.365, -0.66),
		MaterialLibrary.emissive(Color(0.95, 0.60, 0.18), 0.55))
	BuildKit.box_visual(_prong_root, "AimArrowHeadA", Vector3(0.075, 0.006, 0.18), Vector3(-0.075, -0.365, -0.92),
		MaterialLibrary.emissive(Color(0.95, 0.60, 0.18), 0.55), Vector3(0.0, 38.0, 0.0))
	BuildKit.box_visual(_prong_root, "AimArrowHeadB", Vector3(0.075, 0.006, 0.18), Vector3(0.075, -0.365, -0.92),
		MaterialLibrary.emissive(Color(0.95, 0.60, 0.18), 0.55), Vector3(0.0, -38.0, 0.0))

	# 棘爪（锁定后落进齿槽，视觉上说明“已经锁住”）
	_pawl = Node3D.new()
	_pawl.name = "Pawl"
	_pawl.position = Vector3(0.0, 0.30, -0.55)
	add_child(_pawl)
	BuildKit.box_visual(_pawl, "PawlBar", Vector3(0.08, 0.16, 0.10), Vector3.ZERO, brass)

	# 导向环与状态灯
	_ring = MeshInstance3D.new()
	_ring.name = "GuideRing"
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.395
	torus.outer_radius = 0.425
	torus.rings = 24
	torus.ring_segments = 6
	_ring.mesh = torus
	_ring.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	_ring.position = Vector3(0.0, 0.47, 0.0)
	_ring.material_override = MaterialLibrary.emissive(Color(0.55, 0.36, 0.12), 0.65)
	add_child(_ring)

	_indicator = BuildKit.sphere_visual(self, "Indicator", 0.062, Vector3(0.0, 0.48, 0.42), MaterialLibrary.emissive(Color(1.0, 0.55, 0.18), 1.4))
	_indicator.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_indicator_light = BuildKit.omni_light(self, "IndicatorLight", Vector3(0.0, 0.58, 0.40), Color(1.0, 0.55, 0.18), 0.55, 2.2, false)
	_prong_root.rotation.y = deg_to_rad(required_yaw_deg)
	add_to_group("cradle")
	add_to_group("interactable")
	_apply_jaws()
	_update_indicator_state()


func set_required_yaw(yaw_degrees: float) -> void:
	required_yaw_deg = yaw_degrees
	if _prong_root != null:
		_prong_root.rotation.y = deg_to_rad(required_yaw_deg)


func get_seat_position() -> Vector3:
	return global_position + Vector3(0.0, SEAT_Y, 0.0)


func get_interaction_position() -> Vector3:
	return global_position + Vector3(0.0, 0.75, 0.0)


func is_occupied() -> bool:
	return occupied != null


func get_interaction_prompt(_player: Node) -> String:
	if latched:
		return "E 松开锁爪 · 取晶体按 F"
	if occupied == null:
		return "叉口空着 · 把晶体丢进叉口，再按 E 合拢锁爪"
	if jaw_motor:
		return "锁爪行程中…"
	return "E 合拢锁爪 · 夹住晶体"


func interact(_player: Node) -> void:
	if jaw_motor:
		return
	if latched:
		open_clamp()
		return
	jaw_motor = true
	retracting = false


func _physics_process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	var inside: bool = crystal_inside()
	jaw_floor = _jaw_floor_for_occupied() if inside else JAW_STOP
	# A crystal that sits off-centre needs the jaws to stop further out. If the
	# required opening exceeds JAW_OPEN the jaws simply cannot reach it: do not
	# pretend to press (which used to drive the jaw 0.30 m into the crystal and
	# let Jolt eject it), and do not latch.
	var reachable: bool = jaw_floor < JAW_OPEN - 0.01
	pressing = inside and reachable and jaw_x <= jaw_floor + 0.006
	blocked = inside and not reachable
	if jaw_motor:
		if retracting:
			jaw_x = minf(JAW_OPEN, jaw_x + JAW_RATE * delta)
			if jaw_x >= JAW_OPEN - 0.0005:
				jaw_x = JAW_OPEN
				retracting = false
				jaw_motor = false
		else:
			if jaw_x > jaw_floor:
				jaw_x = maxf(jaw_floor, jaw_x - JAW_RATE * delta)
			if jaw_x <= jaw_floor + 0.0005:
				jaw_motor = false
				if inside and pressing:
					_latch()
	if latched:
		_ensure_still_locked()
	_apply_jaws()
	_update_indicator_state()


## Jaw travel that keeps a 2 mm preload on the crystal actually present.
## The old form assumed the crystal was perfectly centred, so a crystal that
## landed 0.30 m off-centre (POCKET_XZ) was overlapped by 0.30 m and ejected by
## Jolt's penetration recovery when the jaws closed.
func _jaw_floor_for_occupied() -> float:
	var offset: float = 0.0
	if occupied != null and is_instance_valid(occupied):
		offset = absf(to_local(occupied.global_position).x)
	return clampf(offset + CRYSTAL_RADIUS + JAW_HALF - PEN_ALLOW, JAW_STOP, JAW_OPEN)


func _apply_jaws() -> void:
	for index: int in range(_jaws.size()):
		var side: float = -1.0 if index == 0 else 1.0
		_jaws[index].position.x = side * jaw_x
	if _pawl != null:
		_pawl.visible = latched
		_pawl.rotation.x = 0.0 if latched else -0.6


func open_clamp() -> void:
	if jaw_motor:
		return
	latched = false
	aligned = false
	retracting = true
	jaw_motor = true


func _latch() -> void:
	latched = true
	aligned = _yaw_aligned()
	if occupied != null:
		occupied.is_seated = true
		occupied.cradle = self
		occupied.set_visual_tilt(0.0 if aligned else TILT_ANGLE)
	seated.emit(self, occupied, aligned)


func crystal_inside() -> bool:
	if occupied == null or not is_instance_valid(occupied):
		return false
	return contains_crystal(occupied)


# 给定晶体是否落在叉口内部（不依赖占用状态，供晶体自己判断）
func contains_crystal(crystal: Node3D) -> bool:
	if crystal == null or not is_instance_valid(crystal):
		return false
	var local: Vector3 = to_local(crystal.global_position)
	return Vector2(local.x, local.z).length() <= POCKET_XZ and absf(local.y - SEAT_Y) <= POCKET_Y


func _yaw_aligned() -> bool:
	if occupied == null:
		return false
	var difference: float = absf(rad_to_deg(angle_difference(deg_to_rad(required_yaw_deg), deg_to_rad(occupied.held_yaw_deg))))
	return difference <= tolerance_deg


func _ensure_still_locked() -> void:
	if occupied == null or not is_instance_valid(occupied):
		latched = false
		aligned = false
		return
	if not crystal_inside():
		latched = false
		aligned = false


func locked() -> bool:
	return latched and occupied != null and is_instance_valid(occupied) \
		and crystal_inside() and _yaw_aligned()


# 供 PortableCrystal 调用：晶体落进叉口后登记占用（不再传送/冻结）
# 返回值语义 = “是否登记成功”，**不是** aligned。
# 对齐与否由 `_latch()`（锁爪真的夹住那刻）决定，见 `aligned` / `locked()`。
func seat(crystal: PortableCrystal, crystal_yaw_deg: float) -> bool:
	if crystal == null or occupied != null:
		return false
	occupied = crystal
	crystal.is_seated = true
	crystal.cradle = self
	crystal.held_yaw_deg = crystal_yaw_deg
	# 只登记占用；aligned 由“锁爪真的夹住”那一刻决定，不能一放下就点亮中继
	aligned = false
	return true


func release() -> void:
	if occupied == null:
		return
	var crystal: PortableCrystal = occupied
	occupied = null
	aligned = false
	latched = false
	crystal.is_seated = false
	crystal.cradle = null
	released.emit(self)


func _update_indicator_state() -> void:
	if latched:
		_set_indicator(Color(0.30, 1.0, 0.80) if aligned else Color(1.0, 0.30, 0.16), 1.7 if aligned else 1.8)
	elif occupied != null:
		_set_indicator(Color(1.0, 0.62, 0.20), 1.1)
	else:
		_set_indicator(Color(1.0, 0.55, 0.18), 1.0)


func _set_indicator(color: Color, energy: float) -> void:
	# 只在状态真的变化时才动材质：`tick()` 每物理帧调用这里，
	# 无条件改写/复制材质等于 60 次/秒的分配与上传。
	if color == _indicator_color and is_equal_approx(energy, _indicator_energy):
		return
	_indicator_color = color
	_indicator_energy = energy
	if _indicator != null:
		_indicator.material_override = MaterialLibrary.emissive(color, energy)
	if _indicator_light != null:
		_indicator_light.light_color = color
		_indicator_light.light_energy = 0.55 if energy < 1.4 else 0.95
	if _ring != null:
		_ring.material_override = MaterialLibrary.emissive(color, 0.5 + energy * 0.2)
	if _arrow != null:
		if _arrow_material == null and _arrow.material_override is StandardMaterial3D:
			_arrow_material = (_arrow.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
		if _arrow_material != null:
			_arrow_material.albedo_color = color
			_arrow_material.emission = color
			_arrow.material_override = _arrow_material


func reset_cradle() -> void:
	occupied = null
	aligned = false
	latched = false
	jaw_motor = false
	retracting = false
	jaw_x = JAW_OPEN
	_apply_jaws()
	_update_indicator_state()


