extends SceneTree

var output_dir: String = ""
var main: Main3D
var stage: ResonanceStage3D
var camera: Camera3D

func _initialize() -> void:
    run.call_deferred()

func shot(label: String) -> void:
    for _frame in 3:
        await process_frame
    root.get_texture().get_image().save_png(output_dir.path_join(label + ".png"))

func run() -> void:
    var args: PackedStringArray = OS.get_cmdline_user_args()
    output_dir = String(args[0]) if not args.is_empty() else "C:/Users/ASUS/Desktop/迷失太空/work/gameplay-iterations/20261017-resonance-coop-iteration46/relay-capture"
    DirAccess.make_dir_recursive_absolute(output_dir)
    main = load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(main)
    await process_frame
    main._ship_session.persistence_enabled = false
    main.network_port = 25480 + int(Time.get_ticks_msec() % 80)
    main._create_host()
    main.connected_ids = [1, 2]
    main._start_planet("electromagnetic")
    await process_frame
    stage = main._resonance_stage
    main.set_process(false)
    for player_value in main.players.values():
        var player: SpacePlayer3D = player_value as SpacePlayer3D
        if player != null:
            player.set_physics_process(false)
    stage.heat_chain_complete = true
    stage.checkpoint = 1
    stage.modules[0]["state"] = "docked"
    stage.modules[0]["phase"] = "docked"
    stage.modules[1]["state"] = "ready"
    stage.modules[1]["phase"] = "ready"
    stage._refresh_objective_guide()
    camera = Camera3D.new()
    camera.name = "SupportRelayReviewCamera"
    camera.projection = Camera3D.PROJECTION_PERSPECTIVE
    camera.fov = 54.0
    camera.position = Vector3(22.0, 10.5, 9.0)
    main.add_child(camera)
    camera.look_at(Vector3(8.0, 1.2, -2.0), Vector3.UP)
    camera.current = true
    await shot("relay-before")
    var first: SpacePlayer3D = main.players[1] as SpacePlayer3D
    var second: SpacePlayer3D = main.players[2] as SpacePlayer3D
    first.global_position = stage.SUPPORT_RELAY_LOW_POSITION
    main.handle_action(1, "repair")
    stage.stage_tick(0.2)
    await shot("relay-low-active")
    second.global_position = stage.SUPPORT_RELAY_HIGH_POSITION
    main.handle_action(2, "repair")
    stage.stage_tick(0.2)
    await shot("relay-complete")
    print("RESONANCE_COOP_RELAY_CAPTURE: 3 images, unlocked=", stage.shortcut_unlocked)
    quit(0 if stage.shortcut_unlocked else 1)
