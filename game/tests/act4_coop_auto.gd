extends Node

## Two-instance cooperative automation for Act 4 (Resonance 04) in the
## 04→05 vertical slice. Launched by SessionHub/act4 scene with --auto=host or
## --auto=client. Each process drives its own first-person body through the real
## input map; only station teleporting is used (same standard as the accepted
## Act 4 solo probe). Mission state (memories/stage/gate) and the freight
## platform are host-authoritative; the client forwards real actions.

var role: String = "host"
var game: Node
var player: EchoPlayer
var net: CoopNet
var checks: Array[Dictionary] = []
var t0: int = 0
var out_dir: String = "C:/Users/ASUS/Desktop/迷失太空/work/deepseek-resonance-04-05-coop-vertical-slice"
var shot_dir: String = "C:/Users/ASUS/Desktop/迷失太空/work/deepseek-resonance-04-05-coop-vertical-slice/evidence/act4_coop"
var failed: int = 0


func _ready() -> void:
	t0 = Time.get_ticks_msec()
	# This node is added by the act4 scene wrapper (see below) with `role` set.
	game = get_parent()
	player = game.get("player") as EchoPlayer
	net = SessionHub.net
	# The act4 game binds itself to the net in _setup_coop; wait a beat.
	if role == "client":
		_run_client.call_deferred()
	else:
		_run_host.call_deferred()


func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame


func wait(seconds: float) -> void:
	var count: int = maxi(1, int(round(seconds * 60.0)))
	for _i in range(count):
		await get_tree().physics_frame


func wait_until(cond: Callable, timeout: float) -> bool:
	var budget: int = maxi(1, int(round(timeout * 60.0)))
	for _i in range(budget):
		if bool(cond.call()):
			return true
		await get_tree().physics_frame
	return bool(cond.call())


func check(name: String, ok: bool, detail: String = "") -> bool:
	checks.append({"name": name, "ok": ok, "detail": detail})
	print(("PASS  " if ok else "FAIL  ") + name + (("  |  " + detail) if detail != "" else ""))
	if not ok:
		failed += 1
	return ok


func teleport(pos: Vector3, yaw: float = 0.0) -> void:
	player.teleport(pos, yaw)
	await frames(8)


func press(action: String, hold: float = 0.12) -> void:
	Input.action_press(action)
	await wait(hold)
	Input.action_release(action)
	await frames(4)


func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(shot_dir)
	var img: Image = get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("%s/%s_%s.png" % [shot_dir, role, name])
		print("SHOT ", role, "_", name)


