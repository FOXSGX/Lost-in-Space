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
	player.teleport(Vector3(0, 4.06, 25.6), 0.0, -0.05)
	await frames(6)
	Input.action_press("interact")
	await frames(3)
	Input.action_release("interact")
	await frames(3)
	print("OPERATING ", player.operating)
	Input.action_press("move_forward")
	await frames(240)
	Input.action_release("move_forward")
	await frames(10)
	print("DOOR opened=", level.push_door.is_opened, " progress=", level.push_door.progress, " body=", level.push_door.body.position)
	level.push_door.body.global_position = Vector3(0, 7.0, 24.0)
	print("SETTEST ", level.push_door.body.get_class(), " ", level.push_door.body.position, " global=", level.push_door.body.global_position)
	await frames(3)
	print("SETTEST2 ", level.push_door.body.position, " global=", level.push_door.body.global_position)
	print("PLAYER ", player.global_position)
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	for p in [Vector3(0, 4.9, 24.6), Vector3(0, 5.6, 24.0), Vector3(0, 4.9, 23.5), Vector3(0, 6.5, 24.0)]:
		var q: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
		var sphere: SphereShape3D = SphereShape3D.new()
		sphere.radius = 0.35
		q.shape = sphere
		q.transform = Transform3D(Basis(), p)
		q.collision_mask = 1
		q.collide_with_bodies = true
		var hits: Array[Dictionary] = space.intersect_shape(q, 8)
		var names: Array[String] = []
		for h in hits:
			var c: Object = h.get("collider") as Object
			names.append((c as Node).name if c is Node else str(c))
		print("QUERY ", p, " -> ", names)
	# walk through attempt
	Input.action_press("move_forward")
	await frames(180)
	Input.action_release("move_forward")
	await frames(10)
	print("AFTER_WALK ", player.global_position)
	quit()
