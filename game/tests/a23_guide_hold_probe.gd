extends SceneTree

# -----------------------------------------------------------------------------
# ACT23-MP-REPAIR-LOCK-RELAUNCH-R1 · receiver hand-wheel release probe.
#
# Root-cause isolation for the re-board blocker reported by acc-3p-01:
# a player who takes the authored co-op hand wheel in the repair yard and then
# presses E again to let go stays input-locked, so they can never walk away
# from the bay and can never re-board the cart.
#
# Everything is driven by the same real inputs a player uses (WASD, E, W,
# Space). Nothing writes rig or rail state: the guide refuses to engage while
# the section is jammed and outside the jaw window, so the probe does the real
# cable + drum + brake work first, exactly like a player would.
#
# Run: Godot --headless --fixed-fps 60 --path <proj> res://act23/resonance_02.tscn \
#        -s res://tests/a23_guide_hold_probe.gd -- <out_dir>
# -----------------------------------------------------------------------------

var app: Node
var scene: Node3D
var cart: AnimatableBody3D
var yard: Node3D
var rig: Node3D
var flow: Node
var player: CharacterBody3D
var output: String
var failures: int = 0
var checks: Array[Dictionary] = []
var clock: int = 0

func _initialize() -> void:
	run.call_deferred()

func boot() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	output = args[0] if args.size() > 0 else "user://guide_probe"
	DirAccess.make_dir_recursive_absolute(output)
	app = (load("res://act23/resonance_02.tscn") as PackedScene).instantiate()
	root.add_child(app)
	current_scene = app
	await frames(3)
	app.call("start_cart")
	scene = app.get("stage") as Node3D
	cart = scene.get("cart") as AnimatableBody3D
	yard = scene.get("yard") as Node3D
	rig = yard.get("rig") as Node3D
	flow = scene.get("flow")
	player = scene.get("player") as CharacterBody3D
	await frames(45)

func frames(count: int) -> void:
	for _i: int in range(count):
		await physics_frame
		clock += 1

func check(ok: bool, label: String, details: Dictionary = {}) -> void:
	checks.append({"ok": ok, "label": label, "details": details, "t": clock})
	if not ok:
		failures += 1
	print("PROBE_", "OK " if ok else "FAIL ", label, " ", JSON.stringify(details))

func stop_movement() -> void:
	for action: String in ["move_left", "move_right", "move_up", "move_down",
			"winch_haul", "winch_payout", "winch_creep"]:
		Input.action_release(action)

func press(action: String, hold_frames: int = 8) -> void:
	Input.action_press(action)
	await frames(hold_frames)
	Input.action_release(action)
	await frames(6)

func face(target: Vector3) -> void:
	var d: Vector3 = target - player.global_position
	var yaw: float = atan2(-d.x, -d.z)
	player.set("_camera_yaw_target", yaw)
	player.set("_camera_yaw", yaw)

func yard_point(local: Vector3) -> Vector3:
	return yard.to_global(local)

## Real W input toward `target` for at most `limit` physics frames. No teleport,
## no position write: the only thing that moves the body is the move action.
func walk(target: Vector3, limit: int, radius: float = 0.55) -> bool:
	face(target)
	Input.action_press("move_up")
	for _i: int in range(limit):
		await physics_frame
		clock += 1
		face(target)
		var flat: float = Vector2(player.global_position.x - target.x,
			player.global_position.z - target.z).length()
		if flat < radius:
			break
	Input.action_release("move_up")
	await frames(4)
	return true

func rail() -> Dictionary:
	return rig.call("alignment_state") as Dictionary

func angle() -> float:
	return float(rail().get("angle_deg", 999.0))

func wait_until(predicate: Callable, limit: int) -> bool:
	for _i: int in range(limit):
		if predicate.call():
			return true
		await physics_frame
		clock += 1
	return bool(predicate.call())

