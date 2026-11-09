extends Node3D

## 奶龙星 · 射门试玩（本轮核心玩法）
##
## 一句话：把球形燃料踢进飞船，奶龙会来抢球。
##
## 结构上刻意分成三块，方便以后升级：
##   1. 输入：本文件 `_input` / `_try_kick` —— 只决定“能不能踢、往哪踢”；
##   2. 球的运动：`scripts/energy_ball.gd` —— 减速、反弹、滚动、出界自救；
##   3. 入仓判定：`scripts/collector.gd` —— 固定 AABB，只计一次。
## 以后加高空球/旋转/重力时，只换第 2 块，不同重写输入与任务流程。
##
## 单人原型：玩家不是写死的唯一对象（`actors` 字典 + peer_id），但没有联网代码。

const SOURCE_COMMIT := "42519ff403241bf5ac968edb9ae326c6fdbc74fe"
const SPAWN := Vector3(-11.0, 0.02, 5.0)
const SPAWN_YAW := -PI * 0.5
const BALL_HOME := Vector3(-4.6, 0.0, 1.4)
const DRAGON_HOME := Vector3(10.3, 0.0, 0.0)

## 踢球：范围与角度都留了余量，不要求准星点中球心。
const KICK_RANGE := 2.7
const KICK_MIN_DOT := 0.35      ## 约 ±69.5°，只要求“大致朝向”
const KICK_SPEED := 15.0
const GOAL_TARGET := 1

const GROUND := Color("#4e615e")
const STONE := Color("#8fa29d")
const TRIM := Color("#375967")
const AMBER := Color("#ffb347")
const CYAN := Color("#3fd8ff")

var player: CharacterBody3D
var ball: CharacterBody3D
var dragon: CharacterBody3D
var collector: Node3D
var env_art: Node3D
var blender_test_asset: Node3D
var actors: Dictionary = {}

var loaded_count := 0
var completed := false

var _debug := false
var _help_visible := true
var _hud: CanvasLayer
var _root: Control
var _mode_label: Label
var _objective_label: Label
var _hint_label: Label
var _counter_label: Label
var _pips: Array[ColorRect] = []
var _debug_panel: PanelContainer
var _debug_label: Label
var _crosshair_root: Control
var _prompt_panel: PanelContainer
var _prompt_label: Label
var _banner: PanelContainer
var _banner_label: Label
var _font: SystemFont
var _sfx: Node
var _feedback := ""
var _feedback_timer := 0.0
var _counter_punch := 0.0
var _last_collisions := 0

var _automation := false
var _shot_dir := "user://gulu_shots"

# --- 自动录制（连续截图，后可合成为 GIF/视频）---
var _recording := false
var _record_dir := "user://gulu_record"
var _record_index := 0
var _record_accum := 0.0
var _record_peak_loaded := 0
const RECORD_INTERVAL := 0.125


func _ready() -> void:
	_register_input()
	_build_environment()
	_build_field()
	_build_collector()
	_spawn_player()
	_spawn_ball()
	_build_dragon()
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
	elif args.has("--record"):
		_automation = true
		call_deferred("_run_record")

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
	# 旧玩法的动作如果还存在，清掉，避免两套规则混着跑
	for legacy in ["provoke", "interact"]:
		if InputMap.has_action(legacy):
			InputMap.action_erase_events(legacy)
	# 控制器仍然会读这个动作（鼠标重新捕获），保留一个空映射
	if not InputMap.has_action("capture_mouse"):
		InputMap.add_action("capture_mouse")
	InputMap.action_erase_events("capture_mouse")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("capture_mouse", click)


func _input(event: InputEvent) -> void:
	# 左键：没锁定鼠标时先锁定（这一下不算射门）；锁定后才踢球。
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
			return
		get_viewport().set_input_as_handled()
		_try_kick()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			reset_round()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F3:
			_toggle_debug()
		elif event.keycode == KEY_F1:
			_toggle_help()
		elif event.keycode == KEY_F4:
			_toggle_blender_test()


# ---------------------------------------------------------------- world

