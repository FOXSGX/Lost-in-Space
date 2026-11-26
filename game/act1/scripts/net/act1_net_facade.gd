class_name Act1NetFacade
extends Node

## Thin network adapter for Act 01. Act1App talks only to THIS facade, never to
## a raw ENet peer, so the module can neither collide with nor duplicate the
## unified session's single ENet socket.
##
## Two backends, chosen at setup():
## * STANDALONE (no /root/SessionHub autoload) — the module runs on its own
##   (module test host / module-local two-process check). The facade creates the
##   Act01 project's original backend `Act1CoopNet` (alone in the process, so it
##   may own `multiplayer.multiplayer_peer`).
## * INTEGRATED (/root/SessionHub exists) — the unified session owns the only
##   ENet peer. The facade binds to `SessionHub.net` (the unified CoopNet) and
##   NEVER creates Act1CoopNet. Act01-specific RPCs go through a documented
##   `act1_*` surface on the unified CoopNet (see docs/API_CONTRACT.md); until
##   that surface exists, the facade logs `integration-pending` and stays a safe
##   solo mirror (no second peer, no hard crash).
##
## This is the "薄适配器 / 明确提供待整合接口" requirement of the integration
## contract: no second standalone ENet peer is ever merged into the official
## session.

signal peer_joined(pid: int)
signal peer_left(pid: int)
signal connected_changed(online: bool)
signal ride_started(pid: int, completion: Dictionary)

const DEFAULT_PORT := 24568

var stage: Node = null
var mode := "solo"
var is_host := false
var online := false
var local_pid := 1
var port := DEFAULT_PORT

var integrated := false
var backend: Act1CoopNet = null
var unet: Node = null       # unified /root/SessionHub/CoopNet when integrated
var _warned_integration := false


func setup(p_stage: Node) -> void:
	stage = p_stage
	name = "Act1NetFacade"
	integrated = Engine.get_main_loop() != null and Engine.get_main_loop().root.has_node("/root/SessionHub")
	if integrated:
		var hub: Node = Engine.get_main_loop().root.get_node("/root/SessionHub")
		unet = hub.get("net") as Node
		if unet != null and unet.has_method("bind_act1"):
			unet.call("bind_act1", self)
		_sync_from_unified()
		print("ACT1_NET_FACADE integrated mode (bound to unified session, no Act1CoopNet)")
		return
	backend = Act1CoopNet.new()
	backend.name = "Act1CoopNet"
	add_child(backend)
	backend.setup(stage)
	backend.ride_started.connect(func(p: int, c: Dictionary) -> void: ride_started.emit(p, c))
	backend.peer_joined.connect(func(p: int) -> void: peer_joined.emit(p))
	backend.peer_left.connect(func(p: int) -> void: peer_left.emit(p))
	backend.connected_changed.connect(func(_o: bool) -> void: connected_changed.emit(_o))
	backend.connected_changed.connect(func(_o: bool) -> void: _sync_from_backend())
	_sync_from_backend()
	print("ACT1_NET_FACADE standalone mode (Act1CoopNet backend)")


## Called by the unified CoopNet binding (to-integrate surface): the unified net
## learned our local pid / online state, so refresh the facade mirror.
func on_unified_sync() -> void:
	_sync_from_unified()


func _sync_from_unified() -> void:
	if not integrated or unet == null:
		return
	var hub: Node = Engine.get_main_loop().root.get_node_or_null("/root/SessionHub")
	if hub == null:
		return
	var m: Variant = hub.get("mode")
	mode = str(m) if m != null else "solo"
	var is_on: Variant = unet.get("online")
	online = bool(is_on) if is_on != null else (bool(unet.call("is_online")) if unet.has_method("is_online") else false)
	var ih: Variant = unet.get("is_host")
	is_host = bool(ih) if ih != null else false
	var lp: Variant = unet.get("local_pid")
	local_pid = int(lp) if lp != null else 1


func _sync_from_backend() -> void:
	if backend == null:
		return
	mode = backend.mode
	is_host = backend.is_host
	online = backend.online
	local_pid = backend.local_pid


func _process(_delta: float) -> void:
	if integrated:
		_sync_from_unified()


func is_authority() -> bool:
	if backend != null:
		return backend.is_authority()
	if not integrated or unet == null:
		return true
	if not online:
		return true
	return is_host


func peer_count() -> int:
	if backend != null:
		return backend.peer_count()
	if not integrated or unet == null:
		return 1
	if not online:
		return 1
	return int(unet.call("peer_count") if unet.has_method("peer_count") else 1)


func is_online() -> bool:
	if backend != null:
		return backend.is_online()
	return online


