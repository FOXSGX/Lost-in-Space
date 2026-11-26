extends Node3D

## 便携装货口：给第二、三张地图用的紧凑门（不复制整艘船）。
## 判定：球从门前（x < 门线）穿过门线（x >= 门线），且落在门洞宽度/高度内，即得分。
## 对外接口与 collector 对齐（fuel_collected / goal_plane_x / last_goal_zone），
## 这样守门员与结算逻辑不用区分是“飞船门”还是“便携门”。

signal fuel_collected(total: int, target: int)

const GATE_HALF_WIDTH := 1.9
## 每张地图可以覆盖门洞宽度（北场窄门 / 南场宽门）。
var half_width := GATE_HALF_WIDTH
## 门框强调色（北场暖黄 / 南场青绿），让两张图一眼能分。
var accent := Color("#7dffd4")
const GATE_HEIGHT := 2.2
const GATE_DEPTH := 1.2
const GATE_MODEL := preload("res://assets/models/nailong/arena_gate.glb")
const GATE_MODEL_HALF_WIDTH := 2.2
## 由 gulu_app 注入的材质表（按材质名覆盖，顶点遮罩才会生效）。
var materials: Dictionary = {}
## 门楣招牌（贴在门楣上的图片，不是悬浮文字）。
var sign_path := ""

var ball: RigidBody3D
var active := true
var loaded := 0
var target := 0
var last_goal_zone := 0

var _prev_x := 0.0
var _glow: MeshInstance3D
var _mouth_mat: StandardMaterial3D
var _consume_timer := 0.0
var _has_prev := false


func _ready() -> void:
	_build()
	add_to_group("cargo_goals")


func _build() -> void:
	if GATE_MODEL != null:
		_build_model_gate()
		return
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color("#cfc5ae")
	paint.roughness = 0.56
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color("#1f4a4c")
	trim.roughness = 0.42
	trim.metallic = 0.35
	var frame := StandardMaterial3D.new()
	frame.albedo_color = Color("#2f6b6e")
	frame.roughness = 0.5
	_mouth_mat = StandardMaterial3D.new()
	_mouth_mat.albedo_color = Color("#0b1416")
	_mouth_mat.emission_enabled = true
	_mouth_mat.emission = Color("#7dffd4")
	_mouth_mat.emission_energy_multiplier = 0.28

	# 门洞（背板 + 两侧）
	_box(Vector3(GATE_DEPTH, GATE_HEIGHT + 0.3, half_width * 2.2), Vector3(GATE_DEPTH * 0.5, GATE_HEIGHT * 0.5, 0.0), _mouth_mat)
	# 门框：上梁 + 左右柱
	_box(Vector3(0.45, 0.45, half_width * 2.4), Vector3(0.0, GATE_HEIGHT + 0.35, 0.0), trim)
	_box(Vector3(0.45, GATE_HEIGHT + 0.6, 0.35), Vector3(0.0, (GATE_HEIGHT + 0.6) * 0.5, half_width + 0.2), trim)
	_box(Vector3(0.45, GATE_HEIGHT + 0.6, 0.35), Vector3(0.0, (GATE_HEIGHT + 0.6) * 0.5, -half_width - 0.2), trim)
	# 底座与两侧挡板
	_box(Vector3(GATE_DEPTH + 1.4, 0.16, half_width * 2.8), Vector3(0.4, 0.08, 0.0), paint)
	_box(Vector3(1.8, 1.5, 0.3), Vector3(1.1, 0.75, half_width + 0.55), frame)
	_box(Vector3(1.8, 1.5, 0.3), Vector3(1.1, 0.75, -half_width - 0.55), frame)
	# 门楣指示灯
	_glow = _box(Vector3(0.2, 0.18, 0.5), Vector3(-0.2, GATE_HEIGHT + 0.72, 0.0), _mouth_mat)

	var light := OmniLight3D.new()
	light.position = Vector3(0.6, GATE_HEIGHT * 0.6, 0.0)
	light.light_color = Color("#7dffd4")
	light.light_energy = 0.9
	light.omni_range = 7.0
	add_child(light)



