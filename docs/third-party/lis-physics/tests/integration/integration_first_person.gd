extends "res://tests/harness/lis_test_case.gd"
## 集成 · 两种第一人称控制器接入方式（任务书 §9）
##
## 验证：
##   1.  方式 A：CharacterBody3D + Camera3D，直接填导出字段即可抓握
##   2.  方式 B：自定义控制器节点树，只实现 LISFirstPersonSource 协议即可抓握
##   3.  两种方式走的是**同一份抓握实现**（不是复制两套）
##   4.  方式 B 的自定义能力（施力上限）真的生效
##   5.  方式 B 缺方法时安全失败（不崩溃）
##   6.  适配器自检能指出缺什么
##   7.  协议覆盖了任务书要求的全部输入项
##   8.  两种方式产出的力都作用在物体表面
##   9.  远程参与者（代理）与本地玩家用同一条施力路径
##  10.  抓握意图对象可被构造与传递
##  11.  主机权威桥能为远端玩家建代理并施力
##  12.  玩家退出后代理与其持有关系被清理


## 方式 B 的最小自定义控制器：节点树故意与方式 A 不同
## （不是 CharacterBody3D，相机是动态创建的，玩家 ID 也不同）。
class CustomController extends LISFirstPersonSource:
	var cam: Camera3D
	var body_root: Node3D

	func _init() -> void:
		body_root = Node3D.new()
		body_root.name = "CustomBody"
		add_child(body_root)
		cam = Camera3D.new()
		cam.name = "CustomEye"
		add_child(cam)

	func fp_player_id() -> int:
		return 7

	func fp_camera() -> Camera3D:
		return cam

	func fp_body() -> Node3D:
		return body_root

	func fp_forward() -> Vector3:
		return -cam.global_transform.basis.z

	func fp_max_lift_force() -> float:
		# 这名角色"力气小"：单手只有 600 N
		return 600.0


func _configure() -> void:
	suite_name = "integration_first_person"
	expected_checks = 12


