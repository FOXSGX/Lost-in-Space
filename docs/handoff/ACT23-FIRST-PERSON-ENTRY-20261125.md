# ACT23-FIRST-PERSON-ENTRY · Act23 独立第一人称入口导入

日期：2026-11-25
范围：把已同步的 Act23 第一人称模块导入 `repo/game` 并验证可从 Godot 独立运行。
未改：主游戏 `main_3d.tscn`、主游戏共振星入口 `resonance_stage.tscn`、剧情/联机/数值。

## 问题

打开 `repo/game` 后按 F5 运行的是主游戏 `main_3d.tscn`；主游戏的“登陆共振星”走
`resonance_stage.tscn`，玩家是第三人称 `SpacePlayer3D`。

第一人称新版是独立模块：

- `game/act1/act01.tscn`
- `game/act23/act23_entry.tscn`

它们没有被主游戏调用。所以从主菜单进共振星仍然是旧第三人称，不是 Act23 的 bug。

## 本次操作

1. `godot --headless --path game --import` 完成资源导入。
2. 新增 `game/act23/README.md`：说明用 **F6 运行当前场景**，不要用 F5。
3. 新增 `game/act23/tests/act23_first_person_smoke.gd`，直接实例化 `act23_entry.tscn` 检查第一人称。
4. 用 headless 启动 `act23_entry.tscn`，确认无资源/脚本错误。
5. 跑 Act1 既有 `act1_module_smoke.gd`，确认第一幕模块也能独立启动。

## 验证结果

| 项目 | 结果 |
|---|---|
| `godot --headless --path game --import` | 0，导入完成 |
| `act23/act23_entry.tscn` headless 启动 | 0 |
| `act23_first_person_smoke.gd` | 10/0 |
| `act1_module_smoke.gd` | 24/0 |

Act23 smoke 断言：

- 入口场景可实例化，`MovingCartSlice` 存在。
- 玩家 `use_first_person = true`。
- 相机是 `current`，父节点是玩家，眼高 1.30 m。
- `fp_rig` 第一人称手部模型存在。
- 本地玩家标记为 true。

## 怎么运行

见 [game/act23/README.md](../../game/act23/README.md)：

- 编辑器：打开 `repo/game/project.godot` → 双击 `act23/act23_entry.tscn` → F6。
- 命令行：`godot --path game res://act23/act23_entry.tscn`。

## 后续

如果要把主游戏“登陆共振星”直接切到新版 Act23，需要另做整合：
主舱航线 → Act23 场景切换、返回主舱、联机席位、HUD/物品、任务状态。本轮只完成独立入口，未改主流程。
