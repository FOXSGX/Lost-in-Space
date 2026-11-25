# 迷失太空（Lost in Space）

214 宿舍游戏项目，游戏名称已由团队确定为《迷失太空》（Lost in Space）。

GitHub 仓库：[FOXSGX/Lost-in-Space](https://github.com/FOXSGX/Lost-in-Space)。

本机试玩：双击根目录 `运行.cmd`，按编号选择主游戏、美术演示、物理沙盒或霜烬星预览；也可以直接运行 `$env:LOCALAPPDATA\Programs\Godot\4.7.2\Godot_v4.7.2-stable_win64.exe --path game`。

## 霜烬星 0.4：六栋科考站（2026-10-29）

按建筑采访方案接入新版霜烬星：大厅与综合实验室、主楼二层环廊和首席办公室保险柜、静态骨架标本馆、可吃与收藏的生活物资、可驾驶运货载队友的运输车、动力恢复、仓库局部融冰探索。主舱“新航程→出舱”已加载新版，运输车可进入实际可通过的遗迹地形。旧0.3预览保留。

独立入口：[启动新版霜烬星](game/previews/frost_station/play.cmd)。免安装试玩包在 `builds/Frost_Station_v0.4/`，双击“启动霜烬星.cmd”；“启动完整航程.cmd”保留主舱航线流程。操作与验证边界见[新版说明](game/previews/frost_station/README.md)及[六栋建筑设计](docs/design/planets/planet-00-科考站建筑设计.md)。当前为可玩低模原型，仍需真人节奏、四人体验和美术迭代。

### 霜烬星美术层（2026-11-24，按共振星模板）

按 ART-SAMPLE-002 的 `ART-PLANET-VISUAL-STANDARD v1` 与共振星 `cave_*` 做法，给六栋科考站补了五族材质（涂装钢构/基岩/雪/冰/骨）、环境与三光位、门斗与灯具、基座/檐雪/冰锥/雪堆/裂隙/冰晶簇/飘雪，并把家具原色收进站区色板。只改视觉，碰撞、交互与联机结算不动；`FROST_ART=0` 可关闭做同机位对照。规则见[霜烬星美术说明](docs/design/planets/planet-00-霜烬星美术说明.md)，证据与结论见[本轮美术迭代](work/art-iterations/20261124-frost-station-art/README.md)：技术 GO、视觉 CONDITIONAL GO、性能 P50 +25%（待合并 Draw Call），尚未真人试玩。

## 共振星五幕试玩版（2026-11-21 接收）

队友上传的独立导出包，已解压到 `builds/Resonance_FiveActs_20261121/`。包内是单文件 `迷失太空_共振星试玩版.exe`（610 MB，内嵌资源）加 5 个快捷脚本：五幕完整版、第一幕·静默矿站、第二三幕·矿车与断轨、第四幕·晶体洞窟、第五幕·地心核心。

- 操作：WASD 移动、Shift 奔跑、空格跳、E 交互/抓扶/操控台、F 拾取或放置晶体、Q 旋转晶体、X 抛下、左右键挥拳、R 重置本幕、Esc 暂停菜单。
- 联机：2–4 人，局域网主机端口 9877；异地需先连同一虚拟局域网再填房主 IP。
- 这是独立构建，与仓库内 `game/` 的共振星关卡不是同一份实现，运行时也不会改动仓库。原始压缩包存于 `work/incoming-20261121/`，说明见包内 `试玩说明.txt`。

2026-10-28 正式入口已接入新主线：菜单“新航程”从坠落霜烬星的飞船开始，先出舱寻找能源修复起飞核心，再通过航线电脑的当前星系图选择目的地，全员驾驶席就位后出发。已安装核心与归航能源分开记账；霜烬星重访保留任务和融冰进度，搜集足够能源与物资后可主动返航地球。“继续航程”使用独立存档，不覆盖旧主舱存档。操作、原型数值与验证见[新航程与当前星系图](game/docs/campaign-navigation.md)。下方较早的信标/主舱开局描述保留为旧实现背景，以本更新为当前正式入口规则。

多人合作生存射击闯关游戏：迷航的地球人前往不同星球搜集燃料与物资，最终返回地球。支持单人尝试通关。

当前 `game/` 已切换为 Godot 4 的真实 3D 运行架构：使用 `Node3D`、`Camera3D`、`CharacterBody3D` 和 `StaticBody3D`。太空舱、训练舱和新版霜烬星采用第一人称，旧霜烬星信标预览保留正交视角，共振星采用第三人称。原 2D/伪 2.5D 版本已备份到 `backups/霜烬星-2.5d-20261009/`。

当前统一操作：WASD 移动、鼠标环视、Shift 加速、空格跳跃；E 拾取/操作/投送/救援，左键使用手中选中物品（空手攻击），右键扫描。初始两个手持格和两个橙色装备格，Tab 切换两栏焦点，1/2 或滚轮选择当前栏，G 丢落物品或卸下选中装备；星球日志 J、地图 M。主舱每个功能区使用一台电脑：靠近按 E 打开图形界面，选择图片卡并确认，Esc 关闭后恢复环视；航线、制作、装备、道具和换装的同类选项已合并，维修、补给、归还、记录和离舰有各自电脑。四个驾驶台仍各自按 E 就位，全员就位后倒数出发；再次 E 或走开取消。规则与实机图见 [主舱设备](game/docs/ship-devices.md)、[两格物品栏](game/docs/interaction-inventory.md)。

太空舱已采用新下载的 Kenney Space Station Kit 与 Modular Space Kit，更新舱壁、甲板、天花板、驾驶台、气闸及生活区陈设。资源授权、实机截图和验证见 [Kenney 美术接入](game/docs/ship-hub-kenney-art.md)。

生命系统第 1 层已接入：左上绿色五格血量，满血 5 点，普通攻击扣 1 点；零血倒地，停止移动、跳跃、推进和攻击，显示简洁倒地图标。上方中间仅显示“主舱”或“训练舱”。详见[生命系统与验证](game/docs/health-layer1.md)。

当前可试玩流程为“主界面 → 可移动的归航号主舱 ↔ 训练舱 → 星际航线图 → 霜烬星或共振星 → 返回主舱”。主舱正按用户选择的精致卡通方向迭代，加入圆润设备、统一配色和舱内陈设；现为约 42×33 米的大空间，采用第一人称在舱内行走查看各区域。主舱已接入共享储物、舰体维修、补给恢复与物资制作、任务记录和全员准备。靠近设施按 `E`；补给、任务货物共用初始两格物品栏，一格一件，选择后按左键使用；共振星使用透视 3D 镜头、纵深机械结构、地面引导光点和“下一步”目标标牌，三节模块分别提供路线双端锁止、磁力货箱护送、交替光束校准，随后进入升降接力、镜面反射、冷却单元护送三段反应堆甲板任务，单人按 `Z` 部署辅助无人机。现场设备的持续操作会显示进度条，战斗和关键物资操作会显示浮动确认与轻量镜头反馈。玩法和可调整数值见 [`game/docs/ship-hub-3d.md`](game/docs/ship-hub-3d.md)、[`game/docs/interaction-experience.md`](game/docs/interaction-experience.md) 与 [`docs/design/planets/planet-01-共振星.md`](docs/design/planets/planet-01-共振星.md)。

探索系统还包括地图线索支线、日志成就、星球长期状态、资源点刷新、失败资源散落、团队共享装备/货币和实体集市终端。欢乐道具从道具柜按 E 领取，装入物品栏后按左键重复使用，不扣数量、不设置冷却。实现细节见 [`game/docs/campaign-systems.md`](game/docs/campaign-systems.md)。

## 氧气瓶推进练习（2026-10-22）

从主舱气闸按 E 进入训练舱，在氧气瓶架前按 E 拿取，左键装到宇航服。短按空格立即跳跃，长按空格喷气登高，WASD 控制移动；单瓶满条支持 0.5 秒喷气，双瓶合计 1 秒，按装备栏顺序耗完第一条再用第二条。落地松开等待后，两根条同时恢复，各自消耗对应瓶内少量氧气。主舱补给设备可补满瓶内氧气。Tab 选择装备栏、滚轮选中氧气瓶后按 G 卸下并丢在地上，再 Tab 返回手持栏。训练依次通过低台、高台与终点落台，途中有恢复压力的中继落台；回到门口按 E 返回主舱，正式背包和原装备会恢复。

放下的轻型道具有碰撞体积，会自然翻倒、落地，氧气瓶可以躺在地上并再次拾取。主机同步落点和旋转。说明和验证见[宇航服氧气瓶推进与实体训练](game/docs/oxygen-jet-training.md)。

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
| `game/addons/` | 团队 Godot 插件；当前为 `lis_physics` 第一人称物理 SDK |
| `art-source/references/` | 美术风格参考 |
| `art-source/ai-generated/` | AI 原图、提示词和生成记录 |
| `art-source/editable/` | 可编辑美术原稿 |
| `art-source/licenses/` | 素材来源及授权记录 |
| `art-source/deliveries/` | 队友或外部交付的美术包，保持原始结构与验收材料 |
| `builds/` | 按版本号存放导出的试玩包 |
| `submission/` | 最终参赛说明、截图和视频 |

## 队友交付包（2026-11-21 解包归位）

两份队友交付已解压到各自目录，原始压缩包保存在 `work/incoming-20261121/`（本地存档，不入库）。

- **美术母版 ART-SAMPLE-002** → `art-source/deliveries/ART-SAMPLE-002_TEAM_KIT/`：独立 Godot 演示工程、Blender 源与高模烘焙链路、可直接使用的 GLB、2K 材质库、5 份美术规范、四机位验收图和验证日志。包内结论为技术验收 GO / 视觉 CONDITIONAL GO；解压后按包内清单复核 SHA256 208/208 全等。索引见 [art-source/README.md](art-source/README.md)。
- **物理 SDK LIS-PHYSICS 1.0.0-rc1** → `game/addons/lis_physics/`，文档在 [`game/docs/lis-physics/`](game/docs/lis-physics/)，示例在 `game/examples/`。Godot 4.7.2 下导入无错误，环境体检 `verdict=OK-WITH-WARNINGS`，示例 `minimal_planet` 可启动。安装、验证与未落地事项见 [物理 SDK 安装记录](game/docs/lis-physics-sdk.md)。

接入物理 SDK 前仍需决定：3D 物理引擎是否显式切到 Jolt、共振星与腐墟星第三人称镜头与“SDK 只覆盖第一人称”的取舍、旧物件碰撞层位值 4 与 8 的对齐。

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