func _run() -> void:
	make_world_with_floor(24.0)
	await wait_physics(6)

	# ===== 方式 A：CharacterBody3D + Camera3D =========================
	var char_body: CharacterBody3D = CharacterBody3D.new()
	char_body.name = "WayA_Player"
	char_body.collision_layer = LISPhysics.LAYER_PLAYER
	char_body.collision_mask = LISPhysics.LAYER_WORLD
	var cs: CollisionShape3D = CollisionShape3D.new()
	var cap: CapsuleShape3D = CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.75
	cs.shape = cap
	char_body.add_child(cs)
	add_child(char_body)
	char_body.global_position = Vector3(-6.0, 1.0, 4.0)
	var cam_a: Camera3D = Camera3D.new()
	cam_a.name = "Camera3D"
	char_body.add_child(cam_a)
	cam_a.global_position = Vector3(-6.0, 1.62, 4.0)
	cam_a.look_at(Vector3(-6.0, 0.3, 2.0), Vector3.UP)
	# 适配器：只填 body / camera 两个字段
	var ad_a: LISFirstPersonAdapter = LISFirstPersonAdapter.new()
	ad_a.name = "WayA_Adapter"
	ad_a.read_input = false
	ad_a.player_id = 1
	ad_a.body = char_body
	ad_a.camera = cam_a
	char_body.add_child(ad_a)
	var box_a: LISBody = make_body(Vector3(-6.0, 0.31, 2.0), Vector3(0.6, 0.6, 0.6), 14.0,
		Color(0.6, 0.8, 0.6), {"display_name": "A 箱"})
	await wait_physics(30)
	check("方式 A：CharacterBody3D 直接接入即可抓握",
		ad_a.validate_setup().is_empty() and ad_a.grab(box_a),
		"自检=%s · %s" % [str(ad_a.validate_setup()), ad_a.grabber.describe()])

	# ===== 方式 B：自定义控制器协议 ===================================
	var custom: CustomController = CustomController.new()
	custom.name = "WayB_Source"
	add_child(custom)
	custom.global_position = Vector3(6.0, 0.0, 4.0)
	custom.cam.global_position = Vector3(6.0, 1.5, 4.0)
	custom.cam.look_at(Vector3(6.0, 0.3, 2.0), Vector3.UP)
	var ad_b: LISFirstPersonAdapter = LISFirstPersonAdapter.new()
	ad_b.name = "WayB_Adapter"
	ad_b.read_input = false
	ad_b.source = custom
	add_child(ad_b)
	await wait_physics(4)
	var box_b: LISBody = make_body(Vector3(6.0, 0.31, 2.0), Vector3(0.6, 0.6, 0.6), 14.0,
		Color(0.6, 0.6, 0.85), {"display_name": "B 箱"})
	await wait_physics(30)
	var b_ok: bool = ad_b.validate_setup().is_empty() and ad_b.grab(box_b)
	check("方式 B：只实现协议即可抓握（节点树完全不同）", b_ok,
		"自检=%s · pid=%d · %s" % [
			str(ad_b.validate_setup()), ad_b.player_id, ad_b.grabber.describe()])
	check("方式 B 的玩家身份来自协议", ad_b.player_id == 7,
		"pid=%d（协议返回 7）" % ad_b.player_id)

	# 同一份抓握实现：两个适配器的抓握器是同一个类
	check("两种方式共用同一份抓握实现（不是复制两套）",
		ad_a.grabber.get_script() == ad_b.grabber.get_script(),
		"类型 %s" % str(ad_a.grabber.get_script().get_global_name()))

	# 自定义能力生效：方式 B 的举升上限应被压到 600 N
	check("方式 B 的自定义施力上限真的生效",
		is_equal_approx(ad_b.grabber.lift_force, 600.0),
		"lift_force=%.0f N（协议返回 600）" % ad_b.grabber.lift_force)

	# 力作用在真实抓握点
	await wait_physics(40)
	var grip_a: Vector3 = ad_a.grabber.grip_world()
	var local_a: Vector3 = box_a.to_local(grip_a)
	var half_a: Vector3 = box_a.size() * 0.5
	check("方式 A 的力作用在物体表面",
		absf(absf(local_a.z) - half_a.z) < 0.03,
		"局部抓握点 %s · 半尺寸 %s" % [str(local_a), str(half_a)])

	# ===== 协议完整性 =================================================
	var src: LISFirstPersonSource = custom
	var has_all: bool = src.fp_camera() != null and src.fp_body() != null \
		and src.fp_forward().length() > 0.01 and src.fp_player_id() > 0 \
		and src.fp_eye_position() != Vector3.ZERO and src.fp_max_lift_force() > 0.0 \
		and src.fp_is_authority() and src.fp_max_drag_force() >= 0.0 \
		and src.fp_palm_torque_max() >= 0.0 and src.is_valid_source() == ""
	check("协议覆盖任务书要求的全部输入项", has_all, "10 项协议方法均可用")

	# 缺相机时安全失败
	var broken_src: LISFirstPersonSource = LISFirstPersonSource.new()
	add_child(broken_src)
	var ad_broken: LISFirstPersonAdapter = LISFirstPersonAdapter.new()
	ad_broken.read_input = false
	ad_broken.source = broken_src
	add_child(ad_broken)
	await wait_physics(3)
	var problems: PackedStringArray = ad_broken.validate_setup()
	check("协议不完整时自检能指出问题且抓握安全失败",
		problems.size() > 0 and not ad_broken.grab(box_b),
		"自检报告 %d 条问题：%s" % [problems.size(),
			problems[0] if not problems.is_empty() else ""])
	ad_broken.queue_free()
	broken_src.queue_free()
	await wait_physics(4)

	# ===== 意图对象 ===================================================
	var intent: LISFirstPersonIntent = LISFirstPersonIntent.make(
		LISFirstPersonIntent.Kind.GRAB, 7, box_b)
	check("抓握意图对象可被构造", intent != null and intent.kind == LISFirstPersonIntent.Kind.GRAB,
		intent.describe())

	# ===== 主机权威桥 =================================================
	var host: LISPhysicsHost = LISPhysicsHost.new()
	host.name = "TestHost"
	add_child(host)
	host.register_body(box_b)
	await wait_physics(4)
	var proxy: LISFirstPersonAdapter = host.ensure_proxy(42)
	check("主机权威桥能为远端玩家建代理", proxy != null and proxy.player_id == 42,
		"代理 pid=%d" % (proxy.player_id if proxy != null else -1))
	# 更新远端位姿并应用一次抓握意图
	var remote_box: LISBody = make_body(Vector3(0.0, 0.31, -6.0), Vector3(0.6, 0.6, 0.6), 14.0,
		Color(0.85, 0.7, 0.5), {"display_name": "远端箱"})
	await wait_physics(30)
	host.update_proxy_pose(42, Vector3(0.0, 1.5, -4.2), Vector3(0.0, -0.45, -1.0).normalized())
	await wait_physics(3)
	var grab_intent: LISFirstPersonIntent = LISFirstPersonIntent.make(
		LISFirstPersonIntent.Kind.GRAB, 42, remote_box)
	grab_intent.eye = Vector3(0.0, 1.5, -4.2)
	grab_intent.forward = Vector3(0.0, -0.45, -1.0).normalized()
	var applied: bool = host.apply_intent(grab_intent)
	await wait_physics(40)
	check("远端意图经主机权威桥产生真实抓握",
		applied and remote_box.holder_count() == 1 and proxy.is_holding(),
		"applied=%s · holders=%d" % [str(applied), remote_box.holder_count()])

	# 退出清理
	host.remove_player(42)
	await wait_physics(6)
	check("远端玩家退出后代理与其持有关系被清理",
		remote_box.holder_count() == 0 and host.proxies.is_empty(),
		"清理后 holders=%d · proxies=%d" % [
			remote_box.holder_count(), host.proxies.size()])
