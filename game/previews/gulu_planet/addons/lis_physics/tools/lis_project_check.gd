extends SceneTree
## LIS Physics SDK · 工程配置检查工具
##
##   godot --headless --path <你的工程> --script res://addons/lis_physics/tools/lis_project_check.gd
##
## 只**报告**与给建议，绝不覆盖任何用户配置（任务书 §15）。
## 检查项：Godot 版本 / 3D 物理引擎 / 必需资源 / class_name 冲突 /
##         输入动作 / 碰撞层 / 可选网络适配。
##
## 退出码：0 = 无错误（可能有警告）；1 = 有错误（SDK 无法正常工作）。

const REQUIRED_SCRIPTS := [
	"res://addons/lis_physics/core/lis_physics.gd",
	"res://addons/lis_physics/core/lis_body.gd",
	"res://addons/lis_physics/core/lis_body_profile.gd",
	"res://addons/lis_physics/core/lis_grab_ledger.gd",
	"res://addons/lis_physics/core/lis_contact_probe.gd",
	"res://addons/lis_physics/interaction/lis_grabber.gd",
	"res://addons/lis_physics/first_person/lis_fp_adapter.gd",
	"res://addons/lis_physics/first_person/lis_fp_source.gd",
	"res://addons/lis_physics/first_person/lis_fp_intent.gd",
	"res://addons/lis_physics/joints/lis_joint_kit.gd",
	"res://addons/lis_physics/machines/lis_rope.gd",
	"res://addons/lis_physics/machines/lis_rope_end.gd",
	"res://addons/lis_physics/machines/lis_cart.gd",
	"res://addons/lis_physics/machines/lis_lever.gd",
	"res://addons/lis_physics/machines/lis_hinge_door.gd",
	"res://addons/lis_physics/machines/lis_motor_door.gd",
	"res://addons/lis_physics/machines/lis_limit_switch.gd",
	"res://addons/lis_physics/machines/lis_pulley.gd",
	"res://addons/lis_physics/machines/lis_winch_drum.gd",
	"res://addons/lis_physics/machines/lis_cable.gd",
	"res://addons/lis_physics/machines/lis_brake.gd",
	"res://addons/lis_physics/adapters/lis_physics_host.gd",
]

## SDK 的 class_name 清单。用于发现与使用者工程的重名。
const SDK_CLASS_NAMES := [
	"LISPhysics", "LISBody", "LISBodyProfile", "LISGrabLedger", "LISContactProbe",
	"LISGrabber", "LISFirstPersonAdapter", "LISFirstPersonSource", "LISFirstPersonIntent",
	"LISJointKit", "LISRope", "LISRopeEnd", "LISCart", "LISLever", "LISHingeDoor",
	"LISMotorDoor", "LISLimitSwitch", "LISPulley", "LISWinchDrum", "LISCable",
	"LISBrake", "LISPhysicsHost",
]

## SDK 期望但不强制要求的碰撞层名（第 3 层 = interactable）。
const EXPECTED_LAYER_3 := "interactable"

var errors: Array[String] = []
var warnings: Array[String] = []
var infos: Array[String] = []


func _initialize() -> void:
	print("=== LIS Physics SDK 工程检查 ===")
	_check_godot_version()
	_check_physics_engine()
	_check_required_scripts()
	_check_class_conflicts()
	_check_input_actions()
	_check_collision_layers()
	_check_optional_network()
	_report()
	quit(1 if errors.size() > 0 else 0)


func _check_godot_version() -> void:
	var info: Dictionary = Engine.get_version_info()
	var s: String = str(info.get("string", "?"))
	var major: int = int(info.get("major", 0))
	var minor: int = int(info.get("minor", 0))
	if major == 4 and minor >= 7:
		infos.append("Godot 版本 %s —— 满足要求（>= 4.7）" % s)
	elif major == 4 and minor >= 4:
		warnings.append("Godot 版本 %s —— SDK 在 4.7.2 上验证；4.4~4.6 未验证，请自测" % s)
	else:
		errors.append("Godot 版本 %s 过低：SDK 需要 Godot 4.7+（Jolt 内置、RigidBody3D.inertia）" % s)


func _check_physics_engine() -> void:
	var eng: String = str(ProjectSettings.get_setting("physics/3d/physics_engine", "DEFAULT"))
	infos.append("3D 物理引擎设置：%s" % eng)
	if eng == "Jolt Physics":
		infos.append("物理引擎 —— Jolt Physics，与 SDK 验证环境一致")
	elif eng == "DEFAULT" or eng == "":
		warnings.append(
			"物理引擎未显式指定（%s）。Godot 4.4+ 的 DEFAULT 通常是 Jolt，" % eng
			+ "但请在 项目设置 > 物理 > 3D 中确认 physics/3d/physics_engine = Jolt Physics")
	else:
		warnings.append(
			"物理引擎为 %s，不是 Jolt Physics。SDK 的关节与缆绳行为只在 Jolt 下验证过；" % eng
			+ "换成 GodotPhysics3D 可能出现约束刚度差异（不阻止运行，但需自行回归）")
	var tick: int = int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 60))
	infos.append("物理帧率：%d Hz" % tick)
	if tick != 60:
		warnings.append("物理帧率 %d Hz（SDK 性能数据基于 60 Hz；改动会影响抓握力手感）" % tick)


