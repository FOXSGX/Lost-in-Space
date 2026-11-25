extends "res://previews/frost_first_playable/adventure.gd"

const SANDBOX_GAMEPLAY: Script = preload("res://previews/frost_station/frost_sandbox_gameplay.gd")
const COMPASS_HUD_SCRIPT: Script = preload("res://scripts/mission_compass_hud.gd")
var sandbox: Node3D
var compass_hud: MissionCompassHUD
var grabbed: Dictionary = {}
var beam: MeshInstance3D
var push_clock: Dictionary = {}
var push_latched: Dictionary = {}

func make_world() -> Node3D:return load("res://previews/frost_station/world.gd").new()
func make_actor() -> SpacePlayer3D:return load("res://previews/frost_station/player.gd").new()
func make_items() -> CrewItems3D:return load("res://previews/frost_station/items.gd").new()

func create_threat(point: Vector3) -> void:
	super.create_threat(point+Vector3(0,0,280) if point.z<-700 else point)

func _ready() -> void:
	super._ready()
	DisplayServer.window_set_title("迷失太空 · 霜烬星 2.0 · 极寒科考盆地")
	if menu != null:
		menu.theme = UIStyleKit.build_app_theme()
		menu.add_theme_stylebox_override("panel", UIStyleKit.box(UIStyleKit.CREAM_BG, UIStyleKit.BORDER_SOFT, 20, 1, 26, 22, 14))
		for btn: Node in menu.find_children("*", "Button", true, false):
			var b: Button = btn as Button
			if b.text.contains("单人"):
				UIStyleKit.style_button(b, "orange", 12)
			elif b.text.contains("主机"):
				UIStyleKit.style_button(b, "teal", 12)
			else:
				UIStyleKit.style_button(b, "sand", 12)
	for child: Node in menu.find_children("*","Label",true,false):
		if child.text.begins_with("霜烬星"):
			child.text = "霜烬星 · 极寒科考盆地\n单人或局域网 1–4 人"
			child.add_theme_font_override("font", UIStyleKit.FONT_BOLD)
			child.add_theme_font_size_override("font_size", 24)
			child.add_theme_color_override("font_color", UIStyleKit.NAVY_INK)
		else:
			child.add_theme_color_override("font_color", UIStyleKit.MUTED_INK)
	# 霜烬星写实科幻头盔面罩投影 HUD（仅靠近可交互物体或开车时显示底部提示）
	for lb: Label in [hud_title, hud_prompt, hud_status]:
		if lb != null:
			lb.add_theme_font_override("font", UIStyleKit.FONT_BOLD)
			lb.add_theme_font_size_override("font_size", 15)
			lb.add_theme_color_override("font_color", UIStyleKit.VISOR_TEXT)
			lb.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
			lb.add_theme_stylebox_override("normal", UIStyleKit.box(UIStyleKit.VISOR_GLASS, UIStyleKit.VISOR_BORDER, 6, 1, 16, 6, 4))
	if hud_title != null:
		_place_hud(hud_title, Control.PRESET_CENTER_TOP, Vector2(-260, 14), Vector2(520, 34))
		hud_title.add_theme_color_override("font_color", UIStyleKit.VISOR_CYAN)
	if hud_prompt != null:
		_place_hud(hud_prompt, Control.PRESET_CENTER_BOTTOM, Vector2(-260, -152), Vector2(520, 40))
		hud_prompt.visible = false
	if hud_status != null:
		_place_hud(hud_status, Control.PRESET_CENTER_BOTTOM, Vector2(-300, -152), Vector2(600, 40))
		hud_status.visible = false
	beam = MeshInstance3D.new()
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = 0.025
	mesh.bottom_radius = 0.025
	mesh.height = 1
	beam.mesh = mesh
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color("83e2e6")
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam.material_override = mat
	beam.visible = false
	add_child(beam)
	sandbox = SANDBOX_GAMEPLAY.new() as Node3D
	add_child(sandbox)
	sandbox.setup(self, world)
	compass_hud = COMPASS_HUD_SCRIPT.new() as MissionCompassHUD
	if hud_title != null and hud_title.get_parent() != null:
		hud_title.get_parent().add_child(compass_hud)
	else:
		var cl: CanvasLayer = CanvasLayer.new()
		cl.layer = 20
		add_child(cl)
		cl.add_child(compass_hud)

