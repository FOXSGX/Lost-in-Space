extends Node3D

const ExplorePropKit := preload("res://scripts/world/explore_prop_kit.gd")

## Optional non-story exploration mechanisms across Act 5 Core Hall.
## Integrates natively with Act 5 player.gd (`group = "interactable"`, get_prompt / interact).

var hud: Node = null


func setup(p_hud: Node) -> void:
	hud = p_hud
	name = "Act5ExploreProps"
	_build_east_telemetry()
	_build_west_cryo_valve()
	_build_specimen_case()
	_build_gimbal_spotlight()
	_build_evac_strobe_switch()


func populate_ambient(scene_root: Node3D) -> void:
	if scene_root == null:
		return
	var cands := ExplorePropKit.scan_scene_candidates(scene_root, {
		"min_primary_dist": 1.65,
		"min_spacing": 1.55,
		"max_props": 68,
	})
	var toast_cb := Callable(self, "_toast")
	for i: int in range(cands.size()):
		var c: Dictionary = cands[i]
		var probe := ExplorePropKit.AmbientProbeBody.new(false, 0)
		probe.name = "AmbientExplore5_%d" % i
		probe.position = c["pos"] as Vector3
		probe.target_mesh = c["mesh"] as MeshInstance3D
		probe.probe_cat = str(c["cat"])
		probe.probe_prompt = str(c["prompt"])
		probe.variant_id = int(c["variant"])
		probe.toast_cb = toast_cb
		probe.host_node = self
		add_child(probe)


func _toast(text: String, secs: float = 3.6) -> void:
	if hud != null and hud.has_method("toast"):
		hud.call("toast", text, secs)


func _make_item(item_name: String, pos: Vector3, yaw_deg: float, prompt_cb: Callable, interact_cb: Callable) -> _ExploreInteractable5:
	var item := _ExploreInteractable5.new()
	item.name = item_name
	item.position = pos
	item.rotation_degrees = Vector3(0, yaw_deg, 0)
	item.prompt_cb = prompt_cb
	item.interact_cb = interact_cb
	add_child(item)
	return item


func _build_east_telemetry() -> void:
	var st := {"mode": 0}
	var scr_ref: Array[MeshInstance3D] = []
	var item := _make_item("EastTelemetryScreen", Vector3(10.8, 4.0, 0.4), -90.0,
		func() -> String: return "E 切换东侧观景台地核遥测面板模式",
		func(_p: Node) -> void:
			st["mode"] = (int(st["mode"]) + 1) % 3
			var idx: int = int(st["mode"])
			var cols: Array[Color] = [Color(0.22, 0.86, 1.0), Color(1.0, 0.68, 0.22), Color(0.28, 0.96, 0.60)]
			var readouts: Array[String] = [
				"遥测画面 [频率谱]：核心质量分布不均，需要先平衡两翼配重",
				"遥测画面 [应力分布]：隔离弯臂承受巨大剪切力，切勿蛮力锁死",
				"遥测画面 [星图回传]：上行链路待命——锁定核心即可提取完整导航数据",
			]
			if not scr_ref.is_empty():
				scr_ref[0].material_override = ExplorePropKit.make_mat(Color(0.08, 0.14, 0.18), 0.1, 0.28, cols[idx], 1.8)
			ExplorePropKit.play_wav_3d(self, "res://assets/audio/sfx/radio_beep.wav", Vector3(10.8, 5.2, 0.4), 0.95 + float(idx) * 0.16)
			_toast(readouts[idx], 4.0))
	var m_dark := ExplorePropKit.make_mat(Color(0.18, 0.20, 0.22), 0.72, 0.44)
	ExplorePropKit.box(item, "ConsolePed", Vector3(0.92, 1.15, 0.46), Vector3(0, 0.575, 0), m_dark)
	var scr := ExplorePropKit.box(item, "Display", Vector3(0.74, 0.42, 0.05), Vector3(0, 1.32, 0.14),
		ExplorePropKit.make_mat(Color(0.08, 0.14, 0.18), 0.1, 0.28, Color(0.22, 0.86, 1.0), 1.4), Vector3(-16, 0, 0))
	scr_ref.append(scr)


