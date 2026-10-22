extends SceneTree

class ReplayInputGuard extends Node:
    func _input(event: InputEvent) -> void:
        if event is InputEventMouseMotion:
            get_viewport().set_input_as_handled()

var main: Main3D
var player: SpacePlayer3D
var checks: int = 0
var failures: Array[String] = []
var output: String = ProjectSettings.globalize_path("res://").path_join("../work/training-wall-posters-20261022/course").simplify_path()

func _initialize() -> void:
    run.call_deferred()

func check(ok: bool, message: String) -> void:
    checks += 1
    if not ok:
        failures.append(message)
        push_error(message)

func frames(count: int = 4) -> void:
    for index: int in count:
        await physics_frame
        await process_frame

func charge_full() -> void:
    var deadline: int = Time.get_ticks_msec() + 6000
    while player.jet_charge < 0.995 and Time.get_ticks_msec() < deadline:
        await frames(1)
    check(player.jet_charge >= 0.995, "落地等待没有完成有耗充气")

func key_down(code: Key, pressed: bool) -> void:
    var event: InputEventKey = InputEventKey.new()
    event.physical_keycode = code
    event.keycode = code
    event.pressed = pressed
    Input.parse_input_event(event)

func key(code: Key) -> void:
    key_down(code, true)
    await frames(2)
    key_down(code, false)
    await frames(2)

func click() -> void:
    var event: InputEventMouseButton = InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = true
    event.position = root.size * 0.5
    Input.parse_input_event(event)
    await frames(2)
    event = InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.position = root.size * 0.5
    Input.parse_input_event(event)
    await frames(2)

func stand(point: Vector3, yaw: float = 0.0, pitch: float = 0.15) -> void:
    player.teleport_to(point)
    player._camera_yaw = yaw
    player._camera_yaw_target = yaw
    player._camera_pitch = pitch
    player._camera_pitch_target = pitch
    await frames(6)

func shot(title: String) -> void:
    if DisplayServer.get_name() == "headless":
        return
    await frames(3)
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png(output.path_join(title + ".png"))

