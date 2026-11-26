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
const ARENA_TOWER := preload("res://assets/models/nailong/floodlight_tower.glb")
const ARENA_CONTAINER_A := preload("res://assets/models/nailong/container_a.glb")
const ARENA_CONTAINER_B := preload("res://assets/models/nailong/container_b.glb")
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
## --- 必杀槽（P1）：每踢出一脚满蓄 +1 格，满 3 格后下一脚变成“超载射门” ---
## 超载：冲量 ×1.9，命中带 0.4 s 慢放；代价是满蓄被扑会给奶龙 5 秒加速（风险射门 C）。
const FULL_CHARGE_POWER := 1.25
const METER_MAX := 3
const OVERLOAD_MULTIPLIER := 1.9
const DRAGON_BOOST_SECONDS := 5.0
const DRAGON_BOOST_MULT := 1.25
var power_meter := 0
var _last_shot_full_charge := false
var _last_shot_overload := false
var _dragon_boost_left := 0.0
var _meter_label: Label
var _slowmo_busy := false

## --- 进程层（P1）：难度三档 + 本地挑战清单 ---
## 难度只缩放奶龙的速度/反应，不改球路、进球判定与玩家参数。
const TIER_NAMES := ["轻松", "标准", "硬核"]
const TIER_SPEED := [0.85, 1.0, 1.25]
const TIER_REACT := [1.30, 1.0, 0.82]
const CHALLENGE_LIST := [
	"first_goal", "hat_trick", "combo4", "combo6", "order2",
	"overload", "high_shot", "score500", "score1000", "unbeaten",
]
const CHALLENGE_LABELS := {
	"first_goal": "首球入账",
	"hat_trick": "单局帽子戏法",
	"combo4": "连击 x4",
	"combo6": "连击 x6",
	"order2": "订单双响",
	"overload": "超载射门",
	"high_shot": "高台/坑底进球",
	"score500": "单局 500 分",
	"score1000": "单局 1000 分",
	"unbeaten": "零封一局",
}
var difficulty_tier := 1
var best_by_tier: Array[int] = [0, 0, 0]
var challenges: Dictionary = {}
var _new_challenges: Array[String] = []
var _overload_used := false
var _high_goal := false

## --- 通关结构（关卡制）：一局分 3 关，每关有必达目标；三关全过 = 通关 ---
## 目的是把“无限刷分”变成“打得完的一局”，同时逼玩家用上整张地图。
const STAGE_COUNT := 6
var campaign := true
var stage := 1
var stage_goals := 0
var stage_order_hits := 0
var stage_high_goals := 0
var stage_overloads := 0
var campaign_done := false
var _stage_label: Label
var _stage_hud_left := 0.0
var _order_hud_left := 0.0

## --- 反击（对标 Windjammers / Mario Strikers 的“你来我往”）---
## 奶龙扑出后把球开回场地，玩家在 3 秒内进球算反击，得分 ×1.5。
const COUNTER_WINDOW := 3.0
const COUNTER_BONUS := 1.5
var _counter_left := 0.0
var _counter_warned := false
var counter_enabled := true
var _keep_stage := false

var _combo_timer := 0.0
var _respawn_timer := -1.0
# 进球后不再把球“送回脚下”，而是像开球一样从舱口弹回场地，保持攻防连续。
var _goal_kick_pending := false

## --- 练习关（P1 收尾）：从标题屏 4/5/6 进入，各自一个明确目标，60 秒内完成 ---
const PRACTICE_NAMES := ["", "练习 · 定点射门", "练习 · 骗守门员", "练习 · 连击保持"]
const PRACTICE_SECONDS := 60.0
var practice_mode := 0
var _practice_goal := 0
var _practice_done := 0
var _whiffs_this_round := 0
var _last_whiff_ms := -100000
var _practice_label: Label

## --- P2：时段预设（只改光照/雾/天空，不改任何玩法）---
const TIME_NAMES := ["正午", "黄昏", "夜班"]
var time_of_day := 0
var _env: Environment
var _sky_material: ProceduralSkyMaterial
var _sun: DirectionalLight3D
var _rim: DirectionalLight3D
var _fill: OmniLight3D
var _yard_fill: SpotLight3D
var _graze: SpotLight3D

## --- 提案 B：奶龙偷球（P1 后唯一未做的核心玩法提案）---
## 拦截时按概率把球叼走 4 秒；玩家靠近 2.5 m 按 E 抢回，抢回 +1 格必杀槽。
## 每局最多 2 次、冷却 8 秒，避免变成“一直追着跑”的负体验。
const STEAL_CHANCE := 0.35
const STEAL_LIMIT := 2
const STEAL_COOLDOWN := 8.0
const CARRY_SECONDS := 4.0
const RETRIEVE_RANGE := 2.5
var steals_used := 0
var _steal_cooldown_left := 0.0
var _ball_carried := false
var _carry_left := 0.0
var _steal_force_next := false
var _retrieve_held := false
var _carry_label: Label

## --- 装货订单（玩法改造 A）：每 30 秒换一个舱口高度，命中当前订单 ×2 ---
## 0 = 下舱(低平球) / 1 = 中舱(平射) / 2 = 上舱(挑高球)。只改“打哪一层值钱”，
## 不改任何物理与拦截判定，所以 45 条物理回归不受影响。
const ORDER_PERIOD := 30.0
const ORDER_ZONE_NAMES := ["下舱", "中舱", "上舱"]
var order_zone := 1
var _order_clock := 0.0
var _order_hits := 0
var _order_label: Label

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
# 每张地图的侧风强度/间隔（主图 1.0 / 北场 1.25 / 南场 1.55）
var _wind_strength := 1.0
var _wind_period := 1.0
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
var _hud_canvas: Control
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

# --- P0 打击反馈（顿帧 / 抖动 / 尘埃）---
## 只在“真人游玩 + 渲染窗口”时开启：headless 自测、截图、录像一律关闭，
## 保证 45/21/23 条确定性回归与 art shot 构图完全不受影响。
var _fx_live := false
var _hitstop_busy := false
var _dust_material: StandardMaterial3D
## 手柄按键边沿（轮询用）
var _pad_shoot_held := false
var _pad_pause_held := false
var _pad_pump: Node
var _boot_stage := 0
var _goals: Array = []
var _active_map := 0
var _map_card: Label
var _route_label: RichTextLabel
var _travel_label: Label
var _arena_kit: GuluArtKit
var _arena_mats: Dictionary = {}
## 关卡之间的“走过去”：清关后不瞬移，玩家沿连廊走到下一块场地才开始下一关。
var _travel_pending := false
var _travel_target := Vector3.ZERO
var travel_enabled := true
var _last_dragon_state := ""
var _map_card_shown := false
var _step_clock := 0.0

# --- 自动录制（连续截图，后可合成为 GIF/视频）---
var _record_peak_loaded := 0
const RECORD_INTERVAL := 0.125


func _ready() -> void:
	Engine.time_scale = 1.0
	var args := OS.get_cmdline_user_args()
	# 确定性模式保持旧规则（进一球即结束），其余都是 90 秒街机模式。
	var deterministic := args.has("--selftest") or args.has("--physics")
	for arg in args:
		if arg.begins_with("--motion"):
			deterministic = true
	arcade = not deterministic
	wind_enabled = arcade and args.has("--wind")
	goal_target = GOAL_TARGET if deterministic else ARCADE_TARGET
	_fx_live = arcade and DisplayServer.get_name() != "headless"
	for blocker in ["--shots", "--art-shots", "--record", "--perf", "--selftest", "--physics",
			"--arcade-test", "--flow-test", "--dragon-test", "--pause-test", "--wind-test",
			"--wind-goal", "--ui-shots"]:
		if args.has(blocker):
			_fx_live = false
	for arg in args:
		if arg.begins_with("--stage="):
			_boot_stage = int(arg.split("=")[1])
	_load_best()
	# 自动化模式（自测 / 截图 / 录像 / 带参数启动）固定用“标准”档，保证回归确定性；
	# 只有正常双击启动才会读玩家上次选的难度。
	if not args.is_empty():
		difficulty_tier = 1
		best_score = best_by_tier[difficulty_tier]

	_register_input()
	_build_environment()
	_build_field()
	_build_collector()
	_spawn_player()
	_spawn_ball()
	_build_dragon()
	_build_goals()
	_build_blender_test_asset()
	_build_sfx()
	if _sfx != null:
		_sfx.call("setup_music")
		if _muted:
			_sfx.call("set_muted", true)
	_build_hud()

	# 手柄泵：暂停时也要能读到 Start，所以单独挂一个常驻进程的节点，
	# 而不是把整个场景改成 PROCESS_MODE_ALWAYS（那会让暂停失效）。
	_pad_pump = Node.new()
	_pad_pump.name = "PadPump"
	_pad_pump.set_script(load("res://scripts/pad_pump.gd") as Script)
	_pad_pump.set("target", self)
	add_child(_pad_pump)

	if arcade:
		order_zone = 1
		if collector != null:
			collector.call("set_order_zone", order_zone)
		_update_order_label()
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
	elif args.has("--fx-test"):
		_automation = true
		call_deferred("_run_fx_test")
	elif args.has("--order-test"):
		_automation = true
		call_deferred("_run_order_test")
	elif args.has("--pad-test"):
		_automation = true
		call_deferred("_run_pad_test")
	elif args.has("--result-test"):
		_automation = true
		call_deferred("_run_result_test")
	elif args.has("--audio-test"):
		_automation = true
		call_deferred("_run_audio_test")
	elif args.has("--super-test"):
		_automation = true
		call_deferred("_run_super_test")
	elif args.has("--progress-test"):
		_automation = true
		call_deferred("_run_progress_test")
	elif args.has("--practice-test"):
		_automation = true
		call_deferred("_run_practice_test")
	elif args.has("--steal-test"):
		_automation = true
		call_deferred("_run_steal_test")
	elif args.has("--tod-test"):
		_automation = true
		call_deferred("_run_tod_test")
	elif args.has("--records-test"):
		_automation = true
		call_deferred("_run_records_test")
	elif args.has("--campaign-test"):
		_automation = true
		call_deferred("_run_campaign_test")
	elif args.has("--counter-test"):
		_automation = true
		call_deferred("_run_counter_test")
	elif args.has("--touch-test"):
		_automation = true
		call_deferred("_run_touch_test")
	elif args.has("--hud-test"):
		_automation = true
		call_deferred("_run_hud_test")
	elif args.has("--stage-boot-test"):
		_automation = true
		call_deferred("_run_stage_boot_test")
	elif args.has("--arena-test"):
		_automation = true
		call_deferred("_run_arena_test")
	elif args.has("--probe-map"):
		_automation = true
		call_deferred("_run_map_probe")
	elif args.has("--demo4"):
		call_deferred("_run_demo4")
	elif args.has("--icon-shot"):
		_automation = true
		call_deferred("_run_icon_shot")
	elif args.has("--demo3"):
		call_deferred("_run_demo3")
	elif _arg_value(args, "--look=") != "":
		_automation = true
		call_deferred("_run_look_probe")
	elif args.has("--demo"):
		# 演示片：脚本化走一遍 标题 / 正午进球 / 黄昏超载 / 夜班 / 结算 / 记录板。
		# 与 --record 的区别：保留 _fx_live（顿帧、镜头抖动、慢放），适合录制宣传素材。
		_automation = true
		_fx_live = DisplayServer.get_name() != "headless"
		call_deferred("_run_demo")
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
	_presentation.connect("stage_requested", _on_stage_requested)
	_presentation.connect("practice_requested", _on_practice_requested)
	_presentation.connect("arcade_requested", _on_arcade_requested)
	if _automation:
		# 自动化（自测/截图/录像）直接开局，不打包场屏与倒计时，保证确定性。
		_round_active = true
		return
	_round_active = false
	_set_play_enabled(false)
	if _boot_stage > 1:
		_keep_stage = true
		stage = clampi(_boot_stage, 1, STAGE_COUNT)
		reset_stage_counters()
		call_deferred("_on_start_requested")
		return
	_presentation.call("show_title", best_score, TIER_NAMES[difficulty_tier],
		challenges_done(), CHALLENGE_LIST.size(), TIME_NAMES[time_of_day])
	if _hud != null:
		_hud.visible = false



## 标题屏“第 N 关”按钮：保留该关的目标计数与计时，直接开局。
func _on_stage_requested(index: int) -> void:
	campaign = true
	practice_mode = 0
	if index <= 1:
		_keep_stage = false
		stage = 1
	else:
		_keep_stage = true
		stage = clampi(index, 1, STAGE_COUNT)
	reset_stage_counters()
	_on_start_requested()


## 标题屏“练习关”按钮：先进第一个练习（定点射门）。
func _on_practice_requested() -> void:
	campaign = true
	start_practice(1)


## 标题屏“刷分模式”按钮。
func _on_arcade_requested() -> void:
	campaign = false
	practice_mode = 0
	_on_start_requested()
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
	# --- 手柄（P0-7）：左摇杆移动 / 右摇杆视角 / RT 蓄力射门 / Start 暂停 / A 确认 ---
	# 只在动作表里补手柄事件，键盘鼠标路径完全不变。
	# 抢球（提案 B）：E 或手柄 X。
	if not InputMap.has_action("retrieve"):
		InputMap.add_action("retrieve")
	InputMap.action_erase_events("retrieve")
	var grab := InputEventKey.new()
	grab.physical_keycode = KEY_E
	InputMap.action_add_event("retrieve", grab)
	_joy_button("retrieve", JOY_BUTTON_X)
	_joy_axis("move_left", JOY_AXIS_LEFT_X, -1.0, 0.25)
	_joy_axis("move_right", JOY_AXIS_LEFT_X, 1.0, 0.25)
	_joy_axis("move_up", JOY_AXIS_LEFT_Y, -1.0, 0.25)
	_joy_axis("move_down", JOY_AXIS_LEFT_Y, 1.0, 0.25)
	_joy_button("sprint", JOY_BUTTON_LEFT_STICK)
	for look_action in ["look_left", "look_right", "look_up", "look_down"]:
		if not InputMap.has_action(look_action):
			InputMap.add_action(look_action)
		InputMap.action_erase_events(look_action)
		InputMap.action_set_deadzone(look_action, 0.18)
	_joy_axis("look_left", JOY_AXIS_RIGHT_X, -1.0, 0.18)
	_joy_axis("look_right", JOY_AXIS_RIGHT_X, 1.0, 0.18)
	_joy_axis("look_up", JOY_AXIS_RIGHT_Y, -1.0, 0.18)
	_joy_axis("look_down", JOY_AXIS_RIGHT_Y, 1.0, 0.18)
	for pad_action in ["shoot", "pad_pause"]:
		if not InputMap.has_action(pad_action):
			InputMap.add_action(pad_action)
		InputMap.action_erase_events(pad_action)
	InputMap.action_set_deadzone("shoot", 0.35)
	_joy_axis("shoot", JOY_AXIS_TRIGGER_RIGHT, 1.0, 0.35)
	_joy_button("pad_pause", JOY_BUTTON_START)


