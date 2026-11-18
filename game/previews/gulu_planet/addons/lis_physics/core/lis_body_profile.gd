class_name LISBodyProfile
extends Resource
## LIS Physics SDK · 刚体参数配置
##
## 一件可交互物体的全部**真实物理参数**都放在这里，而不是散落在脚本常量里。
## 这样同一套 SDK 能同时表达"2 kg 的工具箱"和"220 kg 的机柜"，
## 不需要为每种重量改代码。
##
## 用法：
##   var p := LISBodyProfile.new()
##   p.display_name = "木箱"
##   p.size = Vector3(0.6, 0.6, 0.6)
##   p.mass_kg = 12.0
##   p.friction = 0.7
##   $Body.apply_profile(p)
##
## 所有字段都有合理的默认值；不填也能跑，但默认值是**演示用轻物件**，
## 正式关卡请按真实质量填写。

@export_group("身份")
## 显示名（HUD / 提示用），不参与物理。
@export var display_name: String = "物理物体"
## 可选标签，供使用者自己的系统筛选（SDK 不解释其含义）。
@export var tags: PackedStringArray = PackedStringArray()

@export_group("几何与质量")
## 外形尺寸（米）。碰撞体与抓握点几何都以它为准。
@export var size: Vector3 = Vector3(0.6, 0.6, 0.6)
## 质量（kg）。低于 0.05 kg 会被抬到 0.05，避免求解器病态。
@export_range(0.05, 2000.0, 0.05, "or_greater") var mass_kg: float = 12.0
## 重力缩放。1 = 正常重力。
@export_range(0.0, 4.0, 0.01) var gravity_scale: float = 1.0
## 是否允许被举起。false = 只能贴地推 / 拖（重物手感）。
@export var liftable: bool = true

@export_group("表面")
## 摩擦系数。0.02 冰面 / 0.6–0.9 木箱 / 1.1+ 橡胶轮胎。
@export_range(0.0, 3.0, 0.01) var friction: float = 0.7
## 弹性。真实货箱一般 ≤ 0.05。
@export_range(0.0, 1.0, 0.01) var bounce: float = 0.02
## true = 只用本物体的摩擦，忽略接触面摩擦（手感可预测）；
## false = 与接触面合成（"冰面 vs 橡胶面"这类实验必须用 false）。
@export var rough: bool = true

@export_group("阻尼与求解")
## 线阻尼（1/s）。真实刚体应接近 0；不要用它伪装滚动阻力。
@export_range(0.0, 10.0, 0.01) var linear_damp: float = 0.06
## 角阻尼（1/s）。门轴 / 轮轴的真实阻力应放在关节或这里。
@export_range(0.0, 20.0, 0.01) var angular_damp: float = 0.35
## 是否允许休眠。静置的货物允许休眠可以省性能。
@export var can_sleep: bool = true
## 连续碰撞检测。快速抛掷物建议开启。
@export var continuous_cd: bool = true
## 是否接触监视（contact_monitor）。查询受阻状态需要它。
@export var contact_monitor: bool = true
## 上报的接触点上限。
@export_range(0, 32, 1) var max_contacts: int = 4

@export_group("碰撞层")
## 本物体所在层（位值，不是层序号）。默认 4 = 第 3 层。
@export_flags_3d_physics var collision_layer: int = LISPhysics.DEFAULT_BODY_LAYER
## 与哪些层碰撞（位值）。默认 世界 | 玩家 | 同类。
@export_flags_3d_physics var collision_mask: int = LISPhysics.DEFAULT_BODY_MASK

@export_group("重心与惯量")
## 用自定义重心（否则用引擎按碰撞体自动算）。
@export var use_custom_center_of_mass: bool = false
## 自定义重心（物体局部坐标）。
@export var center_of_mass: Vector3 = Vector3.ZERO
## 用自定义惯量张量（主惯性矩，kg·m²）。0 表示交给引擎。
@export var inertia: Vector3 = Vector3.ZERO

@export_group("外观")
## 基础颜色。SDK 示例用纯色盒体，正式项目请关掉 auto_build_visual 用美术资源。
@export var color: Color = Color(0.62, 0.52, 0.32)
@export var metallic: float = 0.15
@export var roughness: float = 0.72
## 是否自发光（警示条、指示灯）。
@export var emission: bool = false
@export var emission_energy: float = 0.35

@export_group("抓握")
## 物体表面显示的抓握把手数量（0 = 不显示）。
@export_range(0, 6, 1) var grip_handles: int = 2
## 是否自动加入 "lis_interactable" 组（供交互射线筛选）。
@export var interactable: bool = true
## 兼容组名：迁移旧工程时可填 "interactable" 等既有组，SDK 会自动加入。
@export var group_aliases: PackedStringArray = PackedStringArray()


## 参数越界修正。返回修正说明列表（空 = 无需修正）。
func sanitize() -> PackedStringArray:
	var notes := PackedStringArray()
	if size.x <= 0.001 or size.y <= 0.001 or size.z <= 0.001:
		size = Vector3(maxf(size.x, 0.05), maxf(size.y, 0.05), maxf(size.z, 0.05))
		notes.append("size 有非正分量，已抬到 0.05 m")
	if mass_kg < 0.05:
		mass_kg = 0.05
		notes.append("mass_kg < 0.05，已抬到 0.05 kg")
	if collision_layer == 0:
		collision_layer = LISPhysics.DEFAULT_BODY_LAYER
		notes.append("collision_layer 为 0，已设为默认可交互层")
	if collision_mask == 0:
		notes.append("collision_mask 为 0：该物体不会与任何东西碰撞（有意为之请忽略）")
	return notes


## 均质物体的理论转动惯量（只读，用于对齐）
func theoretical_inertia() -> Vector3:
	return LISPhysics.box_inertia(mass_kg, size)


## 一行摘要（日志 / 检查工具用）
func describe() -> String:
	return "%s · %.2f kg · %s m · μ=%.2f · layer=%d/mask=%d" % [
		display_name, mass_kg, str(size), friction, collision_layer, collision_mask]
