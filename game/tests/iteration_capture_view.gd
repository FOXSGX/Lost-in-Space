extends SceneTree

const SHOT_DIR := "C:/Users/ASUS/Desktop/迷失太空/work/gameplay-iterations/20261014-181500-full-check/visuals/frost-overview"

func _initialize() -> void:
    run.call_deferred()

func _shot(name: String) -> void:
    await RenderingServer.frame_post_draw
    var image: Image = root.get_texture().get_image()
    image.save_png("%s/%s.png" % [SHOT_DIR, name])
    print("saved ", name)

func _run_frames(count: int) -> void:
    for i in count:
        await process_frame

func run() -> void:
    DirAccess.make_dir_recursive_absolute(SHOT_DIR)
    var main := load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(main)
    await process_frame
    main._create_host()
    await process_frame
    main._start_planet()
    await _run_frames(120)
    await _shot("01_spawn")

    # 俯瞰整张图
    var overview := Camera3D.new()
    overview.projection = Camera3D.PROJECTION_ORTHOGONAL
    overview.size = 440.0
    overview.position = Vector3(0.0, 240.0, 0.6)
    overview.rotation_degrees = Vector3(-88.0, 0.0, 0.0)
    main.add_child(overview)
    overview.current = true
    await _run_frames(20)
    await _shot("02_overview")

    # 斜俯视：接近玩家实际视角，但拉远一点看结构
    var tilted := Camera3D.new()
    tilted.projection = Camera3D.PROJECTION_ORTHOGONAL
    tilted.size = 250.0
    tilted.position = Vector3(0.0, 130.0, 120.0)
    tilted.rotation_degrees = Vector3(-46.0, 0.0, 0.0)
    main.add_child(tilted)
    tilted.current = true
    await _run_frames(20)
    await _shot("03_tilted")

    # 传送到中央冰湖，看玩家在中段实际能见到的范围
    var player := main.players[1] as SpacePlayer3D
    if player != null:
        player.global_position = Vector3(0.0, 0.0, 0.0)
    await _run_frames(30)
    tilted.current = false
    if player != null and player._camera != null:
        player._camera.current = true
    await _run_frames(20)
    await _shot("04_at_lake")

    quit()

