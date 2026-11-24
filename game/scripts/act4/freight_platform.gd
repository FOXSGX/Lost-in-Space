class_name FreightPlatform
extends AnimatableBody3D
## The suspended crystal freight platform.
##
## Design contract
## ---------------
## * The host/single-player process owns the motion, the tilt, the cargo slide
##   and the accident. There is exactly one simulation; observers receive a
##   snapshot (see `apply_net_state`).
## * The platform is an AnimatableBody3D with `sync_to_physics`, so a
##   CharacterBody3D standing on it is carried by the real moving collider.
## * Tilt is a damped spring driven by real load (riders + cargo), speed change
##   and a deliberate resonance impulse. The camera is never shaken to fake it.
## * Cargo is a controlled rigid body: its world transform is driven from a
##   2D slide model in deck space (inertia + gravity tangent + friction), so a
##   long constraint chain can never explode. It becomes a free RigidBody3D the
##   moment it leaves the cradle.
## * Every consequence has a recovery: brake, gain a handhold, clamp the cargo,
##   call the platform, lower the rescue winch, or use the maintenance ramp.

signal control_changed(owner_id: int)
signal cargo_state_changed(mode: String)
signal accident_warning_started(seconds: float)
signal accident_shock(strength: float)
signal accident_finished
signal dock_changed(dock_id: String)
signal grab_state_changed(peer_id: int, point_id: String, grabbed: bool)
signal notice(text: String)
signal delivered_changed(value: bool)
## Emitted after a player-operated control (brake / winch / clamp) is toggled;
## used by the host to credit Act 4 participation to the acting peer.
signal action_used(kind: String, peer_id: int)

## handle_control() result codes. A forwarded request is not a performed action:
## the Act 4 host reads this value instead of assuming that every intent it
## relayed to the platform really changed the world, so a refused lever or a
## taken handhold can never earn participation credit.
const RESULT_CREDIT := "credit"      # applied; counts as a participation action
const RESULT_APPLIED := "applied"    # applied; no new credit (release / toggle)
const RESULT_REJECTED := "rejected"  # refused; nothing changed
const RESULT_PENDING := "pending"    # client forwarded it to the host
## A client grab only lives while the host keeps confirming it. If the snapshot
## stream stops (host gone), the local rail constraint is dropped instead of
## pinning a body forever to a world that no longer updates.
const GRAB_AUTHORITY_TIMEOUT_MS := 2000

## =========================================================================
## MECHANICS-004B — 受约束动力学（CONSTRAINED DYNAMICS，不是完整刚体）
## =========================================================================
##
## 平台是沿悬吊轨道 1 自由度平移的机械，本身仍是运动学 `AnimatableBody3D`：
## 它不是 Jolt 里的自由刚体，也没有被 Jolt 求解的惯量。下面这条显式的
## 低自由度运动方程取代了原来的预设速度曲线（`TRAVEL_SPEED_*` / `ACCEL_*`
## 与 `move_toward(speed, target_speed, accel*delta)` 已经全部删除）：
##
##   M_eff · dv/dt = F_drive − F_brake − F_resist − F_grade
##
##   M_eff    = 平台自重 150 kg + 货台上真实刚体的质量 + 站在台上的玩家 80 kg/人
##   F_drive  = 执行器推力，由速度环给出并硬性钳制在 ±F_DRIVE_MAX
##   F_brake  = 安全制动，硬性钳制在 F_BRAKE_MAX，只在有速度时反复制方向
##   F_resist = 机构库仑阻力 + 粘滞阻力（与速度同号）
##   F_grade  = 0：轨道是水平吊索，没有真实坡度
##
## 速度是这条方程积分出来的，不是时间表。松开 W 后只剩阻力，平台继续滑行。
##
## 货物是**真实 16 kg RigidBody3D**：不冻结、不关碰撞、不写 global_transform。
## 让它跟着平台走的只有两件事：甲板/侧挡的真实接触，以及压板压在顶面上
## 产生的法向接触力。`cargo_attached` 只是“这趟运输算哪块晶体”的登记。
const DECK_SIZE := Vector3(3.2, 0.26, 3.2)
const DECK_HALF := Vector3(1.6, 0.0, 1.6)
const RAIL_TOP := 1.08
## 货台可承载区（平台局部；甲板顶面 y = 0）
const BAY_HALF_U := 0.92
const BAY_HALF_V := 0.60
## 晶体几何（与 PortableCrystal 一致）
const CRYSTAL_RADIUS := 0.34
const CRYSTAL_HEIGHT := 1.20
## 晶体静止时圆柱底面比甲板顶面低的那一点（Jolt 接触余量，实测约 2 cm）
const BAY_FLOOR_OFFSET := 0.02
## 掉出甲板的几何判定（平台局部坐标，纯几何越界后才解除货主登记）
const CARGO_FALL_U := 1.95
const CARGO_FALL_V := 1.75
const WARNING_SECONDS := 3.0
const SHOCK_RECOVERY_SECONDS := 2.4

# ---- 平台动力学参数 ------------------------------------------------------
const M_PLATFORM := 150.0
const M_RIDER := 80.0
const F_DRIVE_MAX := 620.0
const F_BRAKE_MAX := 1150.0
const F_RESIST_STATIC := 60.0
const F_RESIST_VISCOUS := 28.0
const F_GRADE := 0.0
## 电动驱动速度环增益（N per m/s 误差）。与 F_DRIVE_MAX 一起构成明确上限：
## 静止时满推力，接近设定速度时推力自然降到与阻力相等。
const DRIVE_GAIN := 420.0
## 操纵杆给的是**速度设定值**：满杆 = 向对岸 1.45 m/s，反向满杆 = 倒退。
const V_TRAVEL_MAX := 1.45
const V_MAX_SAFE := 3.2
const DRIVE_RAMP := 3.2
const BRAKE_FALLBACK := 4.6
## 货台刚体所在碰撞层（PortableCrystal 是 layer 8）
const CARGO_LAYER_MASK := 8
## 前方障碍探测：甲板上方 0.90 m 处向前探（太低会打到自己，太高会掠过障碍）
const BLOCK_PROBE_AHEAD := 1.72
const BLOCK_PROBE_DEPTH := 0.34
const BLOCK_PROBE_HEIGHT := 0.90

# ---- 货物夹具：四块水平合拢的侧挡 + 一只下压压板 -------------------------
## 侧挡**中心**到货台中心的距离（合拢 / 张开）。壁厚 CHOCK_THICKNESS，
## 所以合拢时内表面在 0.388 − 0.05 = 0.338 m，比晶体半径 0.34 小 2 mm：
## 侧挡真的压在晶体圆柱面上（2 mm 预紧），晶体要横向移动就必须推开实体壁。
## 2 mm 与 004A 锁爪的允许压入量一致，既保证接触又不会把晶体弹飞。
const CHOCK_INNER := 0.388
const CHOCK_OPEN := 1.20
const CHOCK_THICKNESS := 0.10
## 挡块高度。取 0.42 m：足够围住晶体底部提供横向约束，又不会挡住 1.20 m
## 高晶体的上半段 —— 玩家在运输途中必须能看见自己的货。
const CHOCK_HEIGHT := 0.42
const CHOCK_RATE := 0.42
## 压板：厚 0.12 m；张开 1.34，下压到晶体顶面 1.20 + 0.06 + 2 mm
const PRESS_PLATE_HALF := 0.06
## 压板平面尺寸：0.74 × 0.66（晶体直径 0.68，刚好盖住顶面）。
## 不能做得更大：玩家在操纵台驾驶时，过大的压板会把整个货台视线挡住。
const PRESS_PLATE_SIZE := Vector2(0.74, 0.66)
## 张开高度必须**高于晶体**（1.20 m），否则装卸时压板会和晶体体积重叠、
## 把晶体顶在板上（实测晶体落到 local y=1.36 而不是甲板 0.0）。
const PRESS_OPEN_Y := 1.80
const PRESS_MIN_Y := 1.14
## 压板下表面压入晶体顶面的深度（m）。取 2 mm 预紧：压板真的接触顶面，
## 与侧挡一起把晶体机械锁住；数值与 004A 锁爪的允许压入量一致。
const PRESS_PEN_ALLOW := -0.002
const PRESS_RATE := 0.42
const PRESS_TOL := 0.010
## 压板夹紧力的上限读数（N）。压板压住顶面后由 Jolt 法向接触提供约束；
## 这里只记录 HUD / 测试用的名义值，不额外施加脚本力（那会和求解器对抗）。
const PRESS_FORCE_READOUT := 220.0

# ---- 甲板摩擦 ------------------------------------------------------------
## 磨光钢格栅：摩擦系数低于启动加速度需求，未固定的晶体在加速/制动时会滑。
## 晶体自身 μ = 0.62，Jolt 取两者组合，因此固定后摩擦上限明显更高。
const DECK_FRICTION := 0.06

const SERVICE_DOWN_SPEED := 0.62
const SERVICE_UP_SPEED := 0.95
const RIDER_AREA_HEIGHT := 1.45
const GRAB_POINTS: Dictionary = {
	# Stand coordinates sit outside the open & sweeping side chocks (|x|>0.65+0.38
	# for N/S chocks, |z|>0.65+0.38 for E/W chocks) while staying inside the 3.2 m
	# deck and side rails (|z|<1.56-0.38). Verified by act4_freight_clamp.gd.
	"n1": {"rail": Vector3(-1.05, RAIL_TOP, -1.60), "stand": Vector3(-1.05, 0.0, -1.15)},
	"n2": {"rail": Vector3(1.05, RAIL_TOP, -1.60), "stand": Vector3(1.05, 0.0, -1.15)},
	"s1": {"rail": Vector3(-1.05, RAIL_TOP, 1.60), "stand": Vector3(-1.05, 0.0, 1.15)},
	"s2": {"rail": Vector3(1.05, RAIL_TOP, 1.60), "stand": Vector3(1.05, 0.0, 1.15)},
	"w1": {"rail": Vector3(-1.60, RAIL_TOP, -1.16), "stand": Vector3(-1.15, 0.0, -1.05)},
	"w2": {"rail": Vector3(-1.60, RAIL_TOP, 1.16), "stand": Vector3(-1.15, 0.0, 1.05)},
	"e1": {"rail": Vector3(1.60, RAIL_TOP, -1.16), "stand": Vector3(1.15, 0.0, -1.05)},
	"e2": {"rail": Vector3(1.60, RAIL_TOP, 1.16), "stand": Vector3(1.15, 0.0, 1.05)},
}

# ---- layout (set by FreightArena.configure) --------------------------------
var near_park_x: float = -8.8
var far_park_x: float = -14.7
var center_z: float = 3.0
var deck_travel_y: float = 2.6
var service_y: float = 0.2
var rail_y: float = 8.5

# ---- authoritative state ---------------------------------------------------
var travel_x: float = -8.8
var deck_y: float = 2.6
var speed: float = 0.0
var last_speed: float = 0.0
var drive_input: float = 0.0
var target_speed: float = 0.0
var brake_engaged: bool = false
var service_target: bool = false
var service_active: bool = false
var clamp_closed: bool = false
var clamp_t: float = 0.0
var control_owner: Node = null
var control_owner_id: int = 0
var grabs: Dictionary = {}          # player -> point_id
var grab_peer_by_point: Dictionary = {}  # point_id -> peer id (for prompts/net)
var cargo: Node = null
var cargo_attached: bool = false
var cargo_u: float = 0.0
var cargo_v: float = 0.0
var cargo_velocity: Vector2 = Vector2.ZERO
var cargo_loose: bool = false
var accident_phase: int = 0
var accident_timer: float = 0.0
var accident_fired: bool = false
var warning_level: float = 0.0
var stall_timer: float = 0.0
var delivered: bool = false
var ride_count: int = 0
var last_dock: String = "near"
var recall_to_x: float = INF
var net: Node = null
var authority: bool = true
var network_active: bool = false

# ---- 004B 动力学观测值（测试与 HUD 读真实受力结果）----------------------
const PhysicalLinkKit := preload("res://scripts/core/physical_link_kit.gd")
var _brake_lamp_mat: StandardMaterial3D
var _drive_lamp_mat: StandardMaterial3D
var _clamp_lamp_mat: StandardMaterial3D
var _brake_drive_wire_mat: ShaderMaterial
var last_force: float = 0.0
var last_mass_eff: float = M_PLATFORM
var drive_stalled: bool = false
var _drive_ramp: float = 0.0

