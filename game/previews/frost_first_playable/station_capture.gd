extends SceneTree

# Presentation fixtures only. station_test supplies the actual input evidence.
var a: Node3D
var output: String

func _initialize() -> void:
	call_deferred("run")

func shot(label: String, position: Vector3, target: Vector3) -> void:
	var p: Node3D = a.players[1]
	p.position = position
	p.velocity = Vector3.ZERO
	var offset: Vector3 = target-(position+Vector3.UP*1.6)
	p._camera_yaw_target = atan2(-offset.x,-offset.z)
	p._camera_pitch_target = -atan2(offset.y,Vector2(offset.x,offset.z).length())
	for i: int in 25:
		await physics_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output+"/"+label+".png")

func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	output = args[args.find("--evidence-dir")+1]
	a = load("res://previews/frost_first_playable/adventure.tscn").instantiate()
	root.add_child(a)
	a.start_session(false)
	a.test_mode = true
	await shot("01-station-entry",Vector3(-37,1,-318),Vector3(-36,1.5,-343))
	await shot("02-sample-frozen",Vector3(-46,1,-328),Vector3(-48,1.7,-332))
	await shot("03-annex-off",Vector3(-16,1,-333),Vector3(-10,1.8,-340))
	a.progress.station03 = {"power_on":true,"hatch_open":true,"sample_read":true}
	a.world.ice[a.world.station03.hatch_cover].apply_amount(1)
	a.world.ice[a.world.station03.sample_cover].apply_amount(1)
	await shot("04-annex-powered",Vector3(-16,1,-333),Vector3(-10,1.8,-340))
	await shot("05-sample-readable",Vector3(-46,1,-328),Vector3(-48,1.7,-332))
	await shot("06-deck-view",Vector3(-28,3.25,-351.4),Vector3(0,19,-463))
	await shot("07-energy-locked",Vector3(-36,1,-345.5),Vector3(-36,2,-349.5))
	a.progress.energy = true
	await shot("08-energy-opened",Vector3(-36,1,-345.5),Vector3(-36,2,-349.5))
	print("STATION_CAPTURE_RESULT frames=8")
	a.queue_free()
	await process_frame
	var drain: int = Time.get_ticks_msec()+250
	while Time.get_ticks_msec()<drain:
		await process_frame
	quit()
