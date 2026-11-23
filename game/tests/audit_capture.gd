extends SceneTree

## Developer audit camera. Not a gameplay capture: the camera is detached from
## the player so we can inspect a specific joint, wheel/rail contact or ring
## silhouette from a chosen angle. Delivery screenshots are taken by
## capture_polish.gd through the real first-person camera.

var app: Node3D
var player: PlayerController
var level: LevelBuilder
var story: StoryDirector
var hud: GameHud
var cam: Camera3D
var out_dir: String = ""


func _initialize() -> void:
	run.call_deferred()


func frames(n: int) -> void:
	for _i in range(n):
		await physics_frame


func shot(name: String) -> void:
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png("%s/%s.png" % [out_dir, name])
	print("SHOT ", name)


func look(pos: Vector3, target: Vector3, fov: float = 62.0) -> void:
	cam.global_position = pos
	cam.fov = fov
	cam.look_at(target, Vector3.UP)


func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else "res://tests-out/audit_shots"
	DirAccess.make_dir_recursive_absolute(out_dir)
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	await frames(90)
	player = app.get("player") as PlayerController
	level = app.get("level") as LevelBuilder
	story = app.get("story") as StoryDirector
	hud = app.get("hud") as GameHud
	story.set_process(false)
	story.set_physics_process(false)
	hud.title_layer.visible = false
	hud.clear_subtitles()
	hud.toast_label.visible = false
	hud.set_prompt("")
	hud.set_objective("")
	player.camera.current = false
	cam = Camera3D.new()
	cam.fov = 62.0
	cam.near = 0.03
	cam.far = 260.0
	cam.current = true
	level.add_child(cam)

	# --- entrance tunnel -----------------------------------------------------
	look(Vector3(0, 5.4, 34.0), Vector3(0, 5.8, 12.0), 70.0)
	await shot("a01_tunnel_center")
	look(Vector3(1.8, 4.6, 33.0), Vector3(-2.0, 5.0, 22.0), 68.0)
	await shot("a02_tunnel_side")
	look(Vector3(0, 4.4, 27.5), Vector3(0, 5.2, 24.0), 74.0)
	await shot("a03_tunnel_door")
	look(Vector3(-2.0, 4.9, 37.0), Vector3(2.4, 5.2, 26.0), 80.0)
	await shot("a04_tunnel_ceiling")

	# --- balcony / hall reveal ----------------------------------------------
	look(Vector3(0, 5.6, 11.0), Vector3(0, 5.0, -2.0), 62.0)
	await shot("a05_balcony")
	look(Vector3(0, 4.4, 10.4), Vector3(0, 1.2, 2.0), 74.0)
	await shot("a06_balcony_floor")

	# --- core: several angles / states --------------------------------------
	level.left_cart.set_p(0.12)
	level.right_cart.set_p(0.88)
	level.core.set_weights(0.12, 0.88)
	await frames(60)
	look(Vector3(0, 6.2, 9.0), Vector3(0, 7.2, -2.0), 58.0)
	await shot("a07_core_front_tilted")
	look(Vector3(9.0, 7.2, 5.4), Vector3(0, 7.0, -2.0), 58.0)
	await shot("a08_core_side")
	look(Vector3(0, 2.0, 4.0), Vector3(0, 8.0, -2.0), 74.0)
	await shot("a09_core_below")
	look(Vector3(0, 12.0, 5.0), Vector3(0, 16.5, -2.0), 62.0)
	await shot("a10_core_top_support")
	look(Vector3(3.0, 8.8, 2.0), Vector3(0, 8.6, -2.0), 52.0)
	await shot("a11_core_close")
	# balanced / locked
	level.left_cart.set_p(0.55)
	level.right_cart.set_p(0.06)
	level.core.set_weights(0.55, 0.06)
	await frames(150)
	look(Vector3(0, 6.2, 9.0), Vector3(0, 7.2, -2.0), 58.0)
	await shot("a12_core_balanced")
	level.core.force_locked_state()
	level.lock_rig.force_locked_visual()
	await frames(20)
	look(Vector3(2.4, 4.4, 5.2), Vector3(0, 4.3, 0.0), 62.0)
	await shot("a13_core_locked_close")
	look(Vector3(0, 4.4, 9.0), Vector3(0, 4.25, 0.0), 58.0)
	await shot("a14_lock_front")
	level.lock_rig.reset_state()
	level.core.reset_state()

	# --- counterweight station / cart / rail --------------------------------
	level.left_cart.set_p(0.85)
	level.core.set_weights(0.85, level.right_cart.get_p())
	await frames(40)
	look(Vector3(-9.6, 3.3, 8.4), Vector3(-6.2, 2.9, 3.6), 66.0)
	await shot("a15_left_cart_from_station")
	look(Vector3(-6.4, 3.1, 6.6), Vector3(-6.4, 2.2, 3.6), 66.0)
	await shot("a16_left_cart_side")
	look(Vector3(-10.2, 2.4, 5.4), Vector3(-7.0, 2.2, 3.6), 70.0)
	await shot("a17_left_rail_from_floor")
	look(Vector3(-8.0, 2.65, 9.4), Vector3(-8.0, 2.55, 6.2), 72.0)
	await shot("a18_station_console")
	look(Vector3(-8.0, 2.7, 5.1), Vector3(-8.0, 3.4, 6.9), 78.0)
	await shot("a19_station_lever_front")
	look(Vector3(-8.55, 3.0, 6.9), Vector3(-8.6, 1.4, 6.7), 80.0)
	await shot("a20_station_pedestal")
	level.left_cart.set_p(0.12)
	level.core.set_weights(0.12, level.right_cart.get_p())
	await frames(30)
	look(Vector3(-5.2, 3.0, 5.6), Vector3(-4.6, 2.5, 3.6), 66.0)
	await shot("a21_cart_inner_end")

	# --- isolation -----------------------------------------------------------
	look(Vector3(8.2, 2.4, -4.4), Vector3(10.5, 1.3, -9.0), 62.0)
	await shot("a22_isolation_front")
	look(Vector3(10.5, 2.2, -5.2), Vector3(10.5, 1.2, -9.0), 66.0)
	await shot("a23_isolation_clutch")
	look(Vector3(7.0, 1.7, -7.0), Vector3(10.5, 1.2, -9.0), 70.0)
	await shot("a24_isolation_side")
	level.isolation.pin_out = true
	level.isolation.force_separated_state()
	await frames(20)
	look(Vector3(10.5, 2.2, -5.2), Vector3(10.5, 1.2, -9.0), 66.0)
	await shot("a25_isolation_separated")

	# --- memory / data / exit ------------------------------------------------
	look(Vector3(-8.4, 2.3, 4.4), Vector3(-10.5, 1.0, 2.0), 66.0)
	await shot("a26_memory_shard")
	level.core.force_locked_state()
	level.data_plinth.reveal()
	await frames(120)
	look(Vector3(-3.0, 1.9, -7.4), Vector3(-3.0, 2.1, -10.0), 66.0)
	await shot("a27_data_plinth")
	level.exit_door.open_door()
	await frames(180)
	look(Vector3(-14.4, 1.9, -2.0), Vector3(-24.0, 1.6, -2.0), 68.0)
	await shot("a28_exit_corridor")
	look(Vector3(-15.2, 2.2, -2.0), Vector3(-15.2, 2.0, -6.0), 84.0)
	await shot("a29_exit_portal_side")
	look(Vector3(-12.0, 2.6, 0.8), Vector3(-16.0, 1.6, -2.0), 74.0)
	await shot("a30_exit_approach")

	# --- hall overview -------------------------------------------------------
	look(Vector3(0, 10.5, 14.5), Vector3(0, 3.5, -6.0), 70.0)
	await shot("a31_hall_overview")
	look(Vector3(-12.0, 3.0, 8.0), Vector3(5.0, 4.0, -4.0), 78.0)
	await shot("a32_hall_from_west")
	print("AUDIT_CAPTURE_DONE")
	quit()
