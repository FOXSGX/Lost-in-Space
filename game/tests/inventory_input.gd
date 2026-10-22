extends SceneTree

# Keep desktop pointer movement and capture warps out of this fixed-camera replay.
# Mouse-look itself is covered by ship_first_person.gd.
class ReplayInputGuard extends Node:
    func _input(event: InputEvent) -> void:
        if event is InputEventMouseMotion:
            get_viewport().set_input_as_handled()

var main: Main3D
var checks: int = 0
var failures: Array[String] = []
var output: String = ProjectSettings.globalize_path("res://").path_join("../work/oxygen-jet-20261022/inventory-regression").simplify_path()

func _initialize() -> void:
    run.call_deferred()

func check(value: bool, message: String) -> void:
    checks += 1
    if not value:
        failures.append(message)
        push_error(message)

func frames(count: int = 4) -> void:
    for index: int in count:
        await physics_frame
        await process_frame

func key(code: Key) -> void:
    var event: InputEventKey = InputEventKey.new()
    event.physical_keycode = code
    event.keycode = code
    event.pressed = true
    Input.parse_input_event(event)
    await frames(2)
    event = InputEventKey.new()
    event.physical_keycode = code
    event.keycode = code
    event.pressed = false
    Input.parse_input_event(event)
    await frames(2)

func mouse(button: MouseButton, position: Vector2 = Vector2(-1, -1)) -> void:
    var event: InputEventMouseButton = InputEventMouseButton.new()
    event.button_index = button
    event.pressed = true
    event.position = root.size * 0.5 if position.x < 0 else position
    Input.parse_input_event(event)
    await frames(2)
    event = InputEventMouseButton.new()
    event.button_index = button
    event.pressed = false
    event.position = root.size * 0.5 if position.x < 0 else position
    Input.parse_input_event(event)
    await frames(2)

func stand(point: Vector3, yaw: float = 0.0, pitch: float = 0.2) -> void:
    var player: SpacePlayer3D = main.players[1] as SpacePlayer3D
    player.teleport_to(point)
    player._camera_yaw_target = yaw
    player._camera_yaw = yaw
    player._camera_pitch_target = pitch
    player._camera_pitch = pitch
    await frames()

func shot(name: String) -> void:
    await frames(3)
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png(output.path_join(name + ".png"))

