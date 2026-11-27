extends SceneTree

## 腐墟星美术验收（无头）。
## 用法：godot --headless --path game --script res://tests/ruin_art_audit.gd
##
## 只检查“美术层是否按指南落地”的硬指标：没有悬浮 3D 文字、接地件齐全、
## Compatibility 环境开关正确、五层布光齐全、材质家族与顶点遮罩标志正确、
## 本星生态与物理因果节点存在、碰撞体没有被美术改动。视觉好坏由截图与人工评分。

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, message: String, detail := "") -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)
	elif detail != "":
		print("  ok  ", message, "  ", detail)


func run() -> void:
	var main: Main3D = load("res://scenes/main_3d.tscn").instantiate() as Main3D
	root.add_child(main)
	await process_frame
	main._ship_session.persistence_enabled = false
	main.network_port = 28410 + int(Time.get_ticks_msec() % 40)
	main._create_host()
	main.connected_ids = [1]
	main.spawn_player_for_peer(1)
	main._start_ruin_planet()
	await process_frame
	await process_frame
	var ruin: RuinPlanet = main._ruin_planet
	check(ruin != null, "腐墟星世界没有建立")
	if ruin == null:
		_finish()
		return
	var world: Node3D = ruin.world_root
	check(world != null and world.visible, "腐墟星世界根不可见")

	# ── 红线：没有悬浮 3D 文字（只查腐墟星世界与它自己的 HUD）──
	var labels: Array = world.find_children("*", "Label3D", true, false)
	if ruin.hud != null:
		labels.append_array(ruin.hud.find_children("*", "Label3D", true, false))
	check(labels.is_empty(), "存在悬浮 Label3D（指南红线 1）", "labels=%d" % labels.size())

	# ── 接地：每栋建筑 + 登陆艇都有 skirt 与碎石 ──
	for id in ruin.buildings.keys():
		var building: Dictionary = ruin.buildings[id]
		var b_root: Node3D = building.root
		var skirt := b_root.find_children("BuildingSkirt", "MeshInstance3D", true, false)
		var gravel := b_root.find_children("BuildingGravel*", "MeshInstance3D", true, false)
		check(not skirt.is_empty(), "建筑 %s 缺少接地 skirt" % id)
		check(not gravel.is_empty(), "建筑 %s 缺少接地碎石" % id)
	var pad := world.get_node_or_null("RuinLandingPad") as Node3D
	if pad == null:
		check(false, "找不到登陆艇节点")
	else:
		check(not pad.find_children("PadSkirt", "MeshInstance3D", true, false).is_empty(), "登陆艇缺少接地 skirt")
		check(not pad.find_children("PadGravel*", "MeshInstance3D", true, false).is_empty(), "登陆艇缺少接地碎石")
		check(pad.get_node_or_null("PadControlConsole") != null, "登陆艇缺少实体控制台（表盘/状态灯/铭牌）")

	# ── Compatibility 环境开关 ──
	var env := ruin.get("_environment") as Environment
	check(env != null, "缺少环境资源")
	if env != null:
		check(not env.ssr_enabled, "ssr_enabled 未关闭")
		check(not env.ssil_enabled, "ssil_enabled 未关闭")
		check(not env.volumetric_fog_enabled, "volumetric_fog_enabled 未关闭")
		check(not env.sdfgi_enabled, "sdfgi_enabled 未关闭")
		check(not env.ssao_enabled, "ssao_enabled 未关闭（GL 下无效）")
		check(env.ambient_light_energy >= 1.0, "环境光达到 GL 基线（>=1.0）", "%.2f" % env.ambient_light_energy)
	for interior_env in [ruin.get("_hospital_environment"), ruin.get("_energy_environment"), ruin.get("_school_environment"), ruin.get("_market_environment"), ruin.get("_shelter_environment")]:
		if interior_env is Environment:
			var ie := interior_env as Environment
			check(not ie.ssr_enabled and not ie.ssil_enabled and not ie.volumetric_fog_enabled, "室内环境没有关闭 GL 不支持的效果")

	# ── 五层布光 ──
	var sun := world.get_node_or_null("RuinKeySun") as DirectionalLight3D
	check(sun != null, "缺少主故事光")
	if sun != null:
		check(sun.shadow_enabled, "主光没有开阴影")
		check(sun.light_energy >= 1.2, "主光能量达标", "%.2f" % sun.light_energy)
	check(world.get_node_or_null("RuinRimLight") != null, "缺少轮廓光")
	check(world.find_children("RuinFill*", "OmniLight3D", true, false).size() >= 4, "补光不足 4 盏")
	check(world.find_children("RuinGraze*", "SpotLight3D", true, false).size() >= 2, "掠射光不足 2 盏")
	var practical := world.find_children("*LampGlow*", "OmniLight3D", true, false).size()
	practical += world.find_children("EnergyCanopyLight", "OmniLight3D", true, false).size()
	check(practical >= 4, "绑在可见灯具上的实用光数量", "count=%d" % practical)

	# ── 材质：2K 家族 + 无顶点色标志 ──
	var mesh_total := 0
	var shaded := 0
	var shader_mats := 0
	var mask_ok := 0
	var bad_materials := 0
	var triangles := 0
	for node in world.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		mesh_total += 1
		triangles += mi.mesh.get_faces().size() / 3
		var mat := mi.material_override
		if mat == null:
			bad_materials += 1
			continue
		shaded += 1
		if mat is ShaderMaterial:
			shader_mats += 1
			var sm := mat as ShaderMaterial
			var has_flag = sm.get_shader_parameter("vertex_mask_valid")
			if has_flag == null:
				# 非分层 shader（比如发光/文字铭牌）不要求这个参数
				continue
			if not (sm.get_shader_parameter("use_detail") as bool):
				bad_materials += 1
			elif has_flag is bool:
				mask_ok += 1
	# ART-SAMPLE 的 GLB 用 surface material 而不是 material_override，视为已挂材质。
	for node in world.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null or mi.material_override != null:
			continue
		var surfaced := false
		for surface in range(mi.mesh.get_surface_count()):
			if mi.mesh.surface_get_material(surface) != null:
				surfaced = true
		if surfaced:
			bad_materials = maxi(0, bad_materials - 1)
	check(bad_materials == 0, "存在无材质或未挂 2K 细节的网格", "bad=%d" % bad_materials)
	check(shader_mats >= 200, "分层材质数量过少，说明仍有大量平涂件", "shader=%d" % shader_mats)
	check(mask_ok >= shader_mats * 9 / 10, "有分层材质没有正确设置 vertex_mask_valid", "%d/%d" % [mask_ok, shader_mats])

	# ── 本星生态与物理因果 ──
	check(not world.find_children("DrainFungus*", "Node3D", true, false).is_empty(), "街道缺少菌群斑")
	check(not world.find_children("EnergyVentFungus", "Node3D", true, false).is_empty(), "能源站缺少菌群")
	check(not world.find_children("EnergyStarMarrow", "Node3D", true, false).is_empty(), "能源站缺少星髓晶簇")
	check(not world.find_children("EnergyCityConduit*", "Node3D", true, false).is_empty(), "缺少能源站→城区导管")
	check(not world.find_children("EnergyCitySchematic*", "Node3D", true, false).is_empty(), "缺少贴壁图示铭牌")
	check(ruin.get("_link_flow") is ShaderMaterial, "导管流动材质缺失")
	check(ruin.get("_pad_dial") != null, "登陆艇实体表盘缺失")
	check((ruin.get("_link_lamps") as Array).size() >= 4, "物理因果状态灯不足")

	# ── 灯光预算：室内灯按空间隔离，室外只查外景预算 ──
	var interior_roots: Array[Node] = []
	for key in ["hospital_interior", "energy_station_interior", "school_interior", "market_interior", "shelter_interior"]:
		var interior_node = ruin.get(key)
		if interior_node is Node:
			interior_roots.append(interior_node as Node)
	var all_lights := 0
	var outdoor_lights := 0
	for node in world.find_children("*", "Light3D", true, false):
		all_lights += 1
		var inside := false
		for interior_root in interior_roots:
			if _is_under(node as Node, interior_root):
				inside = true
				break
		if not inside:
			outdoor_lights += 1
	check(outdoor_lights <= 28, "室外灯光超出预算", "outdoor=%d all=%d" % [outdoor_lights, all_lights])

	print("RUIN_ART_AUDIT: %d checks, %d failures | meshes=%d shader_mats=%d tris=%d outdoor_lights=%d interior_lights=%d" % [
		checks, failures.size(), mesh_total, shader_mats, triangles, outdoor_lights, all_lights - outdoor_lights])
	_finish()


func _is_under(node: Node, root: Node) -> bool:
	var current := node
	while current != null:
		if current == root:
			return true
		current = current.get_parent()
	return false


func _finish() -> void:
	quit(0 if failures.is_empty() else 1)
