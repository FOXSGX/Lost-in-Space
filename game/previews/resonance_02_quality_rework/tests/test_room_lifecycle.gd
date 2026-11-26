extends "res://tests/app_driver.gd"

var host: bool = false
var base: String

func marker(label: String) -> void:
    var file: FileAccess = FileAccess.open(base.path_join(label), FileAccess.WRITE)
    file.store_string("ready")
    file.close()

func wait_for(predicate: Callable, seconds: float = 20.0) -> bool:
    var deadline: int = Time.get_ticks_msec() + int(seconds * 1000)
    while not predicate.call() and Time.get_ticks_msec() < deadline: await frames(1)
    return bool(predicate.call())

func connect_ui() -> void:
    await click("创建房间" if host else "加入房间")
    (app.get("port_input") as LineEdit).text = "26842"
    if not host: (app.get("address") as LineEdit).text = "127.0.0.1"
    await click("创建并等待队友" if host else "连接房间")
    bind_stage()
    ui_check(await wait_for(func() -> bool: return (scene.get("actors") as Dictionary).size() == 2), "两名独立进程在大厅会合")
    if host:
        await frames(20)
        await click("开始合作任务")
    ui_check(await wait_for(func() -> bool: return str(app.get("screen")) == "playing"), "双方开始任务")

func run() -> void:
    await launch_app()
    base = output.get_base_dir()
    host = OS.get_cmdline_user_args().has("--role-host")
    for cycle: int in range(2):
        if not host:
            await wait_for(func() -> bool: return FileAccess.file_exists(base.path_join("host-ready-" + str(cycle))))
        else: marker("host-ready-" + str(cycle))
        await connect_ui()
        if host:
            app.call("show_pause")
            await frames(5)
            await click("重新开始任务")
            marker("reset-" + str(cycle))
            ui_check(await wait_for(func() -> bool: return FileAccess.file_exists(base.path_join("client-reset-" + str(cycle)))), "客户端确认重开同步")
            app.call("show_pause")
            await frames(5)
            await click("返回主菜单 / 离开房间")
            ui_check(app.get("stage") == null, "主机在正常菜单退出房间")
            await wait_for(func() -> bool: return FileAccess.file_exists(base.path_join("client-left-" + str(cycle))))
        else:
            ui_check(await wait_for(func() -> bool: return int(device.get("epoch")) == 1), "收到房主任务重开且连接保留")
            marker("client-reset-" + str(cycle))
            ui_check(await wait_for(func() -> bool: return str(app.get("screen")) == "main"), "主机退出后客户端返回主菜单")
            ui_check(app.get("stage") == null and "主机" in str(app.get("message")), "主机离开原因可见，无旧会话")
            marker("client-left-" + str(cycle))
    if not host:
        await click("加入房间")
        (app.get("address") as LineEdit).text = "127.0.0.1"
        (app.get("port_input") as LineEdit).text = "26849"
        await click("连接房间")
        ui_check(await wait_for(func() -> bool: return str(app.get("screen")) == "main"), "连接不存在的房间超时后可重试")
        await capture_ui("connection_failed")
    await finish_app()
