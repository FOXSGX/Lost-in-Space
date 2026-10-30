# 共振星内容索引（队友参考用）

> 口径：**本仓库里所有共振星内容以本机（M-J-M-6，2026-10-26）版本为准。**
> 2026-10-26 已把被其他机器改写的共振星文件回退到本版本：
> `game/scripts/resonance_stage.gd`、`game/scripts/resonance_cave_chapter.gd`、
> `game/assets/resonance/models/*.import`（14 个）。
> 非共振星内容（主舱电脑、双装备栏、生命 HUD、Kenney 素材等）保持仓库最新版不动。

## 1. 主工程里的共振星实现

| 路径 | 内容 |
| --- | --- |
| `game/scripts/resonance_stage.gd` | 轨道工厂主逻辑：三节移动能源模块、双端锁止、磁力货箱、A/B/C 光束、反应堆甲板、返航平台（239 KB / 约 3.9k 行） |
| `game/scripts/resonance_cave_chapter.gd` | 洞穴章节：路线、机关、撤离与 HUD（48 KB） |
| `game/scripts/resonance_cave_art.gd` | 洞穴资产接入与材质分配（18 KB） |
| `game/scripts/resonance_cave_feedback.gd` | 洞穴反馈层（47 KB） |
| `game/scripts/minigame_gauge.gd` | 小游戏量表控件 |
| `game/assets/resonance/models/` | 25 个运行时 GLB（模块、轨道、反应堆、洞穴、无人机、返航平台等） |
| `game/assets/resonance/textures/` | `alien_rock_ground.png`、`industrial_panel.png` |
| `game/scenes/resonance_stage.tscn` | 章节挂载点（工程是 Code-First，节点树在脚本里建） |

## 2. 设计与资产文档

| 路径 | 内容 |
| --- | --- |
| `docs/design/planets/planet-01-共振星.md` | 共振星设计主文档（规则、检查点、验收口径） |
| `docs/asset-list.md` | 11 件高细节资产清单（.blend / GLB / 预览图 / 接入状态） |
| `game/docs/resonance-gameplay-loop.md` | 单局流程 |
| `game/docs/resonance-asset-pipeline.md` | 资产管线（导出、命名、导入规则） |
| `game/docs/resonance-art-import.md` | 美术导入步骤 |
| `docs/design/resonance-01-codex-iteration-options.md` | Resonance 01 迭代方案（待讨论建议） |
| `docs/design/resonance-01-codex-reality-check.md` | Resonance 01 现实校验 |
| `docs/design/resonance-01-codex-test-plan.md` | Resonance 01 验证入口 |

## 3. 独立预览工程

已入库（可直接打开）：`game/previews/resonance_03_winch_prototype/`
—— 断裂轨道挂缆 / 绞盘收放 / 过冲与回摆 / 锁定座插销的单人原型，含 README、试玩说明、KNOWN-ISSUES、PERFORMANCE、HANDOFF。

**未入库（体积原因，只在本地）** 的 8 个预览工程，合计约 **878.9 MB（不含 `.godot` 缓存，实测）**：

| 预览工程 | 体积（不含缓存） | 文件数 | 内容 |
| --- | ---: | ---: | --- |
| `game/previews/resonance_02_quality_rework` | 243.3 MB | 370 | 第 2 幕质量返工 |
| `game/previews/resonance_02_moving_cart` | 214.7 MB | 202 | 运煤车 |
| `game/previews/resonance_coop_playtest_01_1` | 74.9 MB | 147 | 合作试玩 01.1 |
| `game/previews/resonance_coop_playtest_01` | 74.9 MB | 125 | 合作试玩 01 |
| `game/previews/resonance_cooperation_slice_01` | 74.8 MB | 87 | 合作切片 |
| `game/previews/resonance_station_interaction_01` | 74.8 MB | 65 | 矿站能源交互 |
| `game/previews/resonance_mining_station_01_1` | 74.2 MB | 45 | 矿站原型 01.1 |
| `game/previews/resonance_mining_station_01` | 47.3 MB | 20 | 矿站原型 01 |

（已入库的 `resonance_03_winch_prototype` 为 1.8 MB / 79 文件；9 个预览合计 880.7 MB。）

> 单文件最大 93.9 MB（`resonance_02_*/assets/moving_tunnel.scn`），未超 GitHub 100 MB 硬限制；
> 但整包 878 MB 会显著撑大仓库。需要入库时建议：**GitHub Release 附 zip**，或 Git LFS；不要直接 commit。

## 4. 共振星五幕合作候选线（不在本仓库）

`work/deepseek-resonance-r12-unified-candidate-r3-mp03/candidate/`（**另一个 Godot 工程**，`launcher.tscn` + `SessionHub` autoload + Jolt 物理）

- 生产文件 604，生产集合聚合 `b402c2111c53f77bcdb7f247faf8cf0f902929dd339cd435d8618b199a872c4b`（path-NUL 公式）
- 另有 `work/deepseek-resonance-r12-mp-identity-r1/candidate/`（604 文件，`218cdb26…`，1–4 人身份修复）
- 体积约 **321 MB**（不含 `.godot`），同样建议 Release/LFS，不要直接塞进 `game/`
- 结构：Act01 沉默的矿区 → Act23 断轨运煤车 → Act04 会记忆的晶体 → Act05 地心 → Finale
- 验收边界：2 人五幕全链路连续 3 轮通过（host 109/0、client 96/0）；**3–4 人在 Act23 断轨点下车进维修场阻塞，五幕未通过**

## 5. 怎么跑

```bash
# 主工程（含共振星：主舱航线图 → 共振星）
godot --path game

# 绞盘预览（已入库）
godot --path game/previews/resonance_03_winch_prototype

# 其余预览（本地存在时）
godot --path game/previews/resonance_02_moving_cart

# 五幕候选线（本地存在时，独立工程，不要与 game/ 混用）
godot --path work/deepseek-resonance-r12-unified-candidate-r3-mp03/candidate
```

## 6. 边界（别当成已验收）

- 本仓库**没有**共振星的整局通关验收记录；本轮也未运行 Godot。
- 8 个预览工程**未做真人试玩**；自动探针通过不等于玩法有趣。
- 五幕线的 2 人通过结论只适用于它自己的工程树，**不能**用来给 `game/` 背书。
