extends Node3D

## 咕噜星第一人称试玩预览。
##
## 复用来源：
##   game/previews/resonance_coop_playtest_01_1/scripts/station_player.gd
##   game/previews/resonance_02_quality_rework/scripts/station_player.gd（两份 hash 相同）
## 控制器文件逐字复制，未改写；本脚本只负责输入映射、测试场地、HUD 与启动参数。
##
## 本轮只验证：移动、鼠标观察、第一/第三人称切换、场景碰撞、重置。
## 不包含麦克风、发现、追逐、叼走燃料、联网或正式美术。

const SOURCE_COMMIT := "42519ff403241bf5ac968edb9ae326c6fdbc74fe"
const SPAWN := Vector3(-8.0, 0.02, 0.0)
const SPAWN_YAW := -PI * 0.5
const GULU_POSITION := Vector3(2.0, 0.0, -3.5)
const FUEL_POSITION := Vector3(5.0, 0.0, 3.0)

var player: CharacterBody3D
var gulu: Node3D
var fuel: Node3D
var actors: Dictionary = {}

var _debug := false
var _help_visible := true
var _hud: CanvasLayer
var _root: Control
var _mode_label: Label
var _debug_panel: PanelContainer
var _debug_label: Label
var _crosshair_root: Control
var _help_label: Label
var _font: SystemFont

var _automation := false
var _shot_dir := "user://gulu_shots"
var _last_collisions := 0


func _ready() -> void:
	_register_input()
	_build_environment()
	_build_field()
	_build_gulu()
	_build_fuel()
	_spawn_player()
	_build_hud()

	var args := OS.get_cmdline_user_args()
	if args.has("--selftest"):
		_automation = true
		call_deferred("_run_selftest")
	elif args.has("--shots"):
		_automation = true
		call_deferred("_run_shots")

	set_process(true)


# ---------------------------------------------------------------- input

func _register_input() -> void:
	var map := {
		"move_left": KEY_A,
		"move_right": KEY_D,
		"move_up": KEY_W,
		"move_down": KEY_S,
		"sprint": KEY_SHIFT,
		"release_mouse": KEY_ESCAPE,
		"inspect_first_person": KEY_TAB,
		"brace": KEY_H,
	}
	for action in map:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_set_deadzone(action, 0.5)
		InputMap.action_erase_events(action)
		var key := InputEventKey.new()
		key.physical_keycode = int(map[action]) as Key
		InputMap.action_add_event(action, key)
	if not InputMap.has_action("capture_mouse"):
		InputMap.add_action("capture_mouse")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("capture_mouse", click)


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_R:
			reset_preview()
		KEY_F3:
			_toggle_debug()
		KEY_F1:
			_help_visible = not _help_visible
			_help_label.visible = _help_visible


# ---------------------------------------------------------------- world

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#071117")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#6f9fae")
	env.ambient_light_energy = 0.55
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color("#16333c")
	env.fog_density = 0.012
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -34.0, 0.0)
	sun.light_color = Color("#c9e8ff")
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	add_child(sun)

	var fill := OmniLight3D.new()
	fill.position = Vector3(0.0, 6.0, 0.0)
	fill.omni_range = 24.0
	fill.light_color = Color("#9fe4d2")
	fill.light_energy = 1.1
	add_child(fill)


