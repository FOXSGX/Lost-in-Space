extends SceneTree

var a: Node3D
var failures: int = 0
var output: String = ProjectSettings.globalize_path("res://").path_join("../work/gameplay-iterations/20261025-frost-first-playable/")

func _initialize() -> void:
	call_deferred("run")

func frames(n: int) -> void:
	for i: int in n:
		await physics_frame

func action(key: String, pressed: bool) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = key
	event.pressed = pressed
	Input.parse_input_event(event)

func tap(key: String) -> void:
	action(key,true)
	await frames(2)
	action(key,false)
	await frames(2)

func check(value: bool, label: String) -> void:
	print("PASS " if value else "FAIL ",label)
	if not value:
		failures += 1

func shot(label: String) -> void:
	await frames(8)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output+label+".png")

func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if "--evidence-dir" in args:
		output = args[args.find("--evidence-dir")+1]+"/"
	a = load("res://previews/frost_first_playable/adventure.tscn").instantiate()
	root.add_child(a)
	await shot("ui-menu")
	a.start_session(false)
	await frames(30)
	var p: Node3D = a.players[1]
	var before: Vector3 = p.position
	action("move_up",true)
	await frames(65)
	action("move_up",false)
	check(p.position.z < before.z-4,"engine move_up input moves capsule")
	p.position = Vector3(-4,1,-2.8)
	p.velocity = Vector3.ZERO
	await frames(15)
	await tap("interact")
	check(a._items.count_kind(1,"heater")==1,"engine E picks tool")
	p.position = Vector3(0,1,-14)
	p.velocity = Vector3.ZERO
	p._camera_yaw_target = 0
	p._camera_pitch_target = 0.2
	action("item_use",true)
	await frames(450)
	action("item_use",false)
	var melted: int = 0
	for chunk: Node3D in a.world.ice:
		if chunk.amount>=1:
			melted += 1
	check(melted>0,"engine left-button action melts ice")
	await shot("input-thaw")
	p.position = Vector3(0,1,-30)
	p._camera_pitch_target = -0.08
	await shot("base-vista")
	for entry: Dictionary in a._items.drops:
		if entry.kind == "oxygen":
			p.position = entry.position+Vector3(0,0.4,1.3)
			break
	p.velocity = Vector3.ZERO
	await frames(10)
	print("OXYGEN_NEARBY ",a._items.nearby_item(1))
	await tap("interact")
	check(a._items.selected(1).get("kind", "")=="oxygen","engine E picks oxygen")
	await tap("item_use")
	check(a._items.has_jet(1),"engine use equips shared oxygen system")
	p.position = Vector3(0,1,-40)
	await frames(100)
	action("jump",true)
	var highest: float = 0
	for i: int in 60:
		await physics_frame
		highest = maxf(highest,p.position.y)
	action("jump",false)
	check(highest>2,"hold jump produces shared jet ascent")
	await tap("slot_1")
	p.position = a.world.creatures[0].position+Vector3.UP*1.0
	p.velocity = Vector3.ZERO
	p._camera_pitch_target = 1.25
	p._camera_yaw_target = 0
	await frames(30)
	action("item_use",true)
	await frames(180)
	await shot("organism-inflating")
	await frames(100)
	action("item_use",false)
	check(a.world.creatures[0].launches>0,"engine heat input launches solo passenger")
	for view: Array in [[Vector3(0,1,-465),0.0,-0.2,"fossil-entrance"],[Vector3(-23,4.1,-492),-0.8,-0.1,"rib-hall"],[Vector3(18,8.1,-674),0.5,-0.1,"habitat"],[Vector3(0,12.2,-879),0.0,0.15,"deep-evidence"]]:
		p.position = view[0]
		p.velocity = Vector3.ZERO
		p._camera_yaw_target = view[1]
		p._camera_pitch_target = view[2]
		await shot(view[3])
	print("VISUAL_RESULT failures=",failures," jet_peak=",highest)
	a.queue_free()
	await process_frame
	await process_frame
	quit(failures)