# ---- 004B 夹具状态 -------------------------------------------------------
## `clamp_t` 现在是**压板行程的归一化位置**（0 = 张开，1 = 走到下限）。
## 它不再单独代表“夹住”：真正的夹持是 `jaw_locked`（侧挡合拢 + 压板压住）。
var jaw_pressing: bool = false
var jaw_locked: bool = false
var jaw_blocked: bool = false
var jaw_floor: float = PRESS_OPEN_Y
var jaw_side_inner: float = CHOCK_OPEN - CHOCK_THICKNESS * 0.5
var jaw_press_force: float = 0.0
var _press_y: float = PRESS_OPEN_Y
var _chock_pos: float = CHOCK_OPEN

## The body this process actually drives (Act 4 binds it). A client uses it to
## turn the host's grab table into rail state on its own CharacterBody3D; the
## host/solo side owns the authority path and never needs it.
var local_player: Node = null

# ---- internal --------------------------------------------------------------
var tilt_roll: float = 0.0
var tilt_pitch: float = 0.0
var _roll_vel: float = 0.0
var _pitch_vel: float = 0.0
var _accel_world: Vector3 = Vector3.ZERO
var _vertical_velocity: float = 0.0
var _last_deck_y: float = 2.6
var _riders: Array[Node] = []
var _trolley: Node3D
var _cables: Array[MeshInstance3D] = []
var _deck_anchors: Array[Vector3] = []
var _top_anchors: Array[Vector3] = []
var _clamp_sides: Array[Node3D] = []
var _clamp_press: Node3D
var _beacons: Array[MeshInstance3D] = []
var _beacon_materials: Array[StandardMaterial3D] = []
var _beacon_lights: Array[OmniLight3D] = []
var _warning_pylons: Array[Dictionary] = []
var _grip_marks: Dictionary = {}
var _rider_area: Area3D
var _drive_control: FreightControl
var _brake_control: FreightControl
var _clamp_control: FreightControl
var _winch_control: FreightControl
var _grab_controls: Dictionary = {}
var _audio: Node
var _beacon_clock: float = 0.0
var _warning_sound_clock: float = 0.0
var _shake_sent: bool = false

# Net interpolation targets (client only).
var _net_x: float = 0.0
var _net_y: float = 2.6

# 复用的载重探测形状/查询（`deck_bodies()` 每物理帧被 effective_mass() 调用）。
var _deck_probe_shape: BoxShape3D
var _deck_probe_query: PhysicsShapeQueryParameters3D
var _net_roll: float = 0.0
var _net_pitch: float = 0.0
var _net_cargo_u: float = 0.0
var _net_cargo_v: float = 0.0


var _last_snapshot_ms: int = 0


func _ready() -> void:
	name = "FreightPlatform"
	collision_layer = 1
	collision_mask = 0
	sync_to_physics = false
	add_to_group("freight_platform")
	add_to_group("freight_bay")
	_audio = get_tree().get_first_node_in_group("audio_director")
	_build_collision()
	_build_visuals()
	_build_controls()
	_build_rider_area()
	travel_x = near_park_x
	deck_y = deck_travel_y
	global_position = Vector3(travel_x, deck_y, center_z)


func configure(near_x: float, far_x: float, z_center: float, travel_y: float, service_height: float, rail_height: float) -> void:
	near_park_x = near_x
	far_park_x = far_x
	center_z = z_center
	deck_travel_y = travel_y
	service_y = service_height
	rail_y = rail_height
	travel_x = near_park_x
	deck_y = deck_travel_y
	global_position = Vector3(travel_x, deck_y, center_z)
	last_speed = 0.0
	if _trolley != null:
		_trolley.global_position = Vector3(travel_x, rail_y, center_z)
	_update_cables()


func bind_cables(trolley: Node3D, cables: Array[MeshInstance3D], top_anchors: Array[Vector3], deck_anchors: Array[Vector3]) -> void:
	_trolley = trolley
	_cables = cables
	_top_anchors = top_anchors
	_deck_anchors = deck_anchors
	if _trolley != null:
		_trolley.global_position = Vector3(travel_x, rail_y, center_z)
	_update_cables()


func register_warning_pylon(pylon: MeshInstance3D, base_energy: float) -> void:
	if pylon == null:
		return
	var material: StandardMaterial3D = MaterialLibrary.emissive(Color(0.45, 0.82, 1.0), base_energy).duplicate() as StandardMaterial3D
	pylon.material_override = material
	_warning_pylons.append({"mesh": pylon, "base": base_energy, "material": material})


# ---------------------------------------------------------------- geometry

func _build_collision() -> void:
	# 004B：甲板摩擦来自真实材质（磨光钢格栅 μ=0.06）。它低于启动加速度
	# 所需的 μ，所以未固定的晶体在加速/制动时真的会滑；固定后由侧挡与压板
	# 的真实接触提供约束。
	var plate: PhysicsMaterial = PhysicsMaterial.new()
	plate.friction = DECK_FRICTION
	plate.rough = true
	physics_material_override = plate
	_add_box_shape(Vector3(DECK_SIZE.x, DECK_SIZE.y, DECK_SIZE.z), Vector3(0.0, -DECK_SIZE.y * 0.5, 0.0), "DeckShape")
	# Rails: north and south are solid; east and west are loading gates with
	# corner posts only, so the platform can be boarded from either dock.
	_add_box_shape(Vector3(DECK_SIZE.x + 0.10, 0.92, 0.08), Vector3(0.0, 0.76, -1.60), "RailNorth")
	_add_box_shape(Vector3(DECK_SIZE.x + 0.10, 0.92, 0.08), Vector3(0.0, 0.76, 1.60), "RailSouth")
	# The east and west loading gates are deliberately open. Their corner posts
	# are visual only: a collision post at the berth threshold snagged players
	# walking from the dock onto the deck when the approach was not dead-centre.
	# The cargo lips and the two full-length side rails still contain the load.
	# Low cargo lips (west, north, south). The east side is the discharge gate.
	_add_box_shape(Vector3(0.10, 0.20, 1.28), Vector3(-0.95, 0.10, 0.0), "CargoLipWest")
	_add_box_shape(Vector3(1.90, 0.20, 0.10), Vector3(0.0, 0.10, -0.62), "CargoLipNorth")
	_add_box_shape(Vector3(1.90, 0.20, 0.10), Vector3(0.0, 0.10, 0.62), "CargoLipSouth")


func _add_box_shape(size_value: Vector3, position_value: Vector3, shape_name: String) -> void:
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.name = shape_name
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size_value
	shape.shape = box
	shape.position = position_value
	add_child(shape)


## 004B：夹具的真实碰撞体。
##   侧挡 ×4：每块一个 BoxShape3D（0.10 × 1.12 × 1.30），随水平行程移动
##   压板 ×1：挂在 `_clamp_press` 上，随 −y 行程移动
## 晶体要横向滑出去或翻倒，必须先推开这些实体。
## 004B：夹具的真实碰撞体。
##
## 每块侧挡与压板都是一只 `StaticBody3D`（layer 1）+ `CollisionShape3D`，
## 与 004A 锁爪完全相同的做法。CollisionShape3D 只有挂在 CollisionObject3D
## 下才会被物理服务器接收；挂在普通 Node3D 下会被静默忽略。
## 它们随 `_tick_clamp()` 的位移一起移动，所以接触是真正的几何接触。
func _build_clamp_colliders() -> void:
	for index: int in range(_clamp_sides.size()):
		var side_node: Node3D = _clamp_sides[index]
		if side_node == null:
			continue
		var along_z: bool = bool(side_node.get_meta("clamp_along_z", true))
		# AnimatableBody3D（不是 StaticBody3D）：侧挡每帧沿行程平移，静态体只能被
		# “瞬移”进求解器，没有扫掠速度，2 mm 预压会退化成穿透修正，把 16 kg 晶体
		# 弹出去。sync_to_physics 保持 false —— 实测（探针）false 才能正确传递接触，
		# true 反而让被承载物体下陷 0.41 m。
		var body: AnimatableBody3D = AnimatableBody3D.new()
		body.name = "SideWallBody%d" % index
		body.sync_to_physics = false
		body.collision_layer = 1
		body.collision_mask = 0
		var shape: CollisionShape3D = CollisionShape3D.new()
		shape.name = "SideWallShape%d" % index
		var box: BoxShape3D = BoxShape3D.new()
		box.size = Vector3(1.30, CHOCK_HEIGHT, CHOCK_THICKNESS) if along_z \
			else Vector3(CHOCK_THICKNESS, CHOCK_HEIGHT, 1.30)
		shape.shape = box
		shape.position = Vector3(0.0, CHOCK_HEIGHT * 0.5, 0.0)
		body.add_child(shape)
		side_node.add_child(body)
	if _clamp_press != null:
		var press_body: AnimatableBody3D = AnimatableBody3D.new()
		press_body.name = "PressPlateBody"
		press_body.sync_to_physics = false
		press_body.collision_layer = 1
		press_body.collision_mask = 0
		var press_shape: CollisionShape3D = CollisionShape3D.new()
		press_shape.name = "PressPlateShape"
		var press_box: BoxShape3D = BoxShape3D.new()
		press_box.size = Vector3(PRESS_PLATE_SIZE.x, PRESS_PLATE_HALF * 2.0,
			PRESS_PLATE_SIZE.y)
		press_shape.shape = press_box
		press_body.add_child(press_shape)
		_clamp_press.add_child(press_body)


