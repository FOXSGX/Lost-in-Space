class_name ExplorePropKit
extends RefCounted

## Shared visual, particle, and 3D SFX builders for non-story interactive props
## across Acts 1-5. Strictly diegetic (no floating 3D text labels).

static func make_mat(color: Color, metallic: float = 0.45, roughness: float = 0.52,
		emit: Color = Color.BLACK, emit_energy: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	if emit_energy > 0.0:
		m.emission_enabled = true
		m.emission = emit
		m.emission_energy_multiplier = emit_energy
	return m


static func box(parent: Node3D, name_val: String, size: Vector3, pos: Vector3,
		mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name_val
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


static func cyl(parent: Node3D, name_val: String, radius: float, height: float,
		pos: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO, segs: int = 12) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name_val
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = segs
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


static func play_wav_3d(host: Node, res_path: String, world_pos: Vector3,
		pitch: float = 1.0, volume_db: float = -4.0) -> void:
	if host == null or not host.is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	if not ResourceLoader.exists(res_path):
		return
	var stream := load(res_path) as AudioStream
	if stream == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.pitch_scale = pitch
	p.volume_db = volume_db
	p.unit_size = 6.0
	p.max_distance = 26.0
	host.add_child(p)
	p.global_position = world_pos
	p.finished.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free())
	p.play()


static func spawn_burst(parent: Node3D, local_pos: Vector3, dir: Vector3,
		color: Color, amount: int = 16, speed: float = 2.6, life: float = 0.75) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var cpu := CPUParticles3D.new()
	cpu.position = local_pos
	cpu.amount = amount
	cpu.lifetime = life
	cpu.one_shot = true
	cpu.explosiveness = 0.92
	cpu.direction = dir.normalized()
	cpu.spread = 28.0
	cpu.initial_velocity_min = speed * 0.55
	cpu.initial_velocity_max = speed
	cpu.gravity = Vector3(0.0, -1.6, 0.0)
	var sm := SphereMesh.new()
	sm.radius = 0.045
	sm.height = 0.09
	sm.radial_segments = 5
	sm.rings = 3
	cpu.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	cpu.material_override = mat
	parent.add_child(cpu)
	cpu.emitting = true
	var timer := parent.get_tree().create_timer(life + 0.4)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(cpu):
			cpu.queue_free())


static func attach_valve_wheel(parent: Node3D, radius: float = 0.20,
		rim_mat: Material = null, spoke_mat: Material = null) -> Node3D:
	var wheel := Node3D.new()
	wheel.name = "ValveWheel"
	var m_rim: Material = rim_mat if rim_mat != null else make_mat(Color(0.86, 0.24, 0.14), 0.3, 0.45)
	var m_sp: Material = spoke_mat if spoke_mat != null else make_mat(Color(0.26, 0.28, 0.30), 0.75, 0.42)
	var tor := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius * 0.78
	tm.outer_radius = radius
	tm.rings = 16
	tm.ring_segments = 6
	tor.mesh = tm
	tor.material_override = m_rim
	tor.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	wheel.add_child(tor)
	cyl(wheel, "Hub", radius * 0.24, 0.08, Vector3.ZERO, m_sp, Vector3(90.0, 0.0, 0.0), 10)
	box(wheel, "SpokeH", Vector3(radius * 1.72, 0.032, 0.032), Vector3.ZERO, m_sp)
	box(wheel, "SpokeV", Vector3(0.032, radius * 1.72, 0.032), Vector3.ZERO, m_sp)
	parent.add_child(wheel)
	return wheel


const _SKIP_KEYWORDS := [
	"floor", "ceiling", "wall", "ground", "terrain", "cliff", "talus", "sky",
	"apron", "skirt", "shaft", "motes", "steam", "focusring", "hosetube",
	"ferrule", "wire_core", "shell", "envelope", "tunnel", "endwall", "farrock",
	"void", "pit_opened", "cavern", "rock_cave", "player", "glove", "hand",
	"visor", "helmet_rig", "mite", "pickup", "tread", "gravel",
]


static func collect_primary_points(scene_root: Node) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	if scene_root == null or not scene_root.get_tree():
		return pts
	var tree := scene_root.get_tree()
	for grp: String in ["interactable", "winch_anchor"]:
		for n: Node in tree.get_nodes_in_group(grp):
			if n.is_in_group("explore_prop"):
				continue
			var n3 := n as Node3D
			if n3 == null or not n3.is_inside_tree():
				continue
			pts.append(n3.global_position)
			for child in n3.get_children():
				if child is Area3D or child is CollisionShape3D:
					var c3 := child as Node3D
					pts.append(c3.global_position)
	return pts


