extends SceneTree

# 霜烬星美术检查：用真实渲染各存一张图，方便逐轮比较配色和明暗。
#
# 运行（在仓库根目录）：
#   godot --path game --rendering-method gl_compatibility --script res://tests/frost_art_capture.gd
#
# 输出到 builds/frost-art/。这几张图分别对应：
#   01_spawn    坠机点，玩家实际镜头高度
#   02_overview 正交俯瞰，用来看区域之间的明度差
#   03_tilted   斜俯瞰，用来看地貌和投影
#   04_at_lake  中央冰湖，用来看大块地表的读法
#   05_journal_map 日志里的地图页，用来和世界实际布局对照
#
# 本脚本只读场景、不改动玩法状态，也不会写进游戏存档。

const SHOT_DIR := "res://../builds/frost-art"

func _initialize() -> void:
    run.call_deferred()

func _shot(shot_name: String) -> void:
    await RenderingServer.frame_post_draw
    var output_dir := ProjectSettings.globalize_path(SHOT_DIR)
    DirAccess.make_dir_recursive_absolute(output_dir)
    root.get_texture().get_image().save_png(output_dir.path_join(shot_name + ".png"))
    print("saved ", shot_name)

func _run_frames(count: int) -> void:
    for index in count:
        await process_frame

func run() -> void:
    var main := load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(main)
    await process_frame
    # 换一个端口，避免和同时运行的主舱截图、联机测试抢同一个主机端口。
    main.network_port = 24571
    main._create_host()
    await process_frame
    main._start_planet()
    await _run_frames(120)
    await _shot("01_spawn")

    var overview := Camera3D.new()
    overview.projection = Camera3D.PROJECTION_ORTHOGONAL
    overview.size = 440.0
    overview.position = Vector3(0.0, 240.0, 0.6)
    overview.rotation_degrees = Vector3(-88.0, 0.0, 0.0)
    main.add_child(overview)
    overview.current = true
    await _run_frames(20)
    await _shot("02_overview")

    var tilted := Camera3D.new()
    tilted.projection = Camera3D.PROJECTION_ORTHOGONAL
    tilted.size = 250.0
    tilted.position = Vector3(0.0, 130.0, 120.0)
    tilted.rotation_degrees = Vector3(-46.0, 0.0, 0.0)
    main.add_child(tilted)
    tilted.current = true
    await _run_frames(20)
    await _shot("03_tilted")

    var player := main.players[1] as SpacePlayer3D
    if player != null:
        player.global_position = Vector3(0.0, 0.0, 0.0)
    await _run_frames(30)
    tilted.current = false
    if player != null and player._camera != null:
        player._camera.current = true
    await _run_frames(20)
    await _shot("04_at_lake")

    main._toggle_map()
    await _run_frames(20)
    var map_view = main._journal_map_view
    print("journal map: cliffs=", map_view.cliffs.size(), " pathways=", map_view.pathways.size(), " landmarks=", map_view.landmarks.size(), " map_size=", map_view.map_size)
    await _shot("05_journal_map")
    main._toggle_map()

    quit()