func _build_environment() -> void:
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
	env_art = load("res://scripts/nailong_environment.gd").new() as Node3D
	env_art.name = "EnvironmentArt"
	add_child(env_art)


func _build_collector() -> void:
	collector = load("res://scripts/collector.gd").new() as Node3D
	collector.name = "ShipLoadingBay"
	collector.set("target_count", GOAL_TARGET)
	add_child(collector)
	collector.connect("fuel_collected", _on_goal_scored)


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


func _spawn_ball() -> void:
	ball = load("res://scripts/energy_ball.gd").new() as CharacterBody3D
	ball.name = "EnergyBall"
	ball.position = BALL_HOME
	add_child(ball)
	ball.call("setup_goal", collector)
	ball.connect("reached_goal", _on_ball_reached_goal)
	ball.connect("stuck", _on_ball_stuck)


func _build_dragon() -> void:
	dragon = load("res://scripts/milk_dragon.gd").new() as CharacterBody3D
	dragon.name = "MilkDragon"
	dragon.position = DRAGON_HOME
	dragon.set("home", DRAGON_HOME)
	dragon.rotation.y = PI * 0.5
	var visual := _make_dragon_visual()
	visual.name = "Visual"
	dragon.add_child(visual)
	add_child(dragon)
	dragon.call("setup_ball", ball)
	dragon.call("setup_goal", collector)
	dragon.connect("blocked", _on_dragon_blocked)
	dragon.connect("state_changed", _on_dragon_state_changed)


func _make_dragon_visual() -> Node3D:
	return load("res://scripts/milk_dragon_model.gd").new() as Node3D


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


func _on_dragon_state_changed(current: String) -> void:
	if _sfx == null:
		return
	if current == "拦球":
		_sfx.call("play", "block")


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
	panel.custom_minimum_size = Vector2(430, 0)
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
	title.text = "奶龙星 · 射门试玩"
	title.add_theme_font_size_override("font_size", 21)
	title.add_theme_color_override("font_color", Color("#e9f7f3"))
	column.add_child(title)

	_objective_label = Label.new()
	_objective_label.text = "把能源球踢进飞船装货口"
	_objective_label.add_theme_font_size_override("font_size", 14)
	_objective_label.add_theme_color_override("font_color", Color("#ffcf8a"))
	column.add_child(_objective_label)

	# 只保留一句操作提示
	_hint_label = Label.new()
	_hint_label.text = "靠近球，左键踢进装货口。"
	_hint_label.add_theme_font_size_override("font_size", 13)
	_hint_label.add_theme_color_override("font_color", Color("#b9d4cf"))
	column.add_child(_hint_label)

	_mode_label = Label.new()
	_mode_label.position = Vector2(1080, 22)
	_mode_label.size = Vector2(176, 30)
	_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_mode_label.add_theme_font_size_override("font_size", 15)
	_mode_label.add_theme_color_override("font_color", Color("#7dffd4"))
	_root.add_child(_mode_label)

	_counter_label = Label.new()
	_counter_label.position = Vector2(980, 54)
	_counter_label.size = Vector2(276, 30)
	_counter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_counter_label.add_theme_font_size_override("font_size", 19)
	_counter_label.add_theme_color_override("font_color", Color("#ffcf8a"))
	_root.add_child(_counter_label)

	for index in range(GOAL_TARGET):
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
	_prompt_panel.visible = false
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
	_banner_label.text = "燃料已装载\n按 R 再来一局"
	bmargin.add_child(_banner_label)

	_debug_panel = PanelContainer.new()
	_debug_panel.position = Vector2(22, 200)
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

	_counter_label.text = "已装载 0 / %d" % GOAL_TARGET
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
	if _recording:
		_record_accum += delta
		if _record_accum >= RECORD_INTERVAL:
			_record_accum = 0.0
			_record_frame()
	if player == null:
		return

	var first := bool(player.get("use_first_person"))
	_mode_label.text = "第一人称" if first else "第三人称"
	_mode_label.add_theme_color_override("font_color", Color("#7dffd4") if first else Color("#ffcf5c"))
	_crosshair_root.visible = first

	_feedback_timer = maxf(_feedback_timer - delta, 0.0)
	_counter_punch = maxf(0.0, _counter_punch - delta * 3.0)
	_counter_label.add_theme_font_size_override("font_size", 19 + int(round(8.0 * _counter_punch)))

	for index in range(_pips.size()):
		var lit: bool = index < loaded_count
		_pips[index].color = AMBER if lit else Color(0.24, 0.33, 0.34, 0.9)

	_update_prompt()

	if _debug:
		var pos := player.global_position
		var cam := player.get("camera") as Camera3D
		var ball_speed := float(ball.call("speed")) if ball != null else 0.0
		_debug_label.text = "\n".join(PackedStringArray([
			"FPS %d · 位置 %.2f, %.2f, %.2f" % [Engine.get_frames_per_second(), pos.x, pos.y, pos.z],
			"球 %.2f, %.2f, %.2f · 速度 %.2f · %s" % [ball.global_position.x, ball.global_position.y, ball.global_position.z, ball_speed, String(ball.get("mode"))],
			"奶龙 %s" % (dragon.call("debug_text") if dragon else "—"),
			"装货 %d/%d · 镜头高 %.2f · FOV %.0f" % [loaded_count, GOAL_TARGET, cam.global_position.y - pos.y, cam.fov],
		]))


