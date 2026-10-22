extends SceneTree

class ReplayMotionGuard extends Node:
    func _input(event: InputEvent) -> void:
        if event is InputEventMouseMotion and event.device != 777:
            get_viewport().set_input_as_handled()

# Run with a graphical display: the headless display driver cannot capture a mouse.

var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
    run.call_deferred()

func check(ok: bool, message: String) -> void:
    checks += 1
    if not ok:
        failures.append(message)
        push_error(message)

func tab_press() -> void:
    var key: InputEventKey = InputEventKey.new()
    key.keycode = KEY_TAB
    key.physical_keycode = KEY_TAB
    key.pressed = true
    Input.parse_input_event(key)
    key = key.duplicate() as InputEventKey
    key.pressed = false
    Input.parse_input_event(key)

func run() -> void:
    if DisplayServer.get_name() == "headless":
        print("SHIP_FIRST_PERSON_NOT_RUN: graphical display required for mouse capture and input replay")
        quit(0)
        return
    var main: Main3D = load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(main)
    await process_frame
    var guard: ReplayMotionGuard = ReplayMotionGuard.new()
    guard.process_mode = Node.PROCESS_MODE_ALWAYS
    root.add_child(guard)
    main._ship_session.persistence_enabled = false
    main.network_port = 28163
    main._create_host()
    await physics_frame
    var ship: ShipSession3D = main._ship_session
    var player: SpacePlayer3D = main.players[1] as SpacePlayer3D
    check(player._camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "主舱没有使用透视镜头")
    check(player._camera.global_position.distance_to(player.global_position + Vector3.UP * player.SHIP_EYE_HEIGHT) < 0.02, "镜头不在眼睛位置")
    check(not player._visual.visible, "本机头盔遮挡第一人称视线")
    check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "进入舱室没有捕获鼠标")
    check(ship.room.has_node("FirstPersonCeiling"), "剖面模型缺少舱顶")
    main.spawn_player_for_peer(2)
    var remote: SpacePlayer3D = main.players[2] as SpacePlayer3D
    remote.configure_ship_camera()
    check(remote._visual.visible and remote._camera == null, "远端角色应该保持可见且不创建本机镜头")
    check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "远端角色初始化不应释放本机鼠标")
    var motion: InputEventMouseMotion = InputEventMouseMotion.new()
    motion.device = 777
    motion.relative = Vector2(350, -180)
    Input.parse_input_event(motion)
    player._process(0.25)
    check(player._camera_yaw < -0.5 and -player._camera.global_basis.z.y > 0.1, "鼠标右上移动没有产生正确的环视方向")
    var before: Vector3 = player.global_position
    Input.action_press("move_up")
    for frame: int in 8:
        await physics_frame
    Input.action_release("move_up")
    check(player.global_position.x > before.x + 0.1 and player.global_position.z < before.z - 0.1, "前进没有跟随转向后的视线")
    tab_press()
    await process_frame
    check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "Tab 不应再打断舱内第一人称")
    var stopped: Vector3 = player.global_position
    Input.action_press("move_up")
    for frame: int in 4:
        await physics_frame
    Input.action_release("move_up")
    check(player.global_position.distance_to(stopped) > 0.01, "Tab 后角色被旧 HUD 模式锁住")
    tab_press()
    player.teleport_to(Vector3(ShipDevices3D.PILOT_X[0], 0, -12.2))
    player._camera_yaw = 0.0
    player._camera_yaw_target = 0.0
    await physics_frame
    var ready_key: InputEventKey = InputEventKey.new()
    ready_key.physical_keycode = KEY_E
    ready_key.pressed = true
    Input.parse_input_event(ready_key)
    await physics_frame
    await physics_frame
    ready_key = ready_key.duplicate() as InputEventKey
    ready_key.pressed = false
    Input.parse_input_event(ready_key)
    check(ship.ready_peers.has(1), "第一人称实际 E 无法在驾驶台就位")
    check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and ship._layer.find_children("*", "BaseButton", true, false).is_empty(), "驾驶台仍依赖按钮/释放光标")
    ship.request("ready")
    player.teleport_to(ShipHub3D.MISSION + Vector3(0, 0, 1.3))
    player._camera_yaw = 0.0
    player._camera_yaw_target = 0.0
    player.rotation.y = 0.0
    ship.request("interact")
    check(ship.has_panel() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "记录面板没有释放鼠标")
    var old_yaw: float = player._camera_yaw_target
    Input.parse_input_event(motion)
    check(is_equal_approx(old_yaw, player._camera_yaw_target), "操作设施时鼠标仍会旋转镜头")
    ship.close_panel()
    check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "返回舱内没有恢复环视")
    main._show_route()
    check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not ship.has_panel(), "航线仍打开鼠标按钮界面")
    ship.close_panel()
    player.teleport_to(ShipDevices3D.point_for("skin_ranger") + Vector3(0, 0, 1.3))
    player.rotation.y = 0.0
    ship.request("interact")
    check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and main.skin_for(1) == "ranger", "外观终端未保持第一人称")
    main._open_settings()
    check(paused and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "设置暂停前没有释放鼠标")
    main._close_settings()
    check(not paused and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "关闭设置没有恢复输入")
    ship.switch_area(false)
    await physics_frame
    check(player._camera.projection == Camera3D.PROJECTION_PERSPECTIVE and not player._visual.visible, "训练舱未保持第一人称")
    ship.switch_area(true)
    await physics_frame
    check(is_zero_approx(player._camera_yaw), "返回主舱后初始朝向异常")
    main._start_planet()
    await process_frame
    player = main.players[1] as SpacePlayer3D
    check(player._camera.projection == Camera3D.PROJECTION_ORTHOGONAL and player._visual.visible, "登陆霜烬星没有恢复星球原有镜头和角色")
    check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "离开第一人称舱室后鼠标仍被锁定")
    main.return_to_ship("第一人称回归检查", main._vitals_snapshot())
    await physics_frame
    player = main.players[1] as SpacePlayer3D
    check(player._camera.projection == Camera3D.PROJECTION_PERSPECTIVE and not player._visual.visible, "返航没有恢复第一人称")
    main._show_home()
    # Allow menu sky/radiance resources to finish their renderer-side update.
    for frame: int in 12:
        await process_frame
    check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "退出房间没有恢复系统光标")
    print("SHIP_FIRST_PERSON: %d checks, %d failures" % [checks, failures.size()])
    main.queue_free()
    for frame: int in 3:
        await process_frame
    await RenderingServer.frame_post_draw
    quit(0 if failures.is_empty() else 1)
