extends SceneTree

var a: Node3D
var folder: String

func _initialize() -> void:call_deferred("run")
func frames(n: int = 12) -> void:
	for i: int in n:await physics_frame
func run() -> void:
	folder = ProjectSettings.globalize_path("res://").path_join("../work/gameplay-iterations/20261028-frost-station-implementation/visuals-final").simplify_path()
	DirAccess.make_dir_recursive_absolute(folder)
	a = load("res://previews/frost_station/adventure.tscn").instantiate()
	root.add_child(a)
	a.start_session(false)
	a.test_mode = true
	await frames(20)
	var actor: Node3D = a.players[1]
	var locations: Array = [
		["01-main-hall",Vector3(0,0.3,-96),Vector3(10,3,-112)],
		["02-window",Vector3(19,4.3,-121),Vector3(0,19,-185)],
		["03-skeleton",Vector3(-60,0.3,-57),Vector3(-49,3,-75)],
		["04-suction",Vector3(15,0.3,-104),Vector3(15,1.5,-107)],
		["05-living",Vector3(49,0.3,-66),Vector3(60,1.4,-77)]
	]
	for entry: Array in locations:
		actor.position = entry[1]
		actor.velocity = Vector3.ZERO
		a.notice_time = 0
		var offset: Vector3 = entry[2]-(actor.position+Vector3.UP*1.5)
		actor._camera_yaw_target = atan2(-offset.x,-offset.z)
		actor._camera_pitch_target = atan2(-offset.y,Vector2(offset.x,offset.z).length())
		a.accept_controls(1,{"yaw":actor._camera_yaw_target,"pitch":actor._camera_pitch_target})
		await frames(30)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/"+entry[0]+".png")
	var camera: Camera3D = Camera3D.new()
	root.add_child(camera)
	camera.far = 1400
	camera.position = Vector3(100,105,45)
	camera.look_at(Vector3(0,0,-65))
	camera.make_current()
	await frames(20)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"/06-station-overview.png")
	camera.position = Vector3(46,3.8,-5)
	camera.look_at(Vector3(45,1,-21))
	await frames(10)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"/07-cart.png")
	print("STATION_CAPTURE_OK")
	quit()