func _build_visuals() -> void:
	var steel: StandardMaterial3D = MaterialLibrary.metal(Color(0.34, 0.38, 0.42), 0.48, 0.85)
	var dark: StandardMaterial3D = MaterialLibrary.metal(Color(0.12, 0.14, 0.16), 0.62, 0.55)
	var rust: StandardMaterial3D = MaterialLibrary.metal(Color(0.42, 0.24, 0.12), 0.84, 0.28)
	var hazard: StandardMaterial3D = MaterialLibrary.painted(Color(0.86, 0.55, 0.10), 0.55)
	var deck_plate: StandardMaterial3D = MaterialLibrary.metal(Color(0.26, 0.29, 0.32), 0.66, 0.55)
	var brass: StandardMaterial3D = MaterialLibrary.metal(Color(0.60, 0.44, 0.19), 0.40, 0.82)

	# Deck: a heavy frame with a grating surface and a visible underside.
	BuildKit.box_visual(self, "DeckPlate", Vector3(DECK_SIZE.x, 0.10, DECK_SIZE.z), Vector3(0.0, -0.05, 0.0), deck_plate)
	BuildKit.box_visual(self, "DeckFrame", Vector3(DECK_SIZE.x + 0.12, 0.16, DECK_SIZE.z + 0.12), Vector3(0.0, -0.18, 0.0), steel)
	BuildKit.box_visual(self, "DeckUnderBeamX", Vector3(DECK_SIZE.x + 0.24, 0.20, 0.20), Vector3(0.0, -0.32, 0.0), dark)
	for index: int in range(3):
		var z: float = -1.15 + float(index) * 1.15
		BuildKit.box_visual(self, "DeckRib%d" % index, Vector3(DECK_SIZE.x - 0.18, 0.07, 0.10), Vector3(0.0, 0.015, z), steel)
	for index: int in range(11):
		var x: float = -1.40 + float(index) * 0.28
		BuildKit.box_visual(self, "Grate%d" % index, Vector3(0.055, 0.018, DECK_SIZE.z - 0.20), Vector3(x, 0.005, 0.0), dark)
	# Hazard edges on the loading side and the flanks.
	BuildKit.box_visual(self, "HazardEastL", Vector3(0.16, 0.02, 0.62), Vector3(1.48, 0.012, -1.30), hazard)
	BuildKit.box_visual(self, "HazardEastR", Vector3(0.16, 0.02, 0.62), Vector3(1.48, 0.012, 1.30), hazard)
	BuildKit.box_visual(self, "HazardWest", Vector3(0.10, 0.02, DECK_SIZE.z - 0.12), Vector3(-1.54, 0.012, 0.0), hazard)
	# Corner cable lugs.
	for sx: int in range(2):
		for sz: int in range(2):
			var lx: float = -1.42 if sx == 0 else 1.42
			var lz: float = -1.42 if sz == 0 else 1.42
			BuildKit.box_visual(self, "CableLug%d%d" % [sx, sz], Vector3(0.24, 0.20, 0.24), Vector3(lx, 0.10, lz), rust)
			BuildKit.cylinder_visual(self, "CablePin%d%d" % [sx, sz], 0.045, 0.30,
				Vector3(lx, 0.24, lz), brass, Vector3(0.0, 0.0, 90.0))

	# Rails: two tubes plus posts, with a toe board.
	for side: int in range(2):
		var z: float = -1.60 if side == 0 else 1.60
		BuildKit.cylinder_visual(self, "RailTop%d" % side, 0.045, DECK_SIZE.x + 0.10,
			Vector3(0.0, RAIL_TOP, z), brass, Vector3(0.0, 0.0, 90.0))
		BuildKit.cylinder_visual(self, "RailMid%d" % side, 0.032, DECK_SIZE.x + 0.06,
			Vector3(0.0, 0.58, z), steel, Vector3(0.0, 0.0, 90.0))
		for index: int in range(4):
			var x: float = -1.45 + float(index) * 0.967
			BuildKit.cylinder_visual(self, "RailPost%d_%d" % [side, index], 0.035, 1.06,
				Vector3(x, 0.53, z), steel)
		BuildKit.box_visual(self, "ToeBoard%d" % side, Vector3(DECK_SIZE.x - 0.10, 0.14, 0.035),
			Vector3(0.0, 0.10, z), dark)
	# West loading gate: corner posts only (the middle is open).
	for index: int in range(2):
		var z: float = -1.16 if index == 0 else 1.16
		BuildKit.cylinder_visual(self, "GatePostW%d" % index, 0.05, 1.10,
			Vector3(-1.60, 0.55, z), steel)
		BuildKit.cylinder_visual(self, "GatePostWCap%d" % index, 0.07, 0.08,
			Vector3(-1.60, 1.10, z), hazard)
	# East corner posts only: the middle is the discharge gate.
	for side: int in range(2):
		var z: float = -1.16 if side == 0 else 1.16
		BuildKit.cylinder_visual(self, "GatePost%d" % side, 0.05, 1.10,
			Vector3(1.60, 0.55, z), steel)
		BuildKit.cylinder_visual(self, "GatePostCap%d" % side, 0.07, 0.08,
			Vector3(1.60, 1.10, z), hazard)

	# Cargo cradle: a machined socket with a brass guide line and three lips.
	BuildKit.box_visual(self, "BayFloor", Vector3(1.90, 0.06, 1.28), Vector3(0.0, 0.035, 0.0), dark)
	BuildKit.box_visual(self, "BayLipW", Vector3(0.10, 0.22, 1.28), Vector3(-0.95, 0.13, 0.0), hazard)
	BuildKit.box_visual(self, "BayLipN", Vector3(1.90, 0.22, 0.10), Vector3(0.0, 0.13, -0.64), hazard)
	BuildKit.box_visual(self, "BayLipS", Vector3(1.90, 0.22, 0.10), Vector3(0.0, 0.13, 0.64), hazard)
	BuildKit.box_visual(self, "BayGuide", Vector3(1.55, 0.008, 0.05), Vector3(0.0, 0.07, 0.0),
		MaterialLibrary.emissive(Color(0.95, 0.62, 0.20), 0.55))
	for index: int in range(6):
		var x: float = -0.75 + float(index) * 0.30
		BuildKit.box_visual(self, "BayStud%d" % index, Vector3(0.06, 0.04, 0.06),
			Vector3(x, 0.07, -0.54), rust)
	# ---- 004B：夹具是实体机构（四块水平合拢的侧挡 + 一只下压压板）--------
	# 侧挡张开时退到 CHOCK_OPEN = 1.20 m（完全让开装卸区），合拢后内表面停在
	# 晶体圆柱面外 1 cm，围成一个真正的方框。每块都带真实碰撞体；行程按
	# 0.42 m/s 逐帧推进（每帧约 7 mm），所以不会像瞬移那样把穿透修正能量
	# 灌进晶体。压板沿 −y 下压，落到晶体顶面 2 mm 处。
	for side: int in range(4):
		var side_node: Node3D = Node3D.new()
		side_node.name = "ClampSide%d" % side
		var along_z: bool = side < 2
		var sign: float = -1.0 if side % 2 == 0 else 1.0
		side_node.set_meta("clamp_along_z", along_z)
		side_node.set_meta("clamp_sign", sign)
		# 立刻放到张开位置：不能停在原点，否则会和落座的晶体重叠。
		side_node.position = Vector3(0.0, 0.0, sign * CHOCK_OPEN) if along_z \
			else Vector3(sign * CHOCK_OPEN, 0.0, 0.0)
		add_child(side_node)
		var wall_size: Vector3 = Vector3(1.30, CHOCK_HEIGHT, CHOCK_THICKNESS) if along_z \
			else Vector3(CHOCK_THICKNESS, CHOCK_HEIGHT, 1.30)
		BuildKit.box_visual(side_node, "SideWall%d" % side, wall_size,
			Vector3(0.0, CHOCK_HEIGHT * 0.5, 0.0), hazard)
		BuildKit.box_visual(side_node, "SidePad%d" % side,
			Vector3(1.10, 0.10, 0.03) if along_z else Vector3(0.03, 0.10, 1.10),
			Vector3(0.0, CHOCK_HEIGHT - 0.05, 0.0), dark)
		_clamp_sides.append(side_node)
	_clamp_press = Node3D.new()
	_clamp_press.name = "ClampPress"
	_clamp_press.position = Vector3(0.0, PRESS_OPEN_Y, 0.0)
	add_child(_clamp_press)
	BuildKit.box_visual(_clamp_press, "PressPlate",
		Vector3(PRESS_PLATE_SIZE.x, PRESS_PLATE_HALF * 2.0, PRESS_PLATE_SIZE.y),
		Vector3.ZERO, hazard)
	BuildKit.box_visual(_clamp_press, "PressPad",
		Vector3(PRESS_PLATE_SIZE.x - 0.06, 0.02, PRESS_PLATE_SIZE.y - 0.06),
		Vector3(0.0, -PRESS_PLATE_HALF, 0.0), dark)
	BuildKit.cylinder_visual(_clamp_press, "PressRod", 0.05, 0.55,
		Vector3(0.0, PRESS_PLATE_HALF + 0.27, 0.0), steel)
	_build_clamp_colliders()

	# Drive console: a sloped pedestal with a big lever and a small status lamp.
	BuildKit.box_visual(self, "ConsoleBase", Vector3(0.52, 0.78, 0.40), Vector3(-1.02, 0.39, -0.48), dark)
	BuildKit.box_visual(self, "ConsoleFace", Vector3(0.50, 0.30, 0.08), Vector3(-1.02, 0.84, -0.32), steel, Vector3(24.0, 0.0, 0.0))
	BuildKit.cylinder_visual(self, "ConsoleLever", 0.035, 0.46, Vector3(-1.02, 0.99, -0.48), brass, Vector3(18.0, 0.0, 0.0))
	BuildKit.sphere_visual(self, "ConsoleKnob", 0.075, Vector3(-1.02, 1.20, -0.55), hazard)
	BuildKit.box_visual(self, "ConsoleScreen", Vector3(0.30, 0.14, 0.015), Vector3(-1.02, 0.90, -0.30),
		MaterialLibrary.emissive(Color(0.32, 0.88, 1.0), 1.0), Vector3(24.0, 0.0, 0.0))
	# Brake pedestal at the rear.
	BuildKit.box_visual(self, "BrakeBase", Vector3(0.44, 0.82, 0.42), Vector3(1.05, 0.41, 0.86), dark)
	BuildKit.cylinder_visual(self, "BrakeLever", 0.045, 0.70, Vector3(1.05, 0.95, 0.86), rust, Vector3(-24.0, 0.0, 0.0))
	BuildKit.box_visual(self, "BrakeHandle", Vector3(0.20, 0.10, 0.10), Vector3(1.05, 1.30, 0.78), MaterialLibrary.emissive(Color(1.0, 0.20, 0.12), 1.2))
	BuildKit.box_visual(self, "BrakePlate", Vector3(0.30, 0.18, 0.02), Vector3(1.05, 0.86, 0.64),
		MaterialLibrary.emissive(Color(1.0, 0.30, 0.14), 0.8), Vector3(24.0, 0.0, 0.0))
	# Clamp lever beside the cradle.
	BuildKit.box_visual(self, "ClampBase", Vector3(0.34, 0.72, 0.30), Vector3(-0.20, 0.36, -1.05), dark)
	BuildKit.cylinder_visual(self, "ClampLever", 0.035, 0.52, Vector3(-0.20, 0.88, -1.05), hazard, Vector3(28.0, 0.0, 0.0))
	BuildKit.box_visual(self, "ClampLabel", Vector3(0.22, 0.10, 0.02), Vector3(-0.20, 0.74, -0.90),
		MaterialLibrary.emissive(Color(1.0, 0.72, 0.24), 0.7), Vector3(28.0, 0.0, 0.0))
	# Clear causal indicator lamps on drive / brake / clamp + interlock cable between brake and drive
	_drive_lamp_mat = PhysicalLinkKit.build_status_lamp(self, "PlatDriveLamp", Vector3(-1.02, 1.02, -0.22), 0.055, dark)
	_brake_lamp_mat = PhysicalLinkKit.build_status_lamp(self, "PlatBrakeLamp", Vector3(1.05, 0.90, 0.58), 0.055, dark)
	_clamp_lamp_mat = PhysicalLinkKit.build_status_lamp(self, "PlatClampLamp", Vector3(-0.20, 0.80, -0.82), 0.055, dark)
	_brake_drive_wire_mat = PhysicalLinkKit.make_flow_material(Color(0.24, 0.92, 1.0), 0.8, 1.0, 5.0)
	PhysicalLinkKit.build_conduit_run(self, "PlatBrakeInterlockWire", [
		Vector3(0.95, 0.04, 0.86),
		Vector3(0.10, 0.04, 0.45),
		Vector3(-0.92, 0.04, -0.38),
	], 0.022, dark, _brake_drive_wire_mat, Vector3.ZERO, false)
	PhysicalLinkKit.build_diagram_plaque(self, "PlatControlSchematic", Vector3(-0.56, 1.06, -0.78), Vector3(-14.0, 18.0, 0.0), Vector2(0.58, 0.24), [
		{"num": 1, "icon": "brake", "col": Color(1.0, 0.44, 0.22)},
		{"num": 2, "icon": "cart", "col": Color(0.32, 0.90, 1.0)},
		{"num": 3, "icon": "clamp", "col": Color(0.28, 0.96, 0.72)},
	], Color(1.0, 0.72, 0.24))
	# Rescue winch control on the west side.
	BuildKit.box_visual(self, "WinchBase", Vector3(0.34, 0.72, 0.30), Vector3(-1.02, 0.36, 0.86), dark)
	BuildKit.cylinder_visual(self, "WinchWheel", 0.16, 0.08, Vector3(-1.02, 0.86, 0.86), rust, Vector3(90.0, 0.0, 0.0))
	for index: int in range(4):
		var angle: float = TAU * float(index) / 4.0
		BuildKit.box_visual(self, "WinchSpoke%d" % index, Vector3(0.30, 0.025, 0.025),
			Vector3(-1.02 + cos(angle) * 0.13, 0.86 + sin(angle) * 0.13, 0.82), brass, Vector3(0.0, 0.0, rad_to_deg(angle)))

	# Beacons on the loading corners.
	for side: int in range(2):
		var z: float = -1.48 if side == 0 else 1.48
		var beacon_material: StandardMaterial3D = MaterialLibrary.emissive(Color(1.0, 0.55, 0.12), 0.2).duplicate() as StandardMaterial3D
		var beacon: MeshInstance3D = BuildKit.sphere_visual(self, "Beacon%d" % side, 0.075,
			Vector3(1.42, 1.32, z), beacon_material)
		beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_beacons.append(beacon)
		_beacon_materials.append(beacon_material)
		var light: OmniLight3D = BuildKit.omni_light(self, "BeaconLight%d" % side,
			Vector3(1.42, 1.36, z), Color(1.0, 0.48, 0.10), 0.0, 3.2, false)
		_beacon_lights.append(light)
	# Small work lamp over the deck.
	BuildKit.omni_light(self, "DeckWorkLight", Vector3(0.0, 2.05, 0.0), Color(1.0, 0.78, 0.52), 1.5, 5.0, false)
	BuildKit.box_visual(self, "DeckLampBar", Vector3(0.7, 0.08, 0.10), Vector3(0.0, 1.98, 0.0), dark)
	# Flush schematic badge on north rail (replaces Label3D text)
	PhysicalLinkKit.build_diagram_plaque(self, "PlatCapPlaque", Vector3(0.45, 0.96, -1.56), Vector3.ZERO, Vector2(0.72, 0.28), [
		{"num": 1, "icon": "crystal", "col": Color(0.32, 0.90, 1.0)},
		{"num": 2, "icon": "clamp", "col": Color(1.0, 0.72, 0.24)},
		{"num": 3, "icon": "platform", "col": Color(0.28, 0.96, 0.72)},
	], Color(0.95, 0.72, 0.24))


