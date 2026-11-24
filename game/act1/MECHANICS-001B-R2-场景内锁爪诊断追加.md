# MECHANICS-001B-R2 追加：正式场景内锁爪诊断（第 2 轮）

> 承接 `MECHANICS-001B-R2-真实旋转锁爪与电源模块安装最终完成报告.md`
> 结论不变：**NO-GO**；已回退，001A 基线完好（专项 `failures=0`、全流程 `completion=true`）

---

## 1. 本轮新增的关键事实

### 1.1 一个必须纠正的"假成功"

上一轮我一度看到 `motor: closed_at=99 angle=-3.141`，以为锁爪在正式场景里转起来了。
**那是假的**：当时用的角度是 `jaw.global_rotation.y`，而铰链轴是水平的，
`rotation.y` 在刚体被约束后跳到 ±π 是万向锁表现，不是绕轴旋转。

本轮改用**绕真实铰链轴的有符号角**（`start_basis⁻¹·rel` 投影到轴上）后立刻暴露：
```
PROBE motor: closed_at=-1 angle=0.000 w=0.000 stalled=true
```
→ 锁爪在正式场景里**从未真正绕轴转动**。这条经验写在这里，避免以后再被同样的读数欺骗。

### 1.2 正式场景内的完整状态打印（探针 `mech001b_r2_scene_probe`）

```
PROBE cart=ok jaw=ok hinge=ok
PROBE jaw mass=45.0 grav=1.00 ang_damp=0.80 mask=3 sleeping=false freeze=false
PROBE hinge a=../ClampBracket b=../ClampJaw axis=(0,0,-1) anchor=(5.27,1.52,-4.85)
PROBE motor_flag=on target=0.00 max_impulse=0.0 limit=on lo=-0.03 hi=1.75
PROBE jaw_pos=(5.27,1.52,-4.85) bracket_pos=(5.27,1.52,-4.85)
PROBE impulse30(绕真实轴): angle 0.000 → 0.000  w_axis=+0.000
PROBE impulse_mask0:       angle 0.000 → 0.000  w_axis=+0.000
PROBE impulse_benchparams: angle 0.001 → 0.000  w_axis=+0.000
PROBE motor: closed_at=-1 angle=0.000 w=0.000 timer=4.00 stalled=true
```

即：关节绑定正确、轴向正确、限位正确、马达标志与参数正确、刚体不冻结不休眠、
**即使把碰撞掩码清零、把质量/重力/阻尼全部对齐台架，角冲量仍然产生 0 角速度**。

---

## 2. 已排除的差异（本轮逐个测过）

| # | 差异 | 处理 | 结果 |
|---|---|---|---|
| 1 | 铰链挂在刚体下、事后赋 `global_transform` | 改挂中性父节点、`transform` 前置 | 仍锁死（但这是台架能转的必要条件） |
| 2 | 铰链轴为竖直（`Basis(Z,π/2)`） | 改水平（`Basis(UP,π/2)`，轴 −Z） | 仍锁死 |
| 3 | `stage` 带旋转导致局部基错向 | `stage.basis⁻¹ × 世界基` 换算 | 仍锁死 |
| 4 | 锁爪与支架出生重叠 | `add_collision_exception_with(bracket)` | 仍锁死 |
| 5 | 锁爪与场景其它几何重叠 | 探针里把 `collision_mask` 置 0 | **仍锁死**（且 `get_colliding_bodies()` 为空） |
| 6 | 质量/重力/角阻尼与台架不同 | 探针里改成 22 kg / grav 0 / damp 0.1 | **仍锁死** |
| 7 | 马达堵转判定第一帧就撤力矩 | 加 0.60 s 启动宽限 | 仍锁死（堵转逻辑本身已验证正确） |
| 8 | 角冲量方向不对（探针自身 bug） | 改为绕真实轴施加 | 仍锁死（这一步纠正了诊断有效性） |

**台架对照**（同一份构造、同一测量方法）：
```
STEP 2 马达 +1.25 / max_impulse=40 → 0.802 rad（真实转动）
STEP 3 马达 -1.25                 → 78 帧回到 0.043 rad
```

所以：**台架能转、场景不能转**，而场景里能想到的刚体/关节/碰撞/参数差异都已被排除。
剩下的可疑点只剩"act01 场景树本身"（例如其它 Joint3D 的节点绑定、或舞台根节点的
`freeze`/`process_mode`/`physics_interpolation` 之类的上下文属性），本轮未继续二分。

---

## 3. 当前状态（重要）

已回退到 001A，并验证：

```
MECH001A_DONE failures=0            ← 001A 专项 5 项
RESULT failures=0 completion=true   ← 第一幕 21 项全流程
```

* **WIP**：`physics_lab/wip_mechanics001b/`（本轮含：台架验证过的铰链构造、绕真实轴测角、
  启动宽限、碰撞例外、滑槽 `_ramp_basis`）
* **探针**：`game/act1/tests/mech001b_r2_scene_probe.gd/.tscn`（无 class_name，不进正式测试树）
* **台架**：`game/act1/tests/mech001b_r2_ladder.gd/.tscn`、`physics_lab/wip_mechanics001b/bench/`
* 未改其他四幕/星球/归航号/网络；未做破坏性 Git 操作；未提交推送

---

## 4. 下一轮唯一的判别性实验（已想清楚，只需一次运行）

在 act01 **实例化的同一个场景里**，用**台架的原始代码**再建一只独立的锁爪
（自己的支架 + 刚体 + 关节 + 自己的测量），与 `builder` 里那只**同时存在**，分别施加绕各自轴的角冲量：

* 若"运行时新建的那只"能转、`builder` 那只不能 → 差异在 builder 的构造顺序/属性上，
  逐行对照即可（这是可解的问题，我预期是这一步）；
* 若两只都不能转 → 说明 act01 场景上下文有约束级的问题，
  下一步用"把 act01 逐块隐藏（set_deferred('visible'/process_mode) 或移除无关节点）"做二分。

这条实验能一次把问题从"不知道"收敛到"具体某一行"。
