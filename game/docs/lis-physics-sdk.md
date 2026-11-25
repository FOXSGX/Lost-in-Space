# 第一人称物理 SDK（lis_physics）安装记录

来源：队友交付包 `LIS-PHYSICS-V1.0.0-RC1.zip`，2026-11-21 解包安装；包内构建时间 2026-11-10。
版本 `1.0.0-rc1`（候选版，不是稳定版）。完整限制见 [`lis-physics/PHYSICS_LIMITATIONS.md`](lis-physics/PHYSICS_LIMITATIONS.md) 与 [`lis-physics/TEAM_HANDOFF.md`](lis-physics/TEAM_HANDOFF.md)。

## 装到了哪里

| 位置 | 内容 | 来源 |
| --- | --- | --- |
| `game/addons/lis_physics/` | 插件本体，27 个文件（刚体、抓握、车轮、杠杆、门、缆绳、主机权威适配、体检与性能工具） | 包的 `addons/` |
| `game/docs/lis-physics/` | 原始文档与 `VERSION.json` | 包的 `docs/` |
| `game/examples/` | 8 个示例场景与公共脚本，按包内原始路径放置，`res://examples/...` 可直接运行 | 包的 `examples/` |

未复制的部分：包的 `tests/`（功能测试套件）、`tools/`（打包与批量运行脚本）、根目录 `SHA256SUMS.txt`。它们仍在 `work/incoming-20261121/LIS-PHYSICS-V1.0.0-RC1.zip` 内；需要跑功能测试时按 TEAM_HANDOFF 第 7 节把 `tests/` 与 `tools/` 复制到工程根再执行 `tools\run_tests.ps1`。编辑器插件未启用（`plugin.gd` 只打印提示，不影响运行）。

## 已验证

在 Godot 4.7.2-stable 上实测：

1. 解包内容按包内 `SHA256SUMS.txt` 复核 **120/120 全等**，无缺失、无改动。
2. `godot --headless --path game --import` 退出码 0，无脚本或资源错误。
3. 工程体检 `--script res://addons/lis_physics/tools/lis_project_check.gd`：
   `errors=0 warnings=2 infos=14`，`verdict=OK-WITH-WARNINGS`，22 个必需资源全部存在。
4. 示例 `res://examples/minimal_planet/minimal_planet.tscn` 以 headless 启动 180 帧，无报错。

## 两条体检警告的现状

- **物理引擎仍是 `DEFAULT`**：工程 [project.godot](../project.godot) 没有 `[physics]` 段。SDK 要求 `physics/3d/physics_engine = "Jolt Physics"`。切换会改变现有刚体表现（氧气瓶丢落、运输车、磁力货箱等），必须切完重跑相关测试再定。
- **第 3 层未命名**：SDK 默认把可交互刚体放在第 3 层（位值 4），建议命名为 `interactable`。旧代码里可交互物常用第 4 层（位值 8），迁移时要在 `LISBodyProfile` 里显式指定，SDK 不会自动跟随。

## 接入前要做的决定

1. 是否把 3D 物理引擎显式切到 Jolt，以及切换后谁负责回归现有星球与主舱的物理表现。
2. SDK 只覆盖第一人称；共振星、腐墟星当前是第三人称镜头。是全游戏统一第一人称，还是只在新内容里用 SDK，需要团队定。
3. 哪些星球先接入、先接哪几类组件（门 / 车轮 / 杠杆 / 缆绳），建议按 TEAM_HANDOFF 第 11 节逐个接，不要一次性替换现有机关。

## 为示例补齐的输入动作

示例里的 `LISDemoPlayer` 读的是 SDK 开发工程的动作名，而本工程原来只有 `move_up/move_down` 等。为了示例能直接操作，2026-11-21 在 [project.godot](../project.godot) 的 `[input]` 里**新增**了 8 个动作，没有改动任何已有动作：

| 动作 | 绑定 | 用途 |
| --- | --- | --- |
| `move_forward` / `move_back` | W / ↑、S / ↓ | 与工程原有 `move_up` / `move_down` 等价的别名，仅供示例玩家读 |
| `lis_grab` | 鼠标左键 | 抓取 / 松手 |
| `lis_release` | 鼠标右键 | 松手 |
| `lis_throw` | X | 抛掷 |
| `lis_rotate_left` / `lis_rotate_right` | Q / E | 旋转持有物 |
| `lis_reset` | R | 复位示例场景 |

主游戏代码不读这些动作，所以运行主场景的行为不变（已用 headless 跑主场景 240 帧确认无报错）。改动前的 `project.godot` 备份在 `work/project.godot.before-lis-input-20261121`；如果不想保留，打开 Godot 的项目设置删掉这 8 个动作即可。

## 运行示例

```powershell
$godot = 'C:\Users\IMAFOX\AppData\Local\Programs\Godot\4.7.2\Godot_v4.7.2-stable_win64.exe'
& $godot --path game res://examples/minimal_planet/minimal_planet.tscn
```

`minimal_planet` 是最小接入样板（一个箱子、一扇门、一个杠杆）。
