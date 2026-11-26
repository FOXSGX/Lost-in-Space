extends Node
## Unified co-op session hub for the Resonance 04 → 05 vertical slice.
##
## This autoload is the SINGLE session. It hosts:
##   * CoopSession  — participants, participation ledger, machine claims
##   * CoopNet      — ENet peer, snapshots, RPC surface
## as persistent children, so the RPC node path `/root/SessionHub/CoopNet`
## stays identical across scene changes. Both Act 4 and Act 5 bind their
## scene-local world (level, story, machines, player) to this hub; the socket
## and the session never die on a scene change.
##
## This is the "不要让第四幕和第五幕各自保留一套互相冲突的会话状态" requirement.

signal session_started(mode: String)
signal scene_switch_requested(scene_path: String, spawn: Dictionary)

const PORT_DEFAULT := 9877

var session: CoopSession
var net: CoopNet
var mode: String = "solo"       # solo | host | client
var port: int = PORT_DEFAULT
var address: String = "127.0.0.1"

var scene_path: String = "/root/Main"  # current scene (res://...)

# --- progression carried from Act 4 into Act 5 -------------------------------
# Written by Act 4 on completion; read by Act 5 on spawn. Survives scene change.
var chapter_progress: Dictionary = {}

# --- FIVE-ACT campaign state (integration) -----------------------------------
# Uniform chapter ledger. Every act writes its completion payload here and the
# next act readies/spawns from it, so the five acts are one continuous run that
# shares a single session, single ENet socket, single participation ledger and
# a stable player identity (pid 1..4) across every scene switch.
var chapter_history: Dictionary = {
	"act01": {},
	"act23": {},
	"act04": {},
	"act05": {},
}
var current_chapter: String = "act01"
var story_flags: Dictionary = {}

# --- spawn info for the next scene -------------------------------------------
var pending_spawn: Dictionary = {}


func _ready() -> void:
	name = "SessionHub"
	_parse_args()
	session = CoopSession.new()
	session.name = "CoopSession"
	add_child(session)
	session.setup(1, true)
	net = CoopNet.new()
	net.name = "CoopNet"
	add_child(net)
	# The net must know its session before any start_host/start_client call
	# touches session.net_online (auto-start below, or the act apps' start()).
	net.session = session
	scene_switch_requested.connect(_on_scene_switch_requested)
	# Boot the socket immediately for host/client launches (direct scene or
	# --auto=). The per-act apps call SessionHub.start() too, which adopts the
	# already-running peer, so this is safe.
	if mode == "host":
		net.start_host(port)
	elif mode == "client":
		net.start_client(address, port)


func _parse_args() -> void:
	var args: Array[String] = []
	args.append_array(OS.get_cmdline_args())
	args.append_array(OS.get_cmdline_user_args())
	for arg in args:
		if arg == "--host" or arg == "--auto=host":
			mode = "host"
		elif arg == "--client" or arg == "--auto=client":
			mode = "client"
		elif arg.begins_with("--port="):
			port = int(arg.split("=")[1])
		elif arg.begins_with("--address="):
			address = arg.split("=")[1]
	if OS.has_feature("editor") and mode == "solo" and OS.get_cmdline_user_args().is_empty():
		pass  # keep solo by default in the editor


## Called by an act app after it built its world. Delegates to the persistent
## CoopNet; args only matter the first time (they create the ENet peer).
func start(host: bool, p_port: int = PORT_DEFAULT, p_address: String = "127.0.0.1") -> int:
	port = p_port
	address = p_address
	mode = "host" if host else "client"
	var err: int = OK
	if host:
		err = net.start_host(port)
	else:
		err = net.start_client(address, port)
	if err == OK:
		session_started.emit(mode)
	return err


func is_online() -> bool:
	return net != null and net.is_online()


## Machines and story nodes look up "the net" everywhere; route them here so a
## single lookup survives the peer living on this autoload instead of the
## scene root (as it did pre-integration).
static func the_net() -> CoopNet:
	var hub: Node = Engine.get_main_loop().root.get_node_or_null("/root/SessionHub")
	if hub != null and hub.get("net") != null:
		return hub.get("net") as CoopNet
	return null


