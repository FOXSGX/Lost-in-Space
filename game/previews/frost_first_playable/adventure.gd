extends Main3D

const ACTOR: Script = preload("res://previews/frost_first_playable/player.gd")
const ITEMS: Script = preload("res://previews/frost_first_playable/items.gd")
const SESSION: Script = preload("res://previews/frost_first_playable/session.gd")
const WORLD: Script = preload("res://previews/frost_first_playable/world.gd")
const FROST_PORT: int = 24579
signal board_requested(peer_id: int)
var embedded: bool = false
var embedded_ready: Array[int] = [1]
var world: Node3D
var progress: Dictionary = {"key":false,"energy":false,"installed":false,"flight":false,"evidence":false,"fuel":0,"wipes":0}
var control_age: Dictionary = {}
var notice: String = ""
var notice_time: float = 0
var elapsed: float = 0
var sync_clock: float = 0
var wipe_clock: float = 0
var hud_title: Label
var hud_prompt: Label
var hud_status: Label
var menu: PanelContainer
var address: LineEdit
var mist: MeshInstance3D
var blower: AudioStreamPlayer
var test_mode: bool = false
var prototype: bool = false
var threats: Array[Dictionary] = []
var threat_clock: float = 0
var journal_panel: PanelContainer
var journal_text: Label
var confirm_sound: AudioStreamPlayer
var air: CPUParticles3D

func _ready() -> void:
	name = "FrostAdventure"
	current_planet_id = "frost_first_playable"
	ship_active = false
	_world_root = Node3D.new()
	_world_root.name = "ItemWorld"
	add_child(_world_root)
	_ship_session = SESSION.new()
	_ship_session.name = "Session"
	add_child(_ship_session)
	_items = make_items()
	_items.name = "Items"
	add_child(_items)
	prototype = "--prototype" in OS.get_cmdline_user_args()
	world = make_world()
	world.name = "FrostWorld"
	add_child(world)
	world.build(prototype)
	for creature: Node3D in world.creatures:
		creature.popped.connect(_on_pop)
	_build_adventure_ui()
	_health_hud = HealthHUD3D.new()
	add_child(_health_hud)
	if embedded:
		world.station("board",Vector3(3.2,1.5,12),"进入飞船主舱 · 补给与航线电脑",false)
		world.pictogram(Vector3(3.2,2.65,12.4),"res://assets/ship-hub/computer-icons/exit.svg")
		menu.hide()
		return
	multiplayer.peer_connected.connect(_joined)
	multiplayer.peer_disconnected.connect(_left)
	multiplayer.connected_to_server.connect(func() -> void: show_notice("已连接，正在接收世界状态"))
	multiplayer.connection_failed.connect(_connection_failed)
	multiplayer.server_disconnected.connect(_server_gone)
	DisplayServer.window_set_title("迷失太空 · 霜烬星 0.3 · 科考站")
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if "--host" in args:
		start_session(true)
	elif "--join" in args:
		var i: int = args.find("--join")
		start_session(false,args[i+1] if i+1 < args.size() else "127.0.0.1")
	elif "--solo" in args or prototype:
		start_session(false)

func make_items() -> CrewItems3D:
	return ITEMS.new()

func make_world() -> Node3D:
	return WORLD.new()

func make_actor() -> SpacePlayer3D:
	return ACTOR.new()

func begin_embedded(host: bool, ids: Array, saved: Dictionary, ship_items: Dictionary) -> void:
	is_host = host
	game_started = true
	menu.hide()
	_settings_visible = false
	for id: int in ids:
		spawn_actor(id, false)
	if saved.is_empty():
		_items.drops = world.loot.duplicate(true)
		create_threat(Vector3(30,1,-810))
		create_threat(Vector3(35,1,-825))
	else:
		apply_frost_state(saved)
	var inventory: Dictionary = _items.snapshot()
	inventory.bags = ship_items.get("bags", {}).duplicate(true)
	inventory.next_uid = maxi(int(inventory.next_uid), int(ship_items.get("next_uid", 1)))
	_items.apply_state(inventory)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func start_session(hosting: bool, ip: String = "") -> void:
	if game_started:
		return
	is_host = ip.is_empty()
	if hosting or not ip.is_empty():
		var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
		var error: Error = peer.create_server(FROST_PORT,3) if hosting else peer.create_client(ip,FROST_PORT)
		if error != OK:
			show_notice("网络启动失败："+error_string(error))
			return
		multiplayer.multiplayer_peer = peer
	game_started = true
	menu.hide()
	_settings_visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if is_host:
		_items.drops = world.loot.duplicate(true)
		spawn_actor(1,true)
		if not prototype:
			create_threat(Vector3(30,1,-810))
			create_threat(Vector3(35,1,-825))
	print("FROST_ADVENTURE_READY host=",is_host," prototype=",prototype)

