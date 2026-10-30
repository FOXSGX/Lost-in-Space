extends SceneTree

## 五套皮肤并排展示。

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
    main.network_port = 27110 + int(Time.get_ticks_msec() % 60)
    main._create_host()
    main.connected_ids = [1]
    for peer_id in [2, 3, 4, 5]:
        main.connected_ids.append(peer_id)
        main.spawn_player_for_peer(peer_id)
    main.spawn_player_for_peer(1)
    main._ship_session.enter_ship(true, [1, 2, 3, 4, 5], main._ship_session.snapshot())
    main._ship_session.ready_peers = [1, 2, 3, 4, 5]
    main._ship_session.select_destination("electromagnetic")
    main._confirm_land()
    await process_frame
    main.set_process(false)
    main.set_physics_process(false)
    if main._resonance_stage != null:
        main._resonance_stage.set_process(false)
        main._resonance_stage.set_physics_process(false)
    main._game_layer.visible = false
    var skins: Array = ["ranger", "gala", "nova", "valkyrie", "duck"]
    for index in skins.size():
        var peer_id: int = index + 1
        if not main.players.has(peer_id):
            main.connected_ids.append(peer_id)
            main.spawn_player_for_peer(peer_id)
        var player: SpacePlayer3D = main.players[peer_id] as SpacePlayer3D
        player.set_physics_process(false)
        player.global_position = Vector3(-50.0 + float(index) * 1.15, 0.4, 20.0)
        player.rotation.y = 0.0
        main.equip_skin(peer_id, String(skins[index]))
        await process_frame
    var camera: Camera3D = Camera3D.new()
    camera.projection = Camera3D.PROJECTION_PERSPECTIVE
    camera.fov = 42.0
    camera.position = Vector3(-47.7, 1.35, 16.2)
    main.add_child(camera)
    camera.look_at(Vector3(-47.7, 1.02, 20.0), Vector3.UP)
    camera.current = true
    await _shot("skins-lineup")
    print("SKINS_CAPTURE done")
    quit(0)
