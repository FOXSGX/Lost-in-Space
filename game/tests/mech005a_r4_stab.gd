extends SceneTree

## R4：配平后核心能否真正稳定在捕获窗口内？

var app: Node3D
var core: CoreRig
var level: LevelBuilder


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	for _i in range(90):
		await physics_frame
	level = app.get("level") as LevelBuilder
	core = level.core

	print("=== R4 配平后稳定性 ===")
	level.left_station.reset_state(0.5725)
	level.right_station.reset_state(0.4275)
	core.set_weights(0.5725, 0.4275)
	core.angle = 0.0
	core.omega = 0.0
	print("target = %.4f" % (clampf(core.get_net(),-0.95,0.95)*CoreRig.SWING_PER_NET))
	var amin := 9.0
	var amax := -9.0
	for i in range(1200):
		await physics_frame
		if i > 600:
			amin = minf(amin, core.angle)
			amax = maxf(amax, core.angle)
		if i % 200 == 0:
			print("  f%4d angle=%+.4f omega=%+.5f" % [i, core.angle, core.omega])
	print("后 600 帧角度范围 %.4f .. %.4f (幅值 %.4f rad = %.2f°)" % [
		amin, amax, (amax-amin)*0.5, rad_to_deg((amax-amin)*0.5)])
	print()
	print("捕获窗口（双侧可压）约 |angle| <= 0.087")
	print("稳态幅值 %.4f -> %s" % [(amax-amin)*0.5,
		"在窗口内" if (amax-amin)*0.5 <= 0.087 else "超出窗口!"])
	quit(0)
