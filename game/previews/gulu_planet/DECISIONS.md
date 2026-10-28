# DECISIONS — 咕噜星第一人称试玩预览

日期：2026-10-28。区分“用户已确认”与“本轮实现选择”。

## D-01 新建独立预览，而不是寻找旧咕噜星框架

- 依据：GitHub 当前 `main`（`42519ff`）的路径、分支、PR、Issue、handoff 中都没有咕噜星内容；
  `PlanetRegistry` 只有飞船、霜烬星、共振星、腐墟星。
- 用户已更正并授权：咕噜星是第四个新星球，允许在 `game/previews/` 新建独立预览。
- 选择：`game/previews/gulu_planet/`，不接入正式航线、不改其他星球。

## D-02 逐字复用共振星独立预览的站台玩家控制器

- 来源：`game/previews/resonance_coop_playtest_01_1/scripts/station_player.gd`
  @ `42519ff`。
- 对照：`game/previews/resonance_02_quality_rework/scripts/station_player.gd` 与它**逐字相同**，
  SHA256 均为 `16ADB4AFB5CAE2AB151C870828D9FCA27EBF28BA1ADD30F12072510A67BE399E`。
- 选择：复制 `station_player.gd` 到 `gulu_planet/scripts/`，不修改内容；
  同时复制它依赖的 `camera_guard.gd`、`interaction_pose.gd`、`protagonist_visual.gd`、
  `protagonist_visual.tscn`、`contact_shadow.gdshader`、角色 JSON/皮肤。
- 原因：用户要求保持同一套移动、鼠标观察、镜头高度、FOV 和操作手感，不要另写控制器。
- 结果：没有新增第二套第一人称控制器。

## D-03 默认第一人称由入口脚本覆盖，不修改控制器

- 原预览的 `use_first_person` 默认 `false`；Tab 切换。
- 选择：在 `gulu_app.gd` 生成玩家后设置 `use_first_person=true`，隐藏本机 `visual`，
  调用 `update_camera(1.0,true)`；Tab 仍保留，可切到第三人称查看角色。
- 原因：满足“进入试玩默认第一人称”，同时保留原预览的检查视角功能。
- 注意：控制器文件保持原样，方便后续与上游 diff。

## D-04 输入映射在入口脚本注册，键位与共振星预览一致

- 来源：`station_base.gd` 中的 `InputMap` 设置。
- 映射：A/D/W/S、Shift、Esc、Tab、鼠标左键；另外注册 `brace`（H）避免控制器查询不存在的 action。
- 原因：原预览在运行时建 action；咕噜星预览保持同样方式，不依赖正式工程的输入配置。
- 未加入跳跃：`station_player.gd` 本身没有跳跃逻辑，按“不要另写一套”保持现状。

## D-05 用自己的灰盒场地，不复制 67 MB 空间站

- 原预览含 `station_static.glb`（约 67 MB）和整套空间站任务脚本；咕噜星本轮只需要可行走场地。
- 选择：程序化 32×26 m 灰盒（地板/舱壁/箱子/低台/碰撞墙），加占位咕噜与燃料。
- 影响：第一人称手感来自同一控制器和同一物理层；场景美术不代表最终咕噜星。
- 未复制：共振星的设备/任务/网络脚本，避免把无关系统带进预览。

## D-06 占位对象静态；行为留到下一阶段

- 咕噜：`placeholder_gulu.gd` + 程序化身体/眼睛/耳朵/手臂/脚，StaticBody3D，仅作视觉与碰撞。
- 燃料：`fuel_prop.gd` + 橙色燃料罐/光环/暖光，StaticBody3D，无拾取/叼走/吞噬。
- 原因：用户本轮明确“暂不添加行为”，不要提前补成最终规则。

## D-07 分支基线与网络限制

- 本地 `origin/main` 停在 `3969511`（2026-10-08，旧 2D）；GitHub 当前 main 是 `42519ff`（3D）。
- `git fetch` 多次 `Recv failure: Connection was reset`；改用 GitHub API / raw 读取当前文件。
- 选择：基于本地 `origin/main` 建 `feature/gulu-planet-preview`；新预览是自包含工程，
  文件来自当前 main 的 raw。未拉取当前 main 的完整历史。
- 影响：分支暂时落后当前 main；网络恢复后应 rebase/cherry-pick，新增文件不依赖旧 2D 代码。
- 未推送、未合并。

## D-08 兼容性 shim 放在入口脚本，不改控制器

- `station_player.gd` 的第三人称路径会调用父节点的 `clamp_cave_camera_position()`，
  并通过父节点 `actors` 字典抑制近处角色。
- 选择：在 `gulu_app.gd` 提供简单边界 clamp 和 `actors` 字典；不修改控制器。
- 影响：第三人称只用于检查，镜头被限制在灰盒场地内；第一人称路径不经过这些 shim。

## 待用户决定

1. 第一人称手感是否接受（需真人试玩）。
2. 下一阶段感知范围、视角、遮挡与停靠距离的具体值。
3. 声音引导是否/何时接入；本轮未做。
4. 是否将咕噜星接入正式星球选择/航线（本轮明确不做）。