func _update_prompt() -> void:
	if completed:
		_set_prompt("燃料已装载——按 R 再来一局", Color("#ffe0a8"))
		return
	if _feedback_timer > 0.0:
		_set_prompt(_feedback, Color("#ffcf5c"))
		return
	if ball == null:
		return
	var distance := player.global_position.distance_to(ball.global_position)
	if distance <= KICK_RANGE:
		_set_prompt("左键把球踢向装货口", Color("#7dffd4"))
	else:
		_set_prompt("", Color("#8fa6b2"))


func _set_prompt(text: String, color: Color) -> void:
	_prompt_panel.visible = text != ""
	if _prompt_label.text != text:
		_prompt_label.text = text
	_prompt_label.add_theme_color_override("font_color", color)


func _flash(text: String, seconds: float = 1.4) -> void:
	_feedback = text
	_feedback_timer = seconds


# ---------------------------------------------------------------- 踢球

func _try_kick() -> bool:
	if completed or ball == null or player == null:
		return false
	var cam := player.get("camera") as Camera3D
	var forward := -cam.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = -player.global_transform.basis.z
	forward = forward.normalized()

	var to_ball := ball.global_position - player.global_position
	to_ball.y = 0.0
	var distance := to_ball.length()
	if distance > KICK_RANGE:
		_flash("离球太远——走近一点再踢")
		return false
	if distance < 0.001:
		_flash("球就在脚下，先退半步")
		return false
	if forward.dot(to_ball.normalized()) < KICK_MIN_DOT:
		_flash("先面向球再踢")
		return false

	ball.call("kick", forward, KICK_SPEED)
	if _sfx != null:
		_sfx.call("play", "kick")
	_spawn_kick_pulse(ball.global_position)
	return true


## 踢中时脚边的短促视觉反馈（一圈快速扩散的环，不遮挡球）。
func _spawn_kick_pulse(at: Vector3) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.30
	torus.outer_radius = 0.44
	torus.rings = 18
	torus.ring_segments = 6
	ring.mesh = torus
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.75, 0.35, 0.55)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = Color("#ffb347")
	material.emission_energy_multiplier = 1.4
	ring.material_override = material
	ring.position = Vector3(at.x, 0.08, at.z)
	add_child(ring)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(2.4, 1.0, 2.4), 0.35)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.35)
	tween.chain().tween_callback(func() -> void: ring.queue_free())


# ---------------------------------------------------------------- 事件

func _on_ball_reached_goal() -> void:
	if collector == null or ball == null:
		return
	collector.call("consume", ball)


