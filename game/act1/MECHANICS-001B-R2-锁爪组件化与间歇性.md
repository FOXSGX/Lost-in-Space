# MECHANICS-001B-R2 追加（第 10 轮）：锁爪组件化 + 发现"间歇性"

> NO-GO；正式脚本仍是 001A（`MECH001A_DONE failures=0` / `RESULT failures=0 completion=true`）。

## 1. 本轮产物：可复用的锁爪组件

`game/act1/machines/power_latch.gd`（`class_name Act1PowerLatch`）
——把前面所有已验证的结论固化成一个**独立组件**：

| 固化项 | 依据 |
|---|---|
| 铰链挂**中性父节点**、`transform` 在 `add_child` 之前设 | 第 2 轮台架（挂刚体下会锁死） |
| **不使用关节限位** | 第 9 轮：重力压在限位上会钳死关节（420 与 4000 冲量都一样） |
| 锁爪 `can_sleep = false` + 指令时唤醒 | 第 7 轮：休眠的刚体马达驱不动 |
| 轴 `Basis(UP, π/2)` → 世界 −Z（水平翻转） | 第 6 轮：轴取向与台架一致才能转 |
| 冲量 420（25 kg × 0.62 m ≈ 152 N·m 重力矩） | 第 7 轮的力矩估算 |
| 绕**真实铰链轴**测角（不用 `rotation.y`） | 第 8 轮：`rotation.y` 会读到万向锁假象 |

接口：`setup(pivot_world)` / `set_closed(bool)` / `angle()` / `is_closed()` / `reset_latch()`。

## 2. 独立验证结果（重要且矛盾）

```
LATCH built axis=(0,0,-1) angle=-0.000
LATCH closed_at=150 angle=-6.282      ← 组件真的转了（整整一圈，因为当时模块掉到地上、没有止挡）
LATCH hold angle=+0.000 is_closed=false
```
把"电源模块"冻结在插座高度（正确模拟）后再跑：
```
LATCH closed_at=-1 angle=+0.000       ← 又不转了
```

**同样的代码、同样的参数，一次转、一次不转。** 这解释了前面 9 轮的反复：
问题不是几何、不是参数，而是**间歇性**——同一套构造在 Jolt 下有时拿到马达力矩、有时拿不到。

## 3. 现在最可疑的机制（下一轮直接验证）

`RigidBody3D` 的 **唤醒状态与约束裁剪**：Jolt 会把"处于休眠/低活动"的岛从求解里裁掉。
即使 `can_sleep = false`、`sleeping = false`（读回来是 false），**约束本身**也可能未被激活。
下一轮的最小验证：

```gdscript
PhysicsServer3D.body_set_state(jaw.get_rid(), PhysicsServer3D.BODY_STATE_SLEEPING, false)
PhysicsServer3D.body_set_state(jaw.get_rid(), PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
```
马达开启期间**每帧**调用一次；若摆动立刻稳定出现，即证明是约束激活问题，
再把它固化进 `power_latch.set_closed()`。

另可用 `jaw.apply_central_impulse(Vector3(0, 0.001, 0))` 这类**极小真实冲量**作为对照，
判断是"唤醒"还是"约束重建"的差别。

## 4. 状态

* 正式第一幕：001A，未改动（本轮只**新增**了组件与测试文件）。
* 新增：`game/act1/machines/power_latch.gd`、`game/act1/tests/mech001b_r2_latch_test.gd/.tscn`。
* 全部台架/探针仍在 `physics_lab/wip_mechanics001b/bench/`。
* 滑槽接驳问题仍未解决（等锁爪闭环后一并处理）。

## 5. 诚实结论

10 轮下来，我把锁爪问题从"完全不知道"收敛到"**间歇性拿不到关节力矩，怀疑是约束激活/唤醒**"，
并交付了一个把全部已确证结论固化下来的独立组件。但**锁爪仍未在正式第一幕里工作**，
所以我不能给 GO。下一轮的验证点非常具体（上面那两行 `PhysicsServer3D` 调用），
如果能稳定复现"每帧强制唤醒 → 必定转动"，剩下的就是几何与止挡的收尾工作。
