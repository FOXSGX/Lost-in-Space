extends SceneTree

class Driver extends Node:
    var main: Main3D
    var client: bool = false
    var peer_id: int = 0
    var checks: int = 0
    var failures: Array[String] = []
    var acknowledgements: Dictionary = {}

    func check(value: bool, label: String) -> void:
        checks += 1
        if not value:
            failures.append(label)
            print("FAIL ",label)

    func wait_for(predicate: Callable, seconds: float = 12.0) -> bool:
        var deadline: int = Time.get_ticks_msec() + int(seconds * 1000)
        while not predicate.call() and Time.get_ticks_msec() < deadline:
            await get_tree().create_timer(0.05).timeout
        return predicate.call()

    @rpc("any_peer", "call_remote", "reliable")
    func register() -> void:
        peer_id = multiplayer.get_remote_sender_id()

    @rpc("any_peer", "call_remote", "reliable")
    func acknowledge(step: String) -> void:
        acknowledgements[step] = true

    @rpc("authority", "call_remote", "reliable")
    func verify(step: String) -> void:
        var my_id: int = multiplayer.get_unique_id()
        if step == "surface" or step == "late_surface":
            check(await wait_for(func() -> bool: return main._campaign_travel.frost != null and main._campaign_travel.frost.players.size() == 2), "client receives surface subtree and crew")
            check(await wait_for(func() -> bool: return main._campaign_travel.frost.progress.flight), "client inherits repaired core")
            check(await wait_for(func() -> bool: return main._campaign_travel.frost.world.ice[0].amount >= 0.99), "client inherits melted world")
        elif step == "pickup":
            main._campaign_travel.frost.handle_action(my_id, "interact")
            check(await wait_for(func() -> bool: return main._campaign_travel.frost._items.count_kind(my_id, "oxygen") == 1), "client real pickup reaches host and returns in snapshot")
        elif step == "board":
            check(await wait_for(func() -> bool: return main.ship_active and main.players.size() == 2), "client boards same ship")
            check(main._ship_session.campaign.navigation_restored and main._ship_session.campaign.energy == 0, "client receives canonical campaign ledger")
            check(main._items.count_kind(my_id, "oxygen") == 1, "client loadout transfers to cabin")
        elif step == "pilot":
            var actor: SpacePlayer3D = main.players[my_id]
            actor.teleport_to(ShipDevices3D.point_for("pilot_1") + Vector3(0,0,1.3))
            actor.rotation.y = 0
            actor._camera_yaw_target = 0
            actor._camera_pitch_target = 0.12
            actor.sync_transform.rpc(actor.position, false, 0)
            await get_tree().create_timer(0.2).timeout
            main.handle_action(my_id, "interact")
            check(await wait_for(func() -> bool: return main._ship_session.ready_peers.has(my_id)), "client E joins pilot seat")
        elif step == "departed":
            check(await wait_for(func() -> bool: return main.game_started and main.current_planet_id == "electromagnetic"), "client lands on same resonance destination")
        acknowledge.rpc_id(1,step)

    @rpc("authority", "call_remote", "reliable")
    func reconnect() -> void:
        main._show_home()
        await get_tree().create_timer(0.65).timeout
        main._join_host()
        check(await wait_for(func() -> bool: return main.ship_active or main._campaign_travel.frost != null), "rejoin existing voyage")
        register.rpc_id(1)

    @rpc("authority", "call_remote", "reliable")
    func finish_remote() -> void:
        main._show_home()
        finish()

    func ask(step: String) -> void:
        acknowledgements.erase(step)
        verify.rpc_id(peer_id,step)
        check(await wait_for(func() -> bool: return acknowledgements.has(step)), "client step acknowledged: " + step)

    func run() -> void:
        client = "--client" in OS.get_cmdline_user_args()
        main = load("res://scenes/main_3d.tscn").instantiate() as Main3D
        main.name = "Game"
        add_child(main)
        await get_tree().process_frame
        main.network_port = 28402
        main._ship_session.persistence_enabled = false
        if client:
            await get_tree().create_timer(0.5).timeout
            main._join_host()
            if not await wait_for(func() -> bool: return main.ship_active):
                check(false,"initial join")
                finish()
                return
            register.rpc_id(1)
            await get_tree().create_timer(55).timeout
            check(false,"network test timeout")
            finish()
            return
        main._create_campaign()
        check(await wait_for(func() -> bool: return main.players.size() == 2 and peer_id != 0), "two real peers join grounded campaign")
        main._campaign_travel.open_surface()
        check(await wait_for(func() -> bool: return main._campaign_travel.frost != null), "host enters shared surface")
        var frost: Node3D = main._campaign_travel.frost
        frost.progress.key = true
        frost.progress.installed = true
        frost.progress.flight = true
        frost.world.ice[0].apply_amount(1.0)
        await ask("surface")
        (frost.players[peer_id] as SpacePlayer3D).teleport_to(Vector3(-6,0.8,-8.7))
        await get_tree().create_timer(0.3).timeout
        await ask("pickup")
        check(frost._items.count_kind(peer_id, "oxygen") == 1, "host stores exactly one oxygen after client request")
        main._campaign_travel._on_board_requested(1)
        check(await wait_for(func() -> bool: return main.ship_active), "host boards with full team")
        await ask("board")
        var ship: ShipSession3D = main._ship_session
        ship._execute_device(1, {"kind":"route","item":"electromagnetic","title":"共振星","plan_revision":ship.campaign.revision})
        (main.players[1] as SpacePlayer3D).teleport_to(ShipDevices3D.point_for("pilot_0"))
        ship._toggle_station(1,0)
        await ask("pilot")
        check(ship.all_ready(), "both seats are ready")
        var old_peer: int = peer_id
        peer_id = 0
        reconnect.rpc_id(old_peer)
        check(await wait_for(func() -> bool: return main.connected_ids.size() == 1), "disconnect observed")
        check(ship.ready_peers.is_empty() and ship.launch_remaining < 0 and main.ship_active, "disconnect aborts countdown and clears old readiness")
        check(await wait_for(func() -> bool: return peer_id != 0 and main.players.size() == 2), "client reconnects in cabin")
        check(main._items.count_kind(peer_id, "oxygen") == 0, "reconnect does not duplicate former loadout")
        main._campaign_travel.open_surface()
        check(await wait_for(func() -> bool: return main._campaign_travel.frost != null), "surface reentry")
        old_peer = peer_id
        peer_id = 0
        reconnect.rpc_id(old_peer)
        check(await wait_for(func() -> bool: return main.connected_ids.size() == 1), "surface disconnect observed")
        check(await wait_for(func() -> bool: return peer_id != 0 and main._campaign_travel.frost.players.size() == 2), "late join recreates surface RPC tree")
        await ask("late_surface")
        main._campaign_travel._on_board_requested(1)
        check(await wait_for(func() -> bool: return main.ship_active and main.players.size() == 2), "both peers return after late join")
        (main.players[1] as SpacePlayer3D).teleport_to(ShipDevices3D.point_for("pilot_0"))
        ship._toggle_station(1,0)
        await ask("pilot")
        check(await wait_for(func() -> bool: return main.game_started and main.current_planet_id == "electromagnetic"), "two-player countdown starts existing resonance")
        await ask("departed")
        finish_remote.rpc_id(peer_id)
        await get_tree().create_timer(0.3).timeout
        main._show_home()
        finish()

    func finish() -> void:
        print("CAMPAIGN_NETWORK_RESULT role=", "client" if client else "host", " checks=", checks, " failures=", failures.size())
        for failure: String in failures:
            print("CAMPAIGN_NETWORK_FAILED ",failure)
        get_tree().quit(1 if not failures.is_empty() else 0)

func _initialize() -> void:
    var driver: Driver = Driver.new()
    driver.name = "CampaignNetwork"
    root.add_child.call_deferred(driver)
    driver.run.call_deferred()