func _make_font() -> SystemFont:
	var font: SystemFont = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "SimHei", "sans-serif"])
	font.allow_system_fallback = true
	return font


func _build_controls() -> void:
	_drive_control = _make_control("drive", Vector3(-1.02, 1.10, -0.50), "", 1.55)
	_brake_control = _make_control("brake", Vector3(1.05, 1.22, 0.86), "", 1.45)
	_clamp_control = _make_control("clamp", Vector3(-0.20, 1.06, -1.06), "", 1.45)
	_winch_control = _make_control("winch", Vector3(-1.02, 1.04, 0.86), "onboard", 1.45)
	for point_id: String in GRAB_POINTS.keys():
		var data: Dictionary = GRAB_POINTS[point_id] as Dictionary
		var rail: Vector3 = data["rail"] as Vector3
		var control: FreightControl = _make_control("grab", rail + Vector3(0.0, 0.06, 0.0), point_id, 2.25)
		_grab_controls[point_id] = control
		# A visible grip sleeve makes the handhold a real object, not a prompt.
		var grip_material: StandardMaterial3D = MaterialLibrary.painted(Color(0.72, 0.52, 0.20), 0.55)
		if point_id.begins_with("e"):
			grip_material = MaterialLibrary.painted(Color(0.82, 0.28, 0.12), 0.55)
		var sleeve: MeshInstance3D = BuildKit.cylinder_visual(self, "Grip_" + point_id, 0.062, 0.24,
			rail, grip_material, Vector3(90.0, 0.0, 0.0) if point_id.begins_with("e") or point_id.begins_with("w") else Vector3(0.0, 0.0, 90.0))
		sleeve.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mark_material: StandardMaterial3D = MaterialLibrary.emissive(Color(0.36, 0.92, 1.0), 0.35).duplicate() as StandardMaterial3D
		var mark: MeshInstance3D = BuildKit.sphere_visual(self, "GripMark_" + point_id, 0.035,
			rail + Vector3(0.0, 0.08, 0.0), mark_material)
		mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_grip_marks[point_id] = mark


func _make_control(kind_value: String, local_position: Vector3, dock_value: String, reach_value: float) -> FreightControl:
	var control: FreightControl = FreightControl.new()
	control.name = "Control_" + kind_value + (("_" + dock_value) if not dock_value.is_empty() else "")
	control.position = local_position
	add_child(control)
	control.setup(self, kind_value, dock_value, reach_value)
	return control


func _build_rider_area() -> void:
	_rider_area = Area3D.new()
	_rider_area.name = "RiderArea"
	_rider_area.collision_layer = 0
	_rider_area.collision_mask = 2
	_rider_area.monitoring = true
	_rider_area.monitorable = false
	add_child(_rider_area)
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(DECK_SIZE.x - 0.10, RIDER_AREA_HEIGHT, DECK_SIZE.z - 0.10)
	shape.shape = box
	shape.position = Vector3(0.0, RIDER_AREA_HEIGHT * 0.5, 0.0)
	_rider_area.add_child(shape)
	_rider_area.body_entered.connect(_on_rider_entered)
	_rider_area.body_exited.connect(_on_rider_exited)


func _on_rider_entered(body: Node) -> void:
	if not body is CharacterBody3D:
		return
	if not _riders.has(body):
		_riders.append(body)
		body.set("freight_platform", self)


func _on_rider_exited(body: Node) -> void:
	_riders.erase(body)
	if body.get("freight_platform") == self:
		body.set("freight_platform", null)


## The Area3D signals alone miss a teleport inside the same area (reset, test
## station move). Polling the overlap keeps the rider list and the player's
## `freight_platform` link exact, at the cost of two body queries per frame.
func _refresh_riders() -> void:
	if _rider_area == null:
		return
	var bodies: Array[Node3D] = _rider_area.get_overlapping_bodies()
	for body: Node3D in bodies:
		if not body is CharacterBody3D:
			continue
		if not _riders.has(body):
			_riders.append(body)
		body.set("freight_platform", self)
	for rider: Node in _riders.duplicate():
		if not is_instance_valid(rider) or not bodies.has(rider):
			_riders.erase(rider)
			if is_instance_valid(rider) and rider.get("freight_platform") == self:
				rider.set("freight_platform", null)


# ----------------------------------------------------------------- physics

func _physics_process(delta: float) -> void:
	if network_active and not authority:
		_apply_net_interpolation(delta)
		_guard_local_grab_authority()
		_update_visual_state(delta)
		return

	last_speed = speed
	var was_moving: bool = absf(speed) > 0.02
	_refresh_riders()
	_last_deck_y = deck_y
	_tick_timers(delta)
	_tick_service(delta)
	if recall_to_x != INF:
		_tick_recall(delta)
	else:
		_tick_drive(delta)
	_tick_accident(delta)
	_tick_tilt(delta)
	global_position = Vector3(travel_x, deck_y, center_z)
	rotation = Vector3(tilt_pitch, 0.0, tilt_roll)
	_vertical_velocity = (deck_y - _last_deck_y) / maxf(delta, 0.0001)
	_accel_world = global_transform.basis.x * ((speed - last_speed) / maxf(delta, 0.0001))
	_tick_cargo(delta)
	_tick_grab_positions()
	_update_visual_state(delta)
	if _trolley != null:
		_trolley.global_position = Vector3(travel_x, rail_y, center_z)
	_update_cables()
	if was_moving and absf(speed) <= 0.02 and not service_active:
		_emit_dock_if_arrived()


func _tick_timers(delta: float) -> void:
	stall_timer = maxf(stall_timer - delta, 0.0)
	if control_owner != null and not is_instance_valid(control_owner):
		control_owner = null
		control_owner_id = 0
		control_changed.emit(0)
	# Drop stale grab references (a player can be freed by a reset) together
	# with the handhold they were holding, so no point stays taken.
	_prune_stale_grabs()
	# 004B：夹具行程完全由 `_tick_clamp()` 按真实位置推进（见 `_tick_cargo`）。
	# 这里不再用固定速率挪 `clamp_t`，否则空货台也会“夹到底”。
	if cargo == null:
		clamp_closed = false
		jaw_pressing = false
		jaw_locked = false


func _tick_service(delta: float) -> void:
	var dock: String = current_dock()
	var can_service: bool = dock != "" and absf(speed) < 0.08
	if service_target and not can_service:
		service_target = false
		notice.emit("先把平台停稳在装货台，才能放下绞盘。")
	var target_y: float = service_y if service_target else deck_travel_y
	if absf(deck_y - target_y) > 0.002:
		var rate: float = SERVICE_DOWN_SPEED if service_target else SERVICE_UP_SPEED
		deck_y = move_toward(deck_y, target_y, rate * delta)
		service_active = absf(deck_y - deck_travel_y) > 0.05
		if absf(deck_y - target_y) <= 0.002:
			service_active = false
			if service_target:
				notice.emit("救援绞盘已放下。让队友上平台。")
	else:
		service_active = false


## 1 自由度受力模型。速度是这里积出来的，不是预设曲线。
func _tick_drive(delta: float) -> void:
	if service_active or deck_y < deck_travel_y - 0.15:
		# 救援绞盘放下时机构互锁：只有阻力在作用，没有驱动。
		var lock_mass: float = effective_mass()
		speed += (_resist_force(lock_mass, speed) / lock_mass) * delta
		speed = move_toward(speed, 0.0, BRAKE_FALLBACK * delta)
		drive_input = 0.0
		last_force = 0.0
		last_mass_eff = lock_mass
		travel_x += speed * delta
		park_at_limits()
		return
	var mass_eff: float = effective_mass()
	var force: float = 0.0
	var blocked: bool = _blocked_ahead()
	var driving: bool = false
	if stall_timer > 0.0:
		# 共振冲击后的机构卡滞：推力被切断，只剩阻力把速度啃掉。
		drive_input = 0.0
		_drive_ramp = 0.0
		force += _resist_force(mass_eff, speed)
	elif brake_engaged:
		# 真实制动输入：反复制方向的力，硬性钳制在 F_BRAKE_MAX。
		if absf(speed) > 0.02:
			force -= signf(speed) * F_BRAKE_MAX
		_drive_ramp = 0.0
		force += _resist_force(mass_eff, speed)
	elif control_owner != null and drive_input != 0.0 and not blocked:
		# 速度环：操纵杆给设定速度，执行器用有上限的推力去追它。
		_drive_ramp = minf(1.0, _drive_ramp + DRIVE_RAMP * delta)
		var setpoint: float = clampf(drive_input, -1.0, 1.0) * V_TRAVEL_MAX
		force += clampf(DRIVE_GAIN * (setpoint - speed), -F_DRIVE_MAX, F_DRIVE_MAX) * _drive_ramp
		force += _resist_force(mass_eff, speed) - F_GRADE
		driving = true
	else:
		# 松开输入：没有推力，只有机构阻力让它滑行减速（不是瞬间归零）。
		_drive_ramp = 0.0
		force += _resist_force(mass_eff, speed) - F_GRADE
		if blocked and control_owner != null:
			drive_stalled = true
	# 到站前按剩余距离施加真实制动力（不是倒计时）。
	force += _park_brake_force(mass_eff)
	speed += (force / mass_eff) * delta
	speed = clampf(speed, -V_MAX_SAFE, V_MAX_SAFE)
	# 静摩擦：只有**没有驱动输入**时，速度很小且合力不足以克服静阻力才停住。
	if not driving and absf(speed) < 0.012 and absf(force) < F_RESIST_STATIC:
		speed = 0.0
	last_force = force
	last_mass_eff = mass_eff
	travel_x += speed * delta
	park_at_limits()


## 真实的库仑 + 粘滞阻力，方向永远与速度相反。
func _resist_force(_mass_eff: float, v: float) -> float:
	if absf(v) < 0.004:
		return 0.0
	return -signf(v) * (F_RESIST_STATIC + F_RESIST_VISCOUS * absf(v)) + F_GRADE


## 端位硬限位：越过就夹住并把速度清零（限位吸收动能），不穿透也不弹飞。
func park_at_limits() -> void:
	if travel_x >= near_park_x:
		travel_x = near_park_x
		if speed > 0.0:
			speed = 0.0
			_drive_ramp = 0.0
	if travel_x <= far_park_x:
		travel_x = far_park_x
		if speed < 0.0:
			speed = 0.0
			_drive_ramp = 0.0


## 前方被真实物理体挡住时不再推进（只探测碰撞体，不做剧情判断）。
## 采样段必须落在**行进方向前方**：甲板半宽 1.6 m，旧写法用 `-direction`
## 把 1.72→1.38 m 的射线放在车尾后方 0.1–0.3 m 处，前方障碍永远测不到，
## drive_stalled 也就永远不会因为真实阻挡而成立。
func _blocked_ahead() -> bool:
	if absf(speed) < 0.01:
		return false
	var direction: float = signf(speed)
	var origin: Vector3 = global_position + Vector3(
		direction * BLOCK_PROBE_AHEAD, BLOCK_PROBE_HEIGHT, 0.0)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		origin, origin + Vector3(direction * BLOCK_PROBE_DEPTH, 0.0, 0.0), 1)
	query.exclude = [get_rid()]
	query.collide_with_bodies = true
	query.collide_with_areas = false
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## 接近端位时施加与运动方向相反的真实制动力，让到站是减速的结果。
func _park_brake_force(mass_eff: float) -> float:
	var target: float = INF
	if speed > 0.02:
		target = near_park_x
	elif speed < -0.02:
		target = far_park_x
	if target == INF:
		return 0.0
	var distance: float = absf(target - travel_x)
	if distance > 1.6:
		return 0.0
	var needed: float = mass_eff * (speed * speed) / maxf(2.0 * distance, 0.05)
	return -signf(speed) * minf(needed, F_BRAKE_MAX * 0.85)


## 有效总质量 = 平台自重 + 货台上真实刚体的质量 + 站在台上的玩家。
func effective_mass() -> float:
	var mass: float = M_PLATFORM
	for body: Node in deck_bodies():
		mass += float(body.get("mass"))
	for rider: Node in _riders:
		if is_instance_valid(rider):
			mass += M_RIDER
	return mass


