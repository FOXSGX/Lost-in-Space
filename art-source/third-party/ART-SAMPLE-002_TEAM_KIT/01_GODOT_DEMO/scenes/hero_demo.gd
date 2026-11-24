extends Node3D
## ART-SAMPLE-002 · 英雄区独立演示（Godot 4.7.2 / Compatibility）
##
## 这个场景**不依赖正式工程**：它只加载本目录下的 GLB、贴图与 shader，
## 用 `materials/hero_lib.gd` 建材质，用与 `hammer_rig.gd` **相同的积分参数**
## 驱动摆锤。目的是让其他星球的同学"打开就能跑、看到真实材质和真实运动"。
##
## 操作：
##   鼠标左键拖动 = 环绕   滚轮 = 拉近/推远   空格 = 拉锤 → 松手    R = 复位
##   F1 = 显示/隐藏机位预设（Wide / PlayerEye / Interaction / Three-quarter）
##
## 说明：这里不是游戏本体。摆锤积分沿用产品参数（GRAVITY / ARM / DAMPING /
## IMPACT_ANGLE / REST_ANGLE），但没有玩家、没有交互判定、没有关卡逻辑。

const LIB := preload("res://materials/hero_lib.gd")
const ART := "res://assets/models/"

# ---- 与 scripts/act4/hammer_rig.gd 完全一致的积分参数（视觉演示用）----
const PIVOT_HEIGHT := 4.30
const ARM_LENGTH := 3.50
const MAX_PULL := 74.0
const IMPACT_ANGLE := -30.0
const REST_ANGLE := 2.5
const GRAVITY := 8.8
const DAMPING := 0.32
const POST_IMPACT_DAMPING := 1.35
const PULL_RATE := 1.25
const PULL_ACCEL := 4.2
const MZ := -3.4          # 机器局部 z 偏移（与正式工程一致）

var _pivot: Node3D
var _head_root: Node3D
var _cam: Camera3D
var _hud: Label

var _mode := "idle"       # idle / held / swing
var _angle := deg_to_rad(REST_ANGLE)
var _w := 0.0
var _pull_v := 0.0
var _after_impact := false
var _post_t := 0.0
var _struck := false
var _cooldown := 0.0
var _shake := 0.0
var _shake_t := 0.0

var _dust: CPUParticles3D
var _sparks: CPUParticles3D
var _flash: OmniLight3D
var _crystal_light: OmniLight3D
var _key_light: SpotLight3D

var _orbit_yaw := 0.65
var _orbit_pitch := -0.18
var _orbit_dist := 9.2
var _orbit_target := Vector3(0.0, 2.0, MZ - 0.9)
var _dragging := false

var _presets := [
	{"name": "Wide", "pos": Vector3(5.60, 2.45, 5.60 + MZ), "look": Vector3(0.0, 2.20, -1.60 + MZ), "fov": 50.0},
	{"name": "PlayerEye", "pos": Vector3(1.95, 1.58, 3.95 + MZ), "look": Vector3(0.0, 1.60, -1.60 + MZ), "fov": 66.0},
	{"name": "Interaction", "pos": Vector3(0.78, 1.06, 0.90 + MZ), "look": Vector3(0.0, 1.06, -0.45 + MZ), "fov": 40.0},
	{"name": "ThreeQuarter", "pos": Vector3(-4.15, 1.88, 3.15 + MZ), "look": Vector3(0.0, 2.05, -1.20 + MZ), "fov": 52.0},
]
var _preset_idx := -1


func _ready() -> void:
	var want_preset := 0
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--preset="):
			want_preset = clampi(s.substr(9).to_int(), 0, 3)
		if s.begins_with("--shot="):
			_shot_path = s.substr(7)
	_build_environment()
	_build_assets()
	_build_lights()
	_build_fx()
	_build_camera_and_hud()
	_apply_preset(want_preset)
	if _shot_path != "":
		_capture_after_frames()


# ---------------------------------------------------------------- 环境
func _build_environment() -> void:
	var we := WorldEnvironment.new()
	we.environment = load("res://resources/hero_env.tres") as Environment
	add_child(we)


