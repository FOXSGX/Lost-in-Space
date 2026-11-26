extends SceneTree

var adventure: Node3D
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	print("PASS " if condition else "FAIL ",label)
	if not condition:
		failures += 1

func frames(count: int) -> void:
	for i: int in count:
		await physics_frame

func run() -> void:
	adventure = load("res://previews/frost_first_playable/adventure.tscn").instantiate()
	root.add_child(adventure)
	adventure.test_mode = true
	await frames(20)
	var actor: Node3D = adventure.players[1]
	actor.position = Vector3(0,0.35,-4)
	adventure.accept_controls(1,{"heat":true,"pitch":0})
	await frames(330)
	var gate: Node3D = adventure.world.ice[-1]
	print("GATE_AMOUNT ",gate.amount," layer=",gate.collision_layer)
	check(gate.amount>=0.98 and gate.collision_layer==0,"heat ray melts gate AND removes collision")
	adventure.accept_controls(1,{"move":Vector2(0,-1)})
	await frames(65)
	check(actor.position.z < -8.5,"capsule physically walked through melted gate")
	actor.position = Vector3(0,1.1,-15)
	actor.velocity = Vector3.ZERO
	adventure.accept_controls(1,{"heat":true,"pitch":1.25})
	var highest: float = 0
	for i: int in 300:
		await physics_frame
		highest = maxf(highest,actor.position.y)
	check(adventure.world.creatures[0].launches>0,"solo downward heat triggers organism")
	check(highest>5,"launch produces actual vertical movement")
	adventure.accept_controls(1,{})
	await frames(120)
	check(not actor.downed,"organism landing is survivable")
	# Ordinary non-task surface and real shape shrink.
	actor.position = Vector3(6,0.4,0)
	actor.velocity = Vector3.ZERO
	adventure.accept_controls(1,{"heat":true,"pitch":1.25})
	await frames(170)
	var changed: int = 0
	for ice: Node3D in adventure.world.ice:
		if ice.amount > 0.1:
			changed += 1
	check(changed>=2,"non-task snow also melts")
	if DisplayServer.get_name() != "headless":
		actor.position = Vector3(9,1,2)
		actor._camera_pitch_target = 0.12
		await frames(5)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://").path_join("../work/gameplay-iterations/20261025-frost-first-playable/prototype.png"))
	print("PROTOTYPE_RESULT failures=",failures," highest=",highest)
	quit(failures)


