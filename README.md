# 迷失太空（Lost in Space）

214 宿舍游戏项目，游戏名称已由团队确定为《迷失太空》（Lost in Space）。

GitHub 仓库：[FOXSGX/Lost-in-Space](https://github.com/FOXSGX/Lost-in-Space)。

多人合作生存射击闯关游戏：迷航的地球人前往不同星球搜集燃料与物资，最终返回地球。支持单人尝试通关。

当前 `game/` 已切换为 Godot 4 的真实 3D 运行架构：使用 `Node3D`、正交 `Camera3D`、`CharacterBody3D` 和 `StaticBody3D`，以低模 3D + 正交视角呈现《弓箭手大作战》风格的 2.5D 体验。原 2D/伪 2.5D 版本已备份到 `backups/霜烬星-2.5d-20261009/`。

当前可试玩流程为“主界面 → 可移动的归航号主舱 ↔ 训练舱 → 星际航线图 → 霜烬星或共振星 → 返回主舱”。主舱正按用户选择的精致卡通方向迭代，加入圆润设备、统一配色和舱内陈设；现为约 42×33 米的大空间，使用角色跟随镜头，整舱无法一屏看完。主舱已接入共享储物、舰体维修、补给恢复与物资制作、任务记录和全员准备。靠近设施按 `E`；星球内按 `3` 使用医疗包、按 `4` 使用氧气瓶；共振星使用透视 3D 镜头、纵深机械结构、地面引导光点和“下一步”目标标牌，三节模块分别提供路线双端锁止、磁力货箱护送、交替光束校准，随后进入升降接力、镜面反射、冷却单元护送三段反应堆甲板任务，单人按 `Z` 部署辅助无人机。现场设备的持续操作会显示进度条，战斗和关键物资操作会显示浮动确认与轻量镜头反馈。玩法和可调整数值见 [`game/docs/ship-hub-3d.md`](game/docs/ship-hub-3d.md)、[`game/docs/interaction-experience.md`](game/docs/interaction-experience.md) 与 [`docs/design/planets/planet-01-共振星.md`](docs/design/planets/planet-01-共振星.md)。

探索系统还包括地图线索支线、日志成就、星球长期状态、资源点刷新、失败资源散落、团队共享装备/货币和“星际集市·交易星球”。5—9 键是可以连续触发的欢乐道具，不设置冷却。实现细节见 [`game/docs/campaign-systems.md`](game/docs/campaign-systems.md)。

## 共振星 03.1 绞盘原型（独立预览）

`game/previews/resonance_03_winch_prototype/` 是独立单人试玩原型：第三人称走到断裂轨道，选择吊耳挂缆，
回绞盘收放，观察轨道实际移动、过冲与放线回摆，最后到锁定座插销。正常 HUD 只给目标/状态/张力条，
F3 才显示角度等调试数据。**尚未接入正式共振星关卡**，等 Resonance 02 质量返工验收后再讨论整合。

- 工程说明：[`README.md`](game/previews/resonance_03_winch_prototype/README.md)
- 操作说明：[`README_试玩说明.txt`](game/previews/resonance_03_winch_prototype/README_试玩说明.txt)
- 已知问题：[`KNOWN-ISSUES.md`](game/previews/resonance_03_winch_prototype/KNOWN-ISSUES.md)
- 帧时间分析：[`PERFORMANCE.md`](game/previews/resonance_03_winch_prototype/PERFORMANCE.md)
- 交接：[`HANDOFF.md`](game/previews/resonance_03_winch_prototype/HANDOFF.md)
- 单人试玩包：`builds/Resonance_03_Winch_v0.1_20261020/`（双击 `启动_Resonance_03_Winch.cmd`）
- 本轮证据：`work/gameplay-iterations/20261020-resonance-03-1-playability/`

真人试玩尚未进行；自动探针通过不等于玩法已被证明有趣。

## 从这里开始

- [第一次会议纪要与项目共识](docs/meetings/第一次会议纪要与项目共识.md)
- [游戏设计总纲](docs/design/游戏设计总纲.md)
- [任务与分工](docs/planning/任务与分工.md)
- [开发里程碑](docs/planning/开发里程碑.md)
- [比赛要求](docs/competition/比赛要求.md)

## 目录用途

| 目录 | 内容 |
| --- | --- |
| `docs/meetings/` | 会议记录；保留讨论经过和决策依据 |
| `docs/design/` | 当前设计规则；确认后的决定更新到这里 |
| `docs/design/planets/` | 每颗星球的设计说明 |
| `docs/planning/` | 任务、负责人和里程碑 |
| `docs/competition/` | 官方比赛规则、截止时间、提交要求 |
| `game/` | 引擎项目和游戏实际使用的资源 |
| `art-source/references/` | 美术风格参考 |
| `art-source/ai-generated/` | AI 原图、提示词和生成记录 |
| `art-source/editable/` | 可编辑美术原稿 |
| `art-source/licenses/` | 素材来源及授权记录 |
| `builds/` | 按版本号存放导出的试玩包 |
| `submission/` | 最终参赛说明、截图和视频 |

## 协作约定

- 以设计总纲为当前共识入口，会议纪要用于追溯；建议先标记为“待讨论”。
- 按功能和内容组织文件，负责人写入任务表。
- 会议文件可使用 `YYYY-MM-DD-主题.md`；第一次会议日期未知，保留原文件名。
- 星球使用固定编号，如 `planet-01`；先共同完成霜烬星原型，再分工制作。
- 试玩包使用版本目录，如 `builds/v0.1.0/`，附运行方式和已知问题。
- 选定引擎后再确定 `game/` 内部结构、运行步骤和缓存忽略规则。
- 使用 Git 管理代码和文档；试玩包默认不入库，可通过 GitHub Releases 分享。大型原稿的版本管理方式待确认。

## 第一周联机测试

- Godot 工程：[`game/`](game/)
- 运行入口：`game/project.godot`
- 成员1交付说明：[`game/docs/week1-member1.md`](game/docs/week1-member1.md)
- 主机端口：`24567`
- 霜烬星测试：主机切换阶段后，靠近 3 个气象信标按 `E` 修复；共振星测试：模块 1 由导能和定场玩家双端锁止，模块 2 由搬运者和稳定者护送磁力货箱，模块 3 由队伍交替校准 A/B/C 光束，单人按 `Z` 部署辅助无人机。
- Windows 导出预设：`game/export_presets.cfg`

用 Godot 4.3+ 导入 `game/project.godot` 后运行。一个实例点击“创建主机”，其他实例输入主机局域网 IP 并点击“加入主机”。
