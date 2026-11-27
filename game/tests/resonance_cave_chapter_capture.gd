extends SceneTree

var output_dir := "C:/Users/ASUS/Desktop/迷失太空/work/gameplay-iterations/20261018-resonance-cave-reframe/planet-review/cave-chapter"
var main: Main3D
var stage: ResonanceCaveChapter3D

func _initialize() -> void:
    call_deferred("run_capture")

func _shot(label: String) -> void:
    for _frame in 12:
        await process_frame
    # Headless CI does not always emit frame_post_draw; process frames are
    # sufficient after the camera has been made current.
    await process_frame
    var image := root.get_texture().get_image()
    image.resize(1280, 720, Image.INTERPOLATE_BILINEAR)
    image.save_png(output_dir.path_join(label + ".png"))
    print("CAVE_CAPTURE %s" % label)

func _run_room(label: String, focus: Vector3, room: int) -> void:
    stage.cave_room = room
    var player_one := main.players.get(1) as SpacePlayer3D
    var player_two := main.players.get(2) as SpacePlayer3D
    player_one.set_physics_process(false)
    player_two.set_physics_process(false)
    var player_anchor := Vector3(focus.x, 0.2, 0.0)
    if room == 0:
        player_anchor = Vector3(-4.0, 0.2, 0.0)
    elif room == 1:
        player_anchor = Vector3(34.0, 0.2, 0.0)
    else:
        player_anchor = Vector3(70.0, 0.2, 0.0)
    player_one.teleport_to(player_anchor + Vector3(-3.0, 0.0, -2.0))
    player_two.teleport_to(player_anchor + Vector3(2.8, 0.0, 2.4))
    var cinema := Camera3D.new()
    cinema.name = "CaveReviewCamera"
    var camera_position := Vector3(focus.x, maxf(focus.y - 1.0, 4.0), 0.0)
    var camera_target := Vector3(focus.x + 16.0, 2.0, 0.0)
    if room == 0:
        camera_position = Vector3(-6.0, 7.0, 6.0)
        camera_target = Vector3(8.0, 2.0, 0.0)
    elif room == 1:
        camera_position = Vector3(27.0, 6.0, 0.0)
        camera_target = Vector3(47.0, 2.0, 0.0)
    else:
        camera_position = Vector3(52.0, 7.0, 0.0)
        camera_target = Vector3(78.0, 2.0, 0.0)
    cinema.position = camera_position
    main.add_child(cinema)
    cinema.look_at(camera_target, Vector3.UP)
    cinema.current = true
    if stage != null and stage.has_method("update_camera_occlusion"):
        stage.update_camera_occlusion(cinema.global_position, camera_target)
    await _shot(label)
    cinema.queue_free()

func _feedback_shot(label: String, camera_position: Vector3, camera_target: Vector3) -> void:
    var cinema := Camera3D.new()
    cinema.name = "CaveFeedbackReviewCamera"
    cinema.fov = 58.0
    main.add_child(cinema)
    cinema.position = camera_position
    cinema.look_at(camera_target, Vector3.UP)
    cinema.current = true
    if stage != null and stage.has_method("update_camera_occlusion"):
        stage.update_camera_occlusion(cinema.global_position, camera_target)
    await _shot(label)
    cinema.queue_free()
    var player_camera := main.players.get(1) as SpacePlayer3D
    if player_camera != null and player_camera._camera != null:
        player_camera._camera.current = true

