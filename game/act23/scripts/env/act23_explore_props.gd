extends Node3D

const ExplorePropKit := preload("res://scripts/world/explore_prop_kit.gd")
const Cart := preload("res://act23/scripts/moving_cart.gd")

## Optional non-story exploration mechanisms across Act 2/3 (Cart deck + Repair Yard + Dock 106).
## Integrates natively with MovingStage E-key fallback & HUD prompt display.

var stage: Node3D
var cart: Node3D
var _props: Array[Dictionary] = []
var _ambient_props: Array[Dictionary] = []
var _headlamp_on: bool = false
var _chest_open: bool = false
var _flood_on: bool = false
var _shutter_open: bool = false
var _headlight: SpotLight3D = null
var _yard_light: OmniLight3D = null
var _peep_light: SpotLight3D = null


func setup(p_stage: Node3D, p_cart: Node3D) -> void:
	stage = p_stage
	cart = p_cart
	name = "Act23ExploreProps"
	_build_cart_headlamp_lever()
	_build_cart_tool_chest()
	_build_yard_anvil_chime()
	_build_yard_floodlight_switch()
	_build_dock_peep_shutter()
	_build_ambient_inspectables()


func _build_ambient_inspectables() -> void:
	var skips: Array[Vector3] = []
	for e: Dictionary in _props:
		skips.append((e["anchor_fn"] as Callable).call() as Vector3)
	var cands := ExplorePropKit.scan_scene_candidates(stage, {
		"min_primary_dist": 1.65,
		"min_spacing": 1.65,
		"max_props": 68,
		"skip_moving_bodies": true,
		"extra_skip_points": skips,
	})
	for c: Dictionary in cands:
		_ambient_props.append({
			"mesh": c["mesh"],
			"pos": c["pos"],
			"cat": str(c["cat"]),
			"prompt": str(c["prompt"]),
			"variant": int(c["variant"]),
			"toggle": false,
		})


func _add_prop(id: String, anchor_fn: Callable, range_m: float, pivot: Node3D, lamp: MeshInstance3D = null) -> void:
	_props.append({
		"id": id,
		"anchor_fn": anchor_fn,
		"range": range_m,
		"pivot": pivot,
		"lamp": lamp,
	})


func nearest_prompt(actor: CharacterBody3D) -> String:
	var best: Dictionary = _find_nearest(actor)
	if not best.is_empty():
		match str(best["id"]):
			"explore_headlamp":
				return "E 关闭矿车前照远光灯与汽笛" if _headlamp_on else "E 开启矿车前照远光灯 · 鸣笛"
			"explore_toolchest":
				return "E 合上车尾维修工具箱" if _chest_open else "E 掀开车尾维修工具箱检查"
			"explore_anvil":
				return "E 敲击维修湾钢轨听音试棒"
			"explore_floodlight":
				return "E 切断行车检修强光照明" if _flood_on else "E 合上行车检修强光刀闸"
			"explore_shutter":
				return "E 摇闭裂隙观测窥孔闸板" if _shutter_open else "E 摇开裂隙观测窥孔查看深层晶体"
	var amb: Dictionary = _find_nearest_ambient(actor)
	if not amb.is_empty():
		return str(amb.get("prompt", "E 检查物件"))
	return ""


