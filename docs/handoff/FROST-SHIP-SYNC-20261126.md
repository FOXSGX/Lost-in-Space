# FROST-SHIP-SYNC-20261126 · 新霜烬星/太空舱分支同步与腐墟星 UI 统一

## 一、同步

- 分支：`origin/feat/ship-and-frost-2.0`
- 远端最新：`a9deaab`
- 本地合并：`975c12c`
- 本地 `main`：ahead 13（含 5 个新分支提交和之前的腐墟星提交）
- 同步前备份：`backup/pre-frost-sync-20261126`
- 未 push。

### 冲突处理

| 文件 | 处理 |
|---|---|
| `game/project.godot` | 保留 LIS 插件配置 + 新分支 HarmonyOS 全局字体 |
| `game/scripts/crew_items_3d.gd` | 合并新霜烬星物品名与腐墟星 `lockpick` |
| `game/scripts/main_3d.gd` | 保留腐墟星/共振星接入，合入新分支 `CampaignTravel3D`、气闸返航与 UI |
| `game/scripts/ship_devices_3d.gd` | 采用新分支 campaign/workshop/surface 选项 |

### 资源兼容

新分支 `crew_items_3d.gd` 引用了 `res://previews/...`，但 `game/previews/.gdignore` 使这些资源不会被导入。为避免取消 `.gdignore` 后把整个 previews 导入主工程，已将所需图标复制到：

`game/assets/ship_signs/icon_suction.png`、`icon_chips.png`、`icon_keepsake.png`、`icon_crate.png`、`heat.svg`、`cell.svg`

并更新 `crew_items_3d.gd` 引用。

## 二、腐墟星 UI/美术统一

- 项目全局字体切换为新分支的 **HarmonyOS Sans SC**（Regular/Bold）。
- `main_3d` 的 HUD 面板改用 `UIStyleKit.visor_box()`：深空玻璃、冷青描边、左侧强调条。
- 标签统一 `UIStyleKit.FONT_REG`；按钮统一 `UIStyleKit.style_button()`（teal/sand）。
- 腐墟星对话面板、选项按钮、日志/设置/交互提示同步新风格。
- 新 `HealthHUD3D`（VITALS / O2 / TEMP）取代旧右上氧气读数；旧 `_vitals_panel` 永久隐藏，避免重复。
- 隐藏非飞船状态的 `MissionCompassHUD`（TAC-MAP 与右上空白面板），修复进入腐墟星后残留太空舱 HUD 的问题。
- 目标面板下移避开 VITALS；交互提示上移，避免遮挡新物品快捷栏。

## 三、医院相关修复（本轮）

- B1 药房门/铁笼取消；1F 药房铁栅取消；1F 大厅接待黑色后板取消。
- 每层楼梯只保留一个 2.4 m 入口，位置按梯段抵达侧交错：
  - B1 南 +6
  - 1F 北 -6
  - 2F 南 +6
  - 3F 北 -6
- 1F 大厅西侧通道完全打开。
- B1 药库稳定剂仍可正常拾取。

## 四、验证

- `ruin_hospital_stair_traversal.gd` **154/0**
- `ruin_hospital_interior.gd` **57/0**
- `ruin_laser_sword.gd` 7/0
- `ruin_first_person.gd` 21/0
- `ruin_door_lock.gd` 44/0
- `ruin_interior_clipping.gd` 1492/0
- `ruin_story.gd` 37/0
- `ruin_art_audit.gd` 47/0
- 其余腐墟星全量回归通过。

## 五、边界

- 新分支 5 个提交主要在霜烬星/太空舱；腐墟星只做 UI/医院几何适配，不改霜烬星/联动数值。
- 没有提交/推送工作区中的腐墟星修改。

## 六、临时自由选星（调试）

- `game/scripts/main_3d.gd`：`DEBUG_FREE_DESTINATION := true`。
- 正常新航程/读档后把该值写入 `CampaignNavigation.debug_free_destination`，只跳过目的地门槛，不改变飞船操作。
- 霜烬星、共振星、腐墟星、地球四颗目的地均可直接选择；地球仍走原有归航演出。
- 临时验证：`campaign_free_destination.gd` 14/0。
- 恢复正式航程：把 `DEBUG_FREE_DESTINATION` 改回 `false`。