func begin_embedded(host: bool, ids: Array, saved: Dictionary, ship_items: Dictionary) -> void:
	var compatible: Dictionary = saved if int(saved.get("surface_schema",0))==4 else {}
	super.begin_embedded(host,ids,compatible,ship_items)
	if not saved.is_empty() and compatible.is_empty():
		# Preserve quest progress; old ice IDs cannot be applied to rebuilt geometry.
		progress = saved.get("progress",progress).duplicate(true)
		if host:
			var backup: FileAccess = FileAccess.open("user://frost-v3-before-station-"+str(Time.get_unix_time_from_system())+".dat",FileAccess.WRITE)
			if backup != null:backup.store_var(saved)
	world.cart.riders.clear()

func _input(event: InputEvent) -> void:
	super._input(event)
	if game_started and not _settings_visible and not _journal_visible and event.is_action_pressed("scan"):
		handle_action(multiplayer.get_unique_id(),"push")

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not game_started:return
	world.cart.tick(delta)
	if sandbox != null:
		sandbox.tick(delta)
	world.apply_progress(progress)
	# 动态极地吹雪节奏：周期性微调雾效浓度，让车灯、站区路灯与雷达航标真正有用
	if world.frost_art != null and world.frost_art.environment != null:
		var gust: float = 0.5 + 0.5 * sin(elapsed * 0.11)
		world.frost_art.environment.fog_density = lerpf(0.0024, 0.0052, gust * gust)
	if is_host:
		for id: int in push_latched.keys():
			if not players.has(id) or not players[id].controls.get("heat",false):push_latched.erase(id)
		if progress.get("district_power",false):
			for actor: Node3D in players.values():
				if actor.position.distance_to(Vector3(31,0,-65))<12 or actor.position.distance_to(Vector3(58,0,-110))<12 or actor.position.distance_to(Vector3(45,0,-155))<12:
					actor.warmth = minf(1.5,actor.warmth+delta*0.12)
		for id: int in grabbed.keys():
			if not is_instance_valid(grabbed[id]) or not players.has(id) or players[id].downed or not players[id].controls.get("heat",false) or _items.selected(id).get("kind","")!="suction" or _items.ensure_bag(id).equipment_active:grabbed.erase(id)

func handle_action(id: int, action: String) -> void:
	if not is_host:
		super.handle_action(id,action)
		return
	if not players.has(id) or players[id].downed:return
	if action == "push":
		push_target(id)
		return
	if action == "interact":
		if world.cart.riders.has(id):
			if not world.cart.exit_rider(id):tell(id,"旁边没有安全落脚处 · 停稳后换个位置下车")
			return
		var rear: Vector3 = world.cart.to_global(Vector3(0,1,2.8))
		if world.cart.reachable(players[id],rear,2.8):
			world.cart.load_or_unload(id)
			return
		if world.cart.board(id):
			tell(id,"已上车 · 第一位驾驶，WASD 行驶，E 下车；后方货斗 E 装卸")
			return
	super.handle_action(id,action)

func use_station(id: int, entry: Dictionary) -> void:
	if entry.kind == "safe":
		progress["safe_seen"] = true
		super.use_station(id, entry)
		return
	if entry.kind == "district_power":
		progress.district_power = true
		world.apply_power(true)
		tell(id,"旁路已恢复 · 作业院与北哨中继站亮灯供暖，维护台可慢充补氧")
	elif entry.kind == "radar_tower":
		progress["radar_online"] = true
		world.apply_radar(true)
		if players.has(id):
			players[id].warmth = minf(1.5, players[id].warmth + 0.4)
		tell(id,"气象雷达已重启 · 全盆地冰原公路航标灯全部点亮！")
	elif entry.kind == "west_probe":
		progress["west_probe_read"] = true
		tell(id,"已读取探测舱遥测：遗迹冰层下方存在多段巨型骨架空腔，周边能源箱可装车运回。")
	elif entry.kind == "collection":
		if _items.selected(id).get("kind","")=="keepsake" and not _items.ensure_bag(id).equipment_active:
			_items.take_selected(id)
			progress["collection_count"] = int(progress.get("collection_count",0))+1
			_items.publish()
		tell(id,"飞船收藏柜 · 已收藏科考纪念杯 %d 件" % int(progress.get("collection_count",0)))
	else:super.use_station(id,entry)

