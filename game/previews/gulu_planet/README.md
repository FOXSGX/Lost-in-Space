# 奶龙星 · 第一人称试玩预览

《迷失太空 / Lost in Space》第四颗新星球“奶龙星”的独立试玩预览。

本轮只验证最小互动：

**走近奶龙 → 按 Q 挑衅 → 它注意并靠近 → 连续挑衅后蓄势 → 扑来 → 侧移躲开 → 短暂恢复。**

本轮没有真实燃料抢夺、伤害、道具、麦克风、联网或正式模型。

## 启动

用 Godot **4.7.2** 打开本目录 `project.godot`，或：

```powershell
& "<Godot 4.7.2>" --path "<仓库>/game/previews/gulu_planet"
```

入口：`gulu_planet.tscn`。进入默认第一人称，鼠标捕获。

### 操作

| 按键 | 作用 |
| --- | --- |
| WASD | 移动 |
| Shift | 加速 |
| 鼠标 | 环视 |
| **Q** | **挑衅奶龙**（9 m 内、面向它、不能隔墙） |
| Tab | 切换第一/第三人称（第三人称仅检查） |
| R | 重置玩家、奶龙与上头值 |
| Esc / 左键 | 释放 / 重新捕获鼠标 |
| F3 | 调试面板 |
| F4 | 显示/隐藏 Blender GLB 测试方块（默认隐藏） |
| F1 | 隐藏/显示左上说明 |

## 行为与反馈

- **待机**：奶油色占位奶龙，地面状态环微亮。
- **注意**（0.55 s）：转向玩家，环变青，HUD 显示“它注意到你了”。
- **靠近**（2.6 m/s，停 2.4 m）：持续盯住玩家；HUD 提示再挑衅会激怒它。
- **上头**：每次 Q +0.34，停手 1.2 s 后缓慢下降；HUD 有橙色上头条。
- **蓄势**（1.0 s）：压低身体、抖动、红色状态环、HUD 红色预警——“要扑了，侧移躲开”。
- **扑击**（0.42 s，11 m/s）：只扑向蓄势结束时锁定的位置，不追尾。
- **命中/扑空**：1.25 m 判定；本轮没有伤害或抢夺，只显示“扑空/被扑到”。
- **恢复**（1.5 s）：不理会挑衅；结束回待机，上头清零，给玩家搬运窗口。
- 失去视线、超过 13 m 或 9 s 没挑衅 → 回窝。

所有数值集中在 `scripts/milk_dragon.gd` 顶部，**全部是原型值**。

## 第一人称复用

GitHub `main` 提交 `42519ff403241bf5ac968edb9ae326c6fdbc74fe`：

- `game/previews/resonance_coop_playtest_01_1/scripts/station_player.gd`
- 与 `resonance_02_quality_rework/scripts/station_player.gd` 逐字相同
  （SHA256 `16ADB4AF...E399E`）。

`station_player.gd` **未修改**；入口脚本只设置 `use_first_person=true` 和提供灰盒场地/
`clamp_cave_camera_position`/`actors` 兼容。保留 5.8 m/s、Shift 1.65、眼高 1.65 m、
FOV 62°、鼠标 0.0024、俯仰 −0.58…0.30、Tab 切换。

## 场景

- 32×26 m 灰盒：地板、舱壁、箱子、低台、碰撞墙、视线测试柱。
- 奶龙 `(2, 0, -3.5)`；燃料占位 `(5, 0, 3)`；玩家出生 `(-8, 0.02, 0)`。
- 奶龙外观是 `milk_dragon_visual.gd` 程序化占位；行为在 `milk_dragon.gd`，两者分离。
- 无漂浮 3D 文字；HUD 只放必要状态。

## 验证

```powershell
& $godot --headless --path $preview -- --selftest
# GULU SELFTEST SUMMARY passes=38 failures=0
```

已通过：默认第一人称、眼高/FOV、移动、内墙碰撞、Tab 双向、待机→注意→靠近、
第 3 次挑衅蓄势、1.0 s 预兆、侧移躲开、恢复→待机、隔墙拒绝、连按冷却、R 重置、F3 调试。

未验证：真人手感与趣味、鼠标观察（本轮 headless 跳过；基础版曾窗口通过）、
伤害/抢夺/结算、麦克风、联网、正式动画。

## Blender 管线

已安装官方 **Blender 4.5.15 LTS**：

`C:\Users\31798\AppData\Local\Programs\Blender Foundation\Blender 4.5\blender.exe`

- 用自带 Python 3.11 创建独立测试资产（0.8 m 主体 + 前/上/后标记 + 4 个材质），
  导出 GLB 与可编辑 `.blend`。
- 坐标：Blender 源文件 **Z-up、脚底 z=0**；导出后在 Godot 验证 **Y-up、脚底 y=0、角色/前向 −Z**。
  不要把 Godot 的轴向要求直接写进 Blender 源文件。
- Godot 已导入 `assets/test/blender_link_test.glb`，作为独立对象放在 (-4, 0, 2.5)，默认隐藏，按 F4 显示。
  headless 检查：4 个 mesh、0.8 m、Blender +Y→Godot −Z、+Z→+Y、材质正确。
- 未安装 MCP 或第三方插件。详细命令、源文件和检查结果见 `BLENDER.md`。
- 本轮未用 Blender 制作/替换奶龙，只打通管线。

## 素材

查找记录见 `ASSETS.md`：找到可下载 GLB 候选，但实际下载接口返回 401，
骨骼/可编辑性与动画质量未验证；本轮**未导入**第三方模型，继续使用程序化占位。
`BLENDER.md` 记录了下一轮推荐方案。

## 范围

**做**：奶龙占位、Q 挑衅、注意/靠近/蓄势/扑击/恢复/回窝、HUD、重置、文档。

**不做**：真实燃料搬运/叼走/追回、伤害、道具、结算、声音/麦克风、联网、正式建模、
正式航线接入、其他星球修改。

## 文档

- `BRIEF.md`：目标、约束、参数、来源
- `STATUS.md`：完成情况、验证、下一步
- `DECISIONS.md`：选择与待讨论
- `TESTING.md`：启动、测试步骤、结果
- `ASSETS.md`：奶龙素材查找、许可与下载复核
- `BLENDER.md`：Blender 安装、GLB 管线验证与推荐方案
