class_name LISDemoStage
extends Node3D
## LIS Physics SDK · 示例场地公共基类
##
## 提供：地面、光照、简单墙体、玩家、HUD、复位。
## 所有示例场景都从一个空 Node3D + 本脚本（或它的子类）开始，
## 因此**没有任何 .tscn 里手写的节点路径**会因使用者重命名而失效。

## 场地半边长（米）。
@export var stage_half: float = 14.0
## 地面摩擦（冰面示例会覆盖）。
@export var floor_friction: float = 0.85
## 玩家出生点。
@export var spawn_point: Vector3 = Vector3(0.0, 1.2, 6.0)
@export var spawn_yaw: float = 0.0
## 示例标题与操作说明（显示在 HUD 角落）。
@export var stage_title: String = "LIS Physics 示例"
@export_multiline var stage_help: String = ""
## 是否生成示例玩家（自动化测试会关掉，用程序化代理）。
@export var spawn_player: bool = true
## 是否生成 HUD。
@export var spawn_hud: bool = true

var player: LISDemoPlayer
var hud: LISDemoHUD
var floor_body: StaticBody3D
## 由子类登记的"复位时要恢复的物体"：[{node, pose}]
var _reset_list: Array[Dictionary] = []


func _ready() -> void:
	_build_environment()
	_build_scenery()
	if spawn_player:
		_build_player()
	if spawn_hud:
		_build_hud()
	# `await` 对非协程函数是安全的（立即返回），因此子类既可以写同步的
	# _build_content()，也可以在里面 await 物理帧（例如先建刚体再系绳）。
	await _build_content()
	_capture_reset_poses()


## 子类覆写：搭场景内容。
func _build_content() -> void:
	pass


## 子类覆写：搭静态装饰（墙、坡道等）。
func _build_scenery() -> void:
	pass


func _build_environment() -> void:
	# 世界环境（天空 / 环境光）
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.07, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.52, 0.58, 0.66)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we: WorldEnvironment = WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)

	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52, 38, 0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	add_child(sun)

	# 地面
	floor_body = StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.collision_layer = LISPhysics.LAYER_WORLD
	floor_body.collision_mask = 0
	var cs: CollisionShape3D = CollisionShape3D.new()
	var bs: BoxShape3D = BoxShape3D.new()
	bs.size = Vector3(stage_half * 2.0, 0.4, stage_half * 2.0)
	cs.shape = bs
	cs.position = Vector3(0.0, -0.2, 0.0)
	floor_body.add_child(cs)
	var fmat: PhysicsMaterial = PhysicsMaterial.new()
	fmat.friction = floor_friction
	fmat.bounce = 0.0
	fmat.rough = false
	floor_body.physics_material_override = fmat
	add_child(floor_body)
	var fmesh: MeshInstance3D = MeshInstance3D.new()
	var bm: BoxMesh = BoxMesh.new()
	bm.size = bs.size
	fmesh.mesh = bm
	var fmatv: StandardMaterial3D = StandardMaterial3D.new()
	fmatv.albedo_color = Color(0.20, 0.22, 0.25)
	fmatv.roughness = 0.92
	fmesh.material_override = fmatv
	fmesh.position = Vector3(0.0, -0.2, 0.0)
	floor_body.add_child(fmesh)


func _build_player() -> void:
	player = LISDemoPlayer.new()
	player.name = "Player"
	add_child(player)
	player.global_position = spawn_point
	player.yaw = spawn_yaw
	player.pitch = -0.10
	player._apply_look()
	if player.adapter != null:
		player.adapter.player_id = 1
	player.reset_requested.connect(reset_stage)


func _build_hud() -> void:
	hud = LISDemoHUD.new()
	hud.name = "HUD"
	add_child(hud)
	if player != null:
		hud.adapter = player.adapter
	hud.title_text = stage_title
	hud.help_text = stage_help


# ---------------------------------------------------------------------------
# 静态几何工具（示例共用）
# ---------------------------------------------------------------------------

