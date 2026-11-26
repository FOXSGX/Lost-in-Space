extends "res://tests/test_solo.gd"

func prepare_locked() -> bool:
    if player.position.y<.1:
        await travel("ground_return",Vector2(-9.25,-3.0),900)
        await travel("entry_ramp",Vector2(-9.25,-1.82))
        await travel("maintenance_return",Vector2(-5,-1.2))
    if player.position.y<1.6:
        await travel("repeat_stairs",Vector2(1,-1.1));await travel("repeat_board",Vector2(1,1.42))
    await travel("repeat_tray",Vector2(.2,1.42));await press("pickup");await frames(35)
    await travel("repeat_socket",Vector2(-1.22,2.20));await press("deposit")
    await press("repair")
    check(str(device.get("feedback_code"))=="NOT_LOCKED","核心尚未锁定时启动被拒绝")
    await frames(100)
    return str(device.get("phase"))=="locked"

func run() -> void:
    await boot()
    await travel("entry",Vector2(-9.25,-1.82));await travel("aisle",Vector2(-5,-1.2))
    await travel("stairs",Vector2(1,-1.1));await travel("board",Vector2(1,1.42))
    await travel("tray",Vector2(.2,1.42));await press("pickup");await frames(35)
    for _i: int in range(8):
        Input.action_press("pickup");await frames(2);Input.action_release("pickup");await frames(2)
    check(str(device.get("phase"))=="held" and scene.find_children("EnergyCore_701","RigidBody3D",true,false).size()==1,"连续拾取不复制核心、不改变所有者")
    await travel("carry_exit",Vector2(1,1.35))
    var carried_down: bool=await travel("carry_down",Vector2(1,-1.75),600)
    check(carried_down and player.position.y<.45,"携带重核心可通过狭窄台阶下车")
    await travel("wall_approach",Vector2(1,-2.6),180)
    player.set("_camera_yaw_target",0.0);await frames(90)
    Input.action_press("move_up");await frames(180);Input.action_release("move_up");await frames(20)
    check(not bool(device.call("held_overlaps")),"靠近岩壁时核心扫掠保持净空")
    check(not bool(player.call("camera_overlap")),"岩壁附近相机体积未穿入场景")
    Input.action_press("drop");await frames(2);Input.action_release("drop");await frames(4)
    check(str(device.get("phase"))=="held" and str(device.get("feedback_code")) in ["UNSAFE_DROP","BLOCKED_DROP"],"面向岩壁的不合理放置被拒绝并保留核心")
    # Deliberately place only the item behind the nearby rock for a line-of-
    # sight fixture. The actor never changes position and this is not a playthrough.
    await press("reset_preview");await frames(5)
    var core: RigidBody3D=device.get("core") as RigidBody3D
    core.freeze=true;core.position=player.position-player.global_basis.z*1.30+Vector3.UP*.37
    var occluder: StaticBody3D=StaticBody3D.new();occluder.collision_layer=2
    var blocker: CollisionShape3D=CollisionShape3D.new();var box: BoxShape3D=BoxShape3D.new();box.size=Vector3(.75,1.6,.12);blocker.shape=box;occluder.add_child(blocker)
    scene.add_child(occluder);occluder.position=player.position-player.global_basis.z*.65+Vector3.UP*.8;occluder.rotation.y=player.rotation.y
    await frames(2)
    Input.action_press("pickup");await frames(2);Input.action_release("pickup");await frames(2)
    check(str(device.get("phase"))=="free","距离内核心隔测试遮挡体不能拾取（物理遮挡夹具）")
    occluder.queue_free();await frames(2)
    await press("reset_preview");await frames(10)
    if not await prepare_locked():check(false,"入口斜坡回程失败");await finish();return
    check(str(device.get("phase"))=="locked","复位后可以重新登车、安装并锁定")
    await travel("cancel_preload",Vector2(-1.35,1.74));await press("repair")
    await press("cancel_operation")
    check(str(device.get("phase"))=="locked" and str(player.get("operating_role"))=="","校准中停机释放控制席，保留已安装核心")
    check(await calibration_pass(false),"停机后可以再次校准")
    await press("cancel_operation")
    check(str(device.get("phase"))=="locked","充能中可安全停机回到已锁定")
    check(await calibration_pass(false),"充能取消后可以重试并通过校准")
    await frames(240)
    check(str(device.get("phase"))=="stable" and int(device.get("activation_count"))==1,"取消与重试后只产生一次稳定成功")
    await press("reset_preview");await frames(15)
    check(str(device.get("phase"))=="free" and int(device.get("activation_count"))==0,"成功后主机复位所有交互状态")
    check(await prepare_locked(),"成功后复位可重新完成拾取与安装")
    check(await calibration_pass(false),"复位后第二次完整校准可完成")
    await frames(240)
    check(str(device.get("phase"))=="stable" and int(device.get("activation_count"))==1,"第二轮完整链稳定完成且没有重复结算")
    # Physics-only edge fixture uses the real core and real platform collision.
    await press("reset_preview");await frames(10)
    core.freeze=false;core.position=Vector3(4.8,2.1,-2.25);core.linear_velocity=Vector3(.08,0,0);core.angular_velocity=Vector3.ZERO
    await frames(240)
    check(core.position.y> -1.2 and core.linear_velocity.length()<.25,"真实平台边缘刚体落下后未飞出地图并趋于稳定（物理夹具）")
    check(scene.find_children("EnergyCore_701","RigidBody3D",true,false).size()==1,"重试、复位和物理夹具后仍只有一枚核心")
    await finish()
