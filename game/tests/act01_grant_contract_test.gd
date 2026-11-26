extends SceneTree

## Test-only static contract check for the Act01 hold-grant RPC.
##
## This does not replace the real two-process probe; it pins the signature that
## caused the 4-vs-3 argument mismatch so a future rename cannot silently
## reintroduce the transport peer id as an application argument.

func _initialize() -> void:
	var failures: Array[String] = []
	var script: Script = load("res://scripts/coop/coop_net.gd") as Script
	if script == null:
		print("FAIL could not load coop_net.gd")
		quit(1)
		return
	var obj: Object = script.new()
	var found: Dictionary = {}
	for m in obj.get_method_list():
		var name: String = str(m.get("name", ""))
		if name == "act1_grant_hold" or name == "act1_send_grant":
			var names: Array[String] = []
			for a in (m.get("args", []) as Array):
				names.append(str((a as Dictionary).get("name", "")))
			found[name] = names

	var grant: Array = found.get("act1_grant_hold", []) as Array
	var send: Array = found.get("act1_send_grant", []) as Array
	print("CONTRACT act1_grant_hold args=%s" % str(grant))
	print("CONTRACT act1_send_grant args=%s" % str(send))
	if grant != ["id", "pid", "payload"]:
		failures.append("act1_grant_hold must be (id, pid, payload), got %s" % str(grant))
	if send != ["enet_id", "id", "pid", "payload"]:
		failures.append("act1_send_grant must keep (enet_id, id, pid, payload), got %s" % str(send))

	var backend_script: Script = load("res://act1/scripts/coop/act1_coop_net.gd") as Script
	if backend_script == null:
		failures.append("could not load Act1CoopNet backend")
	else:
		var backend_grant: Array = []
		for method in backend_script.new().get_method_list():
			if str(method.get("name", "")) == "grant_hold":
				for argument in (method.get("args", []) as Array):
					backend_grant.append(str((argument as Dictionary).get("name", "")))
		print("CONTRACT Act1CoopNet.grant_hold args=%s" % str(backend_grant))
		if backend_grant != ["id", "pid", "payload"]:
			failures.append("Act1CoopNet.grant_hold must be (id, pid, payload), got %s" % str(backend_grant))
	if failures.is_empty():
		print("CONTRACT_OK")
		quit(0)
	else:
		for f in failures:
			print("FAIL " + f)
		quit(1)
