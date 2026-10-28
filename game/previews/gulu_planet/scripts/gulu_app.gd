extends Node3D

## 奶龙星第一人称试玩预览（内部路径沿用 gulu_planet）。
##
## 复用来源：
##   game/previews/resonance_coop_playtest_01_1/scripts/station_player.gd
##   game/previews/resonance_02_quality_rework/scripts/station_player.gd（两份 hash 相同）
## 控制器文件逐字复制，未改写；本脚本只负责输入映射、测试场地、HUD 与启动参数。
##
## 本轮验证：移动、鼠标观察、第一/第三人称、场景碰撞，以及
## “挑衅 → 注意 → 靠近 → 蓄势扑击 → 躲开/恢复”的最小互动。
## 不包含麦克风、真实抢燃料、伤害、道具、联网或正式美术。

const SOURCE_COMMIT := "42519ff403241bf5ac968edb9ae326c6fdbc74fe"
const SPAWN := Vector3(-8.0, 0.02, 0.0)
const SPAWN_YAW := -PI * 0.5
const GULU_POSITION := Vector3(2.0, 0.0, -3.5)
const FUEL_POSITION := Vector3(5.0, 0.0, 3.0)

var player: CharacterBody3D
var gulu: CharacterBody3D
var fuel: Node3D
var blender_test_asset: Node3D
var actors: Dictionary = {}

var _debug := false
var _help_visible := true
var _hud: CanvasLayer
var _root: Control
var _mode_label: Label
var _creature_label: Label
var _agitation_bar: ProgressBar
var _debug_panel: PanelContainer
var _debug_label: Label
var _crosshair_root: Control
var _help_label: Label
var _prompt_panel: PanelContainer
var _prompt_label: Label
var _font: SystemFont
var _feedback := ""
var _feedback_timer := 0.0

var _automation := false
var _shot_dir := "user://gulu_shots"
var _last_collisions := 0


func _ready() -> void:
	_register_input()
	_build_environment()
	_build_field()
	_spawn_player()
	_build_gulu()
	_build_fuel()
	_build_blender_test_asset()
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

	# 视线测试柱：从它后面挑衅不应生效；不挡主路线。
	_add_static_box(Vector3(0.8, 2.4, 0.6), Vector3(-2.0, 1.2, -4.7), Color("#2b3d44"))
	_add_mesh_box(Vector3(0.84, 0.10, 0.64), Vector3(-2.0, 2.42, -4.7), Color("#72c6b7"))

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
	# 复用控制器默认第三人称；奶龙星要求在进入试玩时直接是第一人称。
	player.set("use_first_person", true)
	(player.get("visual") as Node3D).visible = false
	player.call("update_camera", 1.0, true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_gulu() -> void:
	gulu = load("res://scripts/milk_dragon.gd").new() as CharacterBody3D
	gulu.name = "MilkDragon"
	gulu.position = GULU_POSITION
	gulu.rotation.y = -0.46
	var visual := load("res://scripts/milk_dragon_visual.gd").new() as Node3D
	visual.name = "Visual"
	gulu.add_child(visual)
	add_child(gulu)
	gulu.call("setup_player", player)

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

func _build_blender_test_asset() -> void:
	var packed := load("res://assets/test/blender_link_test.glb") as PackedScene
	if packed == null:
		push_error("Blender 测试 GLB 未导入")
		return
	blender_test_asset = packed.instantiate() as Node3D
	blender_test_asset.name = "BlenderLinkTest"
	blender_test_asset.position = Vector3(-4.0, 0.0, 2.5)
	add_child(blender_test_asset)


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
	title.text = "奶龙星 · 第一人称试玩"
	title.add_theme_font_size_override("font_size", 21)
	title.add_theme_color_override("font_color", Color("#e9f7f3"))
	column.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "占位场地 · 验证挑衅、靠近、扑击与躲开"
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", Color("#8fb3ae"))
	column.add_child(subtitle)

	_help_label = Label.new()
	_help_label.text = "WASD 移动 · Shift 加速 · 鼠标观察 · Q 挑衅\nTab 切换视角 · R 重置 · Esc 释放鼠标 · 左键收回鼠标\nF3 调试 · F1 隐藏说明"
	_help_label.add_theme_font_size_override("font_size", 12)
	_help_label.add_theme_color_override("font_color", Color("#b9d4cf"))
	column.add_child(_help_label)

	_mode_label = Label.new()
	_mode_label.position = Vector2(1080, 22)
	_mode_label.size = Vector2(176, 30)
	_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_mode_label.add_theme_font_size_override("font_size", 17)
	_mode_label.add_theme_color_override("font_color", Color("#7dffd4"))
	_root.add_child(_mode_label)

	_creature_label = Label.new()
	_creature_label.position = Vector2(944, 58)
	_creature_label.size = Vector2(312, 26)
	_creature_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_creature_label.add_theme_font_size_override("font_size", 15)
	_creature_label.add_theme_color_override("font_color", Color("#9fe8d8"))
	_creature_label.text = "奶龙：待机 · 关注 —"
	_root.add_child(_creature_label)

	_agitation_bar = ProgressBar.new()
	_agitation_bar.position = Vector2(1024, 88)
	_agitation_bar.size = Vector2(232, 12)
	_agitation_bar.min_value = 0.0
	_agitation_bar.max_value = 100.0
	_agitation_bar.value = 0.0
	_agitation_bar.show_percentage = false
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.04, 0.1, 0.12, 0.9)
	bar_bg.border_color = Color(0.3, 0.5, 0.46, 0.5)
	bar_bg.set_border_width_all(1)
	bar_bg.corner_radius_top_left = 3
	bar_bg.corner_radius_top_right = 3
	bar_bg.corner_radius_bottom_left = 3
	bar_bg.corner_radius_bottom_right = 3
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color("#ff9a54")
	bar_fill.corner_radius_top_left = 3
	bar_fill.corner_radius_top_right = 3
	bar_fill.corner_radius_bottom_left = 3
	bar_fill.corner_radius_bottom_right = 3
	_agitation_bar.add_theme_stylebox_override("background", bar_bg)
	_agitation_bar.add_theme_stylebox_override("fill", bar_fill)
	_root.add_child(_agitation_bar)

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
	_prompt_panel.position = Vector2(330, 690)
	_prompt_panel.custom_minimum_size = Vector2(620, 52)
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
	_prompt_label.text = "走近奶龙，面向它按 Q 挑衅"
	pmargin.add_child(_prompt_label)

	_debug_panel = PanelContainer.new()
	_debug_panel.position = Vector2(22, 520)
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


