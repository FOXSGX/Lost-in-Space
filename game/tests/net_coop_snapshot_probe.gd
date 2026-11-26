extends SceneTree

## Launcher for the production-CoopNet snapshot probe (see
## net_coop_snapshot_node.gd). Isolated ports only; never 9877.

const NodeScript := preload("res://tests/net_coop_snapshot_node.gd")


func _initialize() -> void:
	var role := "host"
	var port := 19880
	var out_dir := ""
	for arg in OS.get_cmdline_user_args():
		var text := str(arg)
		if text.begins_with("--role="):
			role = text.split("=")[1]
		elif text.begins_with("--port="):
			port = int(text.split("=")[1])
		elif text.begins_with("--out="):
			out_dir = text.split("=")[1]
	var node: Node = NodeScript.new()
	node.call("configure", role, port, out_dir)
	root.add_child(node)