## 一块静态碰撞盒（可带视觉）。返回 StaticBody3D。
func add_static_box(
	box_name: String,
	size: Vector3,
	pos: Vector3,
	rot_deg: Vector3 = Vector3.ZERO,
	color: Color = Color(0.30, 0.33, 0.37),
	friction: float = 0.85
) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = box_name
	body.collision_layer = LISPhysics.LAYER_WORLD
	body.collision_mask = 0
	var cs: CollisionShape3D = CollisionShape3D.new()
	var bs: BoxShape3D = BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	var mat: PhysicsMaterial = PhysicsMaterial.new()
	mat.friction = friction
	mat.bounce = 0.0
	mat.rough = false
	body.physics_material_override = mat
	var mi: MeshInstance3D = MeshInstance3D.new()
	var bm: BoxMesh = BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var vmat: StandardMaterial3D = StandardMaterial3D.new()
	vmat.albedo_color = color
	vmat.roughness = 0.8
	vmat.metallic = 0.1
	mi.material_override = vmat
	body.add_child(mi)
	body.position = pos
	body.rotation_degrees = rot_deg
	add_child(body)
	return body


## 生成一件 SDK 刚体并登记复位。
func add_body(
	body_name: String,
	pos: Vector3,
	size: Vector3,
	mass_kg: float,
	color: Color = Color(0.62, 0.52, 0.32),
	opts: Dictionary = {}
) -> LISBody:
	var prof: LISBodyProfile = LISBodyProfile.new()
	prof.display_name = str(opts.get("display_name", body_name))
	prof.size = size
	prof.mass_kg = mass_kg
	prof.color = color
	prof.friction = float(opts.get("friction", 0.7))
	prof.bounce = float(opts.get("bounce", 0.02))
	prof.rough = bool(opts.get("rough", true))
	prof.liftable = bool(opts.get("liftable", true))
	prof.linear_damp = float(opts.get("linear_damp", 0.06))
	prof.angular_damp = float(opts.get("angular_damp", 0.35))
	prof.metallic = float(opts.get("metallic", 0.15))
	prof.grip_handles = int(opts.get("handles", 2))
	prof.emission = bool(opts.get("emission", false))
	prof.tags = PackedStringArray([str(opts.get("tag", ""))])
	var b: LISBody = LISBody.new()
	b.name = body_name
	b.profile = prof
	b.position = pos
	b.rotation_degrees = opts.get("rot_deg", Vector3.ZERO)
	add_child(b)
	return b


## 登记复位位姿（在 _capture_reset_poses 之前 add_child 的物体自动登记）。
func register_reset(node: Node3D) -> void:
	if node == null:
		return
	_reset_list.append({"node": node, "pose": node.global_transform})


func _capture_reset_poses() -> void:
	for c: Node in get_children():
		var n3: Node3D = c as Node3D
		if n3 == null:
			continue
		if n3 is RigidBody3D:
			register_reset(n3)


## 复位：刚体回到初始位姿并清速度（重置语义，不是运动）。
func reset_stage() -> void:
	for item: Dictionary in _reset_list:
		var n: Node3D = item["node"] as Node3D
		if n == null or not is_instance_valid(n):
			continue
		var pose: Transform3D = item["pose"] as Transform3D
		if n is LISBody:
			(n as LISBody).reset_to(pose)
		elif n is RigidBody3D:
			var rb: RigidBody3D = n as RigidBody3D
			rb.freeze = false
			rb.sleeping = false
			rb.linear_velocity = Vector3.ZERO
			rb.angular_velocity = Vector3.ZERO
			rb.global_transform = pose
		else:
			n.global_transform = pose
	if player != null:
		player.teleport(spawn_point, spawn_yaw, -0.10)


## 场景说明用的静态标牌（贴在墙面/设备上的色块，不是漂浮文字）。
func add_sign_plate(pos: Vector3, size: Vector2, color: Color, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "SignPlate"
	var qm: QuadMesh = QuadMesh.new()
	qm.size = size
	mi.mesh = qm
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.7
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.25
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	add_child(mi)
	return mi
