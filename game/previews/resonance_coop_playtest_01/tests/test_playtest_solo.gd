extends "res://tests/test_solo.gd"

var app: Node

func boot() -> void:
    output=OS.get_cmdline_user_args()[0]
    DirAccess.make_dir_recursive_absolute(output)
    app=(load("res://playtest.tscn") as PackedScene).instantiate()
    root.add_child(app);current_scene=app
    await frames(12)
    var event: InputEventKey=InputEventKey.new()
    event.keycode=KEY_ENTER;event.pressed=true
    Input.parse_input_event(event)
    await frames(3)
    event=event.duplicate() as InputEventKey;event.pressed=false
    Input.parse_input_event(event)
    await frames(35)
    scene=app.get("stage") as Node3D
    if scene==null:
        print("SOLO_MENU_FAILED");quit(1);return
    player=scene.get("player") as CharacterBody3D;device=scene.get("device") as Node3D
    check(str(app.get("screen"))=="playing","通过正常主菜单进入单人试玩")

func finish() -> void:
    var data: Dictionary={"passed":failed==0,"failures":failed,"checks":checks,"route":route,"samples":samples,"actions":actions,"events":device.get("events"),"final_state":device.call("stage_snapshot"),"camera_overlap_frames":camera_hits,"orbit_samples":orbit_samples,"orbit_overlaps":orbit_hits,"held_overlap_frames":held_overlap_frames,"captures":captures,"camera_max_step":(player.get("camera_guard") as RefCounted).get("max_step")}
    var file: FileAccess=FileAccess.open(output.path_join("interaction-test.json"),FileAccess.WRITE)
    file.store_string(JSON.stringify(data,"  "));file.close()
    print("PLAYTEST_SOLO_RESULT ",JSON.stringify({"passed":failed==0,"checks":checks.size(),"camera_max_step":data["camera_max_step"]}))
    current_scene=null;app.queue_free();await frames(4);await process_frame
    quit(0 if failed==0 else 1)
