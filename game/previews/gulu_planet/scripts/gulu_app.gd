extends Node3D

## 奶龙星第一人称试玩预览（内部路径沿用 gulu_planet）。
##
## 复用来源：
##   game/previews/resonance_coop_playtest_01_1/scripts/station_player.gd
##   game/previews/resonance_02_quality_rework/scripts/station_player.gd（两份 hash 相同）
## 控制器保留原有移动/碰撞实现；第一人称镜头按飞船视角逐值对齐
## （space_player_3d.gd @ 42519ff：眼高 1.6、FOV 74、俯仰 ±1.25、灵敏度 0.0020）。
##
## 本轮玩法闭环：
##   奶龙叼着燃料 → 玩家挑衅 → 它靠近/蓄势 → 玩家站到装货口前 → 侧移躲开
##   → 燃料脱口飞入收集仓；没接住就落地，可捡回再试。
##   也可以先引开它，再自己把燃料搬进装货口（安全但路远）。

const SOURCE_COMMIT := "42519ff403241bf5ac968edb9ae326c6fdbc74fe"
const SPAWN := Vector3(-11.0, 0.02, 5.0)
const SPAWN_YAW := -PI * 0.5
const DRAGON_HOME := Vector3(1.0, 0.0, -2.5)
const DRAGON_HOME_YAW := PI * 0.5
## 燃料 0 = 教学罐（出生点前、奶龙看不见）；1 = 奶龙地盘上的；2 = 开场就在它嘴里。
const FUEL_HOMES: Array[Vector3] = [
	Vector3(-8.0, 0.0, 4.4),   # 第一罐：捡起来自己搬，教学用
	Vector3(4.4, 0.0, -5.0),   # 第二罐：奶龙窝边，去拿会有干扰
	Vector3(2.6, 0.0, -3.4),   # 第三罐：开场被奶龙叼着
]
const TARGET_COUNT := 3

const GROUND := Color("#4e615e")
const GROUND_DARK := Color("#5d706d")
const STONE := Color("#8fa29d")
const TRIM := Color("#375967")
const AMBER := Color("#ffb347")
const CYAN := Color("#3fd8ff")

var player: CharacterBody3D
var gulu: CharacterBody3D
var collector: Node3D
var env_art: Node3D
var blender_test_asset: Node3D
var _lock_marker: Node3D
var _lock_material: StandardMaterial3D
var _lock_active := false
var fuels: Array = []
var actors: Dictionary = {}

var loaded_count := 0
var completed := false

var _debug := false
var _help_visible := true
var _hud: CanvasLayer
var _root: Control
var _mode_label: Label
var _objective_label: Label
var _counter_label: Label
var _pips: Array[ColorRect] = []
var _debug_panel: PanelContainer
var _debug_label: Label
var _crosshair_root: Control
var _help_label: Label
var _prompt_panel: PanelContainer
var _prompt_label: Label
var _banner: PanelContainer
var _banner_label: Label
var _font: SystemFont
var _sfx: Node
var _feedback := ""
var _feedback_timer := 0.0

var _automation := false
var _shot_dir := "user://gulu_shots"
var _last_collisions := 0


func _ready() -> void:
	_register_input()
	_build_environment()
	_build_field()
	_build_lock_marker()
	_build_collector()
	_spawn_player()
	_build_fuels()
	_build_gulu()
	_build_blender_test_asset()
	_build_sfx()
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
		"provoke": KEY_Q,
		"interact": KEY_E,
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
	if event.is_action_pressed("provoke"):
		_try_provoke()
		return
	if event.is_action_pressed("interact"):
		_try_interact()
		return
	match event.keycode:
		KEY_R:
			reset_preview()
		KEY_F3:
			_toggle_debug()
		KEY_F4:
			_toggle_blender_test()
		KEY_F1:
			_toggle_help()


# ---------------------------------------------------------------- world

func _build_environment() -> void:
	# 配色对齐飞船内部（ship_hub_3d.gd）：暖灰壳体 + 深蓝绿结构 + 冷白环境光。
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("#1b3141")
	sky_material.sky_horizon_color = Color("#9db6b8")
	sky_material.sky_curve = 0.22
	sky_material.ground_bottom_color = Color("#2a3a3a")
	sky_material.ground_horizon_color = Color("#7d9490")
	sky_material.sun_angle_max = 18.0
	sky_material.sun_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = sky_material
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#dbeaf1")
	env.ambient_light_energy = 0.26
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color("#8fa6aa")
	env.fog_density = 0.006
	env.fog_sky_affect = 0.15
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.9
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -34.0, 0.0)
	sun.light_color = Color("#ffe9cf")
	sun.light_energy = 0.55
	sun.light_specular = 0.15
	sun.shadow_enabled = true
	add_child(sun)

	var fill := OmniLight3D.new()
	fill.position = Vector3(4.0, 7.0, 0.0)
	fill.omni_range = 22.0
	fill.light_color = Color("#cfe9e4")
	fill.light_energy = 0.18
	add_child(fill)


func _build_field() -> void:
	# 场景美术放到独立模块（scripts/nailong_environment.gd）。
	# 本文件只做玩法对象；碰撞边界、装货判定 AABB 都不变。
	env_art = load("res://scripts/nailong_environment.gd").new() as Node3D
	env_art.name = "EnvironmentArt"
	add_child(env_art)


## 蓄势锁定的地面标记：一出现就说明「这块地要被扑了」，比文字直观。
func _build_lock_marker() -> void:
	_lock_marker = Node3D.new()
	_lock_marker.name = "PounceLockMarker"
	add_child(_lock_marker)
	_lock_material = StandardMaterial3D.new()
	_lock_material.albedo_color = Color(1.0, 0.42, 0.22, 0.85)
	_lock_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lock_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_lock_material.emission_enabled = true
	_lock_material.emission = Color(1.0, 0.38, 0.2)
	_lock_material.emission_energy_multiplier = 1.2
	var torus := TorusMesh.new()
	torus.inner_radius = 0.82
	torus.outer_radius = 0.98
	torus.rings = 40
	torus.ring_segments = 8
	var ring := MeshInstance3D.new()
	ring.mesh = torus
	ring.material_override = _lock_material
	_lock_marker.add_child(ring)
	for index in range(4):
		var tick := BoxMesh.new()
		tick.size = Vector3(0.10, 0.02, 0.32)
		var node := MeshInstance3D.new()
		node.mesh = tick
		node.material_override = _lock_material
		var angle := float(index) * PI * 0.5
		node.position = Vector3(cos(angle) * 1.12, 0.0, sin(angle) * 1.12)
		node.rotation.y = -angle
		_lock_marker.add_child(node)
	_lock_marker.visible = false


