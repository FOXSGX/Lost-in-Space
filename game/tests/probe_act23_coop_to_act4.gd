# probe_act23_coop_to_act4.gd — 双进程 Act23 → Act04 交接探针（真实状态驱动）
#
# 运行（两个进程，主机先开）：
#   godot --headless --path <P> res://act23/act23_entry.tscn \
#         -s res://tests/probe_act23_coop_to_act4.gd -- --host --port=9917
#   godot --headless --path <P> res://act23/act23_entry.tscn \
#         -s res://tests/probe_act23_coop_to_act4.gd -- --client --port=9917 --address=127.0.0.1
#
# 主机：放矿车到"到达前"真实状态 → 马达到站 → phase=done → complete_chapter → 切换 act4。
#   主机切换成功后保持运行（不退出），以便客户端验证"在线跟随"；由外部脚本统一结束。
# 客户端：跟随 do_scene_switch 进入 act4；检测 scene=Resonance04 且仍在线 → OK。
extends SceneTree

var _role: String = "solo"
var _setup_done: bool = false
var _host_reached: bool = false

func _initialize() -> void:
	print("PROBE_COOP23_TO_ACT4_START")
	var args: Array[String] = []
	args.append_array(OS.get_cmdline_args())
	args.append_array(OS.get_cmdline_user_args())
	for arg in args:
		if arg == "--host" or arg == "--auto=host":
			_role = "host"
		elif arg == "--client" or arg == "--auto=client":
			_role = "client"

func _process(_delta: float) -> bool:
	var elapsed: int = Time.get_ticks_msec()
	if _role == "host" and not _setup_done and elapsed > 3000:
		_setup_done = true
		var root_node: Node = current_scene
		var slice: Node = root_node.get_node_or_null("MovingCartSlice") if root_node != null else null
		var world: Node = slice if slice != null else root_node
		var cart: Node = world.get_node_or_null("MovingCart") if world != null else null
		var player: Node = world.get_node_or_null("Player1") if world != null else null
		if cart == null or player == null:
			push_error("PROBE_COOP23 host cart/player null")
			quit(1)
			return false
		cart.call("release_route")
		cart.call("snap_to_distance", 103.5)
		cart.set("running", true)
		player.call("restore_at", cart.to_global(Vector3(1.0, 1.91, 1.6)))
		print("PROBE_COOP23 host positioned cart at 103.5")
		return false
	var hub: Node = Engine.get_main_loop().root.get_node_or_null("/root/SessionHub")
	var chapter: String = str(hub.get("current_chapter")) if hub != null else "no-hub"
	var scene: String = str(current_scene.name) if current_scene != null else "null"
	var history: Dictionary = hub.get("chapter_history") as Dictionary if hub != null else {}
	var act23_done: bool = bool((history.get("act23", {}) as Dictionary).get("completed", false)) if hub != null else false
	var reached: bool = chapter == "act04" and act23_done and scene == "Resonance04"
	if reached:
		if _role == "host":
			if not _host_reached:
				_host_reached = true
				print("PROBE_COOP23_TO_ACT4_OK role=host switched to act4")
				# 主机保持在线；由外部脚本统一 kill（超时兜底在下方）
			return false
		else:
			var session: Node = hub.get_node_or_null("CoopSession") if hub != null else null
			var local_pid: int = int(session.get("local_pid")) if session != null else 0
			var online: bool = bool(hub.get("net").get("online")) if hub != null and hub.get("net") != null else false
			print("PROBE_COOP23 client reached act4 local_pid=", local_pid, " online=", online)
			if online and local_pid == 2:
				print("PROBE_COOP23_TO_ACT4_OK role=client online-follow")
				quit(0)
				return false
			# 主机仍在时 client 应先看到在线跟随；若变离线说明主机已退，不视为通过
			if not online and _role == "client":
				push_error("PROBE_COOP23_TO_ACT4_FAIL role=client offline (host exited too early?)")
				quit(1)
				return false
	# 超时兜底
	if elapsed > 60000:
		if _role == "host" and _host_reached:
			# 主机已成功，但外部 kill 未到；正常收尾
			quit(0)
			return false
		push_error("PROBE_COOP23_TO_ACT4_FAIL role=", _role, " chapter=", chapter, " scene=", scene)
		quit(1)
		return false
	return false