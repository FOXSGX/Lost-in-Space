extends Node3D
class_name FrostColonyPuzzles

## 霜烬星 2.0 · 六大建筑物理谜题与全道具深度拓展系统（15–25 分钟核心耐玩度引擎）
## 让每一件物品都从“拿手上玩两下”变成“解开极地科考城六大谜案不可或缺的物理钥匙”：
## 1. 生活医疗楼（living_acoustic）    ——【复古音响 boombox】声波共振震碎结晶锁 -> 强心针永久强化 + 线索 #1
## 2. 生态穹顶温室（greenhouse_thermal）——【信号弹 flare / 热风机 / 吸推热核】融解地热导管 -> 永久抗寒护盾 + 线索 #2
## 3. 冰川钻探中心（drill_core）       ——【电池 cell 插槽 + 吸推器搬箱上双压板】启动冰芯钻塔 -> 永久吸推增幅 + 线索 #3
## 4. 东线机甲维修厂（mech_kinetic）   ——【弹跳垫 bounce_pad 上天桥 + 碰碰球 bumper_orb 三连打靶】-> 载具涡轮提速 +35%！
## 5. 西翼天文观测穹顶（observatory_star）——【信号弹抛投高空热感锁 + 音响声波星图】-> 极光热护盾 + 巨型望远镜极光柱！
## 6. 东翼反应堆电厂（reactor_overdrive）——【双电池插槽过载 + 弹跳垫上高空总闸】-> 热风机 2 倍融冰 + 自动回能超频！

const FUSE_BOX_GLB: PackedScene = preload("res://assets/models/rebuild/hero_puzzle_fuse_box.glb")
const TARGET_GLB: PackedScene = preload("res://assets/models/rebuild/hero_puzzle_target_plate.glb")
const VAULT_GLB: PackedScene = preload("res://assets/models/rebuild/hero_puzzle_acoustic_vault.glb")

const PUZZLE_IDS: Array[String] = [
	"living_acoustic",
	"greenhouse_thermal",
	"drill_core",
	"mech_kinetic",
	"observatory_star",
	"reactor_overdrive",
]

var director: Node3D
var world: Node3D
var _pbr: ArtPbrLib
var _clock: float = 0.0

var solved: Dictionary = {}
var upgrades: Dictionary = {
	"med_boost": false,
	"cold_shield": false,
	"suction_amp": false,
	"turbo_vehicles": false,
	"aurora_shield": false,
	"heater_overclock": false,
}
var discovered_logs: Array[String] = []

# 物理机关节点列表
var fuse_sockets: Array[Dictionary] = []
var acoustic_vaults: Array[Dictionary] = []
var thermal_sensors: Array[Dictionary] = []
var kinetic_targets: Array[Dictionary] = []
var pressure_plates: Array[Dictionary] = []
var catwalk_switches: Array[Dictionary] = []
var _drill_beam: MeshInstance3D
var _drill_light: OmniLight3D
var _aurora_beam: MeshInstance3D
var _aurora_light: OmniLight3D
var _reactor_light: OmniLight3D
var _greenhouse_ice: MeshInstance3D
var _greenhouse_light: OmniLight3D
var _conduit_mats: Dictionary = {}
var _bounce_rings: Array[MeshInstance3D] = []

func setup(owner_director: Node3D, owner_world: Node3D) -> void:
	name = "FrostColonyPuzzles"
	director = owner_director
	world = owner_world
	_pbr = ArtPbrLib.new()
	for pid: String in PUZZLE_IDS:
		solved[pid] = false
	_build_living_acoustic()
	_build_greenhouse_thermal()
	_build_drill_core()
	_build_mech_kinetic()
	_build_observatory_star()
	_build_reactor_overdrive()

# ------------------------------------------------------------------ 通用建造辅助（严禁悬浮 3D 文字，全部用物理发光灯与材质指示！）

func _glow_mat(col: Color, energy: float = 2.4, alpha: float = 1.0) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(col.r, col.g, col.b, alpha)
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = energy
	if alpha < 0.99:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat

func _set_indicator(mat: StandardMaterial3D, light: OmniLight3D, col: Color, energy: float = 2.4) -> void:
	if mat != null:
		mat.albedo_color = Color(col.r, col.g, col.b, mat.albedo_color.a)
		mat.emission = col
		mat.emission_energy_multiplier = energy
	if light != null:
		light.light_color = col
		light.light_energy = energy

func _spawn_fuse_socket(puzzle_id: String, socket_id: String, pos: Vector3, yaw_deg: float, label: String) -> void:
	var holder: Node3D = Node3D.new()
	holder.name = "FuseSocket_" + socket_id
	holder.position = pos
	holder.rotation_degrees.y = yaw_deg
	add_child(holder)
	var vis: Node3D = FUSE_BOX_GLB.instantiate() as Node3D
	_pbr.bind_glb(vis, "frost", true)
	holder.add_child(vis)
	# 顶部状态灯球（红=缺电，翡翠绿=已通电！）
	var lamp_mesh: MeshInstance3D = MeshInstance3D.new()
	var sp: SphereMesh = SphereMesh.new()
	sp.radius = 0.16; sp.height = 0.32
	lamp_mesh.mesh = sp
	lamp_mesh.position = Vector3(0.0, 1.82, 0.0)
	var mat: StandardMaterial3D = _glow_mat(Color("#ff422e"), 2.4)
	lamp_mesh.material_override = mat
	holder.add_child(lamp_mesh)
	# 插槽内电池模型（插入后瞬间现身！）
	var inserted_cell: MeshInstance3D = MeshInstance3D.new()
	var bm: BoxMesh = BoxMesh.new()
	bm.size = Vector3(0.32, 0.42, 0.24)
	inserted_cell.mesh = bm
	inserted_cell.position = Vector3(0.0, 1.02, 0.24)
	inserted_cell.material_override = _glow_mat(Color("#36f0ff"), 2.0)
	inserted_cell.visible = false
	holder.add_child(inserted_cell)
	var lt: OmniLight3D = OmniLight3D.new()
	lt.position = Vector3(0.0, 1.85, 0.25)
	lt.light_color = Color("#ff422e"); lt.light_energy = 1.8; lt.omni_range = 8.5
	holder.add_child(lt)
	fuse_sockets.append({
		"puzzle": puzzle_id, "id": socket_id, "pos": pos, "label": label,
		"powered": false, "mat": mat, "light": lt, "cell_vis": inserted_cell
	})

