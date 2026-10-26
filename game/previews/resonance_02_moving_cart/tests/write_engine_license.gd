extends SceneTree

func _initialize() -> void:
    var file: FileAccess=FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE)
    file.store_string(Engine.get_license_text())
    file.close()
    quit()