func _joy_axis(action: String, axis: JoyAxis, value: float, deadzone: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	InputMap.action_add_event(action, event)
	InputMap.action_set_deadzone(action, minf(deadzone, 0.9))


func _joy_button(action: String, button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	InputMap.action_add_event(action, event)


func _input(event: InputEvent) -> void:
	if completed and arcade:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_R:
				if campaign and not campaign_done:
					restart_stage()
				else:
					_on_restart_requested()
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_T and practice_mode != 0:
				_exit_practice()
				get_viewport().set_input_as_handled()
		elif event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_A:
			_on_restart_requested()
			get_viewport().set_input_as_handled()
		return
	# 标题屏 / 倒计时阶段：不处理踢球，把输入留给开场 UI。
	if not _round_active:
		# 记录板打开时，只接受 L / Esc 关闭，避免误触开局。
		if _presentation != null and bool(_presentation.call("records_visible")):
			if event is InputEventKey and event.pressed and not event.echo \
					and (event.keycode == KEY_L or event.keycode == KEY_ESCAPE):
				_presentation.call("hide_records")
				get_viewport().set_input_as_handled()
			return
		if event is InputEventKey and event.pressed and not event.echo:
			match event.keycode:
				KEY_0:
					campaign = false
					_on_start_requested()
					get_viewport().set_input_as_handled()
					return
				KEY_L:
					_open_records()
					get_viewport().set_input_as_handled()
					return
				KEY_1:
					set_difficulty_tier(0)
					get_viewport().set_input_as_handled()
					return
				KEY_2:
					set_difficulty_tier(1)
					get_viewport().set_input_as_handled()
					return
				KEY_3:
					set_difficulty_tier(2)
					get_viewport().set_input_as_handled()
					return
				KEY_4:
					start_practice(1)
					get_viewport().set_input_as_handled()
					return
				KEY_5:
					start_practice(2)
					get_viewport().set_input_as_handled()
					return
				KEY_6:
					start_practice(3)
					get_viewport().set_input_as_handled()
					return
				KEY_7:
					set_time_of_day(0)
					get_viewport().set_input_as_handled()
					return
				KEY_8:
					set_time_of_day(1)
					get_viewport().set_input_as_handled()
					return
				KEY_9:
					set_time_of_day(2)
					get_viewport().set_input_as_handled()
					return
		if event is InputEventKey and event.pressed and not event.echo \
				and (event.keycode == KEY_ENTER or event.keycode == KEY_SPACE):
			_on_start_requested()
			get_viewport().set_input_as_handled()
		elif event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_A:
			_on_start_requested()
			get_viewport().set_input_as_handled()
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
	_env = env
	env.background_mode = Environment.BG_SKY
	var sky_material := ProceduralSkyMaterial.new()
	_sky_material = sky_material
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
	_sun = sun
	sun.rotation_degrees = Vector3(-52.0, -34.0, 0.0)
	sun.light_color = Color("#fff0d2")
	sun.light_energy = 0.42
	sun.light_specular = 0.15
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	sun.shadow_enabled = true
	add_child(sun)

	# 冷色轮廓光：把奶龙/门框从背景里剥出来，不参与主光造型。
	var rim := DirectionalLight3D.new()
	_rim = rim
	rim.rotation_degrees = Vector3(28.0, 148.0, 0.0)
	rim.light_color = Color("#8fdbe8")
	rim.light_energy = 0.18
	rim.light_specular = 0.0
	rim.shadow_enabled = false
	add_child(rim)

	var fill := OmniLight3D.new()
	_fill = fill
	fill.position = Vector3(4.0, 7.0, 0.0)
	fill.omni_range = 22.0
	fill.light_color = Color("#cfe9e4")
	fill.light_energy = 0.15
	add_child(fill)

	# 场地顶光：只把地面/球/奶龙提亮，不打船体正立面（避免大面积过曝）。
	var yard_fill := SpotLight3D.new()
	_yard_fill = yard_fill
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
	_graze = graze
	graze.position = Vector3(-16.0, 2.4, -9.0)
	graze.rotation_degrees = Vector3(-8.0, 118.0, 0.0)
	graze.light_color = Color("#ffd9a8")
	graze.light_energy = 0.55
	graze.spot_range = 30.0
	graze.spot_angle = 52.0
	graze.spot_attenuation = 1.1
	graze.shadow_enabled = false
	add_child(graze)
	apply_time_of_day()


## 时段预设：正午 / 黄昏 / 夜班。只改天空、环境光、雾与五层灯光的颜色/能量/角度，
## 不改任何玩法参数；切换在标题屏按 7 / 8 / 9。
func apply_time_of_day() -> void:
	if _sun == null or _env == null or _sky_material == null:
		return
	match time_of_day:
		1:
			_sky_material.sky_top_color = Color("#3a2b52")
			_sky_material.sky_horizon_color = Color("#e3a273")
			_sky_material.ground_bottom_color = Color("#4a3b3a")
			_sky_material.ground_horizon_color = Color("#8a6a55")
			_env.ambient_light_color = Color("#f4c9a4")
			_env.ambient_light_energy = 0.30
			_env.fog_light_color = Color("#d9a98f")
			_env.fog_density = 0.0062
			_sun.light_color = Color("#ffb27a")
			_sun.light_energy = 0.52
			_sun.rotation_degrees = Vector3(-24.0, -62.0, 0.0)
			_rim.light_color = Color("#7fb0d8")
			_rim.light_energy = 0.24
			_fill.light_color = Color("#f0c0a0")
			_fill.light_energy = 0.18
			_yard_fill.light_color = Color("#f6d2b0")
			_yard_fill.light_energy = 0.85
			_graze.light_color = Color("#ffbe73")
			_graze.light_energy = 0.70
		2:
			_sky_material.sky_top_color = Color("#060d1a")
			_sky_material.sky_horizon_color = Color("#16283c")
			_sky_material.ground_bottom_color = Color("#05090e")
			_sky_material.ground_horizon_color = Color("#101a24")
			_env.ambient_light_color = Color("#8fb0d8")
			_env.ambient_light_energy = 0.22
			_env.fog_light_color = Color("#1d2c3c")
			_env.fog_density = 0.0080
			_env.glow_intensity = 0.85
			_sun.light_color = Color("#a9c6ff")
			_sun.light_energy = 0.30
			_sun.rotation_degrees = Vector3(-40.0, 24.0, 0.0)
			_rim.light_color = Color("#6fe0ff")
			_rim.light_energy = 0.32
			_fill.light_color = Color("#7ea8c8")
			_fill.light_energy = 0.10
			_yard_fill.light_color = Color("#9fc4ff")
			_yard_fill.light_energy = 0.55
			_graze.light_color = Color("#7fd0ff")
			_graze.light_energy = 0.35
		_:
			_sky_material.sky_top_color = Color("#2c5a76")
			_sky_material.sky_horizon_color = Color("#b4d2d6")
			_sky_material.ground_bottom_color = Color("#6f7f78")
			_sky_material.ground_horizon_color = Color("#9db1aa")
			_env.ambient_light_color = Color("#e6f0f2")
			_env.ambient_light_energy = 0.24
			_env.fog_light_color = Color("#c2d2d0")
			_env.fog_density = 0.0045
			_env.glow_intensity = 0.55
			_sun.light_color = Color("#fff0d2")
			_sun.light_energy = 0.42
			_sun.rotation_degrees = Vector3(-52.0, -34.0, 0.0)
			_rim.light_color = Color("#8fdbe8")
			_rim.light_energy = 0.18
			_fill.light_color = Color("#cfe9e4")
			_fill.light_energy = 0.15
			_yard_fill.light_color = Color("#dfeef0")
			_yard_fill.light_energy = 1.2
			_graze.light_color = Color("#ffd9a8")
			_graze.light_energy = 0.55


func set_time_of_day(index: int) -> void:
	time_of_day = clampi(index, 0, TIME_NAMES.size() - 1)
	apply_time_of_day()
	if _presentation != null:
		_presentation.call("set_time_label", TIME_NAMES[time_of_day])
	_flash("时段：%s" % TIME_NAMES[time_of_day], 1.2)


## 每一关的必达目标。第 2 关强制“高台/坑底进球”，第 3 关强制订单 + 超载。
func orders_enabled() -> bool:
	# 通关模式只留核心动作；订单层与必杀槽放进练习关/刷分模式，避免规则叠太多。
	return practice_mode != 0 or not campaign


## 六关 = 三个场景（正午/黄昏/夜班）× 两种规则（基础 / 侧风+高台刷球）。

## 三个场地 = 同一张大地图上的三个射门区：正门平地 / 北侧货台 / 维修坑。
## 只改玩家出生点、朝向和球的重生区，不改守门员、判定与物理。
func arena_spawn(arena: int) -> Dictionary:
	match arena:
		1:
			return {"pos": Vector3(46.0, 0.02, 0.0), "look": Vector3(68.0, 1.0, 0.0)}
		2:
			return {"pos": Vector3(46.0, 0.02, 26.0), "look": Vector3(68.0, 1.0, 26.0)}
		_:
			return {"pos": SPAWN, "look": Vector3(12.0, 1.2, 0.0)}


func arena_ball_spots(arena: int) -> Array:
	match arena:
		1:
			return [Vector3(48.0, 0.0, 0.0), Vector3(50.0, 0.0, 2.5), Vector3(50.0, 0.0, -2.5)]
		2:
			return [Vector3(48.0, 0.0, 26.0), Vector3(50.0, 0.0, 28.5), Vector3(50.0, 0.0, 23.5)]
		_:
			return BALL_SPOTS


func current_arena() -> int:
	return int(stage_config(stage)["arena"])
func stage_config(index: int) -> Dictionary:
	match index:
		1:
			return {"goals": 2, "time": 0, "wind": false, "high_only": false, "name": "正门装卸场 · 正午", "arena": 0}
		2:
			return {"goals": 3, "time": 1, "wind": false, "high_only": true, "name": "北场 · 黄昏", "arena": 1}
		3:
			return {"goals": 3, "time": 2, "wind": false, "high_only": false, "name": "南场 · 夜班", "arena": 2}
		4:
			return {"goals": 3, "time": 0, "wind": true, "high_only": false, "name": "正门装卸场 · 侧风正午", "arena": 0}
		5:
			return {"goals": 4, "time": 1, "wind": true, "high_only": true, "name": "北场 · 侧风黄昏", "arena": 1}
		_:
			return {"goals": 4, "time": 2, "wind": true, "high_only": false, "name": "南场 · 侧风夜班", "arena": 2}


func stage_targets() -> Dictionary:
	var cfg := stage_config(stage)
	return {"goals": int(cfg["goals"]), "high": 0, "order": 0, "overload": 0}


func stage_desc() -> String:
	var cfg := stage_config(stage)
	return "%s　进 %d 球" % [str(cfg["name"]), int(cfg["goals"])]


## 每一关的球重生点：第 2 关只在高台/坑底重生，逼玩家把整张地图跑起来。
func stage_ball_spots() -> Array:
	if not campaign:
		return BALL_SPOTS
	return arena_ball_spots(current_arena())
	return BALL_SPOTS



## 每关的场景：时段/侧风开关。玩法只有“进球数”，场景负责变化。

## 第二、三张图的便携装货口（map1 北场 / map2 南场）。
func _build_goals() -> void:
	# 三张图的三个门：0 = 飞船装货口，1/2 = 场外便携门（见 _build_extra_arenas）。
	_goals = [collector]
	_build_extra_arenas()
	_build_corridors()
	for index in range(_goals.size()):
		if index != 0:
			_goals[index].set("active", false)

## 三块场地之间的连廊：地面 + 两侧护栏 + 灯带，带碰撞，玩家可以真的走过去。
## 路线：主装卸场东侧 (22,0) → 北场西缘 (43,0)；北场南缘 (56,9.4) → 南场北缘 (56,16.6)。
func _build_corridors() -> void:
	_build_corridor(Vector3(21.0, 0.0, 0.0), Vector3(43.5, 0.0, 0.0), 5.2, "CorridorAB", "res://assets/textures/signs/sign_to_north.png")
	_build_corridor(Vector3(56.0, 0.0, 8.4), Vector3(56.0, 0.0, 17.6), 5.4, "CorridorBC", "res://assets/textures/signs/sign_to_south.png")


func _build_corridor(from: Vector3, to: Vector3, width: float, tag: String, sign_path: String = "") -> void:
	var pivot := Node3D.new()
	pivot.name = tag
	var delta := to - from
	var length := Vector2(delta.x, delta.z).length()
	pivot.position = (from + to) * 0.5
	pivot.rotation.y = atan2(-delta.x, -delta.z)
	add_child(pivot)

	if _arena_kit == null:
		_arena_kit = load("res://scripts/gulu_art_kit.gd").new()
	var concrete := _arena_kit.concrete(Color("#8f8778"), 0.9, 107)
	var steel := _arena_kit.dark_metal(Color("#2f4a4c"), 0.6, 108)
	var accent := StandardMaterial3D.new()
	accent.albedo_color = Color("#ffcf5c")
	accent.emission_enabled = true
	accent.emission = Color("#ffcf5c")
	accent.emission_energy_multiplier = 0.7

	# 地面板（顶面 y≈0.02）
	var pad := MeshInstance3D.new()
	var pad_mesh := BoxMesh.new()
	pad_mesh.size = Vector3(width, 0.30, length)
	pad.mesh = pad_mesh
	pad.material_override = concrete
	pad.position = Vector3(0.0, -0.13, 0.0)
	pivot.add_child(pad)
	var body := StaticBody3D.new()
	body.position = pad.position
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, 0.30, length)
	shape.shape = box
	body.add_child(shape)
	pivot.add_child(body)

	# 两侧护栏（带碰撞，防止掉下去）
	for side in [-1.0, 1.0]:
		var rail := MeshInstance3D.new()
		var rail_mesh := BoxMesh.new()
		rail_mesh.size = Vector3(0.18, 1.05, length)
		rail.mesh = rail_mesh
		rail.material_override = steel
		rail.position = Vector3(side * (width * 0.5 - 0.09), 0.52, 0.0)
		pivot.add_child(rail)
		var rail_body := StaticBody3D.new()
		rail_body.position = rail.position
		var rail_shape := CollisionShape3D.new()
		var rail_box := BoxShape3D.new()
		rail_box.size = Vector3(0.18, 1.05, length)
		rail_shape.shape = rail_box
		rail_body.add_child(rail_shape)
		pivot.add_child(rail_body)
		# 灯带
		var strip := MeshInstance3D.new()
		var strip_mesh := BoxMesh.new()
		strip_mesh.size = Vector3(0.10, 0.06, length - 0.6)
		strip.mesh = strip_mesh
		strip.material_override = accent
		strip.position = Vector3(side * (width * 0.5 - 0.09), 1.08, 0.0)
		pivot.add_child(strip)


	# 入口指路牌（朝向主场景一侧）
	if sign_path != "" and ResourceLoader.exists(sign_path):
		var tex := load(sign_path) as Texture2D
		var sign_mat := StandardMaterial3D.new()
		sign_mat.albedo_texture = tex
		sign_mat.emission_enabled = true
		sign_mat.emission_texture = tex
		sign_mat.emission_energy_multiplier = 0.6
		sign_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var board := MeshInstance3D.new()
		var board_mesh := BoxMesh.new()
		board_mesh.size = Vector3(2.4, 1.20, 0.10)
		board.mesh = board_mesh
		board.material_override = sign_mat
		board.position = Vector3(0.0, 2.55, length * 0.5 - 0.35)
		pivot.add_child(board)
		var post := MeshInstance3D.new()
		var post_mesh := CylinderMesh.new()
		post_mesh.top_radius = 0.07
		post_mesh.bottom_radius = 0.09
		post_mesh.height = 2.3
		post.mesh = post_mesh
		post.material_override = steel
		post.position = Vector3(0.0, 1.15, length * 0.5 - 0.35)
		pivot.add_child(post)	# 顶棚：把走廊盖起来，既遮住主场景上方的岩石，也像真正的货运通道
	var roof := MeshInstance3D.new()
	var roof_mesh := BoxMesh.new()
	roof_mesh.size = Vector3(width + 0.4, 0.18, length)
	roof.mesh = roof_mesh
	roof.material_override = steel
	roof.position = Vector3(0.0, 4.15, 0.0)
	pivot.add_child(roof)
	var roof_body := StaticBody3D.new()
	roof_body.position = roof.position
	var roof_shape := CollisionShape3D.new()
	var roof_box := BoxShape3D.new()
	roof_box.size = roof_mesh.size
	roof_shape.shape = roof_box
	roof_body.add_child(roof_shape)
	pivot.add_child(roof_body)
	# 支撑柱（每 ~7 m 一对）
	var bays := maxi(1, int(length / 7.0))
	for i in range(bays + 1):
		var t := float(i) / float(bays)
		var z := lerpf(-length * 0.5 + 0.6, length * 0.5 - 0.6, t)
		for side in [-1.0, 1.0]:
			var column := MeshInstance3D.new()
			var col_mesh := BoxMesh.new()
			col_mesh.size = Vector3(0.22, 4.15, 0.22)
			column.mesh = col_mesh
			column.material_override = steel
			column.position = Vector3(side * (width * 0.5 - 0.2), 2.07, z)
			pivot.add_child(column)

	# 横跨管束（越高越好，别挡人）+ 地面警示条
	var pipe_mat := _arena_kit.bare_metal(Color("#8b979b"), 0.34, 109)
	var bays2 := maxi(1, int(length / 10.0))
	for i in range(bays2 + 1):
		var t2 := float(i) / float(bays2)
		var zp := lerpf(-length * 0.5 + 3.0, length * 0.5 - 3.0, t2)
		for k in range(3):
			var pipe := MeshInstance3D.new()
			var pipe_mesh := CylinderMesh.new()
			pipe_mesh.top_radius = 0.11
			pipe_mesh.bottom_radius = 0.11
			pipe_mesh.height = width + 0.2
			pipe.mesh = pipe_mesh
			pipe.material_override = pipe_mat
			pipe.rotation.z = PI * 0.5
			pipe.position = Vector3(0.0, 2.45 + k * 0.26, zp)
			pivot.add_child(pipe)
	var warn := StandardMaterial3D.new()
	warn.albedo_color = Color("#ffcf5c")
	warn.emission_enabled = true
	warn.emission = Color("#ffcf5c")
	warn.emission_energy_multiplier = 0.35
	for i in range(2):
		var strip2 := MeshInstance3D.new()
		var smesh2 := BoxMesh.new()
		smesh2.size = Vector3(width - 0.5, 0.02, 0.22)
		strip2.mesh = smesh2
		strip2.material_override = warn
		strip2.position = Vector3(0.0, 0.03, -length * 0.25 + i * length * 0.5)
		pivot.add_child(strip2)
	# 每隔 9 m 一盏灯
	var count := maxi(1, int(length / 9.0))
	for i in range(count + 1):
		var t := 0.0 if count == 0 else float(i) / float(count)
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(0.0, 3.2, lerpf(-length * 0.5, length * 0.5, t))
		lamp.light_color = Color("#ffd9a0")
		lamp.light_energy = 1.2
		lamp.omni_range = 12.0
		pivot.add_child(lamp)
func _build_extra_arenas() -> void:
	var specs := [
		{"center": Vector3(56.0, 0.0, 0.0), "name": "ArenaB", "half_width": 1.45},
		{"center": Vector3(56.0, 0.0, 26.0), "name": "ArenaC", "half_width": 2.2},
	]
	for spec in specs:
		var center: Vector3 = spec["center"] as Vector3
		var tag := str(spec["name"])
		_build_arena_floor(center, tag)
		_dress_arena(center, tag)
		var goal := load("res://scripts/cargo_goal.gd").new() as Node3D
		goal.name = "Goal" + tag
		if spec.has("half_width"):
			goal.set("half_width", float(spec["half_width"]))
		goal.set("accent", Color("#ffcf5c") if tag.ends_with("B") else Color("#7dffd4"))
		goal.set("materials", _arena_materials())
		goal.set("sign_path", "res://assets/textures/signs/sign_%s.png" % ("north" if tag.ends_with("B") else "south"))
		goal.position = center + Vector3(12.0, 0.0, 0.0)
		add_child(goal)
		goal.call("setup_ball", ball)
		goal.connect("fuel_collected", _on_goal_scored)
		goal.set("active", false)
		_goals.append(goal)



## 场外场地的 GLB 资产材质：和主场景一样按材质名覆盖，顶点遮罩才会生效
## （否则 GLB 自带的 PBR 材质会被顶点色/环境压成怪色）。
func _arena_materials() -> Dictionary:
	if not _arena_mats.is_empty():
		return _arena_mats
	if _arena_kit == null:
		_arena_kit = load("res://scripts/gulu_art_kit.gd").new()
	var cream := (_arena_kit.paint(Color("#cfc5ae"), 0.50, 0.10, 1.05, 301.0) as ShaderMaterial).duplicate() as ShaderMaterial
	var yellow := (_arena_kit.paint(Color("#cc8f17"), 0.48, 0.08, 1.15, 302.0) as ShaderMaterial).duplicate() as ShaderMaterial
	var orange := (_arena_kit.paint(Color("#b24510"), 0.48, 0.10, 1.15, 303.0) as ShaderMaterial).duplicate() as ShaderMaterial
	var deep := (_arena_kit.dark_metal(Color("#2b3937"), 0.58, 304.0) as ShaderMaterial).duplicate() as ShaderMaterial
	var bare := (_arena_kit.bare_metal(Color("#8b979b"), 0.34, 305.0) as ShaderMaterial).duplicate() as ShaderMaterial
	var rubber := _arena_kit.rubber(Color("#20282a"))
	for m in [cream, yellow, orange, deep, bare]:
		(m as ShaderMaterial).set_shader_parameter("vertex_mask_valid", true)
	_arena_mats = {
		"M_PaintCream": cream, "M_PaintYellow": yellow, "M_PaintOrange": orange,
		"M_SteelDeep": deep, "M_BareSteel": bare, "M_Rubber": rubber,
	}
	return _arena_mats


## 放置一个带材质覆盖的 GLB（场外场地用）。
func _add_arena_model(res: PackedScene, at: Vector3, yaw: float) -> Node3D:
	var mats := _arena_materials()
	var root := res.instantiate() as Node3D
	root.position = at
	root.rotation.y = yaw
	add_child(root)
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in range(mi.mesh.get_surface_count()):
			var src := mi.mesh.surface_get_material(s)
			if src != null and mats.has(src.resource_name):
				mi.set_surface_override_material(s, mats[src.resource_name])
	return root

## 单段围挡（网格 + 碰撞），供带门洞的墙使用。
func _add_arena_wall_piece(center: Vector3, local_pos: Vector3, size: Vector3, material: Material) -> void:
	var wall := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	wall.mesh = mesh
	wall.material_override = material
	wall.position = center + local_pos
	add_child(wall)
	var body := StaticBody3D.new()
	body.position = wall.position
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)
func _build_arena_floor(center: Vector3, tag: String) -> void:
	if _arena_kit == null:
		_arena_kit = load("res://scripts/gulu_art_kit.gd").new()
	# 与主场景同一套材质族：地面用混凝土、围挡用深色金属，避免“塑料盒子”感。
	var concrete := _arena_kit.concrete(Color("#8f8778"), 0.9, 105)
	var wall_mat := _arena_kit.dark_metal(Color("#2f4a4c"), 0.6, 106)
	# 地面（网格 + 碰撞）
	var pad := MeshInstance3D.new()
	var pad_mesh := BoxMesh.new()
	pad_mesh.size = Vector3(26.0, 0.4, 18.0)
	pad.mesh = pad_mesh
	pad.material_override = concrete
	pad.position = center + Vector3(0.0, -0.2, 0.0)
	add_child(pad)
	var body := StaticBody3D.new()
	body.name = "Body" + tag
	body.position = pad.position
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(26.0, 0.4, 18.0)
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	# 三面围挡（后墙 x=+13，两侧 z=±9）；连廊所在的墙留门洞。
	for spec in [
		{"pos": Vector3(13.0, 1.5, 0.0), "size": Vector3(0.6, 3.0, 18.0)},
		{"pos": Vector3(0.0, 1.5, 9.0), "size": Vector3(26.0, 3.0, 0.6)},
		{"pos": Vector3(0.0, 1.5, -9.0), "size": Vector3(26.0, 3.0, 0.6)},
	]:
		var wpos: Vector3 = spec["pos"] as Vector3
		var wsize: Vector3 = spec["size"] as Vector3
		var doorway := (tag == "ArenaB" and wpos.z > 8.0) or (tag == "ArenaC" and wpos.z < -8.0)
		if doorway:
			# 留 5.6 m 宽的门洞，接上连廊；上方补一道门楣。
			var half_side := (26.0 - 5.6) * 0.5
			_add_arena_wall_piece(center, Vector3(wpos.x - half_side - 2.8, wpos.y, wpos.z), Vector3(half_side, wsize.y, wsize.z), wall_mat)
			_add_arena_wall_piece(center, Vector3(wpos.x + half_side + 2.8, wpos.y, wpos.z), Vector3(half_side, wsize.y, wsize.z), wall_mat)
			_add_arena_wall_piece(center, Vector3(wpos.x, 3.15, wpos.z), Vector3(5.8, 0.5, wsize.z), wall_mat)
		else:
			_add_arena_wall_piece(center, wpos, wsize, wall_mat)
	# 外围地皮（避免看起来像悬空平台）
	var apron := MeshInstance3D.new()
	var apron_mesh := BoxMesh.new()
	apron_mesh.size = Vector3(120.0, 0.2, 90.0)
	apron.mesh = apron_mesh
	var dirt := StandardMaterial3D.new()
	dirt.albedo_color = Color("#6f6a5c")
	dirt.roughness = 0.95
	apron.material_override = dirt
	apron.position = center + Vector3(0.0, -0.32, 0.0)
	add_child(apron)
	# 两侧货箱与地面导引条
	var crate_mat := StandardMaterial3D.new()
	crate_mat.albedo_color = Color("#a8834f")
	crate_mat.roughness = 0.7
	for index in range(3):
		var z: float = -6.0 + index * 6.0
		for side in [-1.0, 1.0]:
			var crate := MeshInstance3D.new()
			var crate_mesh := BoxMesh.new()
			crate_mesh.size = Vector3(1.6, 1.6, 1.6)
			crate.mesh = crate_mesh
			crate.material_override = crate_mat
			crate.position = center + Vector3(-9.0 + fmod(index * 3.0, 4.0), 0.8, side * 7.6)
			add_child(crate)
			var crate_body := StaticBody3D.new()
			crate_body.position = crate.position
			var crate_shape := CollisionShape3D.new()
			var crate_box := BoxShape3D.new()
			crate_box.size = Vector3(1.6, 1.6, 1.6)
			crate_shape.shape = crate_box
			crate_body.add_child(crate_shape)
			add_child(crate_body)
	var stripe := StandardMaterial3D.new()
	stripe.albedo_color = Color("#ffcf5c")
	stripe.emission_enabled = true
	stripe.emission = Color("#ffcf5c")
	stripe.emission_energy_multiplier = 0.35
	for z in [-3.0, 0.0, 3.0]:
		var line := MeshInstance3D.new()
		var line_mesh := BoxMesh.new()
		line_mesh.size = Vector3(14.0, 0.02, 0.12)
		line.mesh = line_mesh
		line.material_override = stripe
		line.position = center + Vector3(-2.0, 0.02, z)
		add_child(line)

	# 门口泛光（夜间图靠它照亮守门员与门楣）
	var goal_light := OmniLight3D.new()
	goal_light.position = center + Vector3(8.0, 4.2, 0.0)
	goal_light.light_color = Color("#eaf6ff")
	goal_light.light_energy = 2.2 if tag.ends_with("B") else 3.4
	goal_light.omni_range = 22.0
	add_child(goal_light)

	# 两盏灯
	for side in [-1.0, 1.0]:
		_add_arena_model(ARENA_TOWER, center + Vector3(7.4, 0.0, side * 8.4), 0.0 if side > 0.0 else PI)
		var lamp := OmniLight3D.new()
		lamp.position = center + Vector3(-11.0, 4.8, side * 8.0)
		lamp.light_color = Color("#ffd9a0")
		lamp.light_energy = 1.8
		lamp.omni_range = 24.0
		add_child(lamp)