func _spawn_acoustic_vault(puzzle_id: String, vault_id: String, pos: Vector3, label: String) -> void:
	var holder: Node3D = Node3D.new()
	holder.name = "AcousticVault_" + vault_id
	holder.position = pos
	add_child(holder)
	var vis: Node3D = VAULT_GLB.instantiate() as Node3D
	_pbr.bind_glb(vis, "frost", true)
	holder.add_child(vis)
	# 半透明六棱共振结晶罩（未震碎前封住内部奖励）
	var dome: MeshInstance3D = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 0.45; cyl.bottom_radius = 0.72; cyl.height = 1.45; cyl.radial_segments = 6
	dome.mesh = cyl
	dome.position = Vector3(0.0, 1.15, 0.0)
	var dome_mat: StandardMaterial3D = _glow_mat(Color("#46d8ff"), 1.6, 0.52)
	dome.material_override = dome_mat
	holder.add_child(dome)
	# 脉冲声波环（提示玩家此处需要声波共振！）
	var ring: MeshInstance3D = MeshInstance3D.new()
	var r_mesh: CylinderMesh = CylinderMesh.new()
	r_mesh.top_radius = 1.05; r_mesh.bottom_radius = 1.05; r_mesh.height = 0.06; r_mesh.radial_segments = 24
	ring.mesh = r_mesh
	ring.position = Vector3(0.0, 0.55, 0.0)
	var ring_mat: StandardMaterial3D = _glow_mat(Color("#ff6ec7"), 2.2, 0.75)
	ring.material_override = ring_mat
	holder.add_child(ring)
	var lt: OmniLight3D = OmniLight3D.new()
	lt.position = Vector3(0.0, 1.45, 0.0)
	lt.light_color = Color("#ff6ec7"); lt.light_energy = 2.0; lt.omni_range = 10.0
	holder.add_child(lt)
	acoustic_vaults.append({
		"puzzle": puzzle_id, "id": vault_id, "pos": pos, "label": label,
		"shattered": false, "charge": 0.0, "dome": dome, "dome_mat": dome_mat,
		"ring": ring, "ring_mat": ring_mat, "light": lt
	})

func _spawn_kinetic_target(puzzle_id: String, target_id: String, pos: Vector3, yaw_deg: float) -> void:
	var holder: Node3D = Node3D.new()
	holder.name = "KineticTarget_" + target_id
	holder.position = pos
	holder.rotation_degrees.y = yaw_deg
	add_child(holder)
	var vis: Node3D = TARGET_GLB.instantiate() as Node3D
	_pbr.bind_glb(vis, "frost", true)
	holder.add_child(vis)
	var bullseye: MeshInstance3D = MeshInstance3D.new()
	var cm: CylinderMesh = CylinderMesh.new()
	cm.top_radius = 0.34; cm.bottom_radius = 0.34; cm.height = 0.30; cm.radial_segments = 16
	bullseye.mesh = cm
	bullseye.rotation_degrees.x = 90.0
	bullseye.position = Vector3(0.0, 0.0, 0.06)
	var mat: StandardMaterial3D = _glow_mat(Color("#ff942e"), 2.8)
	bullseye.material_override = mat
	holder.add_child(bullseye)
	var lt: OmniLight3D = OmniLight3D.new()
	lt.position = Vector3(0.0, 0.0, 0.55)
	lt.light_color = Color("#ff942e"); lt.light_energy = 2.0; lt.omni_range = 10.0
	holder.add_child(lt)
	kinetic_targets.append({
		"puzzle": puzzle_id, "id": target_id, "pos": pos, "node": holder,
		"hit": false, "mat": mat, "light": lt
	})

func _spawn_thermal_sensor(puzzle_id: String, sensor_id: String, pos: Vector3, radius: float, label: String, with_catch_basket: bool = false) -> void:
	var holder: Node3D = Node3D.new()
	holder.name = "ThermalSensor_" + sensor_id
	holder.position = pos
	add_child(holder)
	if with_catch_basket:
		# 高空热感锁下方加装实心钢制接弹火盆（抛投信号弹稳稳接住持续加热，手感极爽不掉地！）
		world.box(pos + Vector3(0.0, -0.58, 0.0), Vector3(2.4, 0.18, 2.4), Color("#425864"))
		for sx: float in [-1.14, 1.14]:
			world.box(pos + Vector3(sx, -0.26, 0.0), Vector3(0.14, 0.56, 2.4), Color("#d98d3c"))
		for sz: float in [-1.14, 1.14]:
			world.box(pos + Vector3(0.0, -0.26, sz), Vector3(2.4, 0.56, 0.14), Color("#d98d3c"))
	var ring: MeshInstance3D = MeshInstance3D.new()
	var cm: CylinderMesh = CylinderMesh.new()
	cm.top_radius = 0.72; cm.bottom_radius = 0.84; cm.height = 0.28; cm.radial_segments = 12
	ring.mesh = cm
	var mat: StandardMaterial3D = _glow_mat(Color("#ff5232"), 2.4)
	ring.material_override = mat
	holder.add_child(ring)
	var frost_cap: MeshInstance3D = MeshInstance3D.new()
	var sp: SphereMesh = SphereMesh.new()
	sp.radius = 0.68; sp.height = 1.15
	frost_cap.mesh = sp
	frost_cap.position.y = 0.35
	frost_cap.material_override = _glow_mat(Color("#9ae6ff"), 0.8, 0.58)
	holder.add_child(frost_cap)
	var lt: OmniLight3D = OmniLight3D.new()
	lt.position.y = 0.45
	lt.light_color = Color("#ff5232"); lt.light_energy = 2.2; lt.omni_range = 11.0
	holder.add_child(lt)
	thermal_sensors.append({
		"puzzle": puzzle_id, "id": sensor_id, "pos": pos, "radius": radius, "label": label,
		"melted": false, "heat": 0.0, "mat": mat, "frost_cap": frost_cap, "light": lt
	})

## 地面/墙体发光因果导管（无悬浮文字！直接把子机关与主机械连成一目了然的视觉回路，解谜后整体变翡翠绿！）
func _spawn_conduit(puzzle_id: String, from_p: Vector3, to_p: Vector3) -> void:
	var delta_v: Vector3 = to_p - from_p
	var length: float = delta_v.length()
	if length < 0.2:
		return
	var mi: MeshInstance3D = MeshInstance3D.new()
	var bm: BoxMesh = BoxMesh.new()
	bm.size = Vector3(0.18, 0.06, length)
	mi.mesh = bm
	mi.position = (from_p + to_p) * 0.5
	mi.look_at_from_position(mi.position, to_p, Vector3.UP)
	var mat: StandardMaterial3D = _glow_mat(Color("#ff9a32"), 1.65)
	mi.material_override = mat
	add_child(mi)
	if not _conduit_mats.has(puzzle_id):
		_conduit_mats[puzzle_id] = []
	(_conduit_mats[puzzle_id] as Array).append(mat)

## 高空天桥正下方脉冲青蓝起跳提示圈（零文字提示玩家此处放【弹跳垫】即可一跃上桥！）
func _spawn_bounce_zone(pos: Vector3) -> void:
	var ring: MeshInstance3D = MeshInstance3D.new()
	var cm: CylinderMesh = CylinderMesh.new()
	cm.top_radius = 1.25; cm.bottom_radius = 1.35; cm.height = 0.05; cm.radial_segments = 24
	ring.mesh = cm
	ring.position = pos
	ring.material_override = _glow_mat(Color("#3ee8ff"), 1.8, 0.55)
	add_child(ring)
	_bounce_rings.append(ring)

