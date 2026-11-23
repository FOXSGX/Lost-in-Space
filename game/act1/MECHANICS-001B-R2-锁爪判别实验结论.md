# MECHANICS-001B-R2 追加（第 3 轮）：锁爪判别实验结论

> 结论不变：**NO-GO**；已回退，001A 基线 `failures=0` / `completion=true`。

---

## 1. 本轮做的判别实验（关键）

在**同一个 act01 实例**里，用台架原始代码**另建一只独立锁爪**（自己的支架 + 22 kg 刚体 +
`HingeJoint3D`，挂在探针根节点下、`transform` 前置），与 `builder` 里那只**同时存在**，
分别绕各自真实轴施加角冲量：

```
PROBE impulse30(绕真实轴):   angle 0.000 → 0.000   w_axis=+0.000        ← builder 那只：锁死
PROBE impulse_mask0:         angle 0.000 → 0.000   w_axis=+0.000        ← 屏蔽碰撞后：仍锁死
PROBE impulse_benchparams:   angle 0.001 → 0.000   w_axis=+0.000        ← 对齐台架质量/重力/阻尼后：仍锁死
PROBE RUNTIME_LATCH axis=(0,0,-1) w_axis=+0.000 rot_changed=true        ← 同场景新建那只：转了
```

**这就是本轮的分水岭**：
* 关节配方**没有问题**（同场景、同代码、同参数，运行时新建的能转）；
* 问题**只出在 `builder` 构造的那一只**身上；
* 且已排除：质量/重力/角阻尼、碰撞掩码、与支架重叠、轴取向、局部基换算、堵转逻辑。

---

## 2. 现在锁定的唯一候选根因

`builder` 与运行时版本的**最后两处差别**只剩：

1. **父节点不同**：builder 的铰链挂在 `stage`（act01 根，可能带非单位变换）；
   运行时那只挂在探针根（单位变换）。
   （但已核对：`jaw` 与 `hinge` 的世界位置一致 `(5.27,1.52,-4.85)`，轴也一致 `(0,0,-1)`。）
2. **构造之后有人动过这只刚体**：`Act1App` 在 build 完成后会调用 `reset_all()` /
   `reset_scene()`（以及 `_restore_body` 一类函数），如果这些流程**在关节已绑定之后
   重设了 `ClampJaw` 的 transform**，Jolt 会把关节拉出一个巨大误差并锁死该自由度。
   —— 这一条最可疑：运行时的锁爪是**在所有复位动作之后**才创建的，所以没被碰过。

**下一轮的第一步（很便宜）**：在 build 结束、复位结束各打一次 `jaw.global_position`，
若复位后有跳变即可确认；确认后让复位流程**跳过 ClampJaw**（或复位后重建关节），
锁爪应当立刻像台架一样转起来。

---

## 3. 归档与当前状态

```
physics_lab/backup_mechanics001b/    001A 末态（已使用）
physics_lab/wip_mechanics001b/       001B/R2 WIP（含台架验证过的锁爪构造、绕真实轴测角、启动宽限、滑槽 _ramp_basis）
physics_lab/wip_mechanics001b/bench/ 全部台架与探针（chute / clamp / ladder / scene_probe）+ .gdignore
```
* 台架与探针已全部移出 `game/act1/tests/`，正式测试树干净、无重复 `class_name`。
* 正式关卡验证：`MECH001A_DONE failures=0`、`RESULT failures=0 completion=true`。
* 未改其他四幕/星球/归航号/网络；未做破坏性 Git；未提交推送。

**仍待办**：滑槽接驳（模块仍在正式场景里不走坡面，与 R1 数值相同）——
等锁爪跑通后按同样方式做"台架 vs 场景"的接触日志对照。