func _on_goal_scored(total: int, target: int) -> void:
	loaded_count = total
	_record_peak_loaded = maxi(_record_peak_loaded, loaded_count)
	_counter_label.text = "已装载 %d / %d" % [loaded_count, target]
	_counter_punch = 1.0
	if _sfx != null:
		_sfx.call("play", "loaded")
	if env_art != null and is_instance_valid(env_art):
		env_art.call("on_loaded", loaded_count)
	_flash("燃料已装载", 1.6)
	if loaded_count >= target and not completed:
		completed = true
		_banner.visible = true


func _on_dragon_blocked(_point: Vector3, _speed: float) -> void:
	if _sfx != null:
		_sfx.call("play", "block")
	_flash("被奶龙拦下来了——换个位置再踢", 1.5)


func _on_ball_stuck(_point: Vector3) -> void:
	# 出界/卡在拿不回来的角落：放回玩家前方的可玩位置，并给一句提示。
	var forward := -player.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	var spot := player.global_position + forward.normalized() * 2.4
	spot.x = clampf(spot.x, -17.0, 17.0)
	spot.z = clampf(spot.z, -12.5, 12.5)
	ball.call("settle", spot)
	_flash("球滚到拿不回来的地方了——已经放回你面前", 2.0)


# ---------------------------------------------------------------- reset / debug

func reset_round() -> void:
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

	if ball != null:
		ball.call("reset_to", BALL_HOME)
	if collector != null:
		collector.call("reset_state")
	if dragon != null:
		dragon.call("reset_to_home")
	loaded_count = 0
	completed = false
	_banner.visible = false
	_counter_label.text = "已装载 0 / %d" % GOAL_TARGET
	_feedback = ""
	_feedback_timer = 0.0
	_last_collisions = int(player.get("contacts"))
	print("GULU reset spawn=%s ball=%s" % [str(SPAWN), str(BALL_HOME)])


func _toggle_debug() -> void:
	_debug = not _debug
	_debug_panel.visible = _debug


## 控制器（station_player.gd）会调用父节点的这个函数来限制相机高度/范围。
func clamp_cave_camera_position(_target: Vector3, desired: Vector3) -> Vector3:
	return Vector3(
		clampf(desired.x, -19.0, 19.0),
		clampf(desired.y, 1.2, 7.5),
		clampf(desired.z, -14.0, 14.0)
	)


func _toggle_help() -> void:
	_help_visible = not _help_visible
	_hint_label.visible = _help_visible


# ---------------------------------------------------------------- automation helpers

func _check(condition: bool, label: String, passes: Array, failures: Array) -> void:
	if condition:
		passes.append(label)
		print("PASS  %s" % label)
	else:
		failures.append(label)
		print("FAIL  %s" % label)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


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


func _aim_at(target: Vector3) -> void:
	var from := player.global_position
	var yaw := atan2(-(target.x - from.x), -(target.z - from.z))
	# 身体和镜头一起转：控制器会让镜头跟着身体朝向回正，只改镜头会被拉回去
	player.rotation.y = yaw
	player.set("_camera_yaw", yaw)
	player.set("_camera_yaw_target", yaw)


func _click_kick() -> void:
	_try_kick()


func _ball_speed() -> float:
	return float(ball.call("speed")) if ball != null else 0.0

# ---------------------------------------------------------------- 自测

