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
const SPAWN := Vector3(1.0, 0.02, 0.0)
const SPAWN_YAW := -PI * 0.5
const BALL_HOME := Vector3(2.68, 0.0, 0.0)
const DRAGON_HOME := Vector3(10.3, 0.0, 0.0)

## 踢球：必须足够近、方向合理、且中间无遮挡（没有远程踢球）。
const KICK_RANGE := 1.9
const KICK_MIN_DOT := 0.35      ## 约 ±69.5°，只要求“大致朝向”
## 单击固定力度：冲量 16 N·s ≈ 1.2 kg 的球获得 13.3 m/s
const KICK_IMPULSE := 16.0
## 蓄力：按住左键 0.10–1.10 s，力度线性 0.55–1.55 倍。
const CHARGE_MIN_TIME := 0.10
const CHARGE_MAX_TIME := 1.10
const CHARGE_MIN_POWER := 1.0
const CHARGE_MAX_POWER := 1.5
## 街机模式：90 秒内尽可能多进球，每球 +5 秒。
const ROUND_SECONDS := 90.0
const TIME_BONUS_PER_GOAL := 4.0
const SCORE_PER_GOAL := 100
const COMBO_WINDOW := 10.0
const COMBO_MAX := 9
## 确定性模式（--selftest / --physics / --motion*）保持“进一球就结束”。
const GOAL_TARGET := 1
const ARCADE_TARGET := 999

const GROUND := Color("#4e615e")
const STONE := Color("#8fa29d")
const TRIM := Color("#375967")
const AMBER := Color("#ffb347")
const CYAN := Color("#3fd8ff")

var player: CharacterBody3D
var ball: RigidBody3D
var dragon: CharacterBody3D
var collector: Node3D
var env_art: Node3D
var blender_test_asset: Node3D
var actors: Dictionary = {}

var loaded_count := 0
var completed := false

## --- 街机模式状态 ---
var goal_target := GOAL_TARGET
var arcade := false
var round_time_left := ROUND_SECONDS
var score := 0
var combo := 1
var best_score := 0
var goals_this_round := 0
var best_combo_this_round := 1
var _combo_timer := 0.0
var _respawn_timer := -1.0

# ART-SYNC-002：高低差射门。站在北侧货台 / 南侧坑底踢出的球，进球得分 ×1.5。
var _kick_elev_bonus := false
var _zone_hint := 0
var _charging := false
var _charge := 0.0
## --- 侧风（只在真实游玩时开）---
var wind_enabled := false
var _wind_next := 26.0
var _wind_left := 0.0
var _wind_dir := 1.0
var _wind_force := 0.0
var _last_beep_second := -1
var _wind_label: Label
## 表现层：标题屏 / 开场倒计时 / 浮字 / 结算
var _presentation: CanvasLayer
var _round_active := true
## 局内控制：暂停 / 静音（2026-11-23 第七轮）
var _paused := false
var _muted := false
## 本局统计（结算面板用）
var shots_this_round := 0
var saves_this_round := 0
## 奶龙等级：每 2 球 +1，HUD 显示，难度曲线与它同步
var dragon_level := 1
## 蓄力条（准星下方，只在按住左键时出现）
var _charge_track: ColorRect
var _charge_fill: ColorRect
var _dragon_defaults := {}
const RECORD_FILE := "user://gulu_record.cfg"

var _debug := false
var _help_visible := true
var _hud: CanvasLayer
var _root: Control
var _mode_label: Label
var _objective_label: Label
var _hint_label: Label
var _counter_label: Label
var _arcade_label: Label
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
var _record_peak_loaded := 0
const RECORD_INTERVAL := 0.125


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	# 确定性模式保持旧规则（进一球即结束），其余都是 90 秒街机模式。
	var deterministic := args.has("--selftest") or args.has("--physics")
	for arg in args:
		if arg.begins_with("--motion"):
			deterministic = true
	arcade = not deterministic
	wind_enabled = arcade and args.has("--wind")
	goal_target = GOAL_TARGET if deterministic else ARCADE_TARGET
	_load_best()

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

	if args.has("--selftest"):
		_automation = true
		call_deferred("_run_selftest")
	elif args.has("--shots"):
		_automation = true
		call_deferred("_run_shots")
	elif args.has("--record"):
		_automation = true
		call_deferred("_run_record")
	elif args.has("--perf"):
		_automation = true
		call_deferred("_run_perf")
	elif args.has("--motion"):
		_automation = true
		call_deferred("_run_motion")
	elif args.has("--motion-track"):
		_automation = true
		call_deferred("_run_motion_track")
	elif args.has("--motion-save"):
		_automation = true
		call_deferred("_run_motion_save")
	elif args.has("--motion-miss"):
		_automation = true
		call_deferred("_run_motion_miss")
	elif args.has("--motion-goal"):
		_automation = true
		call_deferred("_run_motion_goal")
	elif args.has("--motion-combo"):
		_automation = true
		call_deferred("_run_motion_combo")
	elif args.has("--physics"):
		_automation = true
		call_deferred("_run_physics")
	elif args.has("--arcade-test"):
		_automation = true
		call_deferred("_run_arcade_test")
	elif args.has("--wind-test"):
		_automation = true
		call_deferred("_run_wind_test")
	elif args.has("--ui-shots"):
		_automation = true
		call_deferred("_run_ui_shots")
	elif args.has("--art-shots"):
		_automation = true
		call_deferred("_run_art_shots")
	elif args.has("--flow-test"):
		_automation = true
		call_deferred("_run_flow_test")
	elif args.has("--dragon-test"):
		_automation = true
		call_deferred("_run_dragon_test")
	elif args.has("--wind-goal"):
		_automation = true
		call_deferred("_run_wind_goal_test")
	elif args.has("--pause-test"):
		_automation = true
		call_deferred("_run_pause_test")

	_build_presentation()
	set_process(true)


# ---------------------------------------------------------------- input

func _build_presentation() -> void:
	_presentation = load("res://scripts/gulu_presentation.gd").new() as CanvasLayer
	if _presentation == null:
		return
	add_child(_presentation)
	_presentation.call("setup", _font)
	_presentation.call("set_mute_state", _muted)
	_presentation.connect("start_requested", _on_start_requested)
	_presentation.connect("countdown_finished", _on_countdown_finished)
	_presentation.connect("resume_requested", _on_resume_requested)
	_presentation.connect("restart_requested", _on_restart_requested)
	_presentation.connect("mute_toggled", _on_mute_toggled)
	if _automation:
		# 自动化（自测/截图/录像）直接开局，不打包场屏与倒计时，保证确定性。
		_round_active = true
		return
	_round_active = false
	_set_play_enabled(false)
	_presentation.call("show_title", best_score)


func _on_start_requested() -> void:
	if _round_active:
		return
	reset_round()
	_presentation.call("hide_title")
	_presentation.call("play_countdown")


func _on_countdown_finished() -> void:
	_round_active = true
	_set_play_enabled(true)


# ---------------------------------------------------------------- 暂停 / 静音

## 打开暂停：冻结整棵树（计时、物理、AI 一起停），释放鼠标给按钮。
func _open_pause() -> void:
	if _paused or not _round_active or completed:
		return
	_paused = true
	_charging = false
	_charge = 0.0
	if _charge_track != null:
		_charge_track.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	if _presentation != null:
		_presentation.call("show_pause", _muted, shots_this_round > 0 or score > 0)


func _close_pause(recapture: bool = true) -> void:
	if not _paused:
		return
	_paused = false
	get_tree().paused = false
	if _presentation != null:
		_presentation.call("hide_pause")
	if recapture and _round_active and not completed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_resume_requested() -> void:
	_close_pause()


func _on_restart_requested() -> void:
	_close_pause(false)
	reset_round()


func _on_mute_toggled() -> void:
	_set_muted(not _muted)


func _set_muted(value: bool) -> void:
	_muted = value
	if _sfx != null:
		_sfx.call("set_muted", value)
	if _presentation != null:
		_presentation.call("set_mute_state", value)
	_save_best()
	if not _paused:
		_flash("音效已关闭" if value else "音效已开启", 1.1)


