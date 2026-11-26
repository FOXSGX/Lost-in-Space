extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func frames(n: int) -> void:
	for _i in range(n):
		await physics_frame

func run() -> void:
	var app: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	await frames(10)
	var player: PlayerController = app.get("player") as PlayerController
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await frames(5)
	print("MOUSE_MODE ", Input.mouse_mode, " yaw_before=", player.yaw)
	var ev: InputEventMouseMotion = InputEventMouseMotion.new()
	ev.relative = Vector2(100.0, 50.0)
	Input.parse_input_event(ev)
	await frames(3)
	print("AFTER_MOUSE yaw=", player.yaw, " pitch=", player.pitch, " expected_yaw=", -0.21)
	var ev2: InputEventMouseMotion = InputEventMouseMotion.new()
	ev2.relative = Vector2(-40.0, -20.0)
	Input.parse_input_event(ev2)
	await frames(3)
	print("AFTER_MOUSE2 yaw=", player.yaw, " pitch=", player.pitch)
	quit()
