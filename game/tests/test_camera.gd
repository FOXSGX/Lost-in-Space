extends SceneTree

## Camera contract test: mouse signs, one event once, pitch clamp, no auto-turn,
## wall proximity, interaction look limits and reset.

var app: Node3D
var player: PlayerController
var level: LevelBuilder
var story: StoryDirector
var camera: Camera3D
var failures: int = 0
var checks: Array[Dictionary] = []


func _initialize() -> void:
	run.call_deferred()


func frames(n: int) -> void:
	for _i in range(n):
		await physics_frame


func check(ok: bool, label: String, details: Dictionary = {}) -> void:
	checks.append({"ok": ok, "label": label, "details": details})
	if not ok:
		failures += 1
	print("CAM ", "OK   " if ok else "FAIL ", label, " ", JSON.stringify(details))


func mouse(dx: float, dy: float) -> void:
	var ev: InputEventMouseMotion = InputEventMouseMotion.new()
	ev.relative = Vector2(dx, dy)
	player._unhandled_input(ev)


func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "res://tests-out"
	DirAccess.make_dir_recursive_absolute(out_dir)
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	await frames(20)
	player = app.get("player") as PlayerController
	level = app.get("level") as LevelBuilder
	story = app.get("story") as StoryDirector
	camera = player.camera
	await frames(10)

	check(camera != null and camera.is_current(), "first-person camera is current")
	check(camera.top_level == false and camera.get_parent() == player, "camera is rigidly attached to body")
	check(absf(camera.position.y - PlayerController.EYE_HEIGHT) < 0.001, "eye height", {"eye": camera.position.y})

	var yaw0: float = player.yaw
	mouse(100.0, 0.0)
	check(absf((player.yaw - yaw0) + 0.21) < 0.002, "mouse right turns right (yaw decreases)", {"dyaw": player.yaw - yaw0})
	var forward: Vector3 = -camera.global_transform.basis.z
	check(forward.x > 0.15, "camera forward points right", {"forward": str(forward)})

	var pitch0: float = player.pitch
	mouse(0.0, -100.0)
	check(player.pitch < pitch0 - 0.19, "mouse up looks up (pitch negative)", {"pitch": player.pitch, "rot_x": camera.rotation.x})
	check(camera.rotation.x > 0.15, "camera x rotation positive is up", {"rot_x": camera.rotation.x})
	mouse(0.0, 100.0)
	check(player.pitch > pitch0 - 0.02, "mouse down looks down", {"pitch": player.pitch, "rot_x": camera.rotation.x})

	var before: float = player.pitch
	mouse(0.0, 100.0)
	var once: float = player.pitch - before
	await frames(3)
	var after_wait: float = player.pitch - before
	check(absf(once - 0.21) < 0.002 and absf(after_wait - once) < 0.0001, "one mouse event is processed once", {"once": once, "after_wait": after_wait})

	mouse(0.0, 10000.0)
	check(player.pitch <= PlayerController.PITCH_MAX + 0.0001 and camera.rotation.x <= -1.31, "pitch clamped down", {"pitch": player.pitch})
	mouse(0.0, -20000.0)
	check(player.pitch >= PlayerController.PITCH_MIN - 0.0001, "pitch clamped up", {"pitch": player.pitch})

	var yaw_before_idle: float = player.yaw
	var pitch_before_idle: float = player.pitch
	await frames(300)
	check(absf(player.yaw - yaw_before_idle) < 0.0001 and absf(player.pitch - pitch_before_idle) < 0.0001, "no auto-turn or drift while standing", {})

	# wall proximity: east hall rock wall at x ~ 15.85
	player.teleport(Vector3(12.4, 0.06, -2.0), -PI * 0.5, 0.0)
	await frames(8)
	var wall_start: Vector3 = player.global_position
	Input.action_press("move_forward")
	await frames(150)
	Input.action_release("move_forward")
	await frames(5)
	var eye: Vector3 = camera.global_position
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var q: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	var sph: SphereShape3D = SphereShape3D.new()
	sph.radius = 0.06
	q.shape = sph
	q.transform = Transform3D(Basis(), eye)
	q.collision_mask = 1
	var hits: Array[Dictionary] = space.intersect_shape(q, 4)
	check(player.global_position.x > wall_start.x + 0.5, "walked toward the visible wall", {"start": str(wall_start), "end": str(player.global_position)})
	check(player.global_position.x < 15.75, "player is stopped before the visible wall", {"x": player.global_position.x})
	check(hits.is_empty(), "eye is not inside the hall wall", {"eye": str(eye), "hits": hits.size()})

	# interaction look limits
	player.teleport(Vector3(-9.025, 1.66, 7.625), -PI * 0.25, 0.15)
	await frames(6)
	level.left_station.interact(player)
	await frames(6)
	check(player.operating, "station interaction enters operate mode")
	check(absf(camera.position.y - PlayerController.EYE_HEIGHT) < 0.001, "eye height unchanged while operating")
	var center: float = player.operate_yaw_center
	mouse(5000.0, 0.0)
	check(absf(wrapf(player.yaw - center, -PI, PI)) <= player.operate_yaw_limit + 0.001, "operating yaw clamps", {"offset": wrapf(player.yaw - center, -PI, PI)})
	player.stop_operating()
	await frames(4)
	check(not player.operating, "exit interaction restores free look")

	# reset camera
	story.checkpoint = 1
	story.reset_to_checkpoint()
	await frames(10)
	check(absf(camera.position.y - PlayerController.EYE_HEIGHT) < 0.001, "reset keeps eye height")
	check(camera.is_current(), "reset keeps camera current")
	var reset_yaw: float = player.yaw
	await frames(60)
	check(absf(player.yaw - reset_yaw) < 0.0001, "no drift after reset")

	var report: Dictionary = {"ok": failures == 0, "failures": failures, "checks": checks}
	var f: FileAccess = FileAccess.open(out_dir + "/camera_report.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("CAMERA_REPORT ", JSON.stringify({"ok": failures == 0, "failures": failures, "checks": checks.size()}))
	quit(0 if failures == 0 else 1)
