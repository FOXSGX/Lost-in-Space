extends SceneTree

## 废弃能源站验收：命名、储能柜/充电塔/太阳能板，以及原有门锁流程。

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
	var main: Main3D = load("res://scenes/main_3d.tscn").instantiate() as Main3D
	root.add_child(main)
	await process_frame
	main._ship_session.persistence_enabled = false
	main.network_port = 27990 + int(Time.get_ticks_msec() % 40)
	main._create_host()
	main.connected_ids = [1]
	main.spawn_player_for_peer(1)
	main._start_ruin_planet()
	await process_frame

	var ruin: RuinPlanet = main._ruin_planet
	check(ruin.buildings.has("energy_station"), "没有 energy_station 建筑")
	check(not ruin.buildings.has("gas_station"), "旧 gas_station 仍然存在")
	var building: Dictionary = ruin.buildings.get("energy_station", {})
	check(String(building.get("name", "")) == "废弃能源站", "能源站显示名不对")
	var root_node := building.get("root") as Node3D
	check(root_node != null, "能源站没有生成节点")
	if root_node != null:
		check(root_node.find_children("EnergyBatteryBody*", "MeshInstance3D", true, false).size() == 2, "储能电池柜不是两组")
		check(root_node.find_children("ChargePost*", "MeshInstance3D", true, false).size() == 2, "充电塔不是两根")
		check(root_node.find_children("SolarPanel*", "MeshInstance3D", true, false).size() == 2, "顶棚太阳能板不是两块")
		check(root_node.find_children("PumpBody*", "MeshInstance3D", true, false).is_empty(), "仍然残留加油机")
	check(ruin.is_building_locked("energy_station"), "能源站没有沿用大门锁")
	check(building.get("lock") != null, "能源站没有锁模型")

	print("RUIN_ENERGY_STATION: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
