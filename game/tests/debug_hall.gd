extends SceneTree

## Diagnostic: is the hall shell visible from inside, and is its winding correct?

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
	var level: LevelBuilder = app.get("level") as LevelBuilder
	var player: PlayerController = app.get("player") as PlayerController
	var hud: GameHud = app.get("hud") as GameHud
	hud.title_layer.visible = false
	hud.clear_subtitles()
	var shell: MeshInstance3D = level.get_node_or_null("HallShell") as MeshInstance3D
	print("HALL_SHELL ", shell, " aabb=", shell.get_aabb() if shell != null else "null", " visible=", shell.visible if shell != null else false)
	if shell != null:
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = Color(0.8, 0.35, 0.25)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		shell.material_override = mat
	player.teleport(Vector3(0, 4.06, 12.6), 0.0, 0.0)
	await frames(30)
	var image: Image = root.get_texture().get_image()
	image.save_png("C:/Users/ASUS/Desktop/迷失太空/work/deepseek-resonance-05-core-finale/evidence/dev/debug_shell.png")
	print("SHELL_DEBUG_DONE")
	quit()
