extends SceneTree

var preview: Main3D
var player: SpacePlayer3D
var output: String
var checks: Array = []
var path_trace: Array = []
var failed: bool = false
var frame_index: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks.append({"pass":ok,"label":label})
	print("PASS " if ok else "FAIL ", label)
	failed = failed or not ok

func frames(count: int) -> void:
	for i: int in count:
		await physics_frame
		frame_index += 1
		if frame_index % 30 == 0 and player != null:
			path_trace.append({"frame":frame_index,"position":[player.position.x,player.position.y,player.position.z],"jet":player.jet_active})

func mouse_look(yaw: float, pitch: float = 0.0) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.relative = Vector2(-wrapf(yaw-player._camera_yaw_target,-PI,PI)/player.SHIP_LOOK_SENSITIVITY,(pitch-player._camera_pitch_target)/player.SHIP_LOOK_SENSITIVITY)
	Input.parse_input_event(motion)
	await frames(18)

func key(code: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await frames(3)
	event = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = false
	Input.parse_input_event(event)
	await frames(3)

func walk(target: Vector3, max_seconds: float = 25.0) -> bool:
	var start: int = frame_index
	var offset: Vector3 = target-player.position
	await mouse_look(atan2(-offset.x,-offset.z),0)
	Input.action_press("move_up")
	while Vector2(player.position.x-target.x,player.position.z-target.z).length() > 0.45:
		offset = target-player.position
		var motion: InputEventMouseMotion = InputEventMouseMotion.new()
		motion.relative = Vector2(-wrapf(atan2(-offset.x,-offset.z)-player._camera_yaw_target,-PI,PI)/player.SHIP_LOOK_SENSITIVITY,0)
		Input.parse_input_event(motion)
		await frames(5)
		if frame_index-start > int(max_seconds*60):
			Input.action_release("move_up")
			check(false,"route stuck near %s, target %s" % [player.position,target])
			return false
	Input.action_release("move_up")
	return true

func shot(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))