func _process(delta: float) -> void:
	if player == null:
		return
	var first := bool(player.get("use_first_person"))
	_mode_label.text = "第一人称" if first else "第三人称"
	_mode_label.add_theme_color_override("font_color", Color("#7dffd4") if first else Color("#ffcf5c"))
	_crosshair_root.visible = first
	_feedback_timer = maxf(_feedback_timer - delta, 0.0)

	if gulu != null:
		var state := String(gulu.call("state_name"))
		var ag := float(gulu.get("agitation"))
		_creature_label.text = "奶龙：%s · 关注 %s" % [state, String(gulu.call("focus_name"))]
		_agitation_bar.tooltip_text = "上头 %d%%" % int(round(ag * 100.0))
		_creature_label.add_theme_color_override("font_color", _state_color(state))
		_agitation_bar.value = ag * 100.0
		_update_prompt(state)

	if _debug:
		var pos := player.global_position
		var contacts := int(player.get("contacts"))
		var cam := player.get("camera") as Camera3D
		_debug_label.text = "\n".join(PackedStringArray([
			"FPS %d · 视角 %s · 位置 %.2f, %.2f, %.2f" % [Engine.get_frames_per_second(), "FPS" if first else "TPS", pos.x, pos.y, pos.z],
			"镜头高 %.2f m · FOV %.0f · 碰撞计数 %d" % [cam.global_position.y - pos.y, cam.fov, contacts - _last_collisions],
			"奶龙 %s" % (gulu.call("debug_text") if gulu else "—"),
			"燃料 %s" % (fuel.call("get_debug_text") if fuel else "—"),
			"Q 挑衅 · Tab 视角 · R 重置 · 本轮不结算抢夺/伤害",
		]))


func _state_color(state: String) -> Color:
	match state:
		"注意":
			return Color("#7dffd4")
		"靠近":
			return Color("#ffcf5c")
		"蓄势", "扑击":
			return Color("#ff6b5a")
		"恢复":
			return Color("#9fb3ae")
		"回窝":
			return Color("#8fa6b2")
		_:
			return Color("#9fe8d8")


