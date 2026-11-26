extends SceneTree

# Room placement is a fixture; each local approach, door and return is walked.
# Thawing and device use go through the same input actions as normal play.
var a: Node3D
var p: Node3D
var failures: int = 0
var checks: int = 0
var evidence: String = ""

func _initialize() -> void:
	call_deferred("run")

func frames(count: int) -> void:
	for i: int in count:
		await physics_frame

func check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ",label)
	if not ok:
		failures += 1

func action(key: String, pressed: bool) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = key
	event.pressed = pressed
	Input.parse_input_event(event)

func use() -> void:
	a.accept_controls(1,{})
	a.test_mode = false
	action("interact",true)
	await frames(2)
	action("interact",false)
	await frames(3)
	a.test_mode = true

func walk(target: Vector3, maximum: int = 1000) -> bool:
	a.test_mode = true
	for i: int in maximum:
		var offset: Vector3 = target-p.position
		if Vector2(offset.x,offset.z).length()<0.65:
			a.accept_controls(1,{})
			await frames(5)
			return true
		var yaw: float = atan2(-offset.x,-offset.z)
		p._camera_yaw_target = yaw
		a.accept_controls(1,{"move":Vector2(0,-1),"yaw":yaw})
		await physics_frame
	a.accept_controls(1,{})
	print("STATION03_BLOCKED target=",target," actual=",p.position)
	return false

func find_station(kind: String, id: String = "") -> Dictionary:
	for entry: Dictionary in a.world.stations:
		if entry.kind==kind and (id.is_empty() or entry.get("id","")==id):
			return entry
	return {}

func state() -> Dictionary:
	return a.progress.get("station03",{})

func total_stock() -> int:
	var count: int = a._items.drops.size()
	for bag: Dictionary in a._items.bags.values():
		for item: Dictionary in bag.slots+bag.equipment:
			if not item.is_empty():
				count += 1
	return count

func aim_at(point: Vector3) -> void:
	var offset: Vector3 = point-(p.position+Vector3.UP*1.5)
	p._camera_yaw_target = atan2(-offset.x,-offset.z)
	p._camera_pitch_target = clampf(atan2(-offset.y,Vector2(offset.x,offset.z).length()),-1.2,1.2)

func thaw(entry: Dictionary, label: String) -> void:
	var cover: int = int(entry.get("cover",-1))
	check(cover>=0 and cover<a.world.ice.size(),label+" has a real meltable cover")
	if cover<0 or cover>=a.world.ice.size():
		return
	var chunk: Node3D = a.world.ice[cover]
	a.test_mode = false
	action("slot_1",true)
	action("slot_1",false)
	await frames(3)
	check(a._items.selected(1).get("kind","")=="heater",label+" selects the carried heater")
	action("item_use",true)
	for i: int in 720:
		aim_at(chunk.position)
		await physics_frame
		if chunk.amount>=0.98:
			break
	action("item_use",false)
	await frames(3)
	a.test_mode = true
	print("STATION03_THAW ",label," amount=",chunk.amount," position=",chunk.position," actor=",p.position," charge=",a._items.ensure_bag(1).slots[0].get("charge",0))
	check(chunk.amount==1.0 and chunk.collision_layer==0,label+" normal heat removes the real collision")

func shot(label: String) -> void:
	if evidence.is_empty() or DisplayServer.get_name()=="headless":
		return
	await frames(8)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(evidence+"/"+label+".png")

func open_cache(entry: Dictionary, label: String) -> void:
	check(not entry.is_empty(),label+" exists")
	if entry.is_empty():
		return
	if int(entry.get("cover",-1))>=0:
		await thaw(entry,label)
	var before: int = total_stock()
	await use()
	check(entry.id in a.progress.get("opened_caches",[]),label+" opens through normal E")
	check(total_stock()==before+entry.rewards.size(),label+" creates exactly its physical reward stock")
	var after: int = total_stock()
	for i: int in 5:
		await use()
	check(total_stock()==after,label+" repeated E preserves stock including pickups")

func finish() -> void:
	action("item_use",false)
	action("interact",false)
	print("STATION03_RESULT failures=",failures," checks=",checks)
	if is_instance_valid(a):
		a.queue_free()
	await process_frame
	var drain: int = Time.get_ticks_msec()+250
	while Time.get_ticks_msec()<drain:
		await process_frame
	quit(failures)