func run() -> void:
    DirAccess.make_dir_recursive_absolute(output)
    main = load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(main)
    await process_frame
    var guard: ReplayInputGuard = ReplayInputGuard.new()
    root.add_child(guard)
    main.network_port = 28431
    main._ship_session.persistence_enabled = false
    main._create_host()
    await frames(8)
    player = main.players[1] as SpacePlayer3D
    var items: CrewItems3D = main._items
    var stock: Dictionary = main._ship_session.stock.duplicate(true)
    items.add_item(1, "medical")
    var saved: Dictionary = items.ensure_bag(1).duplicate(true)
    main._ship_session.switch_area(false)
    await frames(8)
    check(main._ship_session.training[1] == 0, "走动之前应开始实物训练")
    check(items.occupied(1) == 0 and not items.has_jet(1), "练习未隔离正式物品")
    await shot("01-training-entry")
    await stand(Vector3(0, 0, 4.5))
    key_down(KEY_SPACE, true)
    var normal_apex: float = 0.0
    for index: int in 55:
        await frames(1)
        normal_apex = maxf(normal_apex, player.position.y)
    key_down(KEY_SPACE, false)
    check(normal_apex > 0.5 and normal_apex < 1.2 and not player.jet_active, "未装备时长按不应飞行或重复起跳")
    await frames(30)
    await stand(Vector3(-7, 0, 5.2))
    await key(KEY_E)
    check(items.count_kind(1, "oxygen") == 1, "E 未拿起练习氧气瓶")
    check(main._ship_session.training[1] == 1, "拾取后没有提示安装")
    await key(KEY_E)
    check(items.count_kind(1, "oxygen") == 1, "重复领取复制了练习氧气瓶")
    await click()
    check(items.has_jet(1) and items.occupied(1) == 0, "左键未把瓶子装到宇航服并释放物品格")
    check(main._ship_session.training[1] == 2, "安装后没有进入跳跃练习")
    await frames()
    check(is_instance_valid(player._jet_pack) and player._jet_pack.visible, "已安装设备没有背部模型")
    await charge_full()
    await stand(Vector3(0, 0, 4.5))
    var charge: float = player.jet_charge
    await key(KEY_SPACE)
    check(player.position.y > 0.0 and not player.jet_active and is_equal_approx(charge, player.jet_charge), "短按未立即跳跃或误耗喷气压力")
    await frames(55)
    await stand(Vector3(0, 0, 4.5))
    key_down(KEY_SPACE, true)
    await frames(35)
    check(player.jet_active and player.position.y > normal_apex + 1.0, "长按不能抵达普通跳跃以上的高度")
    check(player.jet_charge < 0.9 and items.has_jet(1), "推进没有压力反馈或错误销毁瓶子")
    await shot("02-jet-airborne")
    key_down(KEY_SPACE, false)
    await frames(2)
    check(not player.jet_active, "松开后没有停止喷气")
    await frames(130)
    await charge_full()
    check(player.is_on_floor() and player.jet_charge > 0.95, "落地松开没有恢复推进压力")
    key_down(KEY_SPACE, true)
    await frames(22)
    main._settings_visible = true
    await frames(4)
    check(not player.jet_active, "打开设置后推进仍运行")
    key_down(KEY_SPACE, false)
    main._settings_visible = false
    await frames(90)
    await charge_full()
    check(main._ship_session.training[1] == 2, "仅按键和飞行就跳过了落地训练")
    # Short jump onto the actual low platform.
    await stand(ShipTutorial3D.HOP_POINT + Vector3(0, -0.55, 1.9))
    key_down(KEY_SPACE, true)
    key_down(KEY_W, true)
    await frames(4)
    key_down(KEY_SPACE, false)
    await frames(13)
    key_down(KEY_W, false)
    await frames(35)
    check(main._ship_session.training[1] == 3 and player.position.y > 0.45, "实际短跳未能登上低台")
    # Fly from the floor to the high platform using real movement and jump inputs.
    await stand(Vector3(-4.2, 0, 0.0))
    key_down(KEY_SPACE, true)
    await frames(46)
    key_down(KEY_W, true)
    await frames(23)
    key_down(KEY_W, false)
    key_down(KEY_SPACE, false)
    await frames(95)
    await charge_full()
    check(main._ship_session.training[1] == 4 and absf(player.position.y - ShipTutorial3D.BOOST_POINT.y) < 0.2, "长按与移动未能实际落上高台")
    player._camera_yaw = -1.2
    player._camera_yaw_target = -1.2
    player._camera_pitch = 0.4
    player._camera_pitch_target = 0.4
    await shot("03-high-platform")
    # Continue via the intermediate landing pad, refill, then cross to the finish.
    player._camera_yaw = -PI / 2.0
    player._camera_yaw_target = -PI / 2.0
    key_down(KEY_SPACE, true)
    await frames(20)
    key_down(KEY_W, true)
    await frames(64)
    key_down(KEY_W, false)
    key_down(KEY_SPACE, false)
    await frames(115)
    await charge_full()
    check(player.position.y > 4.2 and absf(player.position.x - 2.2) < 1.4, "中继落台不可达")
    player._camera_yaw = -2.42
    player._camera_yaw_target = -2.42
    key_down(KEY_SPACE, true)
    await frames(15)
    key_down(KEY_W, true)
    await frames(65)
    key_down(KEY_W, false)
    key_down(KEY_SPACE, false)
    await frames(120)
    check(main._ship_session.training[1] == 5, "实际路线无法完成终点落地")
    player._camera_yaw = 1.1
    player._camera_yaw_target = 1.1
    player._camera_pitch = 0.5
    player._camera_pitch_target = 0.5
    await shot("04-course-finish")
    # An unmounted bottle must settle as a rigid body and keep its pose on selection changes.
    await stand(Vector3(0, 0, 4.5))
    await key(KEY_G)
    check(not items.has_jet(1) and items.drops.size() == 1, "空手 G 未卸下设备")
    await frames(150)
    var uid: String = String(items.drops[0].uid)
    var body: RigidBody3D = items._prop_bodies.get(uid) as RigidBody3D
    check(body != null and body.get_child(0) is CollisionShape3D, "放下物件没有碰撞体积")
    check(body != null and body.position.y > 0.08 and body.position.y < 0.45, "瓶子没有落在地板表面")
    check(body != null and absf(body.global_basis.y.dot(Vector3.UP)) < 0.4, "瓶子仍保持直立而未自然躺倒")
    var pose: Transform3D = body.transform
    await key(KEY_2)
    await key(KEY_1)
    check(items._prop_bodies.get(uid) == body and body.position.distance_to(pose.origin) < 0.12, "切换物品格重建或重置了物理道具")
    player._camera_pitch = 0.95
    player._camera_pitch_target = 0.95
    await shot("05-bottle-on-floor")
    var point: Vector3 = body.position
    await stand(Vector3(point.x, 0, point.z + 1.2), 0.0, 0.7)
    await key(KEY_E)
    check(items.drops.is_empty() and items.count_kind(1, "oxygen") == 1, "倒地后的瓶子无法拾取")
    await click()
    check(items.has_jet(1), "拾回的氧气瓶无法重新安装")
    main._ship_session.switch_area(true)
    await frames(10)
    check(items.ensure_bag(1) == saved, "退出练习没有完整恢复原物品与装备")
    check(main._ship_session.stock == stock, "练习污染了正式共享库存")
    # A formal mounted tank must survive entering/exiting the practice session and return to stock.
    items.add_item(1, "oxygen")
    items.ensure_bag(1).selected = 1
    await click()
    check(items.has_jet(1), "正式氧气瓶无法装配")
    check(int(items.real_counts(1).oxygen) == 1, "已装设备未纳入归库数量")
    main._ship_session.switch_area(false)
    await frames(8)
    check(not items.has_jet(1), "正式设备被带入练习状态")
    main._ship_session.switch_area(true)
    await frames(8)
    check(items.has_jet(1), "原有正式设备未在退出时恢复")
    print("OXYGEN_JET_TRAINING_RESULT " + JSON.stringify({"checks": checks, "failures": failures, "graphical": DisplayServer.get_name() != "headless", "normal_apex": normal_apex}))
    main._show_home()
    main.queue_free()
    await frames(6)
    quit(0 if failures.is_empty() else 1)