func _build_west_cryo_valve() -> void:
	var wheel_ref: Array[Node3D] = []
	var item := _make_item("WestCryoValve", Vector3(-10.8, 4.0, -0.8), 90.0,
		func() -> String: return "E 旋转西侧观景台液氮冷却回流阀",
		func(_p: Node) -> void:
			if not wheel_ref.is_empty():
				create_tween().tween_property(wheel_ref[0], "rotation_degrees:z", 360.0, 0.55).as_relative()
			ExplorePropKit.spawn_burst(self, Vector3(-10.3, 5.15, -0.8), Vector3(1, 0.35, 0), Color(0.72, 0.94, 1.0), 22, 3.2, 0.8)
			ExplorePropKit.play_wav_3d(self, "res://assets/audio/sfx/steam_burst.wav", Vector3(-10.8, 5.15, -0.8), 1.25, -3.0)
			_toast("低温冷凝气喷出 · 冷却管道内壁的结霜稍微退却了一寸", 3.4))
	ExplorePropKit.cyl(item, "CryoPipe", 0.10, 2.2, Vector3(0, 1.1, -0.1), ExplorePropKit.make_mat(Color(0.28, 0.32, 0.36), 0.8, 0.38))
	var wh := ExplorePropKit.attach_valve_wheel(item, 0.20, ExplorePropKit.make_mat(Color(0.22, 0.62, 0.84), 0.35, 0.42))
	wh.position = Vector3(0, 1.18, 0.14)
	wheel_ref.append(wh)


func _build_specimen_case() -> void:
	var st := {"open": false}
	var lid_ref: Array[Node3D] = []
	var item := _make_item("SpecimenCase", Vector3(-11.4, 0.0, 4.2), 135.0,
		func() -> String: return "E 合上原生共鸣晶标本保存箱" if bool(st["open"]) else "E 掀开原生共鸣晶标本保存箱",
		func(_p: Node) -> void:
			st["open"] = not bool(st["open"])
			if not lid_ref.is_empty():
				create_tween().tween_property(lid_ref[0], "rotation_degrees:x", -64.0 if bool(st["open"]) else 0.0, 0.25).set_trans(Tween.TRANS_SINE)
			ExplorePropKit.play_wav_3d(self, "res://assets/audio/door_latch.wav", Vector3(-11.4, 1.1, 4.2), 1.1)
			_toast("标本晶核发出低频嗡鸣——矿工在撤离前仍在试着封存这些共振样本" if bool(st["open"]) else "标本盖锁扣已重锁"))
	var m_dark := ExplorePropKit.make_mat(Color(0.18, 0.20, 0.22), 0.72, 0.44)
	ExplorePropKit.box(item, "Pedestal", Vector3(0.68, 0.96, 0.56), Vector3(0, 0.48, 0), m_dark)
	ExplorePropKit.cyl(item, "SampleCrystal", 0.08, 0.28, Vector3(0, 1.08, 0),
		ExplorePropKit.make_mat(Color(0.2, 0.72, 0.85), 0.2, 0.2, Color(0.36, 0.92, 1.0), 1.8), Vector3(0, 0, 14), 6)
	var hinge := Node3D.new()
	hinge.position = Vector3(0, 0.98, -0.26)
	item.add_child(hinge)
	var m_glass := ExplorePropKit.make_mat(Color(0.45, 0.72, 0.80, 0.42), 0.1, 0.15)
	m_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ExplorePropKit.box(hinge, "Cover", Vector3(0.60, 0.24, 0.50), Vector3(0, 0.12, 0.26), m_glass)
	lid_ref.append(hinge)