# ---------------------------------------------------------------- 资产
func _build_assets() -> void:
	var lib: Dictionary = LIB.new().build()
	# 机器静态件（平台 / 立柱横梁轴承砧座 / 操作台 / 相邻岩层）
	_mount("aqs002_platform.glb", "Platform", Vector3(0, -0.2, MZ), lib)
	_mount("aqs002_press_static.glb", "PressStatic", Vector3(0, -0.2, MZ), lib)
	_mount("aqs002_console.glb", "Console", Vector3(0, -0.2, MZ), lib)
	_mount("aqs002_rock_hero.glb", "RockHero", Vector3(0, -0.2, MZ), lib)
	# 洞壁与地面（提供空间背景；来自 ART-QUALITY-002 的自制地质体）
	_mount("aq002_geology_a.glb", "Geology", Vector3.ZERO, lib)
	_mount("aq002_ground.glb", "Ground", Vector3.ZERO, lib)
	# 摆动件：pivot（真实摆动轴）→ 摆臂 + 高模烘焙锤头
	_pivot = Node3D.new()
	_pivot.name = "PendulumPivot"
	_pivot.position = Vector3(0, 0.2 + PIVOT_HEIGHT, MZ)
	add_child(_pivot)
	_mount("aqs002_swing_arm.glb", "SwingArm", Vector3.ZERO, lib, _pivot)
	_mount("aqs002_head_low.glb", "HeadLow", Vector3.ZERO, lib, _pivot)
	# 主晶体（坐在砧面上：世界 (0, 1.18, -5.14)）
	_mount("aqs002_bell_crystal.glb", "BellCrystal", Vector3(0.0, 1.18, -5.14), lib)


func _mount(file: String, node_name: String, pos: Vector3, lib: Dictionary,
		parent: Node3D = null) -> Node3D:
	var path := ART + file
	if not ResourceLoader.exists(path):
		push_warning("hero_demo: missing " + path)
		return null
	var ps := load(path) as PackedScene
	var holder := Node3D.new()
	holder.name = node_name
	holder.position = pos
	(parent if parent != null else self).add_child(holder)
	holder.add_child(ps.instantiate())
	for mi in holder.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for s in range(m.mesh.get_surface_count()):
			var src: Material = m.mesh.surface_get_material(s)
			var key := "" if src == null else src.resource_name
			var target: Material = lib.get(key) as Material
			if target != null:
				m.set_surface_override_material(s, target)
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return holder


# ---------------------------------------------------------------- 灯光
func _build_lights() -> void:
	# 主光：机装工作灯（灯具几何在 press_static 里）
	_key_light = SpotLight3D.new()
	_key_light.name = "KeyLamp"
	_key_light.position = Vector3(-1.50, 4.62, MZ + 0.10)
	_key_light.light_color = Color(1.0, 0.855, 0.70)
	_key_light.light_energy = 9.0
	_key_light.spot_range = 13.0
	_key_light.spot_angle = 46.0
	_key_light.spot_angle_attenuation = 1.15
	_key_light.shadow_enabled = true
	_key_light.shadow_bias = 0.055
	_key_light.shadow_normal_bias = 1.3
	_key_light.light_specular = 0.85
	_key_light.light_size = 0.55
	add_child(_key_light)
	_key_light.look_at(Vector3(-0.25, 0.95, MZ - 1.45), Vector3.UP)

	var fill := SpotLight3D.new()
	fill.position = Vector3(1.62, 4.70, MZ - 0.55)
	fill.light_color = Color(1.0, 0.80, 0.62)
	fill.light_energy = 5.0
	fill.spot_range = 10.0
	fill.spot_angle = 46.0
	fill.shadow_enabled = false
	add_child(fill)
	fill.look_at(Vector3(0.20, 1.15, MZ - 1.55), Vector3.UP)

	var rim := SpotLight3D.new()
	rim.position = Vector3(-2.35, 5.35, MZ - 5.9)
	rim.light_color = Color(0.46, 0.68, 1.0)
	rim.light_energy = 12.0
	rim.spot_range = 20.0
	rim.spot_angle = 36.0
	rim.shadow_enabled = false
	add_child(rim)
	rim.look_at(Vector3(0.1, 2.4, MZ + 0.4), Vector3.UP)

	var front := OmniLight3D.new()
	front.position = Vector3(1.45, 1.95, MZ + 2.95)
	front.light_color = Color(0.86, 0.88, 0.95)
	front.light_energy = 4.2
	front.omni_range = 8.5
	front.shadow_enabled = false
	add_child(front)

	var bounce := OmniLight3D.new()
	bounce.position = Vector3(0.0, 6.6, MZ - 3.0)
	bounce.light_color = Color(0.30, 0.42, 0.60)
	bounce.light_energy = 6.0
	bounce.omni_range = 44.0
	add_child(bounce)

	# 岩壁掠射灯（P3：让层理断面与解理沟读得出来）
	for spec in [[Vector3(-3.55, 3.10, 1.95 + MZ), Vector3(-4.35, 0.35, -2.15 + MZ), 7.5],
			[Vector3(3.45, 2.85, 2.35 + MZ), Vector3(4.05, 0.30, -1.35 + MZ), 6.0]]:
		var lamp := SpotLight3D.new()
		lamp.position = spec[0] as Vector3
		lamp.light_color = Color(0.86, 0.90, 1.0)
		lamp.light_energy = float(spec[2])
		lamp.spot_range = 9.0
		lamp.spot_angle = 34.0
		lamp.shadow_enabled = false
		add_child(lamp)
		lamp.look_at(spec[1] as Vector3, Vector3.UP)

	# 晶体实用光（跟随共振余振）
	_crystal_light = OmniLight3D.new()
	_crystal_light.position = Vector3(0.0, 2.25, -4.10)
	_crystal_light.light_color = Color(0.36, 0.86, 1.0)
	_crystal_light.light_energy = 2.6
	_crystal_light.omni_range = 5.5
	add_child(_crystal_light)