func _on_scene_switch_requested(next_scene: String, spawn: Dictionary) -> void:
	# The requesting act app does the actual change_scene_to_file (it owns the
	# game tree / loader). This hub only records the pending spawn target.
	scene_path = next_scene
	pending_spawn = spawn


# ---------------------------------------------------------------------------
# Scene switching that keeps the SAME session (M5: Act 4 → Act 5)
# ---------------------------------------------------------------------------
# The SessionHub autoload is a stable node for RPC routing. The host owns the
# transition: it records the spawn payload, broadcasts to every client, then
# both sides call change_scene_to_file. The ENet peer and CoopSession live on
# this autoload, so the socket + participant list + participation ledger all
# survive the change.

## Host-side entry: Act 4 calls this when the exit is claimed to be complete.
func request_scene_switch(next_scene: String, spawn: Dictionary = {}) -> void:
	var online_net: bool = net != null and net.is_online()
	if online_net and not net.is_host:
		return  # only the host orders scene switches
	if online_net:
		do_scene_switch.rpc(next_scene, spawn)
	_do_local_switch(next_scene, spawn)


@rpc("authority", "call_remote", "reliable")
func do_scene_switch(next_scene: String, spawn: Dictionary) -> void:
	# Called on clients by the host. The host itself runs _do_local_switch.
	scene_path = next_scene
	pending_spawn = spawn
	# Apply the campaign state carried by the host, so the client's own
	# SessionHub mirrors the host: key events never replay, and the current
	# chapter matches what the host decided.
	_apply_campaign_state(spawn)
	_get_tree_root().change_scene_to_file(next_scene)


func _do_local_switch(next_scene: String, spawn: Dictionary) -> void:
	scene_path = next_scene
	pending_spawn = spawn
	_apply_campaign_state(spawn)
	_get_tree_root().change_scene_to_file(next_scene)


func _apply_campaign_state(spawn: Dictionary) -> void:
	var hist: Variant = spawn.get("_chapter_history")
	if hist is Dictionary:
		chapter_history = (hist as Dictionary).duplicate(true)
	var progress: Variant = spawn.get("_chapter_progress")
	if progress is Dictionary and not (progress as Dictionary).is_empty():
		chapter_progress = (progress as Dictionary).duplicate(true)
	var cur: Variant = spawn.get("_current_chapter")
	if cur is String and str(cur) != "":
		current_chapter = str(cur)
	var flags: Variant = spawn.get("_story_flags")
	if flags is Dictionary:
		story_flags = (flags as Dictionary).duplicate(true)


func _get_tree_root() -> SceneTree:
	return get_tree()


## Unified five-act hand-off. The caller (an act app) states which chapter it
## just finished, the payload the next chapter needs, and the next scene path.
## Records `chapter_history[current_chapter]`, marks the new chapter, then runs
## the normal cross-scene switch (host orders, clients follow, session survives).
func complete_chapter(chapter: String, payload: Dictionary, next_chapter: String, next_scene: String, spawn: Dictionary = {}) -> void:
	chapter_history[chapter] = payload
	current_chapter = next_chapter
	var merged_spawn: Dictionary = spawn.duplicate()
	merged_spawn["from_chapter"] = chapter
	merged_spawn["to_chapter"] = next_chapter
	# Carry the campaign ledger to the other side(s) so a two-process run keeps
	# the same chapter_history / current_chapter / story_flags on every process.
	merged_spawn["_chapter_history"] = chapter_history.duplicate(true)
	merged_spawn["_chapter_progress"] = chapter_progress.duplicate(true)
	merged_spawn["_current_chapter"] = next_chapter
	merged_spawn["_story_flags"] = story_flags.duplicate(true)
	request_scene_switch(next_scene, merged_spawn)


## Record the current chapter's completion without switching yet (used by the
## finale and by chapters that finish inside a single scene, e.g. 02→03).
func record_chapter_done(chapter: String, payload: Dictionary) -> void:
	chapter_history[chapter] = payload


func _process(_delta: float) -> void:
	pass