func run() -> void:
	await boot()
	# --- ride to the severed rail -----------------------------------------
	await walk(cart.to_global(Vector3(1.0, 1.91, 1.55)), 420, 0.20)
	await walk(cart.to_global(Vector3(2.0, 1.91, 1.70)), 200, 0.20)
	face(cart.to_global(Vector3(2.48, 2.64, 1.08)))
	await press("repair")
	check(bool(cart.get("running")), "E started the cart", {"distance": cart.get("distance")})
	check(await wait_until(func() -> bool: return bool(cart.get("stopped_for_fault")), 3600),
		"cart stopped at the severed rail", {"distance": cart.get("distance")})
	# --- disembark --------------------------------------------------------
	await walk(cart.to_global(Vector3(1.0, 1.91, 1.70)), 240, 0.20)
	await walk(cart.to_global(Vector3(1.0, 1.91, 1.05)), 200, 0.20)
	await walk(cart.to_global(Vector3(1.0, 0.40, -2.00)), 300, 0.30)
	check(cart.to_local(player.global_position).y < 0.6, "left the deck",
		{"local_y": cart.to_local(player.global_position).y})
	# --- hook the front eye, take the drum, break the jam ----------------
	await walk(yard_point(Vector3(2.2, 0.0, -1.20)), 400, 0.45)
	await walk(yard_point(Vector3(3.60, 0.0, -0.60)), 260, 0.40)
	await walk(yard_point(Vector3(5.60, 0.0, -0.55)), 260, 0.45)
	var anchor: Node3D = rig.call("find_anchor", "eye_far") as Node3D
	face(anchor.call("attach_point") as Vector3)
	await press("repair")
	check(bool((rig.call("tension_state") as Dictionary).get("attached", false)),
		"E hooked the cable on the front lifting eye")
	await walk(yard_point(Vector3(5.60, 0.0, -1.50)), 240, 0.40)
	await walk(yard_point(Vector3(5.70, 0.0, 4.60)), 420, 0.55)
	await walk(yard_point(Vector3(-0.60, 0.0, 3.95)), 420, 0.60)
	face((rig.get("winch") as Node3D).global_position)
	await press("repair")
	check(bool(flow.get("at_console")), "E took over the winch drum")
	var jam_broken: bool = false
	Input.action_press("winch_haul")
	for _i: int in range(900):
		await physics_frame
		clock += 1
		if not jam_broken and not bool(rail().get("jammed", true)):
			jam_broken = true
		if absf(angle()) <= 7.2:
			break
	Input.action_release("winch_haul")
	await frames(6)
	await press("winch_brake", 6)
	check(jam_broken, "the drum broke the jam loose", {"angle": angle()})
	check(absf(angle()) <= 8.0, "the nose reached the hand-wheel window", {"angle": angle()})
	await press("repair")
	check(not bool(flow.get("at_console")), "E left the drum")
	# --- take the hand wheel, then let go of it --------------------------
	await walk(yard_point(Vector3(5.60, 0.0, -1.50)), 420, 0.45)
	await walk(yard_point(Vector3(5.55, 0.0, -1.30)), 240, 0.45)
	var guide_at: Vector3 = yard.call("workstations")[0].get("position") as Vector3
	face(guide_at)
	await press("repair")
	var holder_after_take: int = int(rig.get("guide_holder"))
	var locked_after_take: bool = bool(player.get("interaction_locked"))
	check(holder_after_take == 1, "E took the receiver hand wheel",
		{"holder": holder_after_take, "interaction_locked": locked_after_take})
	await press("repair")
	var holder_after_release: int = int(rig.get("guide_holder"))
	var locked_after_release: bool = bool(player.get("interaction_locked"))
	check(holder_after_release == 0, "E released the receiver hand wheel",
		{"holder": holder_after_release, "interaction_locked": locked_after_release})
	# --- the actual defect: can the player walk away again? --------------
	var before: Vector3 = player.global_position
	var target: Vector3 = yard_point(Vector3(2.20, 0.0, -1.20))
	await walk(target, 240, 0.45)
	var after: Vector3 = player.global_position
	var moved: float = after.distance_to(before)
	var rows: Array = yard.call("workstations") as Array
	print("PROBE_WALK ", JSON.stringify({
		"before": str(before), "after": str(after), "moved": moved,
		"interaction_locked": bool(player.get("interaction_locked")),
		"input_enabled": bool(player.get("input_enabled")),
		"velocity": str(player.velocity), "on_floor": player.is_on_floor(),
		"guide_holder": int(rig.get("guide_holder")),
		"workstations": rows.size(), "angle": angle()}))
	check(moved > 0.80, "the player can walk away after releasing the hand wheel",
		{"moved": moved, "interaction_locked": bool(player.get("interaction_locked"))})
	# --- stage B: the wheel owns the stance while it is held -------------
	# A second, deliberate take/release cycle. While the worm gear is held the
	# body is meant to be locomotion-locked (the player is holding a wheel), so
	# a *single* player can never hold the wheel and walk to the pin socket -
	# that case only exists in co-op and is covered by the multiplayer runs.
	# What must hold in every mode is the pair: locked while held, free after
	# release, and a real walk that proves it.
	await walk(yard_point(Vector3(3.60, 0.0, -0.60)), 260, 0.40)
	await walk(yard_point(Vector3(5.60, 0.0, -1.50)), 260, 0.40)
	await walk(yard_point(Vector3(5.55, 0.0, -1.30)), 200, 0.45)
	guide_at = (yard.call("workstations") as Array)[0].get("position") as Vector3
	face(guide_at)
	await press("repair")
	var holder_b: int = int(rig.get("guide_holder"))
	var locked_b: bool = bool(player.get("interaction_locked"))
	check(holder_b == 1 and locked_b, "taking the wheel locks the stance on purpose",
		{"holder": holder_b, "interaction_locked": locked_b})
	await walk(yard_point(Vector3(2.20, 0.0, -1.20)), 120, 0.45)
	var held_move: float = player.global_position.distance_to(yard_point(Vector3(5.55, 0.0, -1.30)))
	check(held_move < 0.30, "the held wheel keeps the operator on the spot",
		{"moved": held_move, "holder": int(rig.get("guide_holder"))})
	face(guide_at)
	await press("repair")
	var holder_b2: int = int(rig.get("guide_holder"))
	var locked_b2: bool = bool(player.get("interaction_locked"))
	check(holder_b2 == 0, "E released the wheel again", {"holder": holder_b2})
	check(not locked_b2, "the release gives the body back every time",
		{"interaction_locked": locked_b2})
	var b_before: Vector3 = player.global_position
	await walk(yard_point(Vector3(2.20, 0.0, -1.20)), 240, 0.45)
	var b_moved: float = player.global_position.distance_to(b_before)
	check(b_moved > 0.80, "the operator can walk away after the second release",
		{"moved": b_moved, "guide_holder": int(rig.get("guide_holder"))})
	# --- write the machine-readable result -------------------------------
	var f: FileAccess = FileAccess.open(output.path_join("probe_result.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({
			"checks": checks.size(), "failures": failures,
			"holder_after_take": holder_after_take,
			"locked_after_take": locked_after_take,
			"holder_after_release": holder_after_release,
			"locked_after_release": locked_after_release,
			"moved_after_release": moved,
			"holder_second_take": holder_b,
			"locked_second_take": locked_b,
			"moved_while_held": held_move,
			"holder_second_release": holder_b2,
			"locked_second_release": locked_b2,
			"moved_after_second_release": b_moved,
			"angle": angle(), "phase": str(flow.get("phase")),
			"completion": bool(yard.call("completion")),
		}, "  "))
		f.close()
	print("PROBE_RESULT ", JSON.stringify({
		"checks": checks.size(), "failures": failures,
		"passed": failures == 0, "moved_after_release": moved,
		"locked_after_release": locked_after_release,
		"holder_after_release": holder_after_release,
		"moved_while_held": held_move,
		"moved_after_second_release": b_moved}))
	stop_movement()
	quit(0 if failures == 0 else 1)
