extends SceneTree

func _initialize() -> void:run.call_deferred()

func run() -> void:
    var output: String=OS.get_cmdline_user_args()[0]
    var stage: Node3D=(load("res://station.tscn") as PackedScene).instantiate() as Node3D
    root.add_child(stage);current_scene=stage
    var teardown: bool=OS.get_cmdline_user_args().has("--teardown-only")
    var until: int=Time.get_ticks_msec()+(0 if teardown else 25000)
    var device: Node3D=stage.get("device") as Node3D
    var session: Node=stage.get("session") as Node
    while Time.get_ticks_msec()<until:
        await physics_frame
        if str(session.get("mode"))=="client" and int(session.get("snapshots_received"))>2:break
    var state: Dictionary=device.call("stage_snapshot") as Dictionary
    var ok: bool=str(session.get("mode"))=="client" and str(state["phase"])=="stable" and int(state["activation_count"])==1 and int(state["carrier_id"])==0
    if teardown:ok=true
    var data: Dictionary={"teardown_only":teardown,"passed":ok,"pid":OS.get_process_id(),"peer_id":get_multiplayer().get_unique_id(),"mode":session.get("mode"),"state":state,"snapshots_received":session.get("snapshots_received")}
    var file: FileAccess=FileAccess.open(output.path_join("teardown-smoke.json" if teardown else "late-join.json"),FileAccess.WRITE);file.store_string(JSON.stringify(data,"  "));file.close()
    print("LATE_JOIN_RESULT ",ok);current_scene=null;stage.queue_free()
    for _i: int in range(3):await physics_frame
    await process_frame;quit(0 if ok else 1)
