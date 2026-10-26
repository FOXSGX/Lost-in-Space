extends SceneTree

func _initialize() -> void:
    var font: SystemFont = SystemFont.new()
    font.font_names = PackedStringArray(["Microsoft YaHei", "sans-serif"])
    var theme: Theme = (load("res://scripts/playtest_theme.gd") as Script).create_theme(font) as Theme
    var result: Error = ResourceSaver.save(theme, "res://assets/playtest_theme.tres")
    print("THEME_SAVE ", result)
    quit(0 if result == OK else 1)