## 台面上真实存在的刚体（用 Jolt 重叠查询，不是脚本记账）。
## 形状与查询对象缓存复用：`effective_mass()` 每个物理帧都会调这里，旧写法
## 每帧新建 1 个 BoxShape3D + 1 个 PhysicsShapeQueryParameters3D + 1 个 Array。
func deck_bodies() -> Array[Node]:
	var bodies: Array[Node] = []
	if not is_inside_tree():
		return bodies
	if _deck_probe_shape == null:
		_deck_probe_shape = BoxShape3D.new()
		_deck_probe_shape.size = Vector3(DECK_SIZE.x - 0.12, 1.5, DECK_SIZE.z - 0.12)
	if _deck_probe_query == null:
		_deck_probe_query = PhysicsShapeQueryParameters3D.new()
		_deck_probe_query.shape = _deck_probe_shape
		_deck_probe_query.collision_mask = CARGO_LAYER_MASK
		_deck_probe_query.collide_with_bodies = true
		_deck_probe_query.collide_with_areas = false
	_deck_probe_query.transform = Transform3D(Basis.IDENTITY, global_position + Vector3(0.0, 0.78, 0.0))
	for hit: Dictionary in get_world_3d().direct_space_state.intersect_shape(_deck_probe_query, 8):
		var collider: Node = hit.get("collider") as Node
		if collider is RigidBody3D and collider != self and not _riders.has(collider):
			bodies.append(collider)
	return bodies


## 载重指数（0..1）：只用于倾斜弹簧与提示，不再参与速度上限的计算。
func _load_factor() -> float:
	var mass: float = 0.0
	for rider: Node in _riders:
		if is_instance_valid(rider):
			mass += M_RIDER
	for body: Node in deck_bodies():
		mass += float(body.get("mass"))
	return clampf(mass / 240.0, 0.0, 1.0)


func _tick_accident(delta: float) -> void:
	if accident_phase == 0:
		if cargo_attached and not accident_fired and speed > 0.12 and travel_x > far_park_x + 0.25:
			accident_phase = 1
			accident_timer = WARNING_SECONDS
			warning_level = 0.0
			accident_warning_started.emit(WARNING_SECONDS)
			notice.emit("断层共振在上升——固定晶体，抓好扶手，或者减速！")
		return
	if accident_phase == 1:
		accident_timer -= delta
		warning_level = clampf(1.0 - accident_timer / WARNING_SECONDS, 0.0, 1.0)
		if accident_timer <= 0.0:
			_fire_shock()
		return
	if accident_phase == 2:
		accident_timer -= delta
		warning_level = clampf(accident_timer / SHOCK_RECOVERY_SECONDS, 0.0, 1.0) * 0.35
		if accident_timer <= 0.0:
			accident_phase = 0
			warning_level = 0.0
			accident_finished.emit()
		return


func _fire_shock() -> void:
	accident_phase = 2
	accident_timer = SHOCK_RECOVERY_SECONDS
	accident_fired = true
	var speed_factor: float = clampf(absf(speed) / V_TRAVEL_MAX, 0.35, 1.0)
	var strength: float = 0.55 + 0.45 * speed_factor
	_roll_vel += 1.45 * strength
	_pitch_vel -= 0.55 * strength
	stall_timer = 1.25
	cargo_loose = true
	# 004B：冲击给真实刚体一个**真实冲量**。已夹持的晶体只受到很小扰动
	# （侧挡和压板把它挡住），没夹持的会被明显推开 —— 差别来自接触，不是脚本。
	if cargo != null and is_instance_valid(cargo) and cargo is RigidBody3D:
		var body: RigidBody3D = cargo as RigidBody3D
		var magnitude: float = 0.22 if is_cargo_fixed() else 1.45
		body.apply_central_impulse(
			global_transform.basis * Vector3(magnitude * strength, 0.0, 0.42 * strength) * body.mass)
	# Only a player who is not holding a rail loses footing. The impulse is along
	# the real deck axes (toward the open discharge gate and the low side).
	for rider: Node in _riders:
		if not is_instance_valid(rider):
			continue
		if grabs.has(rider):
			rider.call("shake", 0.12, 0.4)
			continue
		var impulse: Vector3 = global_transform.basis * Vector3(1.25 * strength, 0.22, 0.55 * strength)
		rider.call("apply_platform_knock", impulse)
		rider.call("shake", 0.18, 0.5)
	accident_shock.emit(strength)
	_play("resonance_strike", global_position, 1.0, 0.82)
	_play("alarm_loop", global_position, 0.35, 1.0)


func _tick_tilt(delta: float) -> void:
	var rider_u: float = 0.0
	var rider_v: float = 0.0
	var rider_n: float = 0.0
	for rider: Node in _riders:
		if not is_instance_valid(rider):
			continue
		var local: Vector3 = to_local((rider as Node3D).global_position)
		rider_u += clampf(local.x, -1.3, 1.3)
		rider_v += clampf(local.z, -1.1, 1.1)
		rider_n += 1.0
	if rider_n > 0.0:
		rider_u /= rider_n
		rider_v /= rider_n
	var target_roll: float = clampf(rider_v * 0.045 + cargo_v * 0.12, -0.22, 0.22)
	var target_pitch: float = clampf(-rider_u * 0.030 - cargo_u * 0.075 - _accel_world.dot(global_transform.basis.x) * 0.020, -0.16, 0.16)
	if brake_engaged and absf(speed) > 0.4:
		target_pitch -= 0.05
	var spring: float = 26.0
	var damp: float = 7.0
	_roll_vel += (-spring * (tilt_roll - target_roll) - damp * _roll_vel) * delta
	_pitch_vel += (-spring * (tilt_pitch - target_pitch) - damp * _pitch_vel) * delta
	tilt_roll = clampf(tilt_roll + _roll_vel * delta, -0.30, 0.30)
	tilt_pitch = clampf(tilt_pitch + _pitch_vel * delta, -0.22, 0.22)


## 004B：货物只是**登记**，不是被托管的物体。
##
## 这里**不写** `global_transform`、不冻结、不关碰撞。晶体是否跟着平台走，
## 完全由 Jolt 的接触决定：甲板摩擦 + 四块侧挡 + 下压压板的法向接触。
## 本函数只做三件事：读回真实状态、推进夹具行程、在真实越界时解除登记。
func _tick_cargo(delta: float) -> void:
	if not cargo_attached:
		return
	# A freed cargo node must not latch this platform shut: `is_cargo_fixed()`
	# would keep returning false, `seat_cargo()` would keep refusing (cargo !=
	# null) and the clamp could never move again — the freight stage becomes
	# unrecoverable until a full level reset.
	if cargo == null or not is_instance_valid(cargo):
		cargo = null
		cargo_attached = false
		cargo_u = 0.0
		cargo_v = 0.0
		cargo_velocity = Vector2.ZERO
		_retract_clamp()
		return
	var body: RigidBody3D = cargo as RigidBody3D
	if body == null:
		return
	var local: Vector3 = to_local(body.global_position)
	cargo_u = local.x
	cargo_v = local.z
	cargo_velocity = Vector2(body.linear_velocity.dot(global_transform.basis.x),
		body.linear_velocity.dot(global_transform.basis.z))
	_tick_clamp(delta, body, local)
	# 掉出甲板：只有真实位置越界才算，不是脚本判定“滑出去”。
	if absf(local.z) > CARGO_FALL_V or local.x > CARGO_FALL_U or local.x < -CARGO_FALL_U \
			or local.y < -0.65:
		_drop_cargo_overboard()


## 夹具行程与真实接触。
##
## 004B 的夹具是「四块水平合拢的侧挡 + 一只下压压板」：
##
##   * `ClampSide0..3` 沿平台局部 ±x / ±z 水平合拢，内表面停在
##     CHOCK_INNER − CHOCK_THICKNESS/2 = 0.35 m（晶体半径 0.34 + 1 cm 间隙），
##     围成一个真正的方框。每块带真实 CollisionShape3D，合拢时会真的挡住
##     晶体：晶体要横向滑出去或翻倒，必须先推开它们。
##   * `ClampPress` 沿平台局部 −y 下压，落到晶体顶面 2 mm 处。它带真实碰撞体，
##     压在晶体顶面上，Jolt 的法向接触力抬高摩擦上限。
##
## 两段行程都是**位移驱动**（每帧约 0.42·dt ≈ 7 mm，与 Jolt 的碰撞检测同量级），
## 所以不会像瞬移那样把穿透修正能量灌进晶体。
func _tick_clamp(delta: float, body: RigidBody3D, local: Vector3) -> void:
	var inside: bool = absf(local.z) <= BAY_HALF_V + 0.30 \
		and absf(local.x) <= BAY_HALF_U + 0.30
	# ---- 侧挡：水平合拢 / 张开（纯位移）----
	var side_target: float = CHOCK_INNER if (clamp_closed and inside) else CHOCK_OPEN
	_chock_pos = move_toward(_chock_pos, side_target, CHOCK_RATE * delta)
	for index: int in range(_clamp_sides.size()):
		var side_node: Node3D = _clamp_sides[index]
		if side_node == null:
			continue
		var along_z: bool = bool(side_node.get_meta("clamp_along_z", true))
		var sign: float = float(side_node.get_meta("clamp_sign", 1.0))
		if along_z:
			side_node.position = Vector3(0.0, 0.0, sign * _chock_pos)
		else:
			side_node.position = Vector3(sign * _chock_pos, 0.0, 0.0)
	jaw_side_inner = _chock_pos - CHOCK_THICKNESS * 0.5
	var sides_closed: bool = _chock_pos <= CHOCK_INNER + 0.01
	# ---- 压板：下压 / 抬起（纯位移）----
	# 目标高度必须在**世界竖直方向**上算：平台有 tilt（横滚最多 0.30 rad），
	# `to_local().y` 会混进倾斜分量（实测晶体 local.y 从 −0.02 涨到 1.36），
	# 用它会把压板顶到 2.6 m 之外，永远贴不到晶体顶面。
	# 先求“压板下表面该停在的世界高度”，再换算成压板自己的局部 y。
	var crystal_top_world: float = body.global_position.y + CRYSTAL_HEIGHT - BAY_FLOOR_OFFSET
	var plate_bottom_world: float = crystal_top_world + PRESS_PEN_ALLOW
	var plate_center_world: float = plate_bottom_world + PRESS_PLATE_HALF
	# 平台局部 +y 在当前姿态下对应的世界 y 分量（tilt 后 < 1）
	var up_y: float = maxf(global_transform.basis.y.y, 0.30)
	var base_origin_y: float = global_transform.origin.y
	jaw_floor = (plate_center_world - base_origin_y) / up_y
	if not inside:
		jaw_floor = PRESS_OPEN_Y
	var plate_target: float = maxf(PRESS_MIN_Y, jaw_floor) if clamp_closed else PRESS_OPEN_Y
	var rate: float = PRESS_RATE * delta
	var previous_y: float = _press_y
	_press_y = move_toward(_press_y, plate_target, rate)
	jaw_blocked = clamp_closed and inside and absf(_press_y - jaw_floor) < 0.0025 \
		and absf(previous_y - _press_y) < rate * 0.5
	jaw_pressing = clamp_closed and inside and _press_y <= jaw_floor + PRESS_TOL
	clamp_t = clampf(inverse_lerp(PRESS_OPEN_Y, PRESS_MIN_Y, _press_y), 0.0, 1.0)
	_apply_press_visual(_press_y)
	jaw_press_force = PRESS_FORCE_READOUT if jaw_pressing else 0.0
	jaw_locked = jaw_pressing and sides_closed


## 把压板的真实行程画到碰撞体上（视觉与碰撞同源）。
func _apply_press_visual(y_value: float) -> void:
	if _clamp_press != null:
		_clamp_press.position.y = y_value


## 夹具回到张开位。
##
## 这一步必须与“有没有货”无关：`_tick_clamp()` 只在 cargo 已登记时才被调用
## （_tick_cargo 在 cargo 为空时提前 return），所以任何释放路径若只把
## clamp_closed 置 false，侧挡碰撞体会永久停在 CHOCK_INNER（内表面 0.338 m，
## 已经压进半径 0.34 m 的晶体），压板也会冻在 ~1.14 m。下一次装同一颗晶体时，
## 静态重叠直接交给 Jolt 的穿透修正 —— 表现为“第二次装车必定被弹出”。
func _retract_clamp() -> void:
	clamp_closed = false
	jaw_pressing = false
	jaw_locked = false
	jaw_blocked = false
	jaw_press_force = 0.0
	_chock_pos = CHOCK_OPEN
	jaw_side_inner = CHOCK_OPEN - CHOCK_THICKNESS * 0.5
	_press_y = PRESS_OPEN_Y
	clamp_t = 0.0
	for index: int in range(_clamp_sides.size()):
		var side_node: Node3D = _clamp_sides[index]
		if side_node == null:
			continue
		var along_z: bool = bool(side_node.get_meta("clamp_along_z", true))
		var sign_value: float = float(side_node.get_meta("clamp_sign", 1.0))
		if along_z:
			side_node.position = Vector3(0.0, 0.0, sign_value * _chock_pos)
		else:
			side_node.position = Vector3(sign_value * _chock_pos, 0.0, 0.0)
	_apply_press_visual(_press_y)