func _run_selftest() -> void:
	await _wait(0.8)
	var passes: Array = []
	var failures: Array = []
	print("GULU SELFTEST start source=%s" % SOURCE_COMMIT)

	# --- 控制器未被破坏（与飞船第一人称逐值一致）---
	_check(bool(player.get("use_first_person")), "default first person", passes, failures)
	var cam := player.get("camera") as Camera3D
	var eye_delta := cam.global_position.y - player.global_position.y
	_check(absf(eye_delta - 1.6) < 0.03, "camera eye height 1.6 (%.3f)" % eye_delta, passes, failures)
	_check(absf(cam.fov - 74.0) < 0.1, "camera fov 74 (%.1f)" % cam.fov, passes, failures)
	_check(absf(cam.near - 0.05) < 0.001, "camera near 0.05", passes, failures)

	var start := player.global_position
	Input.action_press("move_up")
	await _wait(0.8)
	Input.action_release("move_up")
	await get_tree().physics_frame
	_check(player.global_position.distance_to(start) > 2.0, "WASD movement still works (%.2f m)" % player.global_position.distance_to(start), passes, failures)

	# --- 出生首屏：球 / 奶龙 / 装货口 同屏 ---
	reset_round()
	await _wait(0.2)
	var view := get_viewport().get_visible_rect().size
	var cam2 := player.get("camera") as Camera3D
	var ball_screen := cam2.unproject_position(ball.global_position)
	var dragon_screen := cam2.unproject_position(dragon.global_position + Vector3.UP * 0.9)
	var bay_screen := cam2.unproject_position(Vector3(13.5, 1.2, 0.0))
	print("GULU screen ball=%s dragon=%s bay=%s view=%s" % [ball_screen, dragon_screen, bay_screen, view])
	_check(ball_screen.x > 0 and ball_screen.x < view.x and ball_screen.y > 0 and ball_screen.y < view.y, "ball visible on entry", passes, failures)
	_check(dragon_screen.x > 0 and dragon_screen.x < view.x and dragon_screen.y > 0 and dragon_screen.y < view.y, "dragon visible on entry", passes, failures)
	_check(bay_screen.x > 0 and bay_screen.x < view.x and bay_screen.y > 0 and bay_screen.y < view.y, "goal visible on entry", passes, failures)

	# --- 旧玩法已移除 ---
	_check(not InputMap.has_action("provoke"), "old provoke action removed", passes, failures)
	_check(_hint_label.text.contains("左键") and not _hint_label.text.contains("挑衅"), "only one kick hint on HUD", passes, failures)

	# --- 远距离不能踢 ---
	reset_round()
	_teleport(BALL_HOME + Vector3(-6.0, 0.02, 0.0), 0.0)
	_aim_at(BALL_HOME + Vector3(6.0, 0.0, 0.0))
	await _wait(0.1)
	var far_kick := _try_kick()
	_check(not far_kick and _ball_speed() < 0.01, "cannot kick from far away", passes, failures)

	# --- 近距离、大致朝向可以踢，方向跟镜头 ---
	_teleport(BALL_HOME + Vector3(-1.2, 0.02, 0.0), 0.0)
	_aim_at(BALL_HOME + Vector3(6.0, 0.0, 0.0))
	await _wait(0.1)
	var near_kick := _try_kick()
	_check(near_kick, "kick works up close", passes, failures)
	var launch := _ball_speed()
	_check(launch > 12.0, "kick gives a fixed strong impulse (%.1f m/s)" % launch, passes, failures)
	_check(ball.velocity.normalized().dot(Vector3.RIGHT) > 0.9, "kick direction follows the camera", passes, failures)

	# --- 减速与停止（往空场方向踢，避开奶龙与墙）---
	reset_round()
	ball.call("settle", Vector3(-6.0, 0.0, -3.0))
	await _wait(0.1)
	ball.call("kick", Vector3(0.0, 0.0, 1.0), 12.0)
	var fast := _ball_speed()
	await _wait(1.0)
	var slowed := _ball_speed()
	_check(slowed < fast * 0.7, "ball decelerates (%.1f -> %.1f)" % [fast, slowed], passes, failures)
	await _wait(3.4)
	_check(_ball_speed() < 0.05, "ball comes to rest", passes, failures)

	# --- 停球后仍能再踢 ---
	_teleport(ball.global_position + Vector3(-1.3, 0.02, 0.0), 0.0)
	_aim_at(ball.global_position + Vector3(6.0, 0.0, 0.0))
	await _wait(0.1)
	_check(_try_kick() and _ball_speed() > 12.0, "resting ball can be kicked again", passes, failures)

	# --- 墙面反弹 ---
	reset_round()
	ball.call("settle", Vector3(14.0, 0.0, 13.2))
	ball.call("kick", Vector3(0.0, 0.0, 1.0), 10.0)
	await _wait(0.9)
	_check(ball.velocity.z < -0.2, "ball bounces off the boundary wall (vz=%.2f)" % ball.velocity.z, passes, failures)

	# --- 奶龙拦球 ---
	reset_round()
	ball.call("settle", Vector3(6.5, 0.0, 0.0))
	dragon.call("reset_to_home")
	await _wait(0.25)
	ball.call("kick", Vector3(1.0, 0.0, 0.0), 14.0)
	var bounced_back := false
	for _probe in range(150):
		if ball.velocity.x < -0.2:
			bounced_back = true
			break
		await _wait(0.02)
	_check(bounced_back, "keeper blocks a straight shot", passes, failures)
	_check(ball.global_position.x < 12.4, "blocked ball never reaches the bay (x=%.2f)" % ball.global_position.x, passes, failures)

	# --- 奶龙不会连击球 ---
	reset_round()
	await _wait(0.8)
	var block_count := [0]
	var on_block := func(_p: Vector3, _s: float) -> void: block_count[0] += 1
	dragon.connect("blocked", on_block)
	ball.call("settle", Vector3(8.6, 0.0, 0.2))
	await _wait(0.05)
	ball.call("kick", Vector3(1.0, 0.0, 0.0), 6.0)
	await _wait(1.6)
	_check(block_count[0] >= 1 and block_count[0] <= 2, "keeper blocks but does not machine-gun (%d hits)" % block_count[0], passes, failures)
	dragon.disconnect("blocked", on_block)

	# --- 球不会被身体压死 ---
	await _wait(0.6)
	var gap := ball.global_position.distance_to(dragon.global_position)
	_check(gap > 0.75 or _ball_speed() > 0.8, "ball is not trapped under the keeper (gap %.2f)" % gap, passes, failures)

	# --- 斜射：能绕过守门打进 ---
	reset_round()
	dragon.global_position = Vector3(10.3, 0.0, -2.4)
	ball.call("settle", Vector3(11.2, 0.0, 1.7))
	await _wait(0.15)
	var before_goal := loaded_count
	ball.call("kick", Vector3(1.0, 0.0, -0.2), 16.0)
	var scored := false
	for _probe in range(200):
		if loaded_count > before_goal:
			scored = true
			break
		await _wait(0.02)
	_check(scored, "an angled shot into the open side scores (loaded=%d)" % loaded_count, passes, failures)

	# --- 门框外侧不算 ---
	_check(not bool(collector.call("contains_point", Vector3(13.2, 0.4, 3.4))), "outside the frame does not count", passes, failures)
	var before_total := loaded_count
	collector.call("consume", ball)
	await _wait(0.06)
	_check(loaded_count == before_total, "the same ball cannot score twice", passes, failures)

	# --- 出界/卡球自救 ---
	reset_round()
	ball.call("settle", Vector3(13.2, 0.0, 3.3))
	await _wait(5.2)
	_check(ball.global_position.x < 11.4 or absf(ball.global_position.z) < 2.5, "stuck ball is put back in play", passes, failures)

	# --- 完成与本局重开 ---
	reset_round()
	dragon.global_position = Vector3(10.3, 0.0, -2.4)
	ball.call("settle", Vector3(11.4, 0.0, 1.6))
	await _wait(0.1)
	ball.call("kick", Vector3(1.0, 0.0, -0.1), 16.0)
	for _probe in range(200):
		if completed:
			break
		await _wait(0.02)
	_check(completed and _banner.visible, "goal completes the round", passes, failures)
	reset_round()
	await _wait(0.1)
	_check(loaded_count == 0 and not completed and ball.global_position.distance_to(BALL_HOME) < 0.8, "R resets ball and score", passes, failures)
	_check(dragon.global_position.distance_to(DRAGON_HOME) < 0.6, "R resets the keeper", passes, failures)
	reset_round()
	reset_round()
	_check(loaded_count == 0 and not completed, "repeated reset is safe", passes, failures)

	# --- 资源与模型 ---
	var sfx_players := _sfx.get("_players") as Dictionary
	_check(sfx_players != null and sfx_players.size() == 3, "kick/block/loaded sfx imported (%d/3)" % (sfx_players.size() if sfx_players != null else 0), passes, failures)
	var visual := dragon.get("visual") as Node3D
	var skeletons := visual.find_children("*", "Skeleton3D", true, false)
	_check(skeletons.size() > 0, "dragon skeleton present", passes, failures)
	var body := visual.get("_body") as Node3D
	_check(body != null and absf(body.position.y) < 0.05 and absf(body.scale.y - 1.0) < 0.02, "model keeps natural scale and stays grounded", passes, failures)
	_check(blender_test_asset != null and not blender_test_asset.visible, "Blender test asset hidden by default", passes, failures)

	_toggle_debug()
	await _wait(0.1)
	_check(_debug_panel.visible, "debug panel renders", passes, failures)
	_toggle_debug()
	await _wait(0.1)

	print("GULU SELFTEST SUMMARY passes=%d failures=%d" % [passes.size(), failures.size()])
	await _wait(0.2)
	get_tree().quit(0 if failures.is_empty() else 1)

