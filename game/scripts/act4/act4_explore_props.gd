extends Node3D

const ExplorePropKit := preload("res://scripts/world/explore_prop_kit.gd")

## Optional non-story exploration mechanisms across Act 4 cavern & FreightArena pit.
## Uses EchoPlayer's native `"interactable"` contract (get_interaction_prompt / interact).

var game: Node
var hud: Node
var _chime_step: int = 0


func setup(p_game: Node, p_hud: Node) -> void:
	game = p_game
	hud = p_hud
	name = "Act4ExploreProps"
	_spawn_pit_sump_pump()
	_spawn_crystal_chime_rack()
	_spawn_miner_locker()
	_spawn_sample_crusher()
	_spawn_louver_crank()
	_spawn_ambient_inspectables()


func _spawn_ambient_inspectables() -> void:
	var cands := ExplorePropKit.scan_scene_candidates(game, {
		"min_primary_dist": 1.65,
		"min_spacing": 1.55,
		"max_props": 68,
	})
	var toast_cb := Callable(self, "_toast")
	for i: int in range(cands.size()):
		var c: Dictionary = cands[i]
		var probe := ExplorePropKit.AmbientProbeBody.new(true, 0)
		probe.name = "AmbientExplore4_%d" % i
		probe.position = c["pos"] as Vector3
		probe.target_mesh = c["mesh"] as MeshInstance3D
		probe.probe_cat = str(c["cat"])
		probe.probe_prompt = str(c["prompt"])
		probe.variant_id = int(c["variant"])
		probe.toast_cb = toast_cb
		probe.host_node = self
		add_child(probe)


func _make_item(item_name: String, pos: Vector3, yaw_deg: float, prompt_cb: Callable, interact_cb: Callable) -> Node3D:
	var item := _ExploreInteractable4.new()
	item.name = item_name
	item.position = pos
	item.rotation_degrees = Vector3(0, yaw_deg, 0)
	item.prompt_cb = prompt_cb
	item.interact_cb = interact_cb
	add_child(item)
	return item


func _toast(text: String, secs: float = 3.6) -> void:
	if hud != null and hud.has_method("show_toast"):
		hud.call("show_toast", text, secs)


func _spawn_pit_sump_pump() -> void:
	var st := {"on": false}
	var wheel_ref: Array[Node3D] = []
	var light_ref: Array[OmniLight3D] = []
	var item := _make_item("PitSumpPump", Vector3(-14.3, -3.2, 5.8), 90.0,
		func(_p: Node) -> String: return "E 关闭深坑积水排污泵" if bool(st["on"]) else "E 旋开深坑排污泵手轮（顺便照明检修区）",
		func(_p: Node) -> void:
			st["on"] = not bool(st["on"])
			if not wheel_ref.is_empty():
				create_tween().tween_property(wheel_ref[0], "rotation_degrees:z", 360.0 if bool(st["on"]) else -360.0, 0.55).as_relative()
			if not light_ref.is_empty():
				light_ref[0].visible = bool(st["on"])
			if bool(st["on"]):
				ExplorePropKit.spawn_burst(self, Vector3(-14.0, -2.0, 5.8), Vector3(1, 0.5, 0), Color(0.65, 0.90, 1.0), 18, 2.8, 0.75)
			ExplorePropKit.play_wav_3d(self, "res://assets/audio/sfx/steam_burst.wav", Vector3(-14.3, -2.0, 5.8), 0.95)
			_toast("深坑抽水辅泵已启动 · 照明恢复，可从东侧坡道安全回到主洞室" if bool(st["on"]) else "排污辅泵已关闭"))
	var m_dark := ExplorePropKit.make_mat(Color(0.20, 0.22, 0.24), 0.75, 0.44)
	ExplorePropKit.box(item, "PumpHousing", Vector3(0.56, 1.10, 0.42), Vector3(0, 0.55, 0), m_dark)
	var wheel := ExplorePropKit.attach_valve_wheel(item, 0.22)
	wheel.position = Vector3(0, 1.02, 0.24)
	wheel_ref.append(wheel)
	var ol := OmniLight3D.new()
	ol.position = Vector3(0.4, 1.65, 0.4)
	ol.light_color = Color(0.56, 0.90, 1.0)
	ol.light_energy = 2.8
	ol.omni_range = 9.0
	ol.visible = false
	item.add_child(ol)
	light_ref.append(ol)