## 解除货主登记。晶体一个字节的物理状态都不改 —— 它本来就是自由刚体。
func _drop_cargo_overboard() -> void:
	if cargo == null:
		return
	var lost: Node = cargo
	cargo = null
	cargo_attached = false
	cargo_loose = true
	cargo_u = 0.0
	cargo_v = 0.0
	cargo_velocity = Vector2.ZERO
	_retract_clamp()
	lost.set("freight", null)
	cargo_state_changed.emit("lost")
	notice.emit("晶体滑出了平台！它落在下方维修区，可以重新搬起。")
	_play("crystal_wrong", (lost as Node3D).global_position, 0.8, 0.85)


func _tick_grab_positions() -> void:
	for player: Variant in grabs.keys():
		if not is_instance_valid(player):
			continue
		var node: Node = player
		var point_id: String = str(grabs[player])
		if not GRAB_POINTS.has(point_id):
			continue
		var stand: Vector3 = (GRAB_POINTS[point_id] as Dictionary)["stand"] as Vector3
		(node as Node3D).global_position = to_global(stand)
		node.set("velocity", get_ride_velocity() + Vector3(0.0, -0.2, 0.0))


func _update_visual_state(delta: float) -> void:
	_beacon_clock += delta
	var level: float = warning_level
	if level > 0.01:
		var blink: float = 0.55 + 0.45 * sin(_beacon_clock * 14.0)
		_set_beacon(level * blink, Color(1.0, 0.42, 0.08))
		_warning_sound_clock -= delta
		if _warning_sound_clock <= 0.0:
			_warning_sound_clock = 0.62
			_play("beacon_ping", global_position, 0.55, 0.7 + level * 0.4)
	else:
		var idle_color: Color = Color(1.0, 0.55, 0.12)
		var idle_energy: float = 0.25
		if brake_engaged:
			idle_color = Color(1.0, 0.22, 0.12)
			idle_energy = 1.2
		elif clamp_t > 0.9:
			idle_color = Color(0.30, 1.0, 0.72)
			idle_energy = 0.8
		_set_beacon(idle_energy, idle_color)
	for entry: Dictionary in _warning_pylons:
		var material: StandardMaterial3D = entry["material"] as StandardMaterial3D
		var base: float = float(entry["base"])
		if material == null:
			continue
		var energy: float = base + level * 3.2
		material.emission = Color(0.45 + level * 0.55, 0.82 - level * 0.35, 1.0 - level * 0.7)
		material.albedo_color = material.emission
		material.emission_energy_multiplier = energy
	# 004B：夹具的视觉位置由 `_apply_press_visual()` / `_tick_clamp()` 从真实
	# 行程驱动（侧挡水平、压板竖直），这里不再插值一份独立的假位置。
	# Grip indicators: a grabbed point glows, so the other player can see it.
	for point_id: String in _grip_marks.keys():
		var mark: MeshInstance3D = _grip_marks[point_id] as MeshInstance3D
		if mark == null:
			continue
		var held: bool = grab_peer_by_point.has(point_id) or _local_grab_at(point_id)
		var mark_material: StandardMaterial3D = mark.material_override as StandardMaterial3D
		if mark_material != null:
			mark_material.emission = Color(0.32, 1.0, 0.72) if held else Color(0.36, 0.92, 1.0)
			mark_material.albedo_color = mark_material.emission
			mark_material.emission_energy_multiplier = 1.6 if held else 0.35
	# Brake lever visual.
	if _brake_control != null:
		_brake_control.rotation_degrees.z = -18.0 if brake_engaged else 0.0
	if _brake_lamp_mat != null:
		PhysicalLinkKit.set_lamp_state(_brake_lamp_mat, "locked" if brake_engaged else "active")
	if _drive_lamp_mat != null:
		var drive_state := "locked" if brake_engaged else ("active" if absf(speed) > 0.08 else "ready")
		PhysicalLinkKit.set_lamp_state(_drive_lamp_mat, drive_state)
	if _clamp_lamp_mat != null:
		var clamp_state := "active" if jaw_locked else ("ready" if cargo_attached else "off")
		PhysicalLinkKit.set_lamp_state(_clamp_lamp_mat, clamp_state)
	if _brake_drive_wire_mat != null:
		PhysicalLinkKit.set_flow_state(_brake_drive_wire_mat, "locked" if brake_engaged else ("active" if absf(speed) > 0.08 else "ready"))


func _local_grab_at(point_id: String) -> bool:
	for player: Variant in grabs.keys():
		if str(grabs[player]) == point_id and is_instance_valid(player):
			return true
	return false


func _set_beacon(energy: float, color: Color) -> void:
	for material: StandardMaterial3D in _beacon_materials:
		if material != null:
			material.albedo_color = color
			material.emission = color
			material.emission_energy_multiplier = maxf(energy, 0.05)
	for light: OmniLight3D in _beacon_lights:
		if light != null:
			light.light_color = color
			light.light_energy = energy * 1.3


func _update_cables() -> void:
	if _trolley == null or _cables.is_empty():
		return
	for index: int in range(mini(_cables.size(), mini(_top_anchors.size(), _deck_anchors.size()))):
		var mesh: MeshInstance3D = _cables[index]
		if mesh == null:
			continue
		var from_point: Vector3 = _trolley.to_global(_top_anchors[index])
		var to_point: Vector3 = to_global(_deck_anchors[index])
		_place_cable(mesh, from_point, to_point)


func _place_cable(mesh: MeshInstance3D, from_point: Vector3, to_point: Vector3) -> void:
	var delta: Vector3 = to_point - from_point
	var length: float = delta.length()
	if length < 0.01:
		return
	var y_axis: Vector3 = delta / length
	var reference: Vector3 = Vector3.FORWARD if absf(y_axis.dot(Vector3.FORWARD)) < 0.94 else Vector3.RIGHT
	var x_axis: Vector3 = y_axis.cross(reference).normalized()
	var z_axis: Vector3 = x_axis.cross(y_axis).normalized()
	mesh.global_transform = Transform3D(Basis(x_axis, y_axis, z_axis), (from_point + to_point) * 0.5)
	mesh.scale = Vector3(1.0, length, 1.0)


# --------------------------------------------------------------- public API

func configure_network(net_node: Node, is_authority: bool) -> void:
	net = net_node
	authority = is_authority
	network_active = true
	_last_snapshot_ms = Time.get_ticks_msec()
	_net_x = travel_x
	_net_y = deck_y
	_net_roll = tilt_roll
	_net_pitch = tilt_pitch
	_net_cargo_u = cargo_u
	_net_cargo_v = cargo_v


func bind_local_player(body: Node) -> void:
	local_player = body


func set_travel_for_test(x_value: float) -> void:
	travel_x = clampf(x_value, far_park_x, near_park_x)


func current_dock() -> String:
	if absf(travel_x - near_park_x) < 0.06:
		return "near"
	if absf(travel_x - far_park_x) < 0.06:
		return "far"
	return ""


func is_docked() -> bool:
	return current_dock() != ""


func get_bay_position() -> Vector3:
	return to_global(Vector3(0.0, 0.62, 0.0))


func get_platform_velocity() -> Vector3:
	return global_transform.basis.x * speed + Vector3(0.0, _vertical_velocity, 0.0)


func get_ride_velocity() -> Vector3:
	return get_platform_velocity()


## Horizontal acceleration felt by a standing player (m/s^2). The tilt slope
## term is what makes the deck feel like a deck instead of a lift.
func get_ride_push(world_position: Vector3) -> Vector3:
	var tilt_angle: float = absf(tilt_roll) + absf(tilt_pitch)
	var result: Vector3 = Vector3.ZERO
	if tilt_angle > 0.055:
		var gravity_local: Vector3 = global_transform.basis.inverse() * Vector3(0.0, -9.8, 0.0)
		var downhill: Vector3 = Vector3(gravity_local.x, 0.0, gravity_local.z)
		if downhill.length_squared() > 0.0004:
			var strength: float = clampf((tilt_angle - 0.05) * 5.5, 0.0, 2.6)
			result += (global_transform.basis * downhill.normalized()) * strength
	# Sudden drive changes make a standing player stumble a step; grabbing
	# cancels this because the player is attached to the rail.
	var inertia: Vector3 = -_accel_world * 0.085
	inertia.y = 0.0
	result += inertia.limit_length(2.2)
	result.y = 0.0
	return result


func get_point_velocity(world_position: Vector3) -> Vector3:
	# Linear velocity plus the tangential velocity caused by the tilt spring.
	var offset: Vector3 = world_position - global_position
	var angular: Vector3 = Vector3(_roll_vel, 0.0, _pitch_vel)
	return get_platform_velocity() + angular.cross(offset)


func get_grab_position(point_id: String) -> Vector3:
	if not GRAB_POINTS.has(point_id):
		return global_position
	var data: Dictionary = GRAB_POINTS[point_id] as Dictionary
	return to_global(data["rail"] as Vector3)


func is_point_grabbed(point_id: String) -> bool:
	return _local_grab_at(point_id) or grab_peer_by_point.has(point_id)


func control_prompt(kind: String, player: Node, dock_id: String) -> String:
	var player_id: int = _peer_of(player)
	match kind:
		"drive":
			if control_owner == player:
				return "E 松开操纵杆   ·   W/S 行驶"
			if control_owner_id != 0:
				return "操纵杆被玩家 %d 握着" % control_owner_id
			if not is_docked() and absf(speed) > 0.05:
				return "平台移动中，先让它停稳"
			return "E 握住行驶操纵杆"
		"brake":
			if service_active or deck_y < deck_travel_y - 0.15:
				return "救援绞盘工作中"
			return "E 松开安全制动" if brake_engaged else "E 拉下安全制动"
		"clamp":
			if cargo == null:
				return "货物夹具（空）"
			if clamp_closed:
				return "E 松开货物夹具"
			return "E 固定晶体"
		"grab":
			if player != null and player.get("grab_platform") == self:
				return "E 松手"
			if is_point_grabbed(dock_id):
				return "这个扶手已被抓住"
			return "E 抓住栏杆"
		"call":
			if current_dock() == dock_id:
				return "运输平台已在本侧"
			if control_owner != null:
				return "平台正被玩家 %d 操作" % control_owner_id
			return "E 呼叫运输平台到本侧"
		"winch":
			if dock_id == "onboard":
				if current_dock() == "":
					return "平台停稳后才能放下绞盘"
				return "E 收回救援绞盘" if service_target else "E 放下救援绞盘"
			if current_dock() != dock_id:
				return "平台不在这侧"
			return "E 收回救援绞盘" if service_target else "E 放下救援绞盘"
		_:
			return ""
	return ""


## Apply one control request. Returns a RESULT_* code so a caller can tell an
## applied action from a refused one; on a client the request is only forwarded
## and the authority's snapshot decides the outcome.
func handle_control(kind: String, player: Node, dock_id: String) -> String:
	if network_active and not authority:
		if player != null:
			local_player = player
		if _forward_freight_action(kind, dock_id):
			return RESULT_PENDING
		return RESULT_REJECTED
	match kind:
		"drive":
			if control_owner == player:
				release_control(player)
				return RESULT_APPLIED
			if control_owner == null:
				if not request_control(player):
					return RESULT_REJECTED
				# ACT04-3P4P: the host's own lever action must reach the
				# participation ledger too. Only the locally driven body emits,
				# so a remote peer's grant is still credited exactly once by the
				# Act 4 host action path.
				if player != null and player == local_player:
					action_used.emit("drive", _peer_of(player))
				return RESULT_CREDIT
			notice.emit("操纵杆正被玩家 %d 握着。" % control_owner_id)
			return RESULT_REJECTED
		"brake":
			toggle_brake()
			action_used.emit("brake", _peer_of(player))
			return RESULT_CREDIT
		"clamp":
			if not toggle_clamp():
				return RESULT_REJECTED
			action_used.emit("clamp", _peer_of(player))
			# The clamp has never been an Act 4 credit kind; that stays true.
			return RESULT_APPLIED
		"grab":
			if player != null and player.get("grab_platform") == self:
				end_grab(player)
				return RESULT_APPLIED
			if not request_grab(player, dock_id):
				return RESULT_REJECTED
			if player != null and player == local_player:
				action_used.emit("grab", _peer_of(player))
			return RESULT_CREDIT
		"call":
			return RESULT_APPLIED if request_recall(dock_id, player) else RESULT_REJECTED
		"winch":
			if not request_service(dock_id):
				return RESULT_REJECTED
			action_used.emit("winch", _peer_of(player))
			return RESULT_APPLIED
		_:
			return RESULT_REJECTED
	return RESULT_REJECTED


