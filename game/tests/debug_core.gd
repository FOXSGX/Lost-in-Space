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
	await frames(60)
	var player: PlayerController = app.get("player") as PlayerController
	var level: LevelBuilder = app.get("level") as LevelBuilder
	var hud: GameHud = app.get("hud") as GameHud
	var story: StoryDirector = app.get("story") as StoryDirector
	hud.title_layer.visible = false
	hud.clear_subtitles()
	story.set_process(false)
	player.teleport(Vector3(0, 0.06, -10.5), PI, -0.55)
	await frames(25)
	await shot("core_close_lit")
	print("CRYSTAL target=", player.current_target, " pos=", player.global_position)
	level.core.core_light.light_energy = 0.0
	level.core.fill_light.light_energy = 0.0
	for light in level.find_children("*", "OmniLight3D", true, false):
		(light as OmniLight3D).light_energy = 0.0
	for light in level.find_children("*", "SpotLight3D", true, false):
		(light as SpotLight3D).light_energy = 0.0
	var we: WorldEnvironment = level.get_node("WorldEnvironment") as WorldEnvironment
	we.environment.glow_enabled = false
	await frames(10)
	await shot("core_close_nolight")
	level.core.crystal_material.set_shader_parameter("emission_energy", 0.0)
	await frames(10)
	await shot("core_close_noemission")
	# identify which mesh is the bright shape
	var outer: MeshInstance3D = level.core.crystal_pivot.get_node_or_null("CoreCrystal") as MeshInstance3D
	var inner: MeshInstance3D = level.core.crystal_pivot.get_node_or_null("InnerCrystal") as MeshInstance3D
	print("OUTER ", outer, " INNER ", inner)
	if outer != null:
		var red: StandardMaterial3D = StandardMaterial3D.new()
		red.albedo_color = Color(1, 0.1, 0.1)
		red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		red.cull_mode = BaseMaterial3D.CULL_DISABLED
		outer.material_override = red
	if inner != null:
		inner.visible = false
	await frames(10)
	await shot("core_close_redouter")
	print("DONE")
	quit()
