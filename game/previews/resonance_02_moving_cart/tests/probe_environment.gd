extends SceneTree

func _initialize() -> void:
    print("USER_DIR ", OS.get_user_data_dir())
    for property: Dictionary in ProjectSettings.get_property_list():
        var key: String = str(property["name"])
        if "shader_cache" in key or "file_logging" in key or "custom_user" in key:
            print(key, "=", ProjectSettings.get_setting(key))
    quit()
