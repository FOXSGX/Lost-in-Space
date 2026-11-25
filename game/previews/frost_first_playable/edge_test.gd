extends SceneTree

var a: Node3D
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func frames(count: int) -> void:
	for i: int in count:
		await physics_frame

func check(value: bool, label: String) -> void:
	print("PASS " if value else "FAIL ",label)
	if not value:
		failures += 1

func run() -> void:
	a = load("res://previews/frost_first_playable/adventure.tscn").instantiate()
	root.add_child(a)
	a.start_session(false)
	a.test_mode = true
	await frames(20)
	var p: Node3D = a.players[1]
	var safe: Dictionary = {}
	for station: Dictionary in a.world.stations:
		if station.kind=="safe":
			safe = station
	a.use_station(1,safe)
	check(not a.progress.energy,"safe cannot open before key")
	a._items.add_item(1,"heater",-1,{"charge":0.0},true)
	p.position = Vector3(0,1,-14)
	a.accept_controls(1,{"heat":true})
	await frames(120)
	check(a.world.ice[548].amount==0,"exhausted heater does not melt")
	a._items.add_item(1,"cell",-1,{},true)
	a.handle_action(1,"item_use")
	check(a._items.count_kind(1,"cell")==0 and a._items.ensure_bag(1).slots[0].charge==180,"replacement battery consumed exactly once")
	a.handle_action(1,"slot_1")
	a._items.selected(1).charge = 37.0
	a.handle_action(1,"item_drop")
	await frames(50)
	var dropped: Dictionary = a._items.drops[-1]
	check(dropped.kind=="heater" and dropped.charge==37,"drop keeps remaining battery")
	var total_before: int = a._items.drops.size()
	check(a._items.pickup(1,dropped),"dropped tool can be retrieved")
	check(not a._items.pickup(1,dropped) and a._items.drops.size()==total_before-1,"stale pickup cannot duplicate")
	a._items.selected(1).charge = 0
	p.position = Vector3(-5,0.8,7)
	p.velocity = Vector3.ZERO
	a.accept_controls(1,{"rescue":true})
	await frames(180)
	check(a._items.selected(1).charge>20,"empty battery recovers through ship slow charger")
	a.accept_controls(1,{})
	p.position = Vector3(0,10,-55)
	p.velocity = Vector3.ZERO
	await frames(90)
	check(p.health<5 and p.health>0,"actual fall damages but moderate drop survives")
	# Two actors exercise shared rescue before the real-network suite.
	a.spawn_actor(2,false)
	a.players[2].position = p.position+Vector3(1,0,0)
	a.hurt(2,5)
	a.accept_controls(1,{"rescue":true})
	await frames(130)
	check(not a.players[2].downed and a.players[2].health==3,"teammate holding interact rescues")
	a.accept_controls(1,{})
	a.progress.key = true
	a.world.ice[0].heat(10)
	var charge: float = a._items.selected(1).charge
	a.hurt(1,5)
	a.hurt(2,5)
	await frames(140)
	check(a.progress.wipes==1 and p.health==5 and p.position.z>3,"all down respawn inside ship")
	check(a.progress.key and a.world.ice[0].amount==1,"wipe preserves key and melted world")
	check(a._items.selected(1).charge==charge,"wipe neither refills nor loses tool")
	check(a._items.count_kind(1,"cell")==0,"wipe does not duplicate consumed battery")
	# A launched real rigid body returns to its last reachable drop point if it falls out.
	a.handle_action(1,"item_drop")
	await frames(10)
	dropped = a._items.drops[-1]
	var body: RigidBody3D = a._items._prop_bodies[dropped.uid]
	body.position = a.world.creatures[0].position+Vector3.UP*1.3
	await frames(2)
	a._on_pop(a.world.creatures[0])
	check(body.linear_velocity.y>10,"organism launches real dropped object")
	body.position = Vector3(0,-25,-500)
	await frames(5)
	check(body.position.distance_to(dropped.safe_position)<2,"out-of-world object returns to reachable drop point")
	a.use_station(1,safe)
	for station: Dictionary in a.world.stations:
		if station.kind=="core":
			a.use_station(1,station)
	a.use_station(1,safe)
	check(a.progress.installed and not a.progress.energy,"reopening emptied safe cannot duplicate installed energy")
	print("EDGE_RESULT failures=",failures)
	a.queue_free()
	await process_frame
	# Fixed-FPS tests can finish before the audio mixer releases its last playback.
	# Pump real time after freeing the scene, rather than masking shutdown diagnostics.
	var audio_drain_until: int = Time.get_ticks_msec() + 250
	while Time.get_ticks_msec() < audio_drain_until:
		await process_frame
	quit(failures)