func run() -> void:
	output = ProjectSettings.globalize_path("res://").path_join("../work/gameplay-iterations/20261023-frost-layer1/runtime").simplify_path()
	DirAccess.make_dir_recursive_absolute(output)
	preview = load("res://previews/frost_layer1/preview.tscn").instantiate() as Main3D
	root.add_child(preview)
	await frames(30)
	player = preview.walker
	check(player.health == 5 and preview._health_hud.cells.size() == 5,"5HP and shared five-cell HUD")
	check(player._camera.projection == Camera3D.PROJECTION_PERSPECTIVE and not player._visual.visible,"first person camera and hidden local body")
	await shot("01-start-landmark")
	await key(KEY_ESCAPE)
	var paused_position: Vector3 = player.position
	Input.action_press("move_up")
	await frames(20)
	Input.action_release("move_up")
	check(preview._settings_visible and player.position.distance_to(paused_position)<0.1,"Esc releases pointer and blocks movement")
	await key(KEY_ESCAPE)
	check(not preview._settings_visible and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"Esc resumes first-person control")
	# Verify the landmark has a clear physical sightline from the real spawn.
	var beacon: Vector3 = Vector3(-5,22.3,-3)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(player._camera.global_position,beacon,2)
	check(player.get_world_3d().direct_space_state.intersect_ray(query).is_empty(),"spawn to beacon sightline unobstructed")
	await mouse_look(0.65,-0.2)
	check(absf(player._camera_yaw-0.65)<0.02 and player._camera.rotation.x>0.15,"mouse yaw and pitch input")
	await mouse_look(0)
	var ground: float = player.position.y
	Input.action_press("jump")
	await frames(6)
	Input.action_release("jump")
	await frames(10)
	check(player.position.y>ground+0.5 and not player.jet_active,"short jump through real physics")
	await shot("02-jump")
	await frames(60)
	Input.action_press("jump")
	var jet_frames: int = 0
	var max_height: float = player.position.y
	for i: int in 110:
		await frames(1)
		if player.jet_active:
			jet_frames += 1
		max_height = maxf(max_height,player.position.y)
	Input.action_release("jump")
	await frames(150)
	check(jet_frames>=28 and jet_frames<=32 and max_height>2.0,"shared single bottle jet ~0.5s, actual ascent")
	check(preview._items.tank_oxygen(1)<100.0 and preview._items.jet_reserve(1)>0.99,"landed refill consumes bottle oxygen")
	await key(KEY_TAB)
	check(bool(preview._items.ensure_bag(1).equipment_active),"Tab selects equipment bar")
	await key(KEY_G)
	await frames(90)
	check(not preview._items.has_jet(1) and preview._items.drops.size()==1 and preview._items._prop_bodies.size()==1,"G unmounts into actual visible rigid-body bottle")
	await key(KEY_E)
	check(not bool(preview._items.ensure_bag(1).equipment_active) and preview._items.selected(1).get("kind","")=="oxygen","E picks bottle into hand bar")
	await shot("held-bottle")
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	Input.parse_input_event(click)
	await frames(3)
	click = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = false
	Input.parse_input_event(click)
	await frames(80)
	check(preview._items.has_jet(1) and preview._items.occupied(1)==0,"left click remounts shared oxygen and frees hand slot")
	await key(KEY_TAB)
	if bool(preview._items.ensure_bag(1).equipment_active):
		await key(KEY_TAB)
	await walk(Vector3(0,0,32))
	Input.action_press("move_up")
	await frames(90)
	Input.action_release("move_up")
	check(player.position.z>28.5,"closed door blocks real forward movement")
	await key(KEY_E)
	check(not preview.shortcut_open,"outside cannot open the shortcut")
	Input.action_press("move_up")
	Input.action_press("jump")
	await frames(120)
	Input.action_release("jump")
	Input.action_release("move_up")
	await frames(120)
	check(player.position.z>28.5 and not preview.shortcut_open,"jump and equipped jet cannot bypass the closed gate")
	await shot("03-locked-outside")
	await walk(Vector3(0,0,48))
	var outbound: float = preview.distance_walked
	var outbound_start: float = preview.elapsed
	for index: int in range(1,preview.ROUTE.size()):
		var target: Vector2i = preview.ROUTE[index]
		if index == 4:
			if not await walk(Vector3(-64,0,-17)):
				finish()
				return
			check(player.position.y>0.75,"walked the physical ramp onto lookout")
			await mouse_look(-1.80,-0.25)
			await shot("lookout-window")
		if not await walk(Vector3(target.x*8,0,target.y*8)):
			await shot("failure-stuck")
			finish()
			return
		if index in [3,5,6,7,8,10]:
			if index<preview.ROUTE.size()-1:
				var next: Vector2i = preview.ROUTE[index+1]-target
				await mouse_look(atan2(-next.x,-next.y),0)
			await shot("route-%02d" % index)
	check(preview.entered,"entered the roofed ruin via physical side entrance")
	await mouse_look(0,-0.16)
	await shot("04-ruin")
	var outbound_distance: float = preview.distance_walked-outbound
	var outbound_time: float = preview.elapsed-outbound_start
	var back_start: float = preview.elapsed
	var back_distance: float = preview.distance_walked
	if not await walk(Vector3(1,0,25)):
		finish()
		return
	await mouse_look(-2.35,0.14)
	await key(KEY_E)
	await frames(40)
	check(preview.shortcut_open and preview.gate.collision_layer==0,"inside latch E opens the physical gate")
	await shot("05-open-inside")
	await walk(Vector3(0,0,48))
	check(preview.returned,"returned through open door without teleport")
	check(preview.distance_walked-back_distance<outbound_distance*0.3,"return path materially shorter")
	await mouse_look(0,-0.13)
	await shot("06-returned")
	checks.append({"outbound_distance":outbound_distance,"outbound_seconds":outbound_time,"return_distance":preview.distance_walked-back_distance,"return_seconds":preview.elapsed-back_start})
	finish()

func finish() -> void:
	Input.action_release("move_up")
	var file: FileAccess = FileAccess.open(output.path_join("result.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"trace":path_trace,"events":preview.trace,"elapsed":preview.elapsed,"distance":preview.distance_walked,"failed":failed},"\t"))
	print("FROST_REPLAY_FAILED" if failed else "FROST_REPLAY_PASSED")
	quit(1 if failed else 0)