func _spawn_crystal_chime_rack() -> void:
	var bars: Array[MeshInstance3D] = []
	var item := _make_item("CrystalChimeRack", Vector3(9.4, 0.0, -1.8), -90.0,
		func(_p: Node) -> String: return "E 试敲晶体谐波音叉架（音阶 %d/3）" % (_chime_step + 1),
		func(_p: Node) -> void:
			var idx: int = _chime_step
			_chime_step = (_chime_step + 1) % 3
			var pitches: Array[float] = [0.85, 1.06, 1.28]
			var notes: Array[String] = ["基频 C#（低沉共振）", "五度 G#（中频泛音）", "八度高音（清脆裂纹声响）"]
			if idx < bars.size():
				var bar := bars[idx]
				var tw := create_tween()
				tw.tween_property(bar, "rotation_degrees:z", 14.0, 0.08)
				tw.tween_property(bar, "rotation_degrees:z", 0.0, 0.26)
				bar.material_override = ExplorePropKit.make_mat(Color(0.2, 0.7, 0.8), 0.2, 0.2, Color(0.42, 0.94, 1.0), 3.0)
				ExplorePropKit.spawn_burst(self, Vector3(9.4, 1.35, -1.8), Vector3(-0.4, 0.7, 0.0), Color(0.42, 0.94, 1.0), 12, 2.2, 0.55)
			ExplorePropKit.play_wav_3d(self, "res://assets/audio/sfx/crystal_pulse.wav", Vector3(9.4, 1.35, -1.8), pitches[idx], -1.0)
			_toast("音叉架发声：%s" % notes[idx], 2.8))
	var m_dark := ExplorePropKit.make_mat(Color(0.30, 0.34, 0.38), 0.72, 0.42)
	ExplorePropKit.box(item, "RackFrame", Vector3(1.10, 1.65, 0.26), Vector3(0, 0.825, 0), m_dark)
	ExplorePropKit.box(item, "RackHeader", Vector3(1.14, 0.08, 0.30), Vector3(0, 1.65, 0),
		ExplorePropKit.make_mat(Color(0.2, 0.2, 0.2), 0.1, 0.3, Color(0.28, 0.86, 1.0), 1.6))
	var chime_light := OmniLight3D.new()
	chime_light.position = Vector3(0, 1.75, 0.55)
	chime_light.light_color = Color(0.45, 0.90, 1.0)
	chime_light.light_energy = 1.6
	chime_light.omni_range = 4.5
	item.add_child(chime_light)
	for i: int in range(3):
		var c := ExplorePropKit.cyl(item, "ChimeCrystal_%d" % i, 0.055, 0.52 - float(i) * 0.10,
			Vector3(-0.30 + float(i) * 0.30, 1.18, 0.16),
			ExplorePropKit.make_mat(Color(0.18, 0.56, 0.68), 0.2, 0.25, Color(0.32, 0.82, 0.96), 1.0), Vector3.ZERO, 6)
		bars.append(c)


func _spawn_miner_locker() -> void:
	var st := {"open": false}
	var door_ref: Array[Node3D] = []
	var item := _make_item("MinersSupplyLocker", Vector3(-19.2, 0.0, 4.2), 90.0,
		func(_p: Node) -> String: return "E 合上矿工私人工具储物柜" if bool(st["open"]) else "E 拉开矿工私人工具储物柜",
		func(_p: Node) -> void:
			st["open"] = not bool(st["open"])
			if not door_ref.is_empty():
				create_tween().tween_property(door_ref[0], "rotation_degrees:y", -96.0 if bool(st["open"]) else 0.0, 0.24).set_trans(Tween.TRANS_SINE)
			ExplorePropKit.play_wav_3d(self, "res://assets/audio/metal_clank.wav", Vector3(-19.2, 1.2, 4.2), 1.2, -3.0)
			_toast("柜门内贴着矿工便条：「如果撞钟停止了，就从地层北口去核心室找老宋。」" if bool(st["open"]) else "储物柜门已锁上"))
	var m_teal := ExplorePropKit.make_mat(Color(0.18, 0.28, 0.30), 0.45, 0.50)
	var m_amber := ExplorePropKit.make_mat(Color(0.95, 0.65, 0.22), 0.3, 0.35, Color(1.0, 0.72, 0.24), 1.4)
	ExplorePropKit.box(item, "Body", Vector3(0.76, 1.85, 0.52), Vector3(0, 0.925, 0), m_teal)
	ExplorePropKit.box(item, "HelmetLight", Vector3(0.24, 0.16, 0.24), Vector3(0, 1.25, 0.05), m_amber)
	var hinge := Node3D.new()
	hinge.position = Vector3(-0.37, 0.925, 0.27)
	item.add_child(hinge)
	ExplorePropKit.box(hinge, "Door", Vector3(0.72, 1.76, 0.05), Vector3(0.36, 0, 0),
		ExplorePropKit.make_mat(Color(0.26, 0.36, 0.38), 0.55, 0.46))
	door_ref.append(hinge)