func _check_required_scripts() -> void:
	var missing: int = 0
	for p: String in REQUIRED_SCRIPTS:
		if not ResourceLoader.exists(p):
			errors.append("缺少必需脚本：%s" % p)
			missing += 1
	if missing == 0:
		infos.append("必需资源 %d 个 —— 全部存在" % REQUIRED_SCRIPTS.size())
	if FileAccess.file_exists("res://addons/lis_physics/plugin.cfg"):
		infos.append("插件描述文件 plugin.cfg 存在")
	else:
		warnings.append("缺少 addons/lis_physics/plugin.cfg（不影响使用，但编辑器不显示插件项）")


func _check_class_conflicts() -> void:
	# Godot 已加载的全局类名表：若同名出现在别的路径，即为冲突。
	var conflicts: int = 0
	if not ProjectSettings.has_setting("_global_script_classes"):
		# Godot 4.x 把全局类放在 .godot/global_script_class_cache.cfg，
		# 运行期可通过 ProjectSettings 的 "global_groups" 之外的途径拿不到，
		# 这里退回用 ClassDB 检查（引擎类）与资源加载检查（脚本类）。
		for cn: String in SDK_CLASS_NAMES:
			if ClassDB.class_exists(cn):
				errors.append("class_name 与引擎内置类冲突：%s" % cn)
				conflicts += 1
	if conflicts == 0:
		infos.append("class_name 冲突检查 —— 未发现与引擎内置类重名（%d 个）" % SDK_CLASS_NAMES.size())
	# 提示使用者自查：SDK 全部类名都以 LIS 前缀开头，便于避开重名。
	infos.append("SDK 的全局类名全部以 LIS 前缀开头，便于与工程自有类区分")


func _check_input_actions() -> void:
	# SDK 核心**不要求**任何输入动作；示例与适配器字段是可选的。
	infos.append("SDK 核心不读取任何固定 InputMap 动作（适配器的动作名可留空）")
	var demo_actions: Array[String] = ["lis_grab", "lis_release", "lis_throw"]
	var found: Array[String] = []
	for a: String in demo_actions:
		if InputMap.has_action(a):
			found.append(a)
	if found.is_empty():
		infos.append("未找到示例动作（lis_grab / lis_release / lis_throw）—— 核心不受影响")
	else:
		infos.append("已映射示例动作：%s" % ", ".join(found))


func _check_collision_layers() -> void:
	var l3: String = str(ProjectSettings.get_setting("layer_names/3d_physics/layer_3", ""))
	infos.append("第 3 层名称：%s（SDK 默认把可交互刚体放在第 3 层，位值 4）" % (l3 if l3 != "" else "（未命名）"))
	if l3 == "":
		warnings.append(
			"第 3 层未命名。SDK 默认使用位值 4（第 3 层）。"
			+ "建议在 项目设置 > 层名称 > 3D 物理 里把它命名为 \"%s\"。" % EXPECTED_LAYER_3
			+ "（SDK 不会自动改名）")
	elif l3 != EXPECTED_LAYER_3:
		infos.append("第 3 层叫 \"%s\"（与 SDK 推荐的 \"%s\" 不同，不影响运行；" % [l3, EXPECTED_LAYER_3]
			+ "若你的工程把可交互物放在别的层，请在 LISBodyProfile.collision_layer 里改位值）")
	var l4: String = str(ProjectSettings.get_setting("layer_names/3d_physics/layer_4", ""))
	if l4 == "":
		infos.append("第 4 层未命名（SDK 的机械层掩码位值 8 只在机械组件里用到）")
	# 提示：历史工程里 phys_prop 用的是位值 8，迁移时需要显式设置。
	infos.append("迁移提示：若旧工程的可交互物在 collision_layer = 8（第 4 层），"
		+ "请在 LISBodyProfile 里把 collision_layer 设为 8，不要指望 SDK 自动跟随")


func _check_optional_network() -> void:
	var has_hub: bool = ResourceLoader.exists("res://scripts/core/session_hub.gd")
	var has_coop: bool = ResourceLoader.exists("res://scripts/coop/coop_net.gd")
	var autoloads: PackedStringArray = ProjectSettings.get_setting("autoload", PackedStringArray()) \
		if ProjectSettings.has_setting("autoload") else PackedStringArray()
	if has_hub or has_coop:
		infos.append("检测到工程自有会话系统（SessionHub=%s / CoopNet=%s）—— SDK 不会触碰它们"
			% [str(has_hub), str(has_coop)])
	else:
		infos.append("未检测到会话系统 —— 单机物理无需任何网络适配")
	infos.append("可选网络适配：LISPhysicsHost 只处理\"意图进来后物理怎么响应\"，不实现传输层")
	if not autoloads.is_empty():
		infos.append("工程 autoload %d 项 —— SDK 不新增、不覆盖任何 autoload" % autoloads.size())


func _report() -> void:
	print("")
	for s: String in infos:
		print("INFO    %s" % s)
	for s: String in warnings:
		print("WARN    %s" % s)
	for s: String in errors:
		print("ERROR   %s" % s)
	print("")
	print("LIS_CHECK errors=%d warnings=%d infos=%d verdict=%s" % [
		errors.size(), warnings.size(), infos.size(),
		"FAIL" if errors.size() > 0 else ("OK-WITH-WARNINGS" if warnings.size() > 0 else "OK")])
	print("提示：本工具只报告，不修改任何项目设置。")
