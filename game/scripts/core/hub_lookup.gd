class_name HubLookup
extends RefCounted

## Resolve the SessionHub autoload without referencing its symbol at parse time.
##
## Referencing an autoload by name from a class_name script fails to compile in
## `-s` SceneTree preloading, which is how several tests boot. A pure node-path
## lookup works everywhere, exactly like NetLookup.get_net() does for CoopNet.
## Act module scripts (level_flow, machines, stage) use this so a module can be
## tested standalone and still hand off to the campaign when SessionHub exists.

static func hub() -> Node:
	var root: Node = Engine.get_main_loop().root
	if root == null:
		return null
	return root.get_node_or_null("/root/SessionHub")


static func available() -> bool:
	return hub() != null


static func chapter_history() -> Dictionary:
	var h: Node = hub()
	if h == null:
		return {}
	return (h.get("chapter_history") as Dictionary).duplicate(true)


## Hand-off to the campaign: record current chapter completion and switch to the
## next scene in the SAME session (host orders, clients follow). No-op when the
## hub is absent, so the module still boots standalone.
static func complete_chapter(chapter: String, payload: Dictionary, next_chapter: String, next_scene: String, spawn: Dictionary = {}) -> void:
	var h: Node = hub()
	if h == null or not h.has_method("complete_chapter"):
		print("HUB_LOOKUP complete_chapter skipped (no SessionHub)")
		return
	h.call("complete_chapter", chapter, payload, next_chapter, next_scene, spawn)


## Record completion without switching (single-scene multi-chapter, finale).
static func record_chapter_done(chapter: String, payload: Dictionary) -> void:
	var h: Node = hub()
	if h == null or not h.has_method("record_chapter_done"):
		return
	h.call("record_chapter_done", chapter, payload)


static func current_chapter() -> String:
	var h: Node = hub()
	if h == null:
		return ""
	return str(h.get("current_chapter"))


## True when the unified session is running in the given role (solo/host/client).
## The role is fixed at launch, so this stays stable even after a network loss.
static func mode_is(role: String) -> bool:
	var h: Node = hub()
	if h == null:
		return false
	return str(h.get("mode")) == role


static func pending_spawn() -> Dictionary:
	var h: Node = hub()
	if h == null:
		return {}
	return (h.get("pending_spawn") as Dictionary).duplicate(true)
