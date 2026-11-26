extends SceneTree

## MECHANICS-005A · 第五幕稳定支腿真实液压 图形窗口取证（窗口 B）
##
##   tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --path game \
##       --script res://tests/mech005a_capture.gd
##
## 必须用有渲染的窗口模式运行（headless 截不到画面）。输出：
##   game/captures/mech005a/*.png
##
## 取证规则（与任务书一致）：
##   * 相机全部是正式第一人称玩家相机，没有任何证据相机。
##   * 只 teleport 玩家本人（正式 PlayerController），不传送任何物体/机械。
##   * 机械位移全部由真实输入 W 泵压产生：截图脚本从不写 extension / latched /
##     clamp_force / pressure，也不调用 force_latched()。
##   * 关闭碰撞、隐藏物体等作弊手段一律没有使用。
##   * 07/08 两张打开 F3 调试叠加层，用机器读数作为佐证；它们是**调试叠加层**，
##     不是正式 HUD，报告中已明确标注。

const OUT_DIR := "res://captures/mech005a"

var app: Node3D
var player: PlayerController
var level: LevelBuilder
var story: StoryDirector
var core: CoreRig
var hud: GameHud
var legs: Array[StabilizerRig] = []
var shots: Array[String] = []


func _initialize() -> void:
	run.call_deferred()


func frames(n: int) -> void:
	for _i in range(n):
		await physics_frame


func shot(name: String) -> void:
	await process_frame
	await process_frame
	var path: String = "%s/%s.png" % [OUT_DIR, name]
	root.get_texture().get_image().save_png(path)
	shots.append(name)
	print("SHOT %s  %s" % [name, path])


func clean(objective: String = "") -> void:
	hud.title_layer.visible = false
	hud.clear_subtitles()
	hud.set_prompt("")
	if objective != "":
		hud.set_objective(objective)


func look_at_from(pos: Vector3, target: Vector3, pitch_bias: float = 0.0) -> void:
	player.force_exit_operate()
	player.stop_grab()
	player.external_hold = false
	var d: Vector3 = target - pos
	var yaw: float = atan2(-d.x, -d.z)
	var flat: float = Vector2(d.x, d.z).length()
	var pitch: float = -atan2(target.y - (pos.y + 1.62), flat) + pitch_bias
	player.teleport(pos, yaw, clampf(pitch, -1.1, 1.1))
	await frames(16)


## Aim the operating player (body pinned at the console anchor) at a world point.
func aim_at(target: Vector3) -> void:
	var eye: Vector3 = player.global_position + Vector3(0, 1.62, 0)
	var d: Vector3 = target - eye
	var yaw: float = atan2(-d.x, -d.z)
	var flat: Vector2 = Vector2(d.x, d.z)
	var pitch: float = -atan2(d.y, maxf(flat.length(), 0.05))
	player.set_look(yaw, clampf(pitch, -1.1, 1.1))
	await frames(6)


func ram_target(index: int) -> Vector3:
	var leg: StabilizerRig = legs[index]
	return leg.to_global(Vector3(1.45 + leg.extension * StabilizerRig.STROKE, 7.05, 0.0))


func stand_at_leg(index: int, back: float = 1.6) -> void:
	var leg: StabilizerRig = legs[index]
	var pos: Vector3 = leg.area.global_position + leg.global_transform.basis.z * back
	pos.y = 0.06
	await look_at_from(pos, leg.area.global_position + Vector3(0, 0.35, 0))


func hold_until(index: int, seconds: float, cond: Callable) -> void:
	Input.action_press("move_forward")
	var budget: int = int(round(seconds * 60.0))
	for _i in range(budget):
		await physics_frame
		if bool(cond.call()):
			break
	Input.action_release("move_forward")
	await frames(2)


