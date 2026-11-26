extends Node

## Minimal Act1App double for the standalone Act1CoopNet transport probe.
## It records the exact identity arguments the backend passes into the real
## application receiver; it has no gameplay state, ledger, or completion gate.

var local_pid := 1
var grants: Array = []
var rejected: Array = []


func build_snapshot(seq: int = 0) -> Dictionary:
	return {"seq": seq, "players": {}, "flags": {}, "active": []}


func get_local_state() -> Dictionary:
	return {"pos": Vector3.ZERO, "yaw": 0.0}


func client_apply_snapshot(_snap: Dictionary) -> void:
	pass


func set_local_pid(pid: int) -> void:
	local_pid = pid
	print("STUB_STAGE seated pid=%d" % pid)


func client_apply_grant(id: String, payload: Dictionary, sender_peer_id: int, recipient_pid: int) -> void:
	var record: Dictionary = {
		"id": id,
		"attach": bool(payload.get("attach", false)),
		"sender": sender_peer_id,
		"recipient": recipient_pid,
		"local_pid": local_pid,
	}
	grants.append(record)
	print("STUB_GRANT " + JSON.stringify(record))
	if id == "cart_push" and not bool(payload.get("attach", false)):
		rejected.append("release")
	# No local player/body exists in this double; recording the call is the
	# transport contract this probe is checking.


func host_add_player(pid: int) -> void:
	print("STUB_STAGE host_add_player pid=%d" % pid)


func host_remove_player(pid: int) -> void:
	print("STUB_STAGE host_remove_player pid=%d" % pid)


func host_handle_interaction_request(pid: int, id: String, kind: String) -> void:
	print("STUB_STAGE interaction pid=%d id=%s kind=%s" % [pid, id, kind])


func host_receive_state(pid: int, _state: Dictionary) -> void:
	print("STUB_STAGE state pid=%d" % pid)


func host_reset_run(_enet: int = 0) -> void:
	pass


func client_reset_run(_seq: int) -> void:
	pass


func begin_scene_handoff(_completion: Dictionary) -> void:
	pass


func show_network_message(_text: String, _seconds: float) -> void:
	pass
