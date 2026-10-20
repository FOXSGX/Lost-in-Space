# 模块接口与未来整合说明

本文件说明 Resonance 03.1 的绞盘模块如何被正式共振星关卡复用。
**本轮没有接入正式关卡；这是一份接口清单，不是已完成的整合。**

## 设计边界

- 预览工程：`game/previews/resonance_03_winch_prototype/`
- 正式关卡：`game/scenes/resonance_stage.tscn` / `game/scripts/resonance_stage.gd`（本轮未修改）
- 预览里的测试舱、程序化墙、晶体、灯光都**不要**复制进正式关卡；正式关卡应使用自己的美术。
- 只复用 `scripts/winch/` 下的机械模块和 `WinchRig` 的任务编排。

## 场景需要提供的节点

`WinchRig` 不依赖硬编码路径；它可以从导出的 `NodePath` 或分组找到部件：

| 节点 | 分组 | 必需 | 作用 |
| --- | --- | --- | --- |
| `WinchStation/Machine` | `winch_machine` | 是 | 卷线轮、刹车、离合器、缆绳长度 |
| `RailAssembly/RailBody` | `misaligned_rail` | 是 | 单自由度轨道，`AnimatableBody3D` |
| `Cable` | — | 否 | 缆绳视觉；没有则不画 |
| `WinchStation/Sheave` | — | 否 | 缆绳起点；没有则用绞盘上方 |
| `Player` | `player` | 是 | 距离判定、HUD |
| `LockStation` | — | 由应用层持有 | 锁定交互点（不是 `WinchRig` 的必需节点） |

轨道上的吊耳用 `scripts/winch/winch_anchor.gd`，加入 `winch_anchor` 分组。
`anchor_id` 由关卡自己命名；演示里是 `eye_far` / `eye_mid`，正式关卡可以换。

## 对外接口

```gdscript
# 任务
rig.attach_cable("eye_far") -> {ok: bool, reason: String, anchor: String}
rig.detach_cable()
rig.set_winch_input("haul" | "payout" | "creep", pressed: bool)
rig.toggle_brake()
rig.try_install_lock() -> {ok: bool, reason: String}
rig.reset_mission()

# 只读
rig.tension_state() -> {
    mode, free_length, drum_angle, drum_speed, tension, tension_ratio,
    brake, overload, stalled, attached, anchor_name, creep
}
rig.alignment_state() -> {
    angle_deg, lateral_error, vertical_error, end_error, settled, in_band,
    lockable, locked, angular_speed, jammed, moment_arm, lock_pin,
    tension, stretch, hinge_angle, angular_velocity, taut, torque
}
rig.lock_state() -> {locked, lock_pin, state, completions}
rig.rig_snapshot() -> {state, completed, completions, winch, rail, lock, stability}
```

信号：`mission_completed`、`feedback(text, tone)`、`state_changed`。

正式关卡不要直接改 `rail.hinge_angle`、`winch.free_length` 或 `stalled`；
所有输入都走上面的接口，才能保证“收缆长度 → 张力 → 扭矩 → 角度”的求解顺序不被破坏。

## 输入层要求

- W/S 是**持续输入**，不是边沿触发。预览工程在 `_physics_process` 里轮询
  `Input.is_action_pressed`，并只在“接管控制台”时传给 `WinchRig`。
- E 是上下文交互；需要按“最近的有效目标”选择，而不是固定优先级。
  预览里未挂缆时吊耳优先，挂缆后按最近目标（锁定座/控制台）。
- 空格刹车、Q 松缆、F 装销、R 重置是离散动作，可以走 `_unhandled_input`。

## 整合检查清单

- [ ] 正式关卡的轨道段有真实碰撞，玩家能站在接收架附近而不是穿模。
- [ ] 两个吊耳的 `attach_point()` 与视觉吊环一致；远端/中段的力臂差来自几何，不是写死的倍率。
- [ ] 滑轮位置与缆绳视觉一致；挂缆时 `feed_to()` 能覆盖实际距离（`MAX_LENGTH` 足够）。
- [ ] 轨道铰链轴、限位、卡滞阈值与正式关卡的尺寸匹配，重新跑一遍探针。
- [ ] 锁定座与吊耳的交互距离不会互相抢键。
- [ ] 正常 HUD 不显示角度数字；调试 HUD 用 F3。
- [ ] 关卡失败/重试时调用 `reset_mission()`，不要把 `completion_count` 清零。
- [ ] 网络层（如果以后做）只同步 `rig_snapshot` 需要的最小字段，不逐帧同步每个节点。

## 当前调参

见 `README.md` 的数值表。正式关卡如果放大轨道，必须重新计算力矩和卡滞阈值；
不要直接把 `jam_torque` 照搬。

## 不要做的事

- 不要把预览的 `WinchScene`、程序化墙、测试用锁定座复制到正式关卡。
- 不要修改 Resonance 02 的场景或源码。
- 不要在未验收前把 `WinchRig` 接进 `resonance_stage.gd`。
