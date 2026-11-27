extends SceneTree

## 医院/能源站楼层牌、房间目录、配电间路线与固定标牌的验收。
## 标牌使用贴墙 QuadMesh + 纹理，不使用 Label3D。

var checks := 0
var failures: Array[String] = []
var main: Main3D
var ruin: RuinPlanet


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)


func sign_textures(root: Node) -> Array[String]:
	var out: Array[String] = []
	for node: Node in root.find_children("WallSign*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var mat := mesh.material_override as StandardMaterial3D
		if mat != null and mat.albedo_texture != null:
			out.append(mat.albedo_texture.resource_path)
	return out


func has_texture(root: Node, needle: String) -> bool:
	for path in sign_textures(root):
		if path.contains(needle):
			return true
	return false


func run() -> void:
	main = load("res://scenes/main_3d.tscn").instantiate() as Main3D
	root.add_child(main)
	await process_frame
	main._ship_session.persistence_enabled = false
	main.network_port = 28660
	main._create_host()
	main.connected_ids = [1]
	main.spawn_player_for_peer(1)
	main._start_ruin_planet()
	await process_frame
	await physics_frame
	ruin = main._ruin_planet
	var hospital := ruin.hospital_interior as Node3D
	var energy := ruin.energy_station_interior as Node3D
	check(hospital != null, "医院没有建立")
	check(energy != null, "能源站没有建立")
	if hospital != null:
		check(sign_textures(hospital).size() >= 8, "医院楼层/目录牌数量不足")
		check(has_texture(hospital, "hospital_floor_b1") and has_texture(hospital, "hospital_floor_2f"), "医院楼层牌缺失")
		check(has_texture(hospital, "hospital_dir_1f"), "医院楼层目录缺失")
		check(has_texture(hospital, "hospital_directory"), "医院入口目录缺失")
		check(hospital.find_children("*", "Label3D", true, false).is_empty(), "医院仍在使用 Label3D")
	if energy != null:
		check(sign_textures(energy).size() >= 10, "能源站楼层/目录/配电间牌数量不足")
		check(has_texture(energy, "energy_directory"), "能源站入口目录缺失")
		check(has_texture(energy, "energy_distribution"), "能源站配电间门牌缺失")
		check(energy.find_children("DistributionGuide*", "MeshInstance3D", true, false).size() >= 1, "配电间地面导向线缺失")
		check(energy.find_children("DistributionSeamLight*", "MeshInstance3D", true, false).size() >= 1, "配电间门缝灯缺失")
		check(energy.find_child("DisguisedDistributionDoor", true, false) != null, "配电间暗门缺失")
		check(energy.find_children("*", "Label3D", true, false).is_empty(), "能源站仍在使用 Label3D")
		var secret: Vector3 = energy.call("secret_door_position")
		check(absf(secret.z - (energy.global_position.z - 9.1)) < 0.2, "配电间暗门位置被意外移动")
	var objective := ruin.story_objective_text()
	check(objective.contains("1F") and objective.contains("配电间"), "初始目标没有写明 1F 配电间")
	print("RUIN_WAYFINDING: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
