# PROJECT_INVENTORY · 全项目盘点

- 盘点时间：2026-10-26（Asia/Shanghai）
- 盘点根：`<PROJECT_ROOT>`（**已重新核实**，不是沿用历史路径假设：该目录含 `.git`、`README.md`、`AGENTS.md`、`game/`，Git 根与磁盘目录一致）
- 盘点方式：全树遍历 + 逐文件 SHA-256 + `project.godot` 逐份解析（`MEASURED`）
- 原始数据：`evidence/project_inventory.json`

---

## 1. 总量

| 项 | 数值 |
| --- | ---: |
| 全项目文件数（不含 `.git`） | 约 21 万 |
| 全项目体积 | **约 74 GB** |
| `project.godot` 数量 | **193** |
| `work/` 下工作区 | **123** |
| 工程家族（按 `config/name`） | **34** |

| 顶层目录 | 文件 | 体积 | 用途 | 本次处置 |
| --- | ---: | ---: | --- | --- |
| `game/` | 4,834 | 1,901.1 MB | **正式 Godot 工程**（含 `previews/` 9 个独立预览工程、`.godot/` 缓存） | 产品部分进入仓库 |
| `work/` | 191,704 | 66,464.2 MB | 全部候选、实验、审计、测试工作区 | 全部排除（只读保留） |
| `builds/` | 2,239 | 5,501.3 MB | 导出的 EXE/PCK/ZIP 试玩包 | 全部排除 |
| `tools/` | 7,237 | 1,089.8 MB | Godot 编辑器/控制台二进制、导出模板 | 全部排除 |
| `art-source/` | 262 | 670.8 MB | 美术参考、AI 原图、可编辑原稿、授权记录 | 轻量部分进入仓库 |
| `backups/` | 855 | 262.5 MB | 历史引擎备份、迁移基线工程 | 全部排除 |
| `.agents/` | 190 | 2.6 MB | Godot skill 参考包（AI 工具用） | 全部排除 |
| `docs/` | 31 | 0.2 MB | 设计、会议、规划、比赛、工作流文档 | 全部进入仓库 |
| `submission/` | 3 | <1 KB | 参赛说明 | 全部进入仓库 |
| 其它 | 6 | <1 KB | 根文件（README/AGENTS/.gitignore/.gitattributes/两份报告） | 部分重写/排除 |

## 2. 工程家族（34 个 `config/name`）

| config/name | 工程数 | 主要 main_scene | 判定 |
| --- | ---: | --- | --- |
| `迷失太空 · Resonance 04→05 双人纵切片` | **95** | `res://scenes/launcher.tscn` | **线 B**（共振星五幕候选线）；同一 `project.godot` 哈希 `d227a0cc…` 被复制 95 份 |
| `Lost in Space F8 Hero Polish` | 16 | `res://src/main.tscn` | F8 美术验证工程（`22834dc9…`） |
| `TestKit Self-Test Fixture` | 8 | `res://main.tscn` | 测试夹具（`84b435d2…`） |
| `Lost in Space - Resonance Maintenance Bay V2` | 7 | `res://src/main.tscn` | 美术验证分支 |
| **`迷失太空 · Lost in Space`** | **6** | `res://scenes/main_3d.tscn` | **线 A 产品工程**；`project.godot` 哈希 `7af5d603…`，其中 `game/` 一份、P1 资产落地副本一份、opencode 能力验证副本一份 |
| `Lost in Space - Resonance 02 Moving Cart` 等 | 6+4+4+3+3+3+3+3+3+2+2+2+2+2+1… | 各种 | 逐幕/逐原型工程，均为线 B 前身或美术验证 |
| `Act01 Standalone Backend E2E Host` / `Act01 Module Test Host` | 2 | `res://act1/act01.tscn` | Act01 独立后端/模块测试宿主 |
| `RC2P UserDir Probe` / `RC2P UserDir Probe 2` | 2 | `res://probe.tscn` | 导出器 `user://` 探测（临时工程，含 149–180 B 的 `project.godot`） |