func run_capture() -> void:
    DirAccess.make_dir_recursive_absolute(output_dir)
    main = load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(main)
    await process_frame
    main._ship_session.persistence_enabled = false
    main.network_port = 24960 + int(Time.get_ticks_msec() % 50)
    main._create_host()
    main.connected_ids = [1, 2]
    main._start_planet("electromagnetic")
    await process_frame
    await process_frame
    stage = main._resonance_stage as ResonanceCaveChapter3D
    if stage == null:
        print("CAVE_CAPTURE failed: stage missing")
        quit(1)
        return
    await _run_room("01-entrance", Vector3(-4.0, 8.0, 8.0), 0)
    await _run_room("02-mineral-corridor", Vector3(32.0, 6.0, 5.0), 1)
    await _run_room("03-crystal-chamber", Vector3(72.0, 10.0, 12.0), 2)
    stage.cave_room = 0
    var player_camera := main.players.get(1) as SpacePlayer3D
    var partner_camera := main.players.get(2) as SpacePlayer3D
    player_camera.teleport_to(Vector3(-8.0, 0.2, 0.0))
    partner_camera.teleport_to(Vector3(-5.0, 0.2, 2.4))
    player_camera.rotation.y = -PI * 0.5
    player_camera._camera_yaw = -PI * 0.5
    player_camera._camera_yaw_target = -PI * 0.5
    player_camera._camera_pitch = -0.18
    player_camera._camera_pitch_target = -0.18
    player_camera._camera.current = true
    await _shot("05-player-camera-entrance")

    stage.cave_room = 1
    stage.cave_task_one_done = true
    stage.cave_task_two_done = false
    player_camera.teleport_to(Vector3(30.0, 0.2, -1.8))
    partner_camera.teleport_to(Vector3(36.0, 0.2, 2.0))
    await _shot("06-player-camera-corridor")
    stage.cave_room = 2
    stage.cave_task_two_done = true
    stage._set_cave_gate_open(1, true)
    if stage.cave_feedback != null:
        stage.cave_feedback.set_gate_open_instant(1)
    player_camera.teleport_to(Vector3(62.0, 0.2, -2.0))
    partner_camera.teleport_to(Vector3(70.0, 0.2, 2.5))
    await _shot("07-player-camera-chamber")

    if stage.cave_feedback != null:
        # Stop the main tick/snapshot loop for deterministic review frames;
        # the feedback layer is driven directly here so task state cannot
        # override the single-trigger frame with a completed state.
        main.set_process(false)
        stage.cave_feedback.reset_all()
        stage.cave_room = 0
        stage.cave_task_one_done = false
        stage.cave_task_two_done = false
        stage.cave_task_three_done = false
        stage.cave_power_peer = 1
        stage.cave_clamp_peer = 0
        stage.cave_relay_entry_peer = 0
        stage.cave_relay_exit_peer = 0
        stage.cave_freight_peer = 0
        stage.cave_stabilizer_peer = 0
        stage.update_hud(player_camera)
        stage.cave_feedback.play_activation("power", 1)
        await _feedback_shot("08-entrance-single-feedback", Vector3(-4.5, 5.6, 4.8), Vector3(-9.0, 1.6, 0.0))

        stage.cave_clamp_peer = 2
        stage.cave_task_one_done = true
        stage.cave_room = 0
        stage.update_hud(player_camera)
        stage.cave_feedback.play_activation("clamp", 2)
        stage.cave_feedback.play_task_complete(1, {"power": 1, "clamp": 2})
        stage.cave_feedback.play_gate_open(0)
        await _feedback_shot("09-entrance-gate-open", Vector3(4.0, 4.8, 3.5), Vector3(12.1, 3.0, 0.0))

        stage.cave_relay_entry_peer = 1
        stage.cave_relay_exit_peer = 2
        stage.cave_task_two_done = true
        stage.cave_room = 1
        stage.update_hud(player_camera)
        stage.cave_feedback.play_task_complete(2, {"relay_entry": 1, "relay_exit": 2})
        stage.cave_feedback.play_gate_open(1)
        await _feedback_shot("10-tunnel-relay-complete", Vector3(26.0, 4.8, 3.2), Vector3(43.0, 2.0, 0.0))
        await create_timer(0.9).timeout

        stage.cave_freight_peer = 1
        stage.cave_stabilizer_peer = 2
        stage.cave_task_three_done = true
        stage.cave_room = 2
        stage.update_hud(player_camera)
        stage.cave_feedback.play_task_complete(3, {"freight": 1, "stabilizer": 2})
        await _feedback_shot("11-chamber-calibrated", Vector3(64.0, 7.5, -8.0), Vector3(76.0, 2.8, 3.5))

        stage.cave_feedback.reset_all()
        stage.cave_feedback.play_tool_action("conduit", "power", Vector3(-6.0, 0.2, 2.0), Vector3(-9.0, 0.2, 0.0), 1)
        await _feedback_shot("12-conduit-energy-beam", Vector3(-4.5, 5.4, 4.8), Vector3(-9.0, 1.6, 0.0))
        stage.cave_feedback.play_tool_action("hook", "clamp", Vector3(2.0, 0.2, 2.0), Vector3(5.0, 0.2, 0.0), 2)
        await _feedback_shot("13-hook-connection-pull", Vector3(0.0, 5.2, 4.8), Vector3(5.0, 1.6, 0.0))
        stage.cave_feedback.play_tool_action("scanner", "scan_route", Vector3(31.0, 0.2, 0.0), Vector3(33.0, 0.2, -3.6), 3)
        await _feedback_shot("14-scanner-hidden-route", Vector3(27.0, 4.8, 3.2), Vector3(39.0, 1.4, -1.5))
        stage.cave_feedback.play_tool_action("shield", "shield_window", Vector3(2.0, 0.2, -4.0), Vector3(2.0, 0.2, -6.0), 4)
        await _feedback_shot("15-shield-safety-window", Vector3(-2.0, 5.2, 4.0), Vector3(2.0, 1.8, -6.0))
        stage.cave_feedback.play_evacuation(ResonanceCaveChapter3D.CAVE_EXIT_POSITION, 3.0)
        await _feedback_shot("16-collapse-evacuation", Vector3(60.0, 8.0, 8.0), Vector3(80.0, 2.0, 0.0))

    var overview := Camera3D.new()
    overview.name = "CaveChapterOverviewCamera"
    overview.projection = Camera3D.PROJECTION_ORTHOGONAL
    overview.size = 128.0
    overview.position = Vector3(36.0, 145.0, 0.0)
    overview.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
    main.add_child(overview)
    overview.current = true
    await _shot("04-route-overview")
    quit(0)
