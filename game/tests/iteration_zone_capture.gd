extends SceneTree

## 分区包裹前后对比：第一区（闸门关闭）与第二区（闸门收起）。

var output_dir: String = "C:/Users/ASUS/Desktop/迷失太空/work/gameplay-iterations/20261018-resonance-zones"

func _initialize() -> void:
    run.call_deferred()

func _shot(label: String) -> void:
    for _frame in 3:
        await process_frame
    var image: Image = root.get_texture().get_image()
    image.resize(1280, 720, Image.INTERPOLATE_BILINEAR)
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
    main.network_port = 27610 + int(Time.get_ticks_msec() % 60)
    main._create_host()
    main.connected_ids = [1]
    main.spawn_player_for_peer(1)
    main._ship_session.enter_ship(true, [1], main._ship_session.snapshot())
    main._ship_session.ready_peers = [1]
    main._ship_session.select_destination("electromagnetic")
    main._confirm_land()
    await process_frame
    var stage: ResonanceStage3D = main._resonance_stage
    var player: SpacePlayer3D = main.players[1] as SpacePlayer3D
    player.set_physics_process(false)
    player.teleport_to(stage.zone_anchor(0) + Vector3(-6.0, 0.2, 10.0))
    await process_frame
    await _shot("zone-1-gate-closed")
    main.set_process(false)
    stage.modules[0]["state"] = "docked"
    stage.modules[0]["phase"] = "docked"
    stage._on_module_docked(1)
    player.teleport_to(stage.zone_anchor(1) + Vector3(-4.0, 0.2, 10.0))
    await _shot("zone-2-gate-open")
    print("ZONE_CAPTURE done")
    quit(0)