func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	await frames(90)
	player = app.get("player") as PlayerController
	level = app.get("level") as LevelBuilder
	story = app.get("story") as StoryDirector
	hud = app.get("hud") as GameHud
	core = level.get("core") as CoreRig
	legs = level.stabilizers
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await frames(40)

	# 1. 地心设施初始状态（两条支腿完全收回，正式出生点一侧的观景台视角）
	clean("深入 R-05 设施，前往地心共振大厅")
	await look_at_from(Vector3(0, 5.9, 14.0), Vector3(0, 1.4, 0.0), 0.0)
	await shot("01_hall_initial")

	# 走正式入口触发体进入大厅，让阶段机与反冲导演按正常流程启动
	await look_at_from(Vector3(0, 4.06, 12.2), Vector3(0, 4.06, 0.0))
	for _i in range(120):
		if story.stage >= StoryDirector.Stage.DISCOVER_INSTABILITY:
			break
		await physics_frame
	print("CAPTURE_ENTER stage=%d" % story.stage)

	# 2. 玩家靠近机械：站在西侧支腿操作台前，HUD 出现真实交互提示
	await stand_at_leg(0)
	await frames(24)
	await shot("02_approach_west_console")

	# 3. 玩家开始操作：按 E 进入工位，手压泵开始动作
	await stand_at_leg(0)
	await frames(10)
	Input.action_press("interact")
	await frames(3)
	Input.action_release("interact")
	await frames(10)
	var operating: bool = player.operating
	await aim_at(legs[0].to_global(Vector3(1.25, 6.95, 0.0)))
	await shot("03_operate_started")

	# 4a. 机械真实运动：按住 W，活塞在真实液压推动下伸出（中途取帧）
	Input.action_press("move_forward")
	for _i in range(40):
		await physics_frame
	var ext_mid: float = legs[0].extension
	var v_mid: float = legs[0].ram_velocity
	await aim_at(ram_target(0))
	await shot("04a_ram_in_motion")
	Input.action_release("move_forward")
	await frames(2)
	print("CAPTURE_MOTION ext=%.3f v=%.3f m/s p=%.2f MPa load=%.1f kN" % [ext_mid, v_mid,
		legs[0].pressure * StabilizerRig.RELIEF / 1.0e6, legs[0].load_force / 1000.0])

	# 4b. 负载响应：继续泵压到压板咬住平衡环，读数切到“承载/过载”
	await hold_until(0, 2.6, func() -> bool: return legs[0].contact)
	for _i in range(12):
		await physics_frame
	await aim_at(ram_target(0))
	await shot("04b_contact_load")
	print("CAPTURE_CONTACT contact=%s stall=%s load=%.1f kN p=%.2f MPa ext=%.3f" % [
		str(legs[0].contact), str(legs[0].stalled), legs[0].load_force / 1000.0,
		legs[0].pressure * StabilizerRig.RELIEF / 1.0e6, legs[0].extension])

	# 5. 机械锁止成立：棘爪落到齿条、单向阀封住缸压，HUD 弹出夹持力提示
	await hold_until(0, 4.0, func() -> bool: return legs[0].latched)
	if player.operating:
		Input.action_press("interact")
		await frames(3)
		Input.action_release("interact")
		await frames(4)
	await aim_at(ram_target(0))
	await shot("05_latched_west")

	# 6. 后续剧情正常继续：东侧支腿同样真实锁止，配重把核心压进捕获窗口，
	#    阶段机自己进入 CAPTURE_READY，画面回到地心大厅。
	await stand_at_leg(1)
	await frames(10)
	Input.action_press("interact")
	await frames(3)
	Input.action_release("interact")
	await frames(10)
	await hold_until(1, 4.0, func() -> bool: return legs[1].latched)
	if player.operating:
		Input.action_press("interact")
		await frames(3)
		Input.action_release("interact")
		await frames(4)
	await balance_core()
	var capturable: bool = core.is_capturable()
	clean("")
	await look_at_from(Vector3(0, 1.7, 9.4), Vector3(0, 3.4, -2.0), 0.02)
	await shot("06_story_continues")
	print("CAPTURE_STORY latched=%d/%d stage=%d capturable=%s net=%.3f omega=%.3f limit=%.3f" % [
		level.stabilizers_latched(), legs.size(), story.stage, str(capturable),
		core.get_net(), core.get_omega(), core.capture_net_limit()])

	# 7/8. 调试叠加层证据帧（**证据用调试 HUD，不是正式 HUD**）：把真实液压读数
	#      （压力/负载/夹持力/速度/止挡）与核心状态叠在画面上。
	app.call("_toggle_debug")
	await frames(20)
	await look_at_from(Vector3(0, 1.7, 8.6), Vector3(0, 3.2, -2.0), 0.02)
	await shot("07_debug_core_state")
	await stand_at_leg(0)
	await frames(20)
	await shot("08_debug_leg_state")
	app.call("_toggle_debug")

	print("CAPTURE_DONE shots=%d operating=%s" % [shots.size(), str(operating)])
	quit(0)


## 只用真实手柄把核心压进捕获范围（与玩家操作一致，不写任何机械状态）。
func balance_core() -> void:
	for _try in range(8):
		if core.is_capturable():
			break
		await look_at_from(Vector3(8.5, 1.70, 7.47), level.right_station.area.global_position)
		Input.action_press("interact")
		await frames(3)
		Input.action_release("interact")
		await frames(10)
		if not player.operating:
			continue
		var dir: String = "move_back" if core.get_net() > 0.0 else "move_forward"
		Input.action_press(dir)
		var budget: int = int(round((8.0 if _try == 0 else 1.6) * 60.0))
		for _i in range(budget):
			await physics_frame
		Input.action_release(dir)
		await frames(3)
		Input.action_press("interact")
		await frames(3)
		Input.action_release("interact")
		await frames(40)
