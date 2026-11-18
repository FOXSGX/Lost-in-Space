extends RigidBody3D
class_name EnergyBall

## 能源球：真正的刚体（RigidBody3D + 球形碰撞体）。
##
## 重力、碰撞、弹跳、旋转全部交给 Godot 物理解算，本文件不写任何角度积分、
## 不每帧覆盖速度、不在低速时强制归零；滚动由物理摩擦自然产生。
##
## 三层职责仍然分开：
##   踢球输入 → gulu_app.gd（只决定有无冲量与方向）
##   球运动   → 本文件（冲量、阻尼、出界检测）
##   入仓判定 → collector.gd（球心越过门口平面）

signal kicked(speed: float)
signal out_of_bounds(position: Vector3)

## 半径 0.34 m：比真实足球大一点，第一人称容易看见、容易踢中。
const RADIUS := 0.34
## 单击固定力度：冲量 = 质量 × 目标初速。质量 1.2 kg → 16.0 N·s 约 13.3 m/s。
const KICK_IMPULSE := 19.0

var collected := false
var swat_count := 0
var credit_peer := 0

var _visual: Node3D
var _time := 0.0
## 物理冲量必须在本节点的物理回调里施加，否则对休眠中的刚体会被丢掉。
var _pending_impulse := Vector3.ZERO


func _ready() -> void:
	# --- 物理参数：滚动可信、停得住、不过度弹跳 ---
	mass = 1.2
	gravity_scale = 1.0
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.45
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.55
	can_sleep = true
	continuous_cd = true          # 高速射门不穿门柱/墙
	contact_monitor = true
	max_contacts_reported = 4
	collision_layer = 1
	collision_mask = 2 | 4 | 16   # 场景 / 玩家 / 奶龙

	var material := PhysicsMaterial.new()
	material.friction = 0.7
	material.bounce = 0.5
	physics_material_override = material

	var shape := SphereShape3D.new()
	shape.radius = RADIUS
	var collider := CollisionShape3D.new()
	collider.shape = shape
	add_child(collider)

	_build_visual()
	set_physics_process(true)


## 踢球：只施加一次中心冲量，不改位置、不覆盖速度。
func kick(direction: Vector3, impulse: float = KICK_IMPULSE) -> void:
	if collected:
		return
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.0001:
		flat = Vector3.FORWARD
	flat = flat.normalized()
	sleeping = false
	_pending_impulse += flat * impulse
	kicked.emit(impulse / maxf(mass, 0.01))


## 奶龙的“拨球”：独立触发、独立冷却，由行为层调用；不是碰撞反射。
func swat(direction: Vector3, impulse: float) -> void:
	if collected:
		return
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.0001:
		flat = Vector3.LEFT
	flat = flat.normalized()
	sleeping = false
	if impulse > 0.0:
		swat_count += 1
	_pending_impulse += flat * impulse


func speed() -> float:
	return linear_velocity.length()


func collect() -> void:
	if collected:
		return
	collected = true
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


func reset_to(at: Vector3) -> void:
	var old_tween: Variant = get_meta("intake_tween") if has_meta("intake_tween") else null
	if old_tween != null and old_tween is Tween and (old_tween as Tween).is_valid():
		(old_tween as Tween).kill()
	set_meta("intake_tween", null)
	collected = false
	freeze = false
	sleeping = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_position = Vector3(at.x, RADIUS + 0.05, at.z)
	rotation = Vector3.ZERO
	visible = true
	scale = Vector3.ONE
	_time = 0.0
	swat_count = 0


func _physics_process(delta: float) -> void:
	_time += delta
	if _pending_impulse != Vector3.ZERO:
		apply_central_impulse(_pending_impulse)
		_pending_impulse = Vector3.ZERO
	# 只有“真的掉出世界”才算需要救援；正常停球/门边停球一律不动它。
	var p := global_position
	if p.y < -8.0 or absf(p.x) > 28.0 or absf(p.z) > 22.0:
		out_of_bounds.emit(p)


# ------------------------------------------------------------------ 外观

func _build_visual() -> void:
	_visual = Node3D.new()
	_visual.name = "BallVisual"
	add_child(_visual)

	var shell_material := StandardMaterial3D.new()
	shell_material.albedo_color = Color("#e2e8e8")
	shell_material.roughness = 0.30
	shell_material.metallic = 0.22
	shell_material.metallic_specular = 0.55

	var shell := SphereMesh.new()
	shell.radius = RADIUS
	shell.height = RADIUS * 2.0
	shell.radial_segments = 24
	shell.rings = 12
	var shell_node := MeshInstance3D.new()
	shell_node.mesh = shell
	shell_node.material_override = shell_material
	_visual.add_child(shell_node)

	# 能量核心：半透明外壳里的发光球
	var core_material := StandardMaterial3D.new()
	core_material.albedo_color = Color("#ffb347")
	core_material.emission_enabled = true
	core_material.emission = Color("#ffb347")
	core_material.emission_energy_multiplier = 1.15
	var core := SphereMesh.new()
	core.radius = RADIUS * 0.62
	core.height = RADIUS * 1.24
	core.radial_segments = 16
	core.rings = 8
	var core_node := MeshInstance3D.new()
	core_node.mesh = core
	core_node.material_override = core_material
	_visual.add_child(core_node)

	# 外壳经线框：物理自转时能明显看出球在滚，而不是贴地滑。
	# 只留两条，宽度收窄；球面已经够亮，不靠更多灯带抢注意力。
	var rib_material := StandardMaterial3D.new()
	rib_material.albedo_color = Color("#2e4a52")
	rib_material.roughness = 0.55
	rib_material.metallic = 0.30
	for index in range(2):
		var rib := TorusMesh.new()
		rib.inner_radius = RADIUS * 0.992
		rib.outer_radius = RADIUS * 1.006
		rib.rings = 28
		rib.ring_segments = 6
		var rib_node := MeshInstance3D.new()
		rib_node.mesh = rib
		rib_node.material_override = rib_material
		rib_node.rotation.y = float(index) * PI * 0.5
		_visual.add_child(rib_node)

	# 赤道灯带：远景也读得出球的位置与转动
	var band := TorusMesh.new()
	band.inner_radius = RADIUS * 1.01
	band.outer_radius = RADIUS * 1.09
	band.rings = 28
	band.ring_segments = 6
	var band_material := StandardMaterial3D.new()
	band_material.albedo_color = Color("#ffb347")
	band_material.emission_enabled = true
	band_material.emission = Color("#ffb347")
	band_material.emission_energy_multiplier = 0.95
	var band_node := MeshInstance3D.new()
	band_node.mesh = band
	band_node.material_override = band_material
	_visual.add_child(band_node)

	var glow := OmniLight3D.new()
	glow.light_color = Color("#ffb347")
	glow.light_energy = 0.22
	glow.omni_range = 2.0
	add_child(glow)










