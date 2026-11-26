# 迁移指南（MIGRATION_GUIDE）

**把旧的"脚本移动物体"逐步换成真实物理。**

---

## 第 0 条原则：不要一次性推翻全部旧机关

任务要求明确规定：**不得要求其他星球一次性推翻全部旧机关。**

正确的做法是**按价值与风险分批替换**：

| 批次 | 替换什么 | 为什么先做这些 |
| --- | --- | --- |
| 第 1 批 | 单独的可搬运物（箱子、工具、货物） | 影响面最小、玩家立刻能感觉到差异、出问题也容易回退 |
| 第 2 批 | 一扇门 / 一个按钮 / 一个开关 | 单个机关，边界清楚 |
| 第 3 批 | 杠杆、配重、简单机械 | 需要理解力矩与限位，但仍是单点 |
| 第 4 批 | 组合机械（推车 + 坡道 + 货物） | 依赖前几批的经验 |
| 第 5 批 | 绳索、绞盘、滑轮 | SDK 里最复杂、边界最多的一类，放最后 |

每一批都应当**单独验收**，不要攒在一起。

---

## 第 1 步：先找出该替换的地方

旧工程里搜这几类代码，它们都是"脚本假装物理"的信号：

| 搜索关键词 | 说明 |
| --- | --- |
| `global_position =` / `position =`（在刚体上） | 直接写刚体位姿 = 传送 |
| `freeze = true` 配合位置赋值 | 冻结 + 传送式持有 |
| `progress` / `t` + `lerp` 驱动位移 | 脚本进度条假装运动 |
| 按速度设置车轮旋转 | 车轮动画，不是真实滚动 |
| `rotation_speed` / `rotate_y(delta * speed)` | 脚本直接转角度 |
| `move_toward` 用于门/杠杆角度 | 脚本插值到目标角 |

---

## 第 2 步：反模式 → 正确做法对照

### 2.1 抓握：传送 → 力

```gdscript
# ❌ 旧：每帧把物体设到手上
func _process(_delta):
    if held:
        held.global_position = hand.global_position
        held.global_rotation = hand.global_rotation

# ✅ 新：把"想抓"这件事交给 SDK
adapter.grab_current()      # 抓
adapter.release_held(true)  # 抛
# 力、作用点、上限、碰撞、惯性全部由 LISGrabber 处理
```

**换成新做法后你会立刻看到**：重物拖得动但举不起、物体撞墙会停、
松手后保留惯性、两人一起抬会更容易。

### 2.2 冻结 + 传送 → 真实持有

```gdscript
# ❌ 旧：抓住时冻结，避免它乱动
held.freeze = true
held.global_position = anchor.global_position

# ✅ 新：什么都不用做
# SDK 的抓握不冻结、不关碰撞，物体始终参与真实碰撞
```

### 2.3 车轮动画 → 真实轮轴

```gdscript
# ❌ 旧：按车速播车轮动画
func _process(delta):
    var speed = velocity.length()
    for w in wheels:
        w.rotate_x(speed * delta / radius)

# ✅ 新：四个独立刚体车轮 + 四个铰链，滚动来自接触摩擦
var cart := LISCart.new()
add_child(cart)
# 想读转速就读 cart.average_wheel_spin()
```

### 2.4 脚本推进的门 → 真实铰链 / 马达

```gdscript
# ❌ 旧：脚本 lerp 门的角度
func _process(delta):
    if opening:
        progress = minf(progress + delta * speed, 1.0)
    panel.rotation.y = lerpf(0, deg_to_rad(88), progress)

# ✅ 新
var door := LISMotorDoor.new()
add_child(door)
door.set_request(true)      # 马达带限矩，撞到东西会堵转
```

```gdscript
# ❌ 旧：门是 StaticBody3D，靠触发器"打开"
# ✅ 新：LISHingeDoor —— 门板是真刚体，用身体推就开
```

### 2.5 触发式开关 → 真实接触开关

```gdscript
# ❌ 旧：Area3D 进入就认为"开关被压下"
func _on_area_body_entered(body):
    switch_closed = true

# ✅ 新：顶杆是真刚体，弹簧是真实弹簧力，必须**真的被压下去**才算闭合
var sw := LISLimitSwitch.new()
add_child(sw)
sw.state_changed.connect(func(closed): door.set_request(closed))
```

### 2.6 脚本起吊 → 缆绳机构

```gdscript
# ❌ 旧：按 E 把货物 lerp 到目标位置
# ✅ 新
var rope := LISRope.new()
add_child(rope)
await get_tree().physics_frame
rope.build(10, 0.34, from, dir, true)
rope.anchor_first_to(post, post_pos)
rope.tie_last_to(crate, crate_surface_point)
# 玩家抓自由端，靠移动身体牵引 —— 张力真实传递
```

---

## 第 3 步：碰撞层怎么迁移

这是最容易出问题的一步。

| 旧工程 | SDK 默认 | 处理方式 |
| --- | --- | --- |
| `collision_layer = 8`（第 4 层） | `4`（第 3 层） | 二选一：改旧物体为 4，或在新物体上显式写 8 |
| `collision_mask = 1 \| 2 \| 8` | `1 \| 2 \| 4` | 同上 |
| 层名 `interactable` 在第 3 层 | 一致 | 无需处理 |
| 层名 `machine` 在第 4 层 | `LAYER_MACHINE = 8` | 一致 |

**SDK 不会自动跟随你的旧设置**（这是有意的：静默改层会导致更难查的碰撞问题）。