func _spawn_pressure_plate(puzzle_id: String, plate_id: String, pos: Vector3) -> void:
	var holder: Node3D = Node3D.new()
	holder.name = "PressurePlate_" + plate_id
	holder.position = pos
	add_child(holder)
	var frame: MeshInstance3D = MeshInstance3D.new()
	var fm: BoxMesh = BoxMesh.new()
	fm.size = Vector3(2.35, 0.10, 2.35)
	frame.mesh = fm
	var fmat: StandardMaterial3D = StandardMaterial3D.new()
	fmat.albedo_color = Color("#2b3b44"); fmat.roughness = 0.55; fmat.metallic = 0.6
	frame.material_override = fmat
	holder.add_child(frame)
	var pad: MeshInstance3D = MeshInstance3D.new()
	var pm: BoxMesh = BoxMesh.new()
	pm.size = Vector3(1.90, 0.12, 1.90)
	pad.mesh = pm
	pad.position.y = 0.06
	var mat: StandardMaterial3D = _glow_mat(Color("#ff9a32"), 1.8)
	pad.material_override = mat
	holder.add_child(pad)
	var lt: OmniLight3D = OmniLight3D.new()
	lt.position.y = 0.55
	lt.light_color = Color("#ff9a32"); lt.light_energy = 1.4; lt.omni_range = 7.0
	holder.add_child(lt)
	pressure_plates.append({
		"puzzle": puzzle_id, "id": plate_id, "pos": pos,
		"pressed": false, "pad": pad, "mat": mat, "light": lt
	})

func _spawn_catwalk_switch(puzzle_id: String, sw_id: String, deck_pos: Vector3, deck_size: Vector3, switch_pos: Vector3, label: String) -> void:
	# 实心高空检修天桥（无楼梯，必须靠【弹跳垫】或喷气背包跃上！）
	world.box(deck_pos, deck_size, Color("#49626e"))
	# 橙色前缘防坠护栏条
	world.box(deck_pos + Vector3(0.0, 0.55, deck_size.z * 0.5 - 0.1), Vector3(deck_size.x, 0.14, 0.12), Color("#e59642"), false)
	for sx: float in [-deck_size.x * 0.45, deck_size.x * 0.45]:
		world.box(Vector3(deck_pos.x + sx, deck_pos.y * 0.5, deck_pos.z), Vector3(0.32, deck_pos.y, 0.32), Color("#344954"))
	# 高空控制台柱
	var holder: Node3D = Node3D.new()
	holder.name = "CatwalkSwitch_" + sw_id
	holder.position = switch_pos
	add_child(holder)
	var ped: MeshInstance3D = MeshInstance3D.new()
	var pm: BoxMesh = BoxMesh.new()
	pm.size = Vector3(1.1, 1.25, 0.72)
	ped.mesh = pm; ped.position.y = 0.62
	var pmat: StandardMaterial3D = StandardMaterial3D.new()
	pmat.albedo_color = Color("#344c59"); pmat.roughness = 0.5; pmat.metallic = 0.5
	ped.material_override = pmat
	holder.add_child(ped)
	var beacon: MeshInstance3D = MeshInstance3D.new()
	var sm: SphereMesh = SphereMesh.new()
	sm.radius = 0.22; sm.height = 0.44
	beacon.mesh = sm; beacon.position.y = 1.48
	var mat: StandardMaterial3D = _glow_mat(Color("#ff9432"), 2.4)
	beacon.material_override = mat
	holder.add_child(beacon)
	var lt: OmniLight3D = OmniLight3D.new()
	lt.position.y = 1.65
	lt.light_color = Color("#ff9432"); lt.light_energy = 2.0; lt.omni_range = 10.0
	holder.add_child(lt)
	catwalk_switches.append({
		"puzzle": puzzle_id, "id": sw_id, "pos": switch_pos, "label": label,
		"flipped": false, "mat": mat, "light": lt
	})

# ------------------------------------------------------------------ 6 大建筑谜题布设

func _build_living_acoustic() -> void:
	# 谜案 1：生活医疗楼医疗角声波共振生物密柜（用【复古磁力音响】共振震碎！）
	_spawn_acoustic_vault("living_acoustic", "living_med_vault", Vector3(60.2, 0.2, -52.2), "声波共振生物密柜（在附近开启复古音响共振解锁）")

func _build_greenhouse_thermal() -> void:
	# 谜案 2：生态穹顶温室冰封地热导管（扔【极光信号弹】/ 照【热风机】/ 吸推搬来【便携热核】皆可融解！）
	var p: Vector3 = Vector3(-112.4, 0.28, -117.2)
	_spawn_thermal_sensor("greenhouse_thermal", "gh_conduit", p, 4.4, "温室冰封地热导管（投掷信号弹 / 热风机加热 / 搬来热核融解）")
	_greenhouse_light = OmniLight3D.new()
	_greenhouse_light.position = Vector3(-108.0, 7.5, -112.0)
	_greenhouse_light.light_color = Color("#4ef29c")
	_greenhouse_light.light_energy = 0.0
	_greenhouse_light.omni_range = 32.0
	add_child(_greenhouse_light)

func _build_drill_core() -> void:
	# 谜案 3：冰川钻探中心（插入【备用电池】供电 + 用【吸推器】把样本箱搬上双压板启动 8m 冰芯钻塔！）
	var dr: Vector3 = Vector3(-72.0, 0.0, -166.0)
	_spawn_fuse_socket("drill_core", "drill_fuse", dr + Vector3(0.0, 0.2, 7.6), 0.0, "钻探主控电池槽（持备用电池按 E 插入供电）")
	_spawn_pressure_plate("drill_core", "drill_plate_L", dr + Vector3(-4.6, 0.23, 2.6))
	_spawn_pressure_plate("drill_core", "drill_plate_R", dr + Vector3(4.6, 0.23, 2.6))
	# 三条地面发光因果导管直连中央 8m 冰芯钻塔，进门一眼看懂！
	_spawn_conduit("drill_core", dr + Vector3(0.0, 0.25, 7.2), dr + Vector3(0.0, 0.25, -1.5))
	_spawn_conduit("drill_core", dr + Vector3(-4.6, 0.25, 2.6), dr + Vector3(0.0, 0.25, -1.5))
	_spawn_conduit("drill_core", dr + Vector3(4.6, 0.25, 2.6), dr + Vector3(0.0, 0.25, -1.5))
	_drill_beam = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 0.38; cyl.bottom_radius = 0.52; cyl.height = 9.2; cyl.radial_segments = 16
	_drill_beam.mesh = cyl
	_drill_beam.position = dr + Vector3(0.0, 4.8, -1.5)
	_drill_beam.material_override = _glow_mat(Color("#46f2ff"), 3.2, 0.72)
	_drill_beam.visible = false
	add_child(_drill_beam)
	_drill_light = OmniLight3D.new()
	_drill_light.position = dr + Vector3(0.0, 5.2, -1.5)
	_drill_light.light_color = Color("#46f2ff"); _drill_light.light_energy = 0.0; _drill_light.omni_range = 28.0
	add_child(_drill_light)

