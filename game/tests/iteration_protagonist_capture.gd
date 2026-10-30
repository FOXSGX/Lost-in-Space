extends SceneTree

## 三个角度检查 Blender 版本的角色形象。

var output_dir: String = "C:/Users/ASUS/Desktop/迷失太空/work/gameplay-iterations/20261018-protagonist-blender"

func _initialize() -> void:
    run.call_deferred()

func _shot(label: String) -> void:
    for _frame in 3:
        await process_frame
    var image: Image = root.get_texture().get_image()
    image.resize(960, 540, Image.INTERPOLATE_BILINEAR)
    image.save_png(output_dir.path_join(label + ".png"))

func _camera(main: Main3D, position: Vector3, target: Vector3, fov: float = 40.0) -> Camera3D:
    var camera: Camera3D = Camera3D.new()
    camera.projection = Camera3D.PROJECTION_PERSPECTIVE
    camera.fov = fov
    camera.position = position
    main.add_child(camera)
    camera.look_at(target, Vector3.UP)
    camera.current = true
    return camera

func run() -> void:
    var args: PackedStringArray = OS.get_cmdline_user_args()
    if not args.is_empty():
        output_dir = String(args[0])
    DirAccess.make_dir_recursive_absolute(output_dir)
    var main: Main3D = load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(main)
    await process_frame
    main._ship_session.persistence_enabled = false
    main.network_port = 26410 + int(Time.get_ticks_msec() % 60)
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
    var player: SpacePlayer3D = main.players[1] as SpacePlayer3D
    player.set_physics_process(false)
    player.global_position = Vector3(-48.0, 0.4, 20.0)
    main._game_layer.visible = false
    player.rotation.y = 0.0
    main.kit_assignments[1] = "conduit"
    player.set_tool("conduit")
    await process_frame
    var focus: Vector3 = Vector3(-48.0, 1.02, 20.0)
    var front: Camera3D = _camera(main, Vector3(-48.0, 1.55, 16.9), focus)
    await _shot("protagonist-front")
    front.queue_free()
    var back: Camera3D = _camera(main, Vector3(-48.0, 1.25, 24.2), focus)
    await _shot("protagonist-back")
    back.queue_free()
    var side: Camera3D = _camera(main, Vector3(-43.8, 1.25, 20.0), focus)
    await _shot("protagonist-side")
    side.queue_free()
    print("PROTAGONIST_CAPTURE done")
    quit(0)
