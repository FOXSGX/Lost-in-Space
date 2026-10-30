extends "res://tests/app_driver.gd"

func run() -> void:
    await launch_app()
    ui_check(button("单人试玩") != null and button("创建房间") != null and button("加入房间") != null, "主菜单提供真人入口")
    for dimensions: Vector2i in [Vector2i(1280, 800), Vector2i(960, 600)]:
        root.size = dimensions
        root.content_scale_size = dimensions
        await frames(6)
        layout_check("main " + str(dimensions))
        await capture_ui("main_" + str(dimensions.x))
    await click("设置")
    layout_check("settings 960")
    await capture_ui("settings")
    await click("返回")
    await click("加入房间")
    layout_check("join 960")
    await capture_ui("join")
    await click("连接房间")
    ui_check(app.get("stage") == null, "无效 IP 不创建会话")
    await click("返回主菜单")
    await click("创建房间")
    (app.get("port_input") as LineEdit).text = "0"
    await click("创建并等待队友")
    ui_check(app.get("stage") == null, "无效端口保留表单可重试")
    await click("返回主菜单")
    await click("单人试玩")
    bind_stage()
    ui_check((scene.get("actors") as Dictionary).size() == 1 and str(app.get("screen")) == "playing", "单人只有一个真实操作者")
    await capture_ui("solo_entry")
    var event: InputEventKey = InputEventKey.new()
    event.keycode = KEY_ESCAPE
    event.pressed = true
    Input.parse_input_event(event)
    await frames(5)
    ui_check(str(app.get("screen")) == "pause", "Esc 打开正常任务菜单")
    layout_check("pause 960")
    await capture_ui("pause")
    await click("重新开始任务")
    ui_check(int(device.get("epoch")) == 1 and str(app.get("screen")) == "playing", "菜单重开任务不退出程序")
    app.call("show_pause")
    await frames(5)
    await click("返回主菜单 / 离开房间")
    ui_check(app.get("stage") == null and str(app.get("screen")) == "main", "单人可返回主菜单")
    await click("单人试玩")
    bind_stage()
    ui_check(int(player.get("peer_id")) == 1 and int(device.get("epoch")) == 0, "再次试玩无旧状态")
    await finish_app()