func try_interact(actor: CharacterBody3D, host_stage: Node3D) -> bool:
	var best: Dictionary = _find_nearest(actor)
	if best.is_empty():
		var amb: Dictionary = _find_nearest_ambient(actor)
		if amb.is_empty():
			return false
		var tog: bool = not bool(amb.get("toggle", false))
		amb["toggle"] = tog
		var fb := func(msg: String, _secs: float) -> void:
			host_stage.set("feedback", msg)
		ExplorePropKit.trigger_ambient_reaction(self, amb["mesh"] as MeshInstance3D, amb["pos"] as Vector3, str(amb["cat"]), int(amb["variant"]), tog, fb)
		return true
	var id: String = str(best["id"])
	var pivot: Node3D = best["pivot"] as Node3D
	var lamp: MeshInstance3D = best["lamp"] as MeshInstance3D
	var at: Vector3 = (best["anchor_fn"] as Callable).call() as Vector3
	match id:
		"explore_headlamp":
			_headlamp_on = not _headlamp_on
			if _headlight != null:
				_headlight.visible = _headlamp_on
			if pivot != null:
				create_tween().tween_property(pivot, "rotation_degrees:z", -34.0 if _headlamp_on else 24.0, 0.16)
			if lamp != null:
				lamp.material_override = ExplorePropKit.make_mat(Color(0.2, 0.2, 0.2), 0.1, 0.3, Color(1.0, 0.86, 0.56), 2.5 if _headlamp_on else 0.15)
			ExplorePropKit.play_wav_3d(self, "res://assets/audio/ready.wav", at, 0.88 if _headlamp_on else 1.2, -3.0)
			host_stage.set("feedback", "矿车远光探照灯已开启 · 汽笛鸣响回荡在岩道深处" if _headlamp_on else "矿车远光灯已关闭")
			return true
		"explore_toolchest":
			_chest_open = not _chest_open
			if pivot != null:
				create_tween().tween_property(pivot, "rotation_degrees:x", -68.0 if _chest_open else 0.0, 0.24).set_trans(Tween.TRANS_BACK)
			ExplorePropKit.play_wav_3d(self, "res://assets/audio/metal_clank.wav", at, 1.15, -4.0)
			host_stage.set("feedback", "工具箱里放着备用的 24 号套筒和半本旧轨道巡检笔记" if _chest_open else "工具箱已扣好锁扣")
			return true
		"explore_anvil":
			if pivot != null:
				var tw := create_tween()
				tw.tween_property(pivot, "rotation_degrees:z", 22.0, 0.08)
				tw.tween_property(pivot, "rotation_degrees:z", -16.0, 0.12)
				tw.tween_property(pivot, "rotation_degrees:z", 0.0, 0.18)
			ExplorePropKit.spawn_burst(self, at + Vector3(0, 0.35, 0), Vector3(0, 1, 0), Color(0.56, 0.92, 1.0), 10, 1.8, 0.5)
			ExplorePropKit.play_wav_3d(self, "res://assets/audio/sfx/crystal_pulse.wav", at, 1.12, -2.0)
			host_stage.set("feedback", "清脆的钢轨试棒声在维修湾中拉出了 3 秒余振——岩体正在导电共振")
			return true
		"explore_floodlight":
			_flood_on = not _flood_on
			if _yard_light != null:
				_yard_light.visible = _flood_on
			if pivot != null:
				create_tween().tween_property(pivot, "rotation_degrees:x", 40.0 if _flood_on else -32.0, 0.18)
			if lamp != null:
				lamp.material_override = ExplorePropKit.make_mat(Color(0.2, 0.2, 0.15), 0.1, 0.3, Color(1.0, 0.84, 0.45), 2.4 if _flood_on else 0.2)
			ExplorePropKit.play_wav_3d(self, "res://assets/audio/lever_click.wav", at, 1.0, -3.0)
			host_stage.set("feedback", "行车检修副照明已通电 · 北侧岩壁管线全部亮起" if _flood_on else "检修副照明已关闭")
			return true
		"explore_shutter":
			_shutter_open = not _shutter_open
			if _peep_light != null:
				_peep_light.visible = _shutter_open
			if pivot != null:
				create_tween().tween_property(pivot, "position:y", 1.72 if _shutter_open else 1.42, 0.25)
			ExplorePropKit.play_wav_3d(self, "res://assets/audio/door_latch.wav", at, 1.05, -3.0)
			host_stage.set("feedback", "窥孔开启 · 下方晶体裂隙泛着稳定的青蓝冷光（第四幕岩层就在下方）" if _shutter_open else "窥孔防尘闸板已关闭")
			return true
	return false


func _find_nearest(actor: CharacterBody3D) -> Dictionary:
	if actor == null:
		return {}
	var best: Dictionary = {}
	var best_d: float = 1.0e9
	for entry: Dictionary in _props:
		var pos: Vector3 = (entry["anchor_fn"] as Callable).call() as Vector3
		var d: float = actor.global_position.distance_to(pos)
		if d <= float(entry["range"]) and d < best_d:
			best_d = d
			best = entry
	return best