func _update_prompt(state: String) -> void:
	var prompt := ""
	var color := Color("#e9f7f3")
	var distance := player.global_position.distance_to(gulu.global_position)
	if state == "蓄势":
		prompt = "它压低身体、盯住你了——要扑了，侧移躲开！"
		color = Color("#ff7a5e")
	elif state == "扑击":
		prompt = "扑击！立刻离开它锁定的位置"
		color = Color("#ff5a4a")
	elif _feedback_timer > 0.0:
		prompt = _feedback
		color = Color("#ffcf5c")
	else:
		match state:
			"待机":
				if distance > 9.0:
					prompt = "走近奶龙（9 m 内），面向它按 Q 挑衅"
				else:
					prompt = "按 Q 挑衅奶龙，把它从燃料路线引开"
			"注意":
				prompt = "它注意到你了，正转向你"
				color = Color("#7dffd4")
			"靠近":
				prompt = "它正在靠近——再按 Q 会激怒它"
				color = Color("#ffcf5c")
			"恢复":
				if bool(gulu.get("last_pounce_hit")):
					prompt = "被扑到了（原型不结算伤害），它正在恢复"
				else:
					prompt = "它扑空了，正在喘气——这是搬运窗口"
				color = Color("#9fe8d8")
			"回窝":
				prompt = "它失去兴趣，回去了"
				color = Color("#8fa6b2")
			_:
				prompt = "按 Q 挑衅奶龙"
	if prompt != _prompt_label.text:
		_prompt_label.text = prompt
	_prompt_label.add_theme_color_override("font_color", color)


func _try_provoke() -> void:
	if gulu == null or player == null:
		return
	var result: Dictionary = gulu.call("try_provoke", player)
	if bool(result.get("ok", false)):
		_feedback = ""
		_feedback_timer = 0.0
	else:
		_feedback = String(result.get("reason", "现在不能挑衅"))
		_feedback_timer = 1.4

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
	if gulu != null:
		gulu.call("reset_to_home")
	_feedback = ""
	_feedback_timer = 0.0
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


func _yaw_to(target: Vector3) -> float:
	var direction := target - player.global_position
	return atan2(-direction.x, -direction.z)