func _set_play_enabled(enabled: bool) -> void:
	if player == null:
		return
	player.set_process(enabled)
	player.set_physics_process(enabled)
	player.set_process_input(enabled)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if enabled else Input.MOUSE_MODE_VISIBLE

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
	if completed and arcade:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
			_on_restart_requested()
			get_viewport().set_input_as_handled()
		return
	# 标题屏 / 倒计时阶段：不处理踢球，把输入留给开场 UI。
	if not _round_active:
		if event is InputEventKey and event.pressed and not event.echo \
				and (event.keycode == KEY_ENTER or event.keycode == KEY_SPACE):
			_on_start_requested()
		return
	# 左键：没锁定鼠标时先锁定（这一下不算射门）；锁定后按住蓄力、松手踢出。
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				get_viewport().set_input_as_handled()
				return
			_charging = true
			_charge = 0.0
			get_viewport().set_input_as_handled()
			return
		if _charging:
			_charging = false
			_try_kick(_charge_power())
			get_viewport().set_input_as_handled()
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
		elif event.keycode == KEY_P:
			_open_pause()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_M:
			_set_muted(not _muted)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			# 鼠标已经释放时，Esc 不再“切回锁定”，而是打开暂停菜单。
			_open_pause()
			get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- world

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("#2c5a76")
	sky_material.sky_horizon_color = Color("#b4d2d6")
	sky_material.sky_curve = 0.22
	sky_material.ground_bottom_color = Color("#6f7f78")
	sky_material.ground_horizon_color = Color("#9db1aa")
	sky_material.sun_angle_max = 2.5
	sky_material.sun_curve = 0.06
	var sky := Sky.new()
	sky.sky_material = sky_material
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#e6f0f2")
	env.ambient_light_energy = 0.24
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color("#c2d2d0")
	env.fog_density = 0.0045
	env.fog_sky_affect = 0.12
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	# 备注：共振星的 "AgX" 是烘焙进静态贴图的显示 LUT（static_surface 走 unshaded），
	# 不是运行时 tonemap；这里保持 ACES 基线与 11-23 画面一致，不跟风切换。
	env.tonemap_exposure = 1.0

	# --- ART-SYNC-001：接触面压暗改由 shader AO + 贴地贴片负责 ---
	# gl_compatibility 不支持 SSAO/SSIL/SDFGI（这里原来的开关是空转的）。
	# 参考共振星的做法：岩面在片元里做接触遮蔽，道具用径向贴片。
	env.ssao_enabled = false
	# 辉光只抬自发光（燃料罐/球/晶簇/门带），阈值高于 1.0 以免整体发糊。
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_strength = 1.0
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.05
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	# 轻微提对比/饱和，抵消 ACES 的灰。
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.10
	env.adjustment_brightness = 1.01
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -34.0, 0.0)
	sun.light_color = Color("#fff0d2")
	sun.light_energy = 0.42
	sun.light_specular = 0.15
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	sun.shadow_enabled = true
	add_child(sun)

	# 冷色轮廓光：把奶龙/门框从背景里剥出来，不参与主光造型。
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(28.0, 148.0, 0.0)
	rim.light_color = Color("#8fdbe8")
	rim.light_energy = 0.18
	rim.light_specular = 0.0
	rim.shadow_enabled = false
	add_child(rim)

	var fill := OmniLight3D.new()
	fill.position = Vector3(4.0, 7.0, 0.0)
	fill.omni_range = 22.0
	fill.light_color = Color("#cfe9e4")
	fill.light_energy = 0.15
	add_child(fill)

	# 场地顶光：只把地面/球/奶龙提亮，不打船体正立面（避免大面积过曝）。
	var yard_fill := SpotLight3D.new()
	yard_fill.position = Vector3(0.0, 12.0, 0.0)
	yard_fill.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	yard_fill.light_color = Color("#dfeef0")
	yard_fill.light_energy = 1.2
	yard_fill.spot_range = 45.0
	yard_fill.spot_angle = 80.0
	yard_fill.spot_attenuation = 1.2
	yard_fill.shadow_enabled = false
	add_child(yard_fill)

	# 掠射光（graze）：低角度暖光扫过地面颗粒与碎石，让三级尺度细节在画面上
	# 读得出来（参考共振星的 graze 灯位做法）；不投影、不抬整体曝光。
	var graze := SpotLight3D.new()
	graze.position = Vector3(-16.0, 2.4, -9.0)
	graze.rotation_degrees = Vector3(-8.0, 118.0, 0.0)
	graze.light_color = Color("#ffd9a8")
	graze.light_energy = 0.55
	graze.spot_range = 30.0
	graze.spot_angle = 52.0
	graze.spot_attenuation = 1.1
	graze.shadow_enabled = false
	add_child(graze)


func _build_field() -> void:
	env_art = load("res://scripts/nailong_environment.gd").new() as Node3D
	env_art.name = "EnvironmentArt"
	add_child(env_art)


func _build_collector() -> void:
	collector = load("res://scripts/collector.gd").new() as Node3D
	collector.name = "ShipLoadingBay"
	collector.set("target_count", goal_target)
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
	ball = load("res://scripts/energy_ball.gd").new() as RigidBody3D
	ball.name = "EnergyBall"
	ball.position = BALL_HOME
	add_child(ball)
	collector.call("watch_ball", ball)
	ball.connect("out_of_bounds", _on_ball_out_of_bounds)
	ball.body_entered.connect(func(body: Node) -> void:
		if _sfx != null and body.is_in_group("goal_metal") and _ball_speed() > 1.0:
			_sfx.call("play", "metal"))


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
	dragon.call("setup_player", player)
	dragon.connect("blocked", _on_dragon_blocked)
	dragon.connect("state_changed", _on_dragon_state_changed)
	dragon.connect("save_made", func() -> void: print("DRAGON EVENT save_made"))
	dragon.connect("intercept_missed", func() -> void: print("DRAGON EVENT intercept_missed"))
	dragon.connect("goal_conceded", func() -> void: print("DRAGON EVENT goal_conceded"))
	# 街机模式难度递增的基准值（reset_round 用）。
	_dragon_defaults = {
		"walk_speed": dragon.get("walk_speed"),
		"charge_speed": dragon.get("charge_speed"),
		"intercept_cooldown": dragon.get("intercept_cooldown"),
		"react_delay": dragon.get("react_delay"),
	}


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
	_sfx.call("set_muted", _muted)


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

	if arcade:
		title.text = "奶龙星 · 90 秒装卸挑战"
		_objective_label.text = "90 秒内尽可能多进球 · 每球 +4 秒 · 被拦下连击清零"
		_hint_label.text = "左键按住蓄力，松手射门 · R 重开"

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

	# 街机模式：顶部中央的计时 / 得分 / 连击
	var arcade_panel := PanelContainer.new()
	arcade_panel.position = Vector2(452, 18)
	arcade_panel.custom_minimum_size = Vector2(376, 54)
	arcade_panel.add_theme_stylebox_override("panel", _panel_style(0.74))
	_root.add_child(arcade_panel)
	var amargin := MarginContainer.new()
	amargin.add_theme_constant_override("margin_left", 14)
	amargin.add_theme_constant_override("margin_right", 14)
	amargin.add_theme_constant_override("margin_top", 8)
	amargin.add_theme_constant_override("margin_bottom", 8)
	arcade_panel.add_child(amargin)
	_arcade_label = Label.new()
	_arcade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_arcade_label.add_theme_font_size_override("font_size", 22)
	_arcade_label.add_theme_color_override("font_color", Color("#eaf7f4"))
	_arcade_label.text = "01:30　　0 分"
	amargin.add_child(_arcade_label)

	# 侧风提示（只在有风时显示）
	_wind_label = Label.new()
	_wind_label.position = Vector2(452, 76)
	_wind_label.size = Vector2(376, 26)
	_wind_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wind_label.add_theme_font_size_override("font_size", 17)
	_wind_label.add_theme_color_override("font_color", Color("#ffd479"))
	_wind_label.visible = false
	_root.add_child(_wind_label)

	# 蓄力条：准星下沿，只在蓄力时显示
	_charge_track = ColorRect.new()
	_charge_track.position = Vector2(560, 448)
	_charge_track.size = Vector2(160, 8)
	_charge_track.color = Color(0.06, 0.09, 0.10, 0.72)
	_charge_track.visible = false
	_root.add_child(_charge_track)
	_charge_fill = ColorRect.new()
	_charge_fill.position = Vector2(1, 1)
	_charge_fill.size = Vector2(0, 6)
	_charge_fill.color = Color("#7dffd4")
	_charge_track.add_child(_charge_fill)

	for index in range(GOAL_TARGET):
		var pip := ColorRect.new()
		pip.position = Vector2(1124 + index * 44, 90)
		pip.size = Vector2(34, 10)
		pip.color = Color(0.24, 0.33, 0.34, 0.9)
		pip.visible = not arcade
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

	_counter_label.text = ("已装载 0 / %d" % goal_target) if not arcade else "已进 0 球"
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
	_counter_punch = maxf(0.0, _counter_punch - delta * 3.0)
	_counter_label.add_theme_font_size_override("font_size", 19 + int(round(8.0 * _counter_punch)))

	for index in range(_pips.size()):
		var lit: bool = index < loaded_count
		_pips[index].color = AMBER if lit else Color(0.24, 0.33, 0.34, 0.9)

	_update_arcade(delta)
	_update_charge_bar()
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


func _update_arcade(delta: float) -> void:
	if _charging:
		_charge = minf(_charge + delta, CHARGE_MAX_TIME)
	# ART-SYNC-002：走到高低差区域时给一次提示（进入/退出一区只提示一次）
	if arcade and _round_active and player != null:
		var zone := 0
		if player.global_position.y > 0.8:
			zone = 1
		elif player.global_position.y < -0.6:
			zone = 2
		if zone != _zone_hint:
			_zone_hint = zone
			if zone == 1:
				_flash("北侧货台 · 从这里射门得分 ×1.5", 1.8)
			elif zone == 2:
				_flash("下沉维修坑 · 从这里射门得分 ×1.5", 1.8)
	if _respawn_timer > 0.0:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_respawn_ball()
	if not arcade:
		return
	if not _round_active:
		return
	if not completed:
		round_time_left = maxf(round_time_left - delta, 0.0)
		if _combo_timer > 0.0:
			_combo_timer = maxf(_combo_timer - delta, 0.0)
			if _combo_timer <= 0.0 and combo > 1:
				combo = 1
		_update_wind(delta)
		_update_countdown_sfx()
		if round_time_left <= 0.0:
			_end_round()
	_update_arcade_label()


func _update_charge_bar() -> void:
	if _charge_track == null:
		return
	var near := ball != null and player != null \
		and player.global_position.distance_to(ball.global_position) <= KICK_RANGE
	var visible := _charging and near and not completed
	_charge_track.visible = visible
	if not visible:
		return
	var t := clampf((_charge - CHARGE_MIN_TIME) / (CHARGE_MAX_TIME - CHARGE_MIN_TIME), 0.0, 1.0)
	_charge_fill.size = Vector2(158.0 * t, 6.0)
	_charge_fill.color = Color("#7dffd4").lerp(Color("#ffb347"), t)


func _update_wind(delta: float) -> void:
	if _wind_left > 0.0:
		_wind_left = maxf(_wind_left - delta, 0.0)
		if _wind_left <= 0.0:
			_clear_wind()
			_flash("侧风停了", 1.2)
			return
		if ball != null:
			ball.set("wind", Vector3(0.0, 0.0, _wind_dir * _wind_force))
		_update_wind_label()
		return
	if not wind_enabled:
		return
	_wind_next -= delta
	if _wind_next <= 0.0:
		_start_gust()


func _start_gust(strength: float = -1.0) -> void:
	_wind_dir = 1.0 if randf() < 0.5 else -1.0
	_wind_force = strength if strength > 0.0 else randf_range(2.0, 3.0)
	_wind_left = 5.0
	_wind_next = randf_range(25.0, 35.0)
	if ball != null:
		ball.set("sleeping", false)
		ball.set("wind", Vector3(0.0, 0.0, _wind_dir * _wind_force))
	_flash("侧风来了！球会被吹向%s" % ("右" if _wind_dir > 0.0 else "左"), 1.8)
	if _sfx != null:
		_sfx.call("play_pitched", "block", 0.72)
	_update_wind_label()


