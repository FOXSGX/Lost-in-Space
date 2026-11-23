class_name Act1SessionBridge
extends RefCounted

## Session bridge between Act 01 and the unified five-act campaign session.
##
## Act1App never talks to `/root/SessionHub` (or its old `RunState` autoload)
## directly. It calls this bridge, which resolves the destination at runtime:
##
## * INTEGRATED mode — `/root/SessionHub` autoload exists. The bridge forwards
##   player identity / completion / scene-switch onto SessionHub's unified
##   contract (`chapter_history`, `complete_chapter`, `mode`, `net.local_pid`).
##   Act 01's departure becomes `complete_chapter("act01", …, "act23", …)`,
##   which hands true Act 02/03 to the main integration (this module does not
##   build a second act).
##
## * STANDALONE mode — no SessionHub (module test host / solo module run). The
##   bridge keeps a local stub that mirrors the same contract so the module is
##   self-verifiable without the integrated project.
##
## Also absorbs the old `RunState` autoload state (`test_mode`, `debug_enabled`)
## so Act01 imports with no autoload dependency.

signal act01_completed(payload: Dictionary)

## The real Act 02/03 scene the main integration owns. Defaults to the path the
## five-act architecture reserves; the main agent may override it before launch
## if act23 lands elsewhere. It intentionally does not exist inside this module.
# lint:ignore res_path next_act23_scene points at the main project's act23
const ACT23_SCENE_DEFAULT := "res://scenes/act23.tscn"

var integrated := false
var hub: Node = null                # /root/SessionHub when integrated
var test_mode := false
var debug_enabled := false

# Unified-session mirrors used in standalone mode (kept in sync with Hub when
# integrated by reading through Hub directly).
var chapter_history: Dictionary = {
	"act01": {},
	"act23": {},
	"act04": {},
	"act05": {},
}
var current_chapter := "act01"
var pending_spawn: Dictionary = {}
var story_flags: Dictionary = {}

var next_act23_scene := ACT23_SCENE_DEFAULT

var _stub_completion: Dictionary = {}


func _init() -> void:
	if Engine.get_main_loop() != null and Engine.get_main_loop().root.has_node("/root/SessionHub"):
		integrated = true
		hub = Engine.get_main_loop().root.get_node("/root/SessionHub")


func is_online() -> bool:
	if integrated and hub != null and hub.has_method("is_online"):
		return bool(hub.is_online())
	return false


func hub_mode() -> String:
	if integrated and hub != null:
		var m: Variant = hub.get("mode")
		if m != null:
			return str(m)
	return "solo"


func local_pid() -> int:
	if integrated and hub != null:
		var net_node: Node = hub.get("net")
		if net_node != null:
			var lp: Variant = net_node.get("local_pid")
			if lp != null:
				return int(lp)
	return 1


## Returns the current chapter's completion payload that was recorded locally
## (standalone). In integrated mode the payload is read from SessionHub.
func recorded_completion() -> Dictionary:
	if integrated and hub != null and hub.get("chapter_history") != null:
		var hist: Dictionary = hub.get("chapter_history")
		return (hist.get("act01", {}) as Dictionary).duplicate(true)
	return _stub_completion.duplicate(true)


## Act 01 is done. In integrated mode this hands over to the real Act 02/03
## (SessionHub.complete_chapter → request_scene_switch keeps the same session).
## In standalone mode the bridge records the completion locally and emits
## `act01_completed` so module tests can assert on it without a second act.
func complete_act01(payload: Dictionary) -> void:
	var safe: Dictionary = payload.duplicate(true)
	if integrated and hub != null:
		var spawn: Dictionary = build_spawn_payload(safe)
		hub.complete_chapter("act01", safe, "act23", next_act23_scene, spawn)
		return
	chapter_history["act01"] = safe
	current_chapter = "act23"
	_stub_completion = safe
	act01_completed.emit(safe)
	print("ACT1_SESSION standalone completion recorded: chapter_history[act01].completed=", str(safe.get("completed", false)))


## What Act 02/03 reads back from `pending_spawn` to start its opening. The main
## integration defines the exact contract; these are the stable, asserted keys.
func build_spawn_payload(completion: Dictionary) -> Dictionary:
	return {
		"mode": completion.get("mode", hub_mode()),
		"completed": true,
		"result": completion.duplicate(true),
		"launch_seconds": float(completion.get("time", 0)) / 1000.0 if completion.has("time") else 0.0,
	}