## 给场外两张图补“物流场地”细节：集装箱堆、管线、碎石、墙面警示条、门头横梁。
## 纯视觉（与主场景装饰一致，不加碰撞），避免改变球路。
func _dress_arena(center: Vector3, tag: String) -> void:
	var warm := tag.ends_with("B")
	var accent := Color("#ffcf5c") if warm else Color("#7dffd4")
	var accent_mat := StandardMaterial3D.new()
	accent_mat.albedo_color = accent
	accent_mat.emission_enabled = true
	accent_mat.emission = accent
	accent_mat.emission_energy_multiplier = 0.6
	var crate_mat := StandardMaterial3D.new()
	crate_mat.albedo_color = Color("#a8834f") if warm else Color("#5f7d86")
	crate_mat.roughness = 0.72
	var rust := StandardMaterial3D.new()
	rust.albedo_color = Color("#7a5a3c")
	rust.roughness = 0.85
	var rock := StandardMaterial3D.new()
	rock.albedo_color = Color("#8b8274")
	rock.roughness = 0.95

	# 后场集装箱堆（错位两层）
	for index in range(3):
		var scene := ARENA_CONTAINER_A if index != 1 else ARENA_CONTAINER_B
		var z_wall := 7.9 if tag.ends_with("C") else -7.9
		_add_arena_model(scene, center + Vector3(3.8 - index * 3.7, 0.0, z_wall), 0.03 * (index - 1))
	# 侧墙管线：两条贴地管道 + 支架
	for index in range(2):
		var pipe := MeshInstance3D.new()
		var pipe_mesh := CylinderMesh.new()
		pipe_mesh.top_radius = 0.22
		pipe_mesh.bottom_radius = 0.22
		pipe_mesh.height = 17.0
		pipe.mesh = pipe_mesh
		pipe.material_override = rust
		pipe.rotation.z = PI * 0.5
		pipe.position = center + Vector3(-2.0 + index * 1.0, 0.45 + index * 0.2, -8.4)
		add_child(pipe)
		for brace in range(4):
			var bracket := MeshInstance3D.new()
			var bmesh := BoxMesh.new()
			bmesh.size = Vector3(0.18, 0.6, 0.18)
			bracket.mesh = bmesh
			bracket.material_override = rust
			bracket.position = center + Vector3(-6.0 + brace * 4.0, 0.3, -8.4)
			add_child(bracket)
	# 地面碎石（小方块随机摆，固定种子）
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261126 + int(center.z)
	for index in range(14):
		var stone := MeshInstance3D.new()
		var smesh := BoxMesh.new()
		var s := rng.randf_range(0.18, 0.42)
		smesh.size = Vector3(s, s * 0.7, s * 1.2)
		stone.mesh = smesh
		stone.material_override = rock
		stone.position = center + Vector3(rng.randf_range(-11.0, 11.0), 0.06, rng.randf_range(-8.0, 8.0))
		stone.rotation.y = rng.randf_range(0.0, TAU)
		add_child(stone)
	# 两侧墙面警示条
	for side in [-1.0, 1.0]:
		for index in range(3):
			var strip := MeshInstance3D.new()
			var stmesh := BoxMesh.new()
			stmesh.size = Vector3(3.0, 0.18, 0.06)
			strip.mesh = stmesh
			strip.material_override = accent_mat
			strip.position = center + Vector3(-8.0 + index * 8.0, 1.3, side * 8.85)
			add_child(strip)
	# 门头横梁 + 门楣标识
	var beam := MeshInstance3D.new()
	var bmesh2 := BoxMesh.new()
	bmesh2.size = Vector3(0.5, 0.5, 19.0)
	beam.mesh = bmesh2
	beam.material_override = rust
	beam.position = center + Vector3(12.4, 3.4, 0.0)
	add_child(beam)
	var plate := MeshInstance3D.new()
	var pmesh := BoxMesh.new()
	pmesh.size = Vector3(0.12, 0.7, 3.2)
	plate.mesh = pmesh
	plate.material_override = accent_mat
	plate.position = center + Vector3(12.1, 2.55, 0.0)
	add_child(plate)
	# 隔离墩（两侧）+ 门槛踏板 + 头顶龙门架
	var barrier_mat := StandardMaterial3D.new()
	barrier_mat.albedo_color = Color("#cfc5ae")
	barrier_mat.roughness = 0.8
	for index in range(4):
		for side in [-1.0, 1.0]:
			var barrier := MeshInstance3D.new()
			var bmesh3 := BoxMesh.new()
			bmesh3.size = Vector3(1.7, 0.85, 0.5)
			barrier.mesh = bmesh3
			barrier.material_override = barrier_mat
			barrier.position = center + Vector3(-6.0 + index * 3.6, 0.42, side * 8.3)
			add_child(barrier)
			var stripe := MeshInstance3D.new()
			var smesh2 := BoxMesh.new()
			smesh2.size = Vector3(1.7, 0.14, 0.52)
			stripe.mesh = smesh2
			stripe.material_override = accent_mat
			stripe.position = barrier.position + Vector3(0.0, 0.24, 0.0)
			add_child(stripe)
	var threshold := MeshInstance3D.new()
	var tmesh := BoxMesh.new()
	tmesh.size = Vector3(1.4, 0.05, 5.4)
	threshold.mesh = tmesh
	threshold.material_override = accent_mat
	threshold.position = center + Vector3(11.6, 0.03, 0.0)
	add_child(threshold)
	var gantry := MeshInstance3D.new()
	var gmesh := BoxMesh.new()
	gmesh.size = Vector3(0.45, 0.45, 18.0)
	gantry.mesh = gmesh
	gantry.material_override = rust
	gantry.position = center + Vector3(5.5, 4.6, 0.0)
	add_child(gantry)
	# 夜班图补顶部填充光，保证守门员和门框可读
	if not warm:
		for offset in [Vector3(-8.0, 6.0, 0.0), Vector3(1.0, 6.0, 0.0), Vector3(10.0, 6.0, 0.0)]:
			var fill := OmniLight3D.new()
			fill.position = center + (offset as Vector3)
			fill.light_color = Color("#cfe6ff")
			fill.light_energy = 1.2
			fill.omni_range = 20.0
			add_child(fill)
	for side in [-1.0, 1.0]:
		var column := MeshInstance3D.new()
		var cmesh := BoxMesh.new()
		cmesh.size = Vector3(0.35, 4.6, 0.35)
		column.mesh = cmesh
		column.material_override = rust
		column.position = center + Vector3(5.5, 2.3, side * 8.6)
		add_child(column)
	# 生活痕迹：托盘、锥桶、防水布、地面油渍
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("#8a6a3f")
	wood.roughness = 0.82
	for index in range(2):
		for side in [-1.0, 1.0]:
			var pallet := MeshInstance3D.new()
			var pmesh2 := BoxMesh.new()
			pmesh2.size = Vector3(1.25, 0.16, 1.05)
			pallet.mesh = pmesh2
			pallet.material_override = wood
			pallet.position = center + Vector3(-1.5 - index * 1.6, 0.08, side * 6.6)
			pallet.rotation.y = 0.12 * index
			add_child(pallet)
			var stack := MeshInstance3D.new()
			var smesh3 := BoxMesh.new()
			smesh3.size = Vector3(1.15, 0.55, 0.95)
			stack.mesh = smesh3
			stack.material_override = crate_mat
			stack.position = pallet.position + Vector3(0.0, 0.42, 0.0)
			add_child(stack)
	var cone_mat := StandardMaterial3D.new()
	cone_mat.albedo_color = Color("#d9702a")
	cone_mat.roughness = 0.7
	for index in range(4):
		var cone := MeshInstance3D.new()
		var cmesh2 := CylinderMesh.new()
		cmesh2.top_radius = 0.03
		cmesh2.bottom_radius = 0.20
		cmesh2.height = 0.62
		cone.mesh = cmesh2
		cone.material_override = cone_mat
		var cx := -4.0 + index * 2.6
		cone.position = center + Vector3(cx, 0.31, 4.2)
		add_child(cone)
		var base := MeshInstance3D.new()
		var bmesh4 := BoxMesh.new()
		bmesh4.size = Vector3(0.5, 0.05, 0.5)
		base.mesh = bmesh4
		base.material_override = cone_mat
		base.position = center + Vector3(cx, 0.03, 4.2)
		add_child(base)
	var tarp := StandardMaterial3D.new()
	tarp.albedo_color = Color("#2f4f5a")
	tarp.roughness = 0.9
	for index in range(2):
		var sheet := MeshInstance3D.new()
		var tmesh2 := BoxMesh.new()
		tmesh2.size = Vector3(2.2, 0.06, 1.6)
		sheet.mesh = tmesh2
		sheet.material_override = tarp
		sheet.position = center + Vector3(2.6 - index * 2.0, 1.86, 7.2)
		sheet.rotation.x = 0.06
		sheet.rotation.z = -0.04
		add_child(sheet)


## 进图提示：地图名 + 目标，1.6 秒淡出。只在换图/开局时出现，不干扰操作。
func _show_map_card(title: String, subtitle: String) -> void:
	if _map_card == null:
		return
	_map_card.text = "%s\n%s" % [title, subtitle]
	_map_card.modulate = Color(1, 1, 1, 0)
	_map_card.visible = true
	var tween := create_tween()
	tween.tween_property(_map_card, "modulate:a", 1.0, 0.18)
	tween.tween_interval(1.1)
	tween.tween_property(_map_card, "modulate:a", 0.0, 0.35)
	tween.tween_callback(func() -> void: _map_card.visible = false)

func _apply_active_map(map_index: int) -> void:
	_active_map = 0 if _goals.size() <= 1 else clampi(map_index, 0, _goals.size() - 1)
	if ball != null:
		ball.set("limit_x", 50.0 if _active_map == 0 else 82.0)
		ball.set("limit_z", 34.0 if _active_map == 0 else 40.0)
	for index in range(_goals.size()):
		var node: Node = _goals[index]
		node.set("active", index == _active_map)
	var previous_map := _active_map
	var goal_node: Node = _goals[_active_map]
	var center := Vector3(12.45, 0.0, 0.0)
	if goal_node.has_method("gate_center"):
		center = goal_node.call("gate_center") as Vector3
	dragon.call("setup_goal", goal_node)
	dragon.set("goal_center", center)
	dragon.set("home", Vector3(center.x - 2.25, center.y, center.z))
	dragon.set("zone_min_x", center.x - 4.0)
	dragon.set("zone_max_x", center.x - 1.0)
	dragon.set("zone_half_z", 2.4 if _active_map == 1 else 3.2)
	_wind_strength = 1.0 if _active_map == 0 else (1.25 if _active_map == 1 else 1.55)
	_wind_period = 1.0 if _active_map == 0 else (0.85 if _active_map == 1 else 0.7)
	if _active_map == 1:
		dragon.set("walk_speed", 1.75)
		dragon.set("charge_speed", 2.3)
		dragon.set("intercept_cooldown", 2.0)
	elif _active_map == 2:
		# 南场宽门：守门员更积极出击，逼玩家打节奏而不是找角度
		dragon.set("walk_speed", 2.0)
		dragon.set("charge_speed", 2.9)
		dragon.set("intercept_cooldown", 1.7)
	dragon.call("reset_to_home")
	if _sfx != null:
		match _active_map:
			0:
				_sfx.call("play_ambience", 0.8, -26.0)
			1:
				_sfx.call("play_ambience", 1.05, -20.0)
			_:
				_sfx.call("play_ambience", 0.62, -22.0)
	if previous_map != _active_map or not _map_card_shown:
		_map_card_shown = true
		_show_map_card(str(stage_config(stage)["name"]), "目标 %d 球" % int(stage_config(stage)["goals"]))
	if ball != null:
		if goal_node.has_method("watch_ball"):
			goal_node.call("watch_ball", ball)
		else:
			goal_node.call("setup_ball", ball)
func _apply_stage_scene() -> void:
	var cfg := stage_config(stage)
	if stage == 1:
		_flash("左键按住蓄力，松手射门" + char(10) + "球在滚动时可以从更远处抽射", 3.2)
	_apply_active_map(current_arena())
	set_time_of_day(int(cfg["time"]))
	var use_wind := bool(cfg["wind"])
	wind_enabled = use_wind
	if use_wind:
		_wind_next = 2.5
	else:
		_clear_wind()
		_wind_next = 999.0
	_update_stage_label()
func reset_stage_counters() -> void:
	stage_goals = 0
	stage_order_hits = 0
	stage_high_goals = 0
	stage_overloads = 0


func _check_stage_complete() -> void:
	if not campaign or completed or practice_mode != 0:
		return
	var targets := stage_targets()
	if stage_goals < int(targets["goals"]):
		return
	if stage_high_goals < int(targets["high"]):
		return
	if stage_order_hits < int(targets["order"]):
		return
	if stage_overloads < int(targets["overload"]):
		return
	if travel_enabled and stage < STAGE_COUNT:
		_begin_travel()
	else:
		_advance_stage()



## 清关后进入“赶路”状态：计时暂停，HUD 指向下一块场地；玩家走进目标区才开始下一关。
func _begin_travel() -> void:
	_travel_pending = true
	var next_stage := stage + 1
	var spawn := arena_spawn(int(stage_config(next_stage)["arena"]))
	_travel_target = spawn["pos"] as Vector3
	if ball != null:
		ball.visible = false
	_stage_hud_left = 6.0
	_flash("第 %d 关完成！%s走，前往%s" % [stage, _compass_hint(_travel_target), str(stage_config(next_stage)["name"])], 3.6)
	_update_stage_label()



## 把“往哪走”翻成中文方位（北 = -z，东 = +x），赶路提示用。
func _compass_hint(target: Vector3) -> String:
	if player == null:
		return ""
	var d := target - player.global_position
	d.y = 0.0
	if d.length() < 2.0:
		return ""
	var deg := rad_to_deg(atan2(d.x, -d.z))
	if deg < 0.0:
		deg += 360.0
	var dirs := ["北", "东北", "东", "东南", "南", "西南", "西", "西北"]
	var index := int(round(deg / 45.0)) % 8
	return "往%s方向" % dirs[index]

## 赶路 HUD：显示目的地、方位和剩余距离，玩家不用瞎找连廊。
func _update_travel_hud() -> void:
	if _travel_label == null:
		return
	if not _travel_pending or player == null:
		_travel_label.visible = false
		return
	var next_name := str(stage_config(stage + 1)["name"])
	var dist := player.global_position.distance_to(_travel_target)
	var hint := _compass_hint(_travel_target)
	_travel_label.visible = true
	_travel_label.text = "前往 %s　%s　%.0f m" % [next_name, hint, dist]
func _update_travel() -> void:
	if not _travel_pending or player == null:
		return
	if player.global_position.distance_to(_travel_target) > 7.0:
		return
	_travel_pending = false
	_advance_stage()
func _advance_stage() -> void:
	if stage >= STAGE_COUNT:
		campaign_done = true
		completed = true
		_set_play_enabled(false)
		_banner_label.text = "通关！\n走过：主装卸场 → 北场 → 南场\n总分 %d · 最高分 %d · 按 R 再打一次" % [score, maxi(best_score, score)]
		_banner.visible = true
		if best_by_tier[difficulty_tier] < score:
			best_by_tier[difficulty_tier] = score
			best_score = score
			if not _automation:
				_save_progress()
		return
	stage += 1
	_stage_hud_left = 3.0
	reset_stage_counters()
	_apply_stage_scene()
	round_time_left = ROUND_SECONDS
	_raise_difficulty()
	_flash("第 %d 关 · %s" % [stage, stage_desc()], 2.4)
	if ball != null:
		ball.visible = true
	_respawn_ball()


## 关卡内重开：保留当前关，只重置这一关的状态。
func restart_stage() -> void:
	_keep_stage = true
	reset_round()
	reset_stage_counters()
	round_time_left = ROUND_SECONDS
	_update_stage_label()


