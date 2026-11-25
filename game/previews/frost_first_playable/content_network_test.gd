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

func until(predicate: Callable, timeout: float = 15) -> bool:
	var started: int = Time.get_ticks_msec()
	while not predicate.call() and Time.get_ticks_msec()-started<timeout*1000:
		await process_frame
	return predicate.call()

func count_cache() -> int:
	return a._items.drops.filter(func(entry: Dictionary) -> bool: return String(entry.uid).begins_with("cache_rib_sled_")).size()

func opened() -> bool:
	return "rib_sled" in a.progress.get("opened_caches",[])

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
	print("CONTENT_NETWORK_RESULT client=",client," failures=",failures)
	# Stop receiving RPCs before freeing their target during audio-thread drain.
	a.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	a.queue_free()
	await process_frame
	var drain: int = Time.get_ticks_msec()+250
	while Time.get_ticks_msec()<drain:
		await process_frame
	quit(failures)

func host_run() -> void:
	check(await until(func() -> bool: return a.players.size()==2),"content client joined real ENet host")
	if a.players.size()!=2:
		return
	var remote: int = a.connected_ids[-1]
	var sled: Dictionary
	for entry: Dictionary in a.world.stations:
		if entry.get("id","")=="rib_sled":
			sled = entry
	a.world.ice[sled.cover].apply_amount(1)
	a.players[remote].position = Vector3(-44,0.8,-513.6)
	a.progress.content_phase = 1
	check(await until(opened),"remote E opens authoritative optional cache")
	check(count_cache()==3,"host creates exactly three cache props")
	a.use_station(1,sled)
	check(count_cache()==3,"second use does not duplicate network cache")
	a.progress.content_phase = 2
	check(await until(func() -> bool: return a.players.size()==1),"content client disconnected")
	check(await until(func() -> bool: return a.players.size()==2),"content client rejoined")
	await create_timer(1).timeout
	check(opened() and count_cache()==3,"rejoin preserves shared cache stock")
	a.progress.content_phase = 3
	await create_timer(2).timeout

func client_run() -> void:
	check(await until(func() -> bool: return a.progress.get("content_phase",0)==1),"client receives content world")
	if a.progress.get("content_phase",0)!=1:
		return
	a.handle_action(a.multiplayer.get_unique_id(),"interact")
	check(await until(opened),"opened cache state synchronized")
	check(await until(func() -> bool: return count_cache()==3),"physical cache supplies synchronized")
	check(await until(func() -> bool: return a.progress.get("content_phase",0)==2),"host confirms unique rewards")
	a.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	await create_timer(1.2).timeout
	for actor: Node in a.players.values():
		actor.queue_free()
	a.players.clear()
	a.connected_ids.clear()
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	check(peer.create_client("127.0.0.1",a.FROST_PORT)==OK,"content reconnect transport created")
	a.multiplayer.multiplayer_peer = peer
	check(await until(func() -> bool: return a.progress.get("content_phase",0)==3),"late connection receives final content state")
	check(opened() and count_cache()==3,"late join retains cache and all unique rewards")
