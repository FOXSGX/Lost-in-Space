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
	await frames(20)
	var player: PlayerController = app.get("player") as PlayerController
	var level: LevelBuilder = app.get("level") as LevelBuilder
	var station: LeverStation = level.left_station
	print("STATION root=", station.global_position, " area=", station.area.global_position, " prompt=", station.get_prompt())
	player.teleport(Vector3(-9.025, 1.66, 7.625), -PI * 0.25, -0.45)
	await frames(10)
	print("PLAYER pos=", player.global_position, " eye=", player.get_eye_position(), " yaw=", player.yaw, " pitch=", player.pitch)
	print("TARGET ", player.current_target, " prompt=", player.current_prompt, " dist=", player.get_eye_position().distance_to(station.area.global_position))
	Input.action_press("interact")
	await frames(4)
	Input.action_release("interact")
	await frames(4)
	print("AFTER E operating=", player.operating, " active=", station.active)
	var ev: InputEventMouseMotion = InputEventMouseMotion.new()
	ev.relative = Vector2(-60, 0)
	player._unhandled_input(ev)
	print("AFTER MOUSE yaw=", player.yaw)
	quit()
