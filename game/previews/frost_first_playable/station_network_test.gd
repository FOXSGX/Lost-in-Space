extends SceneTree

var a: Node3D
var failures: int = 0
var client: bool = false

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:
		failures += 1

func until(predicate: Callable, limit: float = 16) -> bool:
	var start: int = Time.get_ticks_msec()
	while not predicate.call() and Time.get_ticks_msec()-start<limit*1000:
		await process_frame
	return predicate.call()

func phase() -> String:
	return a.progress.get("station_test_phase","")

func lab() -> Dictionary:
	return a.progress.get("station03",{})

func stock() -> int:
	return a._items.drops.filter(func(item: Dictionary) -> bool: return String(item.uid).begins_with("cache_station_spares_")).size()

func run() -> void:
	client = "--client-test" in OS.get_cmdline_user_args()
	a = load("res://previews/frost_first_playable/adventure.tscn").instantiate()
	root.add_child(a)
	a.test_mode = true
	a.start_session(not client,"127.0.0.1" if client else "")
	if client:
		await client_run()
	else:
		await host_run()
	print("STATION_NETWORK_RESULT client=",client," failures=",failures)
	a.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	a.queue_free()
	await process_frame
	var drain: int = Time.get_ticks_msec()+250
	while Time.get_ticks_msec()<drain:
		await process_frame
	quit(failures)

func host_run() -> void:
	check(await until(func() -> bool: return a.players.size()==2),"station client joins real ENet host")
	if a.players.size()!=2:
		return
	var remote: int = a.connected_ids[-1]
	a._items.add_item(remote,"heater",-1,{"charge":80.0},true)
	a._items.publish()
	a.players[remote].position = Vector3(-23,0.4,-335)
	a.progress.station_test_phase = "hatch_heat"
	check(await until(func() -> bool: return a.world.ice[a.world.station03.hatch_cover].amount==1),"remote actual heat melts service hatch ice")
	a.progress.station_test_phase = "hatch_use"
	check(await until(func() -> bool: return lab().get("hatch_open",false)),"remote E opens physical service hatch")
	a.players[remote].position = Vector3(-10,0.4,-337.5)
	a.progress.station_test_phase = "relay"
	check(await until(func() -> bool: return lab().get("power_on",false)),"remote E restores lab power on host")
	check(a.world.station03.power_lights[0].light_energy>0.5,"host laboratory lights respond")
	a.players[remote].position = Vector3(-48,0.4,-328.7)
	a.progress.station_test_phase = "sample_heat"
	check(await until(func() -> bool: return a.world.ice[a.world.station03.sample_cover].amount==1),"remote heat thaws specimen tray")
	a.progress.station_test_phase = "sample_use"
	check(await until(func() -> bool: return lab().get("sample_read",false)),"remote E records specimen inspection")
	a.players[remote].position = Vector3(-9,0.4,-325.6)
	a.progress.station_test_phase = "cache"
	check(await until(func() -> bool: return "station_spares" in a.progress.get("opened_caches",[])),"remote opens service stock cache")
	check(stock()==3,"service cache emits exactly three physical supplies")
	a.progress.station_test_phase = "rejoin"
	check(await until(func() -> bool: return a.players.size()==1),"station client disconnects")
	check(await until(func() -> bool: return a.players.size()==2),"station client reconnects")
	check(lab().get("power_on",false) and lab().get("sample_read",false) and stock()==3,"rejoin does not reset laboratory or duplicate supplies")
	a.progress.station_test_phase = "finish"
	await create_timer(2).timeout

func client_run() -> void:
	check(await until(func() -> bool: return phase()=="hatch_heat"),"client receives station scenario")
	var start: int = Time.get_ticks_msec()
	var last: String = ""
	while phase()!="rejoin" and Time.get_ticks_msec()-start<50000:
		var step: String = phase()
		if step in ["hatch_heat","sample_heat"]:
			var id: int = a.multiplayer.get_unique_id()
			if a.players.has(id):
				var p: Node3D = a.players[id]
				var index: int = a.world.station03.hatch_cover if step=="hatch_heat" else a.world.station03.sample_cover
				var offset: Vector3 = a.world.ice[index].position-(p.position+Vector3.UP*1.5)
				var yaw: float = atan2(-offset.x,-offset.z)
				var pitch: float = -atan2(offset.y,Vector2(offset.x,offset.z).length())
				a.send_controls.rpc_id(1,{"heat":true,"yaw":yaw,"pitch":pitch})
		elif step!=last and step in ["hatch_use","relay","sample_use","cache"]:
			a.send_controls.rpc_id(1,{})
			a.handle_action(a.multiplayer.get_unique_id(),"interact")
		last = step
		await physics_frame
	check(phase()=="rejoin","client completed station interactions")
	check(lab().get("hatch_open",false) and lab().get("power_on",false) and lab().get("sample_read",false),"client sees all lab states")
	check(a.world.station03.power_lights[0].light_energy>0.5,"client laboratory lights respond")
	check(stock()==3,"client receives all service props")
	a.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	await create_timer(1.2).timeout
	for actor: Node in a.players.values():
		actor.queue_free()
	a.players.clear()
	a.connected_ids.clear()
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	check(peer.create_client("127.0.0.1",a.FROST_PORT)==OK,"station reconnect transport created")
	a.multiplayer.multiplayer_peer = peer
	check(await until(func() -> bool: return phase()=="finish"),"late join receives final laboratory state")
	check(lab().get("sample_read",false) and stock()==3,"late join keeps sample and unique stock")