static func scan_scene_candidates(scene_root: Node3D, opts: Dictionary = {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if scene_root == null or not scene_root.is_inside_tree():
		return out
	var min_primary_dist: float = float(opts.get("min_primary_dist", 1.55))
	var min_spacing: float = float(opts.get("min_spacing", 1.45))
	var max_props: int = int(opts.get("max_props", 72))
	var skip_cart: bool = bool(opts.get("skip_moving_bodies", true))

	var primary_pts := collect_primary_points(scene_root)
	var extra_skips: Variant = opts.get("extra_skip_points", [])
	if extra_skips is Array:
		for ep: Variant in (extra_skips as Array):
			if ep is Vector3:
				primary_pts.append(ep as Vector3)

	var placed_pts: Array[Vector3] = []
	var queue: Array[Node] = [scene_root]
	var seen_meshes: int = 0
	while not queue.is_empty():
		var cur: Node = queue.pop_front()
		if cur.is_in_group("explore_prop"):
			continue
		if skip_cart and (cur is CharacterBody3D or cur is RigidBody3D or cur is AnimatableBody3D):
			continue
		var cname: String = str(cur.name).to_lower()
		if cname.contains("exploreprops") or cname.contains("mite") or cname.contains("player"):
			continue
		for child in cur.get_children():
			queue.append(child)

		if not (cur is MeshInstance3D):
			continue
		var mi := cur as MeshInstance3D
		if not mi.visible or not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		seen_meshes += 1
		var pname: String = (str(mi.name) + " " + (str(mi.get_parent().name) if mi.get_parent() != null else "")).to_lower()
		var blocked := false
		for kw: String in _SKIP_KEYWORDS:
			if pname.contains(kw):
				blocked = true
				break
		if blocked:
			continue

		var aabb: AABB = mi.global_transform * mi.mesh.get_aabb()
		var max_dim: float = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
		if max_dim < 0.16 or max_dim > 3.90:
			continue
		var center: Vector3 = aabb.get_center()
		if center.y < -4.2 or center.y > 7.2:
			continue

		var near_primary := false
		for pp: Vector3 in primary_pts:
			if Vector2(center.x - pp.x, center.z - pp.z).length() < min_primary_dist and absf(center.y - pp.y) < 2.2:
				near_primary = true
				break
		if near_primary:
			continue

		var too_close := false
		for sp: Vector3 in placed_pts:
			if center.distance_to(sp) < min_spacing:
				too_close = true
				break
		if too_close:
			continue

		var cat: String = _classify_prop(pname, max_dim)
		if cat == "":
			continue
		placed_pts.append(center)
		out.append({
			"mesh": mi,
			"pos": center,
			"cat": cat,
			"prompt": _prompt_for_category(cat),
			"radius": clampf(max_dim * 0.55, 0.35, 1.15),
			"variant": seen_meshes + out.size(),
		})
		if out.size() >= max_props:
			break
	return out


static func _classify_prop(pname: String, max_dim: float) -> String:
	if pname.contains("crystal") or pname.contains("shard") or pname.contains("cluster") or pname.contains("bell") or pname.contains("socket") or pname.contains("quartz"):
		return "crystal"
	if pname.contains("valve") or pname.contains("pipe") or pname.contains("conduit") or pname.contains("duct") or pname.contains("vent") or pname.contains("louver") or pname.contains("hose") or pname.contains("manifold"):
		return "valve_pipe"
	if pname.contains("lamp") or pname.contains("light") or pname.contains("beacon") or pname.contains("flood") or pname.contains("lens") or pname.contains("strobe"):
		return "lamp"
	if pname.contains("plaque") or pname.contains("panel") or pname.contains("screen") or pname.contains("schematic") or pname.contains("dial") or pname.contains("gauge") or pname.contains("board") or pname.contains("sign") or pname.contains("meter") or pname.contains("terminal"):
		return "panel_sign"
	if pname.contains("crate") or pname.contains("bench") or pname.contains("tool") or pname.contains("locker") or pname.contains("chest") or pname.contains("drum") or pname.contains("barrel") or pname.contains("canister") or pname.contains("cabinet") or pname.contains("case") or pname.contains("box") or pname.contains("wrench"):
		return "crate_tool"
	if pname.contains("rock") or pname.contains("outcrop") or pname.contains("shelf") or pname.contains("boulder") or pname.contains("stone") or pname.contains("spur") or pname.contains("debris"):
		return "rock"
	if pname.contains("cart") or pname.contains("rail") or pname.contains("wheel") or pname.contains("sleeper") or pname.contains("ladder") or pname.contains("truss") or pname.contains("post") or pname.contains("support") or pname.contains("column") or pname.contains("chock") or pname.contains("brake") or pname.contains("winch"):
		return "mech_gear"
	if max_dim >= 0.24 and max_dim <= 2.40:
		return "mech_gear"
	return ""


static func _prompt_for_category(cat: String) -> String:
	match cat:
		"crystal":
			return "E 轻触探测晶体样本"
		"valve_pipe":
			return "E 检视并敲击管路接头"
		"lamp":
			return "E 测试/轻拍照明灯罩"
		"panel_sign":
			return "E 近距离检查铭牌与读数"
		"crate_tool":
			return "E 翻看设备箱/工具杂物"
		"rock":
			return "E 敲击岩样检测矿脉空声"
		"mech_gear":
			return "E 轻敲检查金属构件状态"
	return "E 检查物件"


static func trigger_ambient_reaction(host: Node3D, mesh: MeshInstance3D, world_pos: Vector3,
		cat: String, variant_id: int, toggle_state: bool, toast_cb: Callable) -> void:
	if host != null and is_instance_valid(mesh):
		var base_scale: Vector3 = mesh.scale
		var tw := host.create_tween()
		tw.tween_property(mesh, "scale", base_scale * Vector3(1.06, 0.94, 1.06), 0.08).set_trans(Tween.TRANS_SINE)
		tw.tween_property(mesh, "scale", base_scale * Vector3(0.98, 1.03, 0.98), 0.10)
		tw.tween_property(mesh, "scale", base_scale, 0.14)

	var v := absi(variant_id) + (1 if toggle_state else 0)
	match cat:
		"crystal":
			var notes: Array[String] = [
				"轻敲晶面后发出清亮 C# 泛音——内部晶格正在低频微振。",
				"手指贴近感到一丝温热：这块晶簇仍保留着残留共鸣电流。",
				"切面里看得见层层生长纹，表面落着一层矿区细尘。",
				"敲击瞬间闪出短暂青晕，回声顺着岩缝往下传了数米。",
				"晶体边缘相当锐利，根部紧紧咬在深色围岩裂缝里。",
			]
			if host != null and host.is_inside_tree():
				spawn_burst(host, host.to_local(world_pos), Vector3(0.0, 1.0, 0.0), Color(0.36, 0.94, 1.0), 10, 1.8, 0.55)
				_spawn_temp_flash(host, world_pos, Color(0.35, 0.92, 1.0), 2.4)
			play_wav_3d(host, "res://assets/audio/sfx/crystal_pulse.wav", world_pos, 0.86 + float(v % 5) * 0.10, -4.0)
			_emit_toast(toast_cb, notes[v % notes.size()])
		"valve_pipe":
			var notes: Array[String] = [
				"接头处喷出一丝干燥白雾——管内只剩微弱残压。",
				"轻敲管壁声音清脆，保温包覆层虽有磨损但依然严密。",
				"卡箍螺栓咬合得很死，管壁上能感觉到远处传来的周期脉冲。",
				"管体手感微凉，冷凝水正顺着最低点弯曲处慢慢滴落。",
				"管道漆面上留着班组用油漆笔划下的流向校准记号。",
			]
			if host != null and host.is_inside_tree():
				spawn_burst(host, host.to_local(world_pos), Vector3(0.0, 1.0, 0.25), Color(0.86, 0.92, 0.98), 12, 2.2, 0.65)
			play_wav_3d(host, "res://assets/audio/sfx/steam_burst.wav", world_pos, 0.95 + float(v % 4) * 0.08, -6.0)
			_emit_toast(toast_cb, notes[v % notes.size()])
		"lamp":
			var notes: Array[String] = [
				"轻拍防爆灯罩：钨丝短暂亮起一闪，应急备用电源还算稳定。",
				"玻璃罩内壁沾了灰尘，灯座散热片传来一点微弱暖意。",
				"拨动灯壳侧面的检修微动开关，工作灯柱脉动闪烁了一下。",
				"灯具外壳有几道擦碰旧痕，但密封胶圈依旧牢靠。",
			]
			if host != null and host.is_inside_tree():
				_spawn_temp_flash(host, world_pos + Vector3(0, 0.2, 0), Color(1.0, 0.80, 0.48), 2.8)
			play_wav_3d(host, "res://assets/audio/lever_click.wav", world_pos, 1.10, -4.0)
			_emit_toast(toast_cb, notes[v % notes.size()])
		"crate_tool":
			var notes: Array[String] = [
				"箱角塞着两颗备用六角螺母和一截剪断的铜包线。",
				"翻到半卷耐高温黄色警示胶带与一只沾满润滑油的开口扳手。",
				"箱底垫着一张皱巴巴的班次记录纸条：‘撤离前别忘了关总阀。’",
				"盒子里只有一双磨破指尖的隔热手套和两只空采样管套。",
				"金属箱体发出沉实的空腔回响，里面压着几块配重备用垫片。",
				"边角压着一枚老式矿灯备用电池，电量表早已归零。",
			]
			if host != null and host.is_inside_tree():
				spawn_burst(host, host.to_local(world_pos), Vector3(0.0, 0.8, 0.0), Color(0.76, 0.70, 0.58), 6, 1.2, 0.40)
			play_wav_3d(host, "res://assets/audio/metal_clank.wav", world_pos, 1.05 + float(v % 3) * 0.12, -5.0)
			_emit_toast(toast_cb, notes[v % notes.size()])
		"panel_sign":
			var notes: Array[String] = [
				"检视铭牌刻字：表面有检修划痕，工业编号仍可清晰辨认。",
				"机身外壳留有例行巡检铅封印记，指示模块处于在线监测态。",
				"靠近能听见面板背面继电器极轻微的嗡鸣声。",
				"表壳边缘贴着防水涂装胶条，内部接线按色标梳理得十分工整。",
			]
			if host != null and host.is_inside_tree():
				_spawn_temp_flash(host, world_pos, Color(0.32, 0.90, 1.0), 1.6)
			play_wav_3d(host, "res://assets/audio/sfx/radio_beep.wav", world_pos, 1.0 + float(v % 4) * 0.09, -5.0)
			_emit_toast(toast_cb, notes[v % notes.size()])
		"rock":
			var notes: Array[String] = [
				"敲击岩壁样本发出沉实闷响——深层沉积岩结构非常稳固。",
				"岩石断口锋利，层理缝隙中夹着细小的蓝灰矿物颗粒。",
				"手摸上去略显湿凉，侧面能看出明显的水蚀/崩积纹理。",
				"岩块底部已被当年开拓时的重型支座死死压入地基里。",
			]
			if host != null and host.is_inside_tree():
				spawn_burst(host, host.to_local(world_pos), Vector3(0.0, 0.9, 0.0), Color(0.55, 0.48, 0.40), 8, 1.5, 0.45)
			play_wav_3d(host, "res://assets/audio/sfx/cart_clank.wav", world_pos, 0.72, -6.0)
			_emit_toast(toast_cb, notes[v % notes.size()])
		_:
			var notes: Array[String] = [
				"轻敲金属构件回响扎实——重型工业钢架依然牢牢吃着底座应力。",
				"构件焊接面与螺栓压板完好，没有出现危险级结构松动。",
				"表面漆膜虽已风化起皮，但内层底漆仍牢牢护着钢骨。",
				"细看底座边缘还能摸到施工时留下的少许砂砾与压痕。",
			]
			play_wav_3d(host, "res://assets/audio/metal_clank.wav", world_pos, 0.92 + float(v % 3) * 0.08, -6.0)
			_emit_toast(toast_cb, notes[v % notes.size()])


static func _emit_toast(toast_cb: Callable, text: String) -> void:
	if toast_cb.is_valid():
		toast_cb.call(text, 3.0)


static func _spawn_temp_flash(host: Node3D, world_pos: Vector3, color: Color, energy: float) -> void:
	if host == null or not host.is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = 4.2
	light.shadow_enabled = false
	host.add_child(light)
	light.global_position = world_pos
	var tw := host.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.45)
	tw.tween_callback(func() -> void:
		if is_instance_valid(light):
			light.queue_free())


class AmbientProbeBody extends StaticBody3D:
	var target_mesh: MeshInstance3D = null
	var probe_cat: String = "mech_gear"
	var probe_prompt: String = "E 检查物件"
	var variant_id: int = 0
	var toggle_state: bool = false
	var toast_cb: Callable
	var host_node: Node3D = null
	var _act4_mode: bool = false

	func _init(p_act4_mode: bool = false, p_layer: int = 8) -> void:
		_act4_mode = p_act4_mode
		collision_layer = p_layer
		collision_mask = 0
		add_to_group("interactable")
		add_to_group("explore_prop")
		var cs := CollisionShape3D.new()
		var ss := SphereShape3D.new()
		ss.radius = 0.55
		cs.shape = ss
		add_child(cs)

	func get_interaction_position() -> Vector3:
		return global_position

	func get_interaction_reach() -> float:
		return 2.5

	func get_interaction_prompt(_player: Node) -> String:
		return probe_prompt

	func get_prompt() -> String:
		return probe_prompt

	func interact(_player: Node) -> void:
		toggle_state = not toggle_state
		var kit: Variant = load("res://scripts/world/explore_prop_kit.gd")
		if kit != null:
			kit.trigger_ambient_reaction(host_node, target_mesh, global_position, probe_cat, variant_id, toggle_state, toast_cb)

