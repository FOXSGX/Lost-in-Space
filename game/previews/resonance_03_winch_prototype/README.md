# 共振星 03.1 · 绞盘轨道修复（单人试玩原型）

独立 Godot 4.7 工程。目标不是扩建关卡，而是让一个玩家**不看开发者解释**，
通过第三人称走动、挂缆、收放、观察轨道和对位，完成一次轨道复位。

**状态：单人可完整通关，自动探针 32/32，通过玩家视角录像和 Windows 包启动验证；
真人有感、是否有趣、是否容易学会仍未经用户试玩确认。**

- 操作说明：[`README_试玩说明.txt`](README_试玩说明.txt)（打包时复制进交付目录）
- 已知问题：[`KNOWN-ISSUES.md`](KNOWN-ISSUES.md)
- 帧时间分析：[`PERFORMANCE.md`](PERFORMANCE.md)
- 整合接口：[`docs/integration.md`](docs/integration.md)
- 未来双人预留：[`docs/coop-future.md`](docs/coop-future.md)
- 交接：[`HANDOFF.md`](HANDOFF.md)

## 运行

```powershell
# 在仓库根目录
.\tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --path .\game\previews\resonance_03_winch_prototype
```

Windows 试玩包：`builds/Resonance_03_Winch_v0.1_20261020/`，
双击 `启动_Resonance_03_Winch.cmd`。包内是官方 Godot 4.7.2 运行器 + `Resonance_03_Winch.pck`，
因为本机没有安装标准导出模板，所以体积约 181 MB、窗口标题带 `(DEBUG)`；详见已知问题。

## 操作

| 键 | 行为 |
| --- | --- |
| W / A / S / D | 移动；鼠标转视角 |
| E | 挂缆绳 / 接管或离开绞盘 / 检查或插入锁定销 |
| W / S（接管绞盘后） | 收缆 / 放线 |
| Shift（接管绞盘后） | 慢速微调 |
| 空格 | 鼓式刹车 |
| Q | 松开缆绳 |
| F | 在锁定座安装锁定销（也可用 E） |
| R | 重置任务（保留完成次数） |
| F1 | 操作帮助 |
| F3 | 正常 HUD / 调试 HUD |
| Esc | 暂停并释放鼠标 |

接管绞盘后移动会被锁定，按 E 离开。HUD 底部会提示。

## 玩家看到的信息

**正常模式**只有：当前目标、一行机械状态、张力条、当前可做的操作、短反馈。
不显示角度数字、缆绳米数或端部偏差。

**调试模式（F3）**才显示：任务状态、轨道角、端部偏差、缆绳长度、张力 N/%、模式、刹车、
打滑、卡滞、对位、可锁、稳定、锚点名和 fps。

世界里的可读性来自：

- 轨道前端/中段两个有 3D 标签的吊耳，和一个铰链上的状态灯。
- 接收架上的绿色“复位线”、轨道端部的指针与对齐销。
- 绞盘上的真实张力表针、三色状态灯、顶部旋转警示灯。
- 缆绳的松弛/张紧形态和颜色；打滑时绞盘抖动提示与声音变化。
- 接管绞盘时镜头向右肩偏移，能越过绞盘看到轨道。

## 机制

- 轨道是一段绕倾斜铰链转动的真实结构，初始 15°，卡在碎石里。
- 绞盘只改可用缆绳长度；轨道求解器把长度误差变成张力，再变成绕铰链的扭矩。
- 前端吊耳力臂约 1.42 m，额定 3200 N 时最大扭矩约 4550 N·m，张力打满约 4780 N·m；
  卡滞阈值 4000 N·m，约 88% 额定张力脱开。
- 中段吊耳力臂约 0.88 m，打满约 2970 N·m，拉不开，只会打滑。
- 挂缆自动放线到吊耳距离 +0.45 m；收过头会变负角，放线让轨道荡回。
- 锁定：角度 ≤1.2°，静止，端部垂直误差 ≤0.06 m。

当前数值见 `scripts/winch/misaligned_rail.gd` 与 `winch_machine.gd`。

## 工程结构

| 路径 | 内容 |
| --- | --- |
| `scripts/winch/` | 绞盘机、轨道求解器、吊耳、缆绳、轨道几何、控制台 |
| `scripts/winch_prototype_app.gd` | 场景组装、输入路由、交互选择、HUD、音频、演示入口 |
| `scripts/ui/winch_hud.gd` | 正常/调试 HUD、目标、张力条、提示 |
| `scripts/build/` | 程序化几何、测试舱 |
| `scripts/demo/demo_driver.gd` | 录像/打包验证用的第三人称脚本演示 |
| `scripts/player/` | 第三人称控制器与镜头保护 |
| `tests/probe_rig.gd` | 32 项完整流程回归 |
| `tests/bench_drive.gd` | 调参用快速台架 |
| `tests/perf_probe.gd` | 分阶段帧时间测试 |
| `tests/capture_player.gd` | 玩家镜头质量截图 |
| `tests/capture_winch.gd` | 独立审计镜头截图 |

## 验证

```powershell
# 完整流程（32 项）
.\tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 `
  --path .\game\previews\resonance_03_winch_prototype `
  --script res://tests/probe_rig.gd -- work\gameplay-iterations\20261020-resonance-03-1-playability\probe-final

# 帧时间
... --path ... --script res://tests/perf_probe.gd -- <outdir> final_windowed

# 玩家镜头截图
... --path ... --script res://tests/capture_player.gd -- <outdir>

# 第三人称演示 / 录像（Movie Maker）
... --path ... --write-movie <out.avi> --fixed-fps 30 -- --demo=full
```

最近结果：`probe_rig` **32/32**；演示 `full / wrong_eye / overshoot` 均完成并锁定；
打包 exe 与 `.cmd` 启动后 `--demo=full` 返回 `completed=true`。
证据在 `work/gameplay-iterations/20261020-resonance-03-1-playability/`。

## 集成接口

正式关卡只拿 `WinchRig`，不要直接驱动内部节点：

```gdscript
rig.attach_cable(anchor_id)
rig.detach_cable()
rig.set_winch_input("haul" | "payout" | "creep", pressed)
rig.toggle_brake()
rig.try_install_lock()
rig.reset_mission()
rig.rig_snapshot()
```

详见 [`docs/integration.md`](docs/integration.md)。

## 边界

- 没有接入正式共振星；没有修改 Resonance 02 或正式关卡。
- 单人；双人设计只是未验证的预留文档。
- 视觉仍是独立测试舱，不是完整矿洞美术。
- 真人有感、学习成本、过冲恢复难度都还需要用户试玩。
- 基线快照：`backups/resonance-03-winch-20261020-baseline/`（本轮改动前的工程副本）。
