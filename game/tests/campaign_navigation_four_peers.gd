extends SceneTree

class Driver extends Node:
    var main: Main3D
    var role: int = 0
    var peers: Dictionary = {}
    var acks: Dictionary = {}
    var checks: int = 0
    var failures: Array[String] = []

    func check(value: bool, message: String) -> void:
        checks += 1
        if not value:
            failures.append(message)
            print("FAIL ",message)

    func wait_for(predicate: Callable, seconds: float = 15.0) -> bool:
        var deadline: int = Time.get_ticks_msec() + int(seconds * 1000)
        while not predicate.call() and Time.get_ticks_msec() < deadline:
            await get_tree().create_timer(0.05).timeout
        return predicate.call()

    @rpc("any_peer", "call_remote", "reliable")
    func register(index: int) -> void:
        peers[index] = multiplayer.get_remote_sender_id()

    @rpc("any_peer", "call_remote", "reliable")
    func ack(step: String, index: int) -> void:
        acks[step + str(index)] = true

    @rpc("authority", "call_remote", "reliable")
    func verify(step: String) -> void:
        if step == "surface":
            check(await wait_for(func() -> bool: return main._campaign_travel.frost != null and main._campaign_travel.frost.players.size() == 4 and main._campaign_travel.frost.progress.flight), "four crew enter repaired surface")
        elif step == "board":
            check(await wait_for(func() -> bool: return main.ship_active and main.players.size() == 4 and main._ship_session.campaign.navigation_restored), "four crew board same campaign")
        elif step == "departed":
            check(await wait_for(func() -> bool: return main.game_started and main.current_planet_id == "electromagnetic" and main.players.size() == 4), "four crew land on same destination")
        ack.rpc_id(1,step,role)

    @rpc("authority", "call_remote", "reliable")
    func seat() -> void:
        var id: int = multiplayer.get_unique_id()
        var actor: SpacePlayer3D = main.players[id]
        actor.teleport_to(ShipDevices3D.point_for("pilot_%d" % role) + Vector3(0,0,1.3))
        actor.rotation.y = 0
        actor._camera_yaw_target = 0
        actor._camera_pitch_target = 0.12
        actor._publish_transform(false)
        await get_tree().create_timer(0.25).timeout
        main.handle_action(id,"interact")

    @rpc("authority", "call_remote", "reliable")
    func stop() -> void:
        main._show_home()
        finish()

    func ask(step: String) -> void:
        verify.rpc(step)
        check(await wait_for(func() -> bool: return acks.has(step + "1") and acks.has(step + "2") and acks.has(step + "3")), "all clients acknowledge " + step)

    func run() -> void:
        var args: PackedStringArray = OS.get_cmdline_user_args()
        role = int(args[0]) if not args.is_empty() else 0
        main = load("res://scenes/main_3d.tscn").instantiate() as Main3D
        main.name = "Game"
        add_child(main)
        await get_tree().process_frame
        main.network_port = 28404
        main._ship_session.persistence_enabled = false
        if role != 0:
            await get_tree().create_timer(0.4 + role * 0.15).timeout
            main._join_host()
            if not await wait_for(func() -> bool: return main.ship_active):
                check(false,"join grounded campaign")
                finish()
                return
            register.rpc_id(1,role)
            await get_tree().create_timer(50).timeout
            check(false,"four peer test timeout")
            finish()
            return
        main._create_campaign()
        check(await wait_for(func() -> bool: return peers.size() == 3 and main.players.size() == 4), "four real processes connect")
        main._campaign_travel.open_surface()
        var frost: Node3D = main._campaign_travel.frost
        frost.progress.installed = true
        frost.progress.flight = true
        await ask("surface")
        main._campaign_travel._on_board_requested(1)
        check(await wait_for(func() -> bool: return main.ship_active), "host boards four crew")
        await ask("board")
        var ship: ShipSession3D = main._ship_session
        ship._execute_device(1,{"kind":"route","item":"electromagnetic","title":"共振星","plan_revision":ship.campaign.revision})
        (main.players[1] as SpacePlayer3D).teleport_to(ShipDevices3D.point_for("pilot_0"))
        ship._toggle_station(1,0)
        seat.rpc()
        check(await wait_for(func() -> bool: return ship.ready_peers.size() == 4), "all four physical pilot seats become ready")
        check(await wait_for(func() -> bool: return main.game_started and main.current_planet_id == "electromagnetic"), "four player countdown departs")
        await ask("departed")
        stop.rpc()
        await get_tree().create_timer(0.3).timeout
        main._show_home()
        finish()

    func finish() -> void:
        print("CAMPAIGN_FOUR_RESULT role=",role," checks=",checks," failures=",failures.size())
        for message: String in failures:
            print("CAMPAIGN_FOUR_FAILED ",message)
        get_tree().quit(0 if failures.is_empty() else 1)

func _initialize() -> void:
    var driver: Driver = Driver.new()
    driver.name = "CampaignFour"
    root.add_child.call_deferred(driver)
    driver.run.call_deferred()
