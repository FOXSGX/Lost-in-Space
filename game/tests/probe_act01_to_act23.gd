extends SceneTree

## probe_act01_to_act23.gd — Act01 → Act23 交接「连线冒烟」（FAST WIRING SMOKE）
##
## ⚠️ 本脚本**不是玩法验收**：它只检查交接链路是否接好（节点/方法/场景/常量），
##    不产生、也不冒充任何通关结果。真正的交接验收请看：
##      res://tests/probe_act01_to_act23_full_run.gd
##    那个探针用真实输入走完第一幕全部工序并真实发车，再由生产路径
##    Act1SessionBridge → SessionHub.complete_chapter → res://scenes/act23.tscn 完成切换。
##
## 历史说明（R5 现场）：本文件名原先存放的是直接调用 `cart.begin_departure()` 的旧探针，
## 它绕过了发车联锁，被 `all_active_aboard()` 正确拒绝（这不是 bug，是安全联锁）。
## 该旧探针已按"不伪造联锁"的要求下线，改为下面的连线冒烟 + 上面的真实输入探针。
##
## 运行：
##   godot --headless --path <P> -s res://tests/probe_act01_to_act23.gd

var _done := false
var _fails: Array[String] = []


func _check(ok: bool, text: String) -> void:
	print(("PASS " if ok else "FAIL ") + text)
	if not ok:
		_fails.append(text)


func _process(_delta: float) -> bool:
	if _done:
		return false
	_done = true
	_run.call_deferred()
	return false


func _run() -> void:
	print("PROBE_ACT01_TO_ACT23_WIRING_START")

	var root_node: Node = Engine.get_main_loop().root
	var hub: Node = root_node.get_node_or_null("/root/SessionHub")
	_check(hub != null, "统一会话 autoload 存在：/root/SessionHub")
	for m in ["complete_chapter", "request_scene_switch", "record_chapter_done"]:
		_check(hub != null and hub.has_method(m), "SessionHub.%s() 存在" % m)

	var unified_net: Node = hub.get_node_or_null("CoopNet") if hub != null else null
	_check(unified_net != null, "统一 peer 节点：/root/SessionHub/CoopNet")
	var act1_surface := [
		"bind_act1", "act1_submit_interaction", "act1_submit_state", "act1_submit_reset",
		"act1_grant_hold", "act1_sync_snapshot", "act1_bootstrap", "act1_ride",
		"act1_welcome", "act1_sync_message",
	]
	for m in act1_surface:
		_check(unified_net != null and unified_net.has_method(m), "统一 CoopNet 提供 %s()" % m)

	var act1_scene := load("res://act1/act01.tscn") as PackedScene
	_check(act1_scene != null, "res://act1/act01.tscn 可加载")
	var bridge_script := load("res://act1/scripts/session/act1_session_bridge.gd") as GDScript
	_check(bridge_script != null, "Act1SessionBridge 脚本可加载")
	_check(bridge_script != null and str(bridge_script.get_script_constant_map().get("ACT23_SCENE_DEFAULT", "")) == "res://scenes/act23.tscn",
		"桥默认下一幕 = res://scenes/act23.tscn")

	var wrap_scene := load("res://scenes/act23.tscn") as PackedScene
	_check(wrap_scene != null, "res://scenes/act23.tscn 可加载")
	var wrap: Node = wrap_scene.instantiate() if wrap_scene != null else null
	_check(wrap != null and wrap.name == "Act23Chapter", "包装场景根节点 = Act23Chapter")
	_check(wrap != null and wrap.get_node_or_null("Act23Entry") != null, "包装场景内含 Act23Entry（真实 Act23 子树）")
	if wrap != null:
		wrap.free()

	var act23_entry := load("res://act23/act23_entry.tscn") as PackedScene
	_check(act23_entry != null, "res://act23/act23_entry.tscn 可加载")

	print("PROBE_ACT01_TO_ACT23_WIRING_RESULT failures=%d" % _fails.size())
	if _fails.is_empty():
		print("PROBE_ACT01_TO_ACT23_WIRING_OK")
	else:
		print("PROBE_ACT01_TO_ACT23_WIRING_FAIL")
	quit(0 if _fails.is_empty() else 1)
