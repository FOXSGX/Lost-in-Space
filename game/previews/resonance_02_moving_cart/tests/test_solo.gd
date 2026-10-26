extends "res://tests/input_driver.gd"

# 把某一端往它当前的均衡位置推。新模型有惯性，增益必须小得多（旧版用 18）。
func drive(role: String, limit: int = 2800, gain: float = 6.0) -> bool:
    var model: RefCounted = device.get("calibration") as RefCounted
    for _i: int in range(limit):
        if str(device.get("phase")) != "calibrating": break
        var goal: float = float(model.call("frequency_goal" if role == "frequency" else "preload_goal"))
        var value: float = float(model.get("frequency" if role == "frequency" else "preload_value"))
        var axis: float = clampf((goal - value) * gain, -1, 1)
        var positive: String = "move_right" if role == "frequency" else "move_up"
        var negative: String = "move_left" if role == "frequency" else "move_down"
        stop()
        Input.action_press(positive if axis > 0 else negative, absf(axis))
        await frames(1)
    stop(); await frames(3)
    return str(device.get("phase")) in ["charging", "stable"]

# 新的单人流程：只操作一台设备，另一端由有限速度副控承担。
# 旧版"在 B 调好 → E 锁存 24 秒 → 跑去 A"已经不存在，检查一并替换。
func calibration_pass(capture: bool = true) -> bool:
    var at_a: bool = await travel("frequency_console", Vector2(2.10, 1.90))
    await press("repair")
    check(at_a and str(player.get("operating_role")) == "frequency", "单人接入 A 端，B 端交给副控")
    var model: RefCounted = device.get("calibration") as RefCounted
    check(str(model.get("solo_aux_role")) == "preload", "副控接管 B 端且不是第二个玩家")
    var ok: bool = await drive("frequency", 2800)
    if capture: await shot("09_calibrating", 3)
    check(ok, "玩家与副控共同把机器推入稳定带")
    return ok
func run() -> void:
    await boot()
    await press("pickup")
    check(str(device.get("phase"))=="free" and str(device.get("feedback_code"))=="OUT_OF_REACH","入口不能远距离吸取核心")
    var entry: bool=await travel("entry",Vector2(-9.25,-1.82))
    var aisle: bool=await travel("maintenance",Vector2(-5,-1.2))
    var align: bool=await travel("stairs",Vector2(1,-1.42))
    await shot("00_boarding",8,PI)
    var aboard: bool=await travel("board",Vector2(1,1.42))
    check(entry and aisle and align and aboard and player.position.y>1.7,"沿真实台阶进入开放甲板")
    await shot("01_aboard");orbit()
    await travel("empty_control",Vector2(-1.25,1.75));await press("repair")
    check(str(device.get("feedback_code"))=="MISSING_CORE","无核心启动被拒绝")
    await travel("tray",Vector2(.2,1.42));await face((device.get("core") as Node3D).position)
    var yaw: float=float(player.get("_camera_yaw_target"));player.set("_camera_yaw_target",yaw+PI);await frames(40)
    Input.action_press("pickup");await frames(2);Input.action_release("pickup");await frames(3)
    check(str(device.get("phase"))=="free","背对核心时不能拾取")
    await press("pickup");await frames(35)
    check(str(device.get("phase"))=="held" and int(player.get("carrying"))==3,"F 伸手拾取并自然移到双手前方")
    await shot("02_pickup");orbit()
    Input.action_press("sprint");await travel("sprint_carry",Vector2(.65,2.62));Input.action_release("sprint")
    await shot("03_carry")
    await press("deposit")
    check(str(device.get("feedback_code"))=="WRONG_SOCKET" and str(device.get("phase"))=="held","错误安装位置保留手持核心")
    player.set("_camera_yaw_target",-PI*.5);await frames(115)
    await press("drop");await frames(60)
    check(str(device.get("phase"))=="free","连续下降放置后恢复真实重力")
    var core: RigidBody3D=device.get("core") as RigidBody3D
    check(core.linear_velocity.length()<.15,"落在平台后稳定，无无限弹跳")
    await shot("04_placed")
    await press("pickup");await frames(35)
    check(str(device.get("phase"))=="held","同一核心可再次拾取")
    await travel("socket",Vector2(-1.22,2.20))
    var revision: int=int(device.get("revision"))
    device.call("handle_stage_action",2,"deposit",701,revision)
    check(str(device.get("feedback_code"))=="NO_PLAYER","未登记玩家不能抢占物品")
    device.call("handle_stage_action",1,"deposit",701,revision-1)
    check(str(device.get("feedback_code"))=="STALE_REVISION","过期状态操作不能改变归属")
    await press("deposit")
    check(str(device.get("phase"))=="inserting","正确方向触发连续导轨定位")
    await shot("05_inserting",3)
    await frames(55);await shot("06_locking",3)
    await frames(50)
    check(str(device.get("phase"))=="locked" and int(player.get("carrying"))==0,"核心固定后独立完成机械锁爪闭合")
    await press("deposit")
    check(str(device.get("feedback_code"))=="SOCKET_LOCKED","重复安装不会复制核心")
    await press("drop")
    check(str(device.get("phase"))=="locked","已锁定核心不可随意移走")
    if not await calibration_pass():await finish();return
    await shot("10_charging",3)
    await press("repair")
    check(str(device.get("feedback_code"))=="BUSY","充能期间重复操作不会重启")
    await frames(80);await shot("11_ring_sequence",3)
    await frames(145)
    check(str(device.get("phase"))=="stable" and int(device.get("activation_count"))==1,"校准、环体旋转、分段接通后系统稳定")
    await shot("12_stable");orbit()
    await press("repair")
    check(str(device.get("feedback_code"))=="ALREADY_ACTIVE" and int(device.get("activation_count"))==1,"稳定后重复启动不产生第二次成功")
    var cross: bool=await travel("deck_cross",Vector2(1,2.5))
    var align_exit: bool=await travel("exit_align",Vector2(1,1.35))
    var off: bool=await travel("disembark",Vector2(1,-1.75))
    check(cross and align_exit and off and player.position.y<.45,"完整操作后沿台阶正常下车")
    await shot("13_return");orbit()
    check(camera_hits==0 and orbit_hits==0,"路线及旋转样本未检测到相机穿模")
    check(held_overlap_frames==0,"携带路线未检测到核心穿入静态碰撞")
    await finish()
