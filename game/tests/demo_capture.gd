extends SceneTree

## Windowed visual evidence capture for the isolated demo candidate.
## It instantiates the requested shipped scene, waits for real rendering, and
## stores the viewport image. This script never changes gameplay state.

const SCENES: Dictionary = {
	"start": "res://demo/demo_launcher.tscn",
	"act23": "res://scenes/act23.tscn",
	"ending": "res://demo/demo_ending.tscn",
}

var target: String = "start"
var out_path: String = ""


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--target="):
			target = arg.split("=", true, 1)[1]
		elif arg.begins_with("--out="):
			out_path = arg.split("=", true, 1)[1]
	_run.call_deferred()


func _run() -> void:
	if not SCENES.has(target):
		push_error("DEMO_CAPTURE_UNKNOWN_TARGET " + target)
		quit(2)
		return
	var packed: PackedScene = load(str(SCENES[target])) as PackedScene
	if packed == null:
		push_error("DEMO_CAPTURE_SCENE_LOAD_FAILED " + target)
		quit(3)
		return
	if target == "ending":
		# Visual-only capture: the production ending is entered by app.gd after
		# the real Act05 gate. The seed lets this isolated screenshot show the
		# verified-state copy without pretending that this capture is a gameplay
		# acceptance run.
		var hub: Node = root.get_node_or_null("/root/SessionHub")
		if hub != null:
			hub.chapter_history = {
				"act23": {"completed": true},
				"act04": {"completed": true},
				"act05": {"completed": true},
			}
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	await create_timer(2.0 if target != "act23" else 4.5).timeout
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	if image == null:
		push_error("DEMO_CAPTURE_NO_IMAGE " + target)
		quit(4)
		return
	if out_path.is_empty():
		out_path = "user://demo_%s.png" % target
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	var error: Error = image.save_png(out_path)
	print("DEMO_CAPTURE target=%s display=%s size=%s path=%s error=%d" % [
		target, DisplayServer.get_name(), str(image.get_size()), out_path, error])
	quit(0 if error == OK else 5)
