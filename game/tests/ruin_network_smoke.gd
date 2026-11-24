extends SceneTree

## 腐墟星真实双进程联机冒烟：
## 主机创建房间 → 客户端加入 → 两人就位 → 登陆腐墟星 → 客户端第一人称 →
## 主机返航 → 客户端回主舱。

class RuinPeer extends Node:
	var main: Main3D
	var mode := ""
	var port := 0
	var output := ""
	var phase := 0
	var checks := 0
	var failures: Array[String] = []

	func check(ok: bool, message: String) -> void:
		checks += 1
		if not ok:
			failures.append(message)
			push_error(mode + ": " + message)

	func wait_for(predicate: Callable, seconds := 20.0) -> bool:
		var end := Time.get_ticks_msec() + int(seconds * 1000.0)
		while not predicate.call() and Time.get_ticks_msec() < end:
			await get_tree().create_timer(0.05).timeout
		return predicate.call()

	func run() -> void:
		var args := OS.get_cmdline_user_args()
		mode = args[0]
		output = args[1]
		port = int(args[2])
		main = load("res://scenes/main_3d.tscn").instantiate() as Main3D
		add_child(main)
		await get_tree().process_frame
		main._ship_session.persistence_enabled = false
		main.network_port = port
		if mode == "client":
			if not await wait_for(func(): return FileAccess.file_exists(output.path_join("host.ready"))):
				check(false, "等待主机握手超时")
				finish()
				return
			main._address_edit.text = "127.0.0.1"
			main._join_host()
			if not await wait_for(func(): return main.players.size() == 2):
				check(false, "客户端没有加入两人房间")
				finish()
				return
			if not await wait_for(func(): return phase >= 2, 40.0):
				check(false, "等待腐墟星联机检查结束超时，phase=%d" % phase)
			finish()
			return

		main._create_host()
		check(main.is_host, "主机创建失败")
		var ready_file := FileAccess.open(output.path_join("host.ready"), FileAccess.WRITE)
		if ready_file != null:
			ready_file.store_string(str(port))
			ready_file.close()
		print("RUIN_NETWORK_HOST_READY port=%d" % port)
		if not await wait_for(func(): return main.players.size() == 2):
			check(false, "真实对端没有加入")
			finish()
			return
		var client_id := int(main.multiplayer.get_peers()[0])
		check(main.connected_ids.has(client_id), "客户端没有登记进队伍")

		main._ship_session.select_destination("ruin")
		var pilot: SpacePlayer3D = main.players[1] as SpacePlayer3D
		pilot.teleport_to(Vector3(ShipDevices3D.PILOT_X[0], 0, -12.2))
		pilot.rotation.y = 0.0
		pilot._camera_yaw = 0.0
		pilot._camera_yaw_target = 0.0
		main._ship_session.request("ready")
		ready_at_pilot.rpc_id(client_id)
		check(await wait_for(func(): return main._ship_session.all_ready()), "客户端就位状态没有同步")
		main._confirm_land()
		check(await wait_for(func(): return main.game_started and main.current_planet_id == "ruin"), "主机没有登陆腐墟星")
		check(main._ruin_planet != null, "主机没有建立腐墟星世界")
		check(main.players[1].is_ruin_first_person(), "主机没有切到第一人称")
		check(main.players.size() == 2, "登陆后船员数量不为 2")
		verify_ruin.rpc_id(client_id)
		check(await wait_for(func(): return phase == 1, 20.0), "客户端腐墟星检查未确认")

		main.return_to_ship.rpc("联机冒烟：腐墟星返航", main._vitals_snapshot())
		await get_tree().create_timer(0.4).timeout
		check(main.current_planet_id == "demo", "主机返航后星球 id 没有复位")
		check(not main._ruin_planet.world_root.visible, "主机返航后腐墟星世界仍然可见")
		verify_ship.rpc_id(client_id)
		check(await wait_for(func(): return phase == 2, 20.0), "客户端返航检查未确认")
		finish()

	@rpc("authority", "call_remote", "reliable")
	func ready_at_pilot() -> void:
		var pilot: SpacePlayer3D = main.players[multiplayer.get_unique_id()] as SpacePlayer3D
		pilot.teleport_to(Vector3(ShipDevices3D.PILOT_X[1], 0, -12.2))
		pilot.rotation.y = 0.0
		pilot._camera_yaw = 0.0
		pilot._camera_yaw_target = 0.0
		pilot.sync_transform.rpc(pilot.position, false, 0.0)
		await get_tree().create_timer(0.2).timeout
		main._ship_session.request("ready")

	@rpc("authority", "call_remote", "reliable")
	func verify_ruin() -> void:
		await get_tree().create_timer(0.5).timeout
		check(main.game_started and main.current_planet_id == "ruin", "客户端没有进入腐墟星")
		check(main._ruin_planet != null, "客户端没有建立腐墟星世界")
		check(main.players.size() == 2, "客户端登陆后船员数量不为 2")
		var local: SpacePlayer3D = main.players.get(multiplayer.get_unique_id()) as SpacePlayer3D
		check(local != null and local.is_ruin_first_person(), "客户端没有切到第一人称")
		check(main._ruin_planet.hud != null, "客户端没有腐墟星 HUD")
		print("RUIN_NETWORK_PHASE ruin id=%d players=%s" % [multiplayer.get_unique_id(), main.players.keys()])
		phase = 1
		acknowledge.rpc_id(1, 1)

	@rpc("authority", "call_remote", "reliable")
	func verify_ship() -> void:
		await get_tree().create_timer(0.4).timeout
		check(main.current_planet_id == "demo", "客户端返航后星球 id 没有复位")
		var local: SpacePlayer3D = main.players.get(multiplayer.get_unique_id()) as SpacePlayer3D
		check(local != null and local._ship_first_person_mode, "客户端返航后没有主舱第一人称")
		print("RUIN_NETWORK_PHASE ship id=%d" % multiplayer.get_unique_id())
		phase = 2
		acknowledge.rpc_id(1, 2)

	@rpc("any_peer", "call_remote", "reliable")
	func acknowledge(next_phase: int) -> void:
		phase = next_phase

	func finish() -> void:
		print("RUIN_NETWORK_%s: %d checks, %d failures" % [mode.to_upper(), checks, failures.size()])
		get_tree().quit(0 if failures.is_empty() else 1)


func _initialize() -> void:
	var peer := RuinPeer.new()
	peer.name = "RuinPeer"
	root.add_child.call_deferred(peer)
	peer.run.call_deferred()