func run() -> void:
    if DisplayServer.get_name() == "headless":
        print("INVENTORY_INPUT_NOT_RUN: graphical display required")
        quit()
        return
    DirAccess.make_dir_recursive_absolute(output)
    main = load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(main)
    await process_frame
    var replay_guard: ReplayInputGuard = ReplayInputGuard.new()
    replay_guard.process_mode = Node.PROCESS_MODE_ALWAYS
    root.add_child(replay_guard)
    main.network_port = 28217
    main._ship_session.persistence_enabled = false
    main._create_host()
    await frames(12)
    var items: CrewItems3D = main._items
    var player: SpacePlayer3D = main.players[1] as SpacePlayer3D
    check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "新物品栏阻止了第一人称鼠标捕获")
    await stand(ShipHub3D.STORAGE, PI / 2.0, 0.25)
    await key(KEY_E)
    check(items.occupied(1) == 1, "实际 E 键没有收纳储物架实体")
    if main._ship_session.has_panel():
        main._ship_session.close_panel()
    if items.count_kind(1, "medical") == 0:
        main._ship_session.request("take", "medical")
    if items.occupied(1) < 2:
        main._ship_session.request("take", "oxygen")
    await key(KEY_2)
    check(int(items.ensure_bag(1).selected) == 1, "实际数字 2 未切换物品格")
    await mouse(MOUSE_BUTTON_WHEEL_UP)
    check(int(items.ensure_bag(1).selected) == 0, "滚轮未切换物品格")
    await shot("01-physical-supplies")
    player.health = 3
    await mouse(MOUSE_BUTTON_LEFT)
    check(player.health == 5 and items.count_kind(1, "medical") == 0, "实际左键未使用当前医疗包")
    await key(KEY_2)
    await key(KEY_G)
    check(items.occupied(1) == 0 and items.drops.size() == 1, "实际 G 键未放下物品")
    await key(KEY_E)
    check(items.occupied(1) == 1 and items.drops.is_empty(), "实际 E 未再次拾取放下的实体")
    await stand(Vector3(0, 0, 6))
    var floor_y: float = player.position.y
    await key(KEY_SPACE)
    check(player.position.y > floor_y + 0.05, "实际空格未触发跳跃")
    await frames(65)
    check(absf(player.position.y - floor_y) < 0.05 and player.is_on_floor(), "实际跳跃未落地")
    await stand(ShipHub3D.AIRLOCK)
    await key(KEY_E)
    check(not main._ship_session.in_hub, "实际 E 未进入训练舱")
    await frames(8)
    check(player.position.distance_to(ShipTutorial3D.ENTRY_POINT) < 1.8 and (-player.global_transform.basis.z).dot(Vector3(-1, 0, -1).normalized()) > 0.95, "实际进门落点或朝向错误")
    check(main._ship_session.notice_text().is_empty(), "进入训练舱仍显示旧补给提示")
    await shot("05-training-entry")
    var training_floor: float = player.position.y
    await key(KEY_SPACE)
    check(player.position.y > training_floor + 0.05, "训练室实际空格没有起跳")
    await frames(65)
    check(player.is_on_floor() and absf(player.position.y - training_floor) < 0.05, "训练室跳跃没有落地")
    await stand(Vector3(-7, 0, 5.2), 0.0, 0.25)
    await key(KEY_E)
    check(items.count_kind(1, "oxygen") == 1 and int(main._ship_session.training[1]) == 1, "实际 E 没有拿起练习瓶")
    await key(KEY_E)
    check(items.count_kind(1, "oxygen") == 1, "连续 E 重复领取")
    await mouse(MOUSE_BUTTON_LEFT)
    check(items.has_jet(1) and items.occupied(1) == 0, "实际左键没有安装设备")
    await key(KEY_G)
    await frames(10)
    await key(KEY_E)
    check(items.count_kind(1, "oxygen") == 1 and items.drops.is_empty(), "卸下再拾取未守恒")
    await mouse(MOUSE_BUTTON_LEFT)
    await mouse(MOUSE_BUTTON_RIGHT)
    check(int(main._ship_session.training[1]) == 2, "扫描不应跳过落地训练")
    await stand(Vector3(-0.5, 0, 3.5), 0.0, 0.08)
    await shot("04-training-room")
    await key(KEY_ESCAPE)
    check(main._settings_visible and paused, "实际 Esc 没有打开并暂停设置")
    await shot("07-settings-compact")
    await mouse(MOUSE_BUTTON_LEFT, (main._settings_buttons["sprint"] as Button).get_global_rect().get_center())
    check(main._rebinding_action == "sprint", "精简后的设置按钮无法开始改键")
    await key(KEY_ESCAPE)
    check(main._settings_visible and main._rebinding_action.is_empty(), "Esc 未取消改键并保留设置界面")
    await key(KEY_ESCAPE)
    check(not main._settings_visible and not paused, "实际 Esc 没有关闭设置并恢复游戏")
    await stand(ShipTutorial3D.ENTRY_POINT, PI, 0.0)
    await key(KEY_E)
    await frames()
    check(player.position.distance_to(ShipHub3D.AIRLOCK) < 1.8 and (-player.global_transform.basis.z).dot(Vector3.FORWARD) > 0.99, "实际退出训练未返回气闸并朝向舱内")
    check(main._ship_session.notice_text().is_empty(), "回到主舱仍显示训练完成提示")
    await shot("06-training-return")
    await stand(Vector3(ShipDevices3D.PILOT_X[0], 0, -12.2), 0.0, -0.2)
    await key(KEY_E)
    main._confirm_land()
    await frames(5)
    player = main.players[1] as SpacePlayer3D
    (main.beacons[1] as Node3D).global_position = Vector3.ZERO
    main.activated_beacons.append(1)
    player.teleport_to(Vector3(1.0, 0, 0))
    await frames(3)
    await key(KEY_E)
    check(items.choice_open and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "E 没有打开信号阵列选择或释放鼠标")
    var count_before: int = items.count_kind(1, "oxygen")
    var option: Button = items._choice.get_children()[2] as Button
    await mouse(MOUSE_BUTTON_LEFT, option.get_global_rect().get_center())
    check(not items.choice_open and main.signal_mode == "low", "鼠标选择低频模式失败")
    check(items.count_kind(1, "oxygen") == count_before, "点击选项时意外使用了物品")
    main.return_to_ship("输入检查完成")
    main._show_home()
    main.queue_free()
    await frames()
    print("INVENTORY_INPUT: %d checks, %d failures" % [checks, failures.size()])
    quit(0 if failures.is_empty() else 1)