func spawn_actor(id: int, provision: bool) -> void:
	if players.has(id):
		return
	var actor: SpacePlayer3D = make_actor()
	actor.setup(id,Color("72d3d3") if id==1 else Color("f2bc75"))
	players[id] = actor
	connected_ids.append(id)
	add_child(actor)
	actor.position = Vector3((players.size()-1)*1.5,1.1,8 if not prototype else 4)
	if provision:
		_items.ensure_bag(id).equipment_active = false
		if prototype:
			_items.add_item(id,"oxygen")
			_items.mount_oxygen(id)
			_items.add_item(id,"heater",-1,{},true)
	control_age[id] = 0.0

func _joined(id: int) -> void:
	if is_host:
		spawn_actor(id,true)
		sync_world.rpc_id(id,snapshot())

func _left(id: int) -> void:
	if not players.has(id):
		return
	if is_host:
		var bag: Dictionary = _items.ensure_bag(id)
		for item: Dictionary in bag.slots + bag.equipment:
			if not item.is_empty():
				_items._spawn_drop(id,item)
		_items.bags.erase(id)
		_items.publish()
	(players[id] as Node).queue_free()
	_items._held.erase(id)
	players.erase(id)
	connected_ids.erase(id)
	control_age.erase(id)

func _server_gone() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	game_started = false
	_settings_visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	show_notice("主机已断开。本轮无主机迁移；关闭窗口后重新加入。")

func _connection_failed() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	game_started = false
	menu.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	show_notice("连接失败 · 检查主机 IP / UDP 24579，可重新尝试")

func _input(event: InputEvent) -> void:
	if not game_started:
		return
	if event.is_action_pressed("ui_cancel"):
		if _journal_visible:
			_journal_visible = false
			journal_panel.hide()
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		_settings_visible = not _settings_visible
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _settings_visible else Input.MOUSE_MODE_CAPTURED
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_J:
		_journal_visible = not _journal_visible
		journal_panel.visible = _journal_visible
		journal_text.text = "已见记录 · J / Esc 关闭\n\n" + "\n\n".join(progress.get("notes",[]))
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _journal_visible else Input.MOUSE_MODE_CAPTURED
		return
	if _settings_visible or _journal_visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_TAB:
		handle_action(multiplayer.get_unique_id(),"toggle_equipment")
	for action: String in ["interact","item_drop","slot_1","slot_2","slot_3","slot_4","item_use"]:
		if event.is_action_pressed(action) and not event.is_echo():
			handle_action(multiplayer.get_unique_id(),action)

func _physics_process(delta: float) -> void:
	if not game_started:
		return
	elapsed += delta
	var local: SpacePlayer3D = players.get(multiplayer.get_unique_id()) as SpacePlayer3D
	if local != null and not test_mode:
		var active: bool = not _settings_visible and not _journal_visible
		var packet: Dictionary = {"move":Input.get_vector("move_left","move_right","move_up","move_down") if active else Vector2.ZERO,"yaw":local._camera_yaw_target,"pitch":local._camera_pitch_target,"jump":active and Input.is_action_pressed("jump"),"sprint":active and Input.is_action_pressed("sprint"),"heat":active and Input.is_action_pressed("item_use"),"rescue":active and Input.is_action_pressed("interact")}
		if is_host:
			accept_controls(1,packet)
		else:
			if embedded:
				get_parent().send_surface_controls(packet)
			else:
				send_controls.rpc_id(1,packet)
	if not is_host:
		return
	var standing: int = 0
	for id: int in players:
		control_age[id] = float(control_age.get(id,0))+delta
		var actor: Node3D = players[id]
		if float(control_age[id]) > 0.5 and not test_mode:
			actor.controls = {}
		actor.simulate(delta)
		if not actor.downed:
			standing += 1
			if actor.controls.get("heat",false):
				apply_heat(id,delta)
			if actor.controls.get("rescue",false):
				rescue(id,delta)
			charge_at_station(id,delta)
	for soft: Node3D in world.creatures:
		soft.tick(delta)
	if world.station03 != null:
		world.station03.tick(self,delta)
	if standing == 0 and not players.is_empty():
		wipe_clock += delta
		if wipe_clock > 2:
			respawn_team()
	else:
		wipe_clock = 0
	tick_threats(delta)
	sync_clock += delta
	if sync_clock >= 0.05:
		sync_clock = 0
		if not multiplayer.get_peers().is_empty():
			if embedded:
				for peer_id: int in multiplayer.get_peers():
					if embedded_ready.has(peer_id):
						get_parent().publish_surface(peer_id,snapshot())
			else:
				sync_world.rpc(snapshot())

