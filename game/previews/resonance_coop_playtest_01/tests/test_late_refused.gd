extends "res://tests/app_driver.gd"

func run() -> void:
    await launch_app()
    await click("加入房间")
    (app.get("address") as LineEdit).text = "127.0.0.1"
    (app.get("port_input") as LineEdit).text = "26843"
    await click("连接房间")
    var deadline: int = Time.get_ticks_msec() + 14000
    while str(app.get("screen")) != "main" and Time.get_ticks_msec() < deadline: await frames(1)
    ui_check(str(app.get("screen")) == "main" and app.get("stage") == null, "任务已开始时新玩家被拒绝并返回菜单")
    await capture_ui("late_refused")
    var file: FileAccess = FileAccess.open(output.get_base_dir().path_join("late-join.json"), FileAccess.WRITE)
    file.store_string(JSON.stringify({"passed": failed == 0, "checks": ui_checks}))
    file.close()
    await finish_app()
