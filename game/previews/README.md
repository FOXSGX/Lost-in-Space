# 共振星预览工程（默认关闭）

这里放的是 9 个**独立**的 Godot 预览工程。它们不是主游戏的一部分，
只是共振星不同阶段的试玩 / 审查原型。

## 为什么默认关掉

Godot 的项目管理器会递归扫描子目录里的 `project.godot`。
如果这些文件保持原名，打开 `repo/game` 时会一次列出主工程 + 9 个预览工程。

所以默认把每个预览的 `project.godot` 改名为 `project.godot.disabled`。
主工程 `../project.godot` 不受影响，打开 `repo/game` 只会看到一个项目。

## 怎么临时打开某个预览

在 PowerShell 里运行：

```powershell
# 恢复全部 9 个预览的 project.godot
./toggle_previews.ps1 -Action enable

# 用 Godot 打开 game/previews/<你要看的工程>/project.godot
# 看完后重新关闭，避免项目管理器又列出 10 个项目
./toggle_previews.ps1 -Action disable

# 只查看当前状态
./toggle_previews.ps1 -Action status
```

也可以手动把某个目录里的 `project.godot.disabled` 改回 `project.godot`。
`.godot/` 缓存和 `assets/` 都不动，重新打开不需要重新导入整包。

## 当前预览列表

- `resonance_02_moving_cart`
- `resonance_02_quality_rework`
- `resonance_03_winch_prototype`
- `resonance_cooperation_slice_01`
- `resonance_coop_playtest_01`
- `resonance_coop_playtest_01_1`
- `resonance_mining_station_01`
- `resonance_mining_station_01_1`
- `resonance_station_interaction_01`

这些都是第三人称 / 固定机位原型，和主舱、腐墟星现在的第一人称不是同一套相机。
主工程仍然是 `repo/game/project.godot`。