func write_report(file_name: String, extra: Dictionary = {}) -> void:
	var passed: int = 0
	for c in checks:
		if bool(c["ok"]):
			passed += 1
	var report: Dictionary = {
		"role": role,
		"passed": passed,
		"failed": checks.size() - passed,
		"elapsed": float(Time.get_ticks_msec() - t0) / 1000.0,
		"checks": checks,
		"state": {
			"stage": game.get("stage"),
			"memories": game.get("seen_memories"),
			"gate_open": game.get("gate").get("is_open") if game.get("gate") != null else false,
			"strikes": game.get("hammer").strike_count if game.get("hammer") != null else 0,
			"completed": game.get("completed"),
			"session_players": SessionHub.session.ledger.player_ids(),
			"peers": net.peer_count(),
			"remotes_visible": (game.get("remote_player") as Node3D != null and not (game.get("remote_player") as Node3D).visible) if game.get("remote_player") != null else false,
		},
	}
	for key in extra.keys():
		report[key] = extra[key]
	DirAccess.make_dir_recursive_absolute(out_dir + "/tests-out")
	var f: FileAccess = FileAccess.open("%s/tests-out/%s" % [out_dir, file_name], FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	print("REPORT %s pass=%d fail=%d" % [file_name, passed, checks.size() - passed])


# ---------------------------------------------------------------------------
# host
# ---------------------------------------------------------------------------

func _run_host() -> void:
	await wait(1.2)
	var connected: bool = await wait_until(func() -> bool: return net.peer_count() >= 2, 45.0)
	check("peer_connected", connected, "peers=%d" % net.peer_count())
	if not connected:
		write_report("act4_host.json", {"aborted": "client never connected"})
		get_tree().quit()
		return
	# Remote body visible for the host.
	var seen: bool = await wait_until(func() -> bool: return game.get("remote_player") != null and (game.get("remote_player") as Node3D).visible, 10.0)
	check("client_body_visible", seen, "remote=%s" % str(game.get("remote_player")))

	# --- Client picks up crystal A then (to drive) drops it; the carry RPC is
	# what proves host-authoritative single-holder crystal ownership. Detect it
	# immediately (before the client drops it to drive).
	var carried_by_remote: bool = await wait_until(func() -> bool: return _remote_carries("crystal_a") or _remote_carries("crystal_b"), 45.0)
	check("client_carries_crystal", carried_by_remote, "a=%s b=%s" % [str(_remote_carries("crystal_a")), str(_remote_carries("crystal_b"))])
	await shot("host_crystal_carried")

	# --- Host pulls the hammer (real input) to start memory 1 --------------
	# Match the accepted solo probe's proven teleport + aim + timing exactly.
	await teleport(Vector3(2.25, 0.2, -0.4), 0.0)
	await frames(10)
	player.aim_camera_at(Vector3(2.25, 1.2, -4.5), -0.08)
	await frames(6)
	await press("interact", 0.12)
	await frames(6)
	check("host_grabbed_hammer", game.get("hammer").mode == "held", "mode=%s" % str(game.get("hammer").mode))
	Input.action_press("move_forward")
	await wait(1.45)
	Input.action_release("move_forward")
	await frames(8)
	await press("interact", 0.12)
	var struck: bool = await wait_until(func() -> bool: return (game.get("hammer") as HammerRig).strike_count >= 1, 6.0)
	check("host_struck", struck, "strikes=%d" % (game.get("hammer") as HammerRig).strike_count)

	# --- Client drives the freight platform west (real input stream) -------
	var platform_moved: bool = await wait_until(func() -> bool: return _platform_west_of(-9.0), 60.0)
	check("platform_drove_west", platform_moved, "x=%.2f" % (game.get("platform") as FreightPlatform).travel_x)

	# --- Both see memories / stage advance host-side ----------------------
	var mem1: bool = await wait_until(func() -> bool: return bool((game.get("seen_memories") as Dictionary).get(1, false)), 40.0)
	check("host_memory1", mem1, str(game.get("seen_memories")))

	await write_report("act4_host.json")
	await wait(1.0)
	get_tree().quit()


func _remote_carries(crystal_id: String) -> bool:
	var remote: EchoPlayer = game.get("remote_player") as EchoPlayer
	if remote == null:
		return false
	var crystal: Node = game.call("find_crystal", crystal_id)
	return crystal != null and remote.carrying == crystal


func _platform_west_of(target_x: float) -> bool:
	var platform: FreightPlatform = game.get("platform") as FreightPlatform
	return platform != null and platform.travel_x < target_x


# ---------------------------------------------------------------------------
# client
# ---------------------------------------------------------------------------

func _run_client() -> void:
	await wait(1.2)
	var online: bool = await wait_until(func() -> bool: return net.is_online(), 45.0)
	check("connected_to_host", online)
	if not online:
		write_report("act4_client.json", {"aborted": "no host"})
		get_tree().quit()
		return
	await shot("client_connected")

	# --- Client picks up crystal A on the far dock (real input -> intent) --
	await teleport(Vector3(-17.2, 2.66, 1.0), 0.0)
	await frames(8)
	var crystal_a: PortableCrystal = game.get("crystal_a") as PortableCrystal
	player.aim_camera_at(crystal_a.global_position + Vector3(0, 0.6, 0), -99.0)
	await frames(6)
	await press("pickup", 0.15)
	var carried: bool = await wait_until(func() -> bool: return player.carrying != null, 6.0)
	check("client_picked_up", carried, "carry=%s" % str(player.carrying))

	# --- Client drives the freight platform west (real input stream) -------
	# Carrying blocks the platform grab, so drop the crystal onto the deck
	# first (the real workflow: 装货 -> 驾驶).
	if player.carrying != null:
		await press("drop", 0.15)
		await wait(0.4)
	await teleport(Vector3(-8.6, 2.66, 2.6), 0.0)
	await frames(8)
	var console_pos: Vector3 = (game.get("platform") as FreightPlatform).to_global(Vector3(-1.02, 1.10, -0.50))
	player.aim_camera_at(console_pos, -99.0)
	await frames(6)
	var on_platform: bool = false
	for attempt in range(8):
		await press("interact", 0.12)
		on_platform = (game.get("platform") as FreightPlatform).control_owner_id == 2
		if on_platform:
			break
		await wait(0.5)
	check("client_control", on_platform, "owner=%d" % (game.get("platform") as FreightPlatform).control_owner_id)
	if on_platform:
		# drive_input +1 moves travel_x toward near park (-8.8, east); to ride
		# west toward the far dock you hold move_back (S).
		Input.action_press("move_back")
		var moved: bool = await wait_until(func() -> bool: return (game.get("platform") as FreightPlatform).travel_x < -9.0, 40.0)
		Input.action_release("move_back")
		check("client_drove", moved, "x=%.2f" % (game.get("platform") as FreightPlatform).travel_x)
		await press("interact", 0.12)

	# --- Client should see the same mission state (snapshot mirror) --------
	var mem1_seen: bool = await wait_until(func() -> bool: return bool((game.get("seen_memories") as Dictionary).get(1, false)), 40.0)
	check("client_memory1_mirrored", mem1_seen, str(game.get("seen_memories")))

	await write_report("act4_client.json")
	await wait(1.0)
	get_tree().quit()