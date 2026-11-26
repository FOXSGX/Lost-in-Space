extends SceneTree

## Free-camera geometry probe (development only, not deliverable evidence).
## Used to check that the new machines are physically supported and that the
## stabiliser pads actually meet the core's outer ring.

var app: Node3D
var level: LevelBuilder
var cam: Camera3D
var out_dir: String = "C:/Users/ASUS/Desktop/迷失太空/work/deepseek-resonance-05-coop-party-v2/evidence/geom"


func _initialize() -> void:
	run.call_deferred()


func frames(n: int) -> void:
	for _i in range(n):
		await physics_frame


func view(name: String, pos: Vector3, target: Vector3) -> void:
	cam.global_position = pos
	cam.look_at(target, Vector3.UP)
	await frames(6)
	await process_frame
	root.get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])
	print("GEOM ", name)


func run() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	await frames(80)
	level = app.get("level") as LevelBuilder
	var hud: GameHud = app.get("hud") as GameHud
	hud.title_layer.visible = false
	hud.clear_subtitles()
	hud.toast_label.visible = false
	hud.set_prompt("")
	hud.update_crew("")
	cam = Camera3D.new()
	cam.fov = 68.0
	cam.near = 0.05
	cam.far = 300.0
	app.add_child(cam)
	cam.current = true
	await frames(4)

	await view("01_hall_from_south", Vector3(0, 8.6, 8.5), Vector3(0, 5.0, -2))
	await view("02_catwalk_side", Vector3(2, 5.2, -10.5), Vector3(-11.5, 3.2, -4.2))
	await view("03_catwalk_top", Vector3(-9.5, 7.0, -1.0), Vector3(-11.5, 3.2, -4.2))
	await view("04_east_stabilizer", Vector3(0.5, 4.0, -0.5), Vector3(6.6, 5.5, -7.8))
	await view("05_ram_ring_contact", Vector3(9.0, 7.6, 3.3), Vector3(4.4, 7.2, -2.0))
	await view("06_west_ram_ring", Vector3(-9.0, 7.6, 3.3), Vector3(-4.4, 7.2, -2.0))
	await view("07_brake_and_catwalk", Vector3(-6.0, 6.0, 2.0), Vector3(-12.0, 1.5, -5.0))
	await view("08_isolation_and_damper", Vector3(3.0, 4.5, 1.0), Vector3(8.6, 1.0, -7.0))
	await view("09_board_and_lock", Vector3(2.0, 3.2, 10.5), Vector3(3.5, 1.6, 5.5))
	print("GEOM done")
	quit()
