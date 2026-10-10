# 迷失太空（Lost in Space）

214 宿舍游戏项目，游戏名称已由团队确定为《迷失太空》（Lost in Space）。

GitHub 仓库：[FOXSGX/Lost-in-Space](https://github.com/FOXSGX/Lost-in-Space)。

多人合作生存射击闯关游戏：迷航的地球人前往不同星球搜集燃料与物资，最终返回地球。支持单人尝试通关。

当前 `game/` 已切换为 Godot 4 的真实 3D 运行架构：使用 `Node3D`、正交 `Camera3D`、`CharacterBody3D` 和 `StaticBody3D`，以低模 3D + 正交视角呈现《弓箭手大作战》风格的 2.5D 体验。原 2D/伪 2.5D 版本已备份到 `backups/霜烬星-2.5d-20261009/`。

前端流程为“主界面 → 飞船准备区 → 星际航线图 → 霜烬星”，中间页面使用 3D 舰桥背景和 CanvasLayer 面板，主机在航线图确认登陆后才开始星球关卡。

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
- 霜烬星测试：主机切换阶段后，靠近 3 个气象信标按 `E` 修复；电磁星球暂作为后续关卡保留。
- Windows 导出预设：`game/export_presets.cfg`

用 Godot 4.3+ 导入 `game/project.godot` 后运行。一个实例点击“创建主机”，其他实例输入主机局域网 IP 并点击“加入主机”。