func enet_for_pid(pid: int) -> int:
	if backend != null:
		return backend.enet_for_pid(pid)
	if unet != null and unet.get("_peer_pid") != null:
		var map: Dictionary = unet.get("_peer_pid")
		for enet in map.keys():
			if int(map[enet]) == pid:
				return int(enet)
	return 0


func peer_pids() -> Array[int]:
	if backend != null:
		return backend.peer_pids()
	var out: Array[int] = []
	if unet != null and unet.get("_peer_pid") != null:
		var map: Dictionary = unet.get("_peer_pid")
		for key in map.keys():
			out.append(int(map[key]))
	out.sort()
	return out


func submit_interaction(id: String, kind: String) -> void:
	if is_host:
		return
	if backend != null:
		backend.submit_interaction(id, kind)
		return
	# Integrated path: call the unified net's "send" helper, never the @rpc
	# handler itself. `act1_submit_interaction` starts with `if not is_host:
	# return`, so calling it from the client only ran the guard locally and the
	# intent never left the process (host never saw a client press).
	if unet != null and unet.has_method("act1_submit_interaction_local"):
		unet.call("act1_submit_interaction_local", id, kind)
		return
	if unet != null and unet.has_method("act1_submit_interaction"):
		unet.call("act1_submit_interaction", id, kind)
		return
	_warn_integration_pending("act1_submit_interaction_local")


func submit_reset() -> void:
	if is_host:
		return
	if backend != null:
		backend.submit_reset()
		return
	if unet != null and unet.has_method("act1_submit_reset_local"):
		unet.call("act1_submit_reset_local")
		return
	if unet != null and unet.has_method("act1_submit_reset"):
		unet.call("act1_submit_reset")
		return
	_warn_integration_pending("act1_submit_reset_local")


## Replaces the old `net.grant_hold.rpc_id(...)` call: routes through whichever
## backend is active and never touches the unified peer's internals directly.
func send_grant(pid: int, id: String, payload: Dictionary) -> void:
	if not is_host or pid <= 0:
		return
	if stage != null and stage.has_method("grant_payload_valid"):
		var check: Dictionary = stage.call("grant_payload_valid", id, payload) as Dictionary
		if not bool(check.get("ok", false)):
			print("ACT1_GRANT_REJECT side=facade reason=%s id=%s pid=%d" % [
				str(check.get("reason", "invalid")), id, pid])
			return
	if backend != null:
		var enet := backend.enet_for_pid(pid)
		if enet == 0:
			return
		backend.grant_hold.rpc_id(enet, id, pid, payload)
		return
	# `act1_grant_hold` is an authority->client @rpc that returns early on the
	# host, so calling it locally from the host sent nothing. Use the unified
	# net's send helper, which performs `act1_grant_hold.rpc_id(...)`.
	if unet != null and unet.has_method("act1_send_grant"):
		var enet2 := enet_for_pid(pid)
		if enet2 == 0:
			return
		unet.call("act1_send_grant", enet2, id, pid, payload)
		return
	if unet != null and unet.has_method("act1_grant_hold"):
		var enet3 := enet_for_pid(pid)
		if enet3 == 0:
			return
		unet.call("act1_grant_hold", enet3, id, pid, payload)
		return
	_warn_integration_pending("act1_send_grant")


func notify_ride_started(pid: int, completion: Dictionary) -> void:
	ride_started.emit(pid, completion)


## Authoritative unbind point for the unified session. This node is a child of
## the Act01 scene root, so Godot calls `_exit_tree()` while the scene is being
## removed from the tree — before the persistent `/root/SessionHub/CoopNet` gets
## another `_process` tick. Without this, the Act 1 snapshot loop keeps pointing
## at a torn-down stage and builds one more snapshot against nodes that are no
## longer inside the tree (11 `!is_inside_tree()` errors per exit).
##
## The unified ENet peer belongs to SessionHub and is deliberately NOT touched
## here: leaving Act01 must preserve the session for the next chapter.
func _exit_tree() -> void:
	if not integrated:
		return
	if unet == null or not is_instance_valid(unet):
		return
	if not unet.has_method("unbind_act1"):
		return
	unet.call("unbind_act1", self)


func _warn_integration_pending(rpc_name: String) -> void:
	if _warned_integration:
		return
	_warned_integration = true
	print("ACT1_NET_FACADE integration-pending: unified CoopNet lacks `%s`. "
		+ "Act01 online RPCs are not yet forwarded (see docs/API_CONTRACT.md). "
		+ "The module still runs solo; no second ENet peer was created." % rpc_name)