func _build_mech_kinetic() -> void:
	# 谜案 4：东线机甲维修厂（放【弹跳垫】上 5.4m 高空天桥合闸 + 射【碰碰球】击中三块动能靶心！）
	var mh: Vector3 = Vector3(112.0, 0.0, -34.0)
	_spawn_catwalk_switch(
		"mech_kinetic", "mech_gantry_sw",
		mh + Vector3(0.0, 5.4, -12.8), Vector3(14.0, 0.34, 3.8),
		mh + Vector3(0.0, 5.58, -12.4), "机甲天桥高空超控台（部署弹跳垫跃上按 E 合闸）"
	)
	_spawn_bounce_zone(mh + Vector3(0.0, 0.25, -8.5))
	_spawn_kinetic_target("mech_kinetic", "mech_tgt_1", mh + Vector3(-11.5, 4.6, -16.4), 0.0)
	_spawn_kinetic_target("mech_kinetic", "mech_tgt_2", mh + Vector3(0.0, 7.6, -16.4), 0.0)
	_spawn_kinetic_target("mech_kinetic", "mech_tgt_3", mh + Vector3(11.5, 4.6, -16.4), 0.0)
	_spawn_conduit("mech_kinetic", mh + Vector3(-11.5, 4.6, -16.2), mh + Vector3(0.0, 7.6, -16.2))
	_spawn_conduit("mech_kinetic", mh + Vector3(11.5, 4.6, -16.2), mh + Vector3(0.0, 7.6, -16.2))

func _build_observatory_star() -> void:
	# 谜案 5：西翼天文观测穹顶（抛投【极光信号弹】入高空火盆解热感锁 + 开启【复古音响】共振星图密柜！）
	var obs: Vector3 = Vector3(-164.0, 0.0, -78.0)
	_spawn_thermal_sensor("observatory_star", "obs_thermal", obs + Vector3(0.0, 5.0, -11.6), 4.8, "高空热感火盆锁（向上抛掷极光信号弹入盆解锁）", true)
	_spawn_acoustic_vault("observatory_star", "obs_vault", obs + Vector3(0.0, 0.28, 3.8), "天文星图声波密柜（在附近开启复古音响共振解锁）")
	_spawn_conduit("observatory_star", obs + Vector3(0.0, 0.31, 3.4), obs + Vector3(0.0, 0.31, -1.5))
	_aurora_beam = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 1.2; cyl.bottom_radius = 0.55; cyl.height = 140.0; cyl.radial_segments = 16
	_aurora_beam.mesh = cyl
	_aurora_beam.position = obs + Vector3(0.0, 72.0, -3.5)
	_aurora_beam.material_override = _glow_mat(Color("#58f4ff"), 2.8, 0.38)
	_aurora_beam.visible = false
	add_child(_aurora_beam)
	_aurora_light = OmniLight3D.new()
	_aurora_light.position = obs + Vector3(0.0, 9.0, -2.0)
	_aurora_light.light_color = Color("#58f4ff"); _aurora_light.light_energy = 0.0; _aurora_light.omni_range = 36.0
	add_child(_aurora_light)

func _build_reactor_overdrive() -> void:
	# 谜案 6：东翼地热反应堆电厂（双【备用电池】插槽过载 + 【弹跳垫】上 5.6m 涡轮高空总闸！）
	var rh: Vector3 = Vector3(166.0, 0.0, -76.0)
	_spawn_fuse_socket("reactor_overdrive", "reactor_fuse_L", rh + Vector3(-4.5, 0.2, 5.5), 0.0, "反应堆左侧高压电池槽（持备用电池按 E 插入）")
	_spawn_fuse_socket("reactor_overdrive", "reactor_fuse_R", rh + Vector3(4.5, 0.2, 5.5), 0.0, "反应堆右侧高压电池槽（持备用电池按 E 插入）")
	_spawn_conduit("reactor_overdrive", rh + Vector3(-4.5, 0.25, 5.2), rh + Vector3(-9.0, 0.25, 2.0))
	_spawn_conduit("reactor_overdrive", rh + Vector3(4.5, 0.25, 5.2), rh + Vector3(9.0, 0.25, 2.0))
	_spawn_catwalk_switch(
		"reactor_overdrive", "reactor_breaker",
		rh + Vector3(0.0, 5.6, -13.2), Vector3(12.0, 0.34, 3.6),
		rh + Vector3(0.0, 5.78, -12.6), "反应堆涡轮过载总闸（部署弹跳垫跃上按 E 合闸）"
	)
	_spawn_bounce_zone(rh + Vector3(0.0, 0.25, -8.8))
	_reactor_light = OmniLight3D.new()
	_reactor_light.position = rh + Vector3(0.0, 9.0, -4.0)
	_reactor_light.light_color = Color("#ffbc48"); _reactor_light.light_energy = 0.0; _reactor_light.omni_range = 40.0
	add_child(_reactor_light)

# ------------------------------------------------------------------ 帧循环：实时检测声波、热感、碰碰球打靶、压板、电池与被动超频

func tick(delta: float) -> void:
	_clock += delta
	_tick_visuals(delta)
	if not director.is_host:
		return
	var sandbox: Node3D = director.get("sandbox") as Node3D
	_tick_acoustic_vaults(delta, sandbox)
	_tick_thermal_sensors(delta, sandbox)
	_tick_kinetic_targets(sandbox)
	_tick_pressure_plates()
	_tick_dropped_cells_into_sockets()
	_tick_upgrades_passive(delta)

func _tick_visuals(delta: float) -> void:
	var pulse: float = 0.5 + 0.5 * sin(_clock * 4.2)
	for av: Dictionary in acoustic_vaults:
		if not bool(av.shattered):
			var ring: MeshInstance3D = av.ring as MeshInstance3D
			var ch: float = float(av.charge)
			ring.position.y = 0.55 + pulse * 0.72
			var s: float = 1.0 + ch * 0.35 + sin(_clock * (6.0 + ch * 18.0)) * 0.08
			ring.scale = Vector3(s, 1.0, s)
			if ch > 0.05:
				var dome: MeshInstance3D = av.dome as MeshInstance3D
				dome.position.x = sin(_clock * 45.0) * 0.04 * ch
				dome.position.z = cos(_clock * 41.0) * 0.04 * ch
	for kt: Dictionary in kinetic_targets:
		if not bool(kt.hit):
			(kt.mat as StandardMaterial3D).emission_energy_multiplier = 2.0 + pulse * 1.4
	for br: MeshInstance3D in _bounce_rings:
		var s2: float = 0.94 + pulse * 0.14
		br.scale = Vector3(s2, 1.0, s2)
	if _drill_beam != null and _drill_beam.visible:
		_drill_beam.rotation.y += delta * 2.4
	if _aurora_beam != null and _aurora_beam.visible:
		_aurora_beam.rotation.y += delta * 0.8

func _tick_acoustic_vaults(delta: float, sandbox: Node3D) -> void:
	if sandbox == null:
		return
	var boxes: Array = sandbox.get("boomboxes") as Array
	if boxes == null:
		return
	for av: Dictionary in acoustic_vaults:
		if bool(av.shattered):
			continue
		var vp: Vector3 = av.pos as Vector3
		var near_music: bool = false
		for bb: Dictionary in boxes:
			var bn: Node3D = bb.get("node") as Node3D
			if bn != null and bn.position.distance_to(vp) < 7.8:
				near_music = true
				break
		if near_music:
			av.charge = minf(1.0, float(av.charge) + delta / 2.2)
			if float(av.charge) >= 1.0:
				_shatter_vault(av)
		else:
			av.charge = maxf(0.0, float(av.charge) - delta * 0.4)

