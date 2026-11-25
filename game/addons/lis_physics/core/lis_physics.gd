class_name LISPhysics
extends RefCounted
## LIS Physics SDK · 全局常量与物理小工具
##
## 本类只提供**纯函数与常量**，不持有任何节点、不读写项目设置。
## 所有涉及项目配置的检查都在 tools/lis_project_check.gd 里，只报告不改动。

## SDK 版本（与 plugin.cfg、VERSION.json 保持一致）。
const SDK_VERSION := "1.0.0-rc1"
const SDK_NAME := "LIS Physics"
const SDK_ID := "lis_physics"

## 推荐的 Godot 版本。不匹配时 check 工具只报警告，不阻止运行。
const REQUIRED_GODOT := "4.7"
const REQUIRED_PHYSICS_ENGINE := "Jolt Physics"

# ---------------------------------------------------------------------------
# 碰撞层
#
# 这些是**位值**（collision_layer 的写法），不是层序号。
# SDK 默认占用第 3 层（值 4）作为"可交互刚体"，与《迷失太空》现有工程的
# 3d_physics/layer_3="interactable" 命名一致。
#
# 历史工程里 phys_prop.gd 用的是 8（第 4 层），因此迁移时要么把层名对齐，
# 要么在 LISBodyProfile 里把 collision_layer 显式改成 8。SDK 不替使用者决定。
# ---------------------------------------------------------------------------
const LAYER_WORLD := 1 << 0      ## 1  静态世界
const LAYER_PLAYER := 1 << 1     ## 2  玩家身体
const LAYER_PROP := 1 << 2       ## 4  可交互刚体（默认）
const LAYER_MACHINE := 1 << 3    ## 8  机械设备
const LAYER_TRIGGER := 1 << 4    ## 16 触发器

## 默认的可交互刚体层与掩码：与世界、玩家、同类刚体碰撞。
const DEFAULT_BODY_LAYER := LAYER_PROP
const DEFAULT_BODY_MASK := LAYER_WORLD | LAYER_PLAYER | LAYER_PROP

## 交互射线的默认掩码（只选可交互刚体与机械）。
const DEFAULT_RAY_MASK := LAYER_PROP | LAYER_MACHINE


## 第 index 层（1..32）对应的位值。
static func layer_bit(index: int) -> int:
	if index < 1 or index > 32:
		return 0
	return 1 << (index - 1)


## 某个位掩码里包含哪些层序号（1 起）。
static func layers_in(mask: int) -> Array[int]:
	var out: Array[int] = []
	for i in range(1, 33):
		if mask & layer_bit(i):
			out.append(i)
	return out


## 项目重力（m/s²，正值）。只读。
static func gravity() -> float:
	return float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))


## 当前 3D 物理引擎名（"Jolt Physics" / "GodotPhysics3D" / ...）。
static func physics_engine_name() -> String:
	return str(ProjectSettings.get_setting("physics/3d/physics_engine", "DEFAULT"))


## 物理帧率。
static func physics_ticks_per_second() -> int:
	return int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 60))


## 由尺寸与密度推质量（kg）。density 单位 kg/m³；
## 货箱类（中空木箱）常用 120–260，实心金属件 1200–7800。
static func mass_from_density(size: Vector3, density: float) -> float:
	var volume: float = absf(size.x * size.y * size.z)
	return maxf(0.05, volume * maxf(density, 1.0))


## 均匀长方体的主转动惯量（kg·m²），按 (x, y, z) 三个轴给出。
## I_xx = m/12·(h²+d²) 等。
static func box_inertia(mass: float, size: Vector3) -> Vector3:
	var m: float = maxf(mass, 0.001)
	var s: Vector3 = size.abs()
	return Vector3(
		m / 12.0 * (s.y * s.y + s.z * s.z),
		m / 12.0 * (s.x * s.x + s.z * s.z),
		m / 12.0 * (s.x * s.x + s.y * s.y)
	)


## 绕世界轴 axis 的转动惯量估算（用于"手能施加多大角加速度"）。
static func inertia_about(body: RigidBody3D, axis_world: Vector3, size: Vector3) -> float:
	if body == null:
		return 1.0
	var inv: Basis = body.global_transform.basis.inverse()
	var d: Vector3 = (inv * axis_world).normalized()
	var half: Vector3 = size * 0.5
	var u: Vector3 = d.cross(Vector3.UP)
	if u.length_squared() < 0.0001:
		u = d.cross(Vector3.RIGHT)
	u = u.normalized()
	var v: Vector3 = d.cross(u).normalized()
	var a: float = 2.0 * (absf(u.x) * half.x + absf(u.y) * half.y + absf(u.z) * half.z)
	var b: float = 2.0 * (absf(v.x) * half.x + absf(v.y) * half.y + absf(v.z) * half.z)
	return maxf(body.mass / 12.0 * (a * a + b * b), 1.0e-4)


## 沿某方向的半展宽（米）。dir 需为单位向量。
static func extent_along(size: Vector3, dir: Vector3) -> float:
	var d: Vector3 = dir.normalized()
	var half: Vector3 = size * 0.5
	return absf(d.x) * half.x + absf(d.y) * half.y + absf(d.z) * half.z


## 把向量按最大长度截断（保持方向）。
static func clamp_length(v: Vector3, limit: float) -> Vector3:
	var l: float = v.length()
	if l <= limit or l < 1.0e-9:
		return v
	return v * (limit / l)


## 向量是否全是有限值（用于 NaN / INF 检测）。
static func is_finite_vec3(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


## 版本串，写进日志与报告。
static func version_string() -> String:
	return "%s %s (Godot %s · %s)" % [
		SDK_NAME, SDK_VERSION, str(Engine.get_version_info().get("string", "?")),
		physics_engine_name()]