func _build_field() -> void:
	_add_static_box(Vector3(32.0, 0.5, 26.0), Vector3(0.0, -0.25, 0.0), Color("#223238"), true)
	# 地面网格条，纯视觉。
	for i in range(-7, 8):
		_add_mesh_box(Vector3(0.05, 0.01, 26.0), Vector3(float(i) * 2.0, 0.006, 0.0), Color("#2e4a50"))
	for i in range(-6, 7):
		_add_mesh_box(Vector3(32.0, 0.01, 0.05), Vector3(0.0, 0.006, float(i) * 2.0), Color("#2e4a50"))

	# 四周舱壁。
	_add_static_box(Vector3(32.0, 4.0, 0.6), Vector3(0.0, 2.0, -13.0), Color("#1a2a31"))
	_add_static_box(Vector3(32.0, 4.0, 0.6), Vector3(0.0, 2.0, 13.0), Color("#1a2a31"))
	_add_static_box(Vector3(0.6, 4.0, 26.0), Vector3(-16.0, 2.0, 0.0), Color("#1a2a31"))
	_add_static_box(Vector3(0.6, 4.0, 26.0), Vector3(16.0, 2.0, 0.0), Color("#1a2a31"))

	# 碰撞验证墙：正前方偏右，玩家从左侧撞上去应停下。
	_add_static_box(Vector3(0.6, 3.0, 6.0), Vector3(12.0, 1.5, -4.0), Color("#2b3d44"))
	_add_mesh_box(Vector3(0.64, 0.12, 6.05), Vector3(12.0, 3.02, -4.0), Color("#72c6b7"))

	# 可绕行的箱子与低台，验证普通碰撞/step assist。
	_add_static_box(Vector3(1.0, 1.0, 1.0), Vector3(7.0, 0.5, 5.5), Color("#b77a45"))
	_add_static_box(Vector3(1.0, 1.0, 1.0), Vector3(7.2, 1.5, 5.4), Color("#c98a52"))
	_add_static_box(Vector3(1.2, 0.8, 1.2), Vector3(10.0, 0.4, 6.0), Color("#4b7f86"))
	_add_static_box(Vector3(4.0, 0.3, 3.0), Vector3(-4.0, 0.15, 6.0), Color("#33484f"))
	_add_static_box(Vector3(2.0, 0.3, 1.2), Vector3(-1.2, 0.15, 6.0), Color("#33484f"))

	# 天花板横梁，给第一人称一点纵深参照。
	for z in [-9.0, -3.0, 3.0, 9.0]:
		_add_mesh_box(Vector3(32.0, 0.24, 0.3), Vector3(0.0, 3.9, z), Color("#16262d"))


