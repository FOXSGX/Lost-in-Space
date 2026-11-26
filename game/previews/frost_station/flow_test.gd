extends "res://previews/frost_station/station_test.gd"

func run() -> void:
	a = load("res://previews/frost_station/adventure.tscn").instantiate()
	root.add_child(a)
	a.start_session(false)
	a.test_mode = true
	p = a.players[1]
	await frames(20)
	var approach: Array[Vector3] = [Vector3(0,0,-4),Vector3(10,0,-4),Vector3(10,0,-85),Vector3(0,0,-91),Vector3(0,0,-95),Vector3(-23,0,-95),Vector3(-23,4.2,-116),Vector3(-5,4.2,-116),Vector3(-5,4.2,-120)]
	for point: Vector3 in approach:
		if not await walk(point):
			check(false,"complete approach to upstairs office")
			quit(1);return
	await use()
	check(not a.progress.energy,"initial office provides clue but no energy without key")
	var departure: Array[Vector3] = [Vector3(-5,4.2,-116),Vector3(-23,4.2,-116),Vector3(-23,0,-95),Vector3(0,0,-95),Vector3(0,0,-90),Vector3(36,0,-90),Vector3(36,0,-142),Vector3(0,0,-166)]
	for point: Vector3 in departure:
		if not await walk(point):check(false,"walk from office to bone approach");quit(1);return
	var route: Array[Vector3] = []
	for z: float in [-250,-400,-550]:
		route.append_array([Vector3(0,0.35,z+68),Vector3(-23,4,z+38),Vector3(18,8,z+6),Vector3(-15,12,z-32),Vector3(0,12,z-52)])
		if z != -550:route.append(Vector3(0,0.35,z-78))
	for point: Vector3 in route:
		if not await walk(point):check(false,"walk continuous three-hall bone route");quit(1);return
	check(p.position.y>11,"deep site reached by ordinary walking, without jet or vehicle")
	await use()
	check(a.progress.key,"key obtained at actual deep site by E")
	route.reverse()
	for point: Vector3 in route:
		if not await walk(point):check(false,"return bone route without jet");quit(1);return
	departure.reverse()
	for point: Vector3 in departure:
		if not await walk(point):check(false,"return from ruins to office");quit(1);return
	check(await walk(Vector3(-5,4.2,-120)),"return to same upstairs safe")
	await use()
	check(a.progress.energy,"returning with key opens cabinet")
	approach.reverse()
	for point: Vector3 in approach:
		if not await walk(point):check(false,"walk back from upstairs safe to landing apron");quit(1);return
	check(await walk(Vector3(0,0.9,14)),"walk through ship door to core")
	await use();await use()
	check(a.progress.flight,"complete walking expedition restores navigation")
	check(not a.progress.get("district_power",false),"full mainline succeeds without optional power restoration")
	print("STATION_FLOW_RESULT checks=",checks," failures=",failures," elapsed=",a.elapsed)
	quit(failures)
