extends SceneTree

## 腐墟星联机入口验收：客户端收到主机快照时应切到 ruin、建世界、生成本地玩家，
## 并应用感染者快照；返航时收起世界并恢复主舱第一人称。

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)


func run() -> void:
	var client: Main3D = load("res://scenes/main_3d.tscn").instantiate() as Main3D
	root.add_child(client)
	await process_frame
	client._ship_session.persistence_enabled = false
	client.network_port = 27590 + int(Time.get_ticks_msec() % 40)
	client.connected_ids = [1]
	client.spawn_player_for_peer(1)
	client.sync_full_state({
		"planet_id": "ruin",
		"ruin_enemies": [{"id": 7, "position": Vector3(6.0, 0.0, 6.0), "health": 5, "form": 0}],
		"vitals": [],
		"salvage": 12,
	})
	await process_frame
	check(client.current_planet_id == "ruin", "客户端快照没有切到腐墟星")
	check(client._ruin_planet != null, "客户端没有建立腐墟星世界")
	check(client._ruin_planet.world_root.visible, "客户端腐墟星世界不可见")
	check(client.salvage_value == 12, "客户端没有同步回收价值")
	var player: SpacePlayer3D = client.players.get(1) as SpacePlayer3D
	check(player != null, "客户端没有生成本地玩家")
	if player != null:
		check(player.is_ruin_first_person(), "客户端没有切到腐墟星第一人称")
		check(not player._visual.visible, "客户端第一人称仍显示本地角色")
	check(client._ruin_planet.hud != null, "客户端没有创建腐墟星 HUD")

	client.return_to_ship("联机测试返航")
	await process_frame
	check(client.current_planet_id == "demo", "客户端返航后星球 id 没有复位")
	check(not client._ruin_planet.world_root.visible, "客户端返航后腐墟星世界仍然可见")
	var returned: SpacePlayer3D = client.players.get(1) as SpacePlayer3D
	check(returned != null and returned._ship_first_person_mode, "客户端返航后没有回到主舱第一人称")

	print("RUIN_MULTIPLAYER_ENTRY: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