func _spawn_player() -> void:
	actors = {}
	player = load("res://scripts/station_player.gd").new() as CharacterBody3D
	player.name = "Player"
	player.position = SPAWN
	add_child(player)
	actors[1] = player
	# 复用控制器默认第三人称；咕噜星要求在进入试玩时直接是第一人称。
	player.set("use_first_person", true)
	(player.get("visual") as Node3D).visible = false
	player.call("update_camera", 1.0, true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_gulu() -> void:
	gulu = Node3D.new()
	gulu.name = "PlaceholderGulu"
	gulu.position = GULU_POSITION
	gulu.rotation.y = -0.46
	gulu.set_script(load("res://scripts/placeholder_gulu.gd"))
	add_child(gulu)

	var body := SphereMesh.new()
	body.radius = 0.52
	body.height = 1.04
	_add_mesh(gulu, body, Vector3(0.0, 0.62, 0.0), Color("#67b98d"), Vector3(1.0, 1.15, 0.92))
	var belly := SphereMesh.new()
	belly.radius = 0.3
	belly.height = 0.58
	_add_mesh(gulu, belly, Vector3(0.0, 0.5, 0.28), Color("#a8d9b8"), Vector3(1.0, 1.0, 0.55))
	var head := SphereMesh.new()
	head.radius = 0.35
	head.height = 0.7
	_add_mesh(gulu, head, Vector3(0.0, 1.28, 0.0), Color("#74c79a"), Vector3(1.0, 0.95, 1.0))

	for side in [-1.0, 1.0]:
		var eye := SphereMesh.new()
		eye.radius = 0.085
		eye.height = 0.17
		_add_mesh(gulu, eye, Vector3(side * 0.14, 1.34, -0.3), Color("#f1fff8"))
		var pupil := SphereMesh.new()
		pupil.radius = 0.040
		pupil.height = 0.08
		_add_mesh(gulu, pupil, Vector3(side * 0.14, 1.34, -0.37), Color("#14231f"))
		var ear := CylinderMesh.new()
		ear.top_radius = 0.02
		ear.bottom_radius = 0.12
		ear.height = 0.34
		var ear_node := _add_mesh(gulu, ear, Vector3(side * 0.31, 1.52, 0.0), Color("#67b98d"))
		ear_node.rotation.z = side * -0.55
		var arm := CapsuleMesh.new()
		arm.radius = 0.095
		arm.height = 0.5
		var arm_node := _add_mesh(gulu, arm, Vector3(side * 0.5, 0.66, 0.02), Color("#5eae84"))
		arm_node.rotation.z = side * 0.18
		var foot := SphereMesh.new()
		foot.radius = 0.16
		foot.height = 0.32
		_add_mesh(gulu, foot, Vector3(side * 0.24, 0.12, -0.06), Color("#4f8f70"), Vector3(1.0, 0.6, 1.25))

	var collider := StaticBody3D.new()
	collider.collision_layer = 6
	collider.collision_mask = 0
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.42
	capsule.height = 1.4
	shape.shape = capsule
	shape.position.y = 0.7
	collider.add_child(shape)
	gulu.add_child(collider)


func _build_fuel() -> void:
	fuel = StaticBody3D.new()
	fuel.name = "PlaceholderFuel"
	fuel.position = FUEL_POSITION
	fuel.set_script(load("res://scripts/fuel_prop.gd"))
	add_child(fuel)

	var body := BoxMesh.new()
	body.size = Vector3(0.52, 0.72, 0.34)
	_add_mesh(fuel, body, Vector3(0.0, 0.4, 0.0), Color("#f0a13c"))
	var cap := CylinderMesh.new()
	cap.top_radius = 0.1
	cap.bottom_radius = 0.1
	cap.height = 0.16
	_add_mesh(fuel, cap, Vector3(0.16, 0.82, 0.0), Color("#d4dde2"))
	var stripe := BoxMesh.new()
	stripe.size = Vector3(0.54, 0.08, 0.36)
	_add_mesh(fuel, stripe, Vector3(0.0, 0.34, 0.0), Color("#26343a"))
	var handle := TorusMesh.new()
	handle.inner_radius = 0.12
	handle.outer_radius = 0.2
	var handle_node := _add_mesh(fuel, handle, Vector3(-0.2, 0.72, 0.0), Color("#c9d6dc"))
	handle_node.rotation.x = PI * 0.5

	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.6, 0.9, 0.4)
	collider.shape = shape
	collider.position.y = 0.45
	fuel.add_child(collider)

	var ring := TorusMesh.new()
	ring.inner_radius = 0.48
	ring.outer_radius = 0.55
	var ring_node := _add_mesh(fuel, ring, Vector3(0.0, 0.02, 0.0), Color("#f0a13c"), Vector3.ONE, 1.8)
	ring_node.rotation.x = PI * 0.5

	var glow := OmniLight3D.new()
	glow.position = Vector3(0.0, 0.8, 0.0)
	glow.omni_range = 3.2
	glow.light_color = Color("#ffb45e")
	glow.light_energy = 1.0
	fuel.add_child(glow)


func _add_mesh(parent: Node3D, mesh: Mesh, at: Vector3, color: Color, scale: Vector3 = Vector3.ONE, emission: float = 0.0) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.scale = scale
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.78
	material.metallic = 0.08
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission
	instance.material_override = material
	parent.add_child(instance)
	return instance


func _add_mesh_box(size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _add_mesh(self, mesh, at, color)


func _add_static_box(size: Vector3, at: Vector3, color: Color, collision: bool = true) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = 6
	body.collision_mask = 0
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	instance.material_override = material
	body.add_child(instance)
	if collision:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)
	add_child(body)
	return body


# ---------------------------------------------------------------- HUD