func request_control(player: Node) -> bool:
	if player == null or control_owner != null:
		return false
	control_owner = player
	control_owner_id = _peer_of(player)
	player.set("platform_control", self)
	control_changed.emit(control_owner_id)
	notice.emit("你握住了操纵杆：W 向对岸，S 倒退，E 松手。")
	return true


func release_control(player: Node = null) -> void:
	if control_owner == null:
		return
	if player != null and control_owner != player:
		return
	var owner_node: Node = control_owner
	control_owner = null
	control_owner_id = 0
	drive_input = 0.0
	if is_instance_valid(owner_node):
		owner_node.set("platform_control", null)
	control_changed.emit(0)


func release_control_by_peer(peer_id: int) -> void:
	if control_owner_id == peer_id:
		release_control()


func set_drive_input(value: float) -> void:
	drive_input = clampf(value, -1.0, 1.0)


func toggle_brake() -> void:
	brake_engaged = not brake_engaged
	if brake_engaged:
		_play("hammer_creak", global_position, 0.65, 0.72)
		if absf(speed) > 0.6:
			notice.emit("紧急制动！晶体还会往前冲。")
	else:
		_play("hammer_ratchet", global_position, 0.5, 0.9)
	notice.emit("安全制动已拉下。" if brake_engaged else "安全制动已松开。")


func toggle_clamp() -> bool:
	if cargo == null and not clamp_closed:
		notice.emit("夹具是空的。先把晶体放到货架上。")
		return false
	clamp_closed = not clamp_closed
	if clamp_closed:
		_play("hammer_ratchet", get_bay_position(), 0.75, 0.8)
		notice.emit("货物夹具合拢中——侧挡夹住晶体，压板压到顶面。")
	else:
		jaw_pressing = false
		jaw_locked = false
		_play("hammer_creak", get_bay_position(), 0.65, 0.9)
		notice.emit("货物夹具已打开，晶体重新自由。")
	return true


func request_grab(player: Node, point_id: String) -> bool:
	if player == null or not GRAB_POINTS.has(point_id):
		return false
	if is_point_grabbed(point_id):
		notice.emit("这个扶手已经有人了。")
		return false
	# One body holds one handhold: clear the previous grant first so a new one
	# can never leave the old point permanently marked as taken.
	_drop_previous_hold(player)
	var stand: Vector3 = (GRAB_POINTS[point_id] as Dictionary)["stand"] as Vector3
	grabs[player] = point_id
	player.set("grab_platform", self)
	player.set("grab_local", stand)
	player.set("grab_point_id", point_id)
	player.set("platform_control", null)
	if control_owner == player:
		release_control(player)
	grab_peer_by_point[point_id] = _peer_of(player)
	grab_state_changed.emit(_peer_of(player), point_id, true)
	notice.emit("抓住了。平台倾斜时你不会被甩出去。E 松手。")
	return true


## Release a handhold. `silent` is used by authority-side cleanup (disconnect,
## reset, re-grant) so a player is not told "let go" for a grant it never chose
## to drop. A client that still holds a host-granted rail asks the host to revoke
## it instead of only clearing its own copy.
func end_grab(player: Node, silent: bool = false) -> void:
	if player == null:
		return
	if network_active and not authority and player.get("grab_platform") == self:
		_forward_freight_action("grab", str(player.get("grab_point_id")))
	var had_hold: bool = grabs.has(player)
	var point_id: String = _release_point_record(player)
	if player.get("grab_platform") == self:
		player.set("grab_platform", null)
		player.set("grab_point_id", "")
	if not had_hold:
		return
	grab_state_changed.emit(_peer_of(player), point_id, false)
	if not silent:
		notice.emit("松手了。注意脚下。")


func release_grabs_by_peer(peer_id: int) -> void:
	for player: Variant in grabs.keys():
		if not is_instance_valid(player) or _peer_of(player as Node) != peer_id:
			continue
		end_grab(player as Node, true)


func request_recall(dock_id: String, player: Node = null) -> bool:
	if network_active and not authority:
		if net != null:
			net.rpc_id(1, "act4_freight_action", "call", dock_id)
		return true
	if control_owner != null:
		notice.emit("玩家 %d 正握着操纵杆。" % control_owner_id)
		return false
	var target_x: float = near_park_x if dock_id == "near" else far_park_x
	if absf(travel_x - target_x) < 0.05:
		notice.emit("平台已经在这一侧。")
		return false
	if service_active:
		service_target = false
	recall_to_x = target_x
	notice.emit("平台正在返回%s装货台。" % ("东侧" if dock_id == "near" else "西侧"))
	_play("beacon_ping", global_position, 0.6, 0.8)
	return true


func request_service(dock_id: String) -> bool:
	if network_active and not authority:
		if net != null:
			net.rpc_id(1, "act4_freight_action", "winch", dock_id)
		return true
	if dock_id == "onboard":
		if current_dock() == "":
			notice.emit("平台必须停稳在装货台。")
			return false
	elif current_dock() != dock_id:
		notice.emit("平台不在这侧的装货台。")
		return false
	service_target = not service_target
	_play("hammer_creak", global_position, 0.6, 0.62)
	notice.emit("救援绞盘下降中。" if service_target else "救援绞盘收回中。")
	return true


func dock_player(player: Node, dock_id: String) -> void:
	# Called by an arena dock platform when a player steps onto it (used only
	# for spawn/teleport bookkeeping in tests and co-op).
	if player == null:
		return
	last_dock = dock_id


# Kept as a variable at the end of the state block for readability; the
# recall target is consumed by _tick_drive through current speed.
func _tick_recall(delta: float) -> void:
	if recall_to_x == INF:
		return
	if control_owner != null:
		recall_to_x = INF
		return
	var distance: float = recall_to_x - travel_x
	if absf(distance) < 0.06:
		travel_x = recall_to_x
		speed = 0.0
		recall_to_x = INF
		_emit_dock_if_arrived()
		return
	var direction: float = signf(distance)
	speed = move_toward(speed, direction * 1.0, 1.1 * delta)
	travel_x += speed * delta
	if (direction > 0.0 and travel_x > recall_to_x) or (direction < 0.0 and travel_x < recall_to_x):
		travel_x = recall_to_x
		speed = 0.0
		recall_to_x = INF
		_emit_dock_if_arrived()


func _emit_dock_if_arrived() -> void:
	var dock: String = current_dock()
	if dock == "" or dock == last_dock:
		return
	last_dock = dock
	dock_changed.emit(dock)
	if dock == "near" and delivered:
		pass


## 004B：把晶体登记为平台货物。
##
## 关键差别：**不冻结、不关碰撞、不写 transform**。晶体到这里时还是自由
## 的 16 kg RigidBody3D，落在真实甲板上；`cargo` 只是“这趟运输算哪块晶体”
## 的登记，用来读载重、显示提示。
func seat_cargo(crystal: Node) -> bool:
	if crystal == null or cargo != null:
		return false
	if not (crystal is RigidBody3D):
		return false
	# 必须真的在货台 bay 里。调用方 PortableCrystal.try_seat() 是按 1.75 m 水平
	# 距离判定“在吊篮旁”的，而船坞边缘距平台中心只有约 1.4 m。不做包含性判定，
	# 就会把“放在停靠位旁边地上的晶体”登记成已装载：此后 `inside` 恒为假，
	# 夹具永远合不上、is_cargo_fixed() 恒 false，车一动还报“晶体滑出了平台”。
	var local: Vector3 = to_local((crystal as Node3D).global_position)
	if absf(local.x) > BAY_HALF_U + 0.15 or absf(local.z) > BAY_HALF_V + 0.15:
		return false
	if local.y < -0.10 or local.y > CRYSTAL_HEIGHT + 0.45:
		return false
	cargo = crystal
	cargo_attached = true
	cargo_loose = false
	crystal.set("freight", self)
	crystal.set("is_seated", false)
	crystal.set("is_carried", false)
	(crystal as RigidBody3D).freeze = false
	crystal.call("set_collision_enabled", true)
	crystal.set("held_yaw_deg", rad_to_deg((crystal as Node3D).rotation.y))
	crystal.call("set_cargo_mode", true)
	cargo_u = local.x
	cargo_v = local.z
	cargo_velocity = Vector2.ZERO
	cargo_state_changed.emit("seated")
	notice.emit("晶体落在货台上。E 合上夹具，再开车。")
	_play("crystal_seat", get_bay_position(), 0.75)
	return true


func release_cargo() -> void:
	if cargo == null:
		return
	var released: Node = cargo
	cargo = null
	cargo_attached = false
	cargo_u = 0.0
	cargo_v = 0.0
	cargo_velocity = Vector2.ZERO
	_retract_clamp()
	released.set("freight", null)
	cargo_state_changed.emit("taken")
	_play("crystal_lift", get_bay_position(), 0.6)


## Attach a crystal that the host already owns (network mirror, reset, tests).
## Silent: no notices, no audio, no pickup event.
func adopt_cargo(crystal: Node) -> void:
	if crystal == null:
		return
	if cargo == crystal and cargo_attached:
		return
	if not (crystal is RigidBody3D):
		return
	cargo = crystal
	cargo_attached = true
	cargo_loose = false
	crystal.set("freight", self)
	crystal.set("is_seated", false)
	crystal.set("is_carried", false)
	(crystal as RigidBody3D).freeze = false
	crystal.call("set_collision_enabled", true)
	crystal.call("set_cargo_mode", true)
	var local: Vector3 = to_local((crystal as Node3D).global_position)
	cargo_u = local.x
	cargo_v = local.z
	cargo_velocity = Vector2.ZERO


func release_cargo_silent() -> void:
	if cargo != null and is_instance_valid(cargo):
		cargo.set("freight", null)
	cargo = null
	cargo_attached = false
	cargo_u = 0.0
	cargo_v = 0.0
	cargo_velocity = Vector2.ZERO
	_retract_clamp()


## 004B：`is_cargo_fixed` 读的是**真实夹持状态**，不是 `clamp_t` 阈值：
## 侧挡已经合拢围住晶体，并且压板真的压到晶体顶面。
func is_cargo_fixed() -> bool:
	if not cargo_attached or cargo == null or not is_instance_valid(cargo):
		return false
	return clamp_closed and jaw_locked


func mark_delivered(value: bool) -> void:
	if delivered == value:
		return
	delivered = value
	delivered_changed.emit(value)
	if value:
		notice.emit("晶体运抵东侧装货台。")
		_play("success_chime", get_bay_position(), 0.5)


func apply_platform_knock(impulse: Vector3) -> void:
	pass


func reset_platform() -> void:
	release_control()
	for player: Variant in grabs.keys():
		if not is_instance_valid(player):
			continue
		var node: Node = player
		node.set("grab_platform", null)
		node.set("grab_point_id", "")
	grabs.clear()
	grab_peer_by_point.clear()
	release_cargo_silent()
	travel_x = near_park_x
	deck_y = deck_travel_y
	speed = 0.0
	last_speed = 0.0
	drive_input = 0.0
	target_speed = 0.0
	brake_engaged = false
	service_target = false
	service_active = false
	clamp_closed = false
	clamp_t = 0.0
	jaw_pressing = false
	jaw_locked = false
	jaw_blocked = false
	jaw_press_force = 0.0
	_press_y = PRESS_OPEN_Y
	_chock_pos = CHOCK_OPEN
	_drive_ramp = 0.0
	last_force = 0.0
	drive_stalled = false
	accident_phase = 0
	accident_timer = 0.0
	accident_fired = false
	warning_level = 0.0
	stall_timer = 0.0
	tilt_roll = 0.0
	tilt_pitch = 0.0
	_roll_vel = 0.0
	_pitch_vel = 0.0
	delivered = false
	last_dock = "near"
	recall_to_x = INF
	global_position = Vector3(travel_x, deck_y, center_z)
	rotation = Vector3.ZERO
	if _trolley != null:
		_trolley.global_position = Vector3(travel_x, rail_y, center_z)
	_update_cables()
	_update_visual_state(0.0)


