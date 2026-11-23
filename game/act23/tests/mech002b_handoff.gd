extends Node
## MECHANICS-002B · 第一幕→第二幕过幕入口检查
##
## 走 act1_app 实际调用的同一条链路：
##   Act1SessionBridge.complete_act01(payload) → SessionHub.complete_chapter(
##       "act01", payload, "act23", "res://scenes/act23.tscn", spawn)
## 这里直接调用 hub.complete_chapter（同一实现），确认场景真的切到第二幕、
## 且第二幕的矿车/货舱/制动机构在线。
##
## 声明：这是"过幕接线 + 场景切换"的验证，不是重打一遍 20 分钟第一幕。
## 场景一旦切换，本测试节点会被释放，所以观察者挂在 /root 上继续断言。

func _ready() -> void:
	var hub: Node = get_node_or_null("/root/SessionHub")
	if hub == null:
		print("FAIL  H1 找不到 SessionHub 自动加载（过幕链路缺失）")
		print("MECH002B_HANDOFF_DONE failures=1")
		get_tree().quit(1)
		return
	print("PASS  H1 SessionHub 在线，complete_chapter 可用=%s" % str(hub.has_method("complete_chapter")))
	var scene: PackedScene = load("res://scenes/act23.tscn") as PackedScene
	print(("PASS  " if scene != null else "FAIL  ") + "H2 第二幕正式入口 res://scenes/act23.tscn 可加载")
	if scene == null:
		print("MECH002B_HANDOFF_DONE failures=1")
		get_tree().quit(1)
		return
	var watcher: Node = (load("res://act23/tests/mech002b_handoff_watch.gd") as Script).new() as Node
	watcher.name = "HandoffWatcher"
	get_tree().root.add_child.call_deferred(watcher)
	hub.call("complete_chapter", "act01", {"completed": true, "source": "mech002b_handoff"},
		"act23", "res://scenes/act23.tscn", {})