func _build_hud() -> void:
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])

	_hud = CanvasLayer.new()
	_hud.layer = 10
	add_child(_hud)
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var theme := Theme.new()
	theme.default_font = _font
	theme.default_font_size = 15
	_root.theme = theme

	var panel := PanelContainer.new()
	panel.position = Vector2(22, 20)
	panel.custom_minimum_size = Vector2(470, 0)
	panel.add_theme_stylebox_override("panel", _panel_style())
	_root.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)

	var title := Label.new()
	title.text = "咕噜星 · 第一人称试玩"
	title.add_theme_font_size_override("font_size", 21)
	title.add_theme_color_override("font_color", Color("#e9f7f3"))
	column.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "占位场地 · 只验证移动、观察与碰撞"
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", Color("#8fb3ae"))
	column.add_child(subtitle)

	_help_label = Label.new()
	_help_label.text = "WASD 移动 · Shift 加速 · 鼠标观察\nTab 切换视角 · R 回到起点 · Esc 释放鼠标 · 左键收回鼠标\nF3 调试 · F1 隐藏说明"
	_help_label.add_theme_font_size_override("font_size", 13)
	_help_label.add_theme_color_override("font_color", Color("#b9d4cf"))
	column.add_child(_help_label)

	_mode_label = Label.new()
	_mode_label.position = Vector2(1080, 22)
	_mode_label.size = Vector2(176, 30)
	_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_mode_label.add_theme_font_size_override("font_size", 17)
	_mode_label.add_theme_color_override("font_color", Color("#7dffd4"))
	_root.add_child(_mode_label)

	_crosshair_root = Control.new()
	_crosshair_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_crosshair_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_crosshair_root)
	var h := ColorRect.new()
	h.color = Color(0.75, 1.0, 0.92, 0.8)
	h.position = Vector2(634, 399)
	h.size = Vector2(12, 2)
	_crosshair_root.add_child(h)
	var v := ColorRect.new()
	v.color = Color(0.75, 1.0, 0.92, 0.8)
	v.position = Vector2(639, 394)
	v.size = Vector2(2, 12)
	_crosshair_root.add_child(v)

	_debug_panel = PanelContainer.new()
	_debug_panel.position = Vector2(22, 606)
	_debug_panel.custom_minimum_size = Vector2(460, 0)
	_debug_panel.add_theme_stylebox_override("panel", _panel_style(0.92))
	_debug_panel.visible = false
	_root.add_child(_debug_panel)
	var dmargin := MarginContainer.new()
	dmargin.add_theme_constant_override("margin_left", 12)
	dmargin.add_theme_constant_override("margin_right", 12)
	dmargin.add_theme_constant_override("margin_top", 8)
	dmargin.add_theme_constant_override("margin_bottom", 8)
	_debug_panel.add_child(dmargin)
	_debug_label = Label.new()
	_debug_label.add_theme_font_size_override("font_size", 12)
	_debug_label.add_theme_color_override("font_color", Color("#a9d8cd"))
	dmargin.add_child(_debug_label)

	set_process(true)


func _panel_style(alpha: float = 0.82) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.06, 0.075, alpha)
	style.border_color = Color(0.25, 0.5, 0.46, 0.55)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 9
	style.corner_radius_top_right = 9
	style.corner_radius_bottom_left = 9
	style.corner_radius_bottom_right = 9
	return style


func _process(_delta: float) -> void:
	if player == null:
		return
	var first := bool(player.get("use_first_person"))
	_mode_label.text = "第一人称" if first else "第三人称"
	_mode_label.add_theme_color_override("font_color", Color("#7dffd4") if first else Color("#ffcf5c"))
	_crosshair_root.visible = first
	if _debug:
		var pos := player.global_position
		var contacts := int(player.get("contacts"))
		var cam := player.get("camera") as Camera3D
		_debug_label.text = "\n".join(PackedStringArray([
			"FPS %d · 视角 %s · 位置 %.2f, %.2f, %.2f" % [Engine.get_frames_per_second(), "FPS" if first else "TPS", pos.x, pos.y, pos.z],
			"镜头高 %.2f m · FOV %.0f · 碰撞计数 %d" % [cam.global_position.y - pos.y, cam.fov, contacts - _last_collisions],
			"咕噜 %s" % (gulu.call("get_debug_text") if gulu else "—"),
			"燃料 %s" % (fuel.call("get_debug_text") if fuel else "—"),
			"Tab 切换 · R 重置 · 本轮无行为",
		]))


