extends SceneTree

## 腐墟星截图：确认合并后的星球能正常渲染。

var output_dir: String = "C:/Users/ASUS/Desktop/迷失太空/work/gameplay-iterations/20261018-ruin-merge"

func _initialize() -> void:
    run.call_deferred()

func run() -> void:
    var args: PackedStringArray = OS.get_cmdline_user_args()
    if not args.is_empty():
        output_dir = String(args[0])
    DirAccess.make_dir_recursive_absolute(output_dir)
    var main: Main3D = load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(main)
    await process_frame
    main._ship_session.persistence_enabled = false
    main.network_port = 27410 + int(Time.get_ticks_msec() % 60)
    main._create_host()
    main.connected_ids = [1]
    main.spawn_player_for_peer(1)
    main._ship_session.enter_ship(true, [1], main._ship_session.snapshot())
    main._ship_session.ready_peers = [1]
    main._ship_session.select_destination("ruin")
    main._confirm_land()
    await process_frame
    for index in 20:
        main._ruin_planet.tick(1.0 / 30.0)
    await process_frame
    for frame in 5:
        await process_frame
    var image: Image = root.get_texture().get_image()
    image.resize(1280, 720, Image.INTERPOLATE_BILINEAR)
    image.save_png(output_dir.path_join("ruin-planet.png"))
    print("RUIN_CAPTURE done")
    quit(0)
