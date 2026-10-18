extends SceneTree

## 只读截图：验证装置拉杆在操作过程中会转动。

var output_dir: String = ""

func _initialize() -> void:
    run.call_deferred()

func _shot(label: String) -> void:
    for _frame in 3:
        await process_frame
    var image: Image = root.get_texture().get_image()
    image.resize(960, 540, Image.INTERPOLATE_BILINEAR)
    image.save_png(output_dir.path_join(label + ".png"))

func run() -> void:
    var args: PackedStringArray = OS.get_cmdline_user_args()
    output_dir = String(args[0]) if not args.is_empty() else "C:/Users/ASUS/Desktop/迷失太空/work/gameplay-iterations/20261017-resonance-solo-clear"
    DirAccess.make_dir_recursive_absolute(output_dir)
    var main: Main3D = load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(main)
    await process_frame
    main._ship_session.persistence_enabled = false
    main.network_port = 25810 + int(Time.get_ticks_msec() % 80)
    main._create_host()
    main.connected_ids = [1]
    main._ship_session.enter_ship(true, [1], main._ship_session.snapshot())
    main._ship_session.ready_peers = [1]
    main._ship_session.select_destination("electromagnetic")
    main._confirm_land()
    await process_frame
    main.set_process(false)
    main.set_physics_process(false)
    var stage: ResonanceStage3D = main._resonance_stage
    var player: SpacePlayer3D = main.players[1] as SpacePlayer3D
    player.set_physics_process(false)
    player.teleport_to(Vector3(stage.heat_valve_positions["left"]))
    await process_frame

    main.handle_action(1, "repair")
    for _step in 12:
        stage.stage_tick(0.05)
    var lever: Node3D = stage._minigame_lever
    if lever == null:
        print("LEVER_CAPTURE: no lever")
        quit(1)
        return
    var camera: Camera3D = Camera3D.new()
    camera.projection = Camera3D.PROJECTION_PERSPECTIVE
    camera.fov = 55.0
    var focus: Vector3 = lever.global_position + Vector3(0.0, 0.6, 0.0)
    camera.position = focus + Vector3(2.6, 1.6, 2.6)
    main.add_child(camera)
    camera.look_at(focus, Vector3.UP)
    camera.current = true
    await _shot("lever-mid")
    # 让光标走到另一侧，拉杆角度应该跟着变
    for _step in 18:
        stage.stage_tick(0.05)
    await _shot("lever-other-side")
    print("LEVER_CAPTURE: ok cursor=%.2f" % float(stage.minigame.get("cursor", 0.0)))
    quit(0)