func _build_gimbal_spotlight() -> void:
	var st := {"step": 0}
	var head_ref: Array[Node3D] = []
	var spot_ref: Array[SpotLight3D] = []
	var item := _make_item("PerimeterSpotlight", Vector3(11.8, 0.0, -8.8), -45.0,
		func() -> String: return "E 旋转大厅外缘强光云台照射角度",
		func(_p: Node) -> void:
			st["step"] = (int(st["step"]) + 1) % 3
			var s_idx: int = int(st["step"])
			var yaws: Array[float] = [-24.0, 26.0, 0.0]
			var pitches: Array[float] = [28.0, 18.0, -10.0]
			if not head_ref.is_empty():
				create_tween().tween_property(head_ref[0], "rotation_degrees", Vector3(pitches[s_idx], yaws[s_idx], 0), 0.26)
			if not spot_ref.is_empty():
				spot_ref[0].light_energy = 5.5 if s_idx != 2 else 2.2
			ExplorePropKit.play_wav_3d(self, "res://assets/audio/servo.wav", Vector3(11.8, 1.3, -8.8), 1.25, -5.0)
			_toast(["云台转向：照射大厅上部岩穹层理", "云台转向：扫射东侧稳态支架底座", "云台归位：低功耗待机"][s_idx], 2.8))
	var m_dark := ExplorePropKit.make_mat(Color(0.20, 0.22, 0.24), 0.72, 0.44)
	ExplorePropKit.cyl(item, "TripodCol", 0.09, 1.25, Vector3(0, 0.625, 0), m_dark)
	var head := Node3D.new()
	head.position = Vector3(0, 1.32, 0)
	item.add_child(head)
	ExplorePropKit.box(head, "Housing", Vector3(0.32, 0.24, 0.36), Vector3.ZERO, m_dark)
	ExplorePropKit.cyl(head, "Lens", 0.10, 0.04, Vector3(0, 0, -0.19),
		ExplorePropKit.make_mat(Color(0.95, 0.85, 0.65), 0.1, 0.2, Color(1.0, 0.86, 0.56), 2.0), Vector3(90, 0, 0))
	var sl := SpotLight3D.new()
	sl.position = Vector3(0, 0, -0.22)
	sl.light_color = Color(1.0, 0.88, 0.62)
	sl.light_energy = 5.5
	sl.spot_range = 28.0
	sl.spot_angle = 32.0
	head.add_child(sl)
	head_ref.append(head)
	spot_ref.append(sl)


func _build_evac_strobe_switch() -> void:
	var cap_ref: Array[Node3D] = []
	var beacon_ref: Array[MeshInstance3D] = []
	var item := _make_item("EvacBeaconSwitch", Vector3(-15.0, 0.0, -4.8), 90.0,
		func() -> String: return "E 测试西侧撤离通道信标脉冲",
		func(_p: Node) -> void:
			if not cap_ref.is_empty():
				var tw := create_tween()
				tw.tween_property(cap_ref[0], "rotation_degrees:x", -90.0, 0.14)
				tw.tween_interval(0.6)
				tw.tween_property(cap_ref[0], "rotation_degrees:x", 0.0, 0.2)
			if not beacon_ref.is_empty():
				beacon_ref[0].material_override = ExplorePropKit.make_mat(Color(0.2, 0.3, 0.2), 0.1, 0.2, Color(0.28, 0.96, 0.62), 3.0)
			ExplorePropKit.spawn_burst(self, Vector3(-15.0, 1.55, -4.8), Vector3(0, 1, 0), Color(0.28, 0.96, 0.62), 14, 2.4, 0.6)
			ExplorePropKit.play_wav_3d(self, "res://assets/audio/sfx/beacon_ping.wav", Vector3(-15.0, 1.35, -4.8), 1.35, -2.0)
			_toast("撤离信标自检正常 · 上行升降井气压稳定，取完核心星图即可通过西侧大门", 3.6))
	var m_dark := ExplorePropKit.make_mat(Color(0.18, 0.20, 0.22), 0.72, 0.44)
	ExplorePropKit.box(item, "Post", Vector3(0.36, 1.32, 0.32), Vector3(0, 0.66, 0), m_dark)
	var bcn := ExplorePropKit.cyl(item, "StrobeLamp", 0.09, 0.18, Vector3(0, 1.42, 0),
		ExplorePropKit.make_mat(Color(0.1, 0.25, 0.18), 0.1, 0.3, Color(0.28, 0.96, 0.62), 0.8))
	beacon_ref.append(bcn)
	var guard := Node3D.new()
	guard.position = Vector3(0, 1.24, 0.17)
	item.add_child(guard)
	ExplorePropKit.box(guard, "GuardCap", Vector3(0.16, 0.18, 0.06), Vector3(0, 0, 0), ExplorePropKit.make_mat(Color(0.92, 0.56, 0.16), 0.3, 0.4))
	cap_ref.append(guard)


class _ExploreInteractable5 extends StaticBody3D:
	var prompt_cb: Callable
	var interact_cb: Callable

	func _init() -> void:
		collision_layer = 8
		collision_mask = 0
		add_to_group("interactable")
		add_to_group("explore_prop")
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.85, 1.65, 0.85)
		cs.shape = bs
		cs.position = Vector3(0, 0.825, 0)
		add_child(cs)

	func get_prompt() -> String:
		if prompt_cb.is_valid():
			return str(prompt_cb.call())
		return "E 检查"

	func interact(player: Node) -> void:
		if interact_cb.is_valid():
			interact_cb.call(player)
