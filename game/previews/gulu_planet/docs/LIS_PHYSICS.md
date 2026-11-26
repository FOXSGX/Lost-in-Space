# LIS Physics SDK 接入记录（1.0.0-rc1）

> 2026-11-18 · 奶龙星试玩预览

## 来源与校验

- 包：`LIS-PHYSICS-V1.0.0-RC1.zip`（119 文件，addon 约 250 KB）
- 安装：`game/previews/gulu_planet/addons/lis_physics/`
- 完整性：按包内 `SHA256SUMS.txt` 逐文件核对，`checked=120 bad=0`
- 包内状态：功能验收通过；**性能验收未完成**；真人试玩未做
- 包声明：Godot >= 4.7、Jolt Physics、60 Hz；本工程为 4.7.2 + Jolt Physics，满足

## 工程体检

```powershell
& $godot --headless --path <preview> --script res://addons/lis_physics/tools/lis_project_check.gd
```

结果：`LIS_CHECK errors=0 warnings=1 infos=15 verdict=OK-WITH-WARNINGS`

唯一警告：第 3 层未命名（SDK 建议命名为 `interactable`）。
**本工程不要照做**：第 3 层（位值 4）已被环境/墙体查询使用
（`camera_guard.gd`、`station_player.gd` 的 `collision_mask = 4`），
命名会误导。若使用 `LISBody`，必须在 `LISBodyProfile` 里显式写
`collision_layer` / `collision_mask`，不要用 SDK 默认值（默认 4 / 1|2|4）。

## 兼容性验证

- 加入 addon 后原自测不变：`GULU SELFTEST SUMMARY passes=43 failures=0`
- 无 `class_name` 冲突（SDK 全部 `LIS` 前缀，22 个全局类）
- SDK 自带 `minimal_planet` 示例在独立临时工程 headless 跑 240 帧，无脚本错误
- 注意：`tools/run_tests.ps1` 依赖发布包里不存在的 `lab/` 目录，不能直接在包内跑全套测试；
  `tools/verify_package.ps1` 用了 PowerShell 7 语法，本机 Windows PowerShell 5.1 解析失败
  → 完整性用 `Get-FileHash` 对照 `SHA256SUMS.txt` 自行核对

## 它是什么 / 不是什么

**是**：跑在 Jolt 之上的第一人称物理**交互层**——真实抓握/搬运/抛掷、
质量与力上限、车轮/门/杠杆/缆绳/绞盘等机械、多人权威适配。

**不是**：物理引擎替代品（底层仍是 Jolt）；也不是第三人称方案。
`LISBody` 只生成 `BoxShape3D` 碰撞体，球形物体需要自带 `CollisionShape3D` 并绕过
`apply_profile()` 重建，不干净。

## 对当前玩法的判断

当前闭环是「踢球 → 奶龙扑救 → 入仓」，球已经是 Jolt 下的真 `RigidBody3D`：
冲量踢球、物理反弹/旋转/休眠、CCD，43 项自测覆盖。**不建议**把 `EnergyBall`
换成 `LISBody`：拿不到额外物理收益，却要承担 profile 重建、层掩码、包裹球形的
额外复杂度与回归风险。

SDK 真正能补的是现在没有的能力：

| 候选 | 用到的模块 | 适合的场景 |
| --- | --- | --- |
| 可搬燃料罐（有重量、举不动就只能拖） | `LISBody` + `LISGrabber` + `LISFirstPersonAdapter` | 恢复「抱货」玩法，或装货口搬运环节 |
| 装货口卷扬/吊臂 | `LISWinchDrum` + `LISCable` + `LISPulley` | 码头机械化、把燃料吊进舱 |
| 舱门/闸门 | `LISHingeDoor` / `LISMotorDoor` / `LISLimitSwitch` | 装货口开合、连锁反馈 |
| 推车 | `LISCart` | 多罐搬运路线 |
| 多人协作 | `LISPhysicsHost` | 以后做联机时 |

已知限制（摘自包内 `PHYSICS_LIMITATIONS.md`）：

- 抓握姿态辅助是游戏化能力（单手 500 N·m ≈ 人体 3.3 倍），不是人体力学
- 绞盘缆绳是近似模型（无质量、无缠绕接触）
- 高延迟 / 丢包 / 断线重连未验证
- 高张力下销毁整条绳有约 8–20% 退出崩溃概率（`0xC0000005`），需先松手或长期保留

## 当前状态

- 分支：`feature/lis-physics-rc1`（本地，未 push）
- addon 已随工程入库，未启用编辑器插件（插件本身也不改任何设置）
- 尚未在正式场景中使用任何 `LIS*` 节点；等玩法方向确认后再接