# ---------------------------------------------------------------- 截图

func _run_shots() -> void:
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	await _wait(1.0)

	# 01 出生点：球 / 奶龙 / 装货口同屏
	reset_round()
	await _wait(0.6)
	await _shot("01_spawn_ball_dragon_goal.png")

	# 02 走近球：能看清球面与外壳（退开 2.3 m，球和球门都在画面里）
	_teleport(BALL_HOME + Vector3(-2.3, 0.02, 0.7), 0.0)
	_aim_at(Vector3(2.0, 0.7, -0.2))
	await _wait(0.4)
	await _shot("02_near_ball.png")

	# 03 刚踢出：球在滚动、脚边有冲击环
	_aim_at(BALL_HOME + Vector3(8.0, 0.0, 0.0))
	await _wait(0.15)
	_try_kick()
	await _wait(0.12)
	await _shot("03_kick_moment.png")

	# 04 被奶龙拦下
	for _probe in range(150):
		if ball.velocity.x < -0.2:
			break
		await _wait(0.02)
	_place_player(Vector3(6.6, 0.02, 3.0), dragon.global_position)
	await _wait(0.1)
	await _shot("04_keeper_block.png")

	# 05 斜射入门 + 装载横幅
	reset_round()
	dragon.global_position = Vector3(10.3, 0.0, -2.4)
	ball.call("settle", Vector3(11.2, 0.0, 1.7))
	_place_player(Vector3(9.4, 0.02, 4.4), Vector3(13.5, 1.0, 0.6))
	await _wait(0.2)
	ball.call("kick", Vector3(1.0, 0.0, -0.2), 16.0)
	for _probe in range(200):
		if completed:
			break
		await _wait(0.02)
	await _wait(0.2)
	await _shot("05_goal_loaded.png")

	# 06 场地全景
	_place_player(Vector3(-6.5, 0.02, 8.4), Vector3(9.0, 1.0, -1.0))
	await _wait(0.5)
	await _shot("06_yard_wide.png")

	# 07 奶龙近景：迈步/拦球姿势
	reset_round()
	ball.call("settle", Vector3(7.4, 0.0, 0.9))
	_place_player(Vector3(8.2, 0.02, 3.4), dragon.global_position + Vector3.UP * 0.6)
	await _wait(1.2)
	await _shot("07_keeper_closeup.png")

	print("GULU SHOTS dir=%s" % ProjectSettings.globalize_path(_shot_dir))
	get_tree().quit(0)