func _shatter_vault(av: Dictionary) -> void:
	if bool(av.shattered):
		return
	av.shattered = true
	av.charge = 1.0
	(av.dome as MeshInstance3D).visible = false
	(av.ring as MeshInstance3D).visible = false
	_set_indicator(null, av.light as OmniLight3D, Color("#34f29e"), 2.4)
	if director.get("sandbox") != null:
		director.sandbox._spawn_explosion_fx((av.pos as Vector3) + Vector3.UP * 1.1, Color("#4ef4ff"), 5.5)
	SfxKit.play_3d(self, "sfx_explosion", av.pos as Vector3, -4.0, 1.35)
	_broadcast("声波共振成功！结晶密柜已震碎解锁！")
	_check_puzzle_completion(String(av.puzzle))

func _tick_thermal_sensors(delta: float, sandbox: Node3D) -> void:
	for ts: Dictionary in thermal_sensors:
		if bool(ts.melted):
			continue
		var tp: Vector3 = ts.pos as Vector3
		var rad: float = float(ts.radius)
		var rate: float = 0.0
		if sandbox != null:
			var fls: Array = sandbox.get("flares") as Array
			if fls != null:
				for fl: Dictionary in fls:
					var fb: RigidBody3D = fl.get("body") as RigidBody3D
					if fb != null:
						var dist: float = fb.position.distance_to(tp)
						if dist < 2.2:
							# 精准投进火盆/擦身直击瞬间大幅升温，手感极爽！
							rate = maxf(rate, 2.2)
						elif dist < rad:
							rate = maxf(rate, 0.85)
			var cores: Array = sandbox.get("heat_cores") as Array
			if cores != null:
				for hc: RigidBody3D in cores:
					if is_instance_valid(hc) and hc.position.distance_to(tp) < rad:
						rate = maxf(rate, 0.72)
		if rate > 0.0:
			ts.heat = minf(1.0, float(ts.heat) + delta * rate)
			if float(ts.heat) >= 1.0:
				_melt_thermal_sensor(ts)

func heat_hit_at(point: Vector3, delta: float) -> void:
	if not director.is_host:
		return
	for ts: Dictionary in thermal_sensors:
		if bool(ts.melted):
			continue
		if (ts.pos as Vector3).distance_to(point) < 3.6:
			ts.heat = minf(1.0, float(ts.heat) + delta * 0.48)
			if float(ts.heat) >= 1.0:
				_melt_thermal_sensor(ts)

func _melt_thermal_sensor(ts: Dictionary) -> void:
	if bool(ts.melted):
		return
	ts.melted = true
	ts.heat = 1.0
	(ts.frost_cap as MeshInstance3D).visible = false
	_set_indicator(ts.mat as StandardMaterial3D, ts.light as OmniLight3D, Color("#34f29e"), 2.6)
	if director.get("sandbox") != null:
		director.sandbox._spawn_explosion_fx(ts.pos as Vector3, Color("#ffaa48"), 4.2)
	SfxKit.play_3d(self, "sfx_flare_ignite", ts.pos as Vector3, -3.5, 1.2)
	_broadcast("热感机关融解激活！")
	_check_puzzle_completion(String(ts.puzzle))

func _tick_kinetic_targets(sandbox: Node3D) -> void:
	var orbs: Array = (sandbox.get("bumper_orbs") as Array) if sandbox != null else []
	for kt: Dictionary in kinetic_targets:
		if bool(kt.hit):
			continue
		var kp: Vector3 = kt.pos as Vector3
		var struck: bool = false
		for ob: Dictionary in orbs:
			var rb: RigidBody3D = ob.get("body") as RigidBody3D
			if rb != null and rb.position.distance_to(kp) < 2.25 and rb.linear_velocity.length() > 3.2:
				struck = true
				rb.linear_velocity = -rb.linear_velocity * 0.65 + Vector3.UP * 2.5
				break
		if not struck and director._items != null:
			for body_v in director._items._prop_bodies.values():
				var rb2: RigidBody3D = body_v as RigidBody3D
				if is_instance_valid(rb2) and rb2.position.distance_to(kp) < 2.0 and rb2.linear_velocity.length() > 4.5:
					struck = true
					break
		if struck:
			_hit_kinetic_target(kt)

func _hit_kinetic_target(kt: Dictionary) -> void:
	if bool(kt.hit):
		return
	kt.hit = true
	_set_indicator(kt.mat as StandardMaterial3D, kt.light as OmniLight3D, Color("#34f29e"), 3.0)
	if director.get("sandbox") != null:
		director.sandbox._spawn_explosion_fx(kt.pos as Vector3, Color("#4ef4ff"), 4.5)
	SfxKit.play_3d(self, "sfx_orb_bounce", kt.pos as Vector3, -2.0, 1.35)
	var hit_cnt: int = 0
	for other: Dictionary in kinetic_targets:
		if other.puzzle == kt.puzzle and bool(other.hit):
			hit_cnt += 1
	_broadcast("命中动能靶心！（%d / 3）" % hit_cnt)
	_check_puzzle_completion(String(kt.puzzle))

func _tick_pressure_plates() -> void:
	var changed_puzzles: Dictionary = {}
	for pp: Dictionary in pressure_plates:
		var ppos: Vector3 = pp.pos as Vector3
		var occupied: bool = false
		for actor: Node3D in director.players.values():
			if actor is SpacePlayer3D and not actor.downed:
				if Vector2(actor.position.x - ppos.x, actor.position.z - ppos.z).length() < 1.45 and absf(actor.position.y - ppos.y) < 1.5:
					occupied = true
					break
		if not occupied and director._items != null:
			for entry: Dictionary in director._items.drops:
				if String(entry.get("kind", "")) in ["crate", "bumper_orb", "oxygen", "cell"]:
					var dp: Vector3 = entry.position as Vector3
					if Vector2(dp.x - ppos.x, dp.z - ppos.z).length() < 1.55 and absf(dp.y - ppos.y) < 1.4:
						occupied = true
						break
		if not occupied and director.get("sandbox") != null:
			for hc: RigidBody3D in director.sandbox.heat_cores:
				if is_instance_valid(hc) and Vector2(hc.position.x - ppos.x, hc.position.z - ppos.z).length() < 1.55:
					occupied = true
					break
		var already_solved: bool = bool(solved.get(String(pp.puzzle), false))
		var active: bool = occupied or already_solved
		if active != bool(pp.pressed):
			pp.pressed = active
			(pp.pad as MeshInstance3D).position.y = 0.01 if active else 0.06
			_set_indicator(pp.mat as StandardMaterial3D, pp.light as OmniLight3D, Color("#34f29e") if active else Color("#ff9a32"), 2.4 if active else 1.8)
			if active:
				SfxKit.play_3d(self, "sfx_lever_clunk", ppos, -5.0, 1.25)
				changed_puzzles[String(pp.puzzle)] = true
	for pid: String in changed_puzzles.keys():
		_check_puzzle_completion(pid)

