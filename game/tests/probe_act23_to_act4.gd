extends SceneTree

var _checks: Dictionary = {}

func _initialize() -> void:
	print("PROBE_ACT23_TO_ACT4_START")

func _diag(tag: String) -> void:
	var root_node: Node = current_scene
	var slice: Node = root_node.get_node_or_null("MovingCartSlice") if root_node != null else null
	var world: Node = slice if slice != null else root_node
	var cart: Node = world.get_node_or_null("MovingCart") if world != null else null
	var flow: Node = world.get_node_or_null("LevelFlow") if world != null else null
	var stage: Node = world if world != null else null
	var line: String = tag
	line += " cart.arrived=" + (str(cart.get("arrived")) if cart != null else "null")
	line += " cart.speed=" + (str(cart.get("speed")) if cart != null else "null")
	line += " cart.distance=" + (str(cart.get("distance")) if cart != null else "null")
	line += " flow.phase=" + (str(flow.get("phase")) if flow != null else "null")
	line += " handoffStarted=" + (str(stage.get("_chapter_handoff_started")) if stage != null else "null")
	print(line)

func _process(_delta: float) -> bool:
	var elapsed: int = Time.get_ticks_msec()
	if elapsed > 2500 and not _checks.has("setup"):
		_checks["setup"] = true
		var root_node: Node = current_scene
		var slice: Node = root_node.get_node_or_null("MovingCartSlice") if root_node != null else null
		var world: Node = slice if slice != null else root_node
		var cart: Node = world.get_node_or_null("MovingCart") if world != null else null
		var player: Node = world.get_node_or_null("Player1") if world != null else null
		if cart == null or player == null:
			push_error("PROBE cart/player null")
			quit(1)
			return false
		# Realistic end-of-run state: line restored, cart near the mine entrance,
		# the rider standing on the deck. The motor drives the last metres, the
		# derived phase flips to "done", and the stage hands off to Act 4.
		cart.call("release_route")
		cart.call("snap_to_distance", 103.5)
		cart.set("running", true)
		player.call("restore_at", cart.to_global(Vector3(1.0, 1.91, 1.6)))
		print("PROBE setup: rider aboard, cart at 103.5, route clear")
		return false
	if elapsed > 5000 and not _checks.has("d1"):
		_checks["d1"] = true
		_diag("PROBE_DIAG@5s")
		return false
	if elapsed > 9000 and not _checks.has("d2"):
		_checks["d2"] = true
		_diag("PROBE_DIAG@9s")
		return false
	if elapsed > 13000:
		var hub: Node = Engine.get_main_loop().root.get_node_or_null("/root/SessionHub")
		_diag("PROBE_DIAG@13s")
		var chapter: String = str(hub.get("current_chapter")) if hub != null else "no-hub"
		var history: Dictionary = hub.get("chapter_history") as Dictionary if hub != null else {}
		var act23_done: bool = bool((history.get("act23", {}) as Dictionary).get("completed", false)) if hub != null else false
		print("PROBE final current_chapter=", chapter, " act23_completed=", act23_done,
			" scene=", (str(current_scene.name) if current_scene != null else "null"))
		if chapter == "act04" and act23_done:
			print("PROBE_ACT23_TO_ACT4_OK")
			quit(0)
		else:
			push_error("PROBE_ACT23_TO_ACT4_FAIL")
			quit(1)
		return false
	return false
