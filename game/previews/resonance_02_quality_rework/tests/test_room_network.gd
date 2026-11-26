extends "res://tests/test_network.gd"

var app: Node

func click(text: String) -> bool:
    for node: Node in app.find_children("*", "Button", true, false):
        var target: Button = node as Button
        if target.text != text or not target.is_visible_in_tree(): continue
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
    print("ROOM_BUTTON_MISSING ", text)
    failed += 1
    return false

func boot() -> void:
    output = OS.get_cmdline_user_args()[0]
    DirAccess.make_dir_recursive_absolute(output)
    shared = output.get_base_dir()
    app = (load("res://playtest.tscn") as PackedScene).instantiate()
    root.add_child(app)
    current_scene = app
    await frames(10)
    peer_mode = "host" if OS.get_cmdline_user_args().has("--role-host") else "client"
    await click("创建房间" if peer_mode == "host" else "加入房间")
    (app.get("port_input") as LineEdit).text = "26843"
    if peer_mode == "client": (app.get("address") as LineEdit).text = "127.0.0.1"
    await click("创建并等待队友" if peer_mode == "host" else "连接房间")
    scene = app.get("stage") as Node3D
    if scene == null:
        print("ROOM_BOOT_FAILED ", app.get("message"))
        app.queue_free()
        await frames(3)
        quit(1)
        return
    player = scene.get("player") as CharacterBody3D
    device = scene.get("device") as Node3D
    network = scene.get("session") as Node
    var joined: bool = await wait_for(func() -> bool: return is_instance_valid(scene) and (scene.get("actors") as Dictionary).size() == 2)
    if not joined:
        print("ROOM_CONNECT_FAILED")
        app.queue_free()
        await frames(3)
        quit(1)
        return
    check(joined, "通过正常菜单创建/加入房间")
    await frames(20)
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png(output.path_join("lobby.png"))
    if peer_mode == "host": await click("开始合作任务")
    check(await wait_for(func() -> bool: return str(app.get("screen")) == "playing"), "房主开始后双方正常进入任务")
    Engine.max_fps = 60

func run() -> void:
    await boot()
    if peer_mode == "host": await host_flow()
    else: await client_flow()
    await finish()

func finish() -> void:
    check(camera_hits == 0, "双人实际路线相机体积无重叠")
    check(float((player.get("camera_guard") as RefCounted).get("max_step")) <= 0.201, "正常 60Hz 运行相机每步不超过 0.2 米")
    var data: Dictionary = {"pid": OS.get_process_id(), "mode": peer_mode, "passed": failed == 0, "stable_evidence": stable_evidence, "snapshots_received": network.get("snapshots_received"), "snapshots_sent": network.get("snapshots_sent"), "rejected_poses": network.get("rejected_poses"), "checks": checks, "camera_overlap_frames": camera_hits, "samples": samples, "events": device.get("events"), "captures": captures, "route": route}
    data["max_snapshot_bytes"] = network.get("max_snapshot_bytes")
    data["camera_max_step"] = (player.get("camera_guard") as RefCounted).get("max_step")
    var file: FileAccess = FileAccess.open(output.path_join("network.json"), FileAccess.WRITE)
    file.store_string(JSON.stringify(data, "  "))
    file.close()
    print("ROOM_NETWORK_RESULT ", JSON.stringify({"passed": failed == 0, "checks": checks.size(), "mode": peer_mode, "camera_overlaps": camera_hits}))
    current_scene = null
    app.queue_free()
    await frames(4)
    await process_frame
    quit(0 if failed == 0 else 1)