func _tick_dropped_cells_into_sockets() -> void:
	if director._items == null:
		return
	for fs: Dictionary in fuse_sockets:
		if bool(fs.powered):
			continue
		var fp: Vector3 = fs.pos as Vector3
		for entry: Dictionary in director._items.drops.duplicate():
			if String(entry.get("kind", "")) == "cell" and not bool(entry.get("placed", false)):
				if (entry.position as Vector3).distance_to(fp + Vector3.UP * 0.9) < 1.5:
					director._items.drops.erase(entry)
					director._items.publish()
					_power_fuse_socket(fs)
					break

func _power_fuse_socket(fs: Dictionary) -> void:
	if bool(fs.powered):
		return
	fs.powered = true
	(fs.cell_vis as MeshInstance3D).visible = true
	_set_indicator(fs.mat as StandardMaterial3D, fs.light as OmniLight3D, Color("#34f29e"), 2.8)
	if director.get("sandbox") != null:
		director.sandbox._spawn_explosion_fx((fs.pos as Vector3) + Vector3.UP * 1.1, Color("#34f29e"), 3.6)
	SfxKit.play_3d(self, "sfx_lever_clunk", fs.pos as Vector3, -3.5, 1.0)
	_broadcast("备用电池已卡入通电槽！绿灯亮起！")
	_check_puzzle_completion(String(fs.puzzle))

func _flip_catwalk_switch(sw: Dictionary) -> void:
	if bool(sw.flipped):
		return
	sw.flipped = true
	_set_indicator(sw.mat as StandardMaterial3D, sw.light as OmniLight3D, Color("#34f29e"), 2.8)
	if director.get("sandbox") != null:
		director.sandbox._spawn_explosion_fx((sw.pos as Vector3) + Vector3.UP * 1.2, Color("#4ef4ff"), 4.2)
	SfxKit.play_3d(self, "sfx_lever_clunk", sw.pos as Vector3, -3.0, 0.92)
	_broadcast("高空超控总闸已合闸！")
	_check_puzzle_completion(String(sw.puzzle))

func _tick_upgrades_passive(delta: float) -> void:
	# 1. 热风机超频（解开反应堆谜案）：手持热风机自动缓慢回能 +6/秒！
	if bool(upgrades.get("heater_overclock", false)) and director._items != null:
		for id: int in director.players.keys():
			var bag: Dictionary = director._items.ensure_bag(id)
			for slot: Dictionary in bag.slots:
				if String(slot.get("kind", "")) == "heater":
					slot["charge"] = minf(180.0, float(slot.get("charge", 180.0)) + delta * 6.0)
	# 2. 温室恒温模组 / 极光热护盾 / 热可可暖流 Buff：持续抵消极寒掉温！
	var passive_warmth: float = 0.0
	if bool(upgrades.get("cold_shield", false)):
		passive_warmth += 0.022
	if bool(upgrades.get("aurora_shield", false)):
		passive_warmth += 0.032
	for actor: Node3D in director.players.values():
		if actor is SpacePlayer3D and not actor.downed:
			var thermos_left: float = maxf(0.0, float(actor.get_meta("thermos_buff", 0.0)) - delta)
			var chips_left: float = maxf(0.0, float(actor.get_meta("chips_buff", 0.0)) - delta)
			actor.set_meta("thermos_buff", thermos_left)
			actor.set_meta("chips_buff", chips_left)
			var extra_warm: float = passive_warmth + (0.035 if thermos_left > 0.0 else 0.0)
			if extra_warm > 0.0 and actor.warmth < 1.45:
				actor.warmth = minf(1.5, actor.warmth + delta * extra_warm)

# ------------------------------------------------------------------ 玩家按 E 交互与提示（电池插槽 / 高空开关 / 抚摸小霜问线索）

func nearby_prompt(actor: SpacePlayer3D, selected_kind: String) -> String:
	if actor == null:
		return ""
	var p: Vector3 = actor.position
	for fs: Dictionary in fuse_sockets:
		if not bool(fs.powered) and p.distance_to(fs.pos as Vector3) < 2.8:
			return "按 E 插入【备用电池】通电" if selected_kind == "cell" else String(fs.label)
	for sw: Dictionary in catwalk_switches:
		if not bool(sw.flipped) and p.distance_to(sw.pos as Vector3) < 2.8:
			return "按 E 合上高空总闸"
	for av: Dictionary in acoustic_vaults:
		if not bool(av.shattered) and p.distance_to(av.pos as Vector3) < 3.2:
			return String(av.label)
	for ts: Dictionary in thermal_sensors:
		if not bool(ts.melted) and p.distance_to(ts.pos as Vector3) < 4.5:
			return String(ts.label)
	if director.get("sandbox") != null and not director.sandbox.helper_bot.is_empty():
		var bot_node: Node3D = director.sandbox.helper_bot.get("node") as Node3D
		if bot_node != null and p.distance_to(bot_node.position) < 3.2:
			return "按 E 拍拍【小霜】获取下一处未解谜案线索"
	return ""

func try_interact(peer_id: int) -> bool:
	var actor: SpacePlayer3D = director.players.get(peer_id) as SpacePlayer3D
	if actor == null:
		return false
	var p: Vector3 = actor.position
	var sel_kind: String = String(director._items.selected(peer_id).get("kind", "")) if director._items != null else ""
	for fs: Dictionary in fuse_sockets:
		if not bool(fs.powered) and p.distance_to(fs.pos as Vector3) < 2.8:
			if sel_kind == "cell" and not bool(director._items.ensure_bag(peer_id).equipment_active):
				director._items.take_selected(peer_id)
				director._items.publish()
				_power_fuse_socket(fs)
			else:
				director.tell(peer_id, "需要先在货架拿一块【备用电池】拿在手上，再按 E 插入通电！")
			return true
	for sw: Dictionary in catwalk_switches:
		if not bool(sw.flipped) and p.distance_to(sw.pos as Vector3) < 2.8:
			_flip_catwalk_switch(sw)
			return true
	if director.get("sandbox") != null and not director.sandbox.helper_bot.is_empty():
		var bot_node: Node3D = director.sandbox.helper_bot.get("node") as Node3D
		if bot_node != null and p.distance_to(bot_node.position) < 3.2:
			SfxKit.play_3d(self, "sfx_robot_chirp", bot_node.position, -2.5, 1.15)
			director.sandbox._spawn_explosion_fx(bot_node.position + Vector3.UP * 0.8, Color("#4ef4ff"), 4.6)
			director.tell(peer_id, next_mystery_hint())
			return true
	return false

# ------------------------------------------------------------------ 谜案完成判定 + 永久升级奖励 + 线索解锁

