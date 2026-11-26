extends SceneTree

var a: Node3D
var failures: int = 0
var client: bool

func _initialize() -> void:call_deferred("run")
func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures += 1
func until(predicate: Callable, timeout: float = 12) -> bool:
	var start: int = Time.get_ticks_msec()
	while not predicate.call() and Time.get_ticks_msec()-start<timeout*1000:await process_frame
	return predicate.call()
func run() -> void:
	client = "--client-test" in OS.get_cmdline_user_args()
	a = load("res://previews/frost_station/adventure.tscn").instantiate()
	root.add_child(a)
	a.test_mode = true
	a.start_session(not client,"127.0.0.1" if client else "")
	if client:await run_client()
	else:await run_host()
	print("STATION_NETWORK_RESULT client=",client," failures=",failures)
	quit(failures)
func run_host() -> void:
	check(await until(func() -> bool:return a.players.size()==2),"real ENet peer joins new station")
	if a.players.size()!=2:return
	var id: int = a.connected_ids[-1]
	a.players[id].position = a.world.cart.position+Vector3(-3,0,0)
	a.progress.phase = 1
	check(await until(func() -> bool:return a.world.cart.riders.has(id)),"remote E boards authoritative vehicle")
	var start: Vector3 = a.world.cart.position
	a.progress.phase = 2
	check(await until(func() -> bool:return a.world.cart.position.distance_to(start)>8),"remote controls actually drive host vehicle")
	a.accept_controls(id,{})
	a.progress.phase = 3
	check(await until(func() -> bool:return not a.world.cart.riders.has(id)),"remote E safely exits vehicle")
	a._items.bags[id].slots = [{"kind":"suction"},{}]
	a._items.bags[id].selected = 0
	a._items.publish()
	var body: Node3D
	for entry: Dictionary in a._items.drops:
		if entry.kind=="crate":body = a._items._prop_bodies[entry.uid];break
	if body == null:
		check(false,"crate fixture exists")
		return
	var original: Vector3 = body.position
	a.players[id].position = original+Vector3(0,0,5)
	a.players[id].position.y = 0.5
	a.progress.pull_target = original
	a.progress.phase = 4
	check(await until(func() -> bool:return a.grabbed.has(id) and body.position.distance_to(original)>0.3),"remote input pulls real host rigidbody")
	a.progress.phase = 5
	check(await until(func() -> bool:return a.push_latched.get(id,false)),"remote right action pushes and latches until release")
	a.accept_controls(id,{})
	a._items.bags[id].slots = [{"kind":"chips"},{}]
	a._items.publish()
	a.progress.phase = 6
	check(await until(func() -> bool:return a.progress.get("snacks_eaten",0)==1),"remote food consumed by host once")
	a.players[id].position = Vector3(50,0.5,-106)
	a.progress.phase = 7
	check(await until(func() -> bool:return a.progress.get("district_power",false)),"remote switch changes district power on host")
	a.world.cart.cargo = [{"kind":"cell","charge":71.0}]
	a.world.ice[a.world.warehouse_ice[0]].apply_amount(1)
	a.progress.key = true
	a.progress.phase = 8
	check(await until(func() -> bool:return a.players.size()==1),"disconnect removes remote rider and actor")
	check(not a.world.cart.riders.has(id),"disconnect cannot leave occupied vehicle seat")
	check(await until(func() -> bool:return a.players.size()==2,18),"fresh peer rejoins running station")
	await create_timer(1).timeout
	check(a.world.cart.cargo.size()==1 and a.progress.key,"rejoin does not duplicate cargo or reset key")
	a.progress.phase = 9
	await create_timer(2).timeout
func run_client() -> void:
	check(await until(func() -> bool:return a.players.size()==2 and a.progress.get("phase",0)==1),"initial station state received")
	if a.players.size()!=2:return
	var id: int = a.multiplayer.get_unique_id()
	var acted: Dictionary = {}
	var start: int = Time.get_ticks_msec()
	while int(a.progress.get("phase",0))<8 and Time.get_ticks_msec()-start<65000:
		var phase: int = int(a.progress.get("phase",0))
		if phase in [1,3,5,6,7] and not acted.has(phase):
			acted[phase] = true
			a.handle_action(id,"push" if phase==5 else ("item_use" if phase==6 else "interact"))
		if phase == 2:a.send_controls.rpc_id(1,{"move":Vector2(0,1)})
		elif phase == 4:
			var offset: Vector3 = Vector3(a.progress.pull_target)-(a.players[id].position+Vector3.UP*1.5)
			a.send_controls.rpc_id(1,{"heat":true,"yaw":atan2(-offset.x,-offset.z),"pitch":atan2(-offset.y,Vector2(offset.x,offset.z).length())})
		else:a.send_controls.rpc_id(1,{})
		await physics_frame
	check(a.progress.get("district_power",false) and a.progress.get("snacks_eaten",0)==1,"power and food outcomes synchronized")
	check(a.world.cart.position.distance_to(a.world.cart.home)>7,"client receives moved vehicle pose")
	await create_timer(0.3).timeout
	a.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	await create_timer(0.7).timeout
	for actor: Node in a.players.values():actor.queue_free()
	a.players.clear();a.connected_ids.clear()
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	check(peer.create_client("127.0.0.1",a.FROST_PORT)==OK,"reconnect transport starts")
	a.multiplayer.multiplayer_peer = peer
	check(await until(func() -> bool:return a.players.has(a.multiplayer.get_unique_id())),"late peer receives actors")
	check(await until(func() -> bool:return a.progress.get("phase",0)==9),"late peer receives durable snapshot")
	check(a.progress.get("district_power",false) and a.progress.key,"late join receives power and key")
	check(a.world.cart.cargo.size()==1 and a.world.cart.cargo[0].charge==71.0,"late join receives cargo with item state")
	check(a.world.ice[a.world.warehouse_ice[0]].amount==1,"late join receives warehouse opening collision")