# ---------------------------------------------------------------- 撞击表现
func _build_fx() -> void:
	_dust = CPUParticles3D.new()
	_dust.emitting = false
	_dust.amount = 52
	_dust.lifetime = 2.6
	_dust.one_shot = true
	_dust.explosiveness = 0.85
	_dust.direction = Vector3.UP
	_dust.spread = 78.0
	_dust.initial_velocity_min = 0.5
	_dust.initial_velocity_max = 2.6
	_dust.gravity = Vector3(0, -1.7, 0)
	_dust.damping_min = 0.35
	_dust.damping_max = 1.1
	_dust.scale_amount_min = 0.05
	_dust.scale_amount_max = 0.22
	_dust.color = Color(0.58, 0.55, 0.49, 0.42)
	var q := QuadMesh.new()
	q.size = Vector2(0.30, 0.30)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dm.vertex_color_use_as_albedo = true
	dm.albedo_color = Color(0.60, 0.57, 0.50, 0.30)
	q.material = dm
	_dust.mesh = q
	_dust.position = Vector3(0.0, 1.22, -5.14)
	_dust.local_coords = false
	add_child(_dust)

	_sparks = CPUParticles3D.new()
	_sparks.emitting = false
	_sparks.amount = 26
	_sparks.lifetime = 0.55
	_sparks.one_shot = true
	_sparks.explosiveness = 1.0
	_sparks.direction = Vector3.UP
	_sparks.spread = 88.0
	_sparks.initial_velocity_min = 2.2
	_sparks.initial_velocity_max = 6.5
	_sparks.gravity = Vector3(0, -9.2, 0)
	_sparks.damping_min = 1.4
	_sparks.damping_max = 3.2
	_sparks.scale_amount_min = 0.006
	_sparks.scale_amount_max = 0.020
	var bm := BoxMesh.new()
	bm.size = Vector3(0.03, 0.006, 0.006)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = Color(1.0, 0.86, 0.55)
	sm.emission_enabled = true
	sm.emission = Color(1.0, 0.70, 0.32)
	sm.emission_energy_multiplier = 6.0
	bm.material = sm
	_sparks.mesh = bm
	_sparks.position = Vector3(0.0, 1.20, -5.14)
	_sparks.local_coords = false
	add_child(_sparks)

	_flash = OmniLight3D.new()
	_flash.position = Vector3(0.0, 1.30, -5.05)
	_flash.light_color = Color(1.0, 0.78, 0.48)
	_flash.light_energy = 0.0
	_flash.omni_range = 3.6
	_flash.shadow_enabled = false
	add_child(_flash)


# ---------------------------------------------------------------- 相机 / HUD
func _build_camera_and_hud() -> void:
	_cam = Camera3D.new()
	_cam.near = 0.03
	_cam.far = 140.0
	add_child(_cam)
	_cam.make_current()
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(18, 14)
	_hud.add_theme_font_size_override("font_size", 15)
	_hud.modulate = Color(0.92, 0.95, 1.0)
	layer.add_child(_hud)


func _apply_preset(i: int) -> void:
	_preset_idx = i
	var p: Dictionary = _presets[i]
	_cam.fov = float(p["fov"])
	_cam.global_position = p["pos"] as Vector3
	_cam.look_at(p["look"] as Vector3, Vector3.UP)
	var tgt: Vector3 = p["look"] as Vector3
	var dir: Vector3 = (p["pos"] as Vector3) - tgt
	_orbit_dist = dir.length()
	_orbit_yaw = atan2(dir.x, dir.z)
	_orbit_pitch = asin(clampf(dir.y / maxf(_orbit_dist, 0.001), -1.0, 1.0))
	_orbit_target = tgt


