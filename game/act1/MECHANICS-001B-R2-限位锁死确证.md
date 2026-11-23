# MECHANICS-001B-R2 追加（第 9 轮）：限位锁死已被证实，集成仍有 1 处未解

> NO-GO；已回退，`MECH001A_DONE failures=0` / `RESULT failures=0 completion=true`。

## 1. 本轮确证的根因（带重力的限位台架）

同一构造、同样参数，只切换 `FLAG_USE_LIMIT`：

```
A 限位关 / 起始 0°      angle = +6.283 rad    ← 马达完全正常，转了一整圈
B 限位开 / 起始 0°      angle = +0.002 rad    ← 现状：锁死
C 限位开 / 起始 +20°    angle = +0.013 rad    ← 仍锁死（重力先把它压到下限）
D 限位关 / 起始 +20°    angle = +6.283 rad    ← 又正常
```

**结论：在本工程（Godot 4.7.2 + Jolt）里，`HingeJoint3D` 打开角度限位后，
只要重力把刚体压在限位上，限位约束就会把关节钳死在边界，马达（即使冲量 4000）也拉不动。**
这也解释了此前所有"台架（无重力）能转、关卡（有重力）不转"的矛盾——
之前的台架全部是 `gravity_scale = 0`，从来没有触发过这条路径。

## 2. 按此根因做的整改（已实现但未通过验证）

1. 关闭关节限位（`FLAG_USE_LIMIT = false`）；
2. 闭合方向改为重力方向（`-1.25`），让锁爪"落"下去；
3. 铰链支点抬到模块顶上方（`SOCKET.y + 1.30` ≈ 2.64），让锁爪摆下来**压在模块上**——
   模块本身就是实体止挡，重力负责保持闭合（真正的重力自锁）；
4. `CLAMP_CLOSED_ANGLE` 改为 0.30 rad（对应压在模块顶的角度）。

## 3. 仍未解决的一处（诚实记录）

上述整改后，**正式场景里马达仍然 0.000 rad**（`stalled=true`，0.6 s 内无位移），
即使把锁爪 `collision_mask` 置 0 也一样：
```
PROBE jaw sleeping=false bracket_y=2.64
  t=  0 angle=-0.000 w=+0.000 stalled=false
  t= 40 angle=-0.000 w=+0.000 stalled=true
  ...
```
而**完全相同的构造在台架里（案例 A/D）能转到 6.283 rad**。
所以还剩一处"台架 vs 场景"的差异没有找到：场景里这只关节拿不到马达力矩，
且与限位、碰撞掩码、休眠、质量、重力都无关（都已单独排除过）。

## 4. 下一轮唯一推荐的做法（换路径，不再在场景里拼装）

**把锁爪做成独立的 `PackedScene`（自带支架/锁爪/关节/止挡），先在独立场景里验证能闭合，
再把这个已证明可用的子场景 `instantiate()` 进 act1。**
理由：目前所有失败都出现在"在 act1 的构建代码里现场拼关节"这条路径上，
而台架里的同款拼装始终可用。把机械做成独立场景能一次性消掉这层差异，
也便于以后复用（其它幕的锁爪/闸门可以直接用）。

具体：
1. 新建 `game/act1/machines/power_latch.tscn`（Node3D 根 + 支架 + 锁爪 + 关节 + 止挡），
   脚本暴露 `set_closed(bool)`、`angle()`、`is_closed()`；
2. 独立测试场景验证：无重力/有重力、限位关、马达 1.25/冲量 420，能在 1 s 内闭合到止挡；
3. 通过后 act1 只做 `add_child(preload(...).instantiate())` 并接信号，
   不再在 builder 里拼关节。

## 5. 状态与遗留

* 正式关卡：001A，可玩（`MECH001A_DONE failures=0`、`RESULT failures=0 completion=true`）。
* 本轮新增台架：`mech001b_r2_limit`（限位对照，含决定性数据）已归档到
  `physics_lab/wip_mechanics001b/bench/`；
* `game/act1/tests/` 残留两个 `.uid`（`mech001b_r2_ladder.gd.uid`、
  `mech001b_r2_scene_probe.gd.uid`），对应的 `.gd/.tscn` 已移出，可安全删除；
* 滑槽接驳问题（模块在关卡里不走坡面）仍未解决，等锁爪路径打通后按同样方式处理。
