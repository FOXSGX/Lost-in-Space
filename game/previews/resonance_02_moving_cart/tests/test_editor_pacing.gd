extends "res://tests/test_pacing.gd"

var editor_app: Node

func boot() -> void:
    output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
    # F5 supplies --scene. Reuse its real app, rather than create a second scene
    # underneath the main menu. It is the same normal Enter used by a player.
    await frames(12)
    editor_app=root.get_node_or_null("Playtest")
    if editor_app==null:push_error("EDITOR_MAIN_APP_MISSING");quit(1);return
    var event: InputEventKey=InputEventKey.new();event.keycode=KEY_ENTER;event.pressed=true
    Input.parse_input_event(event);await frames(3)
    event=event.duplicate() as InputEventKey;event.pressed=false;Input.parse_input_event(event)
    await frames(35)
    scene=editor_app.get("stage") as Node3D
    if scene==null:push_error("EDITOR_SOLO_ENTRY_FAILED");quit(1);return
    player=scene.get("player") as CharacterBody3D;device=scene.get("device") as Node3D
    check(str(editor_app.get("screen"))=="playing","F5 实际主场景通过正常菜单进入单人")

func finish() -> void:
    var file: FileAccess=FileAccess.open(output.path_join("interaction-test.json"),FileAccess.WRITE)
    file.store_string(JSON.stringify({"passed":failed==0,"checks":checks,"camera_overlap_frames":camera_hits,"route":route,"captures":captures}));file.close()
    current_scene=null;editor_app.queue_free();await frames(4);quit(0 if failed==0 else 1)
