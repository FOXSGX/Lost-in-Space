extends SceneTree

var a: Node3D
var failures: int = 0
var client: bool = false

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	print("PASS " if value else "FAIL ",label)
	if not value:
		failures += 1

func seconds(duration: float) -> void:
	await create_timer(duration).timeout

func until(predicate: Callable, timeout: float = 12) -> bool:
	var start: int = Time.get_ticks_msec()
	while not predicate.call() and Time.get_ticks_msec()-start<timeout*1000:
		await process_frame
	return predicate.call()

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
	print("NETWORK_RESULT client=",client," failures=",failures)
	quit(failures)

func host_run() -> void:
	check(await until(func() -> bool: return a.players.size()==2),"real ENet client joined")
	if a.players.size()!=2:
		return
	var remote: int = a.connected_ids[-1]
	a.players[1].position = Vector3(0,1,8)
	a.players[remote].position = Vector3(1.5,1,8)
	a._items.add_item(remote,"heater",-1,{"charge":42.0},true)
	a._items.publish()
	a.players[remote].position = Vector3(0,0.9,-14)
	a.players[1].position = Vector3(4,1,8)
	a.progress["test_phase"] = 10
	var gate: Node3D
	for ice: Node3D in a.world.ice:
		if ice.original.z == -18 and ice.original.x == 0:
			gate = ice
	check(await until(func() -> bool: return gate.amount>0.15),"remote input heats actual gate on host")
	a.players[1].position = Vector3(0,0.9,-16)
	a.progress["test_phase"] = 11
	check(await until(func() -> bool: return a.players[1].warmth>1.08),"remote heat warms teammate")
	a.players[remote].position = a.world.creatures[0].position+Vector3.UP
	a.players[remote].velocity = Vector3.ZERO
	a.progress["test_phase"] = 12
	check(await until(func() -> bool: return a.world.creatures[0].launches>0),"remote solo heat launches organism")
	a.accept_controls(remote,{})
	a.players[1].position = Vector3(0,1,8)
	a.players[remote].position = Vector3(1.5,1,8)
	a.players[remote].velocity = Vector3.ZERO
	a.players[remote].launch_time = 0
	a.progress.key = true
	a.world.ice[0].heat(20)
	a.progress["test_phase"] = 1
	await seconds(1)
	check(await until(func() -> bool: return a._items.count_kind(remote,"heater")==0),"client action drops authoritative tool")
	check(a._items.drops[-1].charge>20 and a._items.drops[-1].charge<42,"remote drop preserves spent charge")
	a.progress["test_phase"] = 2
	a.hurt(1,5)
	check(await until(func() -> bool: return not a.players[1].downed),"remote held input rescues host over ENet")
	a.hurt(1,5)
	a.hurt(remote,5)
	check(await until(func() -> bool: return a.progress.wipes==1),"network team wipe respawns")
	a._items.add_item(remote,"medical",-1,{},true)
	a._items.publish()
	a.progress["test_phase"] = 3
	await seconds(1)
	check(await until(func() -> bool: return a.players.size()==1),"disconnect removes actor")
	check(a._items.drops.any(func(entry: Dictionary) -> bool: return entry.get("owner",0)==remote and entry.kind=="medical"),"disconnect leaves carried consumable in world")
	check(await until(func() -> bool: return a.players.size()==2),"fresh connection joins existing world")
	await seconds(2)
	check(a.progress.key and a.world.ice[0].amount==1,"late join did not reset world")
	check(a._items.occupied(a.connected_ids[-1])==0,"rejoin does not duplicate equipment or supplies")
	a.progress["test_phase"] = 4
	await seconds(2)

func client_run() -> void:
	check(await until(func() -> bool: return a.players.size()==2 and a.progress.get("test_phase",0)==10),"initial snapshot received")
	if a.players.size()!=2:
		return
	var id: int = a.multiplayer.get_unique_id()
	var heat_start: int = Time.get_ticks_msec()
	while int(a.progress.get("test_phase",0)) in [10,11,12] and Time.get_ticks_msec()-heat_start<25000:
		a.send_controls.rpc_id(1,{"heat":true,"pitch":1.25 if a.progress.get("test_phase",0)==12 else 0.0})
		await physics_frame
	check(a.world.creatures[0].launches>0,"organism result synchronized to client")
	check(a.progress.key and a.world.ice[0].amount==1,"key and melt synchronized")
	check(a._items.selected(id).get("charge",0)>20,"inventory synchronized")
	a.handle_action(id,"item_drop")
	check(await until(func() -> bool: return a.progress.get("test_phase",0)==2),"drop acknowledged")
	var began: int = Time.get_ticks_msec()
	while a.progress.get("test_phase",0)==2 and Time.get_ticks_msec()-began < 15000:
		a.send_controls.rpc_id(1,{"rescue":true})
		await physics_frame
	check(await until(func() -> bool: return a.progress.get("test_phase",0)==3),"rescue and wipe progressed")
	check(not a.players[id].downed and a.players[id].health==5,"revived health synced")
	check(a.progress.key,"wipe retained shared key on client")
	a.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	await seconds(1.2)
	for actor: Node in a.players.values():
		actor.queue_free()
	a.players.clear()
	a.connected_ids.clear()
	var reconnect: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	check(reconnect.create_client("127.0.0.1",a.FROST_PORT)==OK,"reconnect transport created")
	a.multiplayer.multiplayer_peer = reconnect
	check(await until(func() -> bool: return a.players.has(a.multiplayer.get_unique_id())),"late join receives player")
	check(a.progress.key and a.world.ice[0].amount==1,"late join receives durable world progress")
	check(await until(func() -> bool: return a.progress.get("test_phase",0)==4),"host finished scenario")
