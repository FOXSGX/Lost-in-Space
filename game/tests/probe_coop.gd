extends SceneTree

## Visual probe for the V2 co-op machinery. Runs the real main scene and takes
## first-person screenshots of every new station, then prints the state that the
## interaction code sees. Used while tuning geometry; not an acceptance test.

var app: Node3D
var player: PlayerController
var level: LevelBuilder
var story: StoryDirector
var hud: GameHud
var session: CoopSession
var out_dir: String = "C:/Users/ASUS/Desktop/迷失太空/work/deepseek-resonance-05-coop-party-v2/evidence/probe"


func _initialize() -> void:
	run.call_deferred()


func frames(n: int) -> void:
	for _i in range(n):
		await physics_frame


func shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])
	print("SHOT ", name)


func clean(objective: String = "") -> void:
	hud.title_layer.visible = false
	hud.clear_subtitles()
	hud.toast_label.visible = false
	hud.hide_alert()
	hud.set_prompt("")
	if objective != "":
		hud.set_objective(objective)


func yaw_to(from: Vector3, to: Vector3) -> float:
	var d: Vector3 = to - from
	return atan2(-d.x, -d.z)


func pitch_to(from: Vector3, to: Vector3) -> float:
	var flat: float = Vector2(to.x - from.x, to.z - from.z).length()
	return -atan2(to.y - (from.y + 1.62), flat)


func tp_look(pos: Vector3, target: Vector3) -> void:
	player.force_exit_operate()
	player.stop_grab()
	player.teleport(pos, yaw_to(pos, target), clampf(pitch_to(pos, target), -1.2, 1.2))
	await frames(10)


func tp(pos: Vector3, yaw: float, pitch: float) -> void:
	player.force_exit_operate()
	player.stop_grab()
	player.teleport(pos, yaw, pitch)
	await frames(10)


func run() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	await frames(90)
	player = app.get("player") as PlayerController
	level = app.get("level") as LevelBuilder
	story = app.get("story") as StoryDirector
	hud = app.get("hud") as GameHud
	session = app.get("session") as CoopSession
	clean()
	story.set_process(false)
	hud.update_crew("P1 七号 ●○○\nP2 队友 ○○○", "你还需要：展开并锁定机械稳定支腿", "全员参与 · 2 人")

	await tp_look(Vector3(0, 4.06, 11.6), Vector3(0, 6.0, -2))
	clean("分头行动：把两侧稳定支腿泵到锁止，同时用配重把核心压进捕获范围")
	await shot("01_hall_overview")

	await tp_look(Vector3(-3.4, 0.06, -1.2), Vector3(-10.5, 3.6, -4.2))
	await shot("02_catwalk_from_hall")
	await tp_look(Vector3(-6.2, 0.06, -2.2), Vector3(-8.6, 3.4, -3.6))
	await shot("03_catwalk_landing")
	level.catwalk.preload_state = 0.0
	level.catwalk.pins_seated = 1
	level.catwalk.tilt = 0.20
	await frames(12)
	await tp_look(Vector3(-5.0, 0.06, -7.2), Vector3(-10.5, 3.6, -4.2))
	await shot("04_catwalk_tilted")
	level.catwalk.tilt = 0.34
	level.catwalk.pins_seated = 0
	await frames(12)
	await tp(Vector3(-12.4, 3.48, -4.2), -PI * 0.5, -0.10)
	await shot("05_standing_on_tilted_catwalk")
	level.catwalk.tilt = 0.0
	level.catwalk.pins_seated = 2
	await frames(10)

	await tp_look(Vector3(4.6, 0.06, -10.6), Vector3(6.0, 1.2, -8.0))
	await shot("06_east_stabilizer_console")
	await tp_look(Vector3(1.2, 0.06, 3.8), Vector3(6.4, 7.2, -6.4))
	await shot("07_east_stabilizer_ram")
	level.stabilizers[1].force_latched()
	await frames(20)
	await shot("08_east_stabilizer_latched")
	await tp_look(Vector3(-0.6, 0.06, -11.6), Vector3(4.4, 7.2, -6.8))
	await shot("09_ram_vs_ring")

	await tp_look(Vector3(-1.6, 0.06, -12.4), Vector3(-5.6, 7.2, -7.2))
	await shot("10_west_stabilizer_ram")
	await tp_look(Vector3(-13.0, 0.06, -2.2), Vector3(-12.0, 1.4, -5.2))
	await shot("11_brake_console")

	await tp_look(Vector3(4.2, 0.06, -2.0), Vector3(6.4, 1.2, -4.4))
	await shot("12_damper")
	await tp_look(Vector3(9.6, 0.06, -5.6), Vector3(10.6, 1.2, -8.6))
	await shot("13_isolation")

	await tp_look(Vector3(3.6, 0.06, 6.8), Vector3(4.6, 2.2, 4.9))
	await shot("14_duty_board")
	await tp_look(Vector3(0, 0.06, 8.0), Vector3(0, 1.2, 8.6))
	await shot("15_lock_console")

	level.set_alarm(true)
	level.catwalk.pins_seated = 0
	level.catwalk.on_surge(1.1)
	await frames(6)
	await tp_look(Vector3(-4.4, 0.06, -7.6), Vector3(-11.0, 3.6, -4.2))
	await shot("16_surge_catwalk")
	level.set_alarm(false)

	print("PROBE states: stab=", level.stabilizers[0].latched, "/", level.stabilizers[1].latched,
		" brake=", level.brake.pressure, " pins=", level.catwalk.pins_seated,
		" damper=", level.damper.pressure)
	print("PROBE done")
	quit()
