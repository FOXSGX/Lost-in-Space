extends SceneTree

## Checkpoint / reset contract. Each checkpoint must restore the mechanical
## state it represents, and the player must be able to finish again from it.

var app: Node3D
var player: PlayerController
var level: LevelBuilder
var story: StoryDirector
var failures: int = 0
var checks: Array[Dictionary] = []


func _initialize() -> void:
	run.call_deferred()


func frames(n: int) -> void:
	for _i in range(n):
		await physics_frame


func check(ok: bool, label: String, details: Dictionary = {}) -> void:
	checks.append({"ok": ok, "label": label, "details": details})
	if not ok:
		failures += 1
	print("RESET ", "OK   " if ok else "FAIL ", label, " ", JSON.stringify(details))


func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "res://tests-out"
	DirAccess.make_dir_recursive_absolute(out_dir)
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	await frames(20)
	player = app.get("player") as PlayerController
	level = app.get("level") as LevelBuilder
	story = app.get("story") as StoryDirector
	var hud: GameHud = app.get("hud") as GameHud
	hud.title_layer.visible = false

	# checkpoint 1
	player.teleport(Vector3(0, 4.06, 12.6), 0.0, -0.1)
	await frames(20)
	check(story.checkpoint == 1, "hall checkpoint reached", {"cp": story.checkpoint})

	# checkpoint 2: lock the core with balanced weights
	level.left_cart.set_p(0.58)
	level.right_cart.set_p(0.02)
	level.core.set_weights(0.58, 0.02)
	# V2 interlock: the claw hydraulics only press once both stabiliser legs are
	# latched. This test verifies checkpoint/reset, not the leg pump itself.
	for i in range(level.stabilizers.size()):
		level.stabilizers[i].latched = true
		level.core.set_stabilizer_latched(i, true)
	await frames(10)
	await frames(60)
	player.teleport(Vector3(0, 0.06, 9.1), 0.0, 0.0)
	await frames(8)
	level.lock_rig.interact(player)
	await frames(160)
	check(level.core.is_locked(), "core locked for checkpoint 2")
	check(story.checkpoint == 2, "lock checkpoint set", {"cp": story.checkpoint})
	var snap_l: float = level.left_cart.get_p()
	var snap_r: float = level.right_cart.get_p()

	story.reset_to_checkpoint()
	await frames(40)
	check(story.checkpoint == 2, "reset kept checkpoint 2")
	check(player.global_position.distance_to(Vector3(0, 0.06, 8.4)) < 0.6, "reset respawn at console", {"pos": str(player.global_position)})
	check(level.core.is_locked(), "reset restored locked core")
	check(absf(level.left_cart.get_p() - snap_l) < 0.02 and absf(level.right_cart.get_p() - snap_r) < 0.02, "reset restored weight snapshot", {"L": level.left_cart.get_p(), "R": level.right_cart.get_p()})
	check(level.push_door.is_opened, "reset restored entrance door open")
	check(not level.isolation.separated_flag and not level.data_plinth.revealed_flag, "reset cleared isolation/data")
	check(not player.operating, "reset leaves operating mode")

	# checkpoint 3: isolation by direct mechanism trigger
	level.isolation.force_separated_state()
	level.isolation.separated.emit()
	await frames(160)
	check(story.checkpoint == 3, "isolation checkpoint set", {"cp": story.checkpoint})
	check(level.isolation.separated_flag, "isolation separated")
	check(level.data_plinth.revealed_flag, "data revealed")

	story.reset_to_checkpoint()
	await frames(40)
	check(story.checkpoint == 3, "reset kept checkpoint 3")
	check(level.isolation.separated_flag, "reset restored isolation")
	check(level.data_plinth.revealed_flag, "reset restored data reveal")
	check(not level.exit_door.should_open, "reset kept exit locked")
	check(not story.data_taken, "reset cleared taken data")

	# take data, then reset again
	player.teleport(Vector3(-3.0, 0.06, -8.3), 0.0, 0.0)
	await frames(10)
	level.data_plinth.interact(player)
	await frames(30)
	check(story.data_taken, "data can be taken after reset")
	check(level.exit_door.should_open, "exit opens after data")
	story.reset_to_checkpoint()
	await frames(40)
	check(not story.data_taken and not level.exit_door.should_open, "reset returns to pre-data state")
	check(level.data_plinth.revealed_flag, "data remains available for a retry")

	# retry must still work (no soft lock)
	player.teleport(Vector3(-3.0, 0.06, -8.3), 0.0, 0.0)
	await frames(10)
	level.data_plinth.interact(player)
	await frames(30)
	check(story.data_taken, "retry after reset succeeds")
	check(level.exit_door.should_open, "exit unlocks on retry")

	var report: Dictionary = {"ok": failures == 0, "failures": failures, "checks": checks, "checkpoint": story.checkpoint}
	var f: FileAccess = FileAccess.open(out_dir + "/reset_report.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("RESET_REPORT ", JSON.stringify({"ok": failures == 0, "failures": failures, "checks": checks.size()}))
	quit(0 if failures == 0 else 1)
