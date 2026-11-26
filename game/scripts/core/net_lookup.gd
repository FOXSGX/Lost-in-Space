class_name NetLookup
extends RefCounted

## Resolve the unified CoopNet without referencing the `SessionHub` autoload
## symbol at parse time. Referencing an autoload by name from a class_name
## script fails to compile in `-s` SceneTree preloading, which is how several
## tests boot. A pure node-path lookup works everywhere.

static func get_net() -> CoopNet:
	var root: Node = Engine.get_main_loop().root
	if root == null:
		return null
	var hub: Node = root.get_node_or_null("/root/SessionHub")
	if hub == null:
		return null
	return hub.get_node_or_null("CoopNet") as CoopNet


static func online() -> bool:
	var net: CoopNet = get_net()
	return net != null and net.is_online()