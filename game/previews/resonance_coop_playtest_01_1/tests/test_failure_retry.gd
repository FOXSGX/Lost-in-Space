extends "res://tests/test_solo.gd"

func run() -> void:
    await boot()
    check(bool(scene.call("request_action", "recover_core")), "房主可找回地上核心")
    await travel("entry",Vector2(-9.25,-1.82));await travel("aisle",Vector2(-5,-1.2))
    await travel("stairs",Vector2(1,-1.42));await travel("board",Vector2(1,1.42))
    await travel("tray",Vector2(.2,1.42));await press("pickup");await frames(40)
    check(not bool(scene.call("request_action", "recover_core")) and str(device.get("phase")) == "held", "持有中的核心不可被回收或复制")
    await travel("socket",Vector2(-1.22,2.20));await press("deposit");await frames(115)
    check(not bool(scene.call("request_action", "recover_core")) and str(device.get("phase")) == "locked", "已安装核心不可被回收或复制")
    await travel("preload", Vector2(-1.35,1.74));await press("repair")
    var model: RefCounted=device.get("calibration") as RefCounted
    while absf(float(model.get("preload_value"))-float(model.call("preload_goal"))) > .035:
        Input.action_press("move_up");await frames(1)
    stop();await press("repair")
    await travel("frequency",Vector2(2.1,1.9));await press("repair")
    var budget: int=600
    while float(model.get("progress")) < .25 and budget>0:
        var error: float=float(model.call("frequency_goal"))-float(model.get("frequency"))
        stop();Input.action_press("move_right" if error>0 else "move_left",minf(1,absf(error)*18))
        await frames(1);budget-=1
    stop();Input.action_press("move_left")
    for i: int in range(600):
        await frames(1)
        if str(device.get("phase"))=="failed":break
    stop()
    check(str(device.get("phase"))=="failed" and int(device.get("activation_count"))==0, "持续失配产生保护停机，未自动成功")
    check(int(device.get("carrier_id"))==0 and str(player.get("operating_role"))=="", "保护停机保留核心并释放操作位")
    await shot("failure", 5)
    check("停机" in str(device.call("objective")), "失败原因与重试方法可见")
    await press("repair")
    check(str(device.get("phase"))=="calibrating", "正常 E 操作重新校准")
    await press("cancel_operation")
    check(await calibration_pass(), "失败后可重新完成单人校准")
    await frames(230)
    check(str(device.get("phase"))=="stable" and int(device.get("activation_count"))==1, "重试成功只结算一次")
    await shot("retry_success",5)
    await finish()