func _shot(file_name: String) -> void:
	RenderingServer.force_draw()
	await get_tree().process_frame
	await get_tree().process_frame
	if player != null and dragon != null and ball != null:
		var cam := player.get("camera") as Camera3D
		var head := cam.unproject_position(dragon.global_position + Vector3.UP * 0.9)
		var ball_screen := cam.unproject_position(ball.global_position)
		var view := get_viewport().get_visible_rect().size
		var on_screen := head.x > 0.0 and head.x < view.x and head.y > 0.0 and head.y < view.y
		print("SHOTMETA %s dragon_screen=%s ball_screen=%s on_screen=%s loaded=%d state=%s ball_speed=%.1f" % [
			file_name, head, ball_screen, on_screen, loaded_count, dragon.call("state_name"), _ball_speed()])
	var image := get_viewport().get_texture().get_image()
	var path := _shot_dir.path_join(file_name)
	var error := image.save_png(path)
	print("SHOT %s %s" % [file_name, "ok" if error == OK else error_string(error)])


# ---------------------------------------------------------------- 录制

func _record_frame() -> void:
	var image := get_viewport().get_texture().get_image()
	if image == null:
		return
	image.resize(640, 400, Image.INTERPOLATE_BILINEAR)
	image.save_png(_record_dir.path_join("f%04d.png" % _record_index))
	_record_index += 1


