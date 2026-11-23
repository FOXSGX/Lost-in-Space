extends Node3D

const ExplorePropKit := preload("res://scripts/world/explore_prop_kit.gd")

## Optional non-story exploration mechanisms scattered across Act 1 (K-17 Station).
## Independent of mission interlocks, credits, or exit conditions.

var stage: Node = null
var _state: Dictionary = {}
var _pivots: Dictionary = {}
var _lamps: Dictionary = {}
var _lights: Dictionary = {}
var _ambient_entries: Dictionary = {}


func setup(p_stage: Node) -> void:
	stage = p_stage
	name = "Act1ExploreProps"
	_build_weather_beacon()
	_build_intercom()
	_build_oscilloscope()
	_build_steam_valve()
	_build_canister_dispenser()
	_build_departure_bell()
	_build_ambient_inspectables()


func _reg(id: String, prompt_text: String, pos: Vector3, size: Vector3, focus_r: float = 0.16) -> Act1Interactable:
	var item: Act1Interactable = stage.call("make_interactable", id, prompt_text, pos, size, false) as Act1Interactable
	if item != null:
		item.add_to_group("explore_prop")
		item.add_focus_marker(focus_r)
		item.prompt_callable = Callable(self, "_prompt_for").bind(id)
	return item


func _build_ambient_inspectables() -> void:
	var cands := ExplorePropKit.scan_scene_candidates(stage, {
		"min_primary_dist": 1.65,
		"min_spacing": 1.55,
		"max_props": 68,
	})
	for i: int in range(cands.size()):
		var c: Dictionary = cands[i]
		var id: String = "explore_amb_%d" % i
		var pos: Vector3 = c["pos"] as Vector3
		var r: float = clampf(float(c.get("radius", 0.55)), 0.45, 0.95)
		var item: Act1Interactable = stage.call("make_interactable", id, str(c["prompt"]), pos, Vector3.ONE * (r * 1.4), false) as Act1Interactable
		if item != null:
			item.add_to_group("explore_prop")
			item.add_focus_marker(0.11)
			item.prompt_callable = Callable(self, "_prompt_for").bind(id)
			_ambient_entries[id] = {
				"mesh": c["mesh"],
				"pos": pos,
				"cat": str(c["cat"]),
				"prompt": str(c["prompt"]),
				"variant": int(c["variant"]),
				"toggle": false,
			}


func _prompt_for(_p: Node = null, id: String = "") -> String:
	if _ambient_entries.has(id):
		return str((_ambient_entries[id] as Dictionary).get("prompt", "E 检查物件"))
	match id:
		"explore_beacon":
			return "E 关闭气象探照灯闸刀" if bool(_state.get(id, false)) else "E 拉下气象探照灯闸刀"
		"explore_intercom":
			return "E 重播旧调度台磁带录音" if bool(_state.get(id, false)) else "E 按下旧调度台对讲键"
		"explore_oscilloscope":
			return "E 切换副电源谐波示波频段"
		"explore_steam_valve":
			return "E 旋开冷凝管手动泄压手轮"
		"explore_canister":
			return "E 弹出气动地质采样瓶检查读数"
		"explore_bell":
			return "E 敲响发车站台黄铜信号铃"
	return "E 检查"


