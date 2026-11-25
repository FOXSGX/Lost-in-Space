# 《第一人称物理 SDK 接入指令》

> 本文件可**直接复制转发**给归航号、霜烬星、腐墟星以及未来新星球的开发负责人。
> 内容自包含，不需要阅读其他文档即可开始。

---

## 一、你要做的事（5 步）

| 步骤 | 做什么 | 预计耗时 |
| --- | --- | --- |
| 1 | 解压发布包，把 `addons/lis_physics` 复制到你工程的 `addons/` 下 | 1 分钟 |
| 2 | 跑一次环境体检，确认 `verdict` 不是 `FAIL` | 1 分钟 |
| 3 | 给你的第一人称玩家加一个适配器节点（约 6 行代码） | 10 分钟 |
| 4 | 加一个可抓握箱子（约 10 行代码），跑起来试试 | 10 分钟 |
| 5 | 需要门 / 车轮 / 杠杆 / 缆绳时，再照 `docs/INTEGRATION_GUIDE.md` 分批加 | 按需 |

---

## 二、安装

```text
1. 解压 LIS-PHYSICS-V1.0.0-RC1.zip
2. 复制 addons/lis_physics  →  你的工程/addons/lis_physics
3. 打开 Godot，等待资源导入
```

**只需要复制 `addons/lis_physics` 这一个目录。** 其他目录（examples / tests / tools / docs）
按需取用。

### 安装不会改你的东西

主场景、玩家控制器、全局重力、物理帧率、Jolt 求解器参数、InputMap、碰撞层名称、
网络自动加载单例、会话系统、存档、背包、任务系统、渲染设置 —— **全部不动**。

### 环境要求

* **Godot 4.7+**（在 4.7.2-stable 上验证）
* **Jolt Physics**：项目设置 → 物理 → 3D → `physics/3d/physics_engine = "Jolt Physics"`
* 物理帧率保持 **60 Hz**

### 先做环境体检

```bash
godot --headless --path <你的工程> --script res://addons/lis_physics/tools/lis_project_check.gd
```

只看最后一行：

```text
LIS_CHECK errors=0 warnings=1 infos=13 verdict=OK-WITH-WARNINGS
```

* `verdict=OK` 或 `OK-WITH-WARNINGS` → 可以继续
* `verdict=FAIL` → 按上面打印的 `ERROR` 行处理（通常是 Godot 版本过低或资源缺失）

工具**只报告，不改你的任何设置**。

---

## 三、适配要求：给你的第一人称玩家加适配器

### 情况 A：玩家是 CharacterBody3D，相机是它的子节点（最常见）

在玩家的 `_ready()` 里加：

```gdscript
var adapter := LISFirstPersonAdapter.new()
adapter.body = self            # 玩家身体
adapter.camera = $Head/Cam     # 第一人称相机（换成你的实际路径）
adapter.player_id = 1          # 单人写 1
adapter.reach = 3.2            # 交互距离（米）
add_child(adapter)
```

输入处理里：

```gdscript
# 抓 / 松
if adapter.is_holding():
    adapter.release_held(false)
else:
    adapter.grab_current()

# 抛掷
adapter.release_held(true)

# 旋转手里拿的东西
adapter.rotate_held(30.0)
```

**你的移动、视角、跳跃、输入代码一行都不用改。**

### 情况 B：玩家不是 CharacterBody3D，或节点树很特别

写一个小脚本：

```gdscript
class_name MyPlanetSource
extends LISFirstPersonSource

func fp_player_id() -> int: return 1
func fp_camera() -> Camera3D: return my_camera      # 必需
func fp_body() -> Node3D: return my_body_root
func fp_forward() -> Vector3: return -my_camera.global_transform.basis.z
# 可选：覆写 fp_hand_anchor / fp_max_lift_force / fp_is_authority 等
```

然后：

```gdscript
adapter.source = my_source
adapter.read_input = false     # 输入由你自己的控制器采样
add_child(adapter)
```

> ⚠ **重要**：一旦提供了 `source`，相机就**必须**由 `fp_camera()` 返回。
> SDK 不会再自动查找 —— 否则可能抓到场景里别的玩家的相机。

### 接入自检

```gdscript
var problems := adapter.validate_setup()
if not problems.is_empty():
    for p in problems:
        push_warning(p)
```

空数组 = 接入正确。

### 关于输入动作

SDK **不要求**任何特定动作名，也**不会**改你的 InputMap。

