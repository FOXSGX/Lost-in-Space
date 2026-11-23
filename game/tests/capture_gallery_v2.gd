extends SceneTree

## V2 screenshot gallery: every frame is the real first-person camera looking at
## the new co-op machinery. Output: evidence/gallery_v2.

var app: Node3D
var player: PlayerController
var level: LevelBuilder
var story: StoryDirector
var hud: GameHud
var out_dir: String = "C:/Users/ASUS/Desktop/迷失太空/work/deepseek-resonance-05-coop-party-v2/evidence/gallery_v2"


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
	hud.toast_label.modulate.a = 0.0
	hud.set_prompt("")
	if objective != "":
		hud.set_objective(objective)


func look_at_from(pos: Vector3, target: Vector3, pitch_bias: float = 0.0) -> void:
	player.force_exit_operate()
	player.stop_grab()
	var d: Vector3 = target - pos
	var yaw: float = atan2(-d.x, -d.z)
	var flat: float = Vector2(d.x, d.z).length()
	var pitch: float = -atan2(target.y - (pos.y + 1.62), flat) + pitch_bias
	player.teleport(pos, yaw, clampf(pitch, -1.1, 1.1))
	await frames(14)


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

	# 1. wide hall from the observation balcony
	clean("R-05 地心共振大厅")
	await look_at_from(Vector3(0, 4.06, 16.5), Vector3(0, 1.6, 0), 0.02)
	await shot("01_hall_overview")

	# 2. west stabiliser leg (retracted)
	var stab_w: StabilizerRig = level.stabilizers[0]
	clean("西侧机械稳定支腿")
	await look_at_from(stab_w.global_position + Vector3(3.6, 2.1, 6.0), stab_w.global_position + Vector3(0, 1.5, 0), -0.02)
	await shot("02_stabilizer_west")

	# 3. east stabiliser leg, latched
	var stab_e: StabilizerRig = level.stabilizers[1]
	stab_e.latched = true
	stab_e.extension = StabilizerRig.STROKE
	level.core.set_stabilizer_latched(1, true)
	await frames(30)
	clean("东侧支腿已锁定（捕获范围放宽）")
	await look_at_from(stab_e.global_position + Vector3(-3.6, 2.1, 6.0), stab_e.global_position + Vector3(0, 1.5, 0), -0.02)
	await shot("03_stabilizer_east_latched")

	# 4. emergency brake with one pump charged
	level.brake.pressure = 0.62
	await frames(20)
	clean("应急共振制动 · 蓄压 62%")
	await look_at_from(level.brake.global_position + Vector3(3.2, 2.0, 5.4), level.brake.global_position + Vector3(0, 1.3, 0), -0.02)
	await shot("04_emergency_brake")

	# 5. maintenance catwalk with a popped pin
	level.catwalk.pins_seated = 1
	level.catwalk.tilt = 0.09
	await frames(20)
	clean("维修栈桥 · 安全销被震脱")
	await look_at_from(Vector3(-10.6, 3.52, -1.4), Vector3(-12.4, 4.1, -4.2), -0.05)
	await shot("05_catwalk_pin")

	# 6. catwalk grab point + winch station
	clean("栈桥抓扶横杆与救援卷扬机")
	await look_at_from(Vector3(-12.6, 3.52, -1.9), Vector3(-14.0, 4.0, -4.0), -0.02)
	await shot("06_catwalk_grab")

	# 7. extraction damper (loaded)
	level.damper.pressure = 0.96
	level.damper.latched_flag = true
	await frames(40)
	clean("采掘回路阻尼器 · 已加载")
	await look_at_from(level.damper.global_position + Vector3(0.8, 2.0, 4.8), level.damper.global_position + Vector3(0, 1.3, 0), -0.02)
	await shot("07_extraction_damper")

	# 8. isolation bed, pin pulled, carriage partly pushed
	level.core.stabilizer_states = [true, true]
	level.isolation.pin_out = true
	level.isolation.pin_anim = 1.0
	level.isolation.progress = 0.45
	await frames(20)
	clean("采掘联轴器 · 滑架推进 45%")
	await look_at_from(Vector3(10.7, 1.7, -5.3), Vector3(10.5, 1.3, -8.7), -0.05)
	await shot("08_isolation_carriage")

	# 9. crew duty board
	clean("全员参与 · 职责看板")
	await look_at_from(Vector3(7.0, 1.70, 8.3), level.duty_board.global_position + Vector3(0, 2.35, 0), 0.0)
	await shot("09_duty_board")

	# 10. core with widened capture range and lit claws
	level.core.stabilizer_states = [true, true]
	await frames(60)
	clean("核心 · 双支腿锁定后的捕获范围")
	await look_at_from(Vector3(0, 1.7, -6.2), Vector3(0, 2.4, 0), 0.03)
	await shot("10_core_capture")

	print("GALLERY_DONE")
	quit(0)