func _check_puzzle_completion(puzzle_id: String) -> void:
	if bool(solved.get(puzzle_id, false)):
		return
	var done: bool = false
	match puzzle_id:
		"living_acoustic":
			done = _all_vaults_shattered(puzzle_id)
		"greenhouse_thermal":
			done = _all_thermals_melted(puzzle_id)
		"drill_core":
			done = _all_fuses_powered(puzzle_id) and _all_plates_pressed(puzzle_id)
		"mech_kinetic":
			done = _all_switches_flipped(puzzle_id) and _all_targets_hit(puzzle_id)
		"observatory_star":
			done = _all_thermals_melted(puzzle_id) and _all_vaults_shattered(puzzle_id)
		"reactor_overdrive":
			done = _all_fuses_powered(puzzle_id) and _all_switches_flipped(puzzle_id)
	if done:
		_complete_puzzle(puzzle_id)

func _complete_puzzle(puzzle_id: String) -> void:
	solved[puzzle_id] = true
	if _conduit_mats.has(puzzle_id):
		for cm: StandardMaterial3D in (_conduit_mats[puzzle_id] as Array):
			_set_indicator(cm, null, Color("#34f29e"), 2.6)
	match puzzle_id:
		"living_acoustic":
			upgrades["med_boost"] = true
			for actor: Node3D in director.players.values():
				if actor is SpacePlayer3D:
					actor.health = 5
					actor.warmth = 1.5
			_spawn_reward_item("thermos", Vector3(60.2, 1.0, -52.2))
			_add_log("【医官日志】声波密柜已开！全员恢复满血满温 · 线索指向西侧【生态穹顶温室】冰封地热导管！")
		"greenhouse_thermal":
			upgrades["cold_shield"] = true
			if _greenhouse_light != null:
				_greenhouse_light.light_energy = 2.8
			_spawn_reward_item("keepsake", Vector3(-112.4, 1.0, -117.2))
			_add_log("【温室复苏】获得永久【抗寒恒温模组】并产出纪念杯 · 线索指向西北【冰川钻探中心】！")
		"drill_core":
			upgrades["suction_amp"] = true
			if _drill_beam != null:
				_drill_beam.visible = true
			if _drill_light != null:
				_drill_light.light_energy = 3.2
			_spawn_reward_item("keepsake", Vector3(-72.0, 1.2, -162.5))
			_add_log("【钻塔启机】冰芯钻塔全速运转！获得永久【磁力吸推增幅 +45%】· 线索指向东线【机甲维修厂】！")
		"mech_kinetic":
			upgrades["turbo_vehicles"] = true
			_add_log("【机甲涡轮解锁】雪地摩托与极地运输车永久提速 +35%！· 线索指向西翼【天文观测穹顶】！")
		"observatory_star":
			upgrades["aurora_shield"] = true
			if _aurora_beam != null:
				_aurora_beam.visible = true
			if _aurora_light != null:
				_aurora_light.light_energy = 3.2
			_add_log("【极光校准】巨型望远镜射出极光柱！获得永久【极光深寒护盾】· 线索指向东翼【地热反应堆电厂】！")
		"reactor_overdrive":
			upgrades["heater_overclock"] = true
			if _reactor_light != null:
				_reactor_light.light_energy = 3.6
			_add_log("【反应堆超频】便携热风机永久解锁【2 倍融冰 + 自动回能】！")

	if solved_count() == PUZZLE_IDS.size():
		_broadcast("★ 霜烬星六大科考谜案全部破译！已获称号【极地首席开拓者】与全套永久强化！")

func _spawn_reward_item(kind: String, pos: Vector3) -> void:
	if director._items == null:
		return
	var entry: Dictionary = {
		"kind": kind,
		"position": pos,
		"uid": "puzzle_reward_%s_%d" % [kind, director._items.next_uid],
		"safe_position": pos,
		"area": "frost_adventure",
		"placed": true,
		"yaw": 0.0,
	}
	director._items.next_uid += 1
	director._items.drops.append(entry)
	director._items.publish()

func _add_log(msg: String) -> void:
	if not discovered_logs.has(msg):
		discovered_logs.append(msg)
	_broadcast(msg)

func _broadcast(msg: String) -> void:
	for id: int in director.players.keys():
		director.tell(id, msg)

func _all_fuses_powered(pid: String) -> bool:
	for fs: Dictionary in fuse_sockets:
		if fs.puzzle == pid and not bool(fs.powered):
			return false
	return true

func _all_vaults_shattered(pid: String) -> bool:
	for av: Dictionary in acoustic_vaults:
		if av.puzzle == pid and not bool(av.shattered):
			return false
	return true

func _all_thermals_melted(pid: String) -> bool:
	for ts: Dictionary in thermal_sensors:
		if ts.puzzle == pid and not bool(ts.melted):
			return false
	return true

func _all_targets_hit(pid: String) -> bool:
	for kt: Dictionary in kinetic_targets:
		if kt.puzzle == pid and not bool(kt.hit):
			return false
	return true

func _all_plates_pressed(pid: String) -> bool:
	for pp: Dictionary in pressure_plates:
		if pp.puzzle == pid and not bool(pp.pressed):
			return false
	return true

func _all_switches_flipped(pid: String) -> bool:
	for sw: Dictionary in catwalk_switches:
		if sw.puzzle == pid and not bool(sw.flipped):
			return false
	return true

func solved_count() -> int:
	var n: int = 0
	for pid: String in PUZZLE_IDS:
		if bool(solved.get(pid, false)):
			n += 1
	return n

func next_mystery_hint() -> String:
	if not bool(solved.get("living_acoustic", false)):
		return "小霜线索 1/6：去东侧【生活医疗楼】医疗角，拿厨房架上的【复古音响】开启共振震碎结晶密柜！"
	if not bool(solved.get("greenhouse_thermal", false)):
		return "小霜线索 2/6：去西侧【生态穹顶温室】，用【信号弹/热风机/搬运热核】融解冰封地热导管！"
	if not bool(solved.get("drill_core", false)):
		return "小霜线索 3/6：去西北【冰川钻探中心】，插【备用电池】供电，再用【吸推器】把两只样本箱搬上双压板！"
	if not bool(solved.get("mech_kinetic", false)):
		return "小霜线索 4/6：去东线【机甲维修厂】，放【弹跳垫】跳上高空天桥合闸，并用【碰碰球】打亮三块动能靶心！"
	if not bool(solved.get("observatory_star", false)):
		return "小霜线索 5/6：去西翼【天文观测穹顶】，朝高处抛【信号弹】解热感锁，并放【复古音响】震开星图密柜！"
	if not bool(solved.get("reactor_overdrive", false)):
		return "小霜线索 6/6：去东翼【反应堆电厂】，插入 2 块【备用电池】，再放【弹跳垫】跃上高空合上过载总闸！"
	return "小霜欢呼：六大科考谜案已全部破解！快骑上涡轮雪地摩托冲进北方巨骨峡谷拿钥匙吧！"