## 用 Blender 资产搭门：窄门/宽门靠 z 轴缩放，判定仍用 half_width。

## 门楣招牌：贴在门楣正面的发光板，用现成 PNG（门区编号/名称）。
func _build_sign() -> void:
	if sign_path == "" or not ResourceLoader.exists(sign_path):
		return
	var tex := load(sign_path) as Texture2D
	if tex == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.emission_enabled = true
	mat.emission_texture = tex
	mat.emission_energy_multiplier = 0.6
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# 灯箱背板
	var back := MeshInstance3D.new()
	var back_mesh := BoxMesh.new()
	back_mesh.size = Vector3(0.10, half_width * 1.16, half_width * 2.28)
	back.mesh = back_mesh
	var back_mat := StandardMaterial3D.new()
	back_mat.albedo_color = Color("#12201f")
	back.material_override = back_mat
	back.position = Vector3(-0.02, GATE_HEIGHT + 0.62, 0.0)
	add_child(back)
	# 招牌面（贴图）
	var quad := MeshInstance3D.new()
	var plane := QuadMesh.new()
	plane.size = Vector2(half_width * 2.1, half_width * 1.05)
	quad.mesh = plane
	quad.material_override = mat
	quad.position = Vector3(-0.09, GATE_HEIGHT + 0.62, 0.0)
	quad.rotation.y = -PI * 0.5
	add_child(quad)


func _build_model_gate() -> void:
	var root := GATE_MODEL.instantiate() as Node3D
	root.scale = Vector3(1.0, 1.0, half_width / GATE_MODEL_HALF_WIDTH)
	add_child(root)
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in range(mi.mesh.get_surface_count()):
			var src := mi.mesh.surface_get_material(s)
			if src != null and materials.has(src.resource_name):
				mi.set_surface_override_material(s, materials[src.resource_name])
	# 门口泛光：夜里也能看清门洞
	var light := OmniLight3D.new()
	light.position = Vector3(0.6, GATE_HEIGHT * 0.6, 0.0)
	light.light_color = Color("#7dffd4")
	light.light_energy = 1.1
	light.omni_range = 8.0
	add_child(light)
	_build_sign()
func _box(size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = at
	add_child(node)
	return node


func setup_ball(next_ball: RigidBody3D) -> void:
	ball = next_ball
	_has_prev = false


func goal_plane_x() -> float:
	return global_position.x + 0.35


func set_order_zone(_zone: int) -> void:
	pass


func _physics_process(delta: float) -> void:
	if _consume_timer > 0.0:
		_consume_timer -= delta
		if _glow != null:
			_glow.visible = fmod(_consume_timer, 0.16) < 0.08
		if _consume_timer <= 0.0 and _glow != null:
			_glow.visible = true
	if not active or ball == null or not is_instance_valid(ball):
		return
	if bool(ball.get("collected")):
		_has_prev = false
		return
	var pos := ball.global_position
	if not _has_prev:
		_prev_x = pos.x
		_has_prev = true
		return
	var plane := goal_plane_x()
	var crossed := _prev_x < plane and pos.x >= plane
	_prev_x = pos.x
	if not crossed:
		return
	if absf(pos.z - global_position.z) > half_width:
		return
	if pos.y < global_position.y - 0.4 or pos.y > global_position.y + GATE_HEIGHT:
		return
	loaded += 1
	target = maxi(target, loaded)
	_consume_timer = 0.5
	if ball.has_method("collect"):
		ball.call("collect")
	fuel_collected.emit(loaded, target)


func reset_state() -> void:
	loaded = 0
	_has_prev = false
	_consume_timer = 0.0
	if _glow != null:
		_glow.visible = true


## 供守门员读取：门中心（世界坐标）。
func gate_center() -> Vector3:
	return global_position
