extends SceneTree

var output_dir: String = ""
var main: Main3D
var stage: ResonanceStage3D
var player: SpacePlayer3D

func _initialize() -> void:
    run.call_deferred()

func capture(label: String) -> void:
    for _frame in 2:
        await process_frame
    var image: Image = root.get_texture().get_image()
    image.save_png(output_dir.path_join(label + ".png"))

func settle_camera() -> void:
    for _frame in 4:
        player._process(0.05)
        await process_frame

func run() -> void:
    var args: PackedStringArray = OS.get_cmdline_user_args()
    output_dir = String(args[0]) if not args.is_empty() else "C:/Users/ASUS/Desktop/迷失太空/work/gameplay-iterations/20261018-resonance-cliff/planet-review-iteration38"
    DirAccess.make_dir_recursive_absolute(output_dir)
    main = load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(main)
    await process_frame
    main._ship_session.persistence_enabled = false
    main.network_port = 25330 + int(Time.get_ticks_msec() % 100)
    main._create_host()
    main.connected_ids = [1]
    main._start_planet("electromagnetic")
    await process_frame
    stage = main._resonance_stage
    player = main.players[1] as SpacePlayer3D
    main.set_process(false)
    player.set_physics_process(false)
    player.global_position = Vector3(-39.2, 0.0, 26.0)
    await settle_camera()
    await capture("resonance-cliff-fall-before")
    stage.stage_tick(0.10)
    if not player.falling_to_lava:
        player.begin_resonance_fall()
    if player.falling_to_lava:
        player._tick_resonance_fall(0.10)
    await settle_camera()
    await capture("resonance-cliff-fall-mid")
    var remaining: float = 0.85
    while remaining > 0.0:
        var delta: float = minf(remaining, 0.05)
        stage.stage_tick(delta)
        if player.falling_to_lava:
            player._tick_resonance_fall(delta)
        remaining -= delta
    await settle_camera()
    await capture("resonance-cliff-fall-impact")
    print("RESONANCE_CLIFF_FALL_CAPTURE: 3 images, falling=", player.falling_to_lava, " lava_dead=", player.lava_dead)
    quit(0 if player.lava_dead else 1)
