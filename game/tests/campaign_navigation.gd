extends SceneTree

var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
    call_deferred("run")

func check(condition: bool, message: String) -> void:
    checks += 1
    if not condition:
        failures.append(message)
        print("FAIL ", message)

func frames(count: int = 4) -> void:
    for index: int in count:
        await physics_frame

func run() -> void:
    var model: CampaignNavigation = CampaignNavigation.new()
    model.start_new()
    check(model.location == "demo" and model.grounded and not model.navigation_restored, "new voyage starts stranded on frost")
    for destination: String in ["demo", "electromagnetic", "ruin", "earth", "unknown"]:
        check(not model.depart(destination), "cannot bypass core requirement: " + destination)
    var result: Dictionary = {"planet_id": "frost", "energy_state": "installed", "navigation_restored": true, "ordinary_fuel_salvaged": 2}
    model.accept_frost(result)
    model.accept_frost(result)
    check(model.energy == 0 and model.ordinary_fuel == 6 and model.navigation_restored, "installed core never duplicates stored energy or cumulative fuel")
    model.settle_planet("electromagnetic", false)
    check(model.energy == 0, "failed expedition gives no core")
    model.settle_planet("electromagnetic", true)
    model.settle_planet("electromagnetic", true)
    check(model.energy == 2 and model.supplies == 0 and not model.can_return_home(), "energy settles exactly once and supplies remain a distinct requirement")
    model.settle_planet("ruin", true, ["food_a", "food_a", "food_b"])
    check(model.supplies == 2 and model.can_return_home(), "ruin site IDs settle uniquely and complete finite home requirements")
    check(model.depart("earth") and model.home_reached and not model.depart("ruin"), "home requires explicit final departure and ends voyage")

    var main: Main3D = load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(main)
    await frames()
    main.network_port = 28401
    var ship: ShipSession3D = main._ship_session
    ship.persistence_enabled = false
    main._create_campaign()
    await frames()
    check(main.ship_active and ship.campaign.grounded and ship.selected_destination.is_empty(), "production new voyage enters grounded cabin without default flight")
    check(ship.device_room().devices.size() == 15, "surface computer exists alongside previous devices")
    ship._toggle_station(1, 0)
    check(ship.ready_peers.is_empty(), "damaged core blocks pilot readiness")
    main._campaign_travel.open_surface()
    await frames(8)
    var frost: Node3D = main._campaign_travel.frost
    check(frost != null and frost.players.has(1), "shared frost expedition instantiated")
    frost.test_mode = true
    check(frost._items.add_item(1, "heater", -1, {"charge": 87.0}), "real expedition inventory accepts heater")
    frost.world.ice[0].apply_amount(1.0)
    frost.progress.key = true
    frost.progress.energy = true
    frost.progress.opened_caches = ["rib_sled", "nest_overlook"]
    var core: Dictionary = {}
    for station: Dictionary in frost.world.stations:
        if station.kind == "core":
            core = station
    frost.use_station(1, core)
    check(frost.progress.installed and not frost.progress.energy and not frost.progress.flight, "installation consumes carried energy without leaving planet")
    frost.use_station(1, core)
    check(frost.progress.flight and main._campaign_travel.frost != null, "restoring navigation does not force departure")
    main._campaign_travel._on_board_requested(1)
    await frames(8)
    check(main.ship_active and main._campaign_travel.frost == null, "boarding restores cabin")
    check(ship.campaign.navigation_restored and ship.campaign.energy == 0, "frost result reaches authoritative campaign without duplicate energy")
    check(main._items.ensure_bag(1).slots[0].get("kind", "") == "heater", "carried heater survives boarding")
    check(is_equal_approx(float(main._items.ensure_bag(1).slots[0].get("charge", 0)), 87.0), "heater battery survives transfer")
    main._items._drop_selected(1)
    var heater_drop: Dictionary = main._items.drops[-1]
    check(main._items.pickup(1, heater_drop) and is_equal_approx(float(main._items.ensure_bag(1).slots[0].get("charge", 0)), 87.0), "cabin drop and pickup preserve heater battery")
    main._campaign_travel.open_surface()
    await frames(8)
    frost = main._campaign_travel.frost
    frost.test_mode = true
    check(frost.progress.flight and frost.progress.key and frost.world.ice[0].amount >= 0.99, "revisit retains core, key and melted world")
    check(frost._items.ensure_bag(1).slots[0].get("kind", "") == "heater", "revisit transfers loadout without replacing it")
    main._campaign_travel._on_board_requested(1)
    await frames(8)
    var version: int = ship.campaign.revision
    ship._execute_device(1, {"kind": "route", "item": "electromagnetic", "title": "共振星", "plan_revision": version})
    check(ship.selected_destination == "electromagnetic", "versioned plan commits")
    ship._execute_device(1, {"kind": "route", "item": "ruin", "title": "腐墟星", "plan_revision": version})
    check(ship.selected_destination == "electromagnetic", "stale plan cannot replace destination")
    (main.players[1] as SpacePlayer3D).teleport_to(ShipDevices3D.point_for("pilot_0"))
    ship._toggle_station(1, 0)
    ship.confirm_land()
    await frames(8)
    check(main.current_planet_id == "electromagnetic" and main.game_started, "existing pilot departure enters existing resonance planet")
    main.mission_completed = true
    main.return_to_ship.rpc("integration reward fixture")
    await frames(8)
    check(main.ship_active and ship.campaign.energy == 2 and ship.campaign.supplies == 2, "successful resonance return fills prototype home requirements")
    check(not ship.campaign.grounded and ship.campaign.location == "electromagnetic", "return to cabin correctly records orbital location")
    ship._execute_device(1, {"kind": "route", "item": "ruin", "title": "腐墟星", "plan_revision": ship.campaign.revision})
    (main.players[1] as SpacePlayer3D).teleport_to(ShipDevices3D.point_for("pilot_0"))
    ship._toggle_station(1, 0)
    ship.confirm_land()
    await frames(8)
    check(main.current_planet_id == "ruin" and main.game_started, "campaign can visit existing ruin planet")
    main._ruin_planet.taken_food = ["food_a"]
    main.handle_action(1, "interact")
    await frames(8)
    check(main.ship_active and ship.campaign.supplies == 3 and main._ruin_planet == null, "ruin return settles supplies and removes dormant colliders")

    ship.save_path = "user://navigation-test-%d.json" % Time.get_ticks_usec()
    ship.persistence_enabled = true
    ship.save_state()
    var saved_text: String = FileAccess.get_file_as_string(ship.save_path)
    ship.campaign.energy = 0
    check(ship.load_campaign() and ship.campaign.energy == 2 and ship.ready_peers.is_empty(), "save round trip restores campaign and clears readiness")
    var damaged: FileAccess = FileAccess.open(ship.save_path, FileAccess.WRITE)
    damaged.store_string("{\"version\":999,\"payload\":\"broken\"}")
    damaged.close()
    check(not ship.load_campaign(), "incompatible save rejected")
    check(FileAccess.get_file_as_string(ship.save_path).contains("999"), "rejected save is preserved")
    damaged = FileAccess.open(ship.save_path, FileAccess.WRITE)
    damaged.store_string(saved_text)
    damaged.close()
    check(ship.load_campaign(), "valid save remains recoverable")
    DirAccess.remove_absolute(ship.save_path)
    ship.persistence_enabled = false
    ship._execute_device(1, {"kind": "route", "item": "earth", "title": "地球", "plan_revision": ship.campaign.revision})
    (main.players[1] as SpacePlayer3D).teleport_to(ShipDevices3D.point_for("pilot_0"))
    ship._toggle_station(1, 0)
    ship.confirm_land()
    await frames(8)
    check(ship.campaign.home_reached and ship._computer.visible, "explicit all-ready flight opens home arrival record")
    main._show_home()
    main.queue_free()
    await frames(5)
    print("CAMPAIGN_NAVIGATION_RESULT checks=", checks, " failures=", failures.size())
    for message: String in failures:
        print("CAMPAIGN_NAVIGATION_FAILED: ", message)
    quit(1 if not failures.is_empty() else 0)
