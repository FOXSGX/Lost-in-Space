# DECISIONS — 奶龙星第一人称试玩预览

日期：2026-10-28。区分用户已确认、本轮实现选择和待讨论事项。

## D-01 名称与目录

- 用户确认：原“咕噜星”暂改称 **奶龙星**，是第四颗新星球；生物采用奶龙形象。
- 选择：预览内显示“奶龙星”；目录 `game/previews/gulu_planet/` 与分支
  `feature/gulu-planet-preview` 沿用上一轮，避免重复创建。内部脚本名 `gulu_app.gd`
  也沿用，文档记录这是历史命名。
- 不修改正式星球注册、航线或其他星球。

## D-02 第一人称控制器逐字复用共振星预览

- 来源：`game/previews/resonance_coop_playtest_01_1/scripts/station_player.gd`
  @ GitHub `42519ff`。
- 对照：`resonance_02_quality_rework/scripts/station_player.gd` 与其逐字相同，
  SHA256 `16ADB4AFB5CAE2AB151C870828D9FCA27EBF28BA1ADD30F12072510A67BE399E`。
- 选择：复制到 `gulu_planet/scripts/`，**未修改**；同时复制 `camera_guard.gd`、
  `interaction_pose.gd`、`protagonist_visual.gd`、`protagonist_visual.tscn`、
  `contact_shadow.gdshader`、角色 JSON/皮肤。
- 默认第一人称由入口脚本设置 `use_first_person=true`；Tab 仍保留。
- 参数保持：5.8 m/s、Shift 1.65、眼高 1.65 m、FOV 62°、鼠标 0.0024、俯仰 −0.58…0.30。

## D-03 挑衅按键选择 Q

- 候选键排除了 WASD、Shift、Tab、R、F3、F1、Esc、鼠标左右键、H。
- 选择 **Q**：不与现有视角/移动/重置冲突，单手可反复按。
- 只有 `InputEventKey` 按下且非 echo 才触发；控制器侧再加 0.7 s 冷却，
  避免按住每帧重复或瞬间连按叠加。
- 玩家必须在 9 m 内、相机前方 ±55°、且与奶龙之间没有墙体遮挡。

## D-04 最小状态机

- 状态：待机 → 注意 → 靠近 → 蓄势 → 扑击 → 恢复 → 待机；失去兴趣/遮挡走回窝。
- 注意 0.55 s：转向玩家、状态环变青。
- 靠近 2.6 m/s，停靠 2.4 m；超过 9 s / 13 m / 失去视线就回窝。
- 上头：每次 +0.34，停手 1.2 s 后按 0.10/s 衰减；到 0.95（通常第 3 次）进入蓄势。
- 蓄势 1.0 s：压低身体、抖动、红色状态环、HUD 预警；结束后锁定玩家当前位置。
- 扑击 0.42 s、11 m/s；只沿锁定点直线移动，不转向追踪；玩家侧移可躲开。
- 恢复 1.5 s：不响应挑衅；结束回待机，上头清零。这样每次扑击后有明确搬运窗口。
- 扑击结束按 1.25 m 判定“命中/扑空”；本轮没有伤害或燃料抢夺，只显示结果。

## D-05 不穿墙、不每帧触发、不切换目标

- 挑衅和靠近都做 2D/3D 射线视线检查（碰撞层 2）。
- 奶龙是 `CharacterBody3D`，扑击撞墙/撞玩家会提前结束；不做瞬间位移。
- 目标只有当前玩家；未实现多目标选择，因此不存在随机切换。
- Q 用事件 + 冷却；不是 `_process` 轮询。

## D-06 外观与行为分离

- `milk_dragon.gd`：状态机、感知、移动、参数；无模型资源。
- `milk_dragon_visual.gd`：程序化占位外观、状态环、颜色/挤压/抖动；
  通过 `set_behavior(state, agitation, windup, pounce)` 接收表现指令。
- 下一轮替换正式模型时，只需改 visual 或换成 GLB 场景，不改行为。