func charge_at_station(id: int, delta: float) -> void:
	var entry: Dictionary = nearby_station(id)
	if entry.get("district_power",false) and not progress.get("district_power",false):return
	super.charge_at_station(id,delta)

func aim_ray(id: int, distance: float = 9.0) -> Dictionary:
	var actor: SpacePlayer3D = players[id]
	var origin: Vector3 = actor.position+Vector3.UP*1.5
	var aim: Vector3 = Basis(Vector3.UP,actor.rotation.y)*Vector3(0,-sin(actor._network_view_pitch),-cos(actor._network_view_pitch))
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin,origin+aim*distance,1|2|8,[actor.get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query)

func apply_heat(id: int, delta: float) -> void:
	if _items.selected(id).get("kind","")!="suction":
		if sandbox != null and players.has(id):
			var hit_h: Dictionary = aim_ray(id, 11.0)
			if not hit_h.is_empty():
				sandbox.heat_hit_at(hit_h.position, delta)
		super.apply_heat(id,delta)
		return
	if _items.ensure_bag(id).equipment_active:return
	if push_latched.get(id,false):return
	var actor: SpacePlayer3D = players[id]
	var target: Node3D = grabbed.get(id) as Node3D if is_instance_valid(grabbed.get(id)) else null
	if target == null:
		var hit: Dictionary = aim_ray(id)
		target = hit.get("collider") as Node3D
		if not target is RigidBody3D and not target is SpacePlayer3D:return
		if target == world.cart or (target is SpacePlayer3D and target.downed):return
		for other: int in grabbed:
			if grabbed[other]==target:return
		grabbed[id] = target
	var origin: Vector3 = actor.position+Vector3.UP*1.5
	var aim: Vector3 = Basis(Vector3.UP,actor.rotation.y)*Vector3(0,-sin(actor._network_view_pitch),-cos(actor._network_view_pitch))
	var desired: Vector3 = origin+aim*3.2
	var sight: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin,target.global_position,2)
	if target.position.distance_to(origin)>11 or not get_world_3d().direct_space_state.intersect_ray(sight).is_empty():
		grabbed.erase(id)
		return
	if target is RigidBody3D:
		target.sleeping = false
		target.linear_velocity = (desired-target.position).limit_length(10)*4
	elif target is SpacePlayer3D:
		var pull: Vector3 = (desired-target.position).limit_length(4)*2
		target.launch_velocity = Vector3(pull.x,0,pull.z)
		target.launch_time = 0.12
		target.velocity.y = clampf(pull.y,-4,5)

func push_target(id: int) -> void:
	if _items.selected(id).get("kind","")!="suction" or _items.ensure_bag(id).equipment_active:return
	if elapsed-float(push_clock.get(id,-1))<0.25:return
	push_clock[id] = elapsed
	push_latched[id] = true
	var target: Node3D = grabbed.get(id) as Node3D if is_instance_valid(grabbed.get(id)) else null
	if target == null:target = aim_ray(id).get("collider") as Node3D
	grabbed.erase(id)
	if target == null:return
	var actor: SpacePlayer3D = players[id]
	var aim: Vector3 = Basis(Vector3.UP,actor.rotation.y)*Vector3(0,-sin(actor._network_view_pitch),-cos(actor._network_view_pitch))
	if target is RigidBody3D:
		target.apply_central_impulse(aim*18)
	elif target is SpacePlayer3D and target != actor and not target.downed:
		target.launch_velocity = aim*7
		target.launch_time = 0.7
		target.velocity.y = maxf(target.velocity.y,4.5)
	else:return
	tell(id,"推出！")

