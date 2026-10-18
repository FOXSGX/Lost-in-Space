extends SceneTree

## 走路循环逐帧截图：确认四肢不再像木棍一样整体摆动。

var output_dir: String = "C:/Users/ASUS/Desktop/迷失太空/work/gameplay-iterations/20261018-protagonist-blender"

func _initialize() -> void:
    run.call_deferred()

func _shot(label: String) -> void:
    for _frame in 2:
        await process_frame
    var image: Image = root.get_texture().get_image()
    image.resize(960, 540, Image.INTERPOLATE_BILINEAR)
    image.save_png(output_dir.path_join(label + ".png"))

func run() -> void:
    var args: PackedStringArray = OS.get_cmdline_user_args()
    if not args.is_empty():
        output_dir = String(args[0])
    DirAccess.make_dir_recursive_absolute(output_dir)
    var main: Main3D = load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(main)
    await process_frame
    main._ship_session.persistence_enabled = false
    main.network_port = 26710 + int(Time.get_ticks_msec() % 60)
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
    if stage != null:
        stage.set_process(false)
        stage.set_physics_process(false)
    main._game_layer.visible = false
    var player: SpacePlayer3D = main.players[1] as SpacePlayer3D
    player.set_physics_process(false)
    player.global_position = Vector3(-48.0, 0.4, 20.0)
    player.rotation.y = 0.6
    var visual: ProtagonistVisual = player._visual
    var camera: Camera3D = Camera3D.new()
    camera.projection = Camera3D.PROJECTION_PERSPECTIVE
    camera.fov = 42.0
    camera.position = Vector3(-49.7, 1.30, 17.5)
    main.add_child(camera)
    camera.look_at(Vector3(-48.0, 0.95, 20.0), Vector3.UP)
    camera.current = true
    for shot in 6:
        for step in 7:
            visual.update_state(1.0 / 60.0, Vector2.RIGHT * 5.8, false, false, false, 5)
            await process_frame
        await _shot("walk-%02d" % shot)
    print("PROTAGONIST_WALK_CAPTURE done")
    quit(0)
