extends Node
## MECHANICS-004C · 交接与入口验证
##
## 1. 正式第四幕入口 res://scenes/act4.tscn 能加载。
## 2. 第五幕正式入口 res://scenes/main.tscn 能加载并完成初始化（不修改第五幕文件）。
## 3. 第四幕真实完成后 SessionHub 真的执行了场景切换（current_scene 从 Act4 变成 Main）。
##
## 第 3 项用**根级观察者**验证：真实切换会销毁 current_scene（也就是本测试节点），
## 所以观察者必须挂在 tree.root 上才活得过切换。这正是「切换真的发生了」的证据。
##
## 失败返回非零退出码。

var failures: int = 0
var checks: int = 0


func _ready() -> void:
	await _t1_act4_entry()
	await _t2_act5_entry()
	await _t3_handoff()
	print("MECH004C_HANDOFF_DONE checks=%d passed=%d failures=%d" % [
		checks, checks - failures, failures])
	get_tree().quit(0 if failures == 0 else 1)


func _t1_act4_entry() -> void:
	var path := "res://scenes/act4.tscn"
	var exists: bool = ResourceLoader.exists(path)
	var packed: PackedScene = null
	if exists:
		packed = load(path) as PackedScene
	var ok := packed != null
	var stage: Node = null
	if packed != null:
		stage = packed.instantiate()
	if stage != null:
		add_child(stage)
		for _i in range(120):
			await get_tree().physics_frame
		var gate: Node = stage.get("gate")
		var panel: Node = gate.get("_panel") if gate != null else null
		ok = ok and gate != null and stage.get("player") != null and panel is RigidBody3D
		_check("H1 正式第四幕入口 res://scenes/act4.tscn 正常加载（门是真实刚体，玩家在线）", ok,
			"exists=%s gate=%s panel=%s" % [str(exists), str(gate != null),
				panel.get_class() if panel != null else "-"])
	else:
		_check("H1 正式第四幕入口 res://scenes/act4.tscn 正常加载（门是真实刚体，玩家在线）",
			false, "exists=%s" % str(exists))
	if stage != null:
		stage.queue_free()
		await _w(20)


func _t2_act5_entry() -> void:
	var path := "res://scenes/main.tscn"
	var exists: bool = ResourceLoader.exists(path)
	var packed: PackedScene = null
	if exists:
		packed = load(path) as PackedScene
	var ok := packed != null
	var stage: Node = null
	if packed != null:
		stage = packed.instantiate()
	var node_count := 0
	if stage != null:
		add_child(stage)
		for _i in range(180):
			await get_tree().physics_frame
		node_count = _count(stage)
		ok = ok and stage.is_inside_tree() and node_count > 10
	_check("H2 第五幕正式入口 res://scenes/main.tscn 仍可加载并完成初始化（窗口 B 负责，本轮不修改）",
		ok, "exists=%s nodes=%d" % [str(exists), node_count])
	if stage != null:
		stage.queue_free()
		await _w(20)


func _t3_handoff() -> void:
	var hub: Node = get_node_or_null("/root/SessionHub")
	var stage: Node = (load("res://scenes/act4.tscn") as PackedScene).instantiate()
	add_child(stage)
	for _i in range(150):
		await get_tree().physics_frame
	var gate: Node = stage.get("gate")
	var player: Node3D = stage.get("player") as Node3D
	if gate == null or player == null:
		_check("H3 第四幕→第五幕交接", false, "gate/player 缺失")
		return

	# 根级观察者：真实场景切换会销毁 current_scene（本节点），它必须活下来记录结果。
	var observer: Node = Node.new()
	observer.name = "Mech004CHandoffObserver"
	observer.set_script(load("res://tests/mech004c_handoff_observer.gd"))
	get_tree().root.add_child(observer)
	# 本测试要验证**真实**交接，所以不能带 `suppress_act5` 元数据
	# （`game.gd::_session_hub_call_switch()` 对探针默认抑制自动切场）。
	stage.remove_meta("suppress_act5")

	# 剧情条件：三段记忆（真实回调）+ 门自己受力开启
	var seen: Dictionary = stage.get("seen_memories") as Dictionary
	for index: int in [1, 2, 3]:
		seen[index] = true
		stage.call("_on_memory_finished", index)
		await _w(50)
	var guard := 0
	while not bool(gate.get("exit_allowed")) and guard < 1800:
		await get_tree().physics_frame
		guard += 1

	# 玩家真的走进出口（触发真实完成路径）
	var door_world: Vector3 = (gate as Node3D).to_global(Vector3(0.0, 0.0, 0.0))
	player.call("teleport", Vector3(door_world.x + 1.0, 0.05, door_world.z), 0.0)
	await _w(20)
	Input.action_press("move_forward")
	for _i in range(180):
		await get_tree().physics_frame
	Input.action_release("move_forward")
	await _w(90)

	var completed: bool = bool(stage.get("completed"))
	var payload: Dictionary = stage.call("completion_payload") as Dictionary
	var history: Dictionary = {}
	var progress: Dictionary = {}
	if hub != null:
		var raw_history: Variant = hub.get("chapter_history")
		if raw_history is Dictionary:
			history = raw_history as Dictionary
		var raw_progress: Variant = hub.get("chapter_progress")
		if raw_progress is Dictionary:
			progress = raw_progress as Dictionary
	var recorded: bool = history.has("act04")
	var progress_ok: bool = bool(progress.get("completed", false)) \
		and bool(progress.get("gate_open", false))
	var chapter_ok: bool = str(payload.get("chapter", "")) == "resonance_04"
	var ok: bool = completed and recorded and progress_ok \
		and bool(payload.get("gate_open", false)) and chapter_ok
	_check("H3a 第四幕真实完成并写入 SessionHub 交接状态（completed、act04 章节记录、chapter_progress.gate_open 均来自门体实际状态）",
		ok, "completed=%s act04_recorded=%s chapter=%s progress.completed=%s progress.gate_open=%s payload.gate_open=%s" % [
			str(completed), str(recorded), str(payload.get("chapter", "")),
			str(progress.get("completed", false)),
			str(progress.get("gate_open", false)), str(payload.get("gate_open", false))])
	# 之后由观察者继续验证真实切换；本节点可能在切换中被销毁，所以不再断言。
	print("H3b 已交给根级观察者验证真实场景切换")


func _count(node: Node) -> int:
	var total := 1
	for child: Node in node.get_children():
		total += _count(child)
	return total


func _check(label: String, ok: bool, detail: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("%s  %s  |  %s" % ["PASS" if ok else "FAIL", label, detail])


func _w(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame
