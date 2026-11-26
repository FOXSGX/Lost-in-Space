extends SceneTree

## Lightweight two-process ENet probe for the standalone Act1CoopNet grant path.
## It uses a stub stage so no Act01 level, ledger, or HUD is loaded; the only
## production object under test is Act1CoopNet's transport receiver.
## Isolated port only (default 19881), never 9877.

const NetScript := preload("res://act1/scripts/coop/act1_coop_net.gd")
const StubScript := preload("res://tests/act1_backend_stub_stage.gd")

var role := "host"
var port := 19881
var out_dir := ""
var stage: Node = null
var net: Node = null
var finished := false
var sent_wrong := false
var sent_valid := false


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var text := str(arg)
		if text.begins_with("--role="):
			role = text.split("=")[1]
		elif text.begins_with("--port="):
			port = int(text.split("=")[1])
		elif text.begins_with("--out="):
			out_dir = text.split("=")[1]
	_run.call_deferred()


func _run() -> void:
	stage = StubScript.new()
	stage.name = "Act1StubStage"
	root.add_child(stage)
	net = NetScript.new()
	net.name = "Act1Backend"
	net.set("stage", stage)
	net.set("port", port)
	root.add_child(net)
	if role == "host":
		var err: int = int(net.call("start_host"))
		print("ACT1_BACKEND host start=%d port=%d" % [err, port])
	else:
		var err2: int = int(net.call("start_client", "127.0.0.1"))
		print("ACT1_BACKEND client start=%d port=%d" % [err2, port])
	await create_timer(0.8).timeout
	if role == "host":
		await _host_flow()
	else:
		await _client_flow()
	_finish()


func _host_flow() -> void:
	var enet := int(net.call("enet_for_pid", 2))
	var guard := 0
	while enet == 0 and guard < 40:
		await create_timer(0.1).timeout
		enet = int(net.call("enet_for_pid", 2))
		guard += 1
	print("ACT1_BACKEND host peer enet=%d" % enet)
	if enet == 0:
		_finish()
		return
	# Wrong recipient first: the client must drop it before the app receiver.
	net.rpc_id(enet, "grant_hold", "cart_push", 1, {
		"attach": true, "offset": [-2.05, 0.02, 0.0], "yaw": -PI * 0.5})
	sent_wrong = true
	await create_timer(0.5).timeout
	# Correct recipient and payload.
	net.rpc_id(enet, "grant_hold", "cart_push", 2, {
		"attach": true, "offset": [-2.05, 0.02, 0.0], "yaw": -PI * 0.5})
	sent_valid = true
	await create_timer(0.8).timeout


func _client_flow() -> void:
	await create_timer(1.8).timeout
	print("ACT1_BACKEND client local_pid=%d grants=%s" % [
		int(net.get("local_pid")), JSON.stringify(stage.get("grants"))])


func _finish() -> void:
	if finished:
		return
	finished = true
	var report: Dictionary = {
		"probe": "act1_backend_probe.gd",
		"role": role,
		"port": port,
		"sent_wrong_recipient": sent_wrong,
		"sent_valid_recipient": sent_valid,
		"grants": stage.get("grants") if stage != null else [],
		"local_pid": int(stage.get("local_pid")) if stage != null else -1,
	}
	print("ACT1_BACKEND_RESULT " + JSON.stringify(report))
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
		var f := FileAccess.open(out_dir.path_join("act1_backend_%s.json" % role), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(report, "  "))
			f.close()
	quit(0)