func _walk_to(target: Vector3, seconds: float) -> void:
	var delta := target - player.global_position
	delta.y = 0.0
	if delta.length() > 0.2:
		var yaw := atan2(-delta.x, -delta.z)
		player.rotation.y = yaw
		player.set("_camera_yaw", yaw)
		player.set("_camera_yaw_target", yaw)
	Input.action_press("move_up")
	await _wait(seconds)
	Input.action_release("move_up")
	await _wait(0.08)


## 走到“球边某一点”再踢；走不准就精确站位（录制专用）。
func _kick_from(offset: Vector3, aim: Vector3) -> bool:
	var stand := ball.global_position + offset
	var distance := player.global_position.distance_to(stand)
	await _walk_to(stand, clampf(distance / 4.6, 0.2, 2.4))
	if player.global_position.distance_to(ball.global_position) > KICK_RANGE - 0.3:
		_teleport(Vector3(stand.x, 0.02, stand.z), 0.0)
	_aim_at(aim)
	await _wait(0.3)
	var ok := _try_kick()
	print("GULU RECORD kick_from ok=%s dir=%s yaw=%.2f" % [str(ok), str(ball.velocity), float(player.get("_camera_yaw"))])
	return ok


## 自动跑一遍：踢球 → 被拦 → 换位置 → 进球（脚本操作，不是真人试玩）。
func _run_record() -> void:
	DirAccess.make_dir_recursive_absolute(_record_dir)
	for name in DirAccess.get_files_at(_record_dir):
		if name.ends_with(".png"):
			DirAccess.remove_absolute(_record_dir.path_join(name))
	_record_index = 0
	await _wait(1.0)
	_recording = true

	# 1) 开场：球 / 奶龙 / 装货口
	reset_round()
	await _wait(1.4)

	# 2) 走到球边
	var kicked1: bool = await _kick_from(Vector3(-1.6, 0.0, 0.4), BALL_HOME + Vector3(8.0, 0.0, 0.0))
	print("GULU RECORD kick1=%s ball=%s" % [str(kicked1), str(ball.global_position)])

	# 3) 第一脚：被守门拦下
	await _wait(0.4)
	for _probe in range(150):
		if ball.velocity.x < -0.2:
			break
		await _wait(0.02)
	await _wait(0.6)

	# 4) 换到侧面，打远角
	var kicked2: bool = await _kick_from(Vector3(-1.7, 0.0, 2.4), Vector3(13.7, 0.5, -2.0))
	print("GULU RECORD kick2=%s ball=%s" % [str(kicked2), str(ball.global_position)])

	# 5) 等进球
	var record_scored := false
	var max_x := -999.0
	for _probe in range(200):
		max_x = maxf(max_x, ball.global_position.x)
		if completed:
			record_scored = true
			break
		await _wait(0.02)
	print("GULU RECORD after_shot ball=%s mode=%s max_x=%.2f keeper=(%.2f, %.2f)" % [str(ball.global_position), String(ball.get("mode")), max_x, dragon.global_position.x, dragon.global_position.z])
	await _wait(1.2)

	# 6) 再来一局
	reset_round()
	await _wait(1.0)

	_recording = false
	print("GULU RECORD dir=%s frames=%d peak_loaded=%d scored=%s" % [
		ProjectSettings.globalize_path(_record_dir), _record_index, _record_peak_loaded, str(record_scored)])
	get_tree().quit(0)