func trigger(id: String, _pid: int, host_stage: Node) -> void:
	if _ambient_entries.has(id):
		var ent: Dictionary = _ambient_entries[id] as Dictionary
		var tog: bool = not bool(ent.get("toggle", false))
		ent["toggle"] = tog
		var toast_cb := func(msg: String, secs: float) -> void:
			host_stage.call("_send_local_toast", msg, secs)
		ExplorePropKit.trigger_ambient_reaction(self, ent["mesh"] as MeshInstance3D, ent["pos"] as Vector3, str(ent["cat"]), int(ent["variant"]), tog, toast_cb)
		return
	var pivot: Node3D = _pivots.get(id) as Node3D
	var lamp: MeshInstance3D = _lamps.get(id) as MeshInstance3D
	var light: Light3D = _lights.get(id) as Light3D
	match id:
		"explore_beacon":
			var on: bool = not bool(_state.get(id, false))
			_state[id] = on
			if pivot != null:
				create_tween().tween_property(pivot, "rotation_degrees:x", 42.0 if on else -36.0, 0.18)
			if light != null:
				light.visible = on
			if lamp != null:
				lamp.material_override = ExplorePropKit.make_mat(Color(0.2, 0.2, 0.2), 0.1, 0.4, Color(1.0, 0.68, 0.22), 2.4 if on else 0.15)
			if on:
				ExplorePropKit.spawn_burst(self, Vector3(3.65, 1.45, 11.8), Vector3(-0.3, 0.4, 0.2), Color(1.0, 0.78, 0.32), 10, 2.2, 0.45)
			ExplorePropKit.play_wav_3d(self, "res://assets/audio/lever_click.wav", Vector3(3.65, 1.4, 11.8), 1.15)
			host_stage.call("_send_local_toast", "气象站探照灯已开启 · 能见度依然极低（室外粉尘浓度 82%）" if on else "气象站探照灯已关闭")
		"explore_intercom":
			_state[id] = true
			if lamp != null:
				lamp.material_override = ExplorePropKit.make_mat(Color(0.1, 0.2, 0.12), 0.1, 0.4, Color(0.28, 0.95, 0.56), 2.2)
			if pivot != null:
				var tw := create_tween()
				tw.tween_property(pivot, "rotation_degrees:z", 720.0, 1.6).as_relative()
			ExplorePropKit.play_wav_3d(self, "res://assets/audio/sfx/radio_beep.wav", Vector3(3.85, 1.45, 6.0), 1.0)
			host_stage.call("_send_local_toast", "【磁带留言】「02站发车前记得检查风压和货舱扣带——深层轨道有奇怪的回响。」", 4.6)
		"explore_oscilloscope":
			var band: int = (int(_state.get(id, 0)) + 1) % 3
			_state[id] = band
			var cols: Array[Color] = [Color(0.24, 0.88, 1.0), Color(1.0, 0.68, 0.22), Color(0.32, 0.96, 0.62)]
			var msgs: Array[String] = [
				"示波器频段 14.2 Hz · 地面背景噪音正常",
				"示波器频段 42.8 Hz · 检测到深层隧道微弱共振脉冲",
				"示波器频段 88.0 Hz · 谐波同步率极高，像一口在持续共鸣的钟",
			]
			if lamp != null:
				lamp.material_override = ExplorePropKit.make_mat(Color(0.08, 0.12, 0.16), 0.1, 0.35, cols[band], 1.8)
			if pivot != null:
				create_tween().tween_property(pivot, "rotation_degrees:y", 120.0, 0.22).as_relative()
			ExplorePropKit.play_wav_3d(self, "res://assets/audio/sfx/beacon_ping.wav", Vector3(-7.2, 1.35, -3.5), 0.92 + float(band) * 0.22)
			host_stage.call("_send_local_toast", msgs[band], 3.8)
		"explore_steam_valve":
			if pivot != null:
				create_tween().tween_property(pivot, "rotation_degrees:z", 360.0, 0.55).set_trans(Tween.TRANS_BACK)
			ExplorePropKit.spawn_burst(self, Vector3(-8.2, 1.45, -17.5), Vector3(1.0, 0.4, 0.0), Color(0.86, 0.94, 1.0), 22, 3.4, 0.85)
			ExplorePropKit.play_wav_3d(self, "res://assets/audio/sfx/steam_burst.wav", Vector3(-8.2, 1.45, -17.5), 1.05, -3.0)
			host_stage.call("_send_local_toast", "高压冷凝管已泄压 · 排气阀恢复常温（非主风道系统）", 3.2)
		"explore_canister":
			var popped: bool = not bool(_state.get(id, false))
			_state[id] = popped
			if pivot != null:
				create_tween().tween_property(pivot, "position:y", 1.18 if popped else 0.96, 0.25).set_trans(Tween.TRANS_BOUNCE)
			if lamp != null:
				lamp.material_override = ExplorePropKit.make_mat(Color(0.1, 0.15, 0.18), 0.1, 0.3, Color(0.32, 0.92, 1.0), 2.4 if popped else 0.6)
			ExplorePropKit.play_wav_3d(self, "res://assets/audio/pin_pull.wav", Vector3(11.75, 2.55, -42.5), 1.2)
			host_stage.call("_send_local_toast", "采样瓶 #09 已弹出 · 标签：第4层石英砂芯（微弱磁性残留）" if popped else "采样瓶已推回气动槽锁定", 3.8)
		"explore_bell":
			if pivot != null:
				var tw := create_tween()
				tw.tween_property(pivot, "rotation_degrees:z", 28.0, 0.10)
				tw.tween_property(pivot, "rotation_degrees:z", -22.0, 0.14)
				tw.tween_property(pivot, "rotation_degrees:z", 12.0, 0.16)
				tw.tween_property(pivot, "rotation_degrees:z", 0.0, 0.20)
			if lamp != null:
				lamp.material_override = ExplorePropKit.make_mat(Color(0.2, 0.15, 0.05), 0.1, 0.3, Color(1.0, 0.78, 0.26), 2.6)
			ExplorePropKit.play_wav_3d(self, "res://assets/audio/ready.wav", Vector3(11.75, 2.65, -51.6), 1.18, -2.0)
			host_stage.call("_send_local_toast", "当——！发车站台黄铜信号铃回荡在隧道穹顶间", 3.0)


