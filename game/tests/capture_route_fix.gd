extends SceneTree

## Evidence shots for the P0 route fix: the left ramp foot and the open lane
## west toward the left counterweight station. These prove the corridor that
## was previously pinched by the ramp railing + innermost west A-frame trestle
## is now a real, walkable lane.

var app: Node3D
var level: LevelBuilder
var cam: Camera3D
var out_dir: String = "C:/Users/ASUS/Desktop/迷失太空/work/deepseek-resonance-04-05-coop-vertical-slice/evidence/route"


func _initialize() -> void:
	run.call_deferred()


func frames(n: int) -> void:
	for _i in range(n):
		await physics_frame


func shot(name: String) -> void:
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png("%s/%s.png" % [out_dir, name])
	print("SHOT ", name)


func look(pos: Vector3, target: Vector3, fov: float = 62.0) -> void:
	cam.global_position = pos
	cam.fov = fov
	cam.look_at(target, Vector3.UP)
	await frames(3)


func run() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	await frames(80)
	level = app.get("level") as LevelBuilder
	var player: PlayerController = app.get("player") as PlayerController
	var story: StoryDirector = app.get("story") as StoryDirector
	var hud: GameHud = app.get("hud") as GameHud
	story.set_process(false)
	story.set_physics_process(false)
	hud.title_layer.visible = false
	hud.clear_subtitles()
	hud.toast_label.visible = false
	hud.set_prompt("")
	hud.set_objective("")
	player.camera.current = false
	cam = Camera3D.new()
	cam.fov = 62.0
	cam.near = 0.03
	cam.far = 260.0
	cam.current = true
	level.add_child(cam)

	# 1. Standing on the ramp deck near its foot, looking west at the lane
	#    that used to be pinched between RampRail and the west trestle.
	await look(Vector3(-5.0, 1.6, 4.4), Vector3(-7.6, 1.0, 2.2), 68.0)
	await shot("ramp_foot_lane")

	# 2. Top-down overview: ramp foot (right) + west track trestles (left).
	await look(Vector3(-4.0, 9.0, 1.0), Vector3(-7.5, 0.5, 2.2), 72.0)
	await shot("ramp_foot_overview")

	# 3. The step-off: bottom of the ramp is open (no railing post at floor),
	#    so the player can walk west onto the hall floor.
	await look(Vector3(-4.8, 1.1, 3.2), Vector3(-5.6, 0.4, 1.6), 70.0)
	await shot("ramp_foot_stepoff")

	# 4. Innermost west trestle pulled further out (foot at x≈-5.5 vs old -5.05).
	await look(Vector3(-6.4, 1.6, 3.4), Vector3(-5.5, 1.2, 1.2), 62.0)
	await shot("west_trestle_foot")

	# 5. The station approach lane at player eye height (the route the bot walks).
	player.teleport(Vector3(-5.0, 0.06, 2.4), 0.0, -0.05)
	await frames(20)
	cam.global_position = player.global_position + Vector3(0, 1.62, 0)
	cam.look_at(Vector3(-8.0, 1.0, 2.2), Vector3.UP)
	await shot("station_approach_eye")
	print("ROUTE_EVIDENCE_DONE")
	quit()