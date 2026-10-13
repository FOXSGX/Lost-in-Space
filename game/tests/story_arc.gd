extends SceneTree

var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
    checks += 1
    if not condition:
        failures += 1
        push_error(message)

func _initialize() -> void:
    run.call_deferred()

func run() -> void:
    var main := load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(main)
    await process_frame
    main.network_port = 25841
    main._ship_session.persistence_enabled = false
    main._create_host()
    main._start_planet()
    main.set_process(false)

    check(main._story_progress_count() == 0, "故事档案在登陆时不应提前完成")
    main._story_beat("arc_arrival", "测试档案 · 登陆", "测试记录", "测试旁白", 1.0)
    check(main.story_flags.has("arc_arrival"), "故事档案没有保存节点标记")
    check(main._story_progress_count() == 1, "日志故事进度没有增加")
    var journal_size := main.journal_entries.size()
    main._story_beat("arc_arrival", "测试档案 · 登陆", "测试记录", "测试旁白", 1.0)
    check(main.journal_entries.size() == journal_size, "重复触发故事档案产生了重复记录")

    main._apply_landmark_knowledge("weather_station")
    check(main.story_flags.has("arc_weather_station"), "气象站调查没有接入故事档案")
    check(main._story_progress_count() == 2, "地标故事节点没有计入进度")
    check("故事档案：" in main._journal_label.text and "2 /" in main._journal_label.text, "日志没有显示故事档案进度")

    var snapshot := main._world_snapshot()
    var restored := load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(restored)
    await process_frame
    restored.sync_full_state(snapshot)
    check(restored.story_flags.has("arc_arrival") and restored.story_flags.has("arc_weather_station"), "中途加入快照没有恢复故事节点")
    check(restored._story_progress_count() == 2, "恢复快照后故事进度不一致")

    print("故事线测试：%d 项检查，%d 项失败" % [checks, failures])
    quit(0 if failures == 0 else 1)
