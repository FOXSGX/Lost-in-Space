extends SceneTree

## Launcher for the lightweight two-process ENet snapshot transport probe.
## Usage (two shells):
##   godot --headless --path <project> -s res://tests/net_snapshot_transport_probe.gd \
##     -- --role=host --port=19879 --out=<evidence-dir>
##   godot ... -- --role=client --port=19879 --out=<evidence-dir>

const NodeScript := preload("res://tests/net_snapshot_transport_node.gd")


func _initialize() -> void:
	var role := "host"
	var port := 19879
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
