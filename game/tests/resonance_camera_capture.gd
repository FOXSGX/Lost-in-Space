extends SceneTree

var output_dir: String = ""
var failures: int = 0
var main: Main3D
var stage: ResonanceStage3D

func _initialize() -> void:
    run.call_deferred()

func capture(label: String) -> void:
    for _frame in 3:
        await process_frame
    var image: Image = root.get_texture().get_image()
    var result: Error = image.save_png(output_dir.path_join(label + ".png"))
    if result != OK:
        failures += 1
    print("RESONANCE_CAMERA_CAPTURE %s save=%d" % [label, result])

func settle_player_camera(point: Vector3) -> void:
    var player: SpacePlayer3D = main.players[1] as SpacePlayer3D
    player.global_position = point
    for _frame in 16:
        player._process(0.05)
        await process_frame

func run() -> void:
    var args: PackedStringArray = OS.get_cmdline_user_args()
    output_dir = String(args[0]) if not args.is_empty() else "C:/Users/ASUS/Desktop/迷失太空/work/gameplay-iterations/20261017-resonance-camera/planet-review"
    DirAccess.make_dir_recursive_absolute(output_dir)
    main = load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(main)
    await process_frame
    main._ship_session.persistence_enabled = false
    main.network_port = 25210 + int(Time.get_ticks_msec() % 100)
    main._create_host()
    main.connected_ids = [1, 2]
    main.spawn_player_for_peer(2)
    main._start_planet("electromagnetic")
    await process_frame
    stage = main._resonance_stage
    main.set_process(false)
    for player_value in main.players.values():
        var player: SpacePlayer3D = player_value as SpacePlayer3D
        if player != null:
            player.set_physics_process(false)
    await settle_player_camera(Vector3(-34.0, 0.0, 18.0))
    await capture("resonance-player-camera-module")
    await settle_player_camera(Vector3(55.0, 0.0, -17.0))
    await capture("resonance-player-camera-reactor")
    var file: FileAccess = FileAccess.open(output_dir.path_join("camera-capture-report.json"), FileAccess.WRITE)
    if file != null:
        file.store_string(JSON.stringify({
            "failures": failures,
            "camera_distance": SpacePlayer3D.THIRD_PERSON_DISTANCE,
            "camera_height": SpacePlayer3D.THIRD_PERSON_HEIGHT,
            "fade_removed": not ("camera_fade_cache" in stage)
        }, "  "))
        file.close()
    else:
        failures += 1
    print("RESONANCE_CAMERA_CAPTURE: 2 images, %d failures" % failures)
    quit(0 if failures == 0 else 1)
