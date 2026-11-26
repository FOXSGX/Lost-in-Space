extends SceneTree

var app: Node3D


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	for i in range(30):
		await physics_frame
	var level: LevelBuilder = app.get("level") as LevelBuilder
	var core: CoreRig = level.core
	level.left_cart.set_p(0.55)
	level.right_cart.set_p(0.05)
	core.set_weights(0.55, 0.05)
	for i in range(20):
		for j in range(60):
			await physics_frame
		print("t=%.1f net=%.3f angle=%.3f omega=%.3f locking=%s locked=%s surge=%.2f L=%.2f R=%.2f" % [
			(i + 1), core.get_net(), core.get_angle(), core.get_omega(), str(core.is_locking()), str(core.is_locked()), core.surge_timer, level.left_cart.get_p(), level.right_cart.get_p()])
	quit()