func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if "--evidence-dir" in args:
		evidence = args[args.find("--evidence-dir")+1]
	a = load("res://previews/frost_first_playable/adventure.tscn").instantiate()
	root.add_child(a)
	a.start_session(false)
	a.test_mode = true
	p = a.players[1]
	a._items.add_item(1,"heater",-1,{"charge":180.0},true)
	await frames(20)
	var hatch: Dictionary = find_station("lab_hatch")
	var relay: Dictionary = find_station("lab_relay")
	var sample: Dictionary = find_station("lab_sample")
	check(a.world.get("station03")!=null,"station expansion is attached to the live world")
	check(not hatch.is_empty() and not relay.is_empty() and not sample.is_empty(),"station expansion exposes its three physical devices")
	if hatch.is_empty() or relay.is_empty() or sample.is_empty():
		await finish()
		return
	check(not bool(state().get("hatch_open",false)) and not bool(state().get("power_on",false)) and not bool(state().get("sample_read",false)),"new optional station states begin incomplete")
	# One entry fixture; no teleports between any of the station activities.
	p.position = Vector3(-36,1,-318)
	p.velocity = Vector3.ZERO
	await frames(15)
	check(await walk(Vector3(-42,0.3,-326)),"walk from courtyard through original station entrance")
	check(await walk(Vector3(-48,0.3,-326)),"walk into the sample preparation bay")
	check(await walk(Vector3(-48,0.3,-328.1)),"approach frozen sample without crossing furniture")
	await use()
	check(not bool(state().get("sample_read",false)),"unpowered frozen sample cannot complete out of order")
	aim_at(Vector3(-48,1.5,-331))
	await shot("01-unpowered-sample")
	check(await walk(Vector3(-42,0.3,-326)),"leave the preparation bay by the same aisle")
	check(await walk(Vector3(-42,0.3,-324)),"reach the clear front edge of the reception desk")
	check(await walk(Vector3(-22.6,0.3,-324)),"cross in front of the reception desk")
	check(await walk(Vector3(-22.6,0.3,-335)),"reach the frozen annex service door")
	await use()
	check(not bool(state().get("hatch_open",false)),"E cannot open the annex through unmelted door ice")
	var crossed_frozen: bool = await walk(Vector3(-17,0.3,-335),110)
	check(not crossed_frozen and p.position.x< -20,"frozen annex physically blocks walking through")
	check(not bool(state().get("power_on",false)),"blocked annex approach does not remotely restore power")
	check(await walk(Vector3(-22.6,0.3,-335)),"step back from the blocked service door")
	aim_at(Vector3(-20,2,-335))
	await shot("02-frozen-service-door")
	await thaw(hatch,"annex door")
	await use()
	await frames(25)
	check(bool(state().get("hatch_open",false)),"normal E opens the thawed metal service door")
	check(await walk(Vector3(-17,0.3,-335)),"walk through the opened metal door")
	check(await walk(Vector3(-10,0.3,-337.4)),"walk to the annex power relay")
	await use()
	check(bool(state().get("power_on",false)),"normal relay E restores optional station power")
	await use()
	check(bool(state().get("power_on",false)),"relay is a one-way repair and cannot toggle power off")
	var powered_charge: Dictionary
	for entry: Dictionary in a.world.stations:
		if entry.kind=="charge" and bool(entry.get("station03_power",false)):
			powered_charge = entry
	check(not powered_charge.is_empty(),"restored power exposes a marked annex charger")
	if not powered_charge.is_empty():
		check(await walk(Vector3(-3,0.3,-337.4)),"walk to the newly powered charging bench")
		a._items.ensure_bag(1).slots[0].charge = 0.0
		a.test_mode = false
		action("interact",true)
		await frames(180)
		action("interact",false)
		await frames(3)
		a.test_mode = true
		check(float(a._items.ensure_bag(1).slots[0].get("charge",0))>20,"holding normal E recharges an empty heater at restored bench")
	aim_at(Vector3(-10,2,-342))
	await shot("03-annex-power-restored")
	check(await walk(Vector3(-13,0.3,-335)),"walk across annex to the spare-parts side")
	check(await walk(Vector3(-13,0.3,-329.8)),"walk around the spare-parts crate")
	check(await walk(Vector3(-9,0.3,-329.8)),"reach the annex spare-parts cache")
	await open_cache(find_station("cache","station_spares"),"annex spare-parts cache")
	check(await walk(Vector3(-13,0.3,-329.8)),"reverse the annex cache approach")
	check(await walk(Vector3(-13,0.3,-335)),"rejoin the annex doorway aisle")
	check(await walk(Vector3(-22.6,0.3,-335)),"return through the same opened annex door")
	check(await walk(Vector3(-22.6,0.3,-324)),"return to the main station front aisle")
	check(await walk(Vector3(-42,0.3,-324)),"walk back across the clear front of reception")
	check(await walk(Vector3(-42,0.3,-326)),"rejoin the western preparation bay aisle")
	check(await walk(Vector3(-48,0.3,-328.1)),"revisit sample after power repair")
	await use()
	check(not bool(state().get("sample_read",false)),"restored power alone does not bypass sample cover ice")
	await thaw(sample,"sample cabinet")
	await use()
	check(bool(state().get("sample_read",false)),"thawing then normal E reads the powered specimen result")
	var sample_notes: int = a.progress.get("notes",[]).size()
	await use()
	check(a.progress.get("notes",[]).size()==sample_notes,"repeat sample inspection does not duplicate journal entries")
	var cold_heat: float = float(state().get("sample_heat",0))
	aim_at(Vector3(-48,1.5,-331.8))
	a.test_mode = false
	action("item_use",true)
	await frames(75)
	action("item_use",false)
	await frames(3)
	a.test_mode = true
	var warmed_heat: float = float(state().get("sample_heat",0))
	var warmed_height: float = a.world.station03.sample.scale.y
	check(warmed_heat>cold_heat+0.2 and warmed_height>1.2,"normal heat input makes the exposed specimen visibly swell")
	await shot("06-warm-specimen")
	await frames(150)
	check(float(state().get("sample_heat",0))<warmed_heat-0.1 and a.world.station03.sample.scale.y<warmed_height,"released heater lets specimen cool and shrink")
	aim_at(Vector3(-48,1.5,-331))
	await shot("04-sample-analysis")
	check(await walk(Vector3(-48,0.3,-326)),"walk back from the specimen table")
	check(await walk(Vector3(-42,0.3,-326)),"rejoin the western main aisle outside specimen furniture")
	check(await walk(Vector3(-42,0.3,-347)),"walk down the preserved western main aisle")
	check(await walk(Vector3(-45.2,0.3,-347)),"walk around the sample return racks")
	check(await walk(Vector3(-45.2,0.3,-350.1)),"reach medical station cache beside the rear wall")
	await open_cache(find_station("cache","station_medical"),"station medical cache")
	check(await walk(Vector3(-42,0.3,-347)),"rejoin original insurance-safe approach aisle")
	check(await walk(Vector3(-42,0.3,-326)),"walk the full original western aisle without jet")
	check(await walk(Vector3(-42,0.3,-324)),"reach the front edge of the reception desk again")
	check(await walk(Vector3(-22.6,0.3,-324)),"walk to the observation platform approach")
	check(await walk(Vector3(-22.6,0.3,-339.5)),"reach observation ramp foot without jet")
	check(await walk(Vector3(-22.6,3.2,-352.2)),"walk up observation ramp without jet")
	check(await walk(Vector3(-27,3.2,-352.4)),"walk across upper observation connector")
	check(await walk(Vector3(-27,3.2,-349)),"walk onto the upper observation platform")
	check(p.position.y>2.9,"observation route reaches real elevated collision")
	p._camera_yaw_target = PI
	p._camera_pitch_target = 0.12
	await shot("05-observation-platform")
	check(await walk(Vector3(-27,3.2,-352.4)),"reverse upper observation platform approach")
	check(await walk(Vector3(-22.6,3.2,-352.2)),"reverse upper observation connector")
	check(await walk(Vector3(-22.6,0.3,-339.5)),"walk down the same ramp without jet")
	check(p.position.y<0.8,"observation ramp returns to original station floor")
	check(p.health==5 and not p.downed,"ordinary local routes preserve health")
	check(not bool(a.progress.key) and not bool(a.progress.energy) and not bool(a.progress.flight),"optional station activities do not grant or advance mainline key energy or flight")
	var stock_before_wipe: int = total_stock()
	var opened_before_wipe: Array = a.progress.get("opened_caches",[]).duplicate()
	a.hurt(1,5)
	await frames(190)
	check(a.progress.wipes==1 and not p.downed,"solo downed state recovers through actual team-wipe timer")
	check(bool(state().get("hatch_open",false)) and bool(state().get("power_on",false)) and bool(state().get("sample_read",false)),"wipe retains door power and analyzed specimen progress")
	check(total_stock()==stock_before_wipe and a.progress.get("opened_caches",[])==opened_before_wipe,"wipe neither refreshes station rewards nor loses held stock")
	check(a.world.ice[int(hatch.cover)].amount==1 and a.world.ice[int(sample.cover)].amount==1,"wipe preserves physically melted door and specimen covers")
	await finish()
