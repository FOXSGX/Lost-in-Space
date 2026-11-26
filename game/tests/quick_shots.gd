extends SceneTree

## Fast developer iteration shots. Usage:
##   godot --path PROJECT --script res://tests/quick_shots.gd -- OUT_DIR SET
## SET is one of: core, carts, station, lock, isolation, exit, rocks, entrance.

var app: Node3D
var level: LevelBuilder
var cam: Camera3D
var out_dir: String = ""
var frames_n: int = 0


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
	print("LOOK pos=", cam.global_position, " fwd=", -cam.global_transform.basis.z, " vp=", root.get_visible_rect())


func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else "res://tests-out/quick"
	var set_name: String = args[1] if args.size() > 1 else "core"
	DirAccess.make_dir_recursive_absolute(out_dir)
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	await frames(80)
	var player: PlayerController = app.get("player") as PlayerController
	level = app.get("level") as LevelBuilder
	var story: StoryDirector = app.get("story") as StoryDirector
	var hud: GameHud = app.get("hud") as GameHud
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
	match set_name:
		"core":
			await core_shots()
		"carts":
			await cart_shots()
		"station":
			await station_shots()
		"lock":
			await lock_shots()
		"isolation":
			await isolation_shots()
		"exit":
			await exit_shots()
		"rocks":
			await rock_shots()
		"entrance":
			await entrance_shots()
		"debug":
			await debug_shots()
	print("QUICK_DONE ", set_name)
	quit()


func debug_shots() -> void:
	look(Vector3(0, 20.0, 22.0), Vector3(0, 4.0, -2.0), 70.0)
	await shot("dbg_overview")
	look(Vector3(0, 9.0, 9.0), Vector3(0, 4.0, -2.0), 66.0)
	await shot("dbg_front_level")
	look(Vector3(0, 6.2, 9.0), Vector3(0, 1.0, 2.0), 66.0)
	await shot("dbg_front_down")
	look(Vector3(0, 6.2, 9.0), Vector3(0, 7.2, -2.0), 66.0)
	await shot("dbg_front_up")
	look(Vector3(0, 4.5, 14.0), Vector3(0, 6.0, -2.0), 66.0)
	await shot("dbg_balcony")


func core_shots() -> void:
	level.left_cart.set_p(0.12)
	level.right_cart.set_p(0.88)
	level.core.set_weights(0.12, 0.88)
	await frames(40)
	look(Vector3(0, 6.2, 9.0), Vector3(0, 7.2, -2.0), 58.0)
	await shot("core_front")
	look(Vector3(9.0, 7.2, 5.4), Vector3(0, 7.0, -2.0), 58.0)
	await shot("core_side")
	look(Vector3(0, 12.0, 5.0), Vector3(0, 16.5, -2.0), 62.0)
	await shot("core_support")
	look(Vector3(3.0, 8.8, 2.0), Vector3(0, 8.6, -2.0), 52.0)
	await shot("core_close")
	level.core.force_locked_state()
	await frames(20)
	look(Vector3(0, 6.2, 9.0), Vector3(0, 7.2, -2.0), 58.0)
	await shot("core_locked")


func cart_shots() -> void:
	level.left_cart.set_p(0.85)
	level.core.set_weights(0.85, level.right_cart.get_p())
	await frames(30)
	look(Vector3(-9.8, 3.4, 8.6), Vector3(-7.0, 2.6, 3.0), 62.0)
	await shot("cart_from_station")
	look(Vector3(-7.0, 2.6, 8.2), Vector3(-7.0, 2.4, 1.2), 66.0)
	await shot("cart_side")
	look(Vector3(-11.0, 1.8, 5.4), Vector3(-7.0, 2.2, 1.2), 70.0)
	await shot("cart_from_floor")
	look(Vector3(-10.4, 2.9, 3.4), Vector3(-6.2, 2.5, 1.2), 66.0)
	await shot("cart_along_track")
	level.left_cart.set_p(0.05)
	level.core.set_weights(0.05, level.right_cart.get_p())
	await frames(20)
	look(Vector3(-9.0, 2.4, 3.0), Vector3(-6.0, 2.6, 1.2), 66.0)
	await shot("cart_inner")