# ---------------------------------------------------------------- 输入
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_orbit_dist = maxf(2.0, _orbit_dist * 0.92)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_orbit_dist = minf(30.0, _orbit_dist * 1.08)
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_orbit_yaw += mm.relative.x * 0.006
		_orbit_pitch = clampf(_orbit_pitch + mm.relative.y * 0.005, -1.2, 1.2)
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.keycode == KEY_SPACE and _mode == "idle":
			_mode = "held"
			_pull_v = 0.0
			_struck = false
			_after_impact = false
			_post_t = 0.0
		elif k.keycode == KEY_R:
			_reset()
		elif k.keycode == KEY_F1:
			_apply_preset((_preset_idx + 1) % _presets.size())
	elif event is InputEventKey and not event.pressed:
		var k2 := event as InputEventKey
		if k2.keycode == KEY_SPACE and _mode == "held":
			_mode = "swing"
			_pull_v = 0.0


func _reset() -> void:
	_mode = "idle"
	_angle = deg_to_rad(REST_ANGLE)
	_w = 0.0
	_pull_v = 0.0
	_after_impact = false
	_post_t = 0.0


# ---------------------------------------------------------------- 摆动积分
func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _mode == "held":
		_pull_v = move_toward(_pull_v, PULL_RATE, PULL_ACCEL * delta)
		_angle += _pull_v * delta
		if _angle > deg_to_rad(MAX_PULL):
			_angle = deg_to_rad(MAX_PULL)
			_pull_v = 0.0
	elif _mode == "swing":
		var damping := POST_IMPACT_DAMPING if _after_impact else DAMPING
		var acc := -(GRAVITY / ARM_LENGTH) * sin(_angle) - damping * _w
		_w += acc * delta
		_angle += _w * delta
		if _after_impact:
			_post_t += delta
		if _angle < deg_to_rad(IMPACT_ANGLE) and _w < 0.0 and _cooldown <= 0.0 and not _struck:
			_do_impact()
		if (absf(_angle) < deg_to_rad(REST_ANGLE + 6.0) and absf(_w) < 0.35) or _post_t > 4.0:
			_angle = deg_to_rad(REST_ANGLE)
			_w = 0.0
			_mode = "idle"
			_after_impact = false
			_post_t = 0.0
	if _pivot != null:
		_pivot.rotation.x = -_angle
	# 余振（只加在可见摆臂容器上）
	_shake = maxf(0.0, _shake - delta * 1.8)
	_shake_t += delta
	var arm := get_node_or_null("SwingArm") as Node3D
	if arm != null:
		arm.rotation.x = sin(_shake_t * 46.0) * 0.0055 * _shake * exp(-_shake_t * 2.2)
	# 相机
	_cam.global_position = _orbit_target + Vector3(
		sin(_orbit_yaw) * cos(_orbit_pitch),
		sin(_orbit_pitch),
		cos(_orbit_yaw) * cos(_orbit_pitch)) * _orbit_dist
	_cam.look_at(_orbit_target, Vector3.UP)
	# 光
	if _flash != null:
		var k: float = maxf(0.0, 1.0 - _shake_t / 0.06)
		_flash.light_energy = 5.5 * k * k
	_hud.text = "ART-SAMPLE-002 英雄区演示   FPS %d\n空格=拉锤松手  R=复位  F1=切换机位(%s)  拖动=环绕\n摆角 %.1f°  角速度 %.3f  %s" % [
		Engine.get_frames_per_second(), str(_presets[_preset_idx]["name"]),
		rad_to_deg(_angle), _w, _mode]


func _do_impact() -> void:
	var strength := clampf(0.58 + absf(_w) * 0.42, 0.58, 1.2)
	_w = absf(_w) * 0.24
	_angle = deg_to_rad(IMPACT_ANGLE) + 0.015
	_after_impact = true
	_post_t = 0.0
	_struck = true
	_cooldown = 0.65
	_shake = strength
	_shake_t = 0.0
	for p in [_dust, _sparks]:
		if p != null:
			p.restart()
			p.emitting = true
	if _crystal_light != null:
		_crystal_light.light_energy = 2.6 * (1.0 + 1.4 * strength)


var _shot_path := ""


## 取证用：等画面稳定后截图并退出（队友也可以用它批量出图）
func _capture_after_frames() -> void:
	for i in range(10):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_shot_path)
	print("DEMO_SHOT " + _shot_path)
	get_tree().quit(0)