func _find_nearest_ambient(actor: CharacterBody3D) -> Dictionary:
	if actor == null:
		return {}
	var actor_pos := actor.global_position + Vector3(0.0, 1.0, 0.0)
	var best: Dictionary = {}
	var best_d: float = 2.25
	for amb: Dictionary in _ambient_props:
		var pos := amb["pos"] as Vector3
		var d := actor_pos.distance_to(pos)
		if d <= best_d:
			best_d = d
			best = amb
	return best


func _build_cart_headlamp_lever() -> void:
	if cart == null:
		return
	var mount := Node3D.new()
	mount.name = "CartHeadlampControl"
	mount.position = Vector3(2.82, 1.95, 2.20)
	cart.add_child(mount)
	var m_dark := ExplorePropKit.make_mat(Color(0.18, 0.20, 0.22), 0.72, 0.44)
	ExplorePropKit.box(mount, "SwitchBox", Vector3(0.22, 0.36, 0.28), Vector3(0, 0.46, 0), m_dark)
	var piv := Node3D.new()
	piv.position = Vector3(-0.12, 0.52, 0)
	piv.rotation_degrees = Vector3(0, 0, 24)
	mount.add_child(piv)
	ExplorePropKit.cyl(piv, "Lever", 0.02, 0.24, Vector3(0, 0.12, 0), ExplorePropKit.make_mat(Color(0.95, 0.56, 0.16), 0.3, 0.4))
	var lens := ExplorePropKit.cyl(cart, "CabSpotLens", 0.12, 0.08, Vector3(3.62, 2.85, 2.20),
		ExplorePropKit.make_mat(Color(0.2, 0.2, 0.2), 0.1, 0.35, Color(1.0, 0.86, 0.56), 0.15), Vector3(0, 0, 90))
	_headlight = SpotLight3D.new()
	_headlight.position = Vector3(3.70, 2.85, 2.20)
	_headlight.rotation_degrees = Vector3(-8.0, -90.0, 0.0)
	_headlight.light_color = Color(1.0, 0.88, 0.62)
	_headlight.light_energy = 5.5
	_headlight.spot_range = 34.0
	_headlight.spot_angle = 36.0
	_headlight.visible = false
	cart.add_child(_headlight)
	_add_prop("explore_headlamp", func() -> Vector3: return cart.to_global(Vector3(2.82, 2.45, 2.20)), 1.75, piv, lens)


func _build_cart_tool_chest() -> void:
	if cart == null:
		return
	var chest := Node3D.new()
	chest.name = "CartToolChest"
	chest.position = Vector3(-1.95, 1.95, 1.25)
	cart.add_child(chest)
	var m_red := ExplorePropKit.make_mat(Color(0.54, 0.16, 0.12), 0.45, 0.48)
	var m_steel := ExplorePropKit.make_mat(Color(0.62, 0.66, 0.70), 0.82, 0.34)
	ExplorePropKit.box(chest, "Base", Vector3(0.68, 0.28, 0.38), Vector3(0, 0.14, 0), m_red)
	ExplorePropKit.box(chest, "Wrench1", Vector3(0.32, 0.03, 0.06), Vector3(-0.08, 0.28, 0), m_steel, Vector3(0, 22, 0))
	var lid := Node3D.new()
	lid.position = Vector3(0, 0.28, -0.19)
	chest.add_child(lid)
	ExplorePropKit.box(lid, "LidMesh", Vector3(0.70, 0.08, 0.40), Vector3(0, 0.04, 0.19), m_red)
	_add_prop("explore_toolchest", func() -> Vector3: return cart.to_global(Vector3(-1.95, 2.20, 1.25)), 1.65, lid)


