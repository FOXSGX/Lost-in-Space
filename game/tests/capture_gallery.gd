extends SceneTree

## Final screenshot gallery. Every frame is the real first-person player camera.

var app: Node3D
var player: PlayerController
var level: LevelBuilder
var story: StoryDirector
var hud: GameHud
var out_dir: String = "C:/Users/ASUS/Desktop/迷失太空/work/deepseek-resonance-05-quality-polish/evidence/gallery_iter"


func _initialize() -> void:
	run.call_deferred()


func frames(n: int) -> void:
	for _i in range(n):
		await physics_frame


func shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])
	print("SHOT ", name)


func clean(objective: String = "") -> void:
	hud.title_layer.visible = false
	hud.clear_subtitles()
	hud.toast_label.visible = false
	hud.set_prompt("")
	if objective != "":
		hud.set_objective(objective)


func tp(pos: Vector3, yaw: float, pitch: float) -> void:
	player.force_exit_operate()
	player.teleport(pos, yaw, pitch)
	await frames(12)


func set_carts(l: float, r: float) -> void:
	level.left_cart.set_p(l)
	level.right_cart.set_p(r)
	level.core.set_weights(l, r)
	await frames(360)


func run() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	await frames(100)
	player = app.get("player") as PlayerController
	level = app.get("level") as LevelBuilder
	story = app.get("story") as StoryDirector
	hud = app.get("hud") as GameHud
	clean()
	story.set_process(false)

	# 01 entrance
	await tp(Vector3(0, 4.06, 37.0), 0.0, -0.02)
	clean("深入 R-05 设施，前往地心共振大厅")
	await shot("01_entrance")
	# 02 balcony reveal
	await tp(Vector3(0, 4.06, 10.8), 0.0, 0.02)
	clean("观察失稳的共振核心，找到两侧配重控制台")
	await shot("02_first_sight")
	# 03 core hero view
	await set_carts(0.55, 0.05)
	await tp(Vector3(0, 4.06, 10.6), 0.0, 0.0)
	clean("操作两侧配重，把核心摆动压入捕获范围")
	print("CORE03 angle=", level.core.get_angle(), " net=", level.core.get_net(), " L=", level.left_cart.get_p(), " R=", level.right_cart.get_p())
	await shot("03_core_overall")
	# 04 unstable core
	await set_carts(0.12, 0.88)
	await shot("04_core_unstable")
	# 05 left counterweight
	await level.left_cart.set_p(0.90)
	level.core.set_weights(0.90, level.right_cart.get_p())
	await frames(20)
	await tp(Vector3(-9.025, 1.66, 7.625), -0.105, -0.04)
	clean("操作两侧配重，把核心摆动压入捕获范围")
	await shot("05_left_counterweight")
	# 06 right counterweight
	level.left_cart.set_p(0.12)
	await level.right_cart.set_p(0.90)
	level.core.set_weights(0.12, 0.90)
	await frames(20)
	await tp(Vector3(9.025, 1.66, 7.625), 0.105, -0.04)
	await shot("06_right_counterweight")
	# 07 first-person lever operation
	await tp(Vector3(-9.025, 1.66, 7.625), -PI * 0.25, 0.15)
	level.left_station.interact(player)
	await frames(10)
	Input.action_press("move_forward")
	await frames(360)
	clean()
	await shot("07_lever_first_person")
	Input.action_release("move_forward")
	player.force_exit_operate()
	# 08 improved balance
	await set_carts(0.58, 0.05)
	await frames(90)
	await tp(Vector3(0, 4.06, 10.6), 0.0, 0.0)
	clean()
	print("CORE08 angle=", level.core.get_angle(), " net=", level.core.get_net())
	await shot("08_core_balanced")
	# 09 overshoot / surge
	await set_carts(0.02, 0.9)
	level.core.play_surge(1.2)
	await frames(10)
	clean()
	await shot("09_overshoot")
	# 10 gauge close-up
	await tp(Vector3(0, 0.06, 9.4), 0.0, 0.12)
	clean("启动捕获锁爪")
	await shot("10_gauge")
	# 11 lock claw
	await tp(Vector3(0.8, 0.06, 5.9), -0.12, -0.30)
	clean()
	await shot("11_lock_claw")
	# 12 balancing for lock + locking action
	await set_carts(0.60, 0.03)
	await frames(80)
	level.core.request_lock()
	await frames(28)
	clean()
	await shot("12_locking")
	await frames(90)
	# 13 isolated rig
	await tp(Vector3(9.4, 0.06, -4.8), -0.42, -0.05)
	clean("拔出安全销，推动滑架分离联轴器")
	await shot("13_isolation_rig")
	level.isolation.pin_out = true
	level.isolation.force_separated_state()
	await frames(360)
	clean()
	await shot("14_coupling_separated")
	# 18 stable hall, before the data projection appears
	await tp(Vector3(0, 4.06, 10.6), 0.0, 0.0)
	clean("核心已稳定，准备取回数据")
	await shot("18_stable_hall")
	# 15 stable hall / data
	level.core.force_locked_state()
	level.core.set_data_mode(true)
	level.data_plinth.reveal()
	await frames(80)
	await tp(Vector3(-3.0, 0.06, -8.3), 0.0, -0.28)
	clean("取回显现的深空航行数据")
	await shot("15_navigation_data")
	# 16 exit corridor
	level.exit_door.open_door()
	await frames(180)
	await tp(Vector3(-13.2, 0.06, -2.0), PI * 0.5, 0.0)
	clean("从西侧紧急撤离通道离开")
	await shot("16_exit")
	# 17 completion card
	story.data_taken = true
	story.start_time = float(Time.get_ticks_msec()) / 1000.0 - 392.0
	story._on_exit_reached()
	await frames(140)
	await shot("17_completion")
	print("GALLERY_DONE")
	quit()