func next_unsolved_beacon() -> Dictionary:
	var specs: Array = [
		["living_acoustic", "谜案·医疗密柜", Vector3(60.2, 1.0, -52.2)],
		["greenhouse_thermal", "谜案·温室热核", Vector3(-112.4, 1.0, -117.2)],
		["drill_core", "谜案·钻塔压板", Vector3(-72.0, 1.0, -162.0)],
		["mech_kinetic", "谜案·机甲靶场", Vector3(112.0, 2.0, -34.0)],
		["observatory_star", "谜案·天文星图", Vector3(-164.0, 2.0, -78.0)],
		["reactor_overdrive", "谜案·反应堆闸", Vector3(166.0, 2.0, -76.0)],
	]
	for sp: Array in specs:
		if not bool(solved.get(String(sp[0]), false)):
			return {"label": String(sp[1]), "pos": sp[2] as Vector3, "color": Color("#ff6ec7"), "main": false}
	return {}

func active_upgrade_tags() -> String:
	var tags: PackedStringArray = PackedStringArray()
	if bool(upgrades.get("cold_shield", false)): tags.append("抗寒")
	if bool(upgrades.get("suction_amp", false)): tags.append("吸推+")
	if bool(upgrades.get("turbo_vehicles", false)): tags.append("涡轮车+")
	if bool(upgrades.get("aurora_shield", false)): tags.append("极光盾")
	if bool(upgrades.get("heater_overclock", false)): tags.append("热枪超频")
	return " / ".join(tags) if not tags.is_empty() else "无（破译建筑谜案解锁）"

func journal_summary() -> String:
	var lines: PackedStringArray = PackedStringArray([
		"【霜烬星 · 六大科考谜案调查档案】(%d / 6)" % solved_count(),
		"  %s 1. 生活医疗楼 · 声波共振生物密柜（用【复古音响】共振解锁 -> 全员满血回温）" % ("✓" if bool(solved.get("living_acoustic", false)) else "☐"),
		"  %s 2. 生态穹顶温室 · 冻土热核复苏（用【信号弹/热风机/搬热核】融解 -> 抗寒护盾）" % ("✓" if bool(solved.get("greenhouse_thermal", false)) else "☐"),
		"  %s 3. 冰川钻探中心 · 电池槽+双压板（插【备用电池】+【吸推器】搬箱 -> 吸推增幅 +45%%）" % ("✓" if bool(solved.get("drill_core", false)) else "☐"),
		"  %s 4. 东线机甲维修厂 · 弹跳天桥+三靶（放【弹跳垫】上桥+【碰碰球】打靶 -> 载具提速 +35%%）" % ("✓" if bool(solved.get("mech_kinetic", false)) else "☐"),
		"  %s 5. 西翼天文观测穹顶 · 热感火盆+星图（抛【信号弹】入高盆+【音响】共振 -> 极光深寒盾）" % ("✓" if bool(solved.get("observatory_star", false)) else "☐"),
		"  %s 6. 东翼反应堆电厂 · 双电池+高空总闸（插 2【电池】+【弹跳垫】合闸 -> 热风机 2 倍超频）" % ("✓" if bool(solved.get("reactor_overdrive", false)) else "☐"),
		"",
		"【已解锁永久强化】" + active_upgrade_tags(),
		"【生活物资妙用】热可可 = 45 秒抗寒+冲刺 | 薯片 = 20 秒冲刺 | 拍拍小霜 = 获取下一处谜案指引",
	])
	if not discovered_logs.is_empty():
		lines.append("")
		lines.append("【已破译现场日志】")
		for lg: String in discovered_logs:
			lines.append(" · " + lg)
	return "\n".join(lines)

# ------------------------------------------------------------------ 多人联机状态同步

func snapshot() -> Dictionary:
	var fs_s: Array = []
	for fs: Dictionary in fuse_sockets: fs_s.append(bool(fs.powered))
	var av_s: Array = []
	for av: Dictionary in acoustic_vaults: av_s.append(bool(av.shattered))
	var ts_s: Array = []
	for ts: Dictionary in thermal_sensors: ts_s.append(bool(ts.melted))
	var kt_s: Array = []
	for kt: Dictionary in kinetic_targets: kt_s.append(bool(kt.hit))
	var sw_s: Array = []
	for sw: Dictionary in catwalk_switches: sw_s.append(bool(sw.flipped))
	return {
		"solved": solved.duplicate(true),
		"upgrades": upgrades.duplicate(true),
		"fs": fs_s, "av": av_s, "ts": ts_s, "kt": kt_s, "sw": sw_s,
	}

func apply_snapshot(data: Dictionary) -> void:
	if data.is_empty() or director.is_host:
		return
	solved = (data.get("solved", solved) as Dictionary).duplicate(true)
	upgrades = (data.get("upgrades", upgrades) as Dictionary).duplicate(true)
	var fs_s: Array = data.get("fs", [])
	for i: int in mini(fs_s.size(), fuse_sockets.size()):
		if bool(fs_s[i]) and not bool(fuse_sockets[i].powered):
			fuse_sockets[i].powered = true
			(fuse_sockets[i].cell_vis as MeshInstance3D).visible = true
			_set_indicator(fuse_sockets[i].mat as StandardMaterial3D, fuse_sockets[i].light as OmniLight3D, Color("#34f29e"), 2.8)
	var av_s: Array = data.get("av", [])
	for i: int in mini(av_s.size(), acoustic_vaults.size()):
		if bool(av_s[i]) and not bool(acoustic_vaults[i].shattered):
			acoustic_vaults[i].shattered = true
			(acoustic_vaults[i].dome as MeshInstance3D).visible = false
			(acoustic_vaults[i].ring as MeshInstance3D).visible = false
			_set_indicator(null, acoustic_vaults[i].light as OmniLight3D, Color("#34f29e"), 2.4)
	var ts_s: Array = data.get("ts", [])
	for i: int in mini(ts_s.size(), thermal_sensors.size()):
		if bool(ts_s[i]) and not bool(thermal_sensors[i].melted):
			thermal_sensors[i].melted = true
			(thermal_sensors[i].frost_cap as MeshInstance3D).visible = false
			_set_indicator(thermal_sensors[i].mat as StandardMaterial3D, thermal_sensors[i].light as OmniLight3D, Color("#34f29e"), 2.6)
	var kt_s: Array = data.get("kt", [])
	for i: int in mini(kt_s.size(), kinetic_targets.size()):
		if bool(kt_s[i]) and not bool(kinetic_targets[i].hit):
			kinetic_targets[i].hit = true
			_set_indicator(kinetic_targets[i].mat as StandardMaterial3D, kinetic_targets[i].light as OmniLight3D, Color("#34f29e"), 3.0)
	var sw_s: Array = data.get("sw", [])
	for i: int in mini(sw_s.size(), catwalk_switches.size()):
		if bool(sw_s[i]) and not bool(catwalk_switches[i].flipped):
			catwalk_switches[i].flipped = true
			_set_indicator(catwalk_switches[i].mat as StandardMaterial3D, catwalk_switches[i].light as OmniLight3D, Color("#34f29e"), 2.8)
	if _drill_beam != null: _drill_beam.visible = bool(solved.get("drill_core", false))
	if _aurora_beam != null: _aurora_beam.visible = bool(solved.get("observatory_star", false))
	if _greenhouse_light != null and bool(solved.get("greenhouse_thermal", false)): _greenhouse_light.light_energy = 2.8
	if _reactor_light != null and bool(solved.get("reactor_overdrive", false)): _reactor_light.light_energy = 3.6
