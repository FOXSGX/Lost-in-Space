extends SceneTree

var a: Node3D
var p: Node3D
var failures: int = 0
var evidence: String = ""

func _initialize() -> void:
	call_deferred("run")

func frames(count: int) -> void:
	for i: int in count:
		await physics_frame

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:
		failures += 1

func action(key: String, pressed: bool) -> void:
	var input: InputEventAction = InputEventAction.new()
	input.action = key
	input.pressed = pressed
	Input.parse_input_event(input)

func walk(target: Vector3, maximum: int = 900) -> bool:
	a.test_mode = true
	for i: int in maximum:
		var offset: Vector3 = target-p.position
		if Vector2(offset.x,offset.z).length()<0.7:
			a.accept_controls(1,{})
			await frames(5)
			return true
		var yaw: float = atan2(-offset.x,offset.z*-1)
		p._camera_yaw_target = yaw
		a.accept_controls(1,{"move":Vector2(0,-1),"yaw":yaw})
		await physics_frame
	print("CONTENT_BLOCKED target=",target," actual=",p.position)
	return false

func use() -> void:
	a.test_mode = false
	action("interact",true)
	await frames(2)
	action("interact",false)
	await frames(2)
	a.test_mode = true

func cache_count(id: String) -> int:
	var count: int = 0
	for entry: Dictionary in a._items.drops:
		if String(entry.uid).begins_with("cache_"+id+"_"):
			count += 1
	return count

func shot(label: String) -> void:
	if evidence.is_empty() or DisplayServer.get_name()=="headless":
		return
	await frames(8)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(evidence+"/"+label+".png")

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
	# Each fixture starts in its room; the local route and return are actually walked.
	var sled: Dictionary
	for entry: Dictionary in a.world.stations:
		if entry.get("id","")=="rib_sled":
			sled = entry
	check(not sled.is_empty(),"frozen expedition sled exists")
	a.use_station(1,sled)
	check(cache_count("rib_sled")==0,"frozen cache cannot spawn rewards through ice")
	p.position = Vector3(-48,1,-492)
	p.velocity = Vector3.ZERO
	check(await walk(Vector3(-53,0.35,-500)),"reach sled approach outside fossil rib")
	check(await walk(Vector3(-53,0.75,-516)),"walk along sled approach")
	check(await walk(Vector3(-44,0.75,-511)),"walk from entry hall to frozen sled")
	p._camera_yaw_target = 0
	p._camera_pitch_target = 0.15
	await shot("01-frozen-sled")
	a.test_mode = false
	action("item_use",true)
	await frames(560)
	action("item_use",false)
	a.test_mode = true
	check(a.world.ice[sled.cover].amount==1,"normal heater input melts optional cache collision")
	check(await walk(Vector3(-44,0.8,-513.6)),"walk into melted cache approach")
	await use()
	check(cache_count("rib_sled")==3,"interact opens cache and creates three physical supplies")
	a.use_station(1,sled)
	a.spawn_actor(2,false)
	a.use_station(2,sled)
	check(cache_count("rib_sled")==3,"repeated and second-player use cannot duplicate cache")
	await frames(60)
	await use()
	check(a._items.occupied(1)==2 and cache_count("rib_sled")==2,"normal interact picks a settled physical cache supply")
	await shot("02-opened-sled")
	check(await walk(Vector3(-53,0.75,-516)),"reverse sled approach")
	check(await walk(Vector3(-53,0.35,-500)),"reverse sled ramp")
	check(await walk(Vector3(-48,0.35,-492)),"walk back from optional entry cache")
	# Solo heat input, actual collision flight, broad landing, and zero-jet return.
	p.position = Vector3(25,1.05,-702)
	p.velocity = Vector3.ZERO
	p._camera_yaw_target = 0
	p._camera_pitch_target = 1.25
	a.handle_action(1,"slot_1")
	check(a._items.selected(1).get("kind","")=="heater","select heater again after collecting a supply")
	await frames(20)
	a.test_mode = false
	action("item_use",true)
	var launched: bool = false
	var landed: bool = false
	var peak: float = p.position.y
	for i: int in 420:
		await physics_frame
		peak = maxf(peak,p.position.y)
		if a.world.creatures[3].launches>0:
			launched = true
			action("item_use",false)
		if launched and p.is_on_floor() and p.position.y>4.8:
			landed = true
			break
	action("item_use",false)
	a.test_mode = true
	check(launched,"solo real heat input triggers eastern habitat organism")
	check(landed,"solo ejection lands on observation platform")
	print("CONTENT_LANDING position=",p.position," peak=",peak)
	p._camera_pitch_target = 0.12
	check(await walk(Vector3(28,5.2,-715.5)),"walk from landing to observation supplies")
	await use()
	check(cache_count("nest_overlook")==2,"observation cache rewards exploration")
	await frames(60)
	p._camera_yaw_target = 0
	await shot("03-observation-platform")
	p._camera_yaw_target = PI
	p._camera_pitch_target = 0.25
	await shot("08-observation-return")
	check(await walk(Vector3(42,5.2,-710)),"reach return slope from observation platform")
	check(await walk(Vector3(43,5.2,-706.3)),"reach observation slope lip")
	check(await walk(Vector3(43,0.35,-683)),"walk down observation slope without jet")
	check(p.position.y<1,"optional high route rejoins same habitat floor")
	# Deep-side loop, normal interaction, and walking reversal.
	p.position = Vector3(43,1,-818)
	p.velocity = Vector3.ZERO
	check(await walk(Vector3(50,0.35,-821)),"reach incident terrace slope")
	check(await walk(Vector3(50,4.5,-847)),"walk up incident terrace")
	check(await walk(Vector3(49,4.5,-854.5)),"reach deep expedition kit")
	await use()
	check(cache_count("incident_kit")==2,"deep terrace kit opens by normal interaction")
	await frames(60)
	check(await walk(Vector3(44,4.5,-857.5)),"walk to exposed damaged valve")
	await use()
	check(a.progress.get("notes",[]).any(func(note: String) -> bool: return note.begins_with("侧台检验")),"physical evidence can be inspected without a log-collection gate")
	p._camera_yaw_target = 0.6
	p._camera_pitch_target = 0.22
	await shot("04-incident-terrace")
	check(await walk(Vector3(50,4.5,-847)),"reverse incident terrace approach")
	check(await walk(Vector3(50,0.35,-821)),"return from incident terrace without jet")
	a.respawn_team()
	await frames(5)
	a.use_station(1,sled)
	check(cache_count("rib_sled")==2 and a.progress.opened_caches.size()==3,"wipe preserves caches without replenishment")
	for view: Array in [[Vector3(35,1,-191),0.0,0.0,"05-living-quarters"],[Vector3(0,1,-470),0.0,-0.1,"06-entry-hall"],[Vector3(0,1,-620),0.0,-0.12,"07-habitat-view"]]:
		p.position = view[0]
		p.velocity = Vector3.ZERO
		p._camera_yaw_target = view[1]
		p._camera_pitch_target = view[2]
		await shot(view[3])
	print("CONTENT_RESULT failures=",failures)
	a.queue_free()
	await process_frame
	var drain: int = Time.get_ticks_msec()+250
	while Time.get_ticks_msec()<drain:
		await process_frame
	quit(failures)
