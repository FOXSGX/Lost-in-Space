extends "res://tests/input_driver.gd"

var app: Node
var ui_checks: Array[Dictionary] = []

func launch_app() -> void:
    output = OS.get_cmdline_user_args()[0]
    DirAccess.make_dir_recursive_absolute(output)
    app = (load("res://playtest.tscn") as PackedScene).instantiate()
    root.add_child(app)
    current_scene = app
    await frames(8)

func button(text: String) -> Button:
    for node: Node in app.find_children("*", "Button", true, false):
        var candidate: Button = node as Button
        if candidate.text == text and candidate.is_visible_in_tree(): return candidate
    return null

func click(text: String) -> bool:
    var target: Button = button(text)
    if target == null:
        print("UI_BUTTON_MISSING ", text)
        failed += 1
        return false
    var at: Vector2 = target.get_global_rect().get_center()
    var motion: InputEventMouseMotion = InputEventMouseMotion.new()
    motion.position = at
    Input.parse_input_event(motion)
    await frames(2)
    var event: InputEventMouseButton = InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.position = at
    event.pressed = true
    Input.parse_input_event(event)
    await frames(2)
    event = event.duplicate() as InputEventMouseButton
    event.pressed = false
    Input.parse_input_event(event)
    await frames(5)
    return true

func bind_stage() -> void:
    scene = app.get("stage") as Node3D
    player = scene.get("player") as CharacterBody3D
    device = scene.get("device") as Node3D

func ui_check(ok: bool, label: String) -> void:
    ui_checks.append({"ok": ok, "label": label})
    if not ok: failed += 1
    print("UI_CHECK_", "OK " if ok else "FAILED ", label)

func capture_ui(label: String) -> void:
    await frames(5)
    if DisplayServer.get_name() != "headless":
        await RenderingServer.frame_post_draw
        root.get_texture().get_image().save_png(output.path_join(label + ".png"))

func layout_check(label: String) -> void:
    var findings: Array = []
    for node: Node in app.find_children("*", "Control", true, false):
        var control: Control = node as Control
        if not control.is_visible_in_tree() or not (control is Button or control is Label or control is LineEdit or control is HSlider): continue
        var rect: Rect2 = control.get_global_rect()
        if rect.size.x < 1 or rect.size.y < 1 or not Rect2(Vector2.ZERO, root.get_visible_rect().size).encloses(rect):
            findings.append({"node": str(control.get_path()), "rect": str(rect)})
    ui_checks.append({"label": label + " layout", "findings": findings, "ok": findings.is_empty()})
    if not findings.is_empty(): failed += 1

func finish_app() -> void:
    var file: FileAccess = FileAccess.open(output.path_join("ui-test.json"), FileAccess.WRITE)
    file.store_string(JSON.stringify({"passed": failed == 0, "failures": failed, "checks": ui_checks}, "  "))
    file.close()
    current_scene = null
    app.queue_free()
    await frames(4)
    await process_frame
    quit(0 if failed == 0 else 1)