func _build_yard_anvil_chime() -> void:
	var p90: Transform3D = Cart.route_pose(90.0)
	var pos: Vector3 = p90 * Vector3(-4.4, 0.0, 5.95)
	var root := Node3D.new()
	root.position = pos
	root.basis = p90.basis
	add_child(root)
	var m_dark := ExplorePropKit.make_mat(Color(0.18, 0.20, 0.22), 0.75, 0.44)
	var m_brass := ExplorePropKit.make_mat(Color(0.84, 0.66, 0.28), 0.88, 0.28)
	ExplorePropKit.cyl(root, "Stand", 0.07, 1.35, Vector3(0, 0.675, 0), m_dark)
	ExplorePropKit.box(root, "CrossArm", Vector3(0.45, 0.08, 0.08), Vector3(0.18, 1.32, 0), m_dark)
	var bar_piv := Node3D.new()
	bar_piv.position = Vector3(0.32, 1.28, 0)
	root.add_child(bar_piv)
	ExplorePropKit.cyl(bar_piv, "AcousticBar", 0.045, 0.56, Vector3(0, -0.30, 0), m_brass)
	_add_prop("explore_anvil", func() -> Vector3: return pos + Vector3(0, 1.0, 0), 2.1, bar_piv)


func _build_yard_floodlight_switch() -> void:
	var p90: Transform3D = Cart.route_pose(90.0)
	var pos: Vector3 = p90 * Vector3(4.5, 0.0, 5.95)
	var root := Node3D.new()
	root.position = pos
	root.basis = p90.basis
	add_child(root)
	var m_dark := ExplorePropKit.make_mat(Color(0.18, 0.20, 0.22), 0.72, 0.44)
	ExplorePropKit.cyl(root, "Pole", 0.08, 2.8, Vector3(0, 1.4, 0), m_dark)
	ExplorePropKit.box(root, "Box", Vector3(0.30, 0.36, 0.22), Vector3(0, 1.25, -0.06), m_dark)
	var piv := Node3D.new()
	piv.position = Vector3(0, 1.28, -0.18)
	piv.rotation_degrees = Vector3(-32, 0, 0)
	root.add_child(piv)
	ExplorePropKit.cyl(piv, "Arm", 0.022, 0.24, Vector3(0, 0.12, 0), ExplorePropKit.make_mat(Color(0.95, 0.64, 0.20), 0.3, 0.4))
	var lens := ExplorePropKit.box(root, "FloodHead", Vector3(0.36, 0.20, 0.18), Vector3(0, 2.75, -0.14),
		ExplorePropKit.make_mat(Color(0.2, 0.2, 0.18), 0.1, 0.35, Color(1.0, 0.84, 0.45), 0.2))
	_yard_light = OmniLight3D.new()
	_yard_light.position = Vector3(0, 2.65, -0.6)
	_yard_light.light_color = Color(1.0, 0.86, 0.56)
	_yard_light.light_energy = 4.2
	_yard_light.omni_range = 16.0
	_yard_light.visible = false
	root.add_child(_yard_light)
	_add_prop("explore_floodlight", func() -> Vector3: return pos + Vector3(0, 1.25, 0), 2.1, piv, lens)


func _build_dock_peep_shutter() -> void:
	var p106: Transform3D = Cart.route_pose(106.0)
	var pos: Vector3 = p106 * Vector3(-2.6, 0.0, -2.5)
	var root := Node3D.new()
	root.position = pos
	root.basis = p106.basis
	add_child(root)
	var m_dark := ExplorePropKit.make_mat(Color(0.20, 0.22, 0.25), 0.72, 0.44)
	ExplorePropKit.box(root, "Frame", Vector3(0.68, 1.72, 0.24), Vector3(0, 0.86, 0), m_dark)
	ExplorePropKit.box(root, "ViewportCyan", Vector3(0.42, 0.28, 0.06), Vector3(0, 1.42, 0),
		ExplorePropKit.make_mat(Color(0.1, 0.3, 0.36), 0.1, 0.2, Color(0.32, 0.90, 1.0), 1.6))
	var slat := ExplorePropKit.box(root, "ShutterPlate", Vector3(0.46, 0.32, 0.10), Vector3(0, 1.42, 0.08),
		ExplorePropKit.make_mat(Color(0.34, 0.36, 0.38), 0.8, 0.42))
	_peep_light = SpotLight3D.new()
	_peep_light.position = Vector3(0, 1.42, 0.12)
	_peep_light.light_color = Color(0.36, 0.92, 1.0)
	_peep_light.light_energy = 3.5
	_peep_light.spot_range = 14.0
	_peep_light.spot_angle = 28.0
	_peep_light.visible = false
	root.add_child(_peep_light)
	_add_prop("explore_shutter", func() -> Vector3: return pos + Vector3(0, 1.25, 0), 2.1, slat)
