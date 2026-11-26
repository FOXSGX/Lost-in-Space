# 快速上手（十分钟跑通第一次抓握）

本文假设你已经把 `addons/lis_physics` 复制进工程（见 [README.md](README.md)）。
目标：**从一个空场景开始，做出"能走过去、用准星抓起来、扔出去"的箱子。**

---

## 第 0 步：确认工程设置

打开 项目设置：

* **物理 → 3D → 物理引擎** = `Jolt Physics`
* **层名称 → 3D 物理 → 第 3 层** = `interactable`（名字随意，但建议起这个名字）
* **物理 → 通用 → 每秒物理帧数** = `60`

不确定就跑一次检查工具：

```bash
godot --headless --path . --script res://addons/lis_physics/tools/lis_project_check.gd
```

它只报告，不会改你的设置。

---

## 第 1 步：做一个最小场景

新建场景，根节点用 `Node3D`，命名 `Main`。给它加：

1. 一个 **`CSGBox3D`**（或 `StaticBody3D` + `CollisionShape3D`），尺寸 `(20, 0.4, 20)`，
   放在 `y = -0.2` —— 这就是地面。
2. 一个 **`DirectionalLight3D`**，随便转个角度。
3. 一个 **`WorldEnvironment`**（可选，但没它场景会很黑）。

把 `Main` 存成 `res://main.tscn`，并在 项目设置 → 应用 → 运行 → 主场景 里选它。

---

## 第 2 步：加一个第一人称玩家

有两种接入方式，**选一种即可**。两种方式用的是同一套抓握实现，不存在"功能少一半"。

### 方式 A：CharacterBody3D + Camera3D（推荐，最常见）

新建脚本 `res://player.gd`：

```gdscript
extends CharacterBody3D

const SPEED := 4.2
const GRAVITY := 22.0
const MOUSE_SENS := 0.0022

var adapter: LISFirstPersonAdapter
var camera: Camera3D
var yaw := 0.0
var pitch := 0.0

func _ready() -> void:
    collision_layer = LISPhysics.LAYER_PLAYER
    collision_mask = LISPhysics.LAYER_WORLD | LISPhysics.LAYER_PROP

    var cs := CollisionShape3D.new()
    var cap := CapsuleShape3D.new()
    cap.radius = 0.32
    cap.height = 1.75
    cs.shape = cap
    cs.position = Vector3(0, 0.9, 0)
    add_child(cs)

    camera = Camera3D.new()
    camera.position = Vector3(0, 1.62, 0)   # 眼高
    camera.near = 0.05
    camera.current = true
    add_child(camera)

    # ↓↓↓ SDK 接入：只有这几行 ↓↓↓
    adapter = LISFirstPersonAdapter.new()
    adapter.body = self        # 玩家身体
    adapter.camera = camera    # 第一人称相机
    adapter.player_id = 1      # 玩家身份（单人就是 1）
    add_child(adapter)
    # ↑↑↑ SDK 接入结束 ↑↑↑

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        yaw -= event.relative.x * MOUSE_SENS
        pitch = clampf(pitch - event.relative.y * MOUSE_SENS, -1.4, 1.4)
    elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        if adapter.is_holding():
            adapter.release_held(false)     # 松手
        else:
            adapter.grab_current()          # 抓准星指着的东西

func _physics_process(delta: float) -> void:
    rotation.y = yaw
    camera.rotation.x = pitch
    if not is_on_floor():
        velocity.y -= GRAVITY * delta
    var input := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
    var wish := transform.basis * Vector3(input.x, 0.0, input.y)
    wish.y = 0.0
    velocity.x = wish.x * SPEED
    velocity.z = wish.z * SPEED
    move_and_slide()
```

把 `CharacterBody3D` 节点加进 `Main`，挂上这个脚本，放在 `y = 1.2` 左右。

> 用 `ui_left` 这类内置动作是为了让示例能直接跑。正式项目请换成你自己的
> WASD 动作名 —— SDK **不要求**任何特定动作名。

### 方式 B：自定义控制器（节点树与输入封装都不同）

如果你的玩家不是 `CharacterBody3D`，或者相机藏在别的层级里，写一个协议脚本：

```gdscript
class_name MySource
extends LISFirstPersonSource

var cam: Camera3D
var body_root: Node3D

func fp_player_id() -> int: return 1
func fp_camera() -> Camera3D: return cam
func fp_body() -> Node3D: return body_root
func fp_forward() -> Vector3: return -cam.global_transform.basis.z
func fp_eye_position() -> Vector3: return cam.global_position
func fp_max_lift_force() -> float: return 1500.0   # 力气大小，可选
```

然后：

```gdscript
var adapter := LISFirstPersonAdapter.new()
adapter.source = my_source_node   # 只需要给协议对象
adapter.read_input = false        # 输入由你自己的控制器采样
add_child(adapter)
```

