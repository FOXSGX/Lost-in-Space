extends SceneTree

const OUTPUT := "res://../builds/ship-cabin-preview"

func _initialize() -> void:
    run.call_deferred()

func shot(file_name: String) -> void:
    for frame in 55:
        await process_frame
    await RenderingServer.frame_post_draw
    var output_dir := ProjectSettings.globalize_path(OUTPUT)
    DirAccess.make_dir_recursive_absolute(output_dir)
    root.get_texture().get_image().save_png(output_dir.path_join(file_name))

func run() -> void:
    var main := load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(main)
    await process_frame
    var ship := main._ship_session
    ship.persistence_enabled = false
    main.network_port = 24570
    main._create_host()
    await shot("01-main-hub.png")
    var player := main.players[1] as SpacePlayer3D
    player.teleport_to(ShipHub3D.STORAGE)
    await shot("06-cargo-walk.png")
    ship.request("interact")
    await shot("02-storage.png")
    ship.close_panel()
    player.teleport_to(ShipHub3D.REPAIR)
    await shot("07-repair-walk.png")
    ship.request("interact")
    await shot("03-repair.png")
    ship.request("repair")
    ship.close_panel()
    player.teleport_to(ShipHub3D.SUPPLY)
    ship.request("interact")
    await shot("04-supply.png")
    ship.close_panel()
    player.teleport_to(ShipHub3D.COCKPIT)
    await shot("08-bridge-walk.png")
    ship.request("interact")
    await shot("05-route.png")
    print("SHIP_CABIN_CAPTURE_OK")
    quit()