func accept_controls(id: int, packet: Dictionary) -> void:
	if not players.has(id):
		return
	var move: Vector2 = packet.get("move",Vector2.ZERO)
	var yaw: float = float(packet.get("yaw",0))
	var pitch: float = float(packet.get("pitch",0))
	if not move.is_finite() or not is_finite(yaw) or not is_finite(pitch):
		return
	players[id].controls = {"move":move.limit_length(),"yaw":wrapf(yaw,-PI,PI),"pitch":clampf(pitch,-1.25,1.25),"jump":bool(packet.get("jump",false)),"sprint":bool(packet.get("sprint",false)),"heat":bool(packet.get("heat",false)),"rescue":bool(packet.get("rescue",false))}
	control_age[id] = 0.0

@rpc("any_peer","call_remote","unreliable_ordered")
func send_controls(packet: Dictionary) -> void:
	if is_host:
		accept_controls(multiplayer.get_remote_sender_id(),packet)

@rpc("any_peer","call_remote","reliable")
func request_frost_action(action: String) -> void:
	if is_host:
		handle_action(multiplayer.get_remote_sender_id(),action)

func handle_action(id: int, action: String) -> void:
	if not is_host:
		if embedded:
			get_parent().send_surface_action(action)
		else:
			request_frost_action.rpc_id(1,action)
		return
	if not players.has(id) or players[id].downed:
		return
	if action == "interact":
		var nearby: Dictionary = _items.nearby_item(id)
		if not nearby.is_empty():
			_items.pickup(id,nearby)
			return
		var entry: Dictionary = nearby_station(id)
		if not entry.is_empty():
			use_station(id,entry)
	elif action in ["item_drop","slot_1","slot_2","slot_3","slot_4","slot_next","slot_previous","toggle_equipment","item_use"]:
		_items.handle_action(id,action)

func nearby_station(id: int) -> Dictionary:
	var actor: SpacePlayer3D = players[id]
	var nearest: Dictionary = {}
	var distance: float = 4.2
	for entry: Dictionary in world.stations:
		var offset: Vector3 = entry.point-(actor.position+Vector3.UP*1.1)
		if absf(offset.y)>2.2 or offset.length()>=distance:
			continue
		if _items.can_reach(actor,entry.point,3.2):
			nearest = entry
			distance = offset.length()
	return nearest

func use_station(id: int, entry: Dictionary) -> void:
	var notes: Array = progress.get("notes",[])
	if entry.kind != "charge" and entry.text not in notes:
		notes.append(entry.text)
		progress.notes = notes
	match entry.kind:
		"board":
			board_requested.emit(id)
		"lab_hatch", "lab_relay", "lab_sample":
			world.station03.interact(self,id,entry)
		"cache":
			var opened: Array = progress.get("opened_caches",[])
			if entry.id in opened:
				tell(id,"运输箱已打开 · 物资留在现场，不会重复补给")
				return
			var cover: int = int(entry.get("cover",-1))
			if cover >= 0 and world.ice[cover].amount < 0.98:
				tell(id,"运输箱仍被封冰包住 · 先用热风机融开")
				return
			opened.append(entry.id)
			progress.opened_caches = opened
			for i: int in entry.rewards.size():
				var point: Vector3 = entry.point+Vector3((i-1)*0.65,0.7,0.45)
				_items.drops.append({"kind":entry.rewards[i],"position":point,"safe_position":point,"uid":"cache_"+entry.id+"_%d"%i,"area":"frost_adventure"})
			_items.publish()
			tell(id,"运输箱已打开 · 可拾取应急物资，队伍共用且不刷新")
			if embedded:
				tell(id,"运输箱已打开 · 归航物资已收入队伍任务匣，进舱后入库；应急物品可在现场拾取")
		"key":
			progress.key = true
			tell(id,"已收好队伍钥匙 · 原路返回科考站保险柜。"+entry.text)
		"evidence":
			progress.evidence = true
			tell(id,entry.text)
		"safe":
			if progress.installed or progress.energy:
				tell(id,"保险柜已经取空 · 能源没有刷新")
			elif progress.key:
				progress.energy = true
				tell(id,"保险柜已打开 · 高密度能源已锁入队伍任务匣，回飞船替换核心。")
			else:
				tell(id,entry.text)
		"core":
			if _items.remove_item(id,"fuel"):
				progress.fuel += 1
				_items.publish()
			if progress.energy and not progress.installed:
				progress.installed = true
				progress.energy = false
				tell(id,"核心已替换 · 再按 E 恢复航行。这只是归航所需的第一份能源。")
			elif progress.installed:
				progress.flight = true
				tell(id,"航行恢复！霜烬星任务完成。能源已装机；返回地球仍需更多能源与物资。")
			else:
				tell(id,entry.text)
		_:
			tell(id,entry.text)