func _on_windup_locked(point: Vector3) -> void:
	_lock_active = true
	_lock_marker.global_position = Vector3(point.x, 0.03, point.z)
	_lock_marker.visible = true
	_lock_marker.scale = Vector3.ONE * 0.72
	var tween := create_tween()
	tween.tween_property(_lock_marker, "scale", Vector3.ONE * 1.15, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _on_pounce_ended(_point: Vector3) -> void:
	_lock_active = false
	var tween := create_tween()
	tween.tween_interval(0.2)
	tween.tween_property(_lock_marker, "scale", Vector3.ONE * 0.3, 0.3)
	tween.tween_callback(func() -> void: _lock_marker.visible = false)


func _build_collector() -> void:
	collector = load("res://scripts/collector.gd").new() as Node3D
	collector.name = "ShipLoadingBay"
	collector.set("target_count", TARGET_COUNT)
	add_child(collector)
	collector.connect("fuel_collected", _on_fuel_collected)


func _spawn_player() -> void:
	actors = {}
	player = load("res://scripts/station_player.gd").new() as CharacterBody3D
	player.name = "Player"
	player.position = SPAWN
	add_child(player)
	actors[1] = player
	player.set("use_first_person", true)
	(player.get("visual") as Node3D).visible = false
	player.call("update_camera", 1.0, true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_fuels() -> void:
	fuels.clear()
	for index in range(FUEL_HOMES.size()):
		var fuel := load("res://scripts/fuel_prop.gd").new() as CharacterBody3D
		fuel.name = "Fuel%d" % (index + 1)
		fuel.position = FUEL_HOMES[index]
		fuel.set("display_name", "燃料罐 %d" % (index + 1))
		add_child(fuel)
		fuel.setup_collector(collector)
		fuel.connect("landed", _on_fuel_landed)
		_build_fuel_mesh(fuel)
		fuels.append(fuel)


func _build_fuel_mesh(fuel: Node3D) -> void:
	# 三级可读性：远处看剪影（罐体 + 提手 + 阀），中景看加强筋与标签，近景看能量窗。
	_add_mesh_child(fuel, _boxm(Vector3(0.52, 0.08, 0.38)), Vector3(0.0, 0.05, 0.0), TRIM)
	_add_mesh_child(fuel, _boxm(Vector3(0.56, 0.46, 0.40)), Vector3(0.0, 0.31, 0.0), AMBER)
	_add_mesh_child(fuel, _boxm(Vector3(0.50, 0.16, 0.36)), Vector3(0.0, 0.62, 0.0), Color("#e39338"))
	_add_mesh_child(fuel, _boxm(Vector3(0.40, 0.10, 0.30)), Vector3(0.0, 0.74, 0.0), Color("#d4dde2"))
	# 能量窗：正反两面都有，近距离才看得出的「能量部分」
	for side in [-1.0, 1.0]:
		_add_mesh_child(fuel, _boxm(Vector3(0.34, 0.34, 0.01)), Vector3(0.0, 0.42, side * 0.196), TRIM)
		_add_mesh_child(fuel, _boxm(Vector3(0.30, 0.26, 0.02)), Vector3(0.0, 0.42, side * 0.205), CYAN, 1.3)
	# 加强筋
	for height in [0.14, 0.38, 0.56]:
		_add_mesh_child(fuel, _boxm(Vector3(0.58, 0.035, 0.42)), Vector3(0.0, height, 0.0), TRIM)
	# 接口：颈 + 阀体 + 阀轮
	_add_mesh_child(fuel, _cylm(0.075, 0.075, 0.12), Vector3(0.13, 0.82, 0.0), Color("#c9d6dc"))
	_add_mesh_child(fuel, _cylm(0.055, 0.055, 0.09), Vector3(0.13, 0.90, 0.0), TRIM)
	_add_mesh_child(fuel, _torusm(0.055, 0.095), Vector3(0.13, 0.96, 0.0), Color("#c9d6dc"))
	# 提手
	var handle_node := _add_mesh_child(fuel, _torusm(0.10, 0.17), Vector3(-0.16, 0.86, 0.0), Color("#c9d6dc"))
	handle_node.rotation.x = PI * 0.5
	# 侧面标签
	_add_mesh_child(fuel, _boxm(Vector3(0.20, 0.10, 0.02)), Vector3(-0.16, 0.48, 0.205), TRIM)
	# 底座脚
	for side in [-1.0, 1.0]:
		_add_mesh_child(fuel, _boxm(Vector3(0.12, 0.06, 0.30)), Vector3(side * 0.18, 0.03, 0.0), TRIM)
	# 地面光环（玩法用 base_ring：被抱起来时隐藏）
	var ring_node := _add_mesh_child(fuel, _torusm(0.42, 0.48), Vector3(0.0, 0.02, 0.0), AMBER, 1.7)
	fuel.set("base_ring", ring_node)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.6, 0.9, 0.4)
	collider.shape = shape
	collider.position.y = 0.45
	fuel.add_child(collider)
	var glow := OmniLight3D.new()
	glow.position = Vector3(0.0, 0.7, 0.0)
	glow.omni_range = 1.7
	glow.light_color = AMBER
	glow.light_energy = 0.35
	fuel.add_child(glow)
	fuel.set("glow_light", glow)


func _boxm(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


func _cylm(r_top: float, r_bottom: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = r_top
	mesh.bottom_radius = r_bottom
	mesh.height = height
	mesh.radial_segments = 16
	return mesh


func _torusm(inner: float, outer: float) -> TorusMesh:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 24
	mesh.ring_segments = 8
	return mesh


func _build_gulu() -> void:
	gulu = load("res://scripts/milk_dragon.gd").new() as CharacterBody3D
	gulu.name = "MilkDragon"
	gulu.position = DRAGON_HOME
	gulu.rotation.y = DRAGON_HOME_YAW
	var visual := load("res://scripts/milk_dragon_visual.gd").new() as Node3D
	visual.name = "Visual"
	gulu.add_child(visual)
	add_child(gulu)
	gulu.call("setup_actors", [player])
	gulu.call("setup_fuels", fuels)
	gulu.call("setup_loading_zone", collector)
	gulu.call("start_holding", fuels[2])
	gulu.connect("pounce_finished", _on_pounce_finished)
	gulu.connect("fuel_grabbed", _on_fuel_grabbed)
	gulu.connect("fuel_released", _on_fuel_released)
	gulu.connect("spotted_cargo", _on_spotted_cargo)
	gulu.connect("fuel_snatched", _on_fuel_snatched)
	gulu.connect("windup_locked", _on_windup_locked)
	gulu.connect("pounce_ended", _on_pounce_ended)


func _build_blender_test_asset() -> void:
	var packed := load("res://assets/test/blender_link_test.glb") as PackedScene
	if packed == null:
		push_error("Blender 测试 GLB 未导入")
		return
	blender_test_asset = packed.instantiate() as Node3D
	blender_test_asset.name = "BlenderLinkTest"
	blender_test_asset.position = Vector3(-16.0, 0.0, 4.0)
	blender_test_asset.visible = false
	add_child(blender_test_asset)


func _toggle_blender_test() -> void:
	if blender_test_asset != null:
		blender_test_asset.visible = not blender_test_asset.visible


func _build_sfx() -> void:
	_sfx = load("res://scripts/sfx.gd").new() as Node
	_sfx.name = "Sfx"
	add_child(_sfx)
	if gulu != null:
		gulu.connect("state_changed", _on_dragon_state_changed)


func _on_dragon_state_changed(_previous: String, current: String) -> void:
	if _sfx == null:
		return
	match current:
		"注意":
			_sfx.call("play", "notice")
		"蓄势":
			_sfx.call("play", "windup")


# ---------------------------------------------------------------- helpers

func _material(color: Color, emission: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.93
	material.metallic = 0.02
	material.metallic_specular = 0.18
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission
	return material


func _add_mesh(mesh: Mesh, at: Vector3, color: Color, emission: float = 0.0, scale: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.scale = scale
	instance.material_override = _material(color, emission)
	add_child(instance)
	return instance


func _add_mesh_child(parent: Node3D, mesh: Mesh, at: Vector3, color: Color, emission: float = 0.0) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.material_override = _material(color, emission)
	parent.add_child(instance)
	return instance


func _add_static_box(size: Vector3, at: Vector3, color: Color, collision: bool = true) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = 2
	body.collision_mask = 0
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _material(color)
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
	title.text = "奶龙星 · 装货试玩"
	title.add_theme_font_size_override("font_size", 21)
	title.add_theme_color_override("font_color", Color("#e9f7f3"))
	column.add_child(title)

	_objective_label = Label.new()
	_objective_label.text = "把 3 罐燃料装进飞船装货口"
	_objective_label.add_theme_font_size_override("font_size", 14)
	_objective_label.add_theme_color_override("font_color", Color("#ffcf8a"))
	column.add_child(_objective_label)

	_help_label = Label.new()
	_help_label.text = "WASD 移动 · Shift 加速 · 鼠标观察 · Q 挑衅 · E 拾取/放下\nTab 切换视角 · R 重开 · Esc 释放鼠标 · F1 隐藏说明 · F3 调试 · F4 测试模型"
	_help_label.add_theme_font_size_override("font_size", 12)
	_help_label.add_theme_color_override("font_color", Color("#b9d4cf"))
	column.add_child(_help_label)

	_mode_label = Label.new()
	_mode_label.position = Vector2(1080, 22)
	_mode_label.size = Vector2(176, 30)
	_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_mode_label.add_theme_font_size_override("font_size", 15)
	_mode_label.add_theme_color_override("font_color", Color("#7dffd4"))
	_root.add_child(_mode_label)

	_counter_label = Label.new()
	_counter_label.position = Vector2(1000, 54)
	_counter_label.size = Vector2(256, 30)
	_counter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_counter_label.add_theme_font_size_override("font_size", 19)
	_counter_label.add_theme_color_override("font_color", Color("#ffcf8a"))
	_root.add_child(_counter_label)
	for index in range(TARGET_COUNT):
		var pip := ColorRect.new()
		pip.position = Vector2(1124 + index * 44, 90)
		pip.size = Vector2(34, 10)
		pip.color = Color(0.24, 0.33, 0.34, 0.9)
		_root.add_child(pip)
		_pips.append(pip)

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

	_prompt_panel = PanelContainer.new()
	_prompt_panel.position = Vector2(300, 700)
	_prompt_panel.custom_minimum_size = Vector2(680, 52)
	_prompt_panel.add_theme_stylebox_override("panel", _panel_style(0.86))
	_root.add_child(_prompt_panel)
	var pmargin := MarginContainer.new()
	pmargin.add_theme_constant_override("margin_left", 18)
	pmargin.add_theme_constant_override("margin_right", 18)
	pmargin.add_theme_constant_override("margin_top", 7)
	pmargin.add_theme_constant_override("margin_bottom", 7)
	_prompt_panel.add_child(pmargin)
	_prompt_label = Label.new()
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt_label.add_theme_font_size_override("font_size", 16)
	_prompt_label.add_theme_color_override("font_color", Color("#e9f7f3"))
	_prompt_label.text = "走近燃料按 E 搬走，或站到装货口前挑衅奶龙"
	pmargin.add_child(_prompt_label)

	_banner = PanelContainer.new()
	_banner.position = Vector2(340, 300)
	_banner.custom_minimum_size = Vector2(600, 0)
	_banner.add_theme_stylebox_override("panel", _panel_style(0.94))
	_banner.visible = false
	_root.add_child(_banner)
	var bmargin := MarginContainer.new()
	bmargin.add_theme_constant_override("margin_left", 26)
	bmargin.add_theme_constant_override("margin_right", 26)
	bmargin.add_theme_constant_override("margin_top", 20)
	bmargin.add_theme_constant_override("margin_bottom", 20)
	_banner.add_child(bmargin)
	_banner_label = Label.new()
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.add_theme_font_size_override("font_size", 24)
	_banner_label.add_theme_color_override("font_color", Color("#ffe0a8"))
	_banner_label.text = "装货完成！\n按 R 再来一次"
	bmargin.add_child(_banner_label)

	_debug_panel = PanelContainer.new()
	_debug_panel.position = Vector2(22, 240)
	_debug_panel.custom_minimum_size = Vector2(470, 0)
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

	_counter_label.text = "已装 0 / %d" % TARGET_COUNT
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


func _process(delta: float) -> void:
	if player == null:
		return
	var first := bool(player.get("use_first_person"))
	_mode_label.text = "第一人称" if first else "第三人称"
	_mode_label.add_theme_color_override("font_color", Color("#7dffd4") if first else Color("#ffcf5c"))
	_crosshair_root.visible = first
	_feedback_timer = maxf(_feedback_timer - delta, 0.0)

	for index in range(_pips.size()):
		var lit: bool = index < loaded_count
		_pips[index].color = AMBER if lit else Color(0.24, 0.33, 0.34, 0.9)

	_lock_pulse(delta)
	_update_prompt()

	if _debug:
		var pos := player.global_position
		var contacts := int(player.get("contacts"))
		var cam := player.get("camera") as Camera3D
		_debug_label.text = "\n".join(PackedStringArray([
			"FPS %d · 视角 %s · 位置 %.2f, %.2f, %.2f" % [Engine.get_frames_per_second(), "FPS" if first else "TPS", pos.x, pos.y, pos.z],
			"镜头高 %.2f m · FOV %.0f · 碰撞计数 %d" % [cam.global_position.y - pos.y, cam.fov, contacts - _last_collisions],
			"奶龙 %s" % (gulu.call("debug_text") if gulu else "—"),
			"装货 %d/%d · 燃料 %s" % [loaded_count, TARGET_COUNT, _fuels_debug()],
			"Q 挑衅 · E 拾取/放下 · Tab 视角 · R 重开",
		]))


func _fuels_debug() -> String:
	var parts: PackedStringArray = []
	for fuel in fuels:
		parts.append(String(fuel.call("get_debug_text")))
	return " | ".join(parts)


func _update_prompt() -> void:
	if completed:
		_set_prompt("返航准备完成！按 R 再来一次，或继续在场上走动", Color("#ffe0a8"))
		return
	if _feedback_timer > 0.0:
		_set_prompt(_feedback, Color("#ffcf5c"))
		return
	var carrying := _carried_fuel() != null
	var dragon_state := String(gulu.call("state_name")) if gulu != null else "待机"
	var holding: bool = bool(gulu.get("has_fuel")) if gulu != null else false
	var snatching: float = float(gulu.call("snatch_progress")) if gulu != null else 0.0
	var near_bay := player.global_position.x > 9.4
	var in_bay := player.global_position.x > 11.2
	if dragon_state == "蓄势":
		_set_prompt("它锁定了你脚下的红圈——出去！", Color("#ff7a5e"))
		return
	if dragon_state == "扑击":
		_set_prompt("扑击！立刻离开它锁定的位置", Color("#ff5a4a"))
		return
	if snatching > 0.05:
		_set_prompt("它要抢你手上的燃料了——快走开，或按 E 放下", Color("#ff8a5e"))
		return
	if carrying:
		if in_bay:
			_set_prompt("再往里走一点，燃料就会被吸进去", Color("#ffcf8a"))
		elif near_bay:
			_set_prompt("抱着燃料直接走进装货口就行", Color("#ffcf8a"))
		else:
			_set_prompt("抱着燃料：沿青色导引条送到船头，E 放下", Color("#ffcf8a"))
		return
	if in_bay:
		_set_prompt("舱口里没法挑衅——先退出去几米，再回头按 Q", Color("#8fa6b2"))
		return
	if near_bay and holding:
		_set_prompt("站住别动，按 Q 让它扑过来——它一张嘴，燃料就往里飞", Color("#7dffd4"))
		return
	if holding and dragon_state in ["待机", "找燃料", "注意", "靠近"]:
		_set_prompt("它嘴里那罐可以抢回来：站到装货口前按 Q 挑衅它", Color("#7dffd4"))
		return
	var nearby := _nearest_free_fuel(6.0)
	if nearby != null:
		if loaded_count == 0 and _nearest_free_fuel(3.2) != null:
			_set_prompt("先用 E 抱起脚边这罐，沿着青色地标走到船头装货口", Color("#ffcf8a"))
		else:
			_set_prompt("E 搬起这罐燃料——绕远路自己搬，或引开它再搬", Color("#ffcf8a"))
		return
	match dragon_state:
		"待机", "找燃料":
			_set_prompt("它守着剩下的燃料。按 Q 挑衅，把它引到别处再搬", Color("#e9f7f3"))
		"注意":
			_set_prompt("它注意到你了，正转向你", Color("#7dffd4"))
		"靠近":
			_set_prompt("它正在靠近——再按 Q 会激怒它", Color("#ffcf5c"))
		"恢复":
			if bool(gulu.get("last_pounce_hit")):
				_set_prompt("被扑到了（不掉血），它正在恢复", Color("#9fe8d8"))
			else:
				_set_prompt("它扑空了，正在喘气——这是搬运窗口", Color("#9fe8d8"))
		"回窝":
			_set_prompt("它失去兴趣，回去了", Color("#8fa6b2"))
		_:
			_set_prompt("按 Q 挑衅奶龙", Color("#e9f7f3"))


func _lock_pulse(_delta: float) -> void:
	if _lock_material == null:
		return
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
	_lock_material.emission_energy_multiplier = 0.9 + (0.9 * pulse if _lock_active else 0.0)


func _set_prompt(text: String, color: Color) -> void:
	if _prompt_label.text != text:
		_prompt_label.text = text
	_prompt_label.add_theme_color_override("font_color", color)


# ---------------------------------------------------------------- actions

func _carried_fuel() -> Node3D:
	for fuel in fuels:
		if String(fuel.get("mode")) == "player":
			return fuel
	return null


func _nearest_free_fuel(max_distance: float) -> Node3D:
	var best: Node3D = null
	var best_distance := max_distance
	for fuel in fuels:
		if not bool(fuel.call("can_pick_up", player, max_distance)):
			continue
		var distance := player.global_position.distance_to(fuel.global_position)
		if distance < best_distance:
			best = fuel
			best_distance = distance
	return best


func _try_provoke() -> void:
	if gulu == null or player == null:
		return
	# 仓口是卸货区，不是掩体：躲进去就挑衅不到它了。
	if player.global_position.x > 11.2:
		_feedback = "它不肯冲进装货口——先退到舱口外再挑衅"
		_feedback_timer = 2.0
		return
	var result: Dictionary = gulu.call("try_provoke", player)
	if bool(result.get("ok", false)):
		_feedback = ""
		_feedback_timer = 0.0
	else:
		_feedback = String(result.get("reason", "现在不能挑衅"))
		_feedback_timer = 1.4


func _try_interact() -> void:
	if player == null:
		return
	var carried := _carried_fuel()
	if carried != null:
		carried.call("drop_from_player", player)
		_feedback = "燃料已放下"
		_feedback_timer = 1.2
		return
	var target := _nearest_free_fuel(2.6)
	if target != null:
		target.call("pick_up", player)
		_feedback = "抱起燃料——搬进船头装货口，或按 E 放下"
		_feedback_timer = 2.0
	else:
		_feedback = "走近燃料再按 E"
		_feedback_timer = 1.2


func _on_fuel_collected(total: int, target: int) -> void:
	loaded_count = total
	if _sfx != null:
		_sfx.call("play", "loaded")
	_counter_label.text = "已装 %d / %d" % [loaded_count, target]
	_feedback = "入仓确认！%d / %d" % [loaded_count, target]
	_feedback_timer = 1.6
	if env_art != null and is_instance_valid(env_art):
		env_art.call("on_loaded", loaded_count)
	if loaded_count >= target and not completed:
		completed = true
		_banner.visible = true


func _on_fuel_landed(_fuel: Node3D) -> void:
	_feedback = "燃料落地了——去捡回来，靠近它按 E"
	_feedback_timer = 2.2


func _on_fuel_grabbed(fuel: Node3D) -> void:
	if _sfx != null:
		_sfx.call("play", "chomp")
	_feedback = "奶龙把%s叼走了！" % String(fuel.get("display_name"))
	_feedback_timer = 2.0


func _on_fuel_released(_fuel: Node3D) -> void:
	if _sfx != null:
		_sfx.call("play", "release")
	_feedback = "它张嘴了——燃料飞出去了！"
	_feedback_timer = 1.4


func _on_spotted_cargo(_who: Node3D) -> void:
	if _sfx != null:
		_sfx.call("play", "notice")
	_feedback = "它看见你手里的燃料了——别让它贴太近"
	_feedback_timer = 2.2


func _on_fuel_snatched(fuel: Node3D) -> void:
	if _sfx != null:
		_sfx.call("play", "chomp")
	_feedback = "它一口把%s抢走了！现在挑衅它，让它扑到装货口前" % String(fuel.get("display_name"))
	_feedback_timer = 3.0


func _on_pounce_finished(hit: bool) -> void:
	if hit:
		var carried := _carried_fuel()
		if carried != null:
			carried.call("drop_from_player", player)
			_feedback = "被扑到了！手上的燃料掉了——趁它恢复捡回来"
			_feedback_timer = 2.6


func _toggle_debug() -> void:
	_debug = not _debug
	_debug_panel.visible = _debug
	if gulu != null:
		gulu.call("set_debug_ring", _debug)


func _toggle_help() -> void:
	_help_visible = not _help_visible
	_help_label.visible = _help_visible


# ---------------------------------------------------------------- reset

func reset_preview() -> void:
	if player == null:
		return
	player.global_position = SPAWN
	player.velocity = Vector3.ZERO
	player.rotation.y = SPAWN_YAW
	player.set("_camera_yaw", SPAWN_YAW)
	player.set("_camera_yaw_target", SPAWN_YAW)
	player.set("_camera_pitch", 0.0)
	player.set("_camera_pitch_target", 0.0)
	player.set("use_first_person", true)
	(player.get("visual") as Node3D).visible = false
	player.call("update_camera", 1.0, true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	for fuel in fuels:
		fuel.call("reset_to_home")
	if collector != null:
		collector.call("reset_state")
	loaded_count = 0
	completed = false
	_banner.visible = false
	_counter_label.text = "已装 0 / %d" % TARGET_COUNT
	if gulu != null:
		gulu.call("reset_to_home")
		gulu.call("start_holding", fuels[2])
	_feedback = ""
	_feedback_timer = 0.0
	_last_collisions = int(player.get("contacts"))
	print("GULU reset spawn=%s" % str(SPAWN))


func clamp_cave_camera_position(_target: Vector3, desired: Vector3) -> Vector3:
	return Vector3(
		clampf(desired.x, -19.0, 19.0),
		clampf(desired.y, 1.2, 7.5),
		clampf(desired.z, -14.0, 14.0)
	)


func _place_player(at: Vector3, look_target: Vector3) -> void:
	_teleport(at, atan2(-(look_target.x - at.x), -(look_target.z - at.z)))


func _teleport(at: Vector3, yaw: float) -> void:
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.rotation.y = yaw
	player.set("_camera_yaw", yaw)
	player.set("_camera_yaw_target", yaw)
	player.set("_camera_pitch", 0.0)
	player.set("_camera_pitch_target", 0.0)
	player.call("update_camera", 1.0, true)


func _press_provoke() -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_Q
	event.keycode = KEY_Q
	event.pressed = true
	event.echo = false
	_unhandled_key_input(event)


func _press_interact() -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_E
	event.keycode = KEY_E
	event.pressed = true
	event.echo = false
	_unhandled_key_input(event)


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


## 等到奶龙进入某个状态（比固定等待稳，避免调参后测试时间错位）。
func _await_state(target_state: String, timeout: float) -> bool:
	var waited := 0.0
	while waited < timeout:
		if gulu != null and gulu.state_name() == target_state:
			return true
		await _wait(0.05)
		waited += 0.05
	return false


func _run_selftest() -> void:
	await _wait(0.8)
	var passes: Array = []
	var failures: Array = []
	print("GULU SELFTEST start source=%s" % SOURCE_COMMIT)

	# --- 视角：与飞船第一人称逐值一致 ---
	_check(bool(player.get("use_first_person")), "default first person", passes, failures)
	var cam := player.get("camera") as Camera3D
	var eye_delta := cam.global_position.y - player.global_position.y
	_check(absf(eye_delta - 1.6) < 0.03, "camera eye height matches ship 1.6 (%.3f)" % eye_delta, passes, failures)
	_check(absf(cam.fov - 74.0) < 0.1, "camera fov matches ship 74 (%.1f)" % cam.fov, passes, failures)
	_check(absf(cam.near - 0.05) < 0.001, "camera near matches ship 0.05", passes, failures)
	var visual := player.get("visual") as Node3D
	_check(absf(visual.scale.x - 1.0) < 0.001, "player visual scale matches ship 1.0", passes, failures)

	# --- 首屏可读性 ---
	var screen_size := get_viewport().get_visible_rect().size
	var gulu_screen := cam.unproject_position(gulu.global_position + Vector3.UP * 0.8)
	print("GULU screen gulu=%s viewport=%s" % [gulu_screen, screen_size])
	_check(gulu_screen.x > 0.0 and gulu_screen.x < screen_size.x and gulu_screen.y > 0.0 and gulu_screen.y < screen_size.y, "dragon visible on entry", passes, failures)

	# --- 玩家建模复用同一套主角资源 ---
	var body := visual.find_child("Body", true, false)
	_check(body != null, "player model built from shared protagonist skin", passes, failures)
	var mesh_count := 0
	if body != null:
		mesh_count = body.find_children("*", "MeshInstance3D", true, false).size()
	_check(mesh_count > 3, "player skin meshes present (%d)" % mesh_count, passes, failures)

	# --- Blender GLB 管线仍在（F4 切换显示）---
	_check(blender_test_asset != null and not blender_test_asset.visible, "Blender test asset hidden by default", passes, failures)
	_toggle_blender_test()
	await get_tree().physics_frame
	var ba_meshes: Array = blender_test_asset.find_children("*", "MeshInstance3D", true, false) if blender_test_asset != null else []
	_check(blender_test_asset != null and blender_test_asset.visible and ba_meshes.size() == 4, "F4 shows imported Blender GLB (4 meshes)", passes, failures)
	_toggle_blender_test()
	await get_tree().physics_frame
	_check(not blender_test_asset.visible, "F4 hides Blender test asset again", passes, failures)

	# --- 场景美术模块 ---
	var env_meshes: Array = env_art.find_children("*", "MeshInstance3D", true, false) if env_art != null else []
	_check(env_art != null and env_meshes.size() > 150, "environment art module built (%d meshes)" % env_meshes.size(), passes, failures)
	var arms: Array = env_art.get("_clamp_arms") if env_art != null else []
	_check(arms.size() == 2, "loading-bay clamp arms present (%d)" % arms.size(), passes, failures)

	# --- 音效资源已导入 ---
	var sfx_players := _sfx.get("_players") as Dictionary
	var sfx_count := sfx_players.size() if sfx_players != null else 0
	_check(sfx_count == 5, "sfx streams imported (%d/5)" % sfx_count, passes, failures)

	# --- 基础移动与碰撞 ---
	var start := player.global_position
	Input.action_press("move_up")
	await _wait(0.9)
	Input.action_release("move_up")
	await get_tree().physics_frame
	var travelled := player.global_position.x - start.x
	_check(travelled > 2.0, "WASD movement forward (%.2f m)" % travelled, passes, failures)

	_teleport(Vector3(17.8, 0.02, 8.0), PI * 0.5)
	Input.action_press("move_up")
	await _wait(1.2)
	Input.action_release("move_up")
	await get_tree().physics_frame
	_check(player.global_position.x < 19.7, "outer wall stops player (x=%.2f)" % player.global_position.x, passes, failures)

	# --- 视角切换 ---
	_teleport(SPAWN, SPAWN_YAW)
	await get_tree().physics_frame
	var toggle := InputEventAction.new()
	toggle.action = "inspect_first_person"
	toggle.pressed = true
	player.call("_unhandled_input", toggle)
	await get_tree().physics_frame
	_check(not bool(player.get("use_first_person")), "Tab switches to third person", passes, failures)
	_check(absf(cam.fov - 62.0) < 0.1, "third person restores fov 62", passes, failures)
	await _wait(0.5)
	_check(visual.visible, "third person shows body", passes, failures)
	player.call("_unhandled_input", toggle)
	await get_tree().physics_frame
	_check(bool(player.get("use_first_person")), "Tab returns to first person", passes, failures)
	_check(absf(cam.fov - 74.0) < 0.1, "first person restores ship fov", passes, failures)

	# --- 起始状态：奶龙叼着第三罐，前两罐在地上 ---
	_check(bool(gulu.get("has_fuel")), "dragon starts holding fuel", passes, failures)
	_check(String(fuels[2].get("mode")) == "dragon", "starting fuel is carried by dragon", passes, failures)
	_check(String(fuels[0].get("mode")) == "free" and String(fuels[1].get("mode")) == "free", "two fuels start on the ground", passes, failures)
	var anchor: Node3D = gulu.call("mouth_anchor")
	_check(anchor != null and fuels[2].global_position.distance_to(anchor.global_position) < 0.4, "dragon mouth anchor holds fuel", passes, failures)

	# --- 挑衅 → 注意 → 靠近 ---
	reset_preview()
	_place_player(Vector3(-4.5, 0.02, -2.0), DRAGON_HOME)
	await _wait(0.2)
	_press_provoke()
	await _wait(0.06)
	_check(gulu.state_name() == "注意", "Q provoke makes dragon notice", passes, failures)
	await _wait(0.8)
	_check(gulu.state_name() == "靠近", "dragon approaches after notice", passes, failures)
	var approach_distance := player.global_position.distance_to(gulu.global_position)
	await _wait(0.6)
	_check(player.global_position.distance_to(gulu.global_position) < approach_distance - 0.3, "dragon closes distance", passes, failures)
	_check(bool(gulu.get("has_fuel")), "dragon keeps fuel while provoked", passes, failures)

	# 隔岩挑衅被拒绝
	reset_preview()
	_place_player(Vector3(2.2, 0.02, 8.8), DRAGON_HOME)
	await _wait(0.2)
	_press_provoke()
	await _wait(0.1)
	_check(gulu.state_name() == "待机", "provoke blocked by rock is rejected", passes, failures)
	_check(float(gulu.get("agitation")) < 0.01, "blocked provoke adds no agitation", passes, failures)

	# 冷却
	reset_preview()
	_place_player(Vector3(-4.5, 0.02, -2.0), DRAGON_HOME)
	await _wait(0.2)
	_press_provoke()
	_press_provoke()
	await _wait(0.06)
	_check(float(gulu.get("agitation")) <= 0.51, "provoke cooldown blocks rapid repeats", passes, failures)

	# --- 核心场面：借力送货 ---
	reset_preview()
	_place_player(Vector3(9.2, 0.02, 0.0), DRAGON_HOME)
	await _wait(0.2)
	_press_provoke()
	await _wait(0.85)
	_press_provoke()
	var got_windup: bool = await _await_state("蓄势", 4.0)
	_check(got_windup, "agitated dragon closes in, then winds up", passes, failures)
	_check(_lock_marker.visible and Vector2(_lock_marker.global_position.x - player.global_position.x, _lock_marker.global_position.z - player.global_position.z).length() < 0.4, "windup shows a lock marker on the floor", passes, failures)
	var locked := player.global_position
	Input.action_press("move_right")
	await _wait(1.2)
	Input.action_release("move_right")
	_check(not bool(gulu.get("last_pounce_hit")), "player can dodge the pounce", passes, failures)
	_check(player.global_position.distance_to(locked) > 0.6, "dodge moved player off the locked spot", passes, failures)
	await _wait(1.8)
	_check(loaded_count >= 1, "fuel launched by pounce lands in the bay (loaded=%d)" % loaded_count, passes, failures)

	# 重复计数保护
	var before_total := loaded_count
	var any_fuel: Node3D = fuels[1]
	collector.call("consume", any_fuel)
	await get_tree().process_frame
	_check(loaded_count == before_total + 1, "hand delivery counts once", passes, failures)
	collector.call("consume", any_fuel)
	await get_tree().process_frame
	_check(loaded_count == before_total + 1, "consuming same fuel twice does not double count", passes, failures)

	# --- 拾取 / 放下 / 掉落 ---
	reset_preview()
	_place_player(FUEL_HOMES[0] + Vector3(-1.2, 0.02, 0.0), FUEL_HOMES[0])
	await _wait(0.2)
	_check(bool(fuels[0].call("can_pick_up", player)), "fuel can be picked up", passes, failures)
	_press_interact()
	await _wait(0.15)
	_check(String(fuels[0].get("mode")) == "player", "E picks up fuel", passes, failures)
	_check(int(fuels[0].collision_layer) == 0, "carried fuel disables collision", passes, failures)
	_check(fuels[0].global_position.distance_to(player.global_position) < 1.4, "carried fuel follows player", passes, failures)
	_press_interact()
	await _wait(0.15)
	_check(String(fuels[0].get("mode")) == "free", "E drops fuel", passes, failures)
	_check(int(fuels[0].collision_layer) != 0, "dropped fuel restores collision", passes, failures)

	# 自己抱着走进装货口：应该自动入仓
	_place_player(FUEL_HOMES[0] + Vector3(-1.2, 0.02, 0.0), FUEL_HOMES[0])
	await _wait(0.2)
	_press_interact()
	await _wait(0.15)
	var before_hand := loaded_count
	_teleport(Vector3(13.6, 0.02, 0.0), 0.0)
	await _wait(0.4)
	_check(loaded_count == before_hand + 1, "carrying fuel into the bay loads it", passes, failures)

	# 被扑中掉落
	reset_preview()
	_place_player(FUEL_HOMES[0] + Vector3(-1.2, 0.02, 0.0), FUEL_HOMES[0])
	await _wait(0.2)
	_press_interact()
	await _wait(0.1)
	_check(String(fuels[0].get("mode")) == "player", "fuel carried for pounce test", passes, failures)
	_place_player(Vector3(1.2, 0.02, 0.6), DRAGON_HOME)
	await _wait(0.2)
	_press_provoke()
	await _wait(0.85)
	_press_provoke()
	var got_windup2: bool = await _await_state("蓄势", 4.0)
	_check(got_windup2, "stationary player triggers windup", passes, failures)
	await _wait(1.7)
	_check(bool(gulu.get("last_pounce_hit")), "pounce can hit a stationary player", passes, failures)
	_check(String(fuels[0].get("mode")) != "player", "getting pounced drops carried fuel", passes, failures)

	# --- 舱口不能当掩体：站在装货口里挑衅应被拒绝 ---
	reset_preview()
	_place_player(Vector3(13.0, 0.02, 0.0), DRAGON_HOME)
	await _wait(0.2)
	_press_provoke()
	await _wait(0.1)
	_check(float(gulu.get("agitation")) < 0.01, "provoking inside the loading bay is rejected", passes, failures)
	_check(_feedback.contains("装货口"), "bay provoke shows a clear reason", passes, failures)

	# --- 看见你抱着燃料 → 凑过来 → 抢走 ---
	reset_preview()
	gulu.call("_release_fuel")
	await get_tree().physics_frame
	_place_player(FUEL_HOMES[1] + Vector3(-1.0, 0.02, 0.0), FUEL_HOMES[1])
	await _wait(0.2)
	_press_interact()
	await _wait(0.3)
	_check(String(fuels[1].get("mode")) == "player", "fuel picked up near dragon", passes, failures)
	_check(gulu.state_name() == "注意", "dragon spots the carried fuel", passes, failures)
	_teleport(gulu.global_position + Vector3(1.6, 0.02, 0.0), 0.0)
	await _wait(1.6)
	_check(String(fuels[1].get("mode")) == "dragon", "dragon snatches the carried fuel", passes, failures)

	# --- 奶龙找燃料 ---
	reset_preview()
	await _wait(0.2)
	_check(bool(gulu.get("has_fuel")), "dragon holds fuel after reset", passes, failures)
	# 让它把嘴里那罐丢掉，并站到一罐散装燃料旁边，验证它会自己去叼。
	gulu.call("_release_fuel")
	await get_tree().physics_frame
	gulu.set("global_position", Vector3(2.0, 0.0, -6.0))
	gulu.call("_set_state", "idle", true)
	await _wait(4.5)
	_check(String(fuels[1].get("mode")) == "dragon", "dragon forages and grabs loose fuel", passes, failures)

	# --- 完成与重开 ---
	reset_preview()
	await _wait(0.2)
	collector.call("consume", fuels[0])
	await get_tree().process_frame
	collector.call("consume", fuels[1])
	await get_tree().process_frame
	collector.call("consume", fuels[2])
	await _wait(0.2)
	_check(loaded_count == TARGET_COUNT, "loading three fuels reaches target", passes, failures)
	_check(completed and _banner.visible, "completion banner shows", passes, failures)

	reset_preview()
	await get_tree().physics_frame
	_check(player.global_position.distance_to(SPAWN) < 0.2, "reset returns to spawn", passes, failures)
	_check(bool(player.get("use_first_person")), "reset restores first person", passes, failures)
	_check(gulu.state_name() == "待机", "reset restores dragon idle", passes, failures)
	_check(loaded_count == 0 and not completed and not _banner.visible, "reset clears loading progress", passes, failures)
	_check(int(fuels[2].collision_layer) == 0 and bool(gulu.get("has_fuel")), "reset re-attaches starting fuel", passes, failures)
	_check(String(fuels[0].get("mode")) == "free" and String(fuels[1].get("mode")) == "free", "reset returns loose fuels", passes, failures)

	# --- 调试面板与状态环 ---
	_toggle_debug()
	await _wait(0.25)
	_check(_debug_label.text.contains("奶龙") and _debug_label.text.contains("装货"), "debug panel renders", passes, failures)
	_check(bool((gulu.get("visual") as Node3D).get("ring_enabled")), "debug mode enables dragon state ring", passes, failures)
	_toggle_debug()
	await _wait(0.1)
	_check(not bool((gulu.get("visual") as Node3D).get("ring_enabled")), "normal play hides dragon state ring", passes, failures)

	Input.action_release("move_up")
	Input.action_release("move_right")
	Input.action_release("sprint")
	print("GULU SELFTEST SUMMARY passes=%d failures=%d" % [passes.size(), failures.size()])
	await _wait(0.2)
	get_tree().quit(0 if failures.is_empty() else 1)


func _run_shots() -> void:
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	await _wait(1.0)

	# 01 出生点：燃料、奶龙、装货口同屏（验收项 1）
	_teleport(SPAWN, SPAWN_YAW)
	await _wait(0.7)
	await _shot("01_spawn_fuel_dragon_bay.png")

	# 02 搬运途中：抱着教学罐走在中场，能看清通路（验收项 2）
	_place_player(FUEL_HOMES[0] + Vector3(0.9, 0.02, 0.5), Vector3(13.0, 0.0, 0.0))
	await _wait(0.3)
	_press_interact()
	await _wait(0.3)
	Input.action_press("move_up")
	await _wait(0.9)
	Input.action_release("move_up")
	await _wait(0.2)
	# 换到一个能同时看见「通路 + 装货口 + 奶龙凑过来」的站位
	_place_player(Vector3(-2.0, 0.02, -0.8), Vector3(12.0, 1.2, 0.0))
	await _wait(0.25)
	_press_provoke()
	await _wait(0.55)
	await _shot("02_carry_midfield.png")

	# 03 奶龙看见你手里的燃料，凑过来
	reset_preview()
	_place_player(Vector3(3.2, 0.02, -4.2), DRAGON_HOME)
	await _wait(0.25)
	_press_interact()
	await _wait(0.45)
	await _shot("03_dragon_approach.png")

	# 04 舱口前：蓄势、躲避区、燃料还挂在嘴上（验收项 3）
	reset_preview()
	_place_player(Vector3(9.2, 0.02, 0.0), DRAGON_HOME)
	await _wait(0.3)
	_press_provoke()
	await _wait(0.85)
	_press_provoke()
	await _await_state("蓄势", 4.0)
	await _wait(0.4)
	await _shot("04_bay_front_windup.png")

	# 05 侧移躲开之后把镜头转向舱口，抓燃料飞行中的一帧
	Input.action_press("move_right")
	await _wait(0.9)
	Input.action_release("move_right")
	var guard := 0
	while String(fuels[2].get("mode")) != "thrown" and guard < 200:
		await _wait(0.02)
		guard += 1
	_place_player(Vector3(6.0, 0.02, 2.6), Vector3(13.5, 1.2, 0.0))
	await _wait(0.10)
	await _shot("05_fuel_in_flight.png")

	# 06 入仓反馈：夹臂 + 三格指示灯 + 舱内打光（抓到入仓那一拍）
	guard = 0
	while loaded_count < 1 and guard < 300:
		await _wait(0.02)
		guard += 1
	_place_player(Vector3(9.6, 0.02, 4.8), Vector3(13.4, 1.7, 0.0))
	await _wait(0.12)
	await _shot("06_bay_load_feedback.png")

	# 07 窝区近景：压扁的货箱、拖痕、散落包装（验收项 4）
	reset_preview()
	_place_player(Vector3(4.9, 0.02, 0.4), Vector3(1.0, 0.6, -2.6))
	await _wait(0.6)
	await _shot("07_nest_closeup.png")

	# 08 场地全景：装货口—搬运场地—窝，一次看全
	_place_player(Vector3(-6.5, 0.02, 8.4), Vector3(8.0, 1.0, -2.0))
	await _wait(0.5)
	await _shot("08_yard_wide.png")

	print("GULU SHOTS dir=%s" % ProjectSettings.globalize_path(_shot_dir))
	get_tree().quit(0)


func _shot(file_name: String) -> void:
	RenderingServer.force_draw()
	await get_tree().process_frame
	await get_tree().process_frame
	if player != null and gulu != null:
		var shot_cam := player.get("camera") as Camera3D
		var head := shot_cam.unproject_position(gulu.global_position + Vector3.UP * 1.0)
		var view := get_viewport().get_visible_rect().size
		var on_screen := head.x > 0.0 and head.x < view.x and head.y > 0.0 and head.y < view.y
		var fuel_modes: PackedStringArray = []
		for fuel in fuels:
			fuel_modes.append(String(fuel.get("mode")))
		var player_screen := shot_cam.unproject_position(player.global_position + Vector3.UP * 0.9)
		var fuel_note := ""
		for fuel in fuels:
			if String(fuel.get("mode")) == "thrown":
				fuel_note = " thrown_at=%s" % shot_cam.unproject_position(fuel.global_position)
		print("SHOTMETA %s dragon_screen=%s on_screen=%s player_screen=%s loaded=%d state=%s holding=%s fuels=%s%s" % [
			file_name, head, on_screen, player_screen, loaded_count, gulu.state_name(), str(gulu.get("has_fuel")), ",".join(fuel_modes), fuel_note])
	var image := get_viewport().get_texture().get_image()
	var path := _shot_dir.path_join(file_name)
	var error := image.save_png(path)
	print("SHOT %s %s" % [file_name, "ok" if error == OK else error_string(error)])