**关键区别**：一旦填了 `source`，SDK 就**不再**在节点树里自动找相机 ——
相机必须由协议回答。否则会把场景里别人的相机当成自己的。

---

## 第 3 步：加一个可抓握的箱子

在 `Main` 的脚本里（或在编辑器里手动搭）：

```gdscript
extends Node3D

func _ready() -> void:
    # 1) 写一份参数：这是"真实物理参数"的唯一定义处
    var prof := LISBodyProfile.new()
    prof.display_name = "木箱"
    prof.size = Vector3(0.6, 0.6, 0.6)   # 米
    prof.mass_kg = 12.0                  # 千克
    prof.friction = 0.7                  # 摩擦系数
    prof.bounce = 0.02                   # 弹性
    prof.liftable = true                 # 能举起来
    prof.color = Color(0.72, 0.58, 0.34)
    prof.grip_handles = 2                # 表面画两个抓握把手

    # 2) 建物体
    var box := LISBody.new()
    box.name = "Crate"
    box.profile = prof
    box.position = Vector3(0, 0.31, -2)
    add_child(box)
```

> `LISBody` 会自动建立**碰撞体**（物理必需）与**视觉盒体 + 把手**（可关掉：
> `box.auto_build_visual = false`，然后自己挂美术资源）。
> 注意：关掉视觉**不会**关掉碰撞体 —— 碰撞体总是会建。

---

## 第 4 步：抓握测试

运行场景（F5）。你应该能：

1. 用 WASD 走动、鼠标环视；
2. 走到箱子前，准星指向它 → 按左键抓住；
3. 后退 → 箱子被**力**拉过来（不是瞬移）；
4. 再按左键 → 松手，箱子保留惯性继续滑；
5. 换一个 **500 kg** 的箱子（`prof.mass_kg = 500.0`）→ 拖得动，但**举不起来**，
   因为它超过单人举升上限（默认 42 kg）。

这就是 SDK 的全部核心行为。

---

## 第 5 步：加一扇门

```gdscript
var door := LISHingeDoor.new()
door.position = Vector3(0, 0, -6)
add_child(door)
```

门板是真实刚体 + 竖直铰链。玩家用身体顶它、或者用抓握拽它，门会**真的转开**。
没有 `progress` 变量、没有补间动画。

> **竖直门轴不会因为重力自己开合** —— 重力与门轴平行，不产生绕轴力矩。
> 这条是 SDK 明确处理的（历史实现曾把重力算成开门力矩）。

---

## 第 6 步：加一辆真实推车

```gdscript
var cart := LISCart.new()
cart.position = Vector3(5, 0.60, 0)   # 车身中心高度 0.60 让四轮刚好触地
add_child(cart)
```

它有四个**独立刚体车轮**与四个真实轮轴铰链。跑一下，推动它，
读 `cart.average_wheel_spin() * LISCart.WHEEL_RADIUS` 与 `cart.telemetry_forward_speed`：
两者应该接近（纯滚动）；在冰面上会明显分离（打滑）。

---

## 第 7 步：跑示例与测试

八个示例场景在 `examples/` 下，每个是一个可运行的 `.tscn`：

```bash
godot --path <工程> res://examples/first_person_sandbox/first_person_sandbox.tscn
```

跑自动化测试（需要 `tests/` 与 `tools/` 一起复制进工程）：

```powershell
pwsh -NoProfile -File tools\run_tests.ps1
```

跑性能基准：

```bash
godot --path <工程> res://addons/lis_physics/tools/lis_perf_bench.tscn
```

---

## 常见问题

| 现象 | 原因与处理 |
| --- | --- |
| 准星选不中物体 | 检查 `LISBodyProfile.collision_layer` 与 `adapter.ray_mask` 是否落在同一层。SDK 默认用第 3 层（位值 4），旧工程常用位值 8 |
| 抓住物体但拉不动 | 物体太重进入了"拖推模式"。看 `grabber.mode`；这是**设计行为**，不是 bug |
| 物体抓起来很飘 | 检查物体质量是否填得太小（默认演示值是轻物件），以及 `hold_stiffness` |
| 静止的物体推不动 | Godot 的 `apply_force` 不会唤醒休眠刚体。用 `LISBody.push_force()` / `push_force_centered()` / `push_impulse()`，或先调 `wake()` |
| 退出场景时报 `previously freed` 或崩溃 | 销毁刚体**之前**必须先拆掉引用它的关节。用 `despawn()` 或 `LISJointKit.teardown()` —— 详见 [INTEGRATION_GUIDE.md](INTEGRATION_GUIDE.md) |
| 门开着开着被门框卡住 | 门的开度不要超过 88°（SDK 默认值就是 88°） |

下一步：[INTEGRATION_GUIDE.md](INTEGRATION_GUIDE.md)。
