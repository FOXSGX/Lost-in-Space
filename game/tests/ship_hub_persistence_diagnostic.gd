extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
    run.call_deferred()

func check(ok: bool, message: String) -> void:
    checks += 1
    if not ok:
        failures.append(message)
        push_error(message)

func run() -> void:
    var main := load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(main)
    await process_frame
    var ship := main._ship_session
    ship.persistence_enabled = false
    main.network_port = 24955 + int(Time.get_ticks_msec() % 40)
    main._create_host()
    await physics_frame
    ship.credits = 45
    ship.stock.medical = 7
    ship.save_path = "user://iteration-persistence-diagnostic.json"
    ship.persistence_enabled = true
    ship.save_state()
    var exists := FileAccess.file_exists(ship.save_path)
    var saved_text := ""
    if exists:
        var file := FileAccess.open(ship.save_path, FileAccess.READ)
        if file != null:
            saved_text = file.get_as_text()
            file.close()
    ship.stock.medical = 0
    ship.credits = 0
    ship.load_state()
    print("PERSISTENCE_DIAGNOSTIC host=%s path=%s exists=%s credits=%d medical=%d bytes=%d" % [main.is_host, ship.save_path, exists, ship.credits, ship.stock.medical, saved_text.length()])
    check(main.is_host, "诊断主机没有建立")
    check(exists, "save_state 没有生成诊断存档")
    check(ship.credits == 45 and ship.stock.medical == 7, "load_state 没有恢复诊断存档")
    if exists:
        DirAccess.remove_absolute(ship.save_path)
    print("SHIP_HUB_PERSISTENCE_DIAGNOSTIC: %d checks, %d failures" % [checks, failures.size()])
    quit(0 if failures.is_empty() else 1)
