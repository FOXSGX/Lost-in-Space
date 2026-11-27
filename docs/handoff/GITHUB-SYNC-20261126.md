# GitHub 同步记录 · 2026-11-26

## 同步结果

- 远端：`origin/main` → `a899839`（45 个新提交）
- 本地：`main` 合并为 `55e905e`（merge commit）
- 本地相对远端：ahead 7（保留原有腐墟星提交 + 本次 merge）
- **未 push**，工作区仍有本地未提交改动（腐墟星/美术/文档等）。

## 冲突与处理

| 文件 | 处理 |
|---|---|
| `game/project.godot` | 采用远端的物理层命名，去掉本地的重复 key；保留 `common/physics_ticks_per_second=60` |
| `game/scripts/main_3d.gd` | 保留本地腐墟星/共振星接入，合并远端其余改动 |
| `game/scripts/space_player_3d.gd` | 保留本地腐墟星/共振星输入与移动分支，合并远端其余改动 |
| `docs/resonance/美术制作与AI协作指南.md` | 采用远端版本（远端已重写为全星球统一指南） |

为保证本地共振星旧接入可加载，补回了合并时被远端删除的本地依赖：
`resonance_stage.tscn`、`resonance_stage.gd`、`resonance_cave_chapter.gd`、`minigame_gauge.gd`、`resonance` 贴图等。这些文件目前处于 staged/工作区状态，尚未单独提交。

## 合并后验证

腐墟星全量测试 19 项全部 exit 0：

- `ruin_interior_clipping.gd` 1492/0
- `ruin_hospital_stair_traversal.gd` 131/0
- `ruin_wayfinding.gd` 16/0
- `ruin_art_audit.gd` 47/0
- 其余医院、能源站、学校、市场、剧情、结局、撤离、联机入口、门锁、物品、感染者动画、僵尸平衡、掉落恢复全部通过。

远端新增测试抽查：

- `test_snapshot_wire.gd` 通过
- `test_reset.gd` 通过
- `test_solo_coop.gd` 通过
- `test_scene_switch.gd` **失败**：`ResonanceCradle` 没有 `accept_crystal`，hammer 未触发。该失败与腐墟星无关，本次同步未修改 Act4/Act5。

## 待办

- 本地 189 项未提交改动仍保留，需人工决定是否提交。
- `test_scene_switch.gd` 的 Act4/Act5 接口问题需要远端/共振星负责人确认；不是腐墟星回归。