func station_shots() -> void:
	level.left_cart.set_p(0.8)
	level.core.set_weights(0.8, level.right_cart.get_p())
	var player: PlayerController = app.get("player") as PlayerController
	player.camera.current = false
	look(Vector3(-9.025, 3.25, 7.625), Vector3(-8.0, 2.7, 5.6), 66.0)
	await shot("station_eye")
	look(Vector3(-8.0, 3.4, 8.6), Vector3(-8.0, 2.4, 6.4), 68.0)
	await shot("station_front")
	look(Vector3(-6.6, 2.8, 7.4), Vector3(-8.0, 2.6, 6.6), 62.0)
	await shot("station_threequarter")
	level.left_station.interact(player)
	await frames(20)
	await shot("station_grab")


func lock_shots() -> void:
	level.core.force_locked_state()
	level.lock_rig.force_locked_visual()
	await frames(10)
	look(Vector3(0, 3.8, 8.4), Vector3(0, 4.2, 0.0), 60.0)
	await shot("lock_from_console")
	look(Vector3(3.6, 3.2, 5.8), Vector3(0, 4.2, 0.0), 62.0)
	await shot("lock_claws")
	look(Vector3(1.4, 5.2, 3.2), Vector3(0, 4.3, 0.0), 60.0)
	await shot("lock_top")
	look(Vector3(0, 1.3, 6.4), Vector3(0, 4.2, 0.0), 72.0)
	await shot("lock_from_floor")


func isolation_shots() -> void:
	level.core.force_locked_state()
	look(Vector3(10.6, 2.2, -5.0), Vector3(10.4, 1.3, -9.0), 64.0)
	await shot("iso_front")
	look(Vector3(8.6, 1.6, -8.0), Vector3(10.4, 1.3, -9.0), 64.0)
	await shot("iso_clutch")
	look(Vector3(10.4, 2.2, -6.2), Vector3(10.4, 1.3, -9.0), 66.0)
	await shot("iso_handle")
	level.isolation.force_separated_state()
	await frames(10)
	look(Vector3(10.4, 2.2, -6.2), Vector3(10.4, 1.3, -9.0), 66.0)
	await shot("iso_separated")
	look(Vector3(7.2, 2.4, -6.6), Vector3(10.4, 1.3, -9.0), 68.0)
	await shot("iso_side")
	look(Vector3(10.4, 3.6, -5.2), Vector3(10.4, 0.8, -9.6), 72.0)
	await shot("iso_above")


func exit_shots() -> void:
	level.exit_door.open_door()
	await frames(220)
	look(Vector3(-13.6, 2.2, -2.0), Vector3(-22.0, 1.4, -2.0), 66.0)
	await shot("exit_down")
	look(Vector3(-15.4, 2.4, -2.0), Vector3(-15.4, 2.4, -6.0), 80.0)
	await shot("exit_wall")
	look(Vector3(-18.0, 2.0, -2.0), Vector3(-15.0, 2.0, -2.0), 68.0)
	await shot("exit_back")
	look(Vector3(-28.4, 2.0, -2.0), Vector3(-20.0, 1.8, -2.0), 66.0)
	await shot("exit_lift")


func rock_shots() -> void:
	look(Vector3(0, 8.0, 12.0), Vector3(-6.0, 6.0, -6.0), 76.0)
	await shot("rocks_west")
	look(Vector3(0, 8.0, 12.0), Vector3(7.0, 6.0, -6.0), 76.0)
	await shot("rocks_east")
	look(Vector3(0, 12.0, 8.0), Vector3(0, 18.0, -2.0), 80.0)
	await shot("rocks_ceiling")
	look(Vector3(-11.0, 3.0, 6.0), Vector3(-14.5, 4.0, -3.0), 72.0)
	await shot("rocks_wall_west")
	look(Vector3(11.0, 3.0, 6.0), Vector3(14.5, 4.0, -3.0), 72.0)
	await shot("rocks_wall_east")


func entrance_shots() -> void:
	look(Vector3(0, 5.4, 34.0), Vector3(0, 5.8, 12.0), 70.0)
	await shot("entrance_center")
	look(Vector3(0, 5.0, 30.0), Vector3(0, 6.6, 24.0), 74.0)
	await shot("entrance_door")
	look(Vector3(0, 6.2, 24.0), Vector3(0, 6.4, 36.0), 74.0)
	await shot("entrance_back")