func _left(id: int) -> void:
	world.cart.exit_rider(id,true)
	grabbed.erase(id)
	super._left(id)

func respawn_team() -> void:
	for id: int in world.cart.riders.duplicate():world.cart.exit_rider(id,true)
	grabbed.clear()
	super.respawn_team()

func snapshot() -> Dictionary:
	var data: Dictionary = super.snapshot()
	data.surface_schema = 4
	data.cart = world.cart.state()
	var rays: Dictionary = {}
	for id: int in grabbed:
		if is_instance_valid(grabbed[id]):rays[id] = grabbed[id].position
	data.grab_rays = rays
	return data

func apply_frost_state(data: Dictionary) -> void:
	if int(data.get("surface_schema",0))!=4:return
	super.apply_frost_state(data)
	world.cart.apply_state(data.get("cart",{}))
	world.apply_progress(progress)
	set_meta("grab_rays",data.get("grab_rays",{}))

func _process(delta: float) -> void:
	super._process(delta)
	if not game_started:return
	var id: int = multiplayer.get_unique_id()
	var actor: SpacePlayer3D = players.get(id) as SpacePlayer3D
	if actor == null:return
	_update_mission_compass_and_beacon(actor)
	hud_title.text = world.location(actor.position)+" · "+("航行已恢复" if progress.flight else ("回飞船安装能源" if progress.energy else ("返回主楼二层开柜" if progress.key else "主线：前往主楼二层查明能源保险柜")))
	if world.cart.riders.has(id):
		hud_status.text = "极地运输车 · %.0f km/h · 货物 %d/%d · Shift 加速 · E 下车" % [absf(world.cart.speed) * 3.6, world.cart.cargo.size(), world.cart.MAX_CARGO]
		hud_status.visible = true
	else:
		# 不开车时彻底隐藏底部常驻按键说明条，避免文字太多遮挡画面
		hud_status.text = ""
		hud_status.visible = false
	if world.cart.reachable(actor,world.cart.to_global(Vector3(0,1,2.8)),2.8):
		hud_prompt.text = notice if notice_time>0 else "E 装入手持物件 / 空手取货"
	elif world.cart.reachable(actor,world.cart.position+Vector3.UP,4.8):
		hud_prompt.text = notice if notice_time>0 else "E 上运输车"
	if hud_prompt != null:
		hud_prompt.visible = not hud_prompt.text.strip_edges().is_empty()
	var end: Vector3
	var active: bool = false
	if is_host and is_instance_valid(grabbed.get(id)):
		end = grabbed[id].position
		active = true
	elif not is_host and get_meta("grab_rays",{}).has(id):
		end = get_meta("grab_rays")[id]
		active = true
	beam.visible = active
	if active:
		var from: Vector3 = actor._camera.global_position+actor._camera.global_basis*Vector3(0.3,-0.3,-0.6)
		beam.position = (from+end)*0.5
		beam.scale.y = from.distance_to(end)
		beam.quaternion = Quaternion(Vector3.UP,(end-from).normalized())