func _toggle_debug() -> void:
	_debug = not _debug
	_debug_panel.visible = _debug


# ---------------------------------------------------------------- reset / camera helpers

func reset_preview() -> void:
	if player == null:
		return
	player.global_position = SPAWN
	player.velocity = Vector3.ZERO
	player.rotation.y = SPAWN_YAW
	player.set("_camera_yaw", SPAWN_YAW)
	player.set("_camera_yaw_target", SPAWN_YAW)
	player.set("_camera_pitch", -0.18)
	player.set("_camera_pitch_target", -0.18)
	player.set("use_first_person", true)
	(player.get("visual") as Node3D).visible = false
	player.call("update_camera", 1.0, true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_last_collisions = int(player.get("contacts"))
	print("GULU reset spawn=%s" % str(SPAWN))


func clamp_cave_camera_position(_target: Vector3, desired: Vector3) -> Vector3:
	return Vector3(
		clampf(desired.x, -15.2, 15.2),
		clampf(desired.y, 1.2, 7.0),
		clampf(desired.z, -12.2, 12.2)
	)


func _teleport(at: Vector3, yaw: float) -> void:
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.rotation.y = yaw
	player.set("_camera_yaw", yaw)
	player.set("_camera_yaw_target", yaw)
	player.set("_camera_pitch", -0.18)
	player.set("_camera_pitch_target", -0.18)
	player.call("update_camera", 1.0, true)


# ---------------------------------------------------------------- automation

func _check(condition: bool, label: String, passes: Array, failures: Array) -> void:
	if condition:
		passes.append(label)
		print("PASS  %s" % label)
	else:
		failures.append(label)
		print("FAIL  %s" % label)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _run_selftest() -> void:
	await _wait(0.8)
	var passes: Array = []
	var failures: Array = []
	print("GULU SELFTEST start source=%s" % SOURCE_COMMIT)

	_check(bool(player.get("use_first_person")), "default first person", passes, failures)
	var cam := player.get("camera") as Camera3D
	var eye_delta := cam.global_position.y - player.global_position.y
	_check(absf(eye_delta - 1.65) < 0.06, "camera eye height 1.65", passes, failures)
	_check(absf(cam.fov - 62.0) < 0.1, "camera fov 62", passes, failures)

	# 两个占位对象应在首屏可见（防止摆到镜头后面或场外）。
	var screen_size := get_viewport().get_visible_rect().size
	var gulu_screen := cam.unproject_position(gulu.global_position + Vector3.UP * 0.8)
	var fuel_screen := cam.unproject_position(fuel.global_position + Vector3.UP * 0.45)
	print("GULU screen gulu=%s fuel=%s viewport=%s" % [gulu_screen, fuel_screen, screen_size])
	_check(gulu_screen.x > 0.0 and gulu_screen.x < screen_size.x and gulu_screen.y > 0.0 and gulu_screen.y < screen_size.y, "placeholder gulu visible on entry", passes, failures)
	_check(fuel_screen.x > 0.0 and fuel_screen.x < screen_size.x and fuel_screen.y > 0.0 and fuel_screen.y < screen_size.y, "placeholder fuel visible on entry", passes, failures)

	# 真实动作输入：W 前进。
	var start := player.global_position
	Input.action_press("move_up")
	await _wait(0.9)
	Input.action_release("move_up")
	await get_tree().physics_frame
	var travelled := player.global_position.x - start.x
	_check(travelled > 2.0, "WASD movement forward (%.2f m)" % travelled, passes, failures)

	# 鼠标观察：走 _unhandled_input 的镜头路径。headless 没有真实鼠标捕获，跳过窗口外验证。
	_teleport(SPAWN, SPAWN_YAW)
	if DisplayServer.get_name() == "headless":
		print("SKIP mouse look / pitch (headless has no captured mouse)")
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		var before_yaw := float(player.get("_camera_yaw_target"))
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(160.0, 0.0)
		player.call("_unhandled_input", motion)
		await get_tree().physics_frame
		var after_yaw := float(player.get("_camera_yaw_target"))
		_check(absf(after_yaw - before_yaw) > 0.15, "mouse look changes yaw", passes, failures)
		var big := InputEventMouseMotion.new()
		big.relative = Vector2(0.0, 10000.0)
		player.call("_unhandled_input", big)
		await get_tree().physics_frame
		var pitch := float(player.get("_camera_pitch_target"))
		_check(pitch <= 0.3001 and pitch >= -0.5801, "pitch clamped (%.3f)" % pitch, passes, failures)

	# 碰撞：从墙左侧持续前进，应被内墙挡住。
	_teleport(Vector3(10.2, 0.02, -4.0), -PI * 0.5)
	Input.action_press("move_up")
	await _wait(1.4)
	Input.action_release("move_up")
	await get_tree().physics_frame
	var wall_x := player.global_position.x
	_check(wall_x < 11.8 and wall_x > 10.9, "wall collision stops player (x=%.2f)" % wall_x, passes, failures)

	# 第一/第三人称切换（回到开阔点，避免第三人称镜头被刚撞到的墙压到角色身上）。
	_teleport(SPAWN, SPAWN_YAW)
	await get_tree().physics_frame
	var toggle := InputEventAction.new()
	toggle.action = "inspect_first_person"
	toggle.pressed = true
	player.call("_unhandled_input", toggle)
	await get_tree().physics_frame
	_check(not bool(player.get("use_first_person")), "Tab switches to third person", passes, failures)
	await _wait(0.7)
	_check((player.get("visual") as Node3D).visible, "third person shows body", passes, failures)
	player.call("_unhandled_input", toggle)
	await get_tree().physics_frame
	_check(bool(player.get("use_first_person")), "Tab returns to first person", passes, failures)
	_check(not (player.get("visual") as Node3D).visible, "first person hides own body", passes, failures)

	# 重置。
	reset_preview()
	await get_tree().physics_frame
	_check(player.global_position.distance_to(SPAWN) < 0.2, "reset returns to spawn", passes, failures)
	_check(bool(player.get("use_first_person")), "reset restores first person", passes, failures)

	_toggle_debug()
	await _wait(0.25)
	_check(_debug_label.text.length() > 0 and _debug_label.text.contains("咕噜"), "debug panel renders", passes, failures)
	_toggle_debug()

	Input.action_release("move_up")
	Input.action_release("sprint")
	print("GULU SELFTEST SUMMARY passes=%d failures=%d" % [passes.size(), failures.size()])
	await _wait(0.2)
	get_tree().quit(0 if failures.is_empty() else 1)


func _run_shots() -> void:
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	await _wait(0.8)
	_teleport(Vector3(-3.0, 0.02, -1.0), -PI * 0.5)
	await _wait(0.5)
	var shot_cam := player.get("camera") as Camera3D
	print("GULU SHOT view gulu=%s fuel=%s" % [shot_cam.unproject_position(gulu.global_position + Vector3.UP * 0.8), shot_cam.unproject_position(fuel.global_position + Vector3.UP * 0.45)])
	await _shot("01_first_person.png")

	var toggle := InputEventAction.new()
	toggle.action = "inspect_first_person"
	toggle.pressed = true
	player.call("_unhandled_input", toggle)
	await _wait(0.7)
	await _shot("02_third_person.png")
	player.call("_unhandled_input", toggle)
	await _wait(0.3)
	print("GULU SHOTS dir=%s" % ProjectSettings.globalize_path(_shot_dir))
	get_tree().quit(0)


func _shot(file_name: String) -> void:
	DisplayServer.window_move_to_foreground()
	RenderingServer.force_draw()
	await get_tree().process_frame
	await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	var path := _shot_dir.path_join(file_name)
	var error := image.save_png(path)
	print("SHOT %s %s" % [file_name, "ok" if error == OK else error_string(error)])
