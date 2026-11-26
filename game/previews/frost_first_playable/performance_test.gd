extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var a: Node3D = load("res://previews/frost_first_playable/adventure.tscn").instantiate()
	root.add_child(a)
	a.start_session(false)
	a.test_mode = true
	a.players[1].position = Vector3(0,1,-14)
	var station: bool = "--station" in OS.get_cmdline_user_args()
	if station:
		a.players[1].position = Vector3(-37,0.4,-326)
		a.progress.station03 = {"power_on":true,"hatch_open":true}
	a._items.add_item(1,"heater",-1,{},true)
	a.accept_controls(1,{"heat":true})
	for i: int in 120:
		await process_frame
	var timings: Array[float] = []
	var stamp: int = Time.get_ticks_usec()
	for i: int in 600:
		await process_frame
		var now: int = Time.get_ticks_usec()
		timings.append(float(now-stamp)/1000)
		stamp = now
	timings.sort()
	var total: float = 0
	for ms: float in timings:
		total += ms
	print("FROST_PERF ",JSON.stringify({"frames":600,"mean_ms":total/600,"p95_ms":timings[570],"max_ms":timings[-1],"ice_chunks":a.world.ice.size(),"nodes":a.get_tree().get_node_count(),"renderer":RenderingServer.get_video_adapter_name(),"viewport":root.size,"scenario":"powered station interior, one host, no fixed fps; not network stress" if station else "full map, one host, continuous gate heat, no fixed fps; not network stress"}))
	a.queue_free()
	await process_frame
	await process_frame
	quit()