func _update_stage_label() -> void:
	if _stage_label == null:
		return
	if _travel_pending:
		_stage_label.visible = false
		return
	if not campaign or campaign_done or _stage_hud_left <= 0.0:
		_stage_label.visible = false
		return
	_stage_label.visible = true
	var targets := stage_targets()
	var parts: Array[String] = []
	parts.append("进球 %d/%d" % [stage_goals, int(targets["goals"])])
	if int(targets["high"]) > 0:
		parts.append("高台 %d/%d" % [stage_high_goals, int(targets["high"])])
	if int(targets["order"]) > 0:
		parts.append("订单 %d/%d" % [stage_order_hits, int(targets["order"])])
	if int(targets["overload"]) > 0:
		parts.append("超载 %d/%d" % [stage_overloads, int(targets["overload"])])
	var cfg := stage_config(stage)
	_stage_label.text = "第 %d 关 · %s　%s" % [stage, str(cfg["name"]), " · ".join(parts)]
	_update_route_label()


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
	# 真实启动（无命令行参数）才开走路镜头起伏；测试/截图/录像保持静止基线。
	player.set("camera_bob_enabled", OS.get_cmdline_user_args().is_empty())
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
	dragon.connect("intercept_missed", _on_dragon_whiff)
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
	# HUD 设计基准 1280×800：所有元素仍按原坐标摆，最后整体等比缩放/居中，
	# 这样 1600×900、1920×1080 都不会错位（共振星试玩版也是按 1600×900 启动）。
	_hud_canvas = Control.new()
	_hud_canvas.size = Vector2(1280, 800)
	_hud_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_hud_canvas)
	_layout_hud_canvas()

	var theme := Theme.new()
	theme.default_font = _font
	theme.default_font_size = 15
	_root.theme = theme

	var panel := PanelContainer.new()
	panel.position = Vector2(22, 20)
	panel.custom_minimum_size = Vector2(430, 0)
	panel.add_theme_stylebox_override("panel", _panel_style())
	_hud_canvas.add_child(panel)
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
		# P0-3 HUD 减法：街机局内不再常驻左上说明板（标题屏已讲过一遍），
		# 只保留顶部计时/得分与准星、蓄力条；说明与按键留在暂停菜单里。
		panel.visible = false

	_mode_label = Label.new()
	_mode_label.position = Vector2(1080, 22)
	_mode_label.size = Vector2(176, 30)
	_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_mode_label.add_theme_font_size_override("font_size", 15)
	_mode_label.add_theme_color_override("font_color", Color("#7dffd4"))
	_hud_canvas.add_child(_mode_label)
	# P0-3：视角标记属于调试信息，常驻会让画面显得像开发版。
	_mode_label.visible = false

	_counter_label = Label.new()
	_counter_label.position = Vector2(980, 54)
	_counter_label.size = Vector2(276, 30)
	_counter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_counter_label.add_theme_font_size_override("font_size", 19)
	_counter_label.add_theme_color_override("font_color", Color("#ffcf8a"))
	_hud_canvas.add_child(_counter_label)
	# P0-3：街机模式的进球数已经由顶部计分条承担，右上角不再重复一遍。
	_counter_label.visible = not arcade

	# 街机模式：顶部中央的计时 / 得分 / 连击
	var arcade_panel := PanelContainer.new()
	arcade_panel.position = Vector2(452, 18)
	arcade_panel.custom_minimum_size = Vector2(376, 54)
	arcade_panel.add_theme_stylebox_override("panel", _panel_style(0.74))
	_hud_canvas.add_child(arcade_panel)
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

	# 订单提示：顶部计时条下方一行，只在街机模式显示当前“值钱的那一层”。
	_order_label = Label.new()
	_order_label.position = Vector2(452, 84)
	_order_label.size = Vector2(376, 26)
	_order_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_order_label.add_theme_font_size_override("font_size", 17)
	_order_label.add_theme_color_override("font_color", Color("#ffe0a8"))
	_order_label.add_theme_color_override("font_outline_color", Color(0.02, 0.05, 0.06, 0.9))
	_order_label.add_theme_constant_override("outline_size", 5)
	_order_label.visible = arcade
	_hud_canvas.add_child(_order_label)

	# 必杀槽提示：订单行下方一行，满 3 格显示“超载就绪”。
	_meter_label = Label.new()
	_meter_label.position = Vector2(452, 112)
	_meter_label.size = Vector2(376, 24)
	_meter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_meter_label.add_theme_font_size_override("font_size", 15)
	_meter_label.add_theme_color_override("font_color", Color("#9fb8b4"))
	_meter_label.add_theme_color_override("font_outline_color", Color(0.02, 0.05, 0.06, 0.9))
	_meter_label.add_theme_constant_override("outline_size", 5)
	_meter_label.visible = arcade
	_hud_canvas.add_child(_meter_label)

	# 练习关进度：只在练习模式显示，格式「练习·骗守门员 1 / 2」。
	_practice_label = Label.new()
	_practice_label.position = Vector2(452, 140)
	_practice_label.size = Vector2(376, 26)
	_practice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_practice_label.add_theme_font_size_override("font_size", 17)
	_practice_label.add_theme_color_override("font_color", Color("#7dffd4"))
	_practice_label.add_theme_color_override("font_outline_color", Color(0.02, 0.05, 0.06, 0.9))
	_practice_label.add_theme_constant_override("outline_size", 5)
	_practice_label.visible = false
	_hud_canvas.add_child(_practice_label)

	# 偷球提示：叼走期间显示倒计时与抢回方式。
	_carry_label = Label.new()
	_carry_label.position = Vector2(452, 168)
	_carry_label.size = Vector2(376, 26)
	_carry_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_carry_label.add_theme_font_size_override("font_size", 17)
	_carry_label.add_theme_color_override("font_color", Color("#ff9b6a"))
	_carry_label.add_theme_color_override("font_outline_color", Color(0.02, 0.05, 0.06, 0.9))
	_carry_label.add_theme_constant_override("outline_size", 5)
	_carry_label.visible = false
	_hud_canvas.add_child(_carry_label)

	# 关卡进度：第 N 关 + 目标计数（只在关卡模式显示）。
	_stage_label = Label.new()
	_stage_label.position = Vector2(24, 96)
	_stage_label.size = Vector2(520, 26)
	_stage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_stage_label.add_theme_font_size_override("font_size", 16)
	_stage_label.add_theme_color_override("font_color", Color("#9fe8ff"))
	_stage_label.add_theme_color_override("font_outline_color", Color(0.02, 0.05, 0.06, 0.9))
	_stage_label.add_theme_constant_override("outline_size", 5)
	_stage_label.visible = campaign
	_hud_canvas.add_child(_stage_label)

	# 侧风提示（只在有风时显示）
	_wind_label = Label.new()
	_wind_label.position = Vector2(452, 104)
	_wind_label.size = Vector2(376, 26)
	_wind_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wind_label.add_theme_font_size_override("font_size", 17)
	_wind_label.add_theme_color_override("font_color", Color("#ffd479"))
	_wind_label.visible = false
	_hud_canvas.add_child(_wind_label)

	# 蓄力条：准星下沿，只在蓄力时显示
	_charge_track = ColorRect.new()
	_charge_track.position = Vector2(560, 448)
	_charge_track.size = Vector2(160, 8)
	_charge_track.color = Color(0.06, 0.09, 0.10, 0.72)
	_charge_track.visible = false
	_hud_canvas.add_child(_charge_track)
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
		_hud_canvas.add_child(pip)
		_pips.append(pip)

	# 进图卡片：让玩家一眼知道“现在在哪张图、目标几球”
	_map_card = Label.new()
	_map_card.position = Vector2(0, 300)
	_map_card.size = Vector2(1280, 90)
	_map_card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_map_card.add_theme_font_size_override("font_size", 40)
	_map_card.add_theme_color_override("font_color", Color("#ffe9bd"))
	_map_card.visible = false
	_hud_canvas.add_child(_map_card)

	_route_label = RichTextLabel.new()
	_route_label.bbcode_enabled = true
	_travel_label = Label.new()
	_travel_label.position = Vector2(440, 96)
	_travel_label.size = Vector2(400, 24)
	_travel_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_travel_label.add_theme_font_size_override("font_size", 16)
	_travel_label.add_theme_color_override("font_color", Color("#ffcf5c"))
	_travel_label.add_theme_color_override("font_outline_color", Color(0.02, 0.05, 0.06, 0.9))
	_travel_label.visible = false
	_hud_canvas.add_child(_travel_label)

	_route_label.position = Vector2(24, 744)
	_route_label.size = Vector2(720, 34)
	_route_label.scroll_active = false
	_route_label.add_theme_font_size_override("normal_font_size", 16)
	_route_label.add_theme_color_override("default_color", Color("#9fb8b4"))
	_hud_canvas.add_child(_route_label)

	_crosshair_root = Control.new()
	_crosshair_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_crosshair_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_canvas.add_child(_crosshair_root)
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
	_hud_canvas.add_child(_prompt_panel)
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
	_hud_canvas.add_child(_banner)
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
	_hud_canvas.add_child(_debug_panel)
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



## 把 1280×800 的 HUD 画布等比缩放并居中到当前窗口；任何分辨率下版式一致。
func _layout_hud_canvas(vp: Vector2 = Vector2.ZERO) -> void:
	if _hud_canvas == null:
		return
	if vp == Vector2.ZERO:
		vp = get_viewport().get_visible_rect().size
	if vp.x <= 1.0 or vp.y <= 1.0:
		vp = Vector2(1280, 800)
	var factor: float = minf(vp.x / 1280.0, vp.y / 800.0)
	_hud_canvas.scale = Vector2(factor, factor)
	_hud_canvas.position = Vector2((vp.x - 1280.0 * factor) * 0.5, (vp.y - 800.0 * factor) * 0.5)
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


## 手柄轮询（P0-7）：RT 走和鼠标左键完全相同的蓄力/松手路径，Start 打开暂停。
## 键盘鼠标仍由 _input 处理，两条路径互不干扰。
## 用“按下/松开边沿”而不是 just_pressed：轮询在 _process 里，帧序更可控，
## 也让模拟输入（Input.action_press）与真机行为一致。
func _poll_pad_actions() -> void:
	var pause_down := Input.is_action_pressed("pad_pause")
	if pause_down and not _pad_pause_held:
		_pad_pause_held = true
		if _paused:
			_close_pause()
		elif _round_active:
			_open_pause()
	elif not pause_down:
		_pad_pause_held = false
	if not _round_active or completed:
		return
	var shoot_down := Input.is_action_pressed("shoot")
	if shoot_down and not _pad_shoot_held:
		_pad_shoot_held = true
		_charging = true
		_charge = 0.0
	elif not shoot_down and _pad_shoot_held:
		_pad_shoot_held = false
		if _charging:
			_charging = false
			_try_kick(_charge_power())


func _process(delta: float) -> void:
	if player == null:
		return
	if _paused:
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
				_flash("北侧货台 ×1.5", 1.4)
			elif zone == 2:
				_flash("维修坑 ×1.5", 1.4)
	if _respawn_timer > 0.0:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_respawn_ball()
	if not arcade:
		return
	if not _round_active:
		return
	if _travel_pending:
		_update_travel()
	if not completed and not _travel_pending:
		round_time_left = maxf(round_time_left - delta, 0.0)
		if _combo_timer > 0.0:
			_combo_timer = maxf(_combo_timer - delta, 0.0)
			if _combo_timer <= 0.0 and combo > 1:
				combo = 1
		_update_wind(delta)
		_tick_order(delta)
		_tick_dragon_boost(delta)
		_update_carry(delta)
		_update_countdown_sfx()
		if round_time_left <= 0.0:
			_end_round()
	_update_arcade_label()
	_update_meter_label()
	_update_practice_label()
	_update_carry_label()
	_stage_hud_left = maxf(_stage_hud_left - delta, 0.0)
	_order_hud_left = maxf(_order_hud_left - delta, 0.0)
	_layout_hud_canvas()
	_watch_dragon_telegraph()
	_update_stage_label()
	_tick_counter(delta)
	_update_travel_hud()


## 订单计时：每 30 秒换一层，换单时闪一下提示并让装货口对应灯带亮起。
func _tick_order(delta: float) -> void:
	if not arcade or not orders_enabled() or completed or not _round_active:
		return
	_order_clock += delta
	if _order_clock >= ORDER_PERIOD:
		_order_clock = 0.0
		_next_order()
	_update_order_label()


func _next_order() -> void:
	var next := order_zone
	while next == order_zone:
		next = randi() % 3
	order_zone = next
	_order_hud_left = 2.5
	if collector != null:
		collector.call("set_order_zone", order_zone)
	_flash("新订单：%s ×2" % ORDER_ZONE_NAMES[order_zone], 1.6)
	if _presentation != null and player != null:
		var cam := player.get("camera") as Camera3D
		if cam != null:
			_presentation.call("flash", AMBER if order_zone == 2 else CYAN, 0.10, 0.25)


func _update_order_label() -> void:
	if _order_label == null:
		return
	_order_label.visible = arcade and orders_enabled() and not completed and _order_hud_left > 0.0
	if not _order_label.visible:
		return
	var left: float = maxf(ORDER_PERIOD - _order_clock, 0.0)
	_order_label.text = "订单 %s ×2　%.0fs" % [ORDER_ZONE_NAMES[order_zone], left]


## 走路脚步声：只在真人游玩时响；频率随速度，音高微随机，避免机械重复。

## 奶龙扑出后把球开回场地：给球一个朝场内、带随机横移的冲量。
func _launch_counter_ball() -> void:
	var dir := Vector3(-1.0, 0.22, randf_range(-0.5, 0.5)).normalized()
	# 先把球放到门口内侧一点再开球，否则它会贴着舱口/门框弹回来；
	# 然后直接给速度（不叠加冲量），保证球真的朝场内飞。
	var launch_z := clampf(ball.global_position.z, -2.0, 2.0)
	ball.set("global_position", Vector3(9.6, 0.65, launch_z))
	ball.set("linear_velocity", dir * 13.0)
	ball.set("angular_velocity", Vector3.ZERO)
	ball.set("sleeping", false)
	_counter_left = COUNTER_WINDOW
	_counter_warned = false
	_flash("奶龙把球开回场地！反击 %.0f 秒" % COUNTER_WINDOW, 1.8)


func _tick_counter(delta: float) -> void:
	if _counter_left <= 0.0:
		return
	_counter_left = maxf(_counter_left - delta, 0.0)
	if not _counter_warned and _counter_left > 0.0 and _counter_left <= 1.0:
		_counter_warned = true
		_flash("反击最后 1 秒！", 0.8)
		if _sfx != null and _fx_live:
			_sfx.call("play_pitched", "metal", 1.3)
	if _counter_left <= 0.0:
		_flash("反击窗口结束", 1.0)

## 南场守门员更积极：出击瞬间给一次“奶龙出击！”提示 + 低频扑救声，
## 让“它比北场更凶”这件事能被听见、看见，而不是只在参数里。

## 底部路线条：三张图里当前在哪一张（暖色高亮），一眼知道自己在第几张图。
func _update_route_label() -> void:
	if _route_label == null:
		return
	var names := ["主装卸场", "北场", "南场"]
	var active := current_arena()
	var pieces: Array = []
	for index in range(names.size()):
		var label := "%d %s" % [index + 1, names[index]]
		if index == active:
			pieces.append("[color=#ffcf5c][b]▶ %s[/b][/color]" % label)
		else:
			pieces.append("[color=#6f827f]%s[/color]" % label)
	_route_label.text = "　".join(pieces)
func _watch_dragon_telegraph() -> void:
	if dragon == null or not is_instance_valid(dragon):
		return
	var state := str(dragon.call("state_name"))
	if state == _last_dragon_state:
		return
	_last_dragon_state = state
	if state != "拦截":
		return
	if _active_map != 2:
		return
	_flash("奶龙出击！", 0.7)
	if _sfx != null and _fx_live:
		_sfx.call("play_pitched", "block", 0.78)
func _update_footsteps(delta: float) -> void:
	if not _fx_live or _sfx == null or player == null:
		return
	if _paused or not _round_active or completed:
		return
	var flat_speed: float = Vector2(player.velocity.x, player.velocity.z).length()
	if flat_speed < 1.2 or not player.is_on_floor():
		return
	_step_clock += delta
	var interval: float = clampf(0.58 - flat_speed * 0.04, 0.26, 0.5)
	if _step_clock >= interval:
		_step_clock = 0.0
		_sfx.call("play_pitched", "step", randf_range(0.94, 1.06))

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
	_wind_force = (strength if strength > 0.0 else randf_range(2.0, 3.0)) * _wind_strength
	_wind_left = 5.0
	_wind_next = randf_range(25.0, 35.0) * _wind_period
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
	if _travel_pending:
		return false
	if _ball_carried:
		_flash("球被叼走了，先抢回来")
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
	# 接球抽射：球在滚的时候允许更远的触球距离、更宽的朝向，并按球速给加成。
	var ball_speed := ball.linear_velocity.length()
	var moving_ball := ball_speed > 3.0
	var reach := KICK_RANGE + (0.9 if moving_ball else 0.0)
	var min_dot := 0.12 if moving_ball else KICK_MIN_DOT
	if distance > reach:
		_flash("太远")
		return false
	if distance < 0.001:
		_flash("退半步")
		return false
	if forward.dot(to_ball.normalized()) < min_dot:
		_flash("面向球")
		return false
	# 玩家与球之间不能有东西（墙/门框/奶龙都算遮挡）
	if not _has_kick_line(distance):
		_flash("被挡住")
		return false

	shots_this_round += 1
	var full_charge := power >= FULL_CHARGE_POWER
	var overload := false
	if full_charge and arcade and orders_enabled():
		if power_meter >= METER_MAX:
			overload = true
			power_meter = 0
		else:
			power_meter += 1
	_last_shot_full_charge = full_charge
	_last_shot_overload = overload
	if overload:
		_overload_used = true
	var catch_bonus := 1.0
	if moving_ball:
		catch_bonus = 1.0 + minf(ball_speed, 14.0) / 45.0
	var impulse: float = KICK_IMPULSE * power * catch_bonus * (OVERLOAD_MULTIPLIER if overload else 1.0)
	ball.call("kick", forward, impulse)
	# 高低差：货台（y>0.8）/ 坑底（y<-0.6）射门算“高台/坑底射门”，进球 ×1.5
	_kick_elev_bonus = player.global_position.y > 0.8 or player.global_position.y < -0.6
	_kick_feedback(power + (0.45 if overload else 0.0))
	_spawn_kick_pulse(ball.global_position)
	if overload:
		_overload_feedback()
	elif moving_ball:
		_flash("接球抽射！×%.2f" % catch_bonus, 0.9)
		player.call("add_camera_shake", 0.16, 0.14)
		_hitstop(0.04)
	elif _kick_elev_bonus and arcade:
		_flash("%s射门" % ("高台" if player.global_position.y > 0.0 else "坑底"), 1.0)
	elif power >= FULL_CHARGE_POWER:
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


# ---------------------------------------------------------------- 打击反馈（P0）

## 踢球反馈：镜头抖动强度随力度、满蓄顿帧、音高随力度。
func _kick_feedback(power: float) -> void:
	if player == null:
		return
	var punch := clampf((power - 1.0) / 0.5, 0.0, 1.0)
	if _sfx != null:
		_sfx.call("play_pitched", "kick", 0.94 + 0.10 * punch + randf_range(-0.02, 0.02))
	if not _fx_live:
		return
	player.call("add_camera_shake", 0.12 + 0.18 * punch, 0.18)
	if power >= 1.25:
		_hitstop(0.055)
		_spawn_impact_dust(ball.global_position, Color("#ffcf8a"), 10, 0.55)


## 扑救反馈：更强的顿帧 + 抖动 + 尘土 + 奶龙挤压。
func _save_feedback(at: Vector3) -> void:
	if _sfx != null:
		_sfx.call("play_pitched", "block", randf_range(0.96, 1.04))
	if dragon != null and is_instance_valid(dragon):
		var dv: Node3D = dragon.get("visual") as Node3D
		if dv != null:
			dv.call("play_squash", 1.0)
	if not _fx_live:
		return
	if player != null:
		player.call("add_camera_shake", 0.5, 0.3)
	_hitstop(0.09)
	_spawn_impact_dust(at, Color("#bfe9de"), 16, 0.7)


## 进球反馈：奶龙懊恼晃身 + 轻微抖动（庆祝由 presentation 层负责）。
func _goal_feedback() -> void:
	if dragon != null and is_instance_valid(dragon):
		var dv: Node3D = dragon.get("visual") as Node3D
		if dv != null:
			dv.call("play_dejected")
	if _fx_live and player != null:
		player.call("add_camera_shake", 0.2, 0.22)


## 瞬间顿帧：只压 Engine.time_scale，不动任何物理参数；用 ignore_time_scale 的定时器还原。
## 只在意 _fx_live 时执行，因此所有 headless 回归与截图流程完全不受影响。
func _hitstop(seconds: float) -> void:
	if not _fx_live or _hitstop_busy:
		return
	_hitstop_busy = true
	Engine.time_scale = 0.06
	await get_tree().create_timer(seconds, true, false, true).timeout
	Engine.time_scale = 1.0
	_hitstop_busy = false


## 一次性尘土：贴地扩散的小尘团，0.7 s 自动释放。
func _spawn_impact_dust(at: Vector3, tint: Color, amount: int, power: float) -> void:
	if _dust_material == null:
		_dust_material = StandardMaterial3D.new()
		_dust_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_dust_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_dust_material.vertex_color_use_as_albedo = true
		_dust_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_dust_material.billboard_keep_scale = true
		_dust_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var particles := CPUParticles3D.new()
	particles.one_shot = true
	particles.amount = maxi(amount, 4)
	particles.lifetime = 0.7
	particles.explosiveness = 1.0
	particles.randomness = 0.6
	particles.direction = Vector3.UP
	particles.spread = 80.0
	particles.initial_velocity_min = 0.9 * power
	particles.initial_velocity_max = 2.6 * power
	particles.gravity = Vector3(0.0, -7.0, 0.0)
	particles.scale_amount_min = 0.05
	particles.scale_amount_max = 0.13
	particles.color = tint
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	particles.mesh = quad
	particles.material_override = _dust_material
	particles.position = at + Vector3.UP * 0.05
	add_child(particles)
	particles.emitting = true
	await get_tree().create_timer(1.0, true).timeout
	if is_instance_valid(particles):
		particles.queue_free()


## 超载射门的表现：更强抖动 + 0.4 s 慢放（仅实机渲染时）+ 换色浮字。
func _overload_feedback() -> void:
	_flash("超载射门！", 1.2)
	if _sfx != null:
		_sfx.call("play_pitched", "kick", 0.72)
	if not _fx_live:
		return
	if player != null:
		player.call("add_camera_shake", 0.6, 0.32)
	_spawn_impact_dust(ball.global_position, Color("#ffb347"), 22, 1.0)
	_slow_motion(0.35, 0.4)


## 慢放：只压 time_scale，用 ignore_time_scale 的计时器还原；与顿帧互斥。
func _slow_motion(scale_value: float, seconds: float) -> void:
	if not _fx_live or _slowmo_busy:
		return
	_slowmo_busy = true
	Engine.time_scale = clampf(scale_value, 0.05, 1.0)
	await get_tree().create_timer(seconds, true, false, true).timeout
	Engine.time_scale = 1.0
	_slowmo_busy = false


## 风险射门 C：满蓄被扑 → 奶龙加速 5 秒（直接改它的两个速度参数，到期按当前难度重算回去）。
func _start_dragon_boost(seconds: float) -> void:
	if dragon == null:
		return
	if _dragon_boost_left <= 0.0:
		dragon.set("walk_speed", float(dragon.get("walk_speed")) * DRAGON_BOOST_MULT)
		dragon.set("charge_speed", float(dragon.get("charge_speed")) * DRAGON_BOOST_MULT)
	_dragon_boost_left = maxf(_dragon_boost_left, seconds)


