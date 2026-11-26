extends SceneTree
## Generates a binary ProjectSettings blob for packaging diagnostics.
##   godot --headless --path . --script res://tests/make_project_binary.gd

func _initialize() -> void:
	var target: String = ProjectSettings.globalize_path("res://project.binary")
	var err: Error = ProjectSettings.save_custom(target)
	print("SAVE_CUSTOM ", err)
	var exists: bool = FileAccess.file_exists(target)
	print("EXISTS ", exists)
	if exists:
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(target)
		print("SIZE ", bytes.size())
		print("HEAD ", bytes.slice(0, 8))
	quit()
