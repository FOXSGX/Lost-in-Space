extends SceneTree

## Rendered evidence for the authored Resonance Star industrial asset set.
## It uses the real stage and keeps all gameplay state/anchors intact.

var output_dir: String = ""
var main: Main3D
var stage: ResonanceStage3D
var failures: int = 0

func _initialize() -> void:
    run.call_deferred()

func _camera(name: String, position: Vector3, target: Vector3, fov: float = 52.0) -> Camera3D:
    var camera: Camera3D = Camera3D.new()
    camera.name = name
    camera.projection = Camera3D.PROJECTION_PERSPECTIVE
    camera.fov = fov
    camera.position = position
    main.add_child(camera)
    camera.look_at(target, Vector3.UP)
    camera.current = true
    return camera

func _shot(label: String) -> void:
    for _frame in 2:
        await process_frame
    var image: Image = root.get_texture().get_image()
    var result: Error = image.save_png(output_dir.path_join(label + ".png"))
    if result != OK:
        failures += 1
    print("RESONANCE_ART_CAPTURE %s save=%d" % [label, result])

func _set_art_only() -> void:
    for control in [main._objective_panel, main._vitals_panel, main._compass_panel, main._interaction_panel, main._subtitle_panel, main._side_quest_panel, main._alert_label, main._hint_label, main._status_label, main._game_status_label]:
        if control != null:
            control.visible = false
    for node in stage.world_root.find_children("*", "Label3D", true, false):
        (node as Label3D).visible = false

func run() -> void:
    var args: PackedStringArray = OS.get_cmdline_user_args()
    output_dir = String(args[0]) if not args.is_empty() else "C:/Users/ASUS/Desktop/迷失太空/work/gameplay-iterations/20261016-resonance-art/planet-review"
    DirAccess.make_dir_recursive_absolute(output_dir)
    main = load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(main)
    await process_frame
    main._ship_session.persistence_enabled = false
    main.network_port = 25120 + int(Time.get_ticks_msec() % 200)
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

    var near_camera: Camera3D = _camera("ResonanceNearCamera", Vector3(-42.0, 5.8, 25.5), Vector3(-34.0, 1.4, 18.0), 50.0)
    await _shot("resonance-near-module")
    near_camera.current = false

    var reactor_camera: Camera3D = _camera("ResonanceReactorCamera", Vector3(82.0, 20.0, -1.0), Vector3(55.0, 6.5, -17.0), 50.0)
    await _shot("resonance-mid-reactor-tower")
    reactor_camera.current = false

    var overview: Camera3D = _camera("ResonanceOverviewCamera", Vector3(0.0, 116.0, 98.0), Vector3(0.0, 0.0, 0.0), 52.0)
    await _shot("resonance-far-overview")
    overview.current = false

    var core_camera: Camera3D = _camera("ResonanceCoreCamera", Vector3(82.0, 18.0, 0.0), Vector3(66.0, 1.8, -14.0), 55.0)
    await _shot("resonance-near-extraction")
    core_camera.current = false

    _set_art_only()
    var art_near: Camera3D = _camera("ResonanceArtOnlyNear", Vector3(-42.0, 5.8, 25.5), Vector3(-34.0, 1.4, 18.0), 50.0)
    await _shot("resonance-art-only-near-module")
    art_near.current = false
    var art_reactor: Camera3D = _camera("ResonanceArtOnlyReactor", Vector3(82.0, 20.0, -1.0), Vector3(55.0, 6.5, -17.0), 50.0)
    await _shot("resonance-art-only-reactor-tower")
    art_reactor.current = false
    var art_overview: Camera3D = _camera("ResonanceArtOnlyOverview", Vector3(0.0, 116.0, 98.0), Vector3(0.0, 0.0, 0.0), 52.0)
    await _shot("resonance-art-only-overview")
    art_overview.current = false

    var file: FileAccess = FileAccess.open(output_dir.path_join("art-capture-report.json"), FileAccess.WRITE)
    if file != null:
        file.store_string(JSON.stringify({
            "assets": stage.art_asset_nodes.keys(),
            "mesh_instances": stage.world_root.find_children("*", "MeshInstance3D", true, false).size(),
            "art_asset_count": stage.art_asset_nodes.size(),
            "failures": failures
        }, "  "))
        file.close()
    else:
        failures += 1
    print("RESONANCE_ART_CAPTURE: 7 images, %d failures" % failures)
    quit(0 if failures == 0 else 1)