适配器的动作字段默认是空的（= 不响应）。要用就显式填你自己已有的动作名：

```gdscript
adapter.action_grab = &"interact"        # 你工程里已有的动作
adapter.action_throw = &"toss"
```

只有当该动作**确实存在**时适配器才会读它。

---

## 四、添加可抓握物品

```gdscript
# 1) 参数对象：这是"真实物理参数"的唯一定义处
var prof := LISBodyProfile.new()
prof.display_name = "补给箱"
prof.size = Vector3(0.6, 0.6, 0.6)     # 米
prof.mass_kg = 18.0                    # 千克 ← 请按真实质量填
prof.friction = 0.72
prof.bounce = 0.02
prof.liftable = true                   # false = 只能推/拖
prof.grip_handles = 2
prof.color = Color(0.72, 0.58, 0.34)

# 2) 建物体
var box := LISBody.new()
box.name = "SupplyCrate"
box.profile = prof
box.position = Vector3(2, 0.31, -3)
add_child(box)
```

**质量参考值**：小工具 0.5–5 kg · 木箱 8–25 kg · 大箱 30–80 kg · 机柜 120–400 kg

也可以用密度推：

```gdscript
prof.mass_kg = LISPhysics.mass_from_density(prof.size, 180.0)   # 中空木箱
```

> **请不要所有物体都用同一套质量与摩擦。** SDK 的设计前提就是"物体行为由真实参数决定"。

用自己的美术资源：

```gdscript
box.auto_build_visual = false    # 不生成盒体网格
```

碰撞体**总会**生成（物理必需品）；若你自带 `CollisionShape3D`，SDK 不会重复添加。

---

## 五、碰撞层怎么设（最容易踩的坑）

SDK 默认：

| 层 | 位值 | 建议名字 |
| --- | --- | --- |
| 世界 | 1 | world |
| 玩家 | 2 | player |
| 可交互刚体 | **4** | interactable |
| 机械 | 8 | machine |

> ⚠ **历史工程注意**：旧代码里可交互物常用 `collision_layer = 8`（第 4 层）。
> SDK **不会**自动跟随。二选一：
> * 把物体层改成 4；或
> * 在新物体上显式写 `prof.collision_layer = 8`、`prof.collision_mask = 1|2|8`

准星射线掩码：

```gdscript
adapter.ray_mask = LISPhysics.LAYER_PROP | LISPhysics.LAYER_MACHINE
```

适配器会自动把世界层并入射线掩码，所以**准星不会穿墙**。

---

## 六、测试入口

### 功能测试（需要把 `tests/` 和 `tools/` 一起复制进工程）

```powershell
pwsh -NoProfile -File tools\run_tests.ps1
```

判定口径（六条全过才算通过）：退出码为 0、断言数与期望一致、FAIL 行为 0、
打印了结果行、没有脚本错误、SKIP 不计入 PASS。

### 性能基准

```bash
godot --path <工程> res://addons/lis_physics/tools/lis_perf_bench.tscn
```

结果写到 `user://lis_perf_result.json`。

### 示例场景（放在 `examples/` 下，可直接运行）

```bash
godot --path <工程> res://examples/minimal_planet/minimal_planet.tscn
```

`minimal_planet` 是**最小接入样板**：一个箱子 + 一扇门 + 一个杠杆，全部接入代码不到 60 行。

---

## 七、注意事项（务必读）

### 1. 不要用传送式持有

```gdscript
# ❌ 每帧把物体设到手上：物体不再参与碰撞，等于放弃物理
held.global_position = hand.global_position

# ❌ 抓住时冻结：物体穿墙
held.freeze = true
```

用 `adapter.grab_current()` / `release_held()`，力与碰撞交给 SDK。

### 2. 静止物体推不动时

Godot 的 `apply_force()` **不会唤醒休眠刚体**。用：

```gdscript
body.push_force(force, offset)      # 施力并唤醒
body.push_force_centered(force)
body.push_impulse(impulse, offset)
body.wake()                         # 或先手动唤醒
```

### 3. 销毁物体前必须先拆关节

```gdscript
# ❌ 直接删（若它身上有铰链 → 场景退出时 0xC0000005）
node.queue_free()

# ✅ 用组件自带的销毁方法（内部已处理顺序）
body.despawn()
cart.despawn()
lever.despawn()
door.despawn()
winch.despawn()
rope.despawn()
LISJointKit.teardown(joint)         # 自己搭的关节
```

