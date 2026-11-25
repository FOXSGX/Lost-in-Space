extends SceneTree

var adventure: Node3D
var actor: Node3D
var failures: int = 0
var travelled: float = 0
var evidence_dir: String = ProjectSettings.globalize_path("res://").path_join("../work/gameplay-iterations/20261025-frost-first-playable/")

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	print("PASS " if condition else "FAIL ",label)
	if not condition:
		failures += 1

func frames(count: int) -> void:
	for i: int in count:
		await physics_frame

func walk(point: Vector3, limit: int = 9000) -> bool:
	var previous: Vector3 = actor.position
	for i: int in limit:
		var offset: Vector3 = point-actor.position
		if Vector2(offset.x,offset.z).length()<0.75:
			adventure.accept_controls(1,{})
			await frames(5)
			return true
		var yaw: float = atan2(-offset.x,-offset.z)
		actor._camera_yaw_target = yaw
		adventure.accept_controls(1,{"move":Vector2(0,-1),"yaw":yaw})
		await physics_frame
		travelled += actor.position.distance_to(previous)
		previous = actor.position
	print("BLOCKED target=",point," actual=",actor.position)
	failures += 1
	return false

func shot(label: String) -> void:
	if DisplayServer.get_name()=="headless":
		return
	await frames(4)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(evidence_dir+label+".png")

func run() -> void:
	adventure = load("res://previews/frost_first_playable/adventure.tscn").instantiate()
	root.add_child(adventure)
	adventure.test_mode = true
	adventure.start_session(false)
	await frames(30)
	actor = adventure.players[1]
	await shot("01-arrival")
	await walk(Vector3(0,0,-2.9))
	await walk(Vector3(-4,0,-2.9))
	adventure.handle_action(1,"interact")
	check(adventure._items.count_kind(1,"heater")==1,"pickup actual physical heater")
	await walk(Vector3(0,0,-2.9))
	await walk(Vector3(0,0,-13))
	adventure.accept_controls(1,{"heat":true})
	await frames(430)
	adventure.accept_controls(1,{})
	await shot("02-thaw")
	check(await walk(Vector3(0,0,-25),800),"walk through exit")
	actor._camera_pitch_target = -0.08
	await shot("03-base-vista")
	var before: float = adventure.elapsed
	check(await walk(Vector3(0,0,-458)),"base axis physically traversed")
	print("BASE_WALK_SECONDS ",adventure.elapsed-before)
	await shot("04-fossil-mouth")
	var route: Array[Vector3] = []
	for z: float in [-530,-680,-830]:
		route.append_array([Vector3(0,0.35,z+68),Vector3(-23,4,z+38),Vector3(18,8,z+6),Vector3(-15,12,z-32),Vector3(0,12,z-52)])
		if z != -830:
			route.append(Vector3(0,0.35,z-78))
	for i: int in route.size():
		if not await walk(route[i],1500):
			print("FLOW_STOP at ",i)
			quit(1)
			return
		if i in [3,9,15]:
			await shot("hall-%d" % i)
	check(actor.position.y>11,"deep site reached via real bone geometry")
	adventure.handle_action(1,"interact")
	check(adventure.progress.key,"key collected by normal interaction")
	await shot("05-deep-scene")
	# Zero oxygen and no jet input throughout: reciprocal ground route must work.
	for gear: Dictionary in adventure._items.ensure_bag(1).equipment:
		if gear.get("kind", "") == "oxygen":
			gear.oxygen = 0
			gear.jet_reserve = 0
	route.reverse()
	for waypoint: Vector3 in route:
		if not await walk(waypoint,1500):
			quit(1)
			return
	check(await walk(Vector3(0,0,-318)),"original route returns to base without jet")
	await walk(Vector3(-36,0,-318))
	await walk(Vector3(-42,0,-330))
	await walk(Vector3(-42,0,-347))
	await walk(Vector3(-36,0,-347))
	adventure.handle_action(1,"interact")
	check(adventure.progress.energy,"safe opens with shared key")
	await walk(Vector3(-42,0,-347))
	await walk(Vector3(-42,0,-320))
	await walk(Vector3(0,0,-320))
	await walk(Vector3(0,0,-13))
	await walk(Vector3(0,0,13))
	adventure.handle_action(1,"interact")
	check(adventure.progress.installed and not adventure.progress.energy,"install consumes carried energy exactly once")
	adventure.handle_action(1,"interact")
	check(adventure.progress.flight,"navigation restored")
	await shot("06-flight-restored")
	print("FLOW_RESULT failures=",failures," seconds=",adventure.elapsed," travelled=",travelled)
	adventure.queue_free()
	await process_frame
	var audio_drain_until: int = Time.get_ticks_msec() + 250
	while Time.get_ticks_msec() < audio_drain_until:
		await process_frame
	quit(failures)

