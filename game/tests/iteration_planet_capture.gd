extends SceneTree

var main: Main3D
var output := ""
var records: Array[Dictionary] = []
var failures := 0

func _initialize() -> void:
    run.call_deferred()

func shot(label: String) -> void:
    main._update_hud()
    for frame in 8:
        await process_frame
    await RenderingServer.frame_post_draw
    var picture := root.get_texture().get_image()
    var code := picture.save_png(output.path_join(label + ".png"))
    if code != OK:
        failures += 1
    records.append({"image": label + ".png", "save_error": code, "planet": main.current_planet_id, "objective": main._progress_label.text, "hint": main._interaction_label.text, "alert": main._alert_label.text, "journal": main._journal_label.text})
    print("PLANET_CAPTURE %s save=%d" % [label, code])

func run() -> void:
    output = OS.get_cmdline_user_args()[0]
    DirAccess.make_dir_recursive_absolute(output)
    main = load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(main)
    await process_frame
    main._ship_session.persistence_enabled = false
    main.network_port = 24945
    main._create_host()
    main._start_planet("demo")
    main.set_process(false)
    var player := main.players[1] as SpacePlayer3D
    player.set_physics_process(false)
    await shot("frost-01-fresh-arrival")
    var beacon := Vector2(main.beacon_positions[0])
    player.teleport_to(Vector3(beacon.x, 0, beacon.y))
    main.handle_action(1, "repair")
    # 观察主线阻挡文字；不直接设置已解锁知识。
    print("FROST_BLOCK_REASON " + main._beacon_block_reason())
    await shot("frost-02-first-beacon")
    main._toggle_journal()
    await shot("frost-03-journal")
    main._toggle_journal()
    main._toggle_map()
    await shot("frost-04-map")
    main._toggle_map()
    var field := main._field_interactions
    player.teleport_to(field.nodes["emergency_locker"].global_position + Vector3(0.8, 0, 0.8))
    main.handle_action(1, "repair")
    field.tick(0.8)
    await shot("frost-05-interaction")
    player.teleport_to(player.position + Vector3(5, 0, 0))
    field.tick(0.1)
    await shot("frost-06-interrupted")

    # 等待关键反馈动画完成，避免返航清理世界时异步浮字回调引用已释放节点。
    await create_timer(1.2).timeout
    main.return_to_ship("截图检查返航；不代表完整通关")
    await process_frame
    main._start_planet("electromagnetic")
    player = main.players[1] as SpacePlayer3D
    player.set_physics_process(false)
    await shot("resonance-01-arrival")
    var stage: ResonanceStage3D = main._resonance_stage
    player.teleport_to(Vector3(stage.stations[0]["rail_position"]))
    await shot("resonance-02-conduit")
    main.handle_action(1, "resonance_drone")
    main.handle_action(1, "repair")
    stage.stage_tick(0.2)
    await shot("resonance-03-drone")
    var overview := Camera3D.new()
    overview.projection = Camera3D.PROJECTION_ORTHOGONAL
    overview.size = 143.0
    overview.position = Vector3(0, 130, 0.4)
    overview.rotation_degrees = Vector3(-89, 0, 0)
    main.add_child(overview)
    overview.current = true
    await shot("resonance-04-map-overview")
    overview.current = false
    player._camera.current = true
    main._toggle_journal()
    await shot("resonance-05-journal")
    var file := FileAccess.open(output.path_join("ui-observations.json"), FileAccess.WRITE)
    if file != null:
        file.store_string(JSON.stringify(records, "  "))
        file.close()
    else:
        failures += 1
    print("PLANET_CAPTURE: %d images, %d failures" % [records.size(), failures])
    quit(0 if failures == 0 else 1)