func _tick_dragon_boost(delta: float) -> void:
	if _dragon_boost_left <= 0.0:
		return
	_dragon_boost_left = maxf(_dragon_boost_left - delta, 0.0)
	if _dragon_boost_left <= 0.0 and dragon != null:
		_raise_difficulty()


func _update_meter_label() -> void:
	if _meter_label == null:
		return
	if not arcade or completed:
		_meter_label.visible = false
		return
	_meter_label.visible = arcade and orders_enabled() and not completed and (power_meter > 0 or _dragon_boost_left > 0.0)
	if not _meter_label.visible:
		return
	if _dragon_boost_left > 0.0:
		_meter_label.text = "奶龙加速 %.0fs" % ceilf(_dragon_boost_left)
		_meter_label.add_theme_color_override("font_color", Color("#ff9b6a"))
	elif power_meter >= METER_MAX:
		_meter_label.text = "超载就绪 · 下一脚必杀"
		_meter_label.add_theme_color_override("font_color", Color("#ffd479"))
	else:
		_meter_label.text = "必杀槽 %d/%d" % [power_meter, METER_MAX]
		_meter_label.add_theme_color_override("font_color", Color("#9fb8b4"))


# ---------------------------------------------------------------- 事件

func _on_goal_scored(total: int, target: int) -> void:
	loaded_count = total
	_record_peak_loaded = maxi(_record_peak_loaded, loaded_count)
	_counter_punch = 1.0
	if _sfx != null:
		_sfx.call("play_pitched", "loaded", 0.95 + 0.06 * float(combo))
	if env_art != null and is_instance_valid(env_art):
		env_art.call("on_loaded", loaded_count)
	_goal_feedback()

	if arcade:
		goals_this_round += 1
		var zone := int(collector.get("last_goal_zone")) if collector != null else -1
		var order_hit := orders_enabled() and zone == order_zone
		var points := SCORE_PER_GOAL * combo
		if _kick_elev_bonus:
			points = int(round(float(points) * 1.5))
			_high_goal = true
		if order_hit:
			points *= 2
			_order_hits += 1
		var counter_hit := _counter_left > 0.0
		if counter_hit:
			points = int(round(float(points) * COUNTER_BONUS))
			_counter_left = 0.0
		# 关卡目标计数
		if campaign and practice_mode == 0:
			stage_goals += 1
			if order_hit:
				stage_order_hits += 1
			if _kick_elev_bonus:
				stage_high_goals += 1
			if _last_shot_overload:
				stage_overloads += 1
			_update_stage_label()
			_check_stage_complete()
		score += points
		# 关卡模式：每关时间固定，进球不加时（否则“通关”变成刷时间）；刷分模式保留 +4 s。
		var time_bonus: float = 0.0 if campaign else TIME_BONUS_PER_GOAL
		if time_bonus > 0.0:
			round_time_left = minf(round_time_left + time_bonus, ROUND_SECONDS + 30.0)
		combo = mini(combo + 1, COMBO_MAX)
		best_combo_this_round = maxi(best_combo_this_round, combo)
		_combo_timer = COMBO_WINDOW
		_counter_label.text = "已进 %d 球" % loaded_count
		var next_level := 1 + int(goals_this_round / 2)
		var level_note := ""
		if next_level > dragon_level:
			level_note = "　奶龙 Lv.%d" % next_level
		_raise_difficulty()
		var order_note := "　订单 ×2" if order_hit else ""
		if counter_hit:
			order_note += "　反击 ×1.5"
		var bonus_note := "　+%ds" % int(time_bonus) if time_bonus > 0.0 else ""
		_flash("+%d　连击 x%d%s%s%s" % [points, combo, bonus_note, level_note, order_note], 1.8)
		if _presentation != null and player != null:
			var cam := player.get("camera") as Camera3D
			if cam != null:
				_presentation.call("celebrate", cam.unproject_position(ball.global_position + Vector3.UP * 0.6),
					points, combo, Color("#ffcf5c"))
		_respawn_timer = 0.7
		_goal_kick_pending = true
		# 练习关进度：三关各自只认一种“完成条件”。
		if practice_mode != 0:
			var whiff_recent := Time.get_ticks_msec() - _last_whiff_ms < 3000
			if practice_mode == 1 and order_hit:
				_practice_done += 1
			elif practice_mode == 2 and whiff_recent:
				_practice_done += 1
			elif practice_mode == 3 and combo >= 4:
				_practice_done += 1
			_update_practice_label()
			_check_practice_complete()
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
	var speed_mult: float = TIER_SPEED[difficulty_tier]
	dragon_level = 1 + int(goals_this_round / 2)
	dragon.set("walk_speed", minf(float(_dragon_defaults["walk_speed"]) + 0.07 * rank, 3.2) * speed_mult)
	dragon.set("charge_speed", minf(float(_dragon_defaults["charge_speed"]) + 0.06 * rank, 4.0) * speed_mult)
	dragon.set("intercept_cooldown", maxf(1.2, float(_dragon_defaults["intercept_cooldown"]) - 0.08 * rank))
	var react: float = maxf(0.10, float(_dragon_defaults["react_delay"]) - 0.010 * rank)
	dragon.set("react_delay", react * TIER_REACT[difficulty_tier])


func _restore_difficulty() -> void:
	if dragon == null or _dragon_defaults.is_empty():
		return
	var speed_mult: float = TIER_SPEED[difficulty_tier]
	for key in _dragon_defaults:
		dragon.set(key, _dragon_defaults[key])
	dragon.set("walk_speed", float(_dragon_defaults["walk_speed"]) * speed_mult)
	dragon.set("charge_speed", float(_dragon_defaults["charge_speed"]) * speed_mult)
	dragon.set("react_delay", float(_dragon_defaults["react_delay"]) * TIER_REACT[difficulty_tier])


## 切难度档：未开局时可用 1/2/3 直接切；最高分按档独立记录。
func set_difficulty_tier(tier: int) -> void:
	difficulty_tier = clampi(tier, 0, TIER_NAMES.size() - 1)
	best_score = best_by_tier[difficulty_tier]
	_restore_difficulty()
	if _presentation != null:
		_presentation.call("set_tier_label", TIER_NAMES[difficulty_tier])
	_flash("难度：%s" % TIER_NAMES[difficulty_tier], 1.2)


# ---------------------------------------------------------------- 练习关（P1）

## 三个练习关：只改“这一局算不算完成”的判定，玩法、物理、奶龙 AI 全部复用街机模式。
func start_practice(mode: int) -> void:
	practice_mode = clampi(mode, 1, 3)
	_on_start_requested()
	round_time_left = PRACTICE_SECONDS
	_practice_done = 0
	_practice_goal = 3 if practice_mode == 1 else (2 if practice_mode == 2 else 1)
	_whiffs_this_round = 0
	_last_whiff_ms = -100000
	_update_practice_label()


func _on_dragon_whiff() -> void:
	_whiffs_this_round += 1
	_last_whiff_ms = Time.get_ticks_msec()
	if practice_mode == 2:
		_update_practice_label()


func _practice_text() -> String:
	return "%s　%d / %d" % [PRACTICE_NAMES[practice_mode], _practice_done, _practice_goal]


func _check_practice_complete() -> void:
	if practice_mode == 0 or completed:
		return
	if _practice_done < _practice_goal:
		return
	completed = true
	_hud.hide()
	_practice_label.visible = false
	_set_play_enabled(false)
	_banner_label.text = "练习完成！\n%s\n按 R 再来一次 · T 回标题" % PRACTICE_NAMES[practice_mode]
	_banner.visible = true


## 回标题：清掉练习状态，重新摆好标题屏（局内 HUD 隐藏）。
func _exit_practice() -> void:
	practice_mode = 0
	completed = false
	_banner.visible = false
	_round_active = false
	_hud.hide()
	_set_play_enabled(false)
	if _presentation != null:
		_presentation.call("show_title", best_score, TIER_NAMES[difficulty_tier],
			challenges_done(), CHALLENGE_LIST.size(), TIME_NAMES[time_of_day])
	if _hud != null:
		_hud.visible = false


func _records_entries() -> Dictionary:
	var rows: Array = []
	for id in CHALLENGE_LIST:
		rows.append({"label": str(CHALLENGE_LABELS.get(id, id)), "done": bool(challenges.get(id, false))})
	return {
		"tiers": [best_by_tier[0], best_by_tier[1], best_by_tier[2]],
		"names": TIER_NAMES,
		"current": difficulty_tier,
		"done": challenges_done(),
		"total": CHALLENGE_LIST.size(),
		"challenges": rows,
		"time_name": TIME_NAMES[time_of_day],
	}


func _open_records() -> void:
	if _presentation == null:
		return
	_presentation.call("show_records", _records_entries())


func _update_practice_label() -> void:
	if _practice_label == null:
		return
	_practice_label.visible = practice_mode != 0 and not completed
	if _practice_label.visible:
		_practice_label.text = _practice_text()


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



## 进球之后：球从装货口弹回场地（带随机横移），玩家要追第二落点，而不是原地等重生。
func _restart_from_goal() -> void:
	_kick_elev_bonus = false
	var z := randf_range(-2.0, 2.0)
	ball.call("reset_to", Vector3(9.2, 0.4, z))
	var dir := Vector3(-1.0, 0.25, randf_range(-0.45, 0.45)).normalized()
	ball.set("linear_velocity", dir * 12.0)
	ball.set("angular_velocity", Vector3.ZERO)
	ball.set("sleeping", false)
	_spawn_landing_marker(Vector3(9.2 - 9.0, 0.03, clampf(z + dir.z * 3.2, -8.0, 8.0)))
	_flash("继续！接第二落点", 1.2)


## 第二落点提示：地面一个扩散的青色圆环，2 秒后自动消失。
func _spawn_landing_marker(at: Vector3) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.55
	torus.outer_radius = 0.72
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#7dffd4")
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color("#7dffd4")
	mat.emission_energy_multiplier = 1.2
	ring.mesh = torus
	ring.material_override = mat
	ring.position = Vector3(at.x, 0.05, at.z)
	add_child(ring)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(1.9, 1.0, 1.9), 2.0)
	tween.tween_property(mat, "albedo_color:a", 0.0, 2.0)
	tween.chain().tween_callback(func() -> void: ring.queue_free())
func _respawn_ball() -> void:
	_respawn_timer = -1.0
	if ball == null:
		return
	if _goal_kick_pending and practice_mode == 0:
		_goal_kick_pending = false
		_restart_from_goal()
		return
	_kick_elev_bonus = false
	var spots: Array = stage_ball_spots()
	var spot: Vector3 = spots[randi() % spots.size()]
	ball.call("reset_to", spot)


func _end_round() -> void:
	if completed:
		return
	completed = true
	_clear_wind()
	# 练习关超时：不进结算面板，给“重试 / 回标题”两个出口。
	if practice_mode != 0:
		if _practice_label != null:
			_practice_label.visible = false
		_hud.hide()
		_set_play_enabled(false)
		_banner_label.text = "练习超时\n%s\n按 R 重试 · T 回标题" % PRACTICE_NAMES[practice_mode]
		_banner.visible = true
		return
	# 关卡模式超时：不弹刷分结算，给“重试本关”的出口。
	if campaign:
		_set_play_enabled(false)
		_banner_label.text = "第 %d 关失败\n%s\n按 R 重试本关" % [stage, stage_desc()]
		_banner.visible = true
		return
	if _sfx != null:
		_sfx.call("play_pitched", "loaded", 0.62)
	var is_record := score > best_score
	var newly: Array[String] = []
	if arcade:
		newly = evaluate_challenges()
	if is_record:
		best_score = score
		best_by_tier[difficulty_tier] = best_score
	if is_record or not newly.is_empty():
		# 自动化（自测/截图/录像）不写玩家存档，避免测试把纪录和挑战打脏。
		if not _automation:
			_save_progress()
	var new_labels: Array[String] = []
	for id in newly:
		new_labels.append(str(CHALLENGE_LABELS.get(id, id)))
	if _presentation != null and arcade:
		_hud.hide()
		_set_play_enabled(false)
		_presentation.call("show_result", score, best_score, goals_this_round, best_combo_this_round,
			is_record, shots_this_round, saves_this_round, _order_hits,
			challenges_done(), CHALLENGE_LIST.size(), new_labels)
	else:
		_banner_label.text = "时间到\n得分 %d · 最高 %d\n按 R 再来一局" % [score, best_score]
		_banner.visible = true


func _load_best() -> void:
	var cfg := ConfigFile.new()
	var legacy := 0
	if cfg.load(RECORD_FILE) == OK:
		legacy = int(cfg.get_value("record", "best", 0))
		_muted = bool(cfg.get_value("audio", "muted", false))
		difficulty_tier = clampi(int(cfg.get_value("record", "tier", 1)), 0, 2)
		for index in range(3):
			best_by_tier[index] = int(cfg.get_value("record", "best_%d" % index, 0))
		for id in CHALLENGE_LIST:
			challenges[id] = bool(cfg.get_value("challenges", id, false))
	# 老存档只有一条 best：迁到“标准”档，避免玩家纪录丢失。
	if legacy > 0 and best_by_tier[1] == 0:
		best_by_tier[1] = legacy
	best_score = best_by_tier[difficulty_tier]


func _save_progress() -> void:
	var cfg := ConfigFile.new()
	cfg.load(RECORD_FILE)
	cfg.set_value("record", "tier", difficulty_tier)
	cfg.set_value("record", "best", best_score)
	for index in range(3):
		cfg.set_value("record", "best_%d" % index, best_by_tier[index])
	for id in CHALLENGE_LIST:
		cfg.set_value("challenges", id, bool(challenges.get(id, false)))
	cfg.set_value("audio", "muted", _muted)
	cfg.save(RECORD_FILE)


func _save_best() -> void:
	_save_progress()


## 挑战清单：一局结束按本局统计判定，只把“本次新达成”的条目返回给结算页。
func evaluate_challenges() -> Array[String]:
	var checks := {
		"first_goal": goals_this_round >= 1,
		"hat_trick": goals_this_round >= 3,
		"combo4": best_combo_this_round >= 4,
		"combo6": best_combo_this_round >= 6,
		"order2": _order_hits >= 2,
		"overload": _overload_used,
		"high_shot": _high_goal,
		"score500": score >= 500,
		"score1000": score >= 1000,
		"unbeaten": goals_this_round >= 2 and saves_this_round == 0,
	}
	var newly: Array[String] = []
	for id in CHALLENGE_LIST:
		if bool(checks.get(id, false)) and not bool(challenges.get(id, false)):
			challenges[id] = true
			newly.append(id)
	_new_challenges = newly
	return newly


func challenges_done() -> int:
	var done := 0
	for id in CHALLENGE_LIST:
		if bool(challenges.get(id, false)):
			done += 1
	return done


func _on_dragon_blocked(point: Vector3, _speed: float) -> void:
	saves_this_round += 1
	_save_feedback(point)
	# 反击：被扑出的球不是“死球”，奶龙会把它开回场地，玩家要追第二落点。
	if arcade and counter_enabled and practice_mode == 0 and ball != null:
		_launch_counter_ball()
	# 风险射门 C：满蓄被扑 → 奶龙得意加速 5 秒，把“每脚都满蓄”变成一个真实风险。
	var boosted := false
	if arcade and _last_shot_full_charge:
		_start_dragon_boost(DRAGON_BOOST_SECONDS)
		boosted = true
	var had_combo := combo > 1
	if arcade and had_combo:
		combo = 1
		_combo_timer = 0.0
	# 提案 B：拦截成功后再掷一次“偷球”
	if arcade and _try_start_steal():
		_flash("奶龙叼走了球！靠近按 E 抢回", 2.0)
		return
	if boosted:
		_flash("被拦！奶龙加速 " + str(int(DRAGON_BOOST_SECONDS)) + " 秒", 1.6)
	elif had_combo:
		_flash("被拦！连击断", 1.2)
	else:
		_flash("被拦下", 1.2)


## 偷球判定：练习模式不偷，冷却/次数/概率都过了才叼走。
func _try_start_steal() -> bool:
	if practice_mode != 0 or _ball_carried or ball == null or dragon == null:
		return false
	# 自动化模式下只有显式强制才偷球，保证回归确定性。
	if _automation and not _steal_force_next:
		return false
	if _steal_cooldown_left > 0.0 or steals_used >= STEAL_LIMIT:
		return false
	var forced := _steal_force_next
	_steal_force_next = false
	if not forced and randf() > STEAL_CHANCE:
		return false
	_ball_carried = true
	_carry_left = CARRY_SECONDS
	steals_used += 1
	_steal_cooldown_left = STEAL_COOLDOWN
	ball.set("freeze", true)
	ball.set("linear_velocity", Vector3.ZERO)
	ball.set("angular_velocity", Vector3.ZERO)
	return true


func _update_carry(delta: float) -> void:
	_steal_cooldown_left = maxf(_steal_cooldown_left - delta, 0.0)
	if not _ball_carried:
		return
	_carry_left = maxf(_carry_left - delta, 0.0)
	# 球跟着奶龙的嘴走：只改视觉位置，不做物理。
	if ball != null and dragon != null:
		var mouth: Vector3 = dragon.global_position + Vector3(0.0, 1.05, 0.0) \
			+ (-dragon.global_transform.basis.z) * 0.65
		ball.global_position = mouth
	var near := player != null and ball != null \
		and player.global_position.distance_to(ball.global_position) <= RETRIEVE_RANGE
	var holding := Input.is_action_pressed("retrieve")
	if near and holding and not _retrieve_held:
		_retrieve_held = true
		_retrieve_ball()
	elif not holding:
		_retrieve_held = false
	if _ball_carried and _carry_left <= 0.0:
		_drop_carried_ball()


func _retrieve_ball() -> void:
	if not _ball_carried:
		return
	_ball_carried = false
	ball.set("freeze", false)
	var at: Vector3 = player.global_position + (-player.global_transform.basis.z) * 1.0
	ball.call("reset_to", at)
	power_meter = mini(power_meter + 1, METER_MAX)
	_update_meter_label()
	_flash("抢回来了！必杀槽 +1", 1.4)


func _drop_carried_ball() -> void:
	_ball_carried = false
	if ball == null:
		return
	ball.set("freeze", false)
	var forward := -dragon.global_transform.basis.z if dragon != null else Vector3.FORWARD
	ball.call("reset_to", dragon.global_position + forward * 1.3 + Vector3.UP * 0.2)
	_flash("奶龙把球吐出来了", 1.2)


func _update_carry_label() -> void:
	if _carry_label == null:
		return
	_carry_label.visible = _ball_carried
	if _ball_carried:
		_carry_label.text = "球被叼走！靠近按 E 抢回　%.1fs" % _carry_left


func _on_ball_out_of_bounds(_point: Vector3) -> void:
	# 只有“真的掉出世界”才恢复；正常停球、门边停球一律不动。
	if ball == null:
		return
	if arcade:
		var spots: Array = stage_ball_spots()
		var spot: Vector3 = spots[randi() % spots.size()]
		ball.call("reset_to", spot)
		_flash("球已回场", 1.4)
	else:
		ball.call("reset_to", BALL_HOME)
		_flash("球已放回", 1.4)
	print("GULU ball out of bounds -> reset")


# ---------------------------------------------------------------- reset / debug

