extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func frames(n: int) -> void:
	for _i in range(n):
		await physics_frame

func shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("C:/Users/ASUS/Desktop/迷失太空/work/deepseek-resonance-05-core-finale/evidence/dev/" + name + ".png")

func run() -> void:
	var app: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	await frames(30)
	var player: PlayerController = app.get("player") as PlayerController
	var level: LevelBuilder = app.get("level") as LevelBuilder
	var hud: GameHud = app.get("hud") as GameHud
	hud.title_layer.visible = false
	hud.clear_subtitles()
	level.left_cart.set_p(0.55)
	level.right_cart.set_p(0.05)
	level.core.set_weights(0.55, 0.05)
	await frames(60)
	player.teleport(Vector3(0, 0.06, 11.5), 0.0, -0.40)
	await frames(15)
	hud.clear_subtitles()
	await shot("view_A")
	player.teleport(Vector3(6.5, 0.06, 9.0), 0.62, -0.40)
	await frames(15)
	await shot("view_B")
	player.teleport(Vector3(-6.5, 0.06, 9.0), -0.62, -0.40)
	await frames(15)
	await shot("view_C")
	player.teleport(Vector3(0, 0.06, 8.4), 0.0, -0.55)
	await frames(15)
	await shot("view_D")
	quit()
