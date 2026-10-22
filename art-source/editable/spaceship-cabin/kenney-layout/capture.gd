extends SceneTree

var output_dir: String = ProjectSettings.globalize_path("res://").path_join("../art-source/editable/spaceship-cabin/kenney-layout/previews").simplify_path()

func _initialize() -> void:
    DirAccess.make_dir_recursive_absolute(output_dir)
    run.call_deferred()

func shot(name: String) -> void:
    for frame: int in 40:
        await process_frame
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png(output_dir.path_join(name))
    print("FIRST_PERSON_CAPTURE " + name)

func run() -> void:
    root.size = Vector2i(1440, 900)
    var main: Main3D = load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(main)
    await process_frame
    main._ship_session.persistence_enabled = false
    main.network_port = 28165
    main._create_host()
    var player: SpacePlayer3D = main.players[1] as SpacePlayer3D
    player._camera_pitch_target = 0.04
    await shot("01-main-cabin.png")
    player.teleport_to(Vector3(5.0, 0.0, -11.1))
    player._camera_yaw_target = 0.35
    player._camera_pitch_target = -0.06
    await shot("02-bridge.png")
    player.teleport_to(ShipHub3D.REPAIR + Vector3(-0.5, 0, 0))
    player._camera_yaw_target = -PI / 2.0
    player._camera_pitch_target = 0.2
    await shot("03-workshop.png")
    main._ship_session.request("interact")
    await shot("04-facility.png")
    main._ship_session.close_panel()
    player.teleport_to(Vector3(12.2, 0, -2.98))
    player._camera_yaw_target = -PI / 2.0
    player._camera_pitch_target = 0.53
    await shot("05-floor-markings.png")
    player.teleport_to(Vector3(11.4, 0, 0.6))
    player._camera_yaw_target = 0.35
    player._camera_pitch_target = 0.1
    await shot("07-crew-compartment.png")
    player.teleport_to(Vector3(-1.8, 0, 10.5))
    player._camera_yaw_target = PI + 0.34
    player._camera_pitch_target = 0.0
    await shot("08-aft-airlock.png")
    player.teleport_to(ShipHub3D.AIRLOCK)
    main._ship_session.request("interact")
    await process_frame
    player = main.players[1] as SpacePlayer3D
    player.teleport_to(Vector3(-2.8, 0, 0.6))
    player._camera_yaw_target = 0.0
    player._camera_pitch_target = 0.5
    await shot("06-training-floor.png")
    main.queue_free()
    for frame: int in 3:
        await process_frame
    await RenderingServer.frame_post_draw
    print("FIRST_PERSON_CAPTURE_COMPLETE")
    quit(0)