## D-07 不导入第三方奶龙模型

- 查找记录见 `ASSETS.md`。
- 找到 Sketchfab 的 GLB 候选，但多数 0 动画；唯一 1 动画的“奶龙女孩”是 21.8 MB 的衍生角色。
- CC BY / Free Standard 只代表上传者授权，不当然包含奶龙 IP 的公开商用/发行权。
- 选择：本轮继续程序化占位；不下载、不提交第三方模型，不绕过任何访问限制。

## D-08 参数集中与原型标记

- 所有行为数值集中在 `milk_dragon.gd` 顶部 `@export`，文档与 HUD 标为原型值。
- 本轮不把数值写成最终平衡；等待真人试玩。

## D-09 不生成新截图、不强制开窗

- 用户明确要求不要强制打开窗口。
- 选择：验证只跑 `--headless`；`--shots` 仍保留给使用者主动运行，但移除了强制置前。
- 旧基础版截图已删除，避免把绿色占位咕噜误当成本轮奶龙。
- 因此本轮没有行为截图；证据是 headless 28/0 日志与代码/文档。

## D-10 分支与网络

- 本地 `origin/main` 仍是旧 2D `3969511`；GitHub 当前 main 为 `42519ff`。
- `git fetch` 多次连接重置，无法把分支基到最新 main；预览文件从 42519ff raw 复制且自包含。
- 网络恢复后需 rebase 到最新 main；未推送、未合并。

## D-11 Blender 用官方 LTS 便携包，不装第三方/MCP

- 机器原先没有 Blender；从官方 `download.blender.org` 下载 **4.5.15 LTS** Windows x64 ZIP，
  校验官方 SHA256 后解压到用户目录。
- 未使用第三方整合包；未安装 MCP 或额外插件。
- 路径：`C:\Users\31798\AppData\Local\Programs\Blender Foundation\Blender 4.5\blender.exe`。
- 自带 Python 3.11.15；无界面脚本可生成/导出/回读 GLB。

## D-12 独立 GLB 测试资产，不替换奶龙

- 新增 `assets/test/blender_link_test.glb`、可编辑 `.blend` 与生成/回读脚本。
- 测试对象放在 `(-4, 0, 2.5)`，无碰撞，仅验证 Blender → GLB → Godot。
- 实测 4 个 mesh、主体 0.8 m、+Y→−Z、+Z→+Y、材质导入；自测 38/0。
- 坐标规范：Blender 源文件 Z-up、脚底 z=0、测试前向 +Y；Godot 导入后 Y-up、脚底 y=0、前向标记 −Z。不要把 Godot 轴向直接写进 Blender 源文件。
- 不把测试资产接进奶龙行为或正式资源。

## D-13 第三方奶龙：静态模型已检查，Sketchfab 候选未下载

- 公开 GitHub `scnuLwz/ai_work_proflie` 的 `nailong.glb` 已下载到仓库外并校验；
  Blender 回读 1 mesh / 846,783 顶点 / 0 armature / 0 action / 3 张 4K 贴图，属静态 AI 网格。
- 该仓库无 LICENSE；角色 IP 未授权；只做内部检查，不导入、不提交、不替换角色。
- Sketchfab 页面标可下载，但匿名下载 API 返回 401；不绕过登录，候选文件未取得。
- 因未取得 Sketchfab 文件，不能确认其骨骼/权重/动画轨道；`animationCount=0` 不等于不能使用。
- CC BY / Free Standard 不当然包含奶龙 IP 发行权；本轮不导入第三方模型。
- 推荐下一轮：团队自制或确认 IP/发行授权后再进 Blender 处理。

## 待用户决定

1. 真人试玩后：挑衅范围、蓄势 1.0 s、扑击 11 m/s 是否合适。
2. 是否要“持续挑衅”改为按住/长按，还是保持单次 Q。
3. 奶龙正式形象/IP 授权与动画方案。
4. 燃料搬运、抢夺、追回、道具与声音入口的规则。