func _build_weather_beacon() -> void:
	var root := Node3D.new()
	root.position = Vector3(3.65, 0.0, 11.8)
	root.rotation_degrees = Vector3(0.0, -90.0, 0.0)
	add_child(root)
	var m_dark := ExplorePropKit.make_mat(Color(0.18, 0.20, 0.22), 0.72, 0.44)
	var m_amber := ExplorePropKit.make_mat(Color(0.92, 0.52, 0.12), 0.35, 0.42)
	ExplorePropKit.cyl(root, "Post", 0.09, 1.35, Vector3(0, 0.675, 0), m_dark)
	ExplorePropKit.box(root, "SwitchBox", Vector3(0.32, 0.42, 0.20), Vector3(0, 1.35, 0.04), m_dark)
	var pivot := Node3D.new()
	pivot.position = Vector3(0, 1.38, 0.14)
	pivot.rotation_degrees = Vector3(-36.0, 0.0, 0.0)
	root.add_child(pivot)
	ExplorePropKit.cyl(pivot, "LeverArm", 0.025, 0.30, Vector3(0, 0.15, 0), ExplorePropKit.make_mat(Color(0.68, 0.70, 0.72), 0.85, 0.32))
	ExplorePropKit.box(pivot, "HandleGrip", Vector3(0.08, 0.05, 0.05), Vector3(0, 0.29, 0), m_amber)
	var lens := ExplorePropKit.cyl(root, "BeaconLens", 0.11, 0.18, Vector3(0, 1.66, 0.0),
		ExplorePropKit.make_mat(Color(0.2, 0.2, 0.2), 0.1, 0.4, Color(1.0, 0.68, 0.22), 0.15))
	var spot := SpotLight3D.new()
	spot.position = Vector3(0, 1.72, 0.1)
	spot.rotation_degrees = Vector3(-12.0, 0.0, 0.0)
	spot.light_color = Color(1.0, 0.76, 0.35)
	spot.light_energy = 4.2
	spot.spot_range = 18.0
	spot.spot_angle = 36.0
	spot.visible = false
	root.add_child(spot)
	_pivots["explore_beacon"] = pivot
	_lamps["explore_beacon"] = lens
	_lights["explore_beacon"] = spot
	_reg("explore_beacon", "E 拉下气象探照灯闸刀", Vector3(3.65, 1.38, 11.8), Vector3(0.65, 0.90, 0.65))


