extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func frames(n: int) -> void:
	for _i in range(n):
		await physics_frame

func report(tag: String, player: PlayerController) -> void:
	print(tag, " pos=", player.global_position, " on_floor=", player.is_on_floor(), " vel=", player.velocity, " floor_normal=", player.get_floor_normal())
	for i in range(player.get_slide_collision_count()):
		var c: KinematicCollision3D = player.get_slide_collision(i)
		var collider: Object = c.get_collider()
		print("   collision ", i, " with ", (collider as Node).name if collider is Node else str(collider), " normal=", c.get_normal(), " pos=", c.get_position())

func run() -> void:
	var app: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	await frames(20)
	var player: PlayerController = app.get("player") as PlayerController
	# descending left ramp
	player.teleport(Vector3(-5.0, 4.12, 10.6), 0.0, 0.0)
	await frames(5)
	report("RAMP_TOP", player)
	Input.action_press("move_forward")
	for i in range(8):
		await frames(30)
		report("DOWN_%d" % i, player)
	Input.action_release("move_forward")
	await frames(5)
	# ascending from floor
	player.teleport(Vector3(-5.0, 0.12, 2.2), PI, 0.0)
	await frames(5)
	report("RAMP_BOTTOM", player)
	Input.action_press("move_forward")
	for i in range(6):
		await frames(30)
		report("UP_%d" % i, player)
	Input.action_release("move_forward")
	# right station ramp bottom approach
	player.teleport(Vector3(8.0, 0.12, 11.4), 0.0, 0.0)
	await frames(5)
	report("ST_RAMP_APPROACH", player)
	Input.action_press("move_forward")
	for i in range(6):
		await frames(30)
		report("ST_UP_%d" % i, player)
	Input.action_release("move_forward")
	quit()