func _spawn_sample_crusher() -> void:
	var lever_ref: Array[Node3D] = []
	var ram_ref: Array[MeshInstance3D] = []
	var item := _make_item("SampleCrusherPress", Vector3(-4.8, 0.0, -16.8), 0.0,
		func(_p: Node) -> String: return "E 拉下液压岩样破碎测试压机",
		func(_p: Node) -> void:
			if not lever_ref.is_empty():
				var tw := create_tween()
				tw.tween_property(lever_ref[0], "rotation_degrees:x", 48.0, 0.12)
				tw.tween_property(lever_ref[0], "rotation_degrees:x", -15.0, 0.28)
			if not ram_ref.is_empty():
				var tw2 := create_tween()
				tw2.tween_property(ram_ref[0], "position:y", 1.02, 0.10)
				tw2.tween_property(ram_ref[0], "position:y", 1.32, 0.25)
			ExplorePropKit.spawn_burst(self, Vector3(-4.8, 1.02, -16.8), Vector3(0, 0.8, 0.4), Color(1.0, 0.72, 0.26), 14, 2.8, 0.45)
			ExplorePropKit.play_wav_3d(self, "res://assets/audio/sfx/cart_clank.wav", Vector3(-4.8, 1.1, -16.8), 1.1)
			_toast("压机冲头砸碎了样本碎晶——碎片在落地时泛起一道蓝光", 3.2))
	var m_dark := ExplorePropKit.make_mat(Color(0.18, 0.20, 0.22), 0.75, 0.44)
	ExplorePropKit.box(item, "PressFrame", Vector3(0.84, 1.58, 0.62), Vector3(0, 0.79, 0), m_dark)
	var ram := ExplorePropKit.cyl(item, "PistonRam", 0.14, 0.34, Vector3(0, 1.32, 0.04),
		ExplorePropKit.make_mat(Color(0.84, 0.62, 0.22), 0.65, 0.38))
	ram_ref.append(ram)
	var lev := Node3D.new()
	lev.position = Vector3(0.46, 1.18, 0.18)
	lev.rotation_degrees = Vector3(-15, 0, 0)
	item.add_child(lev)
	ExplorePropKit.cyl(lev, "Arm", 0.025, 0.42, Vector3(0, 0.21, 0), ExplorePropKit.make_mat(Color(0.86, 0.26, 0.14), 0.3, 0.42))
	lever_ref.append(lev)


func _spawn_louver_crank() -> void:
	var st := {"open": false}
	var slats: Array[MeshInstance3D] = []
	var item := _make_item("CavernLouverCrank", Vector3(3.4, 0.0, 12.6), -90.0,
		func(_p: Node) -> String: return "E 关闭南入口岩壁通风百叶" if bool(st["open"]) else "E 摇开南入口岩壁通风百叶",
		func(_p: Node) -> void:
			st["open"] = not bool(st["open"])
			for slat: MeshInstance3D in slats:
				create_tween().tween_property(slat, "rotation_degrees:x", 52.0 if bool(st["open"]) else 5.0, 0.28)
			ExplorePropKit.play_wav_3d(self, "res://assets/audio/door_grind.wav", Vector3(3.4, 1.3, 12.6), 1.3, -4.0)
			_toast("矿道新风穿堂而入 · 空气中的晶尘被稍微吹散了一些" if bool(st["open"]) else "百叶风门已闭合"))
	var m_dark := ExplorePropKit.make_mat(Color(0.20, 0.22, 0.24), 0.72, 0.44)
	ExplorePropKit.box(item, "LouverBox", Vector3(0.76, 1.56, 0.22), Vector3(0, 0.78, 0), m_dark)
	for i: int in range(4):
		var sl := ExplorePropKit.box(item, "Slat_%d" % i, Vector3(0.60, 0.04, 0.14), Vector3(0, 0.92 + float(i) * 0.15, 0.10),
			ExplorePropKit.make_mat(Color(0.55, 0.60, 0.62), 0.6, 0.45), Vector3(5, 0, 0))
		slats.append(sl)


class _ExploreInteractable4 extends StaticBody3D:
	var prompt_cb: Callable
	var interact_cb: Callable

	func _init() -> void:
		collision_layer = 1
		collision_mask = 0
		add_to_group("interactable")
		add_to_group("explore_prop")
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.85, 1.65, 0.85)
		cs.shape = bs
		cs.position = Vector3(0, 0.825, 0)
		add_child(cs)

	func get_interaction_position() -> Vector3:
		return global_position + Vector3(0, 1.05, 0)

	func get_interaction_reach() -> float:
		return 2.7

	func get_interaction_prompt(_player: Node) -> String:
		if prompt_cb.is_valid():
			return str(prompt_cb.call(_player))
		return "E 检查"

	func interact(player: Node) -> void:
		if interact_cb.is_valid():
			interact_cb.call(player)