func _build_intercom() -> void:
	var root := Node3D.new()
	root.position = Vector3(3.85, 0.0, 6.0)
	root.rotation_degrees = Vector3(0.0, -90.0, 0.0)
	add_child(root)
	var m_teal := ExplorePropKit.make_mat(Color(0.18, 0.28, 0.30), 0.4, 0.55)
	var m_dark := ExplorePropKit.make_mat(Color(0.14, 0.16, 0.18), 0.7, 0.45)
	ExplorePropKit.box(root, "Stand", Vector3(0.44, 1.20, 0.28), Vector3(0, 0.60, 0), m_dark)
	ExplorePropKit.box(root, "Deck", Vector3(0.50, 0.46, 0.24), Vector3(0, 1.38, 0.02), m_teal)
	var reel := Node3D.new()
	reel.position = Vector3(0, 1.44, 0.15)
	root.add_child(reel)
	ExplorePropKit.cyl(reel, "TapeSpool", 0.09, 0.04, Vector3(0, 0, 0), ExplorePropKit.make_mat(Color(0.84, 0.78, 0.68), 0.2, 0.5), Vector3(90, 0, 0))
	ExplorePropKit.box(reel, "SpoolMark", Vector3(0.16, 0.02, 0.05), Vector3(0, 0, 0.01), m_dark)
	var led := ExplorePropKit.box(root, "PlayLed", Vector3(0.08, 0.04, 0.03), Vector3(0.16, 1.24, 0.14),
		ExplorePropKit.make_mat(Color(0.1, 0.2, 0.1), 0.1, 0.4, Color(0.25, 0.9, 0.5), 0.3))
	_pivots["explore_intercom"] = reel
	_lamps["explore_intercom"] = led
	_reg("explore_intercom", "E 按下旧调度台对讲键", Vector3(3.85, 1.38, 6.0), Vector3(0.65, 0.85, 0.65))


func _build_oscilloscope() -> void:
	var root := Node3D.new()
	root.position = Vector3(-7.2, 0.0, -3.5)
	root.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	add_child(root)
	var m_dark := ExplorePropKit.make_mat(Color(0.16, 0.18, 0.20), 0.72, 0.42)
	var m_cream := ExplorePropKit.make_mat(Color(0.76, 0.72, 0.62), 0.25, 0.52)
	ExplorePropKit.box(root, "Bench", Vector3(0.86, 0.96, 0.56), Vector3(0, 0.48, 0), m_dark)
	ExplorePropKit.box(root, "ScopeCase", Vector3(0.56, 0.38, 0.36), Vector3(0, 1.15, 0), m_cream)
	var screen := ExplorePropKit.box(root, "ScopeScreen", Vector3(0.32, 0.22, 0.04), Vector3(-0.08, 1.17, 0.17),
		ExplorePropKit.make_mat(Color(0.08, 0.14, 0.18), 0.1, 0.3, Color(0.24, 0.88, 1.0), 1.4))
	var dial := Node3D.new()
	dial.position = Vector3(0.16, 1.15, 0.19)
	root.add_child(dial)
	ExplorePropKit.cyl(dial, "Knob", 0.05, 0.05, Vector3.ZERO, m_dark, Vector3(90, 0, 0))
	ExplorePropKit.box(dial, "Pointer", Vector3(0.02, 0.06, 0.06), Vector3(0, 0.02, 0), ExplorePropKit.make_mat(Color(1.0, 0.55, 0.14), 0.2, 0.4))
	_pivots["explore_oscilloscope"] = dial
	_lamps["explore_oscilloscope"] = screen
	_reg("explore_oscilloscope", "E 切换副电源谐波示波频段", Vector3(-7.2, 1.25, -3.5), Vector3(0.75, 0.85, 0.75))


