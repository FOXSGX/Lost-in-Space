extends SceneTree

var app: Node
var scene: Node3D
var player: CharacterBody3D
var cart: AnimatableBody3D
var cargo: Node3D
var output: String
var failures: int = 0
var checks: Array[Dictionary] = []
var samples: Array[Dictionary] = []
var captures: Array[Dictionary] = []
var camera_overlaps: int = 0
var sample_clock: int = 0
var mode: String = "m1"

func _initialize() -> void:
	run.call_deferred()

func boot() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	output = args[0]
	if args.size() > 1: mode = args[1]
	DirAccess.make_dir_recursive_absolute(output)
	app = (load("res://resonance_02.tscn") as PackedScene).instantiate()
	root.add_child(app)
	current_scene = app
	await frames(3)
	app.call("start_cart")
	scene = app.get("stage") as Node3D
	player = scene.get("player") as CharacterBody3D
	cart = scene.get("cart") as AnimatableBody3D
	cargo = scene.get("device") as Node3D
	await frames(45)

func frames(count: int) -> void:
	for _i: int in range(count):
		await physics_frame
		sample_clock += 1
		if scene == null or not is_instance_valid(scene): continue
		if sample_clock % 12 == 0:
			var local: Vector3 = cart.to_local(player.global_position)
			var positions: Array = []
			for body: RigidBody3D in cargo.get("cargo") as Array[RigidBody3D]:
				var at: Vector3 = cart.to_local(body.global_position)
				positions.append({"id":body.get("object_id"),"phase":body.get("phase"),"local":[at.x,at.y,at.z],"velocity":body.linear_velocity.length()})
			var overlap: bool = bool(player.call("camera_overlap"))
			if overlap: camera_overlaps += 1
			samples.append({"frame":sample_clock,"distance":cart.get("distance"),"speed":cart.get("speed"),"local":[local.x,local.y,local.z],"floor":player.is_on_floor(),"grip":player.get("grip_id"),"cargo":positions,"camera_overlap":overlap})

func check(ok: bool, text: String, details: Dictionary = {}) -> void:
	checks.append({"ok":ok,"test":text,"details":details})
	print("CART_CHECK_", "OK " if ok else "FAILED ", text, " ", JSON.stringify(details))
	if not ok: failures += 1

func stop() -> void:
	for action: String in ["move_left","move_right","move_up","move_down","sprint"]: Input.action_release(action)

func travel(local_target: Vector3, is_world: bool = false, limit: int = 360) -> bool:
	for _i: int in range(limit):
		var target: Vector3 = local_target if is_world else cart.to_global(local_target)
		var direction: Vector3 = target - player.global_position
		direction.y = 0.0
		if direction.length() < 0.08:
			stop()
			await frames(6)
			return true
		var yaw: float = float(player.get("_camera_yaw"))
		var forward: Vector3 = Vector3(-sin(yaw),0,-cos(yaw))
		var right: Vector3 = Vector3(cos(yaw),0,-sin(yaw))
		var strength: float = clampf(direction.length() / 0.48, 0.56, 1.0)
		var horizontal: float = direction.normalized().dot(right) * strength
		var vertical: float = -direction.normalized().dot(forward) * strength
		stop()
		Input.action_press("move_right" if horizontal > 0 else "move_left",absf(horizontal))
		Input.action_press("move_down" if vertical > 0 else "move_up",absf(vertical))
		await frames(1)
	stop()
	return false

func face(local: Vector3) -> void:
	for _i: int in range(28):
		var direction: Vector3 = cart.to_global(local) - player.global_position
		player.set("_camera_yaw_target", atan2(-direction.x,-direction.z))
		await frames(1)

func press(action: String) -> void:
	Input.action_press(action)
	await frames(2)
	Input.action_release(action)
	await frames(4)

func shot(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))
	captures.append({"name":label,"frame":Engine.get_frames_drawn(),"distance":cart.get("distance")})

func run() -> void:
	await boot()
	check(await travel(Vector3(1,0,1.55)), "从菜单沿真实踏步登车")
	check(player.is_on_floor() and cart.to_local(player.global_position).y > 1.8,"甲板有真实支撑")
	await shot("01_boarded")
	check(await travel(Vector3(2.0,1.91,1.7)),"走到前端控制器")
	await face(Vector3(2.48,2.64,1.08))
	await press("repair")
	check(bool(cart.get("running")),"E 发车")
	var start: Vector3 = cart.to_local(player.global_position)
	await frames(1300)
	var end: Vector3 = cart.to_local(player.global_position)
	check(start.distance_to(end) < 0.20 and player.is_on_floor() and float(cart.get("distance")) > 29.0,"加速、匀速、转弯时静止乘车稳定",{"drift":start.distance_to(end),"start":str(start),"end":str(end),"distance":cart.get("distance"),"platform":str(player.get_platform_velocity())})
	await shot("02_moving")
	check(await travel(Vector3(-0.9,1.91,1.62)),"行驶中横穿甲板")
	await press("cart_brake")
	await frames(140)
	check(float(cart.get("speed")) < 0.001,"B 自然制动至完全停车")
	await shot("03_braked")
	check(await travel(Vector3(2.0,1.91,1.7)),"停车后自由走回控制器")
	await face(Vector3(2.48,2.64,1.08))
	await press("repair")
	check(bool(cart.get("running")),"制动后重新发车")
	await frames(2600)
	check(bool(cart.get("arrived")),"沿轨道转弯起伏并到达终点",{"distance":cart.get("distance"),"speed":cart.get("speed")})
	check(player.is_on_floor() and bool(cart.call("contains_point",player.global_position)),"终点仍站在甲板上")
	await shot("04_arrived")
	check(await travel(Vector3(1,0,1.55)),"对齐终点踏步")
	check(await travel(Vector3(1,0,-2.0)),"停车后沿踏步下车")
	check(cart.to_local(player.global_position).y < 0.5,"终点下车落地")
	await shot("05_offboard")
	await finish()

func finish() -> void:
	stop()
	var data: Dictionary = {"passed":failures==0,"failures":failures,"checks":checks,"samples":samples,"captures":captures,"camera_overlap_samples":camera_overlaps,"events":scene.get("events"),"cargo_events":cargo.get("events"),"evidence":"Real Godot automated inputs; not human playtest"}
	var file: FileAccess = FileAccess.open(output.path_join("moving-cart.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(data,"  "))
	file.close()
	print("MOVING_CART_RESULT ", JSON.stringify({"passed":failures==0,"checks":checks.size(),"failures":failures}))
	scene = null
	current_scene = null
	app.queue_free()
	await frames(4)
	quit(0 if failures == 0 else 1)
