# 2026-10-26 仓库整合与审计归档

本目录是 `PROJECT-GITHUB-CONSOLIDATION-R1` 的落库归档。**它只新增文档，不改动任何游戏代码、场景、资源或既有文档。**

## 1. 本次做了什么

1. 全项目盘点：**193 个 `project.godot`**、**123 个 `work/` 工作区**、约 **21 万文件 / 74 GB**。
2. 基线裁定：仓库里的正式工程是 **`game/`**（产品线）；共振星五幕候选线（R12-03 等 604 文件）是**另一个 Godot 工程**，不能整工程合并，保持未合入。
3. 合并进本仓库：**未覆盖任何既有文件**。本地 `HEAD`（`2f7ea3f`）是远端 `main`（`a3278b7`）的**祖先**，
   因此本地已提交内容 100% 被 GitHub 包含，`git merge --ff-only` 直接快进，**没有产生覆盖、没有回退**。
4. 本次唯一提交内容：本目录（审计归档）。游戏内容一行未改。

## 2. 关于“共振星以本地为准”

核对结果：**本地共振星文件全部是 GitHub 版本的旧版**（GitHub 在 `2f7ea3f` 之后对其做了 3 类改动）。
回退会变成纯回归，且本地没有任何 GitHub 缺失的共振星代码行，所以**没有回退**：

| 文件 | GitHub 侧改动 | 回退的后果 |
| --- | --- | --- |
| `game/scripts/resonance_stage.gd` | 交互提示文案统一 `F` → `E`（22 行） | 提示与实际交互键（E）不一致 |
| `game/scripts/resonance_cave_chapter.gd` | 生命值从 vitals 文本移除（1 行） | 与新的 `health_hud_3d.gd` 生命 HUD 重复显示 |
| `game/assets/resonance/models/*.import`（14 个） | 贴图改 `compress/mode=2` + `vram_texture=true` | 贴图回到未压缩，显存占用上升 |

> 如果确实需要本地旧版共振星文件，回退方式（**未执行**）：
> `git checkout 2f7ea3f -- game/scripts/resonance_stage.gd game/scripts/resonance_cave_chapter.gd game/assets/resonance`

## 3. 未合入的工作线（仍在 `work/`，只读保留）

| 线 | 代表候选 | 生产文件 | 本轮复算聚合（path-NUL） | 状态 |
| --- | --- | ---: | --- | --- |
| 共振星五幕 2 人 RC | `work/deepseek-resonance-r12-unified-candidate-r3-mp03/candidate/` | 604 | `b402c2111c53f77bcdb7f247faf8cf0f902929dd339cd435d8618b199a872c4b` | 2 人 ×3 轮通过；3–4 人 Act23 下车阻塞 |
| 共振星多人身份 | `work/deepseek-resonance-r12-mp-identity-r1/candidate/` | 604 | `218cdb26ca18ad4e47bb2f0c5b294b80ab2b66f82c7b186c6f6d3a749d71edbf` | 1–4 人身份 PASS；3–4 人五幕 PENDING |
| ACT01 多人 | `work/deepseek-resonance-act01-multiplayer-r1/candidate/project/` | 606 | space `2c87af37…` | 3/4 人全链路 BLOCKED |

两条线的 `project.godot` 无任何相同段落（`launcher.tscn` + `SessionHub` autoload + Jolt vs `main_3d.tscn` + 无 autoload + Godot Physics），
`game/` 里 599 / 604 个候选路径不存在。**整工程合并会同时破坏两套架构**；需要时按组件增量移植，不做目录复制。

## 4. 不该进仓库的东西（已在 `.gitignore` 之外的判断清单）

| 路径 | 体积 | 原因 |
| --- | ---: | --- |
| `work/`（123 个工作区） | ~66.7 GB | 候选、运行日志、证据；已由 `.gitignore` 的 `/work/` 忽略 |
| `builds/` | ~5.5 GB | 导出 EXE/PCK/ZIP；已被 `/builds/*` 忽略 |
| `tools/` | ~1.1 GB | Godot 编辑器/导出模板二进制；已被 `/tools/` 忽略 |
| `backups/` | ~262 MB | 历史工程备份（3 个 `project.godot`） |
| `game/previews/` | ~1.67 GB | 9 个**独立**预览工程（各自带 `project.godot`），非产品工程 |
| `art-source/editable/**/*.blend(+.blend1)` | ~590 MB | 可编辑原稿与自动备份；运行时只用 GLB，需版本化请用 Git LFS |
| `game/.godot/` | ~83 MB | 导入缓存，可重建 |

这些文件全部**保留在本地**，未删除、未移动。

## 5. 安全与授权现状（2026-10-26 实测）

- 敏感信息：扫描 **0 处** 凭据/私钥/`.env`；整理副本里 24 个文件的本机绝对路径已脱敏为 `<PROJECT_ROOT>`。
- 大文件：最大单文件 12.09 MB（`game/assets/ship-hub/ship_hub.glb`），**无 >100 MB 文件**，当前不需要 Git LFS。
- 第三方资产：`game/assets/ship-hub/kenney/` 与 `art-source/third-party/kenney/` 均带 `License.txt`，
  标注 **Creative Commons Zero (CC0)**（Kenney，www.kenney.nl）→ 可再分发，署名非强制但建议保留。
- AI 生成图（`art-source/ai-generated/`）：有原图与提示词，**未记录所用工具/条款** → 建议补一份生成记录。
- 仓库仍**没有** `LICENSE`：未获明确授权前不添加开源许可证，也不对外称“开源”。

## 6. 本轮**没有**做

- 没有运行 Godot（未 `--import`、未跑测试、未导出），所有运行期结论仍是 `PENDING`；
- 没有修改 `game/` 下任何源文件、场景、资源或既有文档；
- 没有合并任何候选工程，没有删除原始工作区文件。

## 7. 归档报告（`reports/`）

| 文件 | 内容 |
| --- | --- |
| `PROJECT_INVENTORY.md` | 193 个工程 / 123 个工作区 / Git 状态盘点 |
| `BASELINE_SELECTION.md` | 为什么基线是 `game/`，以及为什么不是 R12-03 |
| `CLEANUP_MANIFEST.md` | 保留/排除清单与体积账 |
| `EXCLUDED_FILES.md` | 逐目录排除明细与取回路径 |
| `SOURCE_PROVENANCE.md` | 来源追溯、路径迁移、脱敏记录、哈希复算 |
| `GITHUB_READINESS_REPORT.md` | 七维判定（基线/完整/清理/文档/安全/授权/上传） |

> 报告引用的 `evidence/*.json`（逐文件哈希清单、输入保护记录、扫描结果）未随仓库分发，保留在本地工作区
> `work/deepseek-resonance-github-consolidation-r1/evidence/`（该目录被 `/work/` 忽略）。

> **口径修正**：上述报告描述的是当时生成的**独立整理副本** `work/deepseek-resonance-github-consolidation-r1/github-ready/`
> （工程被提升到该副本根、共 611 个文件 / 210.8 MB）。最终落库方式改为“整合进本仓库”，
> 因此报告里凡出现“仓库根即工程根”“611 文件”“扁平化”的表述，**指的是那份副本，不是本仓库当前布局**。
> 本仓库当前布局仍是 `game/` 子目录。