func snapshot() -> Dictionary:
	var grab_map: Dictionary = {}
	for player: Variant in grabs.keys():
		if not is_instance_valid(player):
			continue
		grab_map[str(_peer_of(player as Node))] = str(grabs[player])
	return {
		"x": travel_x,
		"y": deck_y,
		"speed": speed,
		"roll": tilt_roll,
		"pitch": tilt_pitch,
		"brake": brake_engaged,
		"service": service_target,
		"clamp": clamp_closed,
		"clamp_t": clamp_t,
		"jaw_locked": jaw_locked,
		"press_y": _press_y,
		"chock": _chock_pos,
		"control": control_owner_id,
		"cargo": cargo_attached,
		"cargo_u": cargo_u,
		"cargo_v": cargo_v,
		"cargo_pos": (cargo as Node3D).global_position if cargo != null and is_instance_valid(cargo) else Vector3.ZERO,
		"cargo_rot": (cargo as Node3D).global_rotation if cargo != null and is_instance_valid(cargo) else Vector3.ZERO,
		"accident": accident_phase,
		"accident_t": accident_timer,
		"fired": accident_fired,
		"warning": warning_level,
		"grabs": grab_map,
		"delivered": delivered,
	}


func _snapshot_ok(state: Dictionary) -> bool:
	for key: String in ["x", "y", "speed", "roll", "pitch"]:
		var val: Variant = state.get(key, null)
		if val == null or (not (val is float) and not (val is int)):
			return false
		if not is_finite(float(val)):
			return false
	var x: float = float(state.get("x", travel_x))
	var y: float = float(state.get("y", deck_y))
	if x < minf(far_park_x, near_park_x) - 1.0 or x > maxf(far_park_x, near_park_x) + 1.0:
		return false
	if y < -10.0 or y > 25.0:
		return false
	return true


func _resolve_cargo_from_host(state: Dictionary) -> Node:
	if not is_inside_tree():
		return null
	var target_pos: Variant = state.get("cargo_pos", null)
	var ref_pos: Vector3 = target_pos as Vector3 if (target_pos is Vector3 and (target_pos as Vector3).is_finite()) else get_bay_position()
	var best: Node = null
	var best_d: float = 3.5
	for node: Node in get_tree().get_nodes_in_group("portable_crystal"):
		if not (node is Node3D) or not is_instance_valid(node):
			continue
		var d: float = (node as Node3D).global_position.distance_to(ref_pos)
		if d < best_d:
			best_d = d
			best = node
	return best


func apply_net_state(state: Dictionary) -> void:
	if not _snapshot_ok(state):
		push_warning("ACT4 platform snapshot rejected: invalid or out-of-range fields")
		return
	_last_snapshot_ms = Time.get_ticks_msec()
	_net_x = float(state.get("x", _net_x))
	_net_y = float(state.get("y", _net_y))
	_net_roll = float(state.get("roll", _net_roll))
	_net_pitch = float(state.get("pitch", _net_pitch))
	_net_cargo_u = float(state.get("cargo_u", _net_cargo_u))
	_net_cargo_v = float(state.get("cargo_v", _net_cargo_v))
	speed = float(state.get("speed", 0.0))
	brake_engaged = bool(state.get("brake", false))
	service_target = bool(state.get("service", false))
	clamp_closed = bool(state.get("clamp", false))
	clamp_t = float(state.get("clamp_t", 0.0))
	jaw_locked = bool(state.get("jaw_locked", false))
	_press_y = float(state.get("press_y", PRESS_OPEN_Y))
	_chock_pos = float(state.get("chock", CHOCK_OPEN))
	control_owner_id = int(state.get("control", 0))
	accident_phase = int(state.get("accident", 0))
	accident_timer = float(state.get("accident_t", 0.0))
	accident_fired = bool(state.get("fired", false))
	warning_level = float(state.get("warning", 0.0))
	delivered = bool(state.get("delivered", false))
	grab_peer_by_point.clear()
	var grab_map: Dictionary = state.get("grabs", {}) as Dictionary
	for peer_key: Variant in grab_map.keys():
		grab_peer_by_point[str(grab_map[peer_key])] = int(str(peer_key))
	var was_attached: bool = cargo_attached
	cargo_attached = bool(state.get("cargo", false))
	if cargo_attached:
		if cargo == null or not is_instance_valid(cargo):
			cargo = _resolve_cargo_from_host(state)
		if cargo != null and is_instance_valid(cargo):
			cargo.set("freight", self)
			if cargo is RigidBody3D:
				var body: RigidBody3D = cargo as RigidBody3D
				body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
				body.freeze = true
				body.linear_velocity = Vector3.ZERO
				body.angular_velocity = Vector3.ZERO
				var cpos: Variant = state.get("cargo_pos", null)
				if cpos is Vector3 and (cpos as Vector3).is_finite():
					body.global_position = cpos as Vector3
				var crot: Variant = state.get("cargo_rot", null)
				if crot is Vector3 and (crot as Vector3).is_finite():
					body.global_rotation = crot as Vector3
	elif not cargo_attached and cargo != null and was_attached:
		# The host says the cargo left the cradle; let local physics own it.
		if cargo is RigidBody3D and is_instance_valid(cargo):
			var body: RigidBody3D = cargo as RigidBody3D
			body.freeze = false
			body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		cargo.set("freight", null)
		cargo = null
	service_active = absf(_net_y - deck_travel_y) > 0.05
	_reconcile_local_grab()


func _apply_net_interpolation(delta: float) -> void:
	if authority:
		return
	var blend: float = 1.0 - exp(-12.0 * delta)
	travel_x = lerpf(travel_x, _net_x, blend)
	deck_y = lerpf(deck_y, _net_y, blend)
	tilt_roll = lerpf(tilt_roll, _net_roll, blend)
	tilt_pitch = lerpf(tilt_pitch, _net_pitch, blend)
	cargo_u = lerpf(cargo_u, _net_cargo_u, blend)
	cargo_v = lerpf(cargo_v, _net_cargo_v, blend)
	# Countdowns are sampled from the host at 20 Hz; advance them locally so the
	# client HUD does not appear frozen between snapshots.
	if accident_phase == 1 or accident_phase == 2:
		accident_timer = maxf(accident_timer - delta, 0.0)
	global_position = Vector3(travel_x, deck_y, center_z)
	rotation = Vector3(tilt_pitch, 0.0, tilt_roll)
	_update_visual_state(0.0)
	if _trolley != null:
		_trolley.global_position = Vector3(travel_x, rail_y, center_z)
	_update_cables()


# --------------------------------------------- R12 · grab authorization mirror
# The host owns `grab_peer_by_point`. A client has to translate that table into
# real state on the one body it drives: before this, the platform and the prompt
# said "grabbed" while the local CharacterBody3D stayed free (no rail
# constraint, no ride velocity, and E requested a grab instead of releasing).
# Nothing here can grant a grab by itself — only a host snapshot can.

## Reliable client -> host freight intent. False when this process has no live
## host connection, so a caller reports a refusal instead of a performed action.
func _forward_freight_action(kind: String, dock_id: String) -> bool:
	if net == null:
		return false
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return false
	net.rpc_id(1, "act4_freight_action", kind, dock_id)
	return true


## Remove this body's own handhold record with no player-facing feedback and
## return the point it held ("" when it held none). The point -> peer mirror is
## only erased while it still names this body, so a stale holder can never free
## a handhold that already belongs to somebody else.
func _release_point_record(body: Node) -> String:
	if not grabs.has(body):
		return ""
	var point_id: String = str(grabs[body])
	grabs.erase(body)
	if int(grab_peer_by_point.get(point_id, -1)) == _peer_of(body):
		grab_peer_by_point.erase(point_id)
	return point_id


## A new grant replaces the old one: clear the body's previous rail (on this
## platform or another one) so no point stays occupied by a grant that no
## longer exists.
func _drop_previous_hold(body: Node) -> void:
	var previous_platform: Node = body.get("grab_platform") as Node
	if previous_platform != null and previous_platform != self \
			and previous_platform.has_method("end_grab"):
		previous_platform.call("end_grab", body, true)
		return
	_release_point_record(body)
	body.set("grab_platform", null)
	body.set("grab_point_id", "")


## Authority integrity pass: a body that was freed (disconnect, reset, scene
## reload) must not keep a handhold taken forever. Rebuild the point -> peer
## mirror from the live grab table whenever a dead reference is dropped.
func _prune_stale_grabs() -> void:
	var dropped: bool = false
	for player: Variant in grabs.keys():
		if not is_instance_valid(player):
			grabs.erase(player)
			dropped = true
	if not dropped:
		return
	var rebuilt: Dictionary = {}
	for player: Variant in grabs.keys():
		if not is_instance_valid(player):
			continue
		var node: Node = player
		rebuilt[str(grabs[player])] = _peer_of(node)
	grab_peer_by_point = rebuilt
	const Log := preload("res://scripts/core/log.gd")
	Log.d("ACT4", "GRAB_PRUNE live=%d points=%s" % [grabs.size(), str(rebuilt)])


## Apply a host grant to the one body this client owns. Mirrors `request_grab`'s
## authoritative effects (platform, point, stand offset, ride velocity) without
## the grant itself: that still only comes from the snapshot.
func _apply_local_grab(body: Node, point_id: String) -> void:
	var data: Dictionary = GRAB_POINTS[point_id] as Dictionary
	var stand: Vector3 = data["stand"] as Vector3
	grabs[body] = point_id
	body.set("grab_platform", self)
	body.set("grab_local", stand)
	body.set("grab_point_id", point_id)
	body.set("platform_control", null)
	var node: Node3D = body as Node3D
	if node != null:
		node.global_position = to_global(stand)
	body.set("velocity", get_ride_velocity())
	grab_state_changed.emit(_peer_of(body), point_id, true)
	const Log := preload("res://scripts/core/log.gd")
	Log.d("ACT4", "GRAB_LOCAL pid=%d point=%s state=granted source=host_authority" % [
		_peer_of(body), point_id])


## Drop the local rail state. Never tells the host anything: the host is the one
## that revoked it (or the world read is stale).
func _clear_local_grab(body: Node, reason: String = "authority_revoke") -> void:
	var point_id: String = _release_point_record(body)
	if body.get("grab_platform") == self:
		body.set("grab_platform", null)
		body.set("grab_point_id", "")
	if point_id.is_empty():
		return
	grab_state_changed.emit(_peer_of(body), point_id, false)
	const Log := preload("res://scripts/core/log.gd")
	Log.d("ACT4", "GRAB_LOCAL pid=%d point=%s state=cleared reason=%s" % [
		_peer_of(body), point_id, reason])


## Reconcile the body this client owns against the authoritative grab table that
## just arrived. Fails closed: no grant for this pid in the snapshot means no
## rail here.
func _reconcile_local_grab() -> void:
	if authority:
		return
	var body: Node = local_player
	if body == null or not is_instance_valid(body):
		return
	var local_pid: int = _peer_of(body)
	if local_pid <= 0:
		return
	var granted: String = ""
	for point_id: Variant in grab_peer_by_point.keys():
		if int(grab_peer_by_point[point_id]) == local_pid:
			granted = str(point_id)
			break
	var holds_here: bool = body.get("grab_platform") == self
	if granted.is_empty() or not GRAB_POINTS.has(granted):
		if holds_here or grabs.has(body):
			_clear_local_grab(body, "authority_revoke")
		return
	if holds_here and str(body.get("grab_point_id")) == granted:
		return
	if holds_here:
		_release_point_record(body)
	_apply_local_grab(body, granted)


## A grab only exists while the host keeps saying so. If the snapshot stream
## stops (host gone), let go instead of pinning the body forever.
func _guard_local_grab_authority() -> void:
	var body: Node = local_player
	if body == null or not is_instance_valid(body) or body.get("grab_platform") != self:
		return
	if Time.get_ticks_msec() - _last_snapshot_ms < GRAB_AUTHORITY_TIMEOUT_MS:
		return
	_clear_local_grab(body, "authority_stale")


## Leaving the tree ends every grant this process knew about: the table belongs
## to the world being torn down, and the local body must not keep a dangling
## platform reference into a freed node.
func _exit_tree() -> void:
	var body: Node = local_player
	if body != null and is_instance_valid(body) and body.get("grab_platform") == self:
		body.set("grab_platform", null)
		body.set("grab_point_id", "")
	local_player = null
	grabs.clear()
	grab_peer_by_point.clear()


func _peer_of(player: Node) -> int:
	if player == null:
		return 0
	var value: Variant = player.get("player_id")
	if value == null:
		return 0
	return int(value)


func _play(sound_name: String, position_value: Vector3, volume: float, pitch: float = 1.0) -> void:
	if _audio == null:
		_audio = get_tree().get_first_node_in_group("audio_director")
	if _audio != null and _audio.has_method("play_at"):
		_audio.call("play_at", sound_name, position_value, volume, pitch)