完整 193 行清单见 `reports/_generated/godot_table.md`；家族汇总见 `reports/_generated/family_summary.md`；
同哈希副本分组见 `reports/_generated/duplicate_project_godot.md`。

## 3. 工作区（123 个）按用途分类

完整表（文件数/体积/最新修改/首标题）见 `reports/_generated/workspace_table.md`。按用途归并：

| 类别 | 代表工作区 | 数量级 | 说明 |
| --- | --- | ---: | --- |
| 五幕逐幕制作 | `deepseek-resonance-01-rebuild-v2`、`…-02-03-coop-party-v2`、`…-04-*`、`…-05-*` | ~20 | 线 B 的逐幕原型与质量返工 |
| 六线整合与验收 | `deepseek-resonance-r11-*`、`r12-unified-candidate-r1/r2/r3`、`layout-r2-*`、`performance-port-*`、`narrative-r1`、`coop-p0-hardening-r1` | ~25 | R11/R12 血缘链，含 604 文件候选与回滚工具 |
| 多人网络专项 | `mp-identity-r1`、`mp-remote-rescue-r1`、`mp04-*`、`multiplayer-stress-r1`、`act01-*network*`、`r12-mp-identity-r1`、`r12-mp03-physical-grip-latejoin-r1` | ~20 | 身份、救援、安全绳、断线、抓握 |
| 三/四人全链路 | `deepseek-resonance-act01-mp-fullchain-r1`、`act01-multiplayer-r1`、`act01-integrated-network-r1` | 5 | 3/4 人五幕验收（Act23 阻塞） |
| 发布与导出 | `rc2p-export-smoke-r1`、`rc2p-windows-export-template-recovery-r1`、`rc2p-windowed-stability-r1` | 3 | PCK/EXE 导出、启动冒烟、窗口化稳定性 |
| 美术（F1–F9/F8-R1–R7） | `art-lookdev-v1`、`art-materials-v3`、`art-v4-integrated`、`environment-art-v2`、`hero-rocks-v3`、`f8-r1…r7` | ~18 | 共振星维护湾/洞穴视觉；**落点是线 A 的 `scripts/resonance_cave_art.gd`** |
| 资产决策与落地 | `game-asset-landing-p1-r1`、`game-asset-contract-decision-r1`、`global-art-asset-research`、`art-library-01` | 4 | P1 资产落地（`project/` 是 `game/` 的逐字节副本，`project.godot` 哈希 `7af5d603…`）、D-1/D-2/D-3 决策材料 |
| 只读审计 | `game-integration-architecture-r1`、`integration-readiness-r1`、`storage-cleanup-r1`、`coop-experience-audit-r1`、`performance-audit-r1` | ~8 | 架构差异、血缘、磁盘清理、体验审计 |
| 早期探索期（线 A 前身） | `gameplay-iterations/`、`github-publish-20261013/`、`github-merge/`、`opencode-*`、`godot-skill-cache/`、`blender-*`、`audit-*` | ~15 | 2D/2.5D 时代与工具链缓存 |
| 临时/杂项 | `tmp/`、`_r2_patchcheck_tmp*`、`$ws`、`deepseek-resonance-github-consolidation-r1`（本任务） | 4 | 临时目录与本次工作区 |

## 4. Git 仓库状态（改动前快照）

`MEASURED`（2026-10-26 16:32）：

| 项 | 值 |
| --- | --- |
| 仓库根 | `<PROJECT_ROOT>`（与磁盘项目根一致） |
| 分支 | `main` |
| HEAD | `2f7ea3f4709e7ee73b3417930146ab06302940f5`（2026-10-20 23:56:26 +0800，`merge: 合并远程 main 更新与共振星整合`） |
| 远端 | `origin` = `https://github.com/FOXSGX/Lost-in-Space.git`（fetch/push） |
| 跟踪文件 | 847 |
| 已修改/已暂存 | **0** |
| 未跟踪条目 | **27**（`art-source/editable/resonance/codex_*`、`game/previews/*`、`docs/workflows/codex-*`、`backups/*` 等） |
| stash | 0 |
| `.gitignore` 关键规则 | `/work/`、`/builds/*`、`/tools/`、`**/.godot/`、`*.log`、`.env*` |