func _press_provoke() -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_Q
	event.keycode = KEY_Q
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

	# Blender 独立测试资产：GLB 已导入，检查节点、比例、轴向与材质。
	var ba := blender_test_asset
	var ba_meshes: Array = ba.find_children("*", "MeshInstance3D", true, false) if ba != null else []
	print("BLENDER_TEST meshes=%d" % ba_meshes.size())
	for mi in ba_meshes:
		var mesh_instance := mi as MeshInstance3D
		var mats: Array = []
		for s in mesh_instance.mesh.get_surface_count():
			var m := mesh_instance.get_active_material(s)
			mats.append(m.resource_name if m != null else "null")
		print("BLENDER_TEST node=%s pos=%s scale=%s aabb=%s mats=%s" % [mesh_instance.name, mesh_instance.position, mesh_instance.global_transform.basis.get_scale(), mesh_instance.get_aabb().size, mats])
	_check(ba != null and ba_meshes.size() == 4, "Blender GLB imports four meshes", passes, failures)
	var body_mesh := ba.find_child("Body", true, false) as MeshInstance3D if ba != null else null
	var fwd_marker := ba.find_child("ForwardMarker", true, false) as Node3D if ba != null else null
	var top_marker := ba.find_child("TopMarker", true, false) as Node3D if ba != null else null
	_check(body_mesh != null, "Blender body node exists", passes, failures)
	if body_mesh != null:
		var body_size := body_mesh.get_aabb().size
		_check(absf(body_size.x - 0.8) < 0.03 and absf(body_size.y - 0.8) < 0.03 and absf(body_size.z - 0.8) < 0.03, "Blender scale is 0.8 m body", passes, failures)
		var body_material := body_mesh.get_active_material(0) as StandardMaterial3D
		_check(body_material != null and body_material.albedo_color.r > body_material.albedo_color.b, "Blender material imports", passes, failures)
	_check(fwd_marker != null and fwd_marker.position.z < -0.4, "Blender +Y becomes Godot -Z", passes, failures)
	_check(top_marker != null and top_marker.position.y > 0.8, "Blender +Z becomes Godot +Y", passes, failures)

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

	# 奶龙行为：挑衅 → 注意 → 靠近 → 蓄势 → 扑击 → 玩家躲开 → 恢复。
	reset_preview()
	_teleport(Vector3(-5.0, 0.02, -3.5), _yaw_to(GULU_POSITION))
	await _wait(0.2)
	_check(gulu.state_name() == "待机", "dragon starts idle", passes, failures)
	_press_provoke()
	await _wait(0.06)
	_check(gulu.state_name() == "注意", "Q provoke makes dragon notice", passes, failures)
	_check(float(gulu.get("agitation")) > 0.2, "provoke raises agitation", passes, failures)
	await _wait(0.8)
	_check(gulu.state_name() == "靠近", "dragon approaches after notice", passes, failures)
	var approach_distance := player.global_position.distance_to(gulu.global_position)
	await _wait(0.7)
	var closer_distance := player.global_position.distance_to(gulu.global_position)
	_check(closer_distance < approach_distance - 0.4, "dragon closes distance (%.2f -> %.2f)" % [approach_distance, closer_distance], passes, failures)

	_press_provoke()
	await _wait(0.8)
	_press_provoke()
	await _wait(0.15)
	_check(gulu.state_name() == "蓄势", "third provoke triggers windup", passes, failures)
	await _wait(0.3)
	_check(gulu.state_name() == "蓄势", "windup telegraph lasts before pounce", passes, failures)

	Input.action_press("move_right")
	await _wait(0.9)
	Input.action_release("move_right")
	await _wait(0.6)
	_check(not bool(gulu.get("last_pounce_hit")), "player can dodge the pounce", passes, failures)
	_check(gulu.state_name() == "恢复" or gulu.state_name() == "待机", "pounce ends in recovery", passes, failures)
	await _wait(1.7)
	_check(gulu.state_name() == "待机", "dragon returns to idle after recovery", passes, failures)

	# 墙体遮挡：隔墙挑衅不应生效。
	reset_preview()
	_teleport(Vector3(-6.0, 0.02, -5.5), _yaw_to(GULU_POSITION))
	await _wait(0.2)
	_press_provoke()
	await _wait(0.1)
	_check(gulu.state_name() == "待机", "provoke behind wall is rejected", passes, failures)
	_check(float(gulu.get("agitation")) < 0.01, "blocked provoke adds no agitation", passes, failures)

	# 冷却：同一瞬间连按不应叠两倍 agitation。
	reset_preview()
	_teleport(Vector3(-5.0, 0.02, -3.5), _yaw_to(GULU_POSITION))
	await _wait(0.2)
	_press_provoke()
	_press_provoke()
	await _wait(0.06)
	_check(float(gulu.get("agitation")) <= 0.35, "provoke cooldown blocks rapid repeats", passes, failures)

	reset_preview()
	await get_tree().physics_frame
	_check(player.global_position.distance_to(SPAWN) < 0.2, "reset returns to spawn", passes, failures)
	_check(bool(player.get("use_first_person")), "reset restores first person", passes, failures)
	_check(gulu.state_name() == "待机", "reset restores dragon idle", passes, failures)

	_toggle_debug()
	await _wait(0.25)
	_check(_debug_label.text.length() > 0 and _debug_label.text.contains("奶龙"), "debug panel renders", passes, failures)
	_toggle_debug()

	Input.action_release("move_up")
	Input.action_release("move_right")
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
	await _shot("01_first_person_idle.png")

	_press_provoke()
	await _wait(0.35)
	await _shot("02_notice.png")

	await _wait(0.8)
	_press_provoke()
	await _wait(0.8)
	_press_provoke()
	await _wait(0.3)
	await _shot("03_windup.png")

	print("GULU SHOTS dir=%s" % ProjectSettings.globalize_path(_shot_dir))
	get_tree().quit(0)

func _shot(file_name: String) -> void:
	RenderingServer.force_draw()
	await get_tree().process_frame
	await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	var path := _shot_dir.path_join(file_name)
	var error := image.save_png(path)
	print("SHOT %s %s" % [file_name, "ok" if error == OK else error_string(error)])