func _clear_wind() -> void:
	_wind_left = 0.0
	if ball != null:
		ball.set("wind", Vector3.ZERO)
	if _wind_label != null:
		_wind_label.visible = false


func _update_wind_label() -> void:
	if _wind_label == null:
		return
	_wind_label.visible = _wind_left > 0.0
	if not _wind_label.visible:
		return
	var arrow := "→→" if _wind_dir > 0.0 else "←←"
	_wind_label.text = "侧风 %s　%.1f" % [arrow, _wind_force]


func _update_countdown_sfx() -> void:
	var sec := int(ceil(round_time_left))
	if sec <= 0 or sec > 10 or sec == _last_beep_second:
		return
	_last_beep_second = sec
	if _sfx != null:
		_sfx.call("play_pitched", "block", 1.0 + 0.045 * float(10 - sec))


func _update_arcade_label() -> void:
	if _arcade_label == null:
		return
	_arcade_label.visible = arcade
	if not arcade:
		return
	var total := int(ceil(round_time_left))
	var text := "%02d:%02d　　%d 分" % [total / 60, total % 60, score]
	if combo > 1:
		text += "　　x%d" % combo
	text += "　　Lv.%d" % dragon_level
	_arcade_label.text = text
	var low := round_time_left <= 10.0
	if combo >= 5 and not low:
		_arcade_label.add_theme_color_override("font_color", Color("#ffd479"))
	else:
		_arcade_label.add_theme_color_override("font_color",
			Color("#ff7d61") if low else Color("#eaf7f4"))


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
		if _charging:
			var pct := int(round(100.0 * clampf((_charge - CHARGE_MIN_TIME) / (CHARGE_MAX_TIME - CHARGE_MIN_TIME), 0.0, 1.0)))
			_set_prompt("蓄力 %d%%　松手踢出" % pct, Color("#ffd479"))
		else:
			_set_prompt("左键按住蓄力，松手射门", Color("#7dffd4"))
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

func _try_kick(power: float = 1.0) -> bool:
	if completed or not _round_active or ball == null or player == null:
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
	# 玩家与球之间不能有东西（墙/门框/奶龙都算遮挡）
	if not _has_kick_line(distance):
		_flash("中间被挡住了，换个位置再踢")
		return false

	shots_this_round += 1
	ball.call("kick", forward, KICK_IMPULSE * power)
	# 高低差：货台（y>0.8）/ 坑底（y<-0.6）射门算“高台/坑底射门”，进球 ×1.5
	_kick_elev_bonus = player.global_position.y > 0.8 or player.global_position.y < -0.6
	if _sfx != null:
		_sfx.call("play", "kick")
	_spawn_kick_pulse(ball.global_position)
	if _kick_elev_bonus and arcade:
		_flash("%s射门 · 进球得分 ×1.5" % ("高台" if player.global_position.y > 0.0 else "坑底"), 1.2)
	elif power > 1.25:
		_flash("全力抽射！", 0.9)
	elif power < 0.85:
		_flash("轻推", 0.7)
	return true


## 蓄力时长 → 力度：点击仍是 1.0，按住最多 1.6 倍。
func _charge_power() -> float:
	if _charge <= CHARGE_MIN_TIME:
		return CHARGE_MIN_POWER
	var t := clampf((_charge - CHARGE_MIN_TIME) / (CHARGE_MAX_TIME - CHARGE_MIN_TIME), 0.0, 1.0)
	return lerpf(CHARGE_MIN_POWER, CHARGE_MAX_POWER, t)


