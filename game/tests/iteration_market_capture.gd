extends SceneTree

## 星际集市面板截图（含预览图）。

var output_dir: String = "C:/Users/ASUS/Desktop/迷失太空/work/gameplay-iterations/20261018-skins-market"

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
    main.network_port = 27210 + int(Time.get_ticks_msec() % 60)
    main._create_host()
    main.connected_ids = [1]
    main.spawn_player_for_peer(1)
    main._ship_session.enter_ship(true, [1], main._ship_session.snapshot())
    await process_frame
    main.credits = 2000
    main.open_market()
    main.market_selection = 1
    main._refresh_market_ui()
    await process_frame
    await _shot("market-gala")
    main.market_selection = 4
    main._refresh_market_ui()
    await process_frame
    await _shot("market-duck")
    print("MARKET_CAPTURE done")
    quit(0)
