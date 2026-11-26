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
	await frames(40)
	var player: PlayerController = app.get("player") as PlayerController
	var level: LevelBuilder = app.get("level") as LevelBuilder
	var hud: GameHud = app.get("hud") as GameHud
	hud.title_layer.visible = false
	hud.clear_subtitles()
	player.teleport(Vector3(-9.025, 1.66, 7.625), -PI * 0.25, 0.35)
	await frames(6)
	level.left_station.interact(player)
	await frames(20)
	var hands: FirstPersonHands = player.hands
	print("OPERATING ", player.operating, " state=", hands.state, " visible=", hands.is_visible_in_tree(), " scale=", hands.scale)
	print("ARM L pos=", hands.left_arm.position, " rot=", hands.left_arm.rotation, " visible=", hands.left_arm.is_visible_in_tree())
	print("CAM ", player.camera.global_position, " rot=", player.camera.rotation, " fov=", player.camera.fov)
	for child in hands.left_arm.get_children():
		if child is MeshInstance3D:
			var mi: MeshInstance3D = child as MeshInstance3D
			var gp: Vector3 = mi.global_position
			var sp: Vector2 = player.camera.unproject_position(gp)
			print("  mesh ", mi.name, " local=", mi.position, " global=", gp, " screen=", sp, " layers=", mi.layers, " vis=", mi.is_visible_in_tree())
	await frames(5)
	root.get_texture().get_image().save_png("C:/Users/ASUS/Desktop/迷失太空/work/deepseek-resonance-05-core-finale/evidence/dev/hands_debug.png")
	quit()