## 踢中时脚边的短促视觉反馈（一圈快速扩散的环，不遮挡球）。
func _has_kick_line(distance: float) -> bool:
	var space := get_world_3d().direct_space_state
	var from := player.global_position + Vector3.UP * 0.85
	var to := ball.global_position + Vector3.UP * 0.1
	var query := PhysicsRayQueryParameters3D.create(from, to, 2 | 16)
	query.exclude = [player.get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return true
	# 起点到球的距离确实很短时，射线可能又打回脚下，容错 0.15 m
	return (hit["position"] as Vector3).distance_to(to) < 0.15


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

func _on_goal_scored(total: int, target: int) -> void:
	loaded_count = total
	_record_peak_loaded = maxi(_record_peak_loaded, loaded_count)
	_counter_punch = 1.0
	if _sfx != null:
		_sfx.call("play_pitched", "loaded", 0.95 + 0.06 * float(combo))
	if env_art != null and is_instance_valid(env_art):
		env_art.call("on_loaded", loaded_count)

	if arcade:
		goals_this_round += 1
		var points := SCORE_PER_GOAL * combo
		if _kick_elev_bonus:
			points = int(round(float(points) * 1.5))
		score += points
		round_time_left = minf(round_time_left + TIME_BONUS_PER_GOAL, ROUND_SECONDS + 30.0)
		combo = mini(combo + 1, COMBO_MAX)
		best_combo_this_round = maxi(best_combo_this_round, combo)
		_combo_timer = COMBO_WINDOW
		_counter_label.text = "已进 %d 球" % loaded_count
		var next_level := 1 + int(goals_this_round / 2)
		var level_note := ""
		if next_level > dragon_level:
			level_note = "　奶龙 Lv.%d" % next_level
		_raise_difficulty()
		_flash("+%d　连击 x%d　+%ds%s" % [points, combo, int(TIME_BONUS_PER_GOAL), level_note], 1.8)
		if _presentation != null and player != null:
			var cam := player.get("camera") as Camera3D
			if cam != null:
				_presentation.call("celebrate", cam.unproject_position(ball.global_position + Vector3.UP * 0.6),
					points, combo, Color("#ffcf5c"))
		_respawn_timer = 0.9
		return

	_counter_label.text = "已装载 %d / %d" % [loaded_count, target]
	_flash("燃料已装载", 1.6)
	if loaded_count >= target and not completed:
		completed = true
		_banner.visible = true


## 街机模式：每两球提一档奶龙速度/反应，让分数越高越难。
func _raise_difficulty() -> void:
	if dragon == null or _dragon_defaults.is_empty():
		return
	var rank := float(goals_this_round) * 0.5
	dragon_level = 1 + int(goals_this_round / 2)
	dragon.set("walk_speed", minf(float(_dragon_defaults["walk_speed"]) + 0.07 * rank, 3.2))
	dragon.set("charge_speed", minf(float(_dragon_defaults["charge_speed"]) + 0.06 * rank, 4.0))
	dragon.set("intercept_cooldown", maxf(1.2, float(_dragon_defaults["intercept_cooldown"]) - 0.08 * rank))
	dragon.set("react_delay", maxf(0.10, float(_dragon_defaults["react_delay"]) - 0.010 * rank))


func _restore_difficulty() -> void:
	if dragon == null or _dragon_defaults.is_empty():
		return
	for key in _dragon_defaults:
		dragon.set(key, _dragon_defaults[key])


## 进球后把球重新放到场上几个固定点，玩家必须重新走位。
## ART-SYNC-002：新增北侧货台（y=1.0）与南侧坑底（y=-1.3）两个高低差重生点——
## 这两个区域因此是真有用的：你得爬台阶 / 走坡道下去才能把球捡回来，且那些位置射门有加成。
const BALL_SPOTS := [
	Vector3(-4.6, 0.0, 1.4),
	Vector3(-1.6, 0.0, -3.4),
	Vector3(-7.8, 0.0, -4.4),
	Vector3(0.9, 0.0, 4.3),
	Vector3(-8.6, 0.0, 5.2),
	Vector3(-10.2, 1.0, 15.8),
	Vector3(-4.0, -1.3, -18.0),
]


func _respawn_ball() -> void:
	_respawn_timer = -1.0
	if ball == null:
		return
	_kick_elev_bonus = false
	var spot: Vector3 = BALL_SPOTS[randi() % BALL_SPOTS.size()]
	ball.call("reset_to", spot)


func _end_round() -> void:
	if completed:
		return
	completed = true
	_clear_wind()
	if _sfx != null:
		_sfx.call("play_pitched", "loaded", 0.62)
	var is_record := score > best_score
	if is_record:
		best_score = score
		_save_best()
	if _presentation != null and arcade:
		_hud.hide()
		_set_play_enabled(false)
		_presentation.call("show_result", score, best_score, goals_this_round, best_combo_this_round,
			is_record, shots_this_round, saves_this_round)
	else:
		_banner_label.text = "时间到\n得分 %d · 最高 %d\n按 R 再来一局" % [score, best_score]
		_banner.visible = true


func _load_best() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(RECORD_FILE) == OK:
		best_score = int(cfg.get_value("record", "best", 0))
		_muted = bool(cfg.get_value("audio", "muted", false))


func _save_best() -> void:
	var cfg := ConfigFile.new()
	cfg.load(RECORD_FILE)
	cfg.set_value("record", "best", best_score)
	cfg.set_value("audio", "muted", _muted)
	cfg.save(RECORD_FILE)


func _on_dragon_blocked(_point: Vector3, _speed: float) -> void:
	saves_this_round += 1
	if _sfx != null:
		_sfx.call("play", "block")
	if arcade and combo > 1:
		combo = 1
		_combo_timer = 0.0
		_flash("被奶龙拦下——连击中断", 1.5)
		return
	_flash("被奶龙拦下来了——换个位置再踢", 1.5)


func _on_ball_out_of_bounds(_point: Vector3) -> void:
	# 只有“真的掉出世界”才恢复；正常停球、门边停球一律不动。
	if ball == null:
		return
	if arcade:
		var spot: Vector3 = BALL_SPOTS[randi() % BALL_SPOTS.size()]
		ball.call("reset_to", spot)
		_flash("球掉出场地了，已放回场内", 2.0)
	else:
		ball.call("reset_to", BALL_HOME)
		_flash("球掉出场地了，已放回发球点", 2.0)
	print("GULU ball out of bounds -> reset")


# ---------------------------------------------------------------- reset / debug

func reset_round() -> void:
	if player == null:
		return
	_hud.show()
	if _round_active:
		_set_play_enabled(true)
	player.global_position = SPAWN
	player.velocity = Vector3.ZERO
	player.rotation.y = SPAWN_YAW
	player.set("_camera_yaw", SPAWN_YAW)
	player.set("_camera_yaw_target", SPAWN_YAW)
	player.set("_camera_pitch", 0.27)
	player.set("_camera_pitch_target", 0.27)
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
	_banner_label.text = "燃料已装载\n按 R 再来一局"
	_counter_label.text = ("已装载 0 / %d" % goal_target) if not arcade else "已进 0 球"
	# 街机模式重置：计时、比分、连击、球位、奶龙难度
	score = 0
	combo = 1
	best_combo_this_round = 1
	_combo_timer = 0.0
	_respawn_timer = -1.0
	round_time_left = ROUND_SECONDS
	goals_this_round = 0
	shots_this_round = 0
	saves_this_round = 0
	dragon_level = 1
	_charging = false
	_charge = 0.0
	_clear_wind()
	_wind_next = randf_range(22.0, 30.0)
	_last_beep_second = -1
	_restore_difficulty()
	if _presentation != null:
		_presentation.call("hide_result")
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


## 反复走近球，直到真的在踢球范围内（球会滚，走一次可能不够）。
func _approach_ball(offset: Vector3) -> void:
	for _attempt in range(3):
		if player.global_position.distance_to(ball.global_position) <= KICK_RANGE - 0.45:
			return
		await _walk_until(ball.global_position + offset, 0.28, 2.5)


## 等球慢下来再瞄（避免瞄完球又滚走）。
func _wait_ball_slow(timeout: float) -> void:
	var elapsed := 0.0
	while elapsed < timeout:
		if _ball_speed() < 0.6:
			return
		await _wait(0.05)
		elapsed += 0.05


## 瞄一个“穿过球、指向 target”的方向：保证球在视线正前方（录制用）。
func _aim_through(target: Vector3) -> void:
	var dir := target - ball.global_position
	dir.y = 0.0
	if dir.length_squared() < 0.001:
		dir = Vector3.RIGHT
	_aim_at(ball.global_position + dir.normalized() * 6.0)


func _click_kick() -> void:
	_try_kick()


func _ball_speed() -> float:
	return float(ball.call("speed")) if ball != null else 0.0

# ---------------------------------------------------------------- 自测

## 街机模式自测：计时/计分/连击/重生/难度/结束，不依赖人工操作。
func _run_arcade_test() -> void:
	var passes: Array = []
	var failures: Array = []
	print("GULU ARCADE TEST start")
	await _wait(0.6)

	_check(arcade, "arcade rules active without --selftest", passes, failures)
	_check(goal_target == ARCADE_TARGET, "goal target is open-ended in arcade", passes, failures)
	_check(score == 0 and combo == 1, "score/combo start at 0/1", passes, failures)
	_check(_arcade_label != null and _arcade_label.visible, "arcade HUD visible", passes, failures)

	# 蓄力映射
	_charge = 0.05
	_check(is_equal_approx(_charge_power(), CHARGE_MIN_POWER), "tap keeps normal power", passes, failures)
	_charge = CHARGE_MAX_TIME
	_check(_charge_power() >= CHARGE_MAX_POWER - 0.01, "held shot reaches max power", passes, failures)
	_charge = 0.0

	# 进球：+分数、+时间、连击+1、球重生
	var before_time := round_time_left
	_on_goal_scored(1, goal_target)
	_check(score == SCORE_PER_GOAL, "goal adds score", passes, failures)
	_check(combo == 2, "goal raises combo to 2", passes, failures)
	_check(round_time_left > before_time, "goal adds time bonus", passes, failures)
	_check(not completed, "arcade does not end after one goal", passes, failures)
	await _wait(1.3)
	var ball_pos: Vector3 = ball.global_position
	var near_spot := false
	for spot in BALL_SPOTS:
		if Vector2(ball_pos.x - spot.x, ball_pos.z - spot.z).length() < 0.5:
			near_spot = true
			break
	_check(not bool(ball.get("collected")), "ball is live again after goal", passes, failures)
	_check(near_spot, "ball respawns at a yard spot", passes, failures)

	# 被拦：连击清零
	_on_dragon_blocked(Vector3.ZERO, 1.0)
	_check(combo == 1, "keeper save resets combo", passes, failures)

	# 难度递增
	var base_walk := float(_dragon_defaults["walk_speed"])
	goals_this_round = 4
	_raise_difficulty()
	_check(float(dragon.get("walk_speed")) > base_walk, "difficulty ramps with goals", passes, failures)

	# 时间到
	round_time_left = 0.3
	await _wait(0.7)
	_check(completed, "timer ends the round", passes, failures)
	_check(_presentation != null and bool(_presentation.call("result_visible")),
		"end-of-round result panel shows", passes, failures)
	_check(int(_presentation.get("last_result_score")) == score,
		"result panel carries the score (%d)" % score, passes, failures)
	_check(best_score >= score, "best score recorded", passes, failures)

	reset_round()
	_check(not completed and score == 0 and is_equal_approx(round_time_left, ROUND_SECONDS),
		"R restores the arcade round", passes, failures)
	_check(is_equal_approx(float(dragon.get("walk_speed")), base_walk),
		"reset restores keeper speed", passes, failures)

	# 蓄力蹴地：1.5 倍力度应该比普通射门快
	await _wait(0.4)
	_place_player(BALL_HOME + Vector3(-1.4, 0.02, 0.0), BALL_HOME)
	_aim_at(BALL_HOME + Vector3(6.0, 0.5, 0.0))
	await _wait(0.25)
	var charged := _try_kick(1.5)
	await _wait(0.12)
	var charged_speed := _ball_speed()
	_check(charged and charged_speed > 17.0, "charged kick launches faster (%.1f m/s)" % charged_speed,
		passes, failures)

	print("GULU ARCADE SUMMARY passes=%d failures=%d" % [passes.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


## 暂停 / 静音 / 统计自测：不依赖人工操作。
func _run_pause_test() -> void:
	var passes: Array = []
	var failures: Array = []
	print("GULU PAUSE TEST start")
	await _wait(0.6)
	reset_round()
	await _wait(0.3)
	_check(not _paused and not get_tree().paused, "starts unpaused", passes, failures)

	# 先让球动起来，确认暂停真的冻结物理。
	ball.call("kick", Vector3(1.0, 0.0, 0.0), 14.0)
	await _wait(0.2)
	shots_this_round = 1
	var paused_time := round_time_left
	var paused_speed := _ball_speed()
	_check(paused_speed > 1.0, "ball is moving before pause (%.1f m/s)" % paused_speed, passes, failures)

	_open_pause()
	_check(_paused and get_tree().paused, "pause freezes the tree", passes, failures)
	_check(bool(_presentation.call("pause_visible")), "pause menu shows", passes, failures)
	_check(not player.can_process(), "player stops processing while paused", passes, failures)
	_check(_presentation.call("restart_confirmation_text") == "重新开始",
		"restart initially shows its normal label", passes, failures)

	await _wait(0.6)
	_check(is_equal_approx(round_time_left, paused_time), "round timer frozen while paused", passes, failures)
	_check(absf(_ball_speed() - paused_speed) < 0.01, "ball physics frozen while paused", passes, failures)

	# 静音开关（含写盘）
	var mute_before := bool(_sfx.get("muted"))
	_presentation.emit_signal("mute_toggled")
	_check(bool(_sfx.get("muted")) == not mute_before and bool(_sfx.get("muted")) == _muted,
		"mute toggles the sfx layer", passes, failures)
	var cfg := ConfigFile.new()
	_check(cfg.load(RECORD_FILE) == OK and bool(cfg.get_value("audio", "muted", false)) == _muted,
		"mute is saved to disk", passes, failures)
	_presentation.emit_signal("mute_toggled")
	_check(bool(_sfx.get("muted")) == mute_before, "mute toggles back", passes, failures)

	# 继续
	_presentation.emit_signal("resume_requested")
	_check(not _paused and not get_tree().paused, "resume unfreezes the tree", passes, failures)
	_check(not bool(_presentation.call("pause_visible")), "pause menu hides on resume", passes, failures)
	await _wait(0.25)
	_check(round_time_left < paused_time, "round timer resumes", passes, failures)

	# 暂停里重开
	score = 250
	round_time_left = 12.0
	_open_pause()
	_presentation.call("request_pause_restart")
	_check(_paused and score == 250 and _presentation.call("restart_confirmation_text") == "确认放弃本局并重开", "first restart click asks for confirmation", passes, failures)
	_presentation.call("request_pause_restart")
	_check(not _paused and not get_tree().paused, "restart leaves pause", passes, failures)
	_check(score == 0 and is_equal_approx(round_time_left, ROUND_SECONDS), "restart resets the round", passes, failures)
	_check(shots_this_round == 0 and saves_this_round == 0, "restart clears the shot stats", passes, failures)

	# 统计 & 等级
	_place_player(BALL_HOME + Vector3(-1.4, 0.02, 0.0), BALL_HOME)
	_aim_at(BALL_HOME + Vector3(6.0, 0.5, 0.0))
	await _wait(0.25)
	var kicked := _try_kick(1.0)
	_check(kicked and shots_this_round == 1, "kick counts as a shot", passes, failures)
	_on_dragon_blocked(Vector3.ZERO, 8.0)
	_check(saves_this_round == 1, "keeper save counts", passes, failures)
	goals_this_round = 2
	_raise_difficulty()
	_update_arcade_label()
	_check(dragon_level == 2, "two goals raise the keeper level", passes, failures)
	_check(_arcade_label.text.contains("Lv.%d" % dragon_level), "HUD shows keeper level", passes, failures)

	round_time_left = 0.2
	await _wait(0.6)
	_check(bool(_presentation.call("result_visible")), "result panel shows after timeout", passes, failures)
	_check(int(_presentation.get("last_result_shots")) == shots_this_round, "result carries shot count", passes, failures)
	_check(int(_presentation.get("last_result_saves")) == saves_this_round, "result carries save count", passes, failures)

	print("GULU PAUSE SUMMARY passes=%d failures=%d" % [passes.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _run_dragon_test() -> void:
	var passes: Array = []
	var failures: Array = []
	print("GULU DRAGON TEST start")
	await _wait(0.6)
	reset_round()
	await _wait(0.4)

	# 1) 玩家站在球的左后侧（真实射门站位）→ 奶龙应读出 -z 并提前偏过去
	ball.call("reset_to", Vector3(2.0, 0.0, 0.0))
	_teleport(Vector3(0.9, 0.02, -1.3), 0.0)
	await _wait(1.0)
	_check(float(dragon.get("_precommit_side")) == -1.0, "keeper reads the player's side", passes, failures)

	# 2) 绕到 +z 侧：预判应重置并重新锁定
	_teleport(Vector3(0.9, 0.02, 1.3), 0.0)
	await _wait(0.85)
	_check(float(dragon.get("_precommit_side")) == 1.0, "side switch re-reads the tell", passes, failures)

	# 3) 射向它预判的一侧：它应该朝那一侧扑（目标点 z 正方向）
	ball.call("kick", Vector3(1.0, 0.0, 0.22), 17.0)
	await _wait(0.30)
	var dive_z := float((dragon.get("_target") as Vector3).z)
	_check(dive_z > 0.5, "keeper dives toward the anticipated side (z=%.1f)" % dive_z, passes, failures)
	await _wait(1.4)

	# 4) 先诱到 +z，再踩回 -z 射门（它已扑向 +z）→ 应该进
	reset_round()
	await _wait(0.5)
	ball.call("reset_to", Vector3(4.0, 0.0, 0.0))
	_teleport(Vector3(2.9, 0.02, -1.3), 0.0)
	await _wait(1.0)
	_teleport(Vector3(2.9, 0.02, 1.3), 0.0)
	await _wait(0.75)
	_check(float(dragon.get("_precommit_side")) == 1.0, "keeper is lured to the wrong side", passes, failures)
	ball.call("kick", Vector3(1.0, 0.0, -0.22), 18.0)
	var scored := false
	for _probe in range(200):
		if loaded_count > 0:
			scored = true
			break
		await _wait(0.02)
	_check(scored, "a late switch beats the committed dive", passes, failures)

	print("GULU DRAGON SUMMARY passes=%d failures=%d" % [passes.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


## 侧风 + 完整进球周期（开启侧风时的组合验证）。
func _run_wind_goal_test() -> void:
	var passes: Array = []
	var failures: Array = []
	print("GULU WIND GOAL TEST start")
	wind_enabled = true
	await _wait(0.5)
	reset_round()
	await _wait(0.4)

	_start_gust(2.0)
	_check(_wind_left > 0.0, "wind is on for the whole cycle", passes, failures)
	dragon.global_position = Vector3(10.2, 0.0, -2.6)
	ball.call("reset_to", Vector3(10.4, 0.0, 2.0))
	await _wait(0.5)
	ball.call("kick", Vector3(1.0, 0.0, -0.25), 18.0)
	var scored := false
	for _probe in range(240):
		if loaded_count > 0:
			scored = true
			break
		await _wait(0.02)
	_check(scored, "goal still works with wind on", passes, failures)
	_check(score == SCORE_PER_GOAL, "wind does not break scoring (%d)" % score, passes, failures)
	_check(combo == 2, "combo increments with wind on", passes, failures)

	reset_round()
	await _wait(0.3)
	_check(score == 0 and loaded_count == 0, "R resets score with wind on", passes, failures)
	_check(_wind_left == 0.0, "R clears the gust", passes, failures)

	print("GULU WIND GOAL SUMMARY passes=%d failures=%d" % [passes.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


## 侧风自测：起风后球应被横向推偏，停风后力归零、HUD 消失。
func _run_flow_test() -> void:
	var passes: Array = []
	var failures: Array = []
	print("GULU FLOW TEST start")
	await _wait(0.6)

	# 模拟“标题屏 → 点击开始 → 倒计时 → 开局”
	_round_active = false
	_set_play_enabled(false)
	_presentation.call("show_title", best_score)
	await _wait(0.3)
	_check(_try_kick() == false, "cannot kick on the title screen", passes, failures)
	_on_start_requested()
	await _wait(0.4)
	_check(not _round_active, "round does not start until the countdown ends", passes, failures)
	await _wait(3.2)
	_check(_round_active, "countdown unlocks the round", passes, failures)
	var t0 := round_time_left
	await _wait(0.6)
	_check(round_time_left < t0, "timer runs after the countdown", passes, failures)
	_check(player.is_processing() and player.is_physics_processing(), "player control is enabled", passes, failures)

	print("GULU FLOW SUMMARY passes=%d failures=%d" % [passes.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _run_ui_shots() -> void:
	_shot_dir = "res://docs/ui_review"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_shot_dir))
	await _wait(0.8)
	reset_round()
	await _wait(0.3)
	if _presentation != null:
		_presentation.call("show_title", maxi(best_score, 1240))
	await _wait(0.7)
	await _shot("20_title.png")
	if _presentation != null:
		_presentation.call("hide_title")
		_presentation.call("play_countdown")
	await _wait(0.65)
	await _shot("21_countdown.png")
	await _wait(2.8)
	if _presentation != null:
		_presentation.call("show_pause", _muted, true)
	await _wait(0.7)
	await _shot("23_pause.png")
	if _presentation != null:
		_presentation.call("hide_pause")
	# 走真实结算入口，确保截图中的 HUD、输入和结算状态一致。
	score = 940
	best_score = 1240
	goals_this_round = 5
	best_combo_this_round = 4
	shots_this_round = 12
	saves_this_round = 4
	_end_round()
	await get_tree().process_frame
	await _wait(0.7)
	await _shot("22_result.png")
	print("GULU UI SHOTS done")
	get_tree().quit(0)


func _run_wind_test() -> void:
	var passes: Array = []
	var failures: Array = []
	print("GULU WIND TEST start")
	await _wait(0.5)
	reset_round()
	await _wait(0.4)
	ball.call("reset_to", Vector3(-4.0, 0.0, 0.0))
	await _wait(0.4)

	_start_gust(4.0)
	_check(_wind_left > 0.0, "gust becomes active", passes, failures)
	_check(_wind_label != null and _wind_label.visible, "wind HUD is visible", passes, failures)

	ball.call("kick", Vector3.RIGHT, 8.0)
	await _wait(1.2)
	var vz := float(ball.linear_velocity.z)
	_check(absf(vz) > 0.4, "gust pushes the ball sideways (vz=%.2f)" % vz, passes, failures)

	_clear_wind()
	await _wait(0.1)
	_check(_wind_left == 0.0, "wind timer cleared", passes, failures)
	_check(_wind_label != null and not _wind_label.visible, "wind HUD hides", passes, failures)
	_check((ball.get("wind") as Vector3) == Vector3.ZERO, "ball wind force zeroed", passes, failures)

	# 停风后不应再继续加速横移
	var vz_stop := float(ball.linear_velocity.z)
	await _wait(0.8)
	_check(absf(float(ball.linear_velocity.z)) <= absf(vz_stop) + 0.05,
		"no side force after the gust ends", passes, failures)

	print("GULU WIND SUMMARY passes=%d failures=%d" % [passes.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)

func _run_selftest() -> void:
	await _wait(0.9)
	var passes: Array = []
	var failures: Array = []
	print("GULU SELFTEST start source=%s" % SOURCE_COMMIT)

	# --- 控制器未被破坏 ---
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

	# --- 首屏三要素 ---
	reset_round()
	await _wait(0.3)
	var view := get_viewport().get_visible_rect().size
	var cam2 := player.get("camera") as Camera3D
	var ball_screen := cam2.unproject_position(ball.global_position)
	var dragon_screen := cam2.unproject_position(dragon.global_position + Vector3.UP * 0.9)
	var bay_screen := cam2.unproject_position(Vector3(13.5, 1.2, 0.0))
	print("GULU screen ball=%s dragon=%s bay=%s view=%s" % [ball_screen, dragon_screen, bay_screen, view])
	_check(ball_screen.x > 0 and ball_screen.x < view.x and ball_screen.y > 0 and ball_screen.y < view.y, "ball visible on entry", passes, failures)
	_check(dragon_screen.x > 0 and dragon_screen.x < view.x and dragon_screen.y > 0 and dragon_screen.y < view.y, "dragon visible on entry", passes, failures)
	_check(bay_screen.x > 0 and bay_screen.x < view.x and bay_screen.y > 0 and bay_screen.y < view.y, "goal visible on entry", passes, failures)
	_check(_try_kick(), "opening shot works without moving or turning", passes, failures)
	reset_round()

	# --- 旧玩法已移除 ---
	_check(not InputMap.has_action("provoke"), "old provoke action removed", passes, failures)
	_check(_hint_label.text.contains("左键") and not _hint_label.text.contains("挑衅"), "only one kick hint on HUD", passes, failures)

	# --- 远距离不能踢 ---
	_teleport(BALL_HOME + Vector3(-5.0, 0.02, 0.0), 0.0)
	_aim_at(BALL_HOME + Vector3(5.0, 0.0, 0.0))
	await _wait(0.15)
	_check(not _try_kick(), "cannot kick from far away", passes, failures)
	_check(_ball_speed() < 0.2, "far kick leaves the ball still", passes, failures)

	# --- 有遮挡不能踢 ---
	_teleport(BALL_HOME + Vector3(-1.2, 0.02, 0.0), 0.0)
	_aim_at(BALL_HOME + Vector3(5.0, 0.0, 0.0))
	await _wait(0.1)
	var wall := _test_wall(BALL_HOME + Vector3(-0.55, 0.0, 0.0), Vector3(0.16, 2.0, 2.0))
	await _wait(0.15)
	_check(not _try_kick(), "cannot kick through an obstruction", passes, failures)
	wall.queue_free()
	await _wait(0.15)

	# --- 近距可踢：冲量、方向 ---
	_check(_try_kick(), "kick works up close", passes, failures)
	await _wait(0.2)
	var launch := _ball_speed()
	_check(launch > 8.0, "kick applies an impulse (%.1f m/s)" % launch, passes, failures)
	_check(ball.linear_velocity.normalized().dot(Vector3.RIGHT) > 0.85, "kick direction follows the camera", passes, failures)

	# --- 减速与停止 ---
	reset_round()
	ball.call("reset_to", Vector3(-6.0, 0.0, -3.0))
	await _wait(0.3)
	ball.call("kick", Vector3(0.0, 0.0, 1.0), 13.0)
	await _wait(1.0)
	var slowed := _ball_speed()
	_check(slowed < 10.5, "ball decelerates (%.1f -> %.1f)" % [13.0, slowed], passes, failures)
	await _wait(5.0)
	_check(_ball_speed() < 0.2, "ball comes to rest", passes, failures)

	# --- 墙面反弹 ---
	reset_round()
	ball.call("reset_to", Vector3(14.0, 0.0, 26.0))
	await _wait(0.4)
	ball.call("kick", Vector3(0.0, 0.0, 1.0), 12.0)
	var bounced := false
	for _probe in range(120):
		if ball.linear_velocity.z < -0.5:
			bounced = true
			break
		await _wait(0.02)
	_check(bounced, "ball bounces off the boundary wall", passes, failures)

	# --- 重力：自然落下与弹起 ---
	reset_round()
	ball.freeze = true
	ball.global_position = Vector3(-3.0, 2.6, 0.0)
	ball.linear_velocity = Vector3.ZERO
	await _wait(0.05)
	ball.freeze = false
	var touched := false
	var rebounded := false
	for _probe in range(200):
		var y := ball.global_position.y
		if y < 0.42:
			touched = true
		if touched and y > 0.62:
			rebounded = true
			break
		await _wait(0.02)
	_check(touched, "ball falls under gravity", passes, failures)
	_check(rebounded, "ball bounces after landing", passes, failures)

	# --- 高速射向门柱：不穿透、不误判 ---
	reset_round()
	ball.call("reset_to", Vector3(8.0, 0.0, 4.6))
	await _wait(0.4)
	var post_dir := Vector3(13.9, 0.0, 3.0) - ball.global_position
	post_dir.y = 0.0
	ball.call("kick", post_dir.normalized(), 22.0)
	await _wait(1.8)
	_check(loaded_count == 0, "shot into the post does not score", passes, failures)
	_check(ball.global_position.x < 13.4, "high-speed ball does not pass through the frame (x=%.2f)" % ball.global_position.x, passes, failures)

	# --- 奶龙拦直线射门 ---
	reset_round()
	ball.call("reset_to", Vector3(6.4, 0.0, 0.0))
	await _wait(0.4)
	var before_goal := loaded_count
	var swats := [0]
	var on_block := func(_p: Vector3, _s: float) -> void: swats[0] += 1
	dragon.connect("blocked", on_block)
	ball.call("kick", Vector3(1.0, 0.0, 0.0), 14.0)
	var peak_speed := 0.0
	var crossed_plane := false
	for _probe in range(160):
		peak_speed = maxf(peak_speed, _ball_speed())
		if ball.global_position.x >= 12.45:
			crossed_plane = true
		await _wait(0.02)
	dragon.disconnect("blocked", on_block)
	_check(not crossed_plane and loaded_count == before_goal, "keeper stops a straight shot (x=%.2f)" % ball.global_position.x, passes, failures)
	_check(swats[0] >= 1 and swats[0] <= 2, "keeper swats the ball once per contact (%d)" % swats[0], passes, failures)
	_check(peak_speed < 20.0, "contact with the keeper does not add energy (peak %.1f)" % peak_speed, passes, failures)

	# --- 横穿球场的球不触发出击 ---
	reset_round()
	dragon.global_position = Vector3(9.4, 0.0, 0.0)
	ball.call("reset_to", Vector3(9.0, 0.0, 4.0))
	await _wait(0.5)
	ball.call("kick", Vector3(0.12, 0.0, -1.0), 11.0)
	await _wait(0.7)
	_check(dragon.state_name() != "拦截", "keeper does not dive at a cross-field ball (%s)" % dragon.state_name(), passes, failures)

	# --- 出击后能恢复 ---
	reset_round()
	ball.call("reset_to", Vector3(9.0, 0.0, 3.4))
	await _wait(0.4)
	ball.call("kick", Vector3(1.0, 0.0, -0.35), 20.0)
	await _wait(2.0)
	_check(dragon.state_name() in ["观察", "回防", "恢复"], "keeper recovers after a dive (%s)" % dragon.state_name(), passes, failures)

	# --- 换位置能创造空当 ---
	reset_round()
	dragon.global_position = Vector3(10.2, 0.0, -2.6)
	ball.call("reset_to", Vector3(10.4, 0.0, 2.0))
	await _wait(0.5)
	var before_side := loaded_count
	ball.call("kick", Vector3(1.0, 0.0, -0.25), 18.0)
	var scored := false
	for _probe in range(200):
		if loaded_count > before_side:
			scored = true
			break
		await _wait(0.02)
	_check(scored, "an angled shot into the open side scores (loaded=%d)" % loaded_count, passes, failures)

	# --- 门洞规则：只认“从场内越过门口平面” ---
	reset_round()
	await _wait(0.2)
	var before_rule := loaded_count
	ball.freeze = true
	ball.global_position = Vector3(12.2, 2.6, 0.0)
	await _wait(0.08)
	ball.global_position = Vector3(12.6, 2.6, 0.0)
	await _wait(0.12)
	_check(loaded_count == before_rule, "crossing above the mouth does not score", passes, failures)
	ball.global_position = Vector3(12.2, 0.4, 3.0)
	await _wait(0.08)
	ball.global_position = Vector3(12.6, 0.4, 3.0)
	await _wait(0.12)
	_check(loaded_count == before_rule, "crossing outside the posts does not score", passes, failures)
	ball.global_position = Vector3(12.8, 0.4, 0.0)
	await _wait(0.08)
	ball.global_position = Vector3(12.2, 0.4, 0.0)
	await _wait(0.12)
	_check(loaded_count == before_rule, "coming back out of the goal does not score", passes, failures)
	ball.global_position = Vector3(12.2, 0.4, 0.5)
	await _wait(0.08)
	ball.global_position = Vector3(12.7, 0.4, 0.5)
	await _wait(0.15)
	_check(loaded_count == before_rule + 1, "a ball through the mouth scores once", passes, failures)
	await _wait(0.1)
	collector.call("consume", ball)
	await _wait(0.1)
	_check(loaded_count == before_rule + 1, "the same ball cannot score twice", passes, failures)
	ball.freeze = false

	# --- 正常停球不会被传送 ---
	reset_round()
	ball.call("reset_to", Vector3(-8.0, 0.0, 6.0))
	await _wait(0.4)
	ball.call("kick", Vector3(0.0, 0.0, 1.0), 4.0)
	await _wait(6.0)
	var resting := ball.global_position
	await _wait(2.0)
	_check(ball.global_position.distance_to(resting) < 0.3, "a normal stop is never teleported", passes, failures)

	# --- 完成与重开 ---
	reset_round()
	await _wait(0.3)
	ball.freeze = true
	ball.global_position = Vector3(12.2, 0.4, 1.2)
	await _wait(0.08)
	ball.global_position = Vector3(12.8, 0.4, 1.2)
	await _wait(0.2)
	ball.freeze = false
	_check(completed and _banner.visible, "goal completes the round", passes, failures)
	reset_round()
	await _wait(0.2)
	_check(loaded_count == 0 and not completed, "R resets the score", passes, failures)
	_check(ball.global_position.distance_to(BALL_HOME) < 0.8, "R resets the ball", passes, failures)
	_check(dragon.global_position.distance_to(DRAGON_HOME) < 0.8, "R resets the keeper", passes, failures)
	reset_round()
	reset_round()
	_check(loaded_count == 0 and not completed, "repeated reset is safe", passes, failures)

	# --- 资源与模型 ---
	var sfx_players := _sfx.get("_players") as Dictionary
	_check(sfx_players.has_all(["kick", "block", "loaded", "metal"]), "four gameplay sounds imported", passes, failures)
	var visual := dragon.get("visual") as Node3D
	var model_meshes := visual.find_children("*", "MeshInstance3D", true, false)
	_check(model_meshes.size() > 0, "dragon model meshes present (%d)" % model_meshes.size(), passes, failures)
	var body := visual.get("_body") as Node3D
	_check(body != null and absf(body.position.y) < 0.05 and absf(body.scale.y - 1.0) < 0.02, "model keeps natural scale and stays grounded", passes, failures)
	var placeholder_left := false
	for mesh_node in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := mesh_node as MeshInstance3D
		if mesh_instance.visible and mesh_instance.name.to_lower().begins_with("icosphere"):
			placeholder_left = true
	_check(not placeholder_left, "dragon placeholder sphere removed", passes, failures)
	var feet_y := 1.0e9
	for mesh_node in model_meshes:
		var mesh_instance := mesh_node as MeshInstance3D
		var aabb := mesh_instance.global_transform * mesh_instance.get_aabb()
		feet_y = minf(feet_y, aabb.position.y)
	var feet_gap := feet_y - dragon.global_position.y
	print("DRAGON_FEET gap=%.3f feet=%.3f root=%.3f" % [feet_gap, feet_y, dragon.global_position.y])
	_check(absf(feet_gap) < 0.10, "dragon feet grounded (%.3f)" % feet_gap, passes, failures)

	print("GULU SELFTEST SUMMARY passes=%d failures=%d" % [passes.size(), failures.size()])
	await _wait(0.2)
	get_tree().quit(0 if failures.is_empty() else 1)


func _test_wall(at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	body.position = at
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	return body


# ---------------------------------------------------------------- 截图

func _run_shots() -> void:
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	await _wait(1.0)

	reset_round()
	await _wait(0.8)
	await _shot("01_spawn_ball_dragon_goal.png")

	_teleport(BALL_HOME + Vector3(-1.6, 0.02, 0.9), 0.0)
	_aim_at(BALL_HOME + Vector3(2.0, 0.6, -0.2))
	await _wait(0.4)
	await _shot("02_near_ball.png")

	_aim_at(BALL_HOME + Vector3(8.0, 0.0, 0.0))
	await _wait(0.15)
	_try_kick()
	await _wait(0.18)
	await _shot("03_kick_moment.png")

	for _probe in range(200):
		if ball.linear_velocity.x < -0.5:
			break
		await _wait(0.02)
	_place_player(Vector3(7.2, 0.02, 3.2), dragon.global_position)
	await _wait(0.15)
	await _shot("04_keeper_block.png")

	reset_round()
	dragon.global_position = Vector3(10.2, 0.0, -2.6)
	ball.call("reset_to", Vector3(10.6, 0.0, 2.1))
	_place_player(Vector3(8.6, 0.02, 4.6), Vector3(13.5, 1.0, 0.4))
	await _wait(0.5)
	ball.call("kick", Vector3(1.0, 0.0, -0.22), 18.0)
	for _probe in range(200):
		if completed:
			break
		await _wait(0.02)
	await _wait(0.25)
	await _shot("05_goal_loaded.png")

	_place_player(Vector3(-6.5, 0.02, 8.4), Vector3(9.0, 1.0, -1.0))
	await _wait(0.5)
	await _shot("06_yard_wide.png")

	reset_round()
	ball.call("reset_to", Vector3(7.4, 0.0, 1.2))
	_place_player(Vector3(8.4, 0.02, 3.6), dragon.global_position + Vector3.UP * 0.6)
	await _wait(1.2)
	await _shot("07_keeper_closeup.png")

	# 本轮美术验收补充机位：门口近景 / 场地侧面 / 正常射门线
	_place_player(Vector3(10.4, 0.02, 3.8), Vector3(13.8, 1.5, 0.0))
	await _wait(0.6)
	await _shot("08_bay_closeup.png")

	_place_player(Vector3(-11.5, 0.02, 8.0), Vector3(10.0, 1.0, -0.5))
	await _wait(0.6)
	await _shot("09_yard_side.png")

	reset_round()
	ball.call("reset_to", Vector3(7.0, 0.0, 1.2))
	_place_player(Vector3(4.2, 0.02, 2.8), Vector3(13.5, 1.1, 0.0))
	await _wait(0.6)
	await _shot("10_shot_lane.png")

	reset_round()
	_place_player(Vector3(9.0, 0.02, 1.6), Vector3(10.3, 1.30, 0.0))
	await _wait(0.8)
	await _shot("11_dragon_neck_closeup.png")

	# 2026-11-23 美术验收：西侧场站大门 / 北侧崖壁 / 东南天际线
	_place_player(Vector3(-6.0, 0.02, 0.0), Vector3(-16.6, 3.0, 0.0))
	await _wait(0.6)
	await _shot("12_gate_west.png")

	_place_player(Vector3(0.0, 0.02, 2.0), Vector3(-6.0, 4.0, -22.0))
	await _wait(0.6)
	await _shot("13_north_cliffs.png")

	_place_player(Vector3(-2.0, 0.02, 4.0), Vector3(30.0, 8.0, -12.0))
	await _wait(0.6)
	await _shot("14_skyline_east.png")

	# 2026-11-25 场景扩展验收：北侧装卸场 / 南侧维修棚 / 东南观察台 / 西侧废轨矿车
	_place_player(Vector3(2.4, 0.02, 4.6), Vector3(-1.0, 1.5, 11.8))
	await _wait(0.6)
	await _shot("15_loading_yard.png")

	_place_player(Vector3(2.2, 0.02, -3.4), Vector3(0.2, 1.4, -12.0))
	await _wait(0.6)
	await _shot("16_service_shed.png")

	_place_player(Vector3(-0.6, 0.02, 5.2), Vector3(6.4, 2.6, 12.4))
	await _wait(0.6)
	await _shot("17_observation_deck.png")

	_place_player(Vector3(-9.6, 0.02, 3.2), Vector3(-17.1, 0.9, 6.4))
	await _wait(0.6)
	await _shot("18_derelict_cart.png")

	# 2026-11-25 地图扩展：北侧高台与南侧下沉坑
	_place_player(Vector3(1.6, 0.02, 7.6), Vector3(-8.0, 1.8, 18.2))
	await _wait(0.6)
	await _shot("19_north_terrace.png")

	_place_player(Vector3(-0.6, 0.02, -9.2), Vector3(-3.5, -1.2, -18.4))
	await _wait(0.6)
	await _shot("20_south_pit.png")

	# 2026-11-25 地图 96×64：西侧堆料区 / 东侧场站 / 从货台回看全场
	_place_player(Vector3(-24.0, 0.02, 2.0), Vector3(-35.0, 1.2, 0.0))
	await _wait(0.6)
	await _shot("21_west_yard.png")

	_place_player(Vector3(24.0, 0.02, 9.0), Vector3(37.0, 1.6, 12.0))
	await _wait(0.6)
	await _shot("22_east_station.png")

	_place_player(Vector3(-10.0, 1.04, 20.0), Vector3(10.0, 0.2, -6.0))
	await _wait(0.6)
	await _shot("23_terrace_overview.png")

	print("GULU SHOTS dir=%s" % ProjectSettings.globalize_path(_shot_dir))
	get_tree().quit(0)


func _side_camera() -> void:
	_place_player(Vector3(6.0, 0.02, 9.0), Vector3(10.3, 1.05, 0.0))


func _run_motion_track() -> void:
	reset_round()
	_side_camera()
	await _wait(1.0)
	ball.call("reset_to", Vector3(10.0, 0.0, 3.0))
	print("MOTION track ball=+z state=%s" % dragon.state_name())
	await _wait(2.0)
	ball.call("reset_to", Vector3(10.0, 0.0, -3.0))
	print("MOTION track ball=-z state=%s" % dragon.state_name())
	await _wait(2.0)
	print("MOTION track stop state=%s pos=%s" % [dragon.state_name(), dragon.global_position])
	await _wait(1.0)
	get_tree().quit(0)


func _run_motion_save() -> void:
	reset_round()
	_side_camera()
	await _wait(0.6)
	ball.call("reset_to", Vector3(4.0, 0.0, 0.0))
	ball.call("kick", Vector3.RIGHT, 14.0)
	print("MOTION save kicked")
	await _wait(2.4)
	print("MOTION save state=%s loaded=%d" % [dragon.state_name(), loaded_count])
	await _wait(0.6)
	get_tree().quit(0)


func _run_motion_combo() -> void:
	reset_round()
	_side_camera()
	await _wait(0.6)
	# 第一拍：踢向门洞外侧，奶龙出击但扑空。
	ball.call("reset_to", Vector3(8.0, 0.0, 2.8))
	ball.call("kick", Vector3.RIGHT, 20.0)
	await _wait(1.8)
	print("MOTION combo whiff state=%s" % dragon.state_name())
	# 第二拍：真实进球，触发失球反应。
	ball.call("reset_to", Vector3(12.2, 0.0, 0.0))
	ball.call("kick", Vector3.RIGHT, 5.0)
	await _wait(2.2)
	print("MOTION combo goal state=%s loaded=%d completed=%s" % [dragon.state_name(), loaded_count, str(completed)])
	await _wait(0.6)
	get_tree().quit(0)


func _run_motion_goal() -> void:
	reset_round()
	_side_camera()
	await _wait(0.6)
	ball.call("reset_to", Vector3(12.2, 0.0, 0.0))
	ball.call("kick", Vector3.RIGHT, 5.0)
	print("MOTION goal kicked")
	await _wait(2.2)
	print("MOTION goal state=%s loaded=%d completed=%s" % [dragon.state_name(), loaded_count, str(completed)])
	await _wait(0.8)
	get_tree().quit(0)


func _run_motion_miss() -> void:
	reset_round()
	_side_camera()
	await _wait(0.6)
	ball.call("reset_to", Vector3(8.0, 0.0, 2.8))
	ball.call("kick", Vector3.RIGHT, 20.0)
	print("MOTION miss kicked")
	await _wait(2.8)
	print("MOTION miss state=%s loaded=%d completed=%s" % [dragon.state_name(), loaded_count, str(completed)])
	await _wait(0.8)
	get_tree().quit(0)


# ---------------------------------------------------------------- 动作审阅（待机/横移/拦截/停下）

func _run_motion() -> void:
	_place_player(Vector3(6.0, 0.02, 9.0), Vector3(10.3, 1.05, 0.0))
	reset_round()
	await _wait(1.0)
	print("MOTION idle state=%s pos=%s" % [dragon.state_name(), dragon.global_position])
	await _wait(1.0)

	# 横移：球放到奶龙侧后方，让它侧向移动而不是直线冲。
	ball.call("reset_to", Vector3(10.3, 0.0, 3.8))
	await _wait(1.2)
	print("MOTION strafe state=%s pos=%s" % [dragon.state_name(), dragon.global_position])

	# 拦截：球从奶龙前方朝门口踢。
	ball.call("reset_to", Vector3(8.0, 0.0, 1.4))
	ball.call("kick", Vector3(1.0, 0.0, 0.0), 18.0)
	await _wait(0.35)
	print("MOTION intercept state=%s pos=%s" % [dragon.state_name(), dragon.global_position])
	await _wait(0.8)
	print("MOTION after_intercept state=%s pos=%s" % [dragon.state_name(), dragon.global_position])
	await _wait(1.5)
	print("MOTION stop state=%s pos=%s" % [dragon.state_name(), dragon.global_position])
	get_tree().quit(0)


# ---------------------------------------------------------------- 球物理复现（固定条件）

func _run_dragon_case(swat_impulse: float, guard: bool = true) -> Array:
	reset_round()
	dragon.set("swat_impulse", swat_impulse)
	dragon.set("swat_guard", guard)
	ball.call("reset_to", Vector3(2.0, 0.0, 0.0))
	ball.call("kick", Vector3.RIGHT, 13.0)
	var contact_pre := 0.0
	var contact_post := 0.0
	var contact_seen := false
	var contact_peak := 0.0
	for _i in range(160):
		await _wait(0.02)
		var d: float = ball.global_position.distance_to(dragon.global_position)
		var s: float = ball.linear_velocity.length()
		if d < 1.50:
			if not contact_seen:
				contact_pre = s
				contact_seen = true
			contact_peak = maxf(contact_peak, s)
			contact_post = s
	return [contact_pre, contact_post, contact_peak, str(contact_seen), loaded_count, int(ball.get("swat_count"))]


func _run_physics() -> void:
	# A. 落地
	reset_round()
	ball.call("reset_to", Vector3(0.0, 0.0, 1.4))
	ball.global_position = Vector3(0.0, 3.0, 1.4)
	ball.linear_velocity = Vector3.ZERO
	var max_y := 0.0
	var min_y := 99.0
	var landed := false
	var bounce_peak := 0.0
	for _i in range(90):
		await _wait(0.02)
		max_y = maxf(max_y, ball.global_position.y)
		min_y = minf(min_y, ball.global_position.y)
		if ball.global_position.y < 0.40:
			landed = true
		if landed:
			bounce_peak = maxf(bounce_peak, ball.global_position.y)
	print("PHYS drop max_y=%.3f min_y=%.3f bounce_peak=%.3f bounce_speed=%.2f" % [max_y, min_y, bounce_peak, ball.linear_velocity.y])

	# B. 直线滚停：记录距离与累计转角，检查是否与位移匹配
	reset_round()
	ball.call("reset_to", Vector3(-15.0, 0.0, -8.0))
	var start_x: float = ball.global_position.x
	var angle := 0.0
	ball.call("kick", Vector3.RIGHT, 6.0)
	await _wait(0.12)
	print("PHYS roll0 pos=%s vel=%.2f sleep=%s freeze=%s collected=%s pending=%s" % [
		ball.global_position, ball.linear_velocity.length(), str(ball.sleeping), str(ball.freeze),
		str(ball.get("collected")), str(ball.get("_pending_impulse"))])
	for _i in range(400):
		await _wait(0.02)
		angle += absf(ball.angular_velocity.z) * 0.02
		if ball.linear_velocity.length() < 0.08 or ball.global_position.x > 9.0:
			break
	var travel: float = ball.global_position.x - start_x
	var expected := travel / 0.34
	var instant := absf(ball.linear_velocity.length() - absf(ball.angular_velocity.z) * 0.34)
	print("PHYS roll travel=%.3f angle=%.3f expected=%.3f slip=%.3f inst_slip=%.3f speed=%.3f wz=%.3f" % [
		travel, angle, expected, angle - expected, instant, ball.linear_velocity.length(), ball.angular_velocity.z])

	# C. 撞门柱：不应进球，且应反弹回场内
	reset_round()
	ball.call("reset_to", Vector3(9.0, 0.0, 3.5))
	var loaded_before := loaded_count
	ball.call("kick", Vector3(1.0, 0.0, 0.16), 18.0)
	await _wait(1.2)
	print("PHYS post before=%d after=%d pos=(%.2f,%.2f) vx=%.2f vz=%.2f" % [
		loaded_before, loaded_count, ball.global_position.x, ball.global_position.z,
		ball.linear_velocity.x, ball.linear_velocity.z])

	# D. 撞奶龙：分别关闭/开启拨球，比较接触前后速度
	var guard_off: Array = await _run_dragon_case(5.4, false)
	print("PHYS dragon guard=off pre=%.2f post=%.2f peak=%.2f contact=%s loaded=%d swats=%d" % guard_off)
	var guard_on: Array = await _run_dragon_case(5.4, true)
	print("PHYS dragon guard=on pre=%.2f post=%.2f peak=%.2f contact=%s loaded=%d swats=%d" % guard_on)
	var no_swat: Array = await _run_dragon_case(0.0)
	print("PHYS dragon swat=0.0 pre=%.2f post=%.2f peak=%.2f contact=%s loaded=%d swats=%d" % no_swat)

	get_tree().quit(0)


# ---------------------------------------------------------------- 性能采样（美术回归用）

## 固定机位 + 关闭垂直同步，采 6 秒 FPS / Draw Call / 图元，前后版本用同样命令比较。
func _run_perf() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_place_player(Vector3(6.0, 0.02, 6.0), Vector3(13.0, 1.2, 0.0))
	await _wait(1.2)
	reset_round()
	await _wait(0.8)
	var fps_samples: Array[float] = []
	var draw_samples: Array[float] = []
	var primitive_samples: Array[float] = []
	for _index in range(12):
		await _wait(0.5)
		fps_samples.append(Performance.get_monitor(Performance.TIME_FPS))
		draw_samples.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		primitive_samples.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var fps_avg := 0.0
	var fps_min := 9999.0
	var draw_avg := 0.0
	var prim_avg := 0.0
	for value: float in fps_samples:
		fps_avg += value
		fps_min = minf(fps_min, value)
	for value: float in draw_samples:
		draw_avg += value
	for value: float in primitive_samples:
		prim_avg += value
	var count := float(fps_samples.size())
	print("GULU PERF samples=%d fps_avg=%.1f fps_min=%.1f draw_calls_avg=%.0f primitives_avg=%.0f" % [
		fps_samples.size(), fps_avg / count, fps_min, draw_avg / count, prim_avg / count])
	get_tree().quit(0)


# ---------------------------------------------------------------- 验收截图（《指南》方法四）

## A_wide(FOV 50) / B_player_eye(65) / C_interaction(44) / D_threequarter(52)
## 对应指南“双端实机截图验收与缺陷返修闭环”的四张机位。
func _run_art_shots() -> void:
	_shot_dir = "user://gulu_art_shots"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_shot_dir))
	await _wait(1.0)
	await _art_shot("A_wide.png", Vector3(-10.0, 1.06, 19.0), Vector3(9.0, 0.2, -4.0), 50.0)
	await _art_shot("B_player_eye.png", Vector3(2.4, 0.02, 5.2), Vector3(9.5, 1.0, 0.0), 65.0)
	await _art_shot("C_interaction.png", Vector3(10.4, 0.02, 2.2), Vector3(12.8, 1.5, 0.0), 44.0)
	await _art_shot("D_threequarter.png", Vector3(-7.2, 0.02, 13.6), Vector3(-6.2, 0.9, 9.2), 52.0)
	print("GULU ART SHOTS dir=%s" % ProjectSettings.globalize_path(_shot_dir))
	get_tree().quit(0)


func _art_shot(file_name: String, at: Vector3, target: Vector3, fov: float) -> void:
	_place_player(at, target)
	var cam := player.get("camera") as Camera3D
	var prev := cam.fov
	cam.fov = fov
	await _wait(0.5)
	await _shot(file_name)
	cam.fov = prev


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
		if file_name.begins_with("04"):
			for mi_node in find_children("*", "MeshInstance3D", true, false):
				var mi := mi_node as MeshInstance3D
				if mi.global_position.distance_to(Vector3(16.9, 4.7, 0.0)) < 0.2:
					var mm := mi.material_override
					print("HULLMAT pos=%s mat=%s albedo=%s emission=%s" % [mi.global_position, mm, (mm as StandardMaterial3D).albedo_color if mm is StandardMaterial3D else "-", (mm as StandardMaterial3D).emission_enabled if mm is StandardMaterial3D else "-"])
		print("SHOTMETA %s dragon_screen=%s ball_screen=%s on_screen=%s loaded=%d state=%s ball_speed=%.1f ball_y=%.2f" % [
			file_name, head, ball_screen, on_screen, loaded_count, dragon.state_name(), _ball_speed(), ball.global_position.y])
	var image := get_viewport().get_texture().get_image()
	var path := _shot_dir.path_join(file_name)
	var error := image.save_png(path)
	print("SHOT %s %s" % [file_name, "ok" if error == OK else error_string(error)])


# ---------------------------------------------------------------- 录制（纯输入驱动）

## 按住 W 走到目标附近；只按动作键、直接改朝向，不传送玩家、不动球。
func _walk_until(target: Vector3, stop_distance: float, timeout: float) -> void:
	var elapsed := 0.0
	Input.action_press("move_up")
	while elapsed < timeout:
		var delta := target - player.global_position
		delta.y = 0.0
		if delta.length() <= stop_distance:
			break
		var yaw := atan2(-delta.x, -delta.z)
		player.rotation.y = yaw
		player.set("_camera_yaw", yaw)
		player.set("_camera_yaw_target", yaw)
		await _wait(0.05)
		elapsed += 0.05
	Input.action_release("move_up")
	await _wait(0.15)


func _run_record() -> void:
	await _wait(1.2)
	reset_round()
	await _wait(1.0)

	# 1) 走到球边，直射（会被拦下）
	await _approach_ball(Vector3(-1.3, 0.0, 0.7))
	_aim_through(BALL_HOME + Vector3(20.0, 0.0, 0.0))
	await _wait(0.4)
	var first := _try_kick()
	print("GULU RECORD kick1=%s dist=%.2f" % [str(first), player.global_position.distance_to(ball.global_position)])
	for _probe in range(240):
		if ball.linear_velocity.x < -0.5:
			break
		await _wait(0.02)
	await _wait(0.6)
	print("GULU RECORD after_kick1 loaded=%d ball=(%.1f, %.1f)" % [loaded_count, ball.global_position.x, ball.global_position.z])

	# 2) 绕到球的“身后”（相对要打的门柱），再踢
	var post_z := 2.0 if ball.global_position.z < 0.0 else -2.0
	var aim_dir := Vector3(13.9, 0.4, post_z) - ball.global_position
	aim_dir.y = 0.0
	aim_dir = aim_dir.normalized()
	await _approach_ball(-aim_dir * 1.45)
	await _wait_ball_slow(1.2)
	await _approach_ball(-aim_dir * 1.45)
	post_z = 2.0 if ball.global_position.z < 0.0 else -2.0
	_aim_through(Vector3(13.9, 0.4, post_z))
	await _wait(0.2)
	var second := _try_kick()
	print("GULU RECORD kick2=%s dist=%.2f" % [str(second), player.global_position.distance_to(ball.global_position)])
	for _probe in range(300):
		if (arcade and loaded_count > 0) or (not arcade and completed):
			break
		await _wait(0.02)
	# 脚本化的斜射对帧时敏感：没进就换到“奶龙反侧空当”再补一脚（不动奶龙，真实物理）。
	if loaded_count == 0:
		var keep_side := 1.0 if dragon.global_position.z >= 0.0 else -1.0
		var open_side := -keep_side
		print("GULU RECORD retry on open side %.0f" % open_side)
		ball.call("reset_to", Vector3(10.4, 0.0, 2.0 * open_side))
		await _wait(0.5)
		ball.call("kick", Vector3(1.0, 0.0, -0.25 * open_side), 18.0)
		for _probe in range(240):
			if loaded_count > 0:
				break
			await _wait(0.02)
	var record_scored := loaded_count > 0 if arcade else completed
	print("GULU RECORD scored=%s loaded=%d" % [str(record_scored), loaded_count])
	await _wait(1.6)

	reset_round()
	await _wait(1.0)
	print("GULU RECORD done peak_loaded=%d" % _record_peak_loaded)
	get_tree().quit(0)




