func _build_steam_valve() -> void:
	var root := Node3D.new()
	root.position = Vector3(-8.5, 0.0, -17.5)
	root.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	add_child(root)
	var m_pipe := ExplorePropKit.make_mat(Color(0.30, 0.32, 0.34), 0.78, 0.42)
	ExplorePropKit.cyl(root, "RiserPipe", 0.10, 2.40, Vector3(0, 1.20, -0.15), m_pipe)
	ExplorePropKit.cyl(root, "ValveStem", 0.045, 0.26, Vector3(0, 1.42, 0.0), m_pipe, Vector3(90, 0, 0))
	var wheel := ExplorePropKit.attach_valve_wheel(root, 0.22)
	wheel.position = Vector3(0, 1.42, 0.15)
	_pivots["explore_steam_valve"] = wheel
	_reg("explore_steam_valve", "E 旋开冷凝管手动泄压手轮", Vector3(-8.5, 1.42, -17.5), Vector3(0.75, 0.85, 0.75))


func _build_canister_dispenser() -> void:
	var root := Node3D.new()
	root.position = Vector3(11.75, 1.52, -42.5)
	root.rotation_degrees = Vector3(0.0, -90.0, 0.0)
	add_child(root)
	var m_dark := ExplorePropKit.make_mat(Color(0.20, 0.22, 0.24), 0.72, 0.44)
	ExplorePropKit.box(root, "TubeHousing", Vector3(0.46, 0.95, 0.36), Vector3(0, 0.475, 0), m_dark)
	var canister := ExplorePropKit.cyl(root, "SampleTube", 0.10, 0.36, Vector3(0, 0.96, 0.02),
		ExplorePropKit.make_mat(Color(0.72, 0.78, 0.82), 0.55, 0.32, Color(0.32, 0.92, 1.0), 0.6))
	_pivots["explore_canister"] = canister
	_lamps["explore_canister"] = canister
	_reg("explore_canister", "E 弹出气动地质采样瓶检查读数", Vector3(11.75, 2.55, -42.5), Vector3(0.70, 0.90, 0.70))


func _build_departure_bell() -> void:
	var root := Node3D.new()
	root.position = Vector3(11.75, 1.52, -51.6)
	root.rotation_degrees = Vector3(0.0, -90.0, 0.0)
	add_child(root)
	var m_dark := ExplorePropKit.make_mat(Color(0.18, 0.20, 0.22), 0.75, 0.45)
	var m_brass := ExplorePropKit.make_mat(Color(0.84, 0.66, 0.28), 0.86, 0.28)
	ExplorePropKit.cyl(root, "BellPost", 0.075, 1.32, Vector3(0, 0.66, 0), m_dark)
	ExplorePropKit.box(root, "BracketArm", Vector3(0.10, 0.10, 0.36), Vector3(0, 1.28, 0.14), m_dark)
	var bell_piv := Node3D.new()
	bell_piv.position = Vector3(0, 1.24, 0.26)
	root.add_child(bell_piv)
	ExplorePropKit.cyl(bell_piv, "BrassBell", 0.14, 0.20, Vector3(0, -0.14, 0), m_brass, Vector3.ZERO, 14)
	var beacon := ExplorePropKit.box(root, "BellLamp", Vector3(0.14, 0.10, 0.14), Vector3(0, 1.39, 0.0),
		ExplorePropKit.make_mat(Color(0.2, 0.15, 0.06), 0.1, 0.35, Color(1.0, 0.74, 0.25), 0.4))
	_pivots["explore_bell"] = bell_piv
	_lamps["explore_bell"] = beacon
	_reg("explore_bell", "E 敲响发车站台黄铜信号铃", Vector3(11.75, 2.65, -51.6), Vector3(0.75, 0.95, 0.75))