### 4. 不要在 `_exit_tree()` 里 `free()` 子节点

那是在引擎拆除遍历的过程中删除被遍历元素，会造成**间歇性**崩溃。
靠子节点顺序解决：用 `LISJointKit.order_joints_first()` 与
`ensure_constraints_precede()`（组件搭建时已自动调用）。

### 5. 参数越界会被自动修正并告警

质量 < 0.05 kg、尺寸非正、层为 0 —— 会被抬到安全值并 `push_warning`，
不会静默出问题。

---

## 八、能力与限制一览

### 已通过自动化测试验证 ✅

* 刚体质量 / 惯量 / 重心 / 摩擦 / 弹性 / 阻尼 / 层掩码真的生效
* 抓握：抓点落在物体表面；12 kg 举起、200 kg 只拖不举
* 抛掷：5 kg 出手 4.30 m/s，40 kg 只有 1.33 m/s（冲量有上限）
* 多人：双人抬 40 kg、四人抬 100 kg、两人反向拉扯产生 27.7° 真实偏航
* 第一人称：准星不穿墙；转身与抬头低头抓握稳定
* 真实车轮：四轮独立刚体；平地纯滚动 slip=0.038、冰面 slip=−0.598
* 杠杆：空载 +14°；24 kg 远端压下、近端压不动
* 电动门：空门开到 87.8°；被静态障碍挡在 16.4° 且力矩顶在 600 N·m
* 限位开关：必须真被压下去才闭合
* 缆绳：线密度 6.53 kg/m（理论 6.52）；复位 10 次后约束仍有效
* 制动：不冻结物体；断电失去容量
* 生命周期：机械子树 10 轮进出无残留；关节销毁 10 次无崩溃
* 两种控制器接入方式共用同一份抓握实现
* 双进程 ENet 冒烟：意图能在主机变成真实抓握，零脚本错误

### 仍有条件限制 ⚠️

1. **抓握姿态辅助是游戏化能力**：500 N·m ≈ 普通人单手的 3.3 倍（人体约 150 N·m）。不是人体力学模拟。
2. **绞盘缆绳是近似模型**：绳无质量、无真正缠绕接触，路径按折线算（机械优势差 2.3%）。
3. **客户端绳索镜像不是独立物理模拟**：只按端点摆直，形状不逐点一致。
4. **高延迟 / 丢包 / 断线重连未验证**：只做了双进程基础冒烟。
5. **性能验收未完成**：工具能跑，但没在目标最低配置上验收，V1 性能门禁未通过。
6. **自动化测试不是真人试玩**：真人试玩尚未进行。
7. **绳索销毁的引擎级边界**：高张力下销毁整条绳，约 8~20% 概率进程退出时
   `0xC0000005`（断言仍全通过）。规避：销毁前先松手，或让绳索长期存在。
8. **第三人称不在本 SDK 范围**：全游戏统一第一人称。远程角色表现（别人看到你的身体/手/持有物）
   由各星球的角色系统负责。

**完整限制清单见 `docs/PHYSICS_LIMITATIONS.md`。**

---

## 九、出错了先查这里

| 症状 | 先查 |
| --- | --- |
| 准星选不中 | `collision_layer` 与 `ray_mask` 是否同层（SDK 默认位值 4，旧工程常是 8） |
| 静止物体推不动 | 用 `push_force()` / `wake()`，别直接用 `apply_force()` |
| 退出报 `previously freed` 或崩溃 | 用 `despawn()`，别裸 `queue_free()` |
| 抓住后穿墙 | 是不是用了 `freeze` 或传送式持有 |
| 物体很飘 | 质量是否填小了 |
| 重物拖不动 | 看 `grabber.mode`，`drag` 是设计行为 |
| 门卡住 | 开度别超 88° |
| 杠杆压不动 | 用 `lever.arm_length()` 核对力臂 |
| `InputMap action doesn't exist` | 动作没映射；SDK 不会替你创建 |

---

## 十、反馈问题请带上

* SDK 版本（`LISPhysics.SDK_VERSION`）
* Godot 版本 + 物理引擎设置
* `lis_project_check.gd` 的完整输出
* 复现步骤（帧数、参数越具体越好）
* `SCRIPT ERROR` 原文
* 崩溃时的退出码（如 `-1073741819` = `0xC0000005`）

---

**当前版本：1.0.0-rc1（候选版本）。**
可以用于试用与集成；**请勿**在此版本上宣布正式稳定版发布 —— 性能验收尚未完成。