func _update_mission_compass_and_beacon(actor: SpacePlayer3D) -> void:
	var stage_t: String = ""
	var m_title: String = ""
	var m_detail: String = ""
	var target_pos: Vector3 = world.landmarks.get("safe", Vector3(-5.0, 5.1, -120.0))
	var target_lbl: String = "主楼保险柜"
	var target_col: Color = Color("#4ef0ff")

	if bool(progress.get("flight", false)):
		stage_t = "主线已完成 · 航行恢复"
		m_title = "归航号已恢复动力！"
		m_detail = "可继续驾车探索盆地外围地标，或返回飞船进舱启程前往下一颗星球。"
		target_pos = world.landmarks.get("ship", Vector3(0.0, 0.9, 8.0))
		target_lbl = "归航号飞船"
		target_col = Color("#7cf2b4")
	elif bool(progress.get("energy", false)) or bool(progress.get("installed", false)):
		stage_t = "主线 4 / 4 · 核心回船点火"
		m_title = "返回【归航号飞船】安装核心"
		m_detail = "携带高能核心回到南部停机坪飞船核心台，按 E 安装并点火恢复航行。"
		target_pos = Vector3(0.0, 2.1, 16.0)
		target_lbl = "飞船核心台"
		target_col = Color("#ffcf66")
	elif bool(progress.get("key", false)):
		stage_t = "主线 3 / 4 · 开启能源保险柜"
		m_title = "返回【主科研楼二层】开启保险柜"
		m_detail = "已拿到遗迹密钥！回主楼二层首席办公室按 E 开柜取出高能起飞核心。"
		target_pos = world.landmarks.get("safe", Vector3(-5.0, 5.1, -120.0))
		target_lbl = "二层保险柜"
		target_col = Color("#7cf2b4")
	elif bool(progress.get("safe_seen", false)):
		stage_t = "主线 2 / 4 · 深入巨骨冰川峡谷"
		m_title = "北上【巨骨遗迹深处】夺取密钥"
		m_detail = "保险柜已锁！推荐先去东南【车库】开极地探险车，沿东侧公路直冲巨骨峡谷取回密钥。"
		target_pos = world.landmarks.get("key", Vector3(-2.4, 12.9, -602.0))
		target_lbl = "遗迹密钥"
		target_col = Color("#ffae4a")
	else:
		stage_t = "主线 1 / 4 · 查明备用能源"
		m_title = "前往【主科研楼二层】检查保险柜"
		m_detail = "顺着地面青蓝发光导管进正北主楼，一楼可拿吸推器，沿西侧楼梯上二层找首席办公室。"
		target_pos = world.landmarks.get("safe", Vector3(-5.0, 5.1, -120.0))
		target_lbl = "主楼保险柜"
		target_col = Color("#4ef0ff")

	# 同步 3D 世界物理主线天空光柱（无文字，400m 外清晰可见）
	if world.frost_art != null and world.frost_art.has_method("set_objective_beacon"):
		world.frost_art.set_objective_beacon(target_pos, target_col)

	if compass_hud == null:
		return
	compass_hud.visible = game_started and not _settings_visible and not _journal_visible and not actor.downed
	if not compass_hud.visible:
		return
	var pwr_ok: bool = bool(progress.get("district_power", false))
	var rdr_ok: bool = bool(progress.get("radar_online", false))
	var prb_ok: bool = bool(progress.get("west_probe_read", false))
	var col_cnt: int = int(progress.get("collection_count", 0))
	var sides: PackedStringArray = PackedStringArray([
		"外围大盆地探索（可选高乐趣）：",
		"%s 动力站通电亮灯供暖" % ("✓" if pwr_ok else "☐"),
		"%s 东线高地重启气象雷达" % ("✓" if rdr_ok else "☐"),
		"%s 西线冰缝探测舱黑匣子" % ("✓" if prb_ok else "☐"),
		"★ 飞船收藏柜纪念杯 (%d/4)" % col_cnt,
	])
	var fwd: Vector3 = -actor._camera.global_basis.z if actor._camera != null else -actor.global_basis.z
	var targets: Array = [
		{"label": target_lbl, "pos": target_pos, "color": target_col, "main": true},
		{"label": "探险车", "pos": world.cart.global_position if world.cart != null else Vector3(45, 1, -20), "color": Color("#f4c068"), "main": false},
		{"label": "动力站", "pos": Vector3(58, 1, -116), "color": Color("#ffaa4c"), "main": false},
		{"label": "雷达高地", "pos": Vector3(215, 15, -75), "color": Color("#7ce8b4"), "main": false},
		{"label": "探测舱", "pos": Vector3(-210, 2, -90), "color": Color("#78d4f0"), "main": false},
	]
	compass_hud.update_guidance(actor.global_position, fwd, stage_t, m_title, m_detail, sides, targets)
