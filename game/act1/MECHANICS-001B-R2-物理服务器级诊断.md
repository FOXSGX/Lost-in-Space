# MECHANICS-001B-R2 追加（第 11 轮）：物理服务器级诊断，锁死点已缩小到"act1 场景上下文"

> NO-GO；已回退，`MECH001A_DONE failures=0` / `RESULT failures=0 completion=true`。

## 1. 本轮用引擎侧真实状态逐项核对（不再靠脚本读数）

通过在本工程内运行 `run_gdscript` 直接读 Jolt 侧状态：

```
mode = 2 (BODY_MODE_RIGID)          ✓ 是动力学刚体
sleeping = false, can_sleep = false ✓ 未休眠且不可休眠
freeze = false                      ✓ 未冻结
mass = 25.0                         ✓
inertia = (0,0,0)                   → auto 自动计算（不是"没有惯量"）
center_of_mass = (0,0,0)            → 质心在刚体原点（臂是**平衡**的）
lock_rotation = false               ✓
axis_lock_angular_x/y/z = false     ✓
场景中关节总数 = 1                  → ClampHinge(limit OFF, motor ON)，绑定 ClampBracket/ClampJaw
```

**关键修正**：`center_of_mass = (0,0,0)` 说明锁爪绕铰链是**力矩平衡**的，
重力从来不会让它摆动——所以第 7 轮"重力负载"的结论**不成立**，这里更正。
真正要解释的只有一件事：**马达和角冲量都推不动它。**

## 2. 决定性测量：关节在 act1 里把刚体完全锁死

```
马达关闭 + 绕真实轴 40 N·m·s 角冲量  → ω = -6.8e-20   （应为 ≈3 rad/s）
显式设 inertia=(1.77,13.0,11.4) + center_of_mass=(-0.62,0,0) 后再冲量 → ω = -1.5e-19
马达开(1.25 / 冲量 400) 1 秒        → ω = +2.1e-19，angle ≈ -0.00001
```

即：**在这个位置、这个场景里，`HingeJoint3D` 把刚体的转动自由度完全钳死**，
与限位、马达、碰撞掩码、休眠、惯量、质心、轴锁、`lock_rotation` **全部无关**（逐项实测排除）。

对照（本工程内、同一套构造）：

| 场景 | 结果 |
|---|---|
| 独立台架（重力 0 / 重力 1 且限位关） | 6.283 rad，正常转动 |
| 独立 `power_latch.tscn`（模块冻结当止挡） | 不转 |
| 独立 `power_latch.tscn`（模块未支撑、落到地面） | 转 6.283 rad |
| act1 场景内 | 转动 0（1e-19） |

## 3. 现在能下的最强结论

`HingeJoint3D` 在本工程里**行为依赖于它所在的场景上下文**，而不是我们传进去的任何参数。
同一份构造在"空场景"里可用、在 "act1" 里被钳死。已排除的项：
限位、马达标志/目标速度/冲量、碰撞掩码与例外、休眠与 can_sleep、惯量、质心、
`lock_rotation`、`axis_lock_angular_*`、缩放、父节点层级、轴向、绑定时机、重绑定。

剩下未被排除、也最值得下一轮查的两条：
1. **act01 场景里是否存在影响整棵子树的物理设置**（例如某个祖先节点的
   `physics_interpolation`、`process_mode`、或 act1 根节点在 `_ready` 之后被整体移动过）；
2. **两个 body 是否真的落在同一个 World3D / physics space 里**（用
   `PhysicsServer3D.body_get_space(rid)` 对比 bracket 与 jaw 的 space RID，这一条一测即知）。

第 2 条我在下一轮会**第一件事**就测（一行即可），因为如果两个 body 不在同一 space，
关节约束就会退化成"把刚体焊死"，与观测完全吻合。

## 4. 状态

* 正式第一幕：001A，未改动，可玩。
* 组件：`game/act1/machines/power_latch.gd`（独立锁爪，含全部已确证结论）；
  测试场景已归档到 `physics_lab/wip_mechanics001b/bench/`。
* 全部台架/探针留在 `physics_lab/wip_mechanics001b/bench/`。
* 滑槽接驳问题仍未解决。

## 5. 结论

**NO-GO。** 11 轮里我确实没能交付可用的旋转锁爪，这一点不掩饰。
但本轮拿到的是**第一条引擎侧硬证据**：不是参数问题，而是关节在 act1 上下文里被整体钳死，
并且已把可疑面收窄到"同一 physics space / 祖先节点设置"两条可一行验证的检查。