func recharge(id: int) -> bool:
	for item: Dictionary in _items.ensure_bag(id).slots:
		if item.get("kind", "") == "heater" and float(item.get("charge",0)) < 179:
			item.charge = 180.0
			return true
	tell(id,"需要同时携带未满电的热风机")
	return false

func charge_at_station(id: int, delta: float) -> void:
	var actor: Node3D = players[id]
	if not actor.controls.get("rescue",false):
		return
	var entry: Dictionary = nearby_station(id)
	if entry.get("kind", "") != "charge":
		return
	if entry.get("station03_power",false) and not progress.get("station03",{}).get("power_on",false):
		return
	for item: Dictionary in _items.ensure_bag(id).slots:
		if item.get("kind", "") == "heater":
			item.charge = minf(180,float(item.get("charge",0))+delta*18)
	_items.refill_oxygen(id)

func apply_heat(id: int, delta: float) -> void:
	var actor: SpacePlayer3D = players[id]
	var bag: Dictionary = _items.ensure_bag(id)
	var held: Dictionary = _items.selected(id)
	if bag.equipment_active or held.get("kind", "") != "heater" or float(held.get("charge",0)) <= 0:
		return
	held.charge = maxf(0,float(held.charge)-delta)
	var origin: Vector3 = actor.position+Vector3.UP*1.5
	var aim: Vector3 = Basis(Vector3.UP,actor.rotation.y)*Vector3(0,-sin(actor._network_view_pitch),-cos(actor._network_view_pitch))
	# A broad nozzle heats visible nearby surfaces, not only an infinitesimal ray.
	for chunk: Node3D in world.ice:
		if chunk.amount >= 0.98 or chunk.position.distance_squared_to(origin) > 350:
			continue
		var half: Vector3 = (chunk.visual.mesh as BoxMesh).size * 0.5
		var point: Vector3 = origin.clamp(chunk.position-half,chunk.position+half)
		var offset: Vector3 = point-origin
		if offset.length()>7 or offset.length()<0.05 or offset.normalized().dot(aim)<0.85:
			continue
		var sight: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin,point+offset.normalized()*0.06,2)
		var surface: Dictionary = get_world_3d().direct_space_state.intersect_ray(sight)
		if surface.get("collider") == chunk:
			chunk.heat(delta)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin,origin+aim*7,2|1|8)
	query.exclude = [actor.get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var target: Object = hit.collider
	if target in world.creatures:
		target.heat(delta)
	elif target.has_meta("lab_specimen"):
		world.station03.heat(self,delta)
	elif target is SpacePlayer3D:
		target.warmth = minf(2.0,target.warmth+delta*0.2)
	# The top is flat physical support; aiming down while aboard hits the organism.

func _on_pop(soft: Node3D) -> void:
	for actor: Node3D in players.values():
		var offset: Vector3 = actor.position-soft.position
		if Vector2(offset.x,offset.z).length()<3.8 and offset.y > 0.25 and offset.y < 4:
			actor.launch()
	for body: RigidBody3D in _items._prop_bodies.values():
		var offset: Vector3 = body.position-soft.position
		if Vector2(offset.x,offset.z).length()<3.8 and offset.y>-0.1 and offset.y<4:
			body.linear_velocity = Vector3(0,13,-5)
	print("FROST_POP ",soft.name)

func hurt(id: int, damage: int) -> void:
	if not is_host or not players.has(id) or players[id].downed:
		return
	var actor: SpacePlayer3D = players[id]
	actor.health = maxi(0,actor.health-damage)
	actor.downed = actor.health == 0
	if actor.downed:
		actor.stop_jet()
		actor.velocity = Vector3.ZERO

func rescue(id: int, delta: float) -> void:
	for other: int in players:
		if other == id or not players[other].downed:
			continue
		if _items.can_reach(players[id],players[other].position+Vector3.UP,2.8):
			var value: float = float(players[other].get_meta("rescue",0))+delta
			players[other].set_meta("rescue",value)
			if value >= 2:
				players[other].health = 3
				players[other].downed = false
				players[other].set_meta("rescue",0.0)
				print("FROST_RESCUED ",other)

func respawn_team() -> void:
	progress.wipes += 1
	wipe_clock = 0
	for id: int in players:
		var actor: SpacePlayer3D = players[id]
		actor.teleport_to(Vector3((connected_ids.find(id))*1.5,1.2,8))
		actor.health = 5
		actor.downed = false
		actor.set_meta("rescue",0.0)
		actor.impact_speed = 0
		actor.launch_time = 0
		actor.controls = {}
		actor.stop_jet()
	show_notice("全队已回飞船 · 装备与世界进度保留，消耗品未补满")
	print("FROST_WIPE ",progress.wipes)

func snapshot() -> Dictionary:
	var actors: Dictionary = {}
	for id: int in players:
		var actor: SpacePlayer3D = players[id]
		actors[id] = [actor.position,actor.rotation.y,actor.health,actor.downed,actor.warmth,actor.jet_active,actor.velocity]
	var melted: Dictionary = {}
	for i: int in world.ice.size():
		if world.ice[i].amount > 0:
			melted[i] = world.ice[i].amount
	var soft: Array = []
	for organism: Node3D in world.creatures:
		soft.append([organism.charge,organism.cooldown,organism.launches])
	var enemy_states: Array = []
	for threat: Dictionary in threats:
		enemy_states.append([threat.body.position,threat.hp])
	return {"actors":actors,"progress":progress.duplicate(true),"items":_items.snapshot(),"ice":melted,"soft":soft,"enemies":enemy_states}

func campaign_result() -> Dictionary:
	# Read-only handoff contract. No cross-planet progression or save writes here.
	return {"schema_version":1,"planet_id":"frost","navigation_restored":bool(progress.flight),"energy_id":"frost_core_01","energy_state":"installed" if progress.installed else ("secured" if progress.energy else "locked"),"ordinary_fuel_salvaged":int(progress.fuel),"supply_caches":progress.get("opened_caches",[]).duplicate() if embedded else [],"facts":{"deliberate_interference_observed":bool(progress.evidence),"attacker_identified":false}}

@rpc("authority","call_remote","reliable")
func sync_world(state: Dictionary) -> void:
	if is_host:
		return
	apply_frost_state(state)

func apply_frost_state(state: Dictionary) -> void:
	for id: int in state.actors:
		spawn_actor(id,false)
		var actor: SpacePlayer3D = players[id]
		var data: Array = state.actors[id]
		actor.position = data[0]
		actor.rotation.y = data[1]
		actor.health = data[2]
		actor.downed = data[3]
		actor.warmth = data[4]
		actor.jet_active = data[5]
		actor.velocity = data[6]
	if not state.actors.is_empty():
		for id: int in players.keys():
			if not state.actors.has(id):
				_left(id)
	progress = state.progress.duplicate(true)
	_items.apply_state(state.items)
	for index: int in state.ice:
		world.ice[index].apply_amount(state.ice[index])
	for index: int in state.soft.size():
		world.creatures[index].charge = state.soft[index][0]
		world.creatures[index].cooldown = state.soft[index][1]
		world.creatures[index].launches = state.soft[index][2]
	for i: int in state.enemies.size():
		if i >= threats.size():
			create_threat(state.enemies[i][0])
		threats[i].body.position = state.enemies[i][0]
		threats[i].hp = state.enemies[i][1]
		threats[i].body.visible = threats[i].hp > 0

func create_threat(point: Vector3) -> void:
	var body: StaticBody3D = world.box(point,Vector3(1.6,1.3,1.6),Color("a1686e"),false)
	threats.append({"body":body,"hp":3,"clock":0.0,"home":point})

func tick_threats(delta: float) -> void:
	for threat: Dictionary in threats:
		if threat.hp <= 0:
			threat.body.visible = false
			continue
		threat.clock = maxf(0,float(threat.clock)-delta)
		for id: int in players:
			var actor: SpacePlayer3D = players[id]
			var offset: Vector3 = actor.position-threat.body.position
			if actor.downed or absf(offset.y)>2.5 or actor.position.distance_to(threat.home)>14:
				continue
			if offset.length()>2:
				threat.body.position += Vector3(offset.x,0,offset.z).normalized()*delta*2
			elif threat.clock <= 0:
				hurt(id,1)
				threat.clock = 2.5
			break

func attack_from_peer(id: int) -> void:
	for threat: Dictionary in threats:
		if threat.hp>0 and players[id].position.distance_to(threat.body.position)<3.8:
			var now: float = Time.get_ticks_msec()/1000.0
			if now-float(players[id].get_meta("attack_at",-1)) >= 0.35:
				players[id].set_meta("attack_at",now)
				threat.hp -= 1
				players[id].show_attack_animation()

func show_notice(message: String) -> void:
	notice = message
	notice_time = 9
	if confirm_sound != null:
		confirm_sound.play()

func tell(id: int, message: String) -> void:
	if id == multiplayer.get_unique_id():
		show_notice(message)
	elif is_host and id in multiplayer.get_peers():
		remote_notice.rpc_id(id,message)

@rpc("authority","call_remote","reliable")
func remote_notice(message: String) -> void:
	show_notice(message)

func _build_adventure_ui() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 36
	add_child(layer)
	hud_title = Label.new()
	_place_hud(hud_title,Control.PRESET_CENTER_TOP,Vector2(-310,20),Vector2(620,44))
	hud_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(hud_title)
	hud_prompt = Label.new()
	_place_hud(hud_prompt,Control.PRESET_CENTER_BOTTOM,Vector2(-440,-270),Vector2(880,100))
	hud_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(hud_prompt)
	hud_status = Label.new()
	_place_hud(hud_status,Control.PRESET_CENTER_BOTTOM,Vector2(-500,-60),Vector2(1000,45))
	hud_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(hud_status)
	var cross: Label = Label.new()
	cross.text = "·"
	_place_hud(cross,Control.PRESET_CENTER,Vector2(-5,-12),Vector2(10,24))
	layer.add_child(cross)
	for label: Label in [hud_title,hud_prompt,hud_status,cross]:
		label.add_theme_font_size_override("font_size",19)
		label.add_theme_color_override("font_shadow_color",Color.BLACK)
		label.add_theme_constant_override("shadow_offset_x",2)
		label.add_theme_constant_override("shadow_offset_y",2)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu = PanelContainer.new()
	_place_hud(menu,Control.PRESET_CENTER,Vector2(-260,-220),Vector2(520,440))
	layer.add_child(menu)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation",16)
	menu.add_child(stack)
	var title: Label = Label.new()
	title.text = "霜烬星 · 冒险灰盒 0.3\n科考站扩展 / 骨骸遗迹\n单人或局域网 1–4 人"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(title)
	for mode: String in ["单人探索","创建联机主机"]:
		var button: Button = Button.new()
		button.text = mode
		button.pressed.connect(start_session.bind(mode=="创建联机主机"))
		stack.add_child(button)
	address = LineEdit.new()
	address.text = "127.0.0.1"
	address.placeholder_text = "主机局域网 IP"
	stack.add_child(address)
	var join_button: Button = Button.new()
	join_button.text = "加入主机"
	join_button.pressed.connect(func() -> void: start_session(false,address.text.strip_edges()))
	stack.add_child(join_button)
	var help: Label = Label.new()
	help.text = "WASD / 鼠标环视 / Shift 跑 / 空格跳跃与推进\nE 拾取与操作 / 左键使用 / G 放下\nTab 装备栏 / 1、2 选格 / Esc 释放鼠标\n旧预览保留；本入口不写正式存档。"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(help)
	blower = AudioStreamPlayer.new()
	blower.stream = preload("res://assets/audio/oxygen-jet.wav")
	blower.volume_db = -24
	add_child(blower)
	confirm_sound = AudioStreamPlayer.new()
	confirm_sound.stream = preload("res://previews/frost_first_playable/audio/confirm.wav")
	confirm_sound.volume_db = -24
	add_child(confirm_sound)
	journal_panel = PanelContainer.new()
	_place_hud(journal_panel,Control.PRESET_CENTER,Vector2(-460,-290),Vector2(920,580))
	var journal_style: StyleBoxFlat = StyleBoxFlat.new()
	journal_style.bg_color = Color("193646")
	journal_style.content_margin_left = 24
	journal_style.content_margin_right = 24
	journal_style.content_margin_top = 20
	journal_style.content_margin_bottom = 20
	journal_panel.add_theme_stylebox_override("panel",journal_style)
	layer.add_child(journal_panel)
	var scroll: ScrollContainer = ScrollContainer.new()
	journal_panel.add_child(scroll)
	journal_text = Label.new()
	journal_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	journal_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	journal_text.add_theme_font_size_override("font_size",20)
	scroll.add_child(journal_text)
	journal_panel.hide()

func _process(delta: float) -> void:
	notice_time = maxf(0,notice_time-delta)
	if not game_started:
		hud_prompt.text = notice if notice_time>0 else ""
		return
	var id: int = multiplayer.get_unique_id()
	var actor: SpacePlayer3D = players.get(id) as SpacePlayer3D
	if actor == null:
		return
	var location: String = "停机坪" if actor.position.z>-25 else ("露天科考基地" if actor.position.z>-465 else ("肋骨前厅" if actor.position.z>-605 else ("活体栖息厅" if actor.position.z>-755 else "深层遇袭现场")))
	if world.station03 != null:
		var station_location: String = world.station03.location(actor.position)
		if not station_location.is_empty():
			location = station_location
	hud_title.text = location+" · "+("航行已恢复" if progress.flight else ("回飞船替换核心" if progress.energy else ("原路返回保险柜" if progress.key else "寻找高能核心的替代能源")))
	var entry: Dictionary = nearby_station(id)
	var prompt: String = "E 操作" if not entry.is_empty() else _items.item_hint(id)
	for other: int in players:
		if other != id and players[other].downed and actor.position.distance_to(players[other].position)<3:
			prompt = "按住 E 救援 · 2 秒"
	hud_prompt.text = notice if notice_time>0 else prompt
	var held: Dictionary = _items.selected(id)
	hud_status.text = "WASD 移动  空格 跳/推进  E 操作  Tab 栏位  G 放下"
	if held.get("kind", "") == "heater":
		hud_status.text = "热风机 %d%% · 按住左键吹风 · 电池选中后左键更换 · 充电台按住 E" % int(float(held.get("charge",0))/1.8)
	if _settings_visible:
		hud_prompt.text = "Esc 继续 · 联机世界仍在运行"
	var blowing: bool = not _settings_visible and Input.is_action_pressed("item_use") and held.get("kind", "") == "heater" and float(held.get("charge",0))>0 and not actor.downed
	if actor.warmth>1.01:
		hud_status.text += " · 宇航服暖意 %d%%" % int((actor.warmth-1)*100)
	if not is_instance_valid(air) and actor._camera != null:
		air = CPUParticles3D.new()
		air.amount = 30
		air.lifetime = 0.45
		air.direction = Vector3(0,0,-1)
		air.spread = 16
		air.gravity = Vector3(0,0.25,0)
		air.initial_velocity_min = 5
		air.initial_velocity_max = 7
		air.scale_amount_min = 0.04
		air.scale_amount_max = 0.12
		var bead: SphereMesh = SphereMesh.new()
		bead.radius = 0.5
		bead.height = 1
		bead.radial_segments = 6
		bead.rings = 3
		air.mesh = bead
		var vapor: StandardMaterial3D = StandardMaterial3D.new()
		vapor.albedo_color = Color(1,0.75,0.4,0.22)
		vapor.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		vapor.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		air.material_override = vapor
		air.position = Vector3(0.25,-0.25,-0.9)
		actor._camera.add_child(air)
	if is_instance_valid(air):
		air.emitting = blowing and not _journal_visible
	if blowing and not blower.playing:
		blower.play()
	elif not blowing and blower.playing:
		blower.stop()



