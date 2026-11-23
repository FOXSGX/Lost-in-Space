extends Node
## MECHANICS-004C · 交接观察者（挂在 tree.root 上，活得过真实场景切换）
##
## 第四幕完成时会调用 SessionHub.request_scene_switch("res://scenes/main.tscn")，
## 真正执行 change_scene_to_file，销毁 current_scene。本节点不在 current_scene
## 之下，因此能在切换后读回结果并把 verdict 写到日志与文件。
##
## 判定：
##   · current_scene 曾经从 Act4 变成 Main（第五幕正式入口）
##   · 切换后第五幕场景真的初始化（节点数 > 10）
##   · SessionHub.current_chapter == "act05"
##   · 交接 payload 的 gate_open 为真
##
## 超时 90 s 未观察到切换则判失败，退出码非零。

const TIMEOUT_SECONDS := 90.0
const REPORT_PATH := "res://captures/mech004c/handoff_verdict.json"

var _elapsed: float = 0.0
var _initial_name: String = ""
var _switched: bool = false
var _next_name: String = ""
var _next_nodes: int = 0
var _hub: Node


func _ready() -> void:
	_hub = get_node_or_null("/root/SessionHub")
	print("HANDOFF_OBSERVER start current_scene=", _scene_name(),
		" root_children=", _child_names())


func _scene_name() -> String:
	var scene: Node = get_tree().current_scene
	if scene == null or not is_instance_valid(scene):
		return ""
	return scene.name


func _child_names() -> String:
	var out: Array[String] = []
	for c: Node in get_tree().root.get_children():
		out.append(c.name)
	return str(out)


func _process(delta: float) -> void:
	if _switched:
		return
	_elapsed += delta
	var scene_name: String = _scene_name()
	# 第一帧可能还没有 current_scene（节点在 _ready 期间就挂上了），
	# 所以初始场景名在这里惰性捕获，而不是在 _ready 里。
	if _initial_name == "" and scene_name != "":
		_initial_name = scene_name
		print("HANDOFF_OBSERVER baseline=", _initial_name, " root_children=", _child_names())
	elif _initial_name != "" and scene_name != "" and scene_name != _initial_name:
		_switched = true
		_next_name = scene_name
		print("HANDOFF_OBSERVER switch_detected to=", _next_name,
			" root_children=", _child_names())
		_finish_deferred()
		return
	if _elapsed > TIMEOUT_SECONDS:
		print("HANDOFF_OBSERVER timeout current_scene=", _scene_name(),
			" root_children=", _child_names())
		_report()


func _finish_deferred() -> void:
	for _i in range(30):
		await get_tree().process_frame
	if get_tree().current_scene != null:
		_next_nodes = _count(get_tree().current_scene)
	_report()


func _report() -> void:
	var chapter: String = ""
	var progress: Dictionary = {}
	if _hub != null:
		chapter = str(_hub.get("current_chapter"))
		var raw: Variant = _hub.get("chapter_progress")
		if raw is Dictionary:
			progress = raw as Dictionary
	var gate_open: bool = bool(progress.get("gate_open", false))
	var completed: bool = bool(progress.get("completed", false))
	var ok: bool = _switched and _next_nodes > 10 \
		and chapter == "act05" and gate_open and completed
	print("%s  H3b 第四幕→第五幕真实场景切换（SessionHub.request_scene_switch → change_scene_to_file）  |  from=%s to=%s nodes=%d chapter=%s gate_open=%s completed=%s elapsed=%.1fs" % [
		"PASS" if ok else "FAIL", _initial_name, _next_name, _next_nodes, chapter,
		str(gate_open), str(completed), _elapsed])
	var payload := {
		"ok": ok,
		"from_scene": _initial_name,
		"to_scene": _next_name,
		"to_scene_nodes": _next_nodes,
		"current_chapter": chapter,
		"chapter_progress": progress,
		"elapsed_seconds": snappedf(_elapsed, 0.01),
	}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures/mech004c"))
	var f: FileAccess = FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(payload, "  "))
		f.close()
	print("HANDOFF_VERDICT ", JSON.stringify(payload))
	get_tree().quit(0 if ok else 1)


func _count(node: Node) -> int:
	var total := 1
	for child: Node in node.get_children():
		total += _count(child)
	return total