> 结论：**没有未提交的已跟踪文件修改**，但有 27 个未跟踪条目。本任务**没有** `git add/commit/push`，
> 也**没有**触碰 `.git`；收工复核见 `evidence/input_protection_final.json`。

## 5. 项目文档与证据分布

| 类型 | 位置 | 数量 |
| --- | --- | --- |
| 团队设计/会议/规划/比赛 | `docs/` | 31 份 |
| 引擎实现说明 | `game/docs/` | 9 份 |
| 引擎根反馈系统文档 | `game/feedback*.md` | 3 份 |
| 资产清单 | `docs/asset-list.md` | 1 份 |
| 授权记录 | `art-source/licenses/` | **0 份（仅 `.gitkeep`）** |
| 候选验收/哈希/回滚 | `work/*/FINAL_REPORT.md`、`FINAL_HASH_MANIFEST.json`、`ROLLBACK.md` 等 | 数十份 |
| 导出与稳定性证据 | `work/deepseek-resonance-rc2p-*/` | 3 个工作区 |
| 磁盘清理记录 | `work/deepseek-resonance-storage-cleanup-r1/` | 1 个工作区（77 文件 / 88.1 MB） |

## 6. 与任务书已知候选的对应（A–F）

| 代号 | 任务书路径 | 实测路径 | 状态 |
| --- | --- | --- | --- |
| A · R12-03 双人整合 | `work/deepseek-resonance-r12-unified-candidate-r3-mp03/candidate/` | 一致 | 604 文件，`b402c211…`（本轮复算一致） |
| B · R12-MP-IDENTITY | `work/deepseek-resonance-r12-mp-identity-r1/candidate/` | 一致（另有同族 `…-mp-identity-r1` 为上游 MP-IDENTITY-R1） | 604 文件，`218cdb26…`（本轮复算一致） |
| C · ACT01 三/四人全链路 | `work/deepseek-resonance-act01-mp-fullchain-r1/` | 一致 | 结论 `BLOCKED at Act23Chapter` |
| D · Windows 窗口化稳定性 | `work/deepseek-resonance-rc2p-windowed-stability-r1/` | 一致 | `ROOT_CAUSE_UNRESOLVED / PENDING` |
| E · Windows 导出模板恢复 | `work/deepseek-resonance-rc2p-windows-export-template-recovery-r1/` | 一致 | `EXPORT_AND_SMOKE_PASS`，包内含 250 个 tests 条目 |
| F · 美术与资产 | `work/deepseek-resonance-f8-r5-final-art-selection/`、`f8-r6`、`f8-r7`、`game-asset-contract-decision-r1`、`game-asset-landing-p1-r1` | 一致 | R5 定稿但 6 项 PENDING；D-1/D-2/D-3 未裁定 |

补充发现（任务书未列、但影响判断）：

1. `deepseek-resonance-r12-mp03-physical-grip-latejoin-r1`（10-26 16:17，**最新**）是对 `218cdb26` 候选的
   物理抓握/晚加入**审计与回归**，无最终报告，**不是新候选**。
2. `deepseek-resonance-integration-readiness-r1`（10-26 02:20）已完成一次全项目血缘审计，
   本盘点的哈希与它一致（`b402c211…`、`218cdb26…`、ACT01 `2c87af37…`），互为交叉验证。
3. `backups/resonance-01-05-integrated-20261023_Act23Bootable/` 是线 B 的一个 1721 B `project.godot`
   快照（`d227a0cc…`），属历史备份，不是新产品。
