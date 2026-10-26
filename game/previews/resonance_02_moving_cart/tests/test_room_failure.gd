extends "res://tests/test_room_network.gd"

func tune(role: String, target_phase: String, seconds: float = 30.0) -> void:
    var deadline: int = Time.get_ticks_msec() + int(seconds * 1000)
    while str(device.get("phase")) == "calibrating" and Time.get_ticks_msec() < deadline:
        var model: RefCounted = device.get("calibration") as RefCounted
        var error: float = float(model.call("frequency_goal" if role == "frequency" else "preload_goal")) - float(model.get("frequency" if role == "frequency" else "preload_value"))
        stop()
        Input.action_press(("move_right" if error > 0 else "move_left") if role == "frequency" else ("move_up" if error > 0 else "move_down"), minf(1, absf(error) * 18))
        await frames(1)
    stop()
    check(str(device.get("phase")) == target_phase, "两端调整后进入 " + target_phase)

func host_flow() -> void:
    check(await board(), "主机沿台阶登车")
    await travel("tray", Vector2(.2,1.42));await press("pickup");await frames(40)
    await travel("socket", Vector2(-1.22,2.2));await press("deposit");await frames(115)
    marker("core-installed.marker")
    await travel("A", Vector2(2.1,1.9));await press("repair")
    await tune("frequency", "failed", 40.0)
    await shot("protection_failure_host", 6)
    check(int(device.get("activation_count")) == 0 and str(player.get("operating_role")) == "", "失败未成功并释放 A 控制位")
    check(await wait_for(func() -> bool: return exists("client-failed.marker")), "客户端已收到相同保护停机")
    await press("repair")
    marker("retry-start.marker")
    await tune("frequency", "charging")
    check(await wait_for(func() -> bool: return str(device.get("phase")) == "stable"), "双人保护停机后正常重试成功")
    stable_evidence = device.call("stage_snapshot") as Dictionary
    await shot("retry_success_host", 5)
    marker("host-success.marker")
    await wait_for(func() -> bool: return exists("client-success.marker"))
    check(int(device.get("activation_count")) == 1, "重试只结算一次")

func client_flow() -> void:
    await wait_for(func() -> bool: return exists("core-installed.marker"))
    check(await board(), "客户端沿台阶登车")
    await travel("B", Vector2(-1.35,1.74))
    await wait_for(func() -> bool: return str(device.get("phase")) in ["locked", "calibrating"])
    await press("repair");await frames(12)
    var deadline: int = Time.get_ticks_msec() + 30000
    while float((device.get("calibration") as RefCounted).get("progress")) < .23 and Time.get_ticks_msec() < deadline:
        var model: RefCounted = device.get("calibration") as RefCounted
        var error: float = float(model.call("preload_goal")) - float(model.get("preload_value"))
        stop();Input.action_press("move_up" if error > 0 else "move_down", minf(1, absf(error) * 18))
        await frames(1)
    stop();Input.action_press("move_up")
    for i: int in range(650):
        await frames(1)
        if str(device.get("phase")) == "failed": break
    stop()
    check(str(device.get("phase")) == "failed", "真实 B 端持续误操作触发保护停机并同步")
    await shot("protection_failure_client", 5)
    check("停机" in str(device.call("objective")), "客户端失败原因与重试方法可见")
    marker("client-failed.marker")
    await wait_for(func() -> bool: return exists("retry-start.marker"))
    await press("repair");await frames(12)
    check(str(player.get("operating_role")) == "preload", "重试重新取得 B 控制位")
    await tune("preload", "charging")
    check(await wait_for(func() -> bool: return str(device.get("phase")) == "stable"), "客户端收到重试成功")
    stable_evidence = device.call("stage_snapshot") as Dictionary
    await shot("retry_success_client", 5)
    marker("client-success.marker")
    await wait_for(func() -> bool: return exists("host-success.marker"))