func reset_round() -> void:
	Engine.time_scale = 1.0
	_hitstop_busy = false
	if player == null:
		return
	_hud.show()
	if _round_active:
		_set_play_enabled(true)
	if campaign:
		_apply_stage_scene()
	player.global_position = SPAWN
	player.velocity = Vector3.ZERO
	player.rotation.y = SPAWN_YAW
	player.set("_camera_yaw", SPAWN_YAW)
	player.set("_camera_yaw_target", SPAWN_YAW)
	player.set("_camera_pitch", 0.27)
	player.set("_camera_pitch_target", 0.27)
	if campaign:
		var spawn := arena_spawn(current_arena())
		var pos: Vector3 = spawn["pos"] as Vector3
		var look: Vector3 = spawn["look"] as Vector3
		player.global_position = pos
		var yaw := atan2(-(look.x - pos.x), -(look.z - pos.z))
		player.rotation.y = yaw
		player.set("_camera_yaw", yaw)
		player.set("_camera_yaw_target", yaw)
	player.set("use_first_person", true)
	# 真实启动（无命令行参数）才开走路镜头起伏；测试/截图/录像保持静止基线。
	player.set("camera_bob_enabled", OS.get_cmdline_user_args().is_empty())
	(player.get("visual") as Node3D).visible = false
	player.call("update_camera", 1.0, true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if ball != null:
		var spawn_ball: Vector3 = BALL_HOME
		if campaign and current_arena() != 0:
			var spots := stage_ball_spots()
			spawn_ball = spots[randi() % spots.size()]
		ball.call("reset_to", spawn_ball)
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
	if practice_mode != 0:
		round_time_left = PRACTICE_SECONDS
	_practice_done = 0
	_whiffs_this_round = 0
	_last_whiff_ms = -100000
	_ball_carried = false
	steals_used = 0
	_steal_cooldown_left = 0.0
	_carry_left = 0.0
	_retrieve_held = false
	_steal_force_next = false
	_update_practice_label()
	if not _keep_stage:
		stage = 1
		_stage_hud_left = 2.5
		_order_hud_left = 2.5
		wind_enabled = false
		_clear_wind()
		_apply_active_map(current_arena())
		set_time_of_day(int(stage_config(1)["time"]))
		campaign_done = false
		reset_stage_counters()
	_keep_stage = false
	_update_stage_label()
	goals_this_round = 0
	shots_this_round = 0
	saves_this_round = 0
	dragon_level = 1
	_charging = false
	_charge = 0.0
	_clear_wind()
	_wind_next = randf_range(22.0, 30.0)
	_last_beep_second = -1
	power_meter = 0
	_dragon_boost_left = 0.0
	_last_shot_full_charge = false
	_last_shot_overload = false
	_overload_used = false
	_high_goal = false
	_new_challenges.clear()
	_update_meter_label()
	_restore_difficulty()
	# 订单重置：回到中舱、计时归零、装货口灯带同步。
	order_zone = 1
	_order_clock = 0.0
	_order_hits = 0
	if collector != null:
		collector.call("set_order_zone", order_zone)
	_update_order_label()
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
	# 这两组测的是“刷分模式”的结算面板；关卡模式有自己的失败横幅。
	campaign = false
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
	_check(not bool(ball.get("collected")), "ball is live again after goal", passes, failures)
	_check(_ball_speed() > 2.0, "ball is kicked back into play (%.1f m/s)" % _ball_speed(),
		passes, failures)

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
	# 这两组测的是“刷分模式”的结算面板；关卡模式有自己的失败横幅。
	campaign = false
	counter_enabled = false
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
	counter_enabled = false
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
	_presentation.call("show_title", best_score, TIER_NAMES[difficulty_tier],
		challenges_done(), CHALLENGE_LIST.size(), TIME_NAMES[time_of_day])
	if _hud != null:
		_hud.visible = false
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
		_presentation.call("show_title", maxi(best_score, 1240), TIER_NAMES[difficulty_tier],
			challenges_done(), CHALLENGE_LIST.size(), TIME_NAMES[time_of_day])
		if _hud != null:
			_hud.visible = false
	await _wait(0.7)
	await _shot("20_title.png")
	# 记录板展示帧（P2）
	_open_records()
	await _wait(0.4)
	await _shot("28_records.png")
	_presentation.call("hide_records")
	await _wait(0.15)
	if _presentation != null:
		_presentation.call("hide_title")
		_hud.show()
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
	# 练习关 HUD 展示帧：用第二关（骗守门员）摆一次进度。
	start_practice(2)
	_on_countdown_finished()
	_hud.show()
	_practice_done = 1
	_last_whiff_ms = Time.get_ticks_msec()
	_update_practice_label()
	await _wait(0.5)
	await _shot("24_practice.png")
	_exit_practice()
	await _wait(0.2)
	# 偷球状态展示帧（提案 B）：强制一次拦截偷球，拍下“叼着球 + 抢回提示”。
	reset_round()
	_round_active = true
	_hud.show()
	_presentation.call("hide_title")
	await _wait(0.35)
	_steal_force_next = true
	_on_dragon_blocked(dragon.global_position, 1.0)
	await _wait(0.5)
	await _shot("25_carry.png")
	_carry_left = 0.0
	_drop_carried_ball()
	await _wait(0.2)
	# 时段预设展示帧（P2）：黄昏 / 夜班，只换光照与雾。
	set_time_of_day(1)
	await _wait(0.5)
	await _shot("26_dusk.png")
	set_time_of_day(2)
	await _wait(0.5)
	await _shot("27_night.png")
	set_time_of_day(0)
	await _wait(0.3)
	# 结算截图走“刷分模式”的面板（关卡模式的超时是失败横幅）。
	campaign = false
	# 走真实结算入口，确保截图中的 HUD、输入和结算状态一致。
	score = 940
	best_score = 1240
	goals_this_round = 5
	best_combo_this_round = 4
	shots_this_round = 12
	saves_this_round = 4
	_order_hits = 2
	_end_round()
	await get_tree().process_frame
	await _wait(0.7)
	await _shot("22_result.png")
	# 关卡 HUD 与通关横幅展示帧（P2 之后的通关结构）
	_presentation.call("hide_result")
	campaign = true
	stage = 2
	stage_goals = 2
	stage_high_goals = 0
	_stage_hud_left = 5.0
	completed = false
	_hud.show()
	_update_stage_label()
	await _wait(0.5)
	await _shot("29_stage.png")

	# 三场地展示帧：北侧货台 / 维修坑
	campaign = true
	_keep_stage = true
	stage = 2
	reset_stage_counters()
	reset_round()
	_hud.show()
	_stage_hud_left = 6.0
	await _wait(0.6)
	await _shot("31_deck.png")
	_keep_stage = true
	stage = 3
	reset_stage_counters()
	reset_round()
	_hud.show()
	_stage_hud_left = 6.0
	await _wait(0.6)
	await _shot("32_pit.png")

	# 赶路提示帧
	_travel_pending = true
	_travel_target = arena_spawn(1)["pos"] as Vector3
	_update_travel_hud()
	await _wait(0.4)
	await _shot("33_travel.png")
	_travel_pending = false
	_update_travel_hud()
	campaign_done = true
	completed = true
	_hud.show()
	_banner_label.text = "通关！\n总分 1840 · 最高分 1240\n按 R 再打一次"
	_banner.visible = true
	await _wait(0.5)
	await _shot("30_victory.png")
	_banner.visible = false
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
	_check(sfx_players.has_all(["kick", "block", "loaded", "metal", "step"]), "five gameplay sounds imported", passes, failures)
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
	# 待机循环会让脚底有几厘米浮动：量之前先关掉待机，阈值放到动画可解释的范围（14 cm）。
	if visual.get("idle_enabled") != null:
		visual.set("idle_enabled", false)
	await get_tree().process_frame
	var feet_y := 1.0e9
	for mesh_node in model_meshes:
		var mesh_instance := mesh_node as MeshInstance3D
		var aabb := mesh_instance.global_transform * mesh_instance.get_aabb()
		feet_y = minf(feet_y, aabb.position.y)
	var feet_gap := feet_y - dragon.global_position.y
	print("DRAGON_FEET gap=%.3f feet=%.3f root=%.3f" % [feet_gap, feet_y, dragon.global_position.y])
	_check(absf(feet_gap) < 0.14, "dragon feet grounded (%.3f)" % feet_gap, passes, failures)
	if visual.get("idle_enabled") != null:
		visual.set("idle_enabled", true)

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
	# A_wide 站台点在北货台上；集装箱堆占住了 y=1.06 的老机位（-10,19 正在箱体内），
	# 机位东移 2 m 出箱，尽量保持原有取景方向；集装箱堆留在左侧近景。
	await _art_shot("A_wide.png", Vector3(-1.2, 1.30, 7.8), Vector3(10.0, 1.0, 0.0), 60.0)
	await _art_shot("B_player_eye.png", Vector3(2.4, 0.02, 5.2), Vector3(9.5, 1.0, 0.0), 65.0)
	await _art_shot("C_interaction.png", Vector3(10.4, 0.02, 2.2), Vector3(12.8, 1.5, 0.0), 44.0)
	await _art_shot("D_threequarter.png", Vector3(-7.2, 0.02, 13.6), Vector3(-6.2, 0.9, 9.2), 52.0)
	# 补充机位（不属于《指南》四机位）：本次三件 Blender 中景资产的自查特写
	await _art_shot("E_service_shed.png", Vector3(2.6, 0.02, -7.6), Vector3(0.2, 1.5, -11.7), 52.0)
	await _art_shot("F_observation_deck.png", Vector3(1.2, 0.02, 15.4), Vector3(5.4, 2.2, 12.4), 52.0)
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
	print("LOOK goals=%d children=%d" % [_goals.size(), get_child_count()])
	for g in _goals:
		var n3 := g as Node3D
		print("  goal %s at %s active=%s" % [n3.name, str(n3.global_position), str(g.get("active"))])
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


# ---------------------------------------------------------------- 表现层自测（P0）

## 抖动 / 顿帧 / 尘土 / 挤压四类反馈的 headless 冒烟：只验表现层，不碰物理与玩法判定。
## 用法： godot --headless --path . -- --fx-test
func _run_fx_test() -> void:
	var passes: Array = []
	var failures: Array = []
	_fx_live = true
	await get_tree().process_frame
	var cam := player.get("camera") as Camera3D
	_check(cam != null, "player camera exists", passes, failures)

	var before: Vector3 = cam.global_transform.origin
	player.call("add_camera_shake", 0.8, 0.25)
	_check(float(player.get("_shake_amp")) > 0.0, "shake armed", passes, failures)
	var moved := 0.0
	for i in range(8):
		player.call("update_camera", 1.0 / 60.0)
		moved = maxf(moved, cam.global_transform.origin.distance_to(before))
	_check(moved > 0.0005, "shake moves camera (%.4f m)" % moved, passes, failures)

	await get_tree().create_timer(0.5, true, false, true).timeout
	for i in range(40):
		player.call("update_camera", 1.0 / 60.0)
	_check(float(player.get("_shake_amp")) <= 0.0, "shake decays to zero", passes, failures)

	var base_dust := _count_dust()
	_spawn_impact_dust(Vector3(-2.0, 0.2, 2.0), Color("#ffcf8a"), 8, 0.5)
	await get_tree().process_frame
	_check(_count_dust() > base_dust, "impact dust spawns", passes, failures)
	await get_tree().create_timer(1.3, true, false, true).timeout
	_check(_count_dust() == base_dust, "impact dust frees itself", passes, failures)

	_check(is_equal_approx(Engine.time_scale, 1.0), "time scale neutral before hitstop", passes, failures)
	_hitstop(0.06)
	await get_tree().create_timer(0.25, true, false, true).timeout
	_check(is_equal_approx(Engine.time_scale, 1.0),
		"hitstop restores time scale (%.2f)" % Engine.time_scale, passes, failures)

	var dragon_visual: Node3D = null
	if dragon != null:
		dragon_visual = dragon.get("visual") as Node3D
	var facing: Node3D = null
	if dragon_visual != null:
		facing = dragon_visual.find_child("Facing", true, false) as Node3D
	_check(facing != null, "dragon facing node present", passes, failures)
	if facing != null and dragon_visual.has_method("play_squash"):
		dragon_visual.call("play_squash", 1.0)
		await get_tree().create_timer(0.05, true, false, true).timeout
		_check(facing.scale.y < 1.0, "dragon squash compresses (%.3f)" % facing.scale.y, passes, failures)
		await get_tree().create_timer(0.45, true, false, true).timeout
		_check(absf(facing.scale.y - 1.0) < 0.05, "dragon squash settles (%.3f)" % facing.scale.y, passes, failures)

	print("GULU FX SUMMARY passes=%d failures=%d" % [passes.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _count_dust() -> int:
	var count := 0
	for child in get_children():
		if child is CPUParticles3D and (child as CPUParticles3D).one_shot:
			count += 1
	return count


# ---------------------------------------------------------------- 订单玩法自测

## 装货订单：初始层、命中 ×2、错层不加成、30 秒换单、R 复位。
## 用法： godot --headless --path . -- --order-test
func _run_order_test() -> void:
	campaign = false
	var passes: Array = []
	var failures: Array = []
	print("GULU ORDER TEST start")
	await _wait(0.6)
	reset_round()
	await _wait(0.3)
	_check(arcade, "arcade rules active", passes, failures)
	_check(order_zone == 1, "order starts at the middle bay", passes, failures)
	_check(_order_label != null and _order_label.visible, "order HUD visible", passes, failures)
	_check(_order_label.text.contains(ORDER_ZONE_NAMES[1]), "order HUD names the bay", passes, failures)
	var strips: Array = collector.get("_order_strips")
	_check(strips.size() == 3, "three order bands exist", passes, failures)
	if strips.size() == 3:
		_check((strips[1] as MeshInstance3D).visible and not (strips[0] as MeshInstance3D).visible,
			"middle band lit by default", passes, failures)

	# 命中订单层 → 分数 ×2
	collector.set("last_goal_zone", order_zone)
	_on_goal_scored(1, goal_target)
	_check(score == SCORE_PER_GOAL * 2, "order hit doubles the score (%d)" % score, passes, failures)
	_check(_order_hits == 1, "order hits counted", passes, failures)

	# 错层 → 只拿基础分
	reset_round()
	await _wait(0.2)
	collector.set("last_goal_zone", (order_zone + 1) % 3)
	_on_goal_scored(1, goal_target)
	_check(score == SCORE_PER_GOAL, "off-order goal keeps base score (%d)" % score, passes, failures)

	# 30 秒换单
	reset_round()
	await _wait(0.2)
	_round_active = true
	var before := order_zone
	_order_clock = ORDER_PERIOD
	_tick_order(0.02)
	_check(order_zone != before, "order rotates after 30 s (%d -> %d)" % [before, order_zone],
		passes, failures)
	var lit := 0
	for strip in collector.get("_order_strips"):
		if (strip as MeshInstance3D).visible:
			lit += 1
	_check(lit == 1, "exactly one band lit after rotation (%d)" % lit, passes, failures)

	reset_round()
	_check(order_zone == 1 and is_equal_approx(_order_clock, 0.0), "R restores the first order",
		passes, failures)

	print("GULU ORDER SUMMARY passes=%d failures=%d" % [passes.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


# ---------------------------------------------------------------- 手柄自测（P0-7）

## 手柄映射与输入路径：左摇杆/右摇杆/RT/Start 的动作表 + 实机路径（模拟按下）。
## 用法： godot --headless --path . -- --pad-test
func _run_pad_test() -> void:
	var passes: Array = []
	var failures: Array = []
	print("GULU PAD TEST start")
	await _wait(0.6)
	reset_round()
	await _wait(0.3)
	_round_active = true
	_set_play_enabled(true)
	await _wait(0.1)

	for action in ["move_left", "move_right", "move_up", "move_down",
			"look_left", "look_right", "look_up", "look_down", "shoot", "pad_pause"]:
		_check(_count_joy_events(action) > 0, "joypad mapping: %s" % action, passes, failures)

	# 左摇杆 → 移动
	var before_pos: Vector3 = player.global_position
	Input.action_press("move_right", 1.0)
	await _wait(0.3)
	Input.action_release("move_right")
	_check(player.global_position.distance_to(before_pos) > 0.05,
		"left stick moves the player (%.2f m)" % player.global_position.distance_to(before_pos),
		passes, failures)

	# 右摇杆 → 视角
	var yaw_before := float(player.get("_camera_yaw_target"))
	Input.action_press("look_right", 1.0)
	await _wait(0.3)
	Input.action_release("look_right")
	_check(absf(float(player.get("_camera_yaw_target")) - yaw_before) > 0.01,
		"right stick turns the camera", passes, failures)

	# RT → 蓄力射门
	_place_player(BALL_HOME + Vector3(-1.4, 0.02, 0.0), BALL_HOME)
	_aim_at(BALL_HOME + Vector3(6.0, 0.5, 0.0))
	await _wait(0.25)
	var shots_before := shots_this_round
	Input.action_press("shoot")
	await _wait(0.25)
	_check(_charging, "RT starts charging", passes, failures)
	Input.action_release("shoot")
	await _wait(0.25)
	_check(not _charging, "releasing RT ends charging", passes, failures)
	_check(shots_this_round > shots_before, "RT shot is fired (%d shots)" % shots_this_round,
		passes, failures)

	# Start → 暂停 / 继续（松开后要留一帧，让轮询看到边沿复位）
	Input.action_press("pad_pause")
	await _wait(0.25)
	Input.action_release("pad_pause")
	await _wait(0.2)
	_check(_paused, "Start opens the pause menu", passes, failures)
	Input.action_press("pad_pause")
	await _wait(0.25)
	Input.action_release("pad_pause")
	await _wait(0.2)
	_check(not _paused, "Start closes the pause menu", passes, failures)

	print("GULU PAD SUMMARY passes=%d failures=%d" % [passes.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _demo_walk(action: String, seconds: float) -> void:
	Input.action_press(action, 1.0)
	await _wait(seconds)
	Input.action_release(action)
	await _wait(0.08)

## 演示片：真实走位 + 真实攻防，不再挪奶龙、不再瞬移玩家（只在开场瞬移一次站位）。
## 用法： godot --path . --write-movie <帧目录>/k.png --fixed-fps 30 -- --demo
func _run_demo() -> void:
	await _wait(0.5)
	reset_round()
	_hud.visible = false
	_presentation.call("show_title", maxi(best_score, 1240), TIER_NAMES[difficulty_tier],
		challenges_done(), CHALLENGE_LIST.size(), TIME_NAMES[time_of_day])
	await _wait(1.6)
	_presentation.call("hide_title")
	_round_active = true
	_hud.show()
	_set_play_enabled(true)
	set_time_of_day(0)
	order_zone = 0
	if collector != null:
		collector.call("set_order_zone", 0)

	# 开场只瞬移一次站位；之后全部用 W/A/S/D 走。
	_place_player(Vector3(-6.0, 0.02, 0.0), Vector3(12.0, 1.0, 0.0))
	await _wait(0.3)
	await _demo_walk("move_up", 1.35)
	await _wait(0.25)
	print("DEMO approach player=%s ball=%s dragon=%s" % [
		str(player.global_position.snapped(Vector3.ONE * 0.1)),
		str(ball.global_position.snapped(Vector3.ONE * 0.1)),
		str(dragon.global_position.snapped(Vector3.ONE * 0.1))])

	# 第一脚：直着打向奶龙站的这一侧，让它真的扑（慢球，给它反应时间）
	_aim_at(Vector3(12.45, 0.5, clampf(dragon.global_position.z, -1.2, 1.2)))
	await _wait(0.2)
	var kicked1 := _try_kick(0.85)
	await _wait(2.2)
	print("DEMO kick1 ok=%s goals=%d saves=%d score=%d" % [str(kicked1), goals_this_round, saves_this_round, score])

	# 第二脚：横向走位、打奶龙反侧空当（超载射门）
	await _demo_walk("move_left", 0.35)
	var side := 1.8 if dragon.global_position.z < 0.0 else -1.8
	_aim_at(Vector3(12.45, 0.9, side))
	if ball != null and player != null:
		var fwd := -player.global_transform.basis.z
		ball.call("reset_to", player.global_position + fwd * 1.1 + Vector3(0.0, 0.0, 0.0))
	await _wait(0.35)
	power_meter = METER_MAX
	_update_meter_label()
	await _wait(0.3)
	var kicked2 := _try_kick(1.5)
	await _wait(3.0)
	print("DEMO kick2 ok=%s goals=%d saves=%d score=%d" % [str(kicked2), goals_this_round, saves_this_round, score])

	# 第三脚：再进一球，凑满第 1 关，触发“第 2 关”提示
	if ball != null and player != null:
		var fwd3 := -player.global_transform.basis.z
		ball.call("reset_to", player.global_position + fwd3 * 1.1)
	_aim_at(Vector3(12.45, 0.8, -side))
	await _wait(0.3)
	_try_kick(1.2)
	await _wait(2.8)
	# 第四脚：补满第 1 关（3 球），让“第 2 关”提示真的出现
	if ball != null and player != null:
		var fwd4 := -player.global_transform.basis.z
		ball.call("reset_to", player.global_position + fwd4 * 1.1)
	_aim_at(Vector3(12.45, 0.8, side))
	await _wait(0.3)
	_try_kick(1.2)
	await _wait(2.8)
	print("DEMO stage=%d goals=%d score=%d" % [stage, goals_this_round, score])

	# 时段展示：只切一次黄昏，停 3 秒（不再快速轮播三个时段）
	set_time_of_day(1)
	await _wait(3.0)
	set_time_of_day(0)
	await _wait(1.0)

	_hud.hide()
	_presentation.call("show_records", _records_entries())
	await _wait(2.2)
	_presentation.call("hide_records")
	await _wait(0.3)
	get_tree().quit(0)


# ---------------------------------------------------------------- 关卡制自测

## 三关递进：目标逐关加码、第 2 关只在高台/坑底重生球、三关全过 = 通关、R 重试本关。
## 用法： godot --headless --path . -- --campaign-test
func _run_campaign_test() -> void:
	var passes: Array = []
	var failures: Array = []
	print("GULU CAMPAIGN TEST start")
	await _wait(0.5)
	_keep_stage = false
	reset_round()
	await _wait(0.3)
	_round_active = true
	_set_play_enabled(true)
	_check(campaign, "campaign mode is on by default", passes, failures)
	_check(stage == 1, "campaign starts at stage 1", passes, failures)
	_check(stage_ball_spots().size() == BALL_SPOTS.size(), "stage 1 uses the whole yard",
		passes, failures)

	# 第 1 关：两球
	for index in range(2):
		_campaign_goal(false, false, false)
	await _wait(0.1)
	_check(_travel_pending, "clearing stage 1 starts the walk", passes, failures)
	var travel_time := round_time_left
	_check(not _try_kick(1.0), "kicking is blocked while travelling", passes, failures)
	await _wait(0.4)
	_check(absf(round_time_left - travel_time) < 0.1, "timer pauses during the walk", passes, failures)
	await _walk_to_next_stage()
	_check(stage == 2, "two goals clear stage 1 (stage=%d)" % stage, passes, failures)
	_check(current_arena() == 1 and stage_ball_spots().size() == 3,
		"stage 2 moves the play zone to the north deck (arena=%d)" % current_arena(), passes, failures)
	_check(round_time_left > ROUND_SECONDS - 1.0, "stage 2 starts with a fresh timer", passes, failures)

	_check(time_of_day == 1, "stage 2 switches the scene to dusk (%d)" % time_of_day, passes, failures)

	# 第 2 关：三球
	for index in range(3):
		_campaign_goal(false, false, false)
	await _wait(0.05)
	_check(_travel_pending, "clearing stage 2 starts the walk", passes, failures)
	await _walk_to_next_stage()
	_check(stage == 3, "three goals clear stage 2 (stage=%d)" % stage, passes, failures)
	_check(time_of_day == 2, "stage 3 switches the scene to night (%d)" % time_of_day, passes, failures)

	# 第 3 关：三球
	for index in range(3):
		_campaign_goal(false, false, false)
	await _wait(0.05)
	_check(_travel_pending, "clearing stage 3 starts the walk", passes, failures)
	await _walk_to_next_stage()
	_check(stage == 4, "three goals clear stage 3 (stage=%d)" % stage, passes, failures)
	_check(wind_enabled and time_of_day == 0, "stage 4 adds side wind back in daytime", passes, failures)

	# 第 4 关：三球
	for index in range(3):
		_campaign_goal(false, false, false)
	await _wait(0.05)
	_check(_travel_pending, "clearing stage 4 starts the walk", passes, failures)
	await _walk_to_next_stage()
	_check(stage == 5, "three goals clear stage 4 (stage=%d)" % stage, passes, failures)
	_check(current_arena() == 1, "stage 5 stays on the north deck (arena=%d)" % current_arena(),
		passes, failures)

	# 第 5 关：四球
	for index in range(4):
		_campaign_goal(false, false, false)
	await _wait(0.05)
	_check(_travel_pending, "clearing stage 5 starts the walk", passes, failures)
	await _walk_to_next_stage()
	_check(stage == 6, "four goals clear stage 5 (stage=%d)" % stage, passes, failures)

	# 第 6 关：四球 → 通关
	for index in range(4):
		_campaign_goal(false, false, false)
	await _wait(0.1)
	_check(campaign_done, "stage 6 completes the campaign", passes, failures)
	_check(completed, "campaign victory ends the round", passes, failures)
	_check(_banner_label.text.contains("通关"), "victory banner appears", passes, failures)

	# R 重试本关：通关后回到第 1 关
	_keep_stage = false
	reset_round()
	await _wait(0.1)
	_check(stage == 1 and not campaign_done, "restart resets the campaign", passes, failures)

	# 关卡内重试保留当前关
	stage = 2
	reset_stage_counters()
	restart_stage()
	await _wait(0.2)
	_check(stage == 2, "restart_stage keeps the current stage (%d)" % stage, passes, failures)
	_check(stage_goals == 0 and round_time_left > ROUND_SECONDS - 6.0,
		"restart_stage resets the stage counters and timer", passes, failures)

	print("GULU CAMPAIGN SUMMARY passes=%d failures=%d" % [passes.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)



## 测试用：把玩家放到“赶路”目标点，让 _process 的到达判定推进到下一关。
func _walk_to_next_stage() -> void:
	if player == null:
		return
	player.global_position = _travel_target
	await _wait(0.3)
func _campaign_goal(order: bool, high: bool, overload: bool) -> void:
	_kick_elev_bonus = high
	_last_shot_overload = overload
	_last_shot_full_charge = false
	if collector != null:
		collector.set("last_goal_zone", order_zone if order else ((order_zone + 1) % 3))
	_on_goal_scored(1, goal_target)

# ---------------------------------------------------------------- 反击自测

## 被扑出后奶龙把球开回场地，3 秒内进球 ×1.5；窗口过期回到基础分。
## 用法： godot --headless --path . -- --counter-test
func _run_counter_test() -> void:
	var passes: Array = []
	var failures: Array = []
	print("GULU COUNTER TEST start")
	await _wait(0.5)
	reset_round()
	await _wait(0.2)
	_round_active = true
	_set_play_enabled(true)
	_check(_counter_left == 0.0, "counter window starts closed", passes, failures)

	_last_shot_full_charge = false
	_steal_force_next = false
	_on_dragon_blocked(Vector3.ZERO, 1.0)
	await _wait(0.15)
	_check(_counter_left > COUNTER_WINDOW - 0.6,
		"save opens the counter window (%.1f s)" % _counter_left, passes, failures)
	var speed := ball.linear_velocity.length()
	_check(speed > 6.0, "keeper launches the ball back (%.1f m/s)" % speed, passes, failures)
	_check(ball.linear_velocity.x < -3.0, "ball travels away from the goal (vx=%.1f)" % ball.linear_velocity.x,
		passes, failures)

	collector.set("last_goal_zone", (order_zone + 1) % 3)
	_on_goal_scored(1, goal_target)
	_check(score == int(SCORE_PER_GOAL * COUNTER_BONUS),
		"counter goal is worth x1.5 (%d)" % score, passes, failures)
	_check(_counter_left == 0.0, "counter window closes after a goal", passes, failures)

	reset_round()
	await _wait(0.2)
	_round_active = true
	_on_dragon_blocked(Vector3.ZERO, 1.0)
	await _wait(COUNTER_WINDOW + 0.5)
	_check(_counter_left <= 0.0, "counter window expires on its own", passes, failures)
	collector.set("last_goal_zone", (order_zone + 1) % 3)
	_on_goal_scored(1, goal_target)
	_check(score == SCORE_PER_GOAL, "goal after the window keeps base score (%d)" % score,
		passes, failures)

	print("GULU COUNTER SUMMARY passes=%d failures=%d" % [passes.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)



# ---------------------------------------------------------------- 接球抽射自测

## 静止球超出 1.9 m 踢不到；滚动的球在 2.8 m 内可以接球抽射，并获得球速加成。
## 用法： godot --headless --path . -- --touch-test
func _run_touch_test() -> void:
	var passes: Array = []
	var failures: Array = []
	print("GULU TOUCH TEST start")
	await _wait(0.5)
	reset_round()
	await _wait(0.2)
	_round_active = true
	_set_play_enabled(true)

	_place_player(Vector3(-2.0, 0.02, 0.0), Vector3(10.0, 1.0, 0.0))
	ball.call("reset_to", Vector3(0.8, 0.0, 0.0))
	await _wait(0.15)
	_check(not _try_kick(1.0), "stationary ball beyond 1.9 m is rejected", passes, failures)

	ball.call("reset_to", Vector3(0.4, 0.0, 0.0))
	await _wait(0.05)
	ball.set("linear_velocity", Vector3(3.2, 0.0, 0.0))
	await _wait(0.03)
	var before := _ball_speed()
	var kicked := _try_kick(1.0)
	await _wait(0.06)
	var after := _ball_speed()
	_check(kicked, "moving ball can be hit from further away", passes, failures)
	_check(after > before, "catch-and-shoot adds pace (%.1f -> %.1f m/s)" % [before, after],
		passes, failures)

	print("GULU TOUCH SUMMARY passes=%d failures=%d" % [passes.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)

# ---------------------------------------------------------------- HUD 分辨率自测

## 1280×800 / 1600×900 / 1920×1080 下，HUD 画布应等比缩放并居中，版式不走样。
## 用法： godot --headless --path . -- --hud-test
func _run_hud_test() -> void:
	var passes: Array = []
	var failures: Array = []
	print("GULU HUD TEST start")
	await _wait(0.4)
	_layout_hud_canvas(Vector2(1280, 800))
	_check(is_equal_approx(_hud_canvas.scale.x, 1.0) and _hud_canvas.position.is_equal_approx(Vector2.ZERO),
		"1280x800 is the 1:1 baseline", passes, failures)
	_layout_hud_canvas(Vector2(1600, 900))
	_check(absf(_hud_canvas.scale.x - 1.125) < 0.001,
		"1600x900 scales to 1.125 (%.3f)" % _hud_canvas.scale.x, passes, failures)
	_check(absf(_hud_canvas.position.x - 80.0) < 0.5,
		"1600x900 is centred (x=%.1f)" % _hud_canvas.position.x, passes, failures)
	_layout_hud_canvas(Vector2(1920, 1080))
	_check(absf(_hud_canvas.scale.x - 1.35) < 0.001,
		"1920x1080 scales to 1.35 (%.3f)" % _hud_canvas.scale.x, passes, failures)
	_layout_hud_canvas(Vector2(1280, 800))
	print("GULU HUD SUMMARY passes=%d failures=%d" % [passes.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)

# ---------------------------------------------------------------- 关卡直达自测

## 启动参数 --stage=N 走的那条路：保留指定关、重置计时与目标、球只在高台/坑底重生。
func _run_stage_boot_test() -> void:
	var passes: Array = []
	var failures: Array = []
	print("GULU STAGE BOOT TEST start")
	await _wait(0.4)
	_keep_stage = true
	stage = 2
	reset_stage_counters()
	reset_round()
	await _wait(0.2)
	reset_stage_counters()
	await _wait(0.05)
	_check(stage == 2, "boot keeps the requested stage (%d)" % stage, passes, failures)
	_check(stage_goals == 0 and round_time_left > ROUND_SECONDS - 6.0,
		"boot resets that stage's counters and timer (goals=%d t=%.1f)" % [stage_goals, round_time_left], passes, failures)
	_check(current_arena() == 1 and stage_ball_spots().size() == 3,
		"stage 2 boots into the north yard (arena=%d)" % current_arena(), passes, failures)

	# 标题屏按钮走同一套入口
	_on_stage_requested(3)
	await _wait(0.1)
	_check(stage == 3, "menu button 3 keeps the requested stage (%d)" % stage, passes, failures)
	_on_arcade_requested()
	await _wait(0.05)
	_check(not campaign, "arcade button switches off the campaign", passes, failures)
	_on_practice_requested()
	await _wait(0.1)
	_check(practice_mode == 1, "practice button starts the first drill (%d)" % practice_mode, passes, failures)
	print("GULU STAGE BOOT SUMMARY passes=%d failures=%d" % [passes.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)

# ---------------------------------------------------------------- 三场地自测

## 三个场地各自有出生点、朝向与球重生区；换关时玩家被放到对应场地。
func _run_arena_test() -> void:
	var passes: Array = []
	var failures: Array = []
	print("GULU ARENA TEST start")
	await _wait(0.4)
	_check(current_arena() == 0, "stage 1 plays at the main yard", passes, failures)

	_keep_stage = true
	stage = 2
	reset_stage_counters()
	reset_round()
	await _wait(0.2)
	var deck_pos: Vector3 = arena_spawn(1)["pos"] as Vector3
	_check(current_arena() == 1, "stage 2 moves to the north yard (arena=%d)" % current_arena(),
		passes, failures)
	_check(player.global_position.distance_to(deck_pos) < 1.0,
		"player spawns in the north yard (%.1f m away)" % player.global_position.distance_to(deck_pos),
		passes, failures)
	_check(stage_ball_spots().size() == 3, "north arena has three ball spots", passes, failures)

	_keep_stage = true
	stage = 3
	reset_stage_counters()
	reset_round()
	await _wait(0.2)
	var pit_pos: Vector3 = arena_spawn(2)["pos"] as Vector3
	_check(current_arena() == 2, "stage 3 moves to the south yard (arena=%d)" % current_arena(),
		passes, failures)
	_check(player.global_position.distance_to(pit_pos) < 1.0,
		"player spawns in the south yard (%.1f m away)" % player.global_position.distance_to(pit_pos),
		passes, failures)

	# 便携门判定 + 守门员落位
	_apply_active_map(1)
	_check(absf(_wind_strength - 1.25) < 0.01,
		"north map has 1.25x wind (%.2f)" % _wind_strength, passes, failures)
	_check(absf(float(_goals[1].get("half_width")) - 1.45) < 0.01,
		"north gate is the narrow one (%.2f)" % float(_goals[1].get("half_width")), passes, failures)
	_apply_active_map(2)
	_check(absf(_wind_strength - 1.55) < 0.01, "south map has 1.55x wind (%.2f)" % _wind_strength, passes, failures)
	_apply_active_map(1)
	_check(absf(float(_goals[2].get("half_width")) - 2.2) < 0.01,
		"south gate is the wide one (%.2f)" % float(_goals[2].get("half_width")), passes, failures)
	_check(absf(float(dragon.get("walk_speed")) - 1.75) < 0.01 and absf(float(dragon.get("intercept_cooldown")) - 2.0) < 0.01,
		"north keeper is slower but covers less", passes, failures)
	_apply_active_map(2)
	_check(absf(float(dragon.get("walk_speed")) - 2.0) < 0.01 and absf(float(dragon.get("intercept_cooldown")) - 1.7) < 0.01,
		"south keeper is more aggressive", passes, failures)
	_apply_active_map(1)
	_check(absf(float(dragon.get("zone_half_z")) - 2.4) < 0.01,
		"keeper covers a narrower zone on the north map (%.1f)" % float(dragon.get("zone_half_z")), passes, failures)
	_check(dragon.global_position.distance_to(Vector3(65.75, 0.0, 0.0)) < 1.5,
		"keeper moves to the new gate (%.1f m)" % dragon.global_position.distance_to(Vector3(65.75, 0.0, 0.0)),
		passes, failures)
	_round_active = true
	_set_play_enabled(true)
	dragon.global_position = Vector3(40.0, 0.0, 8.0)
	var before_goals := goals_this_round
	ball.call("reset_to", Vector3(64.0, 0.9, 0.0))
	await _wait(0.05)
	ball.set("linear_velocity", Vector3(18.0, 2.0, 0.0))
	ball.set("sleeping", false)
	await _wait(0.5)
	dragon.global_position = Vector3(65.75, 0.0, 0.0)
	_check(goals_this_round > before_goals,
		"portable gate scores when the ball crosses it (%d -> %d)" % [before_goals, goals_this_round],
		passes, failures)
	print("GULU ARENA SUMMARY passes=%d failures=%d" % [passes.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)

# ---------------------------------------------------------------- 地图空地探测

## 从上往下打射线，看哪些网格是“平整地面 + 没有东西”，用来挑新场地位置。
func _run_map_probe() -> void:
	await _wait(0.5)
	var space := get_world_3d().direct_space_state
	print("PROBE x: -44..44 step 4, z: -28..28 step 4   (空格=空地, ^=高台, v=坑, #=很高)")
	for zi in range(-7, 8):
		var z := zi * 4
		var row := ""
		for xi in range(-11, 12):
			var x := xi * 4
			var query := PhysicsRayQueryParameters3D.create(Vector3(x, 40.0, z), Vector3(x, -12.0, z))
			var hit := space.intersect_ray(query)
			if hit.is_empty():
				row += " "
				continue
			var h := (hit["position"] as Vector3).y
			if absf(h) < 0.25:
				row += " "
			elif h < -0.3:
				row += "v"
			elif h < 1.6:
				row += "^"
			else:
				row += "#"
		print("PROBE z=%4d |%s|" % [z, row])
	get_tree().quit(0)

# ---------------------------------------------------------------- 看位工具

## --look=ax,az,tx,tz ：把自由相机放到 (ax, 1.7, az) 看向 (tx, 1.0, tz)，截一张图后退出。
## 用来在“不说话”的前提下判断某个位置到底被什么挡住。
func _arg_value(args: PackedStringArray, prefix: String) -> String:
	for arg in args:
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return ""

func _run_look_probe() -> void:
	await _wait(0.6)
	var spec := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--look="):
			spec = arg.substr(7)
	var parts := spec.split(",")
	if parts.size() < 4:
		print("LOOK bad args: %s" % spec)
		get_tree().quit(1)
		return
	var from := Vector3(float(parts[0]), 1.7, float(parts[1]))
	var to := Vector3(float(parts[2]), 1.0, float(parts[3]))
	var cam := Camera3D.new()
	cam.fov = 70.0
	add_child(cam)
	cam.global_position = from
	cam.look_at(to, Vector3.UP)
	cam.current = true
	await _wait(0.4)
	print("LOOK goals=%d children=%d" % [_goals.size(), get_child_count()])
	for g in _goals:
		var n3 := g as Node3D
		print("  goal %s at %s active=%s" % [n3.name, str(n3.global_position), str(g.get("active"))])
	var image := get_viewport().get_texture().get_image()
	var tag := "%d_%d_%d_%d" % [int(from.x), int(from.z), int(to.x), int(to.z)]
	var path := "user://look_%s.png" % tag
	image.save_png(path)
	print("LOOK %s -> %s" % [spec, ProjectSettings.globalize_path(path)])
	get_tree().quit(0)

# ---------------------------------------------------------------- 三图演示

## --demo3：主装卸场一球 → 北场窄门 → 南场夜班宽门，用来说明"三张图"。

# ---------------------------------------------------------------- 走图演示

## --demo4：清关后不瞬移，真的沿连廊走到第二、第三块场地。
func _run_demo4() -> void:
	_presentation.call("hide_title")
	await _wait(1.2)
	_keep_stage = false
	reset_round()
	await _wait(2.4)
	_round_active = true
	_set_play_enabled(true)
	# 第 1 关：两球，直接结算（演示用，省掉跑位时间）
	_campaign_goal(false, false, false)
	_campaign_goal(false, false, false)
	await _wait(0.5)
	print("DEMO4 travel start pending=%s stage=%d" % [str(_travel_pending), stage])
	_demo_walk_to(_travel_target, 14.0)
	await _wait(1.2)
	print("DEMO4 arrived stage=%d arena=%d" % [stage, current_arena()])
	# 第 2 关：三球
	_campaign_goal(false, false, false)
	_campaign_goal(false, false, false)
	_campaign_goal(false, false, false)
	await _wait(0.5)
	_demo_walk_to(_travel_target, 10.0)
	await _wait(1.4)
	print("DEMO4 arrived stage=%d arena=%d" % [stage, current_arena()])
	await _wait(1.2)
	get_tree().quit(0)


## 朝目标点走过去（每 0.35 s 重新对准方向），超时才瞬移兜底。
func _demo_walk_to(target: Vector3, timeout: float) -> void:
	var elapsed := 0.0
	while elapsed < timeout:
		if not _travel_pending:
			return
		if player.global_position.distance_to(target) < 6.0:
			return
		var yaw := atan2(-(target.x - player.global_position.x), -(target.z - player.global_position.z))
		player.rotation.y = yaw
		player.set("_camera_yaw", yaw)
		player.set("_camera_yaw_target", yaw)
		_demo_walk("move_up", 0.35)
		elapsed += 0.35
	if _travel_pending:
		player.global_position = _travel_target
func _run_demo3() -> void:
	_presentation.call("hide_title")
	await _wait(1.4)
	_keep_stage = false
	reset_round()
	await _wait(2.4)
	_round_active = true
	_set_play_enabled(true)
	_demo_walk("move_up", 1.2)
	_aim_at(Vector3(12.45, 0.8, 0.0))
	await _wait(0.2)
	_try_kick(1.2)
	await _wait(2.2)
	print("DEMO3 map0 stage=%d goals=%d" % [stage, goals_this_round])
	for target in [2, 3]:
		_keep_stage = true
		stage = target
		reset_stage_counters()
		reset_round()
		await _wait(2.0)
		_round_active = true
		_set_play_enabled(true)
		await _wait(1.2)
		var gate: Node = _goals[current_arena()]
		var gate_pos: Vector3 = gate.call("gate_center") as Vector3
		_aim_at(gate_pos + Vector3(0.0, 0.9, 0.0))
		await _wait(0.3)
		_try_kick(1.2)
		await _wait(2.0)
		print("DEMO3 map%d stage=%d arena=%d" % [current_arena(), stage, current_arena()])
	await _wait(0.6)
	get_tree().quit(0)

# ---------------------------------------------------------------- 图标截图

## 给导出用的 512×512 图标：贴脸拍奶龙，隐藏 HUD。
func _run_icon_shot() -> void:
	await _wait(0.5)
	if _hud != null:
		_hud.visible = false
	_presentation.call("hide_title")
	var cam := Camera3D.new()
	cam.fov = 34.0
	add_child(cam)
	var head := dragon.global_position + Vector3(0.0, 1.05, 0.0)
	var facing := Vector3(-1.0, 0.0, 0.55).normalized()
	cam.global_position = head + facing * 2.9 + Vector3(0.0, 0.55, 0.0)
	cam.current = true
	await _wait(0.5)
	var image := get_viewport().get_texture().get_image()
	image.save_png("user://icon_raw.png")
	print("ICON %s" % ProjectSettings.globalize_path("user://icon_raw.png"))
	get_tree().quit(0)
func _count_joy_events(action: String) -> int:
	if not InputMap.has_action(action):
		return 0
	var count := 0
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadMotion or event is InputEventJoypadButton:
			count += 1
	return count


# ---------------------------------------------------------------- 结算目标自测（P0-8）

## 三个结算目标（进球 3 / 连击 x4 / 订单命中 2）的判定与结算面板数据。
## 用法： godot --headless --path . -- --result-test
func _run_result_test() -> void:
	var passes: Array = []
	var failures: Array = []
	print("GULU RESULT TEST start")
	await _wait(0.4)
	_check(_presentation != null, "presentation layer exists", passes, failures)
	_check(int(_presentation.call("evaluate_objectives", 0, 1, 0)) == 0,
		"no goals met on an empty round", passes, failures)
	_check(int(_presentation.call("evaluate_objectives", 3, 4, 2)) == 3,
		"all three goals met", passes, failures)
	_check(int(_presentation.call("evaluate_objectives", 3, 1, 0)) == 1,
		"only the goal-count objective met", passes, failures)
	_check(int(_presentation.call("evaluate_objectives", 1, 6, 1)) == 1,
		"only the combo objective met", passes, failures)

	# 结算面板：进球 2 / 连击 5 / 订单 3 → 命中 2 条
	_presentation.call("show_result", 900, 1200, 2, 5, false, 6, 1, 3)
	await _wait(0.15)
	_check(int(_presentation.get("last_result_objectives")) == 2,
		"result panel records 2/3 objectives (%d)" % int(_presentation.get("last_result_objectives")),
		passes, failures)
	_presentation.call("show_result", 100, 1200, 1, 1, false, 3, 2, 0)
	await _wait(0.15)
	_check(int(_presentation.get("last_result_objectives")) == 0,
		"result panel records 0/3 objectives", passes, failures)
	_presentation.call("hide_result")
	await _wait(0.1)
	_check(not bool(_presentation.call("result_visible")), "result panel can be dismissed",
		passes, failures)

	print("GULU RESULT SUMMARY passes=%d failures=%d" % [passes.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


# ---------------------------------------------------------------- 音频自测（P0-6）

## BGM：加载、40 s 循环、播放状态、静音联动。音效本身由 selftest 的「四个音效已导入」覆盖。
## 用法： godot --headless --path . -- --audio-test
func _run_audio_test() -> void:
	var passes: Array = []
	var failures: Array = []
	print("GULU AUDIO TEST start")
	await _wait(0.4)
	_check(_sfx != null, "sfx node exists", passes, failures)
	_check(bool(_sfx.call("has_music")), "bgm stream loaded", passes, failures)
	var length := float(_sfx.call("music_length"))
	_check(length > 39.0, "bgm is a 40 s loop (%.1f s)" % length, passes, failures)
	_check(bool(_sfx.call("music_playing")), "bgm is playing", passes, failures)
	_sfx.call("set_muted", true)
	await _wait(0.1)
	_check(float(_sfx.call("music_volume_db")) <= -60.0,
		"mute silences the bgm (%.0f dB)" % float(_sfx.call("music_volume_db")), passes, failures)
	_check(bool(_sfx.call("is_muted")), "mute state recorded", passes, failures)
	_sfx.call("set_muted", false)
	await _wait(0.1)
	_check(float(_sfx.call("music_volume_db")) > -30.0,
		"unmute restores the bgm (%.0f dB)" % float(_sfx.call("music_volume_db")), passes, failures)

	# 环境底噪：按地图切换音高/音量
	_apply_active_map(1)
	await _wait(0.15)
	var amb := _sfx.get("_amb") as AudioStreamPlayer
	_check(amb != null and amb.playing, "north map starts wind ambience", passes, failures)
	_check(absf(amb.pitch_scale - 1.05) < 0.01, "wind ambience pitch follows the map (%.2f)" % amb.pitch_scale,
		passes, failures)
	_apply_active_map(0)
	await _wait(0.1)
	_check(absf(amb.pitch_scale - 0.8) < 0.01, "main yard uses a lower hum (%.2f)" % amb.pitch_scale,
		passes, failures)

	print("GULU AUDIO SUMMARY passes=%d failures=%d" % [passes.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


# ---------------------------------------------------------------- 必杀槽自测（P1）

## 必杀槽 + 超载射门 + 风险射门 C（满蓄被扑给奶龙加速）。
## 用法： godot --headless --path . -- --super-test
func _run_super_test() -> void:
	campaign = false
	var passes: Array = []
	var failures: Array = []
	print("GULU SUPER TEST start")
	await _wait(0.6)
	reset_round()
	await _wait(0.3)
	_round_active = true
	_set_play_enabled(true)
	await _wait(0.1)
	_check(power_meter == 0, "meter starts empty", passes, failures)

	var speeds: Array = []
	for index in range(3):
		await _setup_super_kick()
		var kicked := _try_kick(1.5)
		await _wait(0.07)
		speeds.append(_ball_speed())
		_check(kicked, "full-charge kick %d accepted" % (index + 1), passes, failures)
	_check(power_meter == METER_MAX, "three full charges fill the meter (%d)" % power_meter,
		passes, failures)
	await _wait(0.1)
	_check(_meter_label != null and _meter_label.text.contains("超载"),
		"meter HUD announces overload", passes, failures)

	var base_speed := float(speeds[2]) if speeds.size() >= 3 else 0.0
	await _setup_super_kick()
	var overload_kicked := _try_kick(1.5)
	await _wait(0.07)
	var overload_speed := _ball_speed()
	_check(overload_kicked, "overload kick accepted", passes, failures)
	_check(_last_shot_overload, "overload flag set", passes, failures)
	_check(power_meter == 0, "meter resets after the overload shot", passes, failures)
	_check(overload_speed > base_speed * 1.5,
		"overload shot is much faster (%.1f vs %.1f m/s)" % [overload_speed, base_speed],
		passes, failures)

	# 风险射门 C：满蓄被扑 → 奶龙加速 5 s
	var base_walk := float(dragon.get("walk_speed"))
	_last_shot_full_charge = true
	_on_dragon_blocked(Vector3.ZERO, 1.0)
	await _wait(0.05)
	_check(_dragon_boost_left > DRAGON_BOOST_SECONDS - 0.5,
		"saved full charge boosts the keeper (%.1f s)" % _dragon_boost_left, passes, failures)
	_check(float(dragon.get("walk_speed")) > base_walk,
		"keeper walks faster during the boost (%.2f > %.2f)" % [float(dragon.get("walk_speed")), base_walk],
		passes, failures)

	_dragon_boost_left = 0.02
	await _wait(0.3)
	_check(_dragon_boost_left <= 0.0, "boost expires", passes, failures)
	_check(absf(float(dragon.get("walk_speed")) - base_walk) < 0.05,
		"keeper speed restored after the boost (%.2f)" % float(dragon.get("walk_speed")),
		passes, failures)

	print("GULU SUPER SUMMARY passes=%d failures=%d" % [passes.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _setup_super_kick() -> void:
	if ball != null:
		var spawn_ball: Vector3 = BALL_HOME
		if campaign and current_arena() != 0:
			var spots := stage_ball_spots()
			spawn_ball = spots[randi() % spots.size()]
		ball.call("reset_to", spawn_ball)
	_place_player(BALL_HOME + Vector3(-1.4, 0.02, 0.0), BALL_HOME)
	_aim_at(BALL_HOME + Vector3(6.0, 0.5, 0.0))
	await _wait(0.15)


# ---------------------------------------------------------------- 进程层自测（P1）

## 挑战清单 + 三档难度 + 分档最高分 + 存档。测试结束会把玩家存档还原。
## 用法： godot --headless --path . -- --progress-test
func _run_progress_test() -> void:
	var passes: Array = []
	var failures: Array = []
	print("GULU PROGRESS TEST start")
	await _wait(0.5)
	var saved_best: Array[int] = best_by_tier.duplicate()
	var saved_challenges: Dictionary = challenges.duplicate()
	var saved_tier: int = difficulty_tier

	reset_round()
	await _wait(0.2)
	for id in CHALLENGE_LIST:
		challenges[id] = false
	# 造一局“满贯”：3 球 / 连击 6 / 订单 3 次 / 超载 / 高台 / 1200 分 / 零封
	goals_this_round = 3
	best_combo_this_round = 6
	_order_hits = 3
	_overload_used = true
	_high_goal = true
	score = 1200
	saves_this_round = 0
	var newly: Array[String] = evaluate_challenges()
	_check(newly.size() >= 8, "a great round unlocks many challenges (%d)" % newly.size(),
		passes, failures)
	_check(bool(challenges.get("first_goal", false)) and bool(challenges.get("score1000", false))
		and bool(challenges.get("unbeaten", false)) and bool(challenges.get("overload", false)),
		"key challenges recorded", passes, failures)
	var again: Array[String] = evaluate_challenges()
	_check(again.is_empty(), "already-earned challenges are not re-awarded (%d)" % again.size(),
		passes, failures)
	_check(challenges_done() >= 8, "challenge counter tracks progress (%d)" % challenges_done(),
		passes, failures)

	# 三档难度：只缩放奶龙速度/反应
	var base_walk := float(_dragon_defaults["walk_speed"])
	set_difficulty_tier(0)
	await _wait(0.05)
	_check(absf(float(dragon.get("walk_speed")) - base_walk * TIER_SPEED[0]) < 0.02,
		"easy tier slows the keeper (%.2f)" % float(dragon.get("walk_speed")), passes, failures)
	set_difficulty_tier(2)
	await _wait(0.05)
	_check(absf(float(dragon.get("walk_speed")) - base_walk * TIER_SPEED[2]) < 0.02,
		"hard tier speeds the keeper (%.2f)" % float(dragon.get("walk_speed")), passes, failures)

	# 分档最高分互不干扰
	best_by_tier = [111, 222, 333]
	set_difficulty_tier(0)
	_check(best_score == 111, "easy best score is isolated (%d)" % best_score, passes, failures)
	set_difficulty_tier(2)
	_check(best_score == 333, "hard best score is isolated (%d)" % best_score, passes, failures)

	# 存档：写盘后能读回分档最高分与挑战状态
	_save_progress()
	var cfg := ConfigFile.new()
	var loaded := cfg.load(RECORD_FILE) == OK
	_check(loaded and int(cfg.get_value("record", "best_2", -1)) == 333,
		"per-tier best persisted", passes, failures)
	_check(loaded and bool(cfg.get_value("challenges", "first_goal", false)),
		"challenge state persisted", passes, failures)

	# 还原玩家存档，避免测试污染纪录
	best_by_tier = saved_best
	challenges = saved_challenges
	set_difficulty_tier(saved_tier)
	_save_progress()

	print("GULU PROGRESS SUMMARY passes=%d failures=%d" % [passes.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


# ---------------------------------------------------------------- 练习关自测（P1）

## 三个练习关：进入、目标计数、完成横幅、回标题。
## 用法： godot --headless --path . -- --practice-test
func _run_practice_test() -> void:
	var passes: Array = []
	var failures: Array = []
	print("GULU PRACTICE TEST start")
	await _wait(0.5)
	reset_round()
	await _wait(0.2)

	# 练习 1：定点射门 —— 三次订单命中
	start_practice(1)
	_on_countdown_finished()
	await _wait(0.1)
	_check(practice_mode == 1, "aim drill armed", passes, failures)
	_check(absf(round_time_left - PRACTICE_SECONDS) < 1.0,
		"practice round runs 60 s (%.0f)" % round_time_left, passes, failures)
	_check(_practice_goal == 3, "aim drill needs three hits", passes, failures)
	for index in range(2):
		collector.set("last_goal_zone", order_zone)
		_on_goal_scored(1, goal_target)
		await _wait(0.05)
	_check(not completed, "aim drill is not done after two hits", passes, failures)
	collector.set("last_goal_zone", order_zone)
	_on_goal_scored(1, goal_target)
	await _wait(0.05)
	_check(completed, "aim drill completes on the third hit", passes, failures)
	_check(_banner_label.text.contains("练习完成"), "completion banner appears", passes, failures)

	# 练习 3：连击保持 —— 连击到 x4
	start_practice(3)
	_on_countdown_finished()
	await _wait(0.1)
	combo = 3
	collector.set("last_goal_zone", -1)
	_on_goal_scored(1, goal_target)
	await _wait(0.05)
	_check(completed and _practice_done >= 1, "combo drill completes at x4", passes, failures)

	# 练习 2：骗守门员 —— 扑空后 3 秒内进球，共两次
	start_practice(2)
	_on_countdown_finished()
	await _wait(0.1)
	for index in range(2):
		_last_whiff_ms = Time.get_ticks_msec()
		collector.set("last_goal_zone", -1)
		_on_goal_scored(1, goal_target)
		await _wait(0.05)
	_check(completed, "feint drill completes after two whiff-goals", passes, failures)
	_check(_practice_done >= 2, "feint drill counted both goals (%d)" % _practice_done,
		passes, failures)

	# 回标题
	_exit_practice()
	await _wait(0.1)
	_check(practice_mode == 0, "T exits the practice", passes, failures)
	_check(not _round_active, "title is not an active round", passes, failures)
	_check(bool(_presentation.call("title_visible")), "title screen is back", passes, failures)

	print("GULU PRACTICE SUMMARY passes=%d failures=%d" % [passes.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


# ---------------------------------------------------------------- 偷球自测（提案 B）

## 奶龙偷球：强制触发、球冻结、E 抢回 + 必杀槽、冷却、4 秒自动吐球、每局上限。
## 用法： godot --headless --path . -- --steal-test
func _run_steal_test() -> void:
	var passes: Array = []
	var failures: Array = []
	print("GULU STEAL TEST start")
	await _wait(0.6)
	reset_round()
	await _wait(0.2)
	_round_active = true
	_set_play_enabled(true)
	await _wait(0.1)
	_check(not _ball_carried, "ball starts free", passes, failures)

	_steal_force_next = true
	_on_dragon_blocked(Vector3.ZERO, 1.0)
	await _wait(0.08)
	_check(_ball_carried, "keeper steals the ball", passes, failures)
	_check(bool(ball.get("freeze")), "carried ball is frozen", passes, failures)
	_check(steals_used == 1, "steal counted (%d)" % steals_used, passes, failures)
	_check(_carry_label != null and _carry_label.visible, "carry hint is visible", passes, failures)
	_check(not _try_kick(1.0), "cannot kick a carried ball", passes, failures)

	# 靠近 + E 抢回
	_place_player(ball.global_position + Vector3(-1.6, 0.0, 0.0), ball.global_position)
	await _wait(0.12)
	var meter_before := power_meter
	Input.action_press("retrieve")
	await _wait(0.25)
	Input.action_release("retrieve")
	await _wait(0.1)
	_check(not _ball_carried, "press E retrieves the ball", passes, failures)
	_check(power_meter == mini(meter_before + 1, METER_MAX),
		"retrieval charges the meter (%d -> %d)" % [meter_before, power_meter], passes, failures)

	# 冷却内再拦不再偷
	_steal_force_next = true
	_on_dragon_blocked(Vector3.ZERO, 1.0)
	await _wait(0.05)
	_check(not _ball_carried, "steal is on cooldown", passes, failures)

	# 冷却结束后第二次偷球，4 秒自动吐球
	_steal_cooldown_left = 0.0
	_steal_force_next = true
	_on_dragon_blocked(Vector3.ZERO, 1.0)
	await _wait(0.08)
	_check(_ball_carried and steals_used == 2, "second steal allowed after cooldown",
		passes, failures)
	_carry_left = 0.05
	await _wait(0.25)
	_check(not _ball_carried, "ball is dropped when the carry timer ends", passes, failures)
	_check(not bool(ball.get("freeze")), "dropped ball is live again", passes, failures)

	# 每局上限 2 次
	_steal_cooldown_left = 0.0
	_steal_force_next = true
	_on_dragon_blocked(Vector3.ZERO, 1.0)
	await _wait(0.05)
	_check(not _ball_carried and steals_used == STEAL_LIMIT,
		"steal limit respected (%d)" % steals_used, passes, failures)

	print("GULU STEAL SUMMARY passes=%d failures=%d" % [passes.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


# ---------------------------------------------------------------- 时段预设自测（P2）

## 三个时段只改天空/环境光/雾/灯光；同时确认玩法完全不受影响。
## 用法： godot --headless --path . -- --tod-test
func _run_tod_test() -> void:
	var passes: Array = []
	var failures: Array = []
	print("GULU TOD TEST start")
	await _wait(0.5)
	_check(_sun != null and _env != null and _sky_material != null,
		"environment refs captured", passes, failures)
	var noon_sun: float = _sun.light_energy
	var noon_fog: float = _env.fog_density
	var noon_ambient: float = _env.ambient_light_energy

	set_time_of_day(1)
	await _wait(0.08)
	_check(absf(_sun.light_energy - noon_sun) > 0.01,
		"dusk changes the sun energy (%.2f)" % _sun.light_energy, passes, failures)
	_check(_env.fog_density > noon_fog, "dusk thickens the fog (%.4f)" % _env.fog_density,
		passes, failures)
	_check(_sun.light_color != Color("#fff0d2"), "dusk changes the sun colour", passes, failures)

	set_time_of_day(2)
	await _wait(0.08)
	_check(_env.ambient_light_energy < noon_ambient,
		"night dims the ambient (%.2f)" % _env.ambient_light_energy, passes, failures)
	_check(_env.fog_density > noon_fog, "night fog is the thickest (%.4f)" % _env.fog_density,
		passes, failures)

	set_time_of_day(0)
	await _wait(0.08)
	_check(absf(_sun.light_energy - noon_sun) < 0.001 and absf(_env.fog_density - noon_fog) < 0.0001,
		"noon restores the baseline", passes, failures)
	var time_label := _presentation.get("_title_time") as Label
	_check(time_label != null and time_label.text.contains("正午"),
		"title screen shows the preset", passes, failures)

	# 玩法不受影响：同一脚球的初速不变
	_round_active = true
	_set_play_enabled(true)
	await _setup_super_kick()
	var kicked := _try_kick(1.0)
	await _wait(0.07)
	_check(kicked and _ball_speed() > 8.0,
		"gameplay is unaffected by the preset (%.1f m/s)" % _ball_speed(), passes, failures)

	print("GULU TOD SUMMARY passes=%d failures=%d" % [passes.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


# ---------------------------------------------------------------- 记录板自测（P2）

## 记录板：数据来源（三档最高分 / 挑战 / 时段）、面板可见、可关闭。
## 用法： godot --headless --path . -- --records-test
func _run_records_test() -> void:
	var passes: Array = []
	var failures: Array = []
	print("GULU RECORDS TEST start")
	await _wait(0.4)
	var entries := _records_entries()
	_check((entries.get("tiers", []) as Array).size() == 3, "records carry three difficulty rows",
		passes, failures)
	_check((entries.get("names", []) as Array).size() == 3, "records carry the tier names",
		passes, failures)
	_check(int(entries.get("total", 0)) == CHALLENGE_LIST.size(),
		"records carry all challenges (%d)" % int(entries.get("total", 0)), passes, failures)
	_check(int(entries.get("done", -1)) == challenges_done(),
		"records show the earned challenge count", passes, failures)
	_check((entries.get("challenges", []) as Array).size() == CHALLENGE_LIST.size(),
		"records carry one row per challenge", passes, failures)

	_open_records()
	await _wait(0.1)
	_check(bool(_presentation.call("records_visible")), "records panel opens", passes, failures)
	_presentation.call("hide_records")
	await _wait(0.1)
	_check(not bool(_presentation.call("records_visible")), "records panel closes", passes, failures)

	print("GULU RECORDS SUMMARY passes=%d failures=%d" % [passes.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)




















