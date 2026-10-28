# BRIEF — 咕噜星第一人称试玩预览

状态：本轮为基础接入预览；不是正式星球关卡，不接入航线。
分支：`feature/gulu-planet-preview`
目录：`game/previews/gulu_planet/`
引擎：Godot 4.7.2

## 1. 本轮目标

在现有 GitHub 项目内新增咕噜星独立预览，复用共振星独立预览的第一人称控制器与镜头：

1. 新建 `game/previews/gulu_planet/` 试玩工程。
2. 默认进入第一人称；移动、鼠标观察、镜头高度、视野和操作手感沿用共振星预览。
3. 搭建可行走的灰盒测试场地，放置一只占位咕噜和一块占位燃料。
4. 实际验证移动、观察、第一/第三人称切换、场景碰撞和重置。
5. 记录来源、差异、测试结果和下一步。

## 2. 已确认约束

- 咕噜星是与现有三个星球并列的**第四个新星球**；当前项目中没有旧咕噜星内容。
- 允许在 `game/previews/` 下新建独立试玩预览，**不允许**另起一个游戏项目。
- 预览阶段不改正式星球选择、航线、主线流程。
- 本轮不做麦克风、声音吸引、发现/追逐、叼走燃料、联网扩展、正式建模。
- 不修改其他星球，不推送、不合并。
- 指引不放漂浮 3D 文字；调试信息只放可关闭的 HUD 面板。
- 模型最终由团队制作；当前是占位模型，外观与行为分离。

## 3. 复用来源（GitHub 当前代码）

GitHub `main` 提交：`42519ff403241bf5ac968edb9ae326c6fdbc74fe`（2026-10-26）。

- `game/previews/resonance_coop_playtest_01_1/scripts/station_player.gd`
- 与 `game/previews/resonance_02_quality_rework/scripts/station_player.gd` **逐字相同**：
  SHA256 `16ADB4AFB5CAE2AB151C870828D9FCA27EBF28BA1ADD30F12072510A67BE399E`
- 同目录复制：`camera_guard.gd`、`interaction_pose.gd`、`protagonist_visual.gd`、
  `scenes/protagonist_visual.tscn`、`contact_shadow.gdshader`、
  `assets/characters/protagonist_model.json`、`assets/characters/skins/skin_ranger.glb`
- 未复制共振星 67 MB 的 `station_static.glb`；本轮用程序化灰盒场地，
  避免把整座空间站搬进咕噜星预览。

## 4. 沿用/覆盖的视角参数

来自 `station_player.gd` 与 `station_base.gd`：

- 移动速度 5.8 m/s；Shift 跑动倍率 1.65。
- 第一人称相机高度 **1.65 m**；FOV **62°**；near 0.04 / far 100。
- 鼠标灵敏度 0.0024；俯仰限制 **−0.58 … +0.30 rad**。
- 切换键 **Tab**（`inspect_first_person`）；Esc 释放鼠标；左键收回鼠标。
- 默认第三人称是原预览的行为；咕噜星在生成玩家后把 `use_first_person` 置为 `true`，
  并在进入试玩时隐藏本机角色外观。未改写控制器文件。

## 5. 场景内容

- 32×26 m 灰盒场地：地板、四周舱壁、横梁、箱子、低台、一道碰撞验证墙。
- 玩家出生点 `(-8, 0.02, 0)`，默认朝 +X；两只占位对象都在首屏内。
- 占位咕噜：绿色圆润身体、眼睛、耳朵、手臂、脚；**静态，无行为**。
- 占位燃料：橙色燃料罐 + 地面光环 + 暖光；**静态，无拾取/叼走/吞噬**。
- 不新增漂浮文字；HUD 只显示模式、操作提示和可关闭的 F3 调试。

## 6. 待讨论/下一阶段

- 咕噜发现燃料的感知距离、视野角度、遮挡判定。
- “注意到 → 转向 → 靠近 → 停靠”的状态机与动画表现。
- 声音引导是否接入、何时接入；本轮不实现。
- 燃料地块的正式规则（叼走、取回、任务结算）尚未确定。
- 正式模型、动画与音效由团队后续制作。