推荐做法：在新物体上显式声明，让差异可见：

```gdscript
prof.collision_layer = 8          # 与本星球既有层保持一致
prof.collision_mask = 1 | 2 | 8
```

---

## 第 4 步：玩家控制器怎么迁移

### 若你的控制器已经是 CharacterBody3D + Camera3D

加一个适配器节点即可，**不要改你的移动/视角代码**：

```gdscript
var adapter := LISFirstPersonAdapter.new()
adapter.body = self
adapter.camera = camera
adapter.player_id = 1
add_child(adapter)
```

然后在输入处理里调用 `grab_current()` / `release_held()` / `rotate_held()`。

### 若你的控制器不是 CharacterBody3D

写一个 `LISFirstPersonSource` 子类（见 [QUICKSTART.md](QUICKSTART.md) 方式 B）。
**你的节点树与输入封装都不需要改。**

### 旧工程里的"E 键交互"怎么办

SDK 不抢你的 E 键。两种做法：

1. **继续用你的 E 键**：在交互分支里调用 `adapter.grab_current()`；
2. **用 SDK 的适配器动作**：设 `adapter.action_grab = &"your_action"`，
   适配器会读它（但**只在该动作已存在时**读取，绝不会改你的 InputMap）。

---

## 第 5 步：销毁路径怎么迁移

旧工程常见的销毁写法在新体系下会崩。对照修改：

```gdscript
# ❌ 旧：直接删掉物体（若它身上有铰链 → 退出时崩溃）
node.queue_free()

# ✅ 新：用组件自带的销毁方法
body.despawn()
cart.despawn()
lever.despawn()
door.despawn()
winch.despawn()
rope.despawn()

# ✅ 自己搭的关节
LISJointKit.teardown(joint)
```

**规则**：释放刚体之前，必须先处理引用它的约束与持有关系。

---

## 第 6 步：分阶段验收清单

每完成一批替换，跑这几项：

| 检查项 | 怎么做 |
| --- | --- |
| 没有脚本报错 | 运行场景，看输出面板有没有 `SCRIPT ERROR` |
| 反复进出场景不崩 | 进出场景 10 次（`integration_lifecycle` 测试做的就是这件事） |
| 物体不会自己漂移 | 静置 100 帧后看速度是否接近 0 |
| 质量差异可见 | 同样推力下，重物位移明显小于轻物 |
| 抓握不会被无限放大 | 抓住一个 200 kg 物体，它不应该被举起来 |
| 松手保留惯性 | 移动中松手，物体会继续滑 |
| 销毁无残留 | 场景退出后不应出现 `previously freed` |

---

## 第 7 步：常见迁移问题的根因

| 现象 | 根因 | 处理 |
| --- | --- | --- |
| 抓住物体后它穿过墙 | 用了 `freeze` 或传送式持有 | 改用 `LISGrabber` |
| 静止物体推不动 | Godot 的 `apply_force` 不唤醒休眠刚体 | 用 `push_force()` / `wake()` |
| 退出场景崩溃（0xC0000005） | 刚体先于引用它的关节被释放 | 用 `despawn()` / `teardown()` |
| 准星选中了墙后面的箱子 | 射线掩码没包含世界层 | 适配器已自动并入；自定义射线时请自行加入 |
| 门开了之后卡住不放 | 开度超过 88° 扫到门框 | 用默认 `open_deg = 88.0` |
| 杠杆压不动 | 货物放在了错误的力臂位置，或载物台被挡边卡住 | 用 `lever.arm_length()` 核对力臂 |
| 车轮不转、车身在滑 | 车轮埋进地面（漏了 `add_child` 再设 `global_transform`） | 参考 `LISCart` 的搭建顺序 |
| 缆绳复位后"报告连接正常但其实断了" | 旧实现的 `enable_mirror(false)` 会清空关节接线 | SDK 已修正：`enable_mirror` 只冻结绳段 |

---

## 第 8 步：不要迁移的东西

| 不要动 | 原因 |
| --- | --- |
| 正式 `game/` 与其他星球关卡 | 本轮 SDK 只做封装，不改正式关卡 |
| 已有的 SessionHub / CoopNet / 身份 / 存档 | SDK 绝不自动安装或覆盖它们 |
| 你的 InputMap | SDK 只读、不改 |
| 你的主场景与渲染设置 | 同上 |
| 共振星剧情 flag 与第五幕专属逻辑 | 不属于公共 SDK（见下表） |

### 明确**没有**进入公共 SDK 的东西

| 组件 | 为什么不适合公共化 |
| --- | --- |
| 第五幕液压 / 棘爪 / 剧情时序 | 强依赖共振星剧情与任务 flag |
| 晶体精密插槽引导 | 是该幕特意做的引导交互，不是通用自由抓握 |
| 任务完成 flag / 结算系统 | 属于各星球的任务系统，不是物理能力 |
| 工程内特定 PlayerController | 各星球控制器不同，公共 SDK 不能绑定其中一个 |
| 特定的提示文案与 HUD | 属于各星球的 UX 设计 |

需要这些能力的星球，请在自己的工程里基于 SDK 的公共组件再包一层。

---

## 附：迁移检查脚本

`tools/lis_project_check.gd` 会报告环境问题（版本、引擎、层名、资源、类名冲突）。
建议在迁移前后各跑一次，对比输出：

```bash
godot --headless --path <你的工程> --script res://addons/lis_physics/tools/lis_project_check.gd
```
