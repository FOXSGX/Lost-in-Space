# EXCLUDED_FILES · 排除记录（逐目录 / 逐文件）

> **作用域声明**：本节所有“排除”只表示**没有复制进 `github-ready/`**。
> **原始工作区内的文件一个都没有删除**，路径与哈希保持原样（`evidence/input_protection_final.json`）。
> 需要任何一项时，按 §5 的路径直接从原工作区取回即可。

数据来源：`evidence/build_manifest.json` 的 `exclusions` 段（实测文件数与字节数）。

---

## 1. 目录级

### 1.1 `work/` —— 123 个工作区（193,056 文件 / 66,695.4 MB）

全部排除。按体积前 15（完整表见 `reports/_generated/workspace_table.md`）：

| 工作区 | 文件 | MB | 用途 |
| --- | ---: | ---: | --- |
| `deepseek-resonance-02-rock-rebuild` | 3,059 | 3,148.0 | 共振星岩石重建（美术实验） |
| `deepseek-resonance-rc2p-windows-export-template-recovery-r1` | 1,811 | 3,189.2 | 导出模板恢复（含 1.28 GB 模板包副本） |
| `deepseek-resonance-rc2p-export-smoke-r1` | 3,824 | 2,699.0 | 导出冒烟（含 EXE/PCK 产物） |
| `deepseek-resonance-act01-network-stable-v1` | 7,392 | 2,259.6 | Act01 网络稳定化 |
| `deepseek-resonance-02-art-polish` | 1,930 | 1,995.2 | 第 2 幕美术 |
| `deepseek-resonance-game-asset-landing-p1-r1` | 4,939 | 1,954.6 | P1 资产落地（`project/` 是 `game/` 副本） |
| `deepseek-resonance-02-03-coop-party-v2` | 13,605 | 1,902.3 | 2+3 幕合作派对 |
| `deepseek-performance-port-r2` | 4,144 | 1,301.8 | 性能移植 |
| `deepseek-resonance-mp04-begin-ack-r1` | 5,369 | 1,227.5 | MP-04 分支 |
| `deepseek-resonance-mp04-cancel-cleanup-r1` | 5,431 | 1,227.4 | MP-04 分支 |
| `deepseek-resonance-mp-remote-rescue-r1` | 5,110 | 1,225.1 | MP-03 救援 |
| `deepseek-resonance-layout-r2-r11-02-credit-r1` | 3,402 | 1,009.9 | R12-01 两线整合 |
| `deepseek-performance-port-r11-r1` | 3,594 | 1,000.3 | PERF-R4 |
| `deepseek-resonance-layout-r2-integration` | 3,368 | 990.4 | LAYOUT-R2 |
| `deepseek-resonance-act01-multiplayer-r1` | 4,191 | 872.7 | ACT01 多人候选 |

理由：这些是**候选 / 实验 / 审计工作区**，不是产品工程；其中 95 个共用同一个
`project.godot`（哈希 `d227a0cc…`），属同一工程的重复副本。
核验：任务书 5.1“不应进入游戏仓库的独立 `work/` 候选工程”；本仓库 0 个文件来自 `work/`。

### 1.2 `game/previews/` —— 9 个独立预览工程（4,232 文件 / 1,671.4 MB）

| 预览工程 | 文件 | MB | 说明 |
| --- | ---: | ---: | --- |
| `resonance_02_quality_rework` | 1,808 | 489.8 | 第 2 幕质量返工预览 |
| `resonance_02_moving_cart` | 1,520 | 442.9 | 运煤车预览 |
| `resonance_station_interaction_01` | 121 | 162.1 | 矿站交互原型 |
| `resonance_coop_playtest_01_1` | 223 | 127.5 | 合作试玩 01.1 |
| `resonance_coop_playtest_01` | 187 | 125.0 | 合作试玩 01 |
| `resonance_cooperation_slice_01` | 140 | 124.9 | 合作切片 |
| `resonance_mining_station_01_1` | 69 | 124.2 | 矿站原型 01.1 |
| `resonance_mining_station_01` | 37 | 72.6 | 矿站原型 01 |
| `resonance_03_winch_prototype` | 126 | 2.5 | 绞盘原型（**有独立 README/KNOWN-ISSUES**，体积小但仍非产品工程） |

理由：每个子目录都有**自己的 `project.godot`**（`afedccf6…`、`27ba7828…`、`fbcb838c…`、
`468b2828…`、`525fdc5c…`、`3b877e04…`、`2a24df02…` 等），是独立可打开工程；
产品主场景/资源引用链中**不包含**它们。
核验：`project.godot` 枚举 + 主工程 `preload`/`load` 路径扫描（无引用）。

### 1.3 `builds/` —— 导出产物（2,239 文件 / 5,501.3 MB）

| 目录 | 文件 | MB |
| --- | ---: | ---: |
| `Resonance_02_03_Playability_Fix` | 780 | 533.6 |
| `Resonance_02_03_FirstPerson_Spike` | 728 | 517.7 |
| `Resonance_02_03_Integrated` | 500 | 484.0 |
| `Resonance_02_Quality_Rework` | 4 | 380.8 |
| `Resonance_02_Rock_Rebuild_Test` | 2 | 375.5 |
| `Resonance_02_Moving_Cart_Playtest` | 5 | 362.5 |
| `Resonance_02_Art_Polish_20261021` | 16 | 306.8 |
| `Resonance_02_Rock_Rebuild_20261021` | 23 | 295.1 |
| `Resonance_Coop_Playtest_01/_1/_Windows` | 15 | 668.1 |
| `Resonance_05_*` | 30 | 358.5 |
| `Resonance_03_Winch_v0.1_20261020` | 21 | 177.8 |
| `Lookdev_v1_20261023`、`_r6b1_applytest`、`*.zip` | 96 | 30.1+ |

理由：`EXE/PCK/ZIP` 构建产物，可由源码重新导出；任务书 5.1 明列。
核验：扩展名统计（`.exe/.pck/.zip` 占绝大多数）。

### 1.4 `tools/`、`backups/`、`.agents/`、临时目录

| 路径 | 文件 | MB | 理由 |
| --- | ---: | ---: | --- |
| `tools/` | 7,237 | 1,089.8 | Godot 编辑器/控制台二进制、导出模板、Blender 便携版 |
| `backups/` | 855 | 262.5 | 历史引擎备份、迁移基线工程（3 个 `project.godot`） |
| `.agents/` | 190 | 2.6 | Godot skill 参考包（AI 工具用） |
| `_r2_patchcheck_tmp` / `_r2_patchcheck_tmp2` / `$ws` | 4 | 0.2 | 临时补丁核对目录、空目录 |

## 2. 文件级

| 文件 | 字节 | 处置 | 理由 |
| --- | ---: | --- | --- |
| `OPENCODE-CAPABILITY-REPORT.md` | 26,036 | 排除 | 外部工具能力评估，与游戏工程无关 |
| `R12_MP_IDENTITY_REPORT.md` | **0** | 排除 | 0 字节空文件（疑似误创建），无内容可保留 |
| `.gitignore` | 432 | 替换 | 原规则不支持新布局；原文完整保留在 `reports/SOURCE_PROVENANCE.md` §4 |

### 2.1 `art-source/editable/` 的排除细分（105 文件 / 610.3 MB）

| 类型 | 文件 | MB | 理由 |
| --- | ---: | ---: | --- |
| `.blend` | 54 | 353.8 | 可编辑原稿，游戏运行只用 GLB；45 MB 级二进制不适合普通 Git |
| `.blend1` | 43 | 237.5 | Blender **自动备份**（与 `.blend` 内容重复） |
| 与游戏内重复的 `.glb` | 4 | 18.9 | 其中 `ship_hub.glb`、`resonance_cave_entrance_hero_v4.glb`、`resonance_cave_vertical_slice_v3.glb` 与 `assets/` 内**同哈希**；`archive/v0.1.2/ship_hub.glb` 为旧版本 |
| `.pyc` | 3 | <1 | Python 字节码（生成物） |

保留的同目录内容：预览 PNG（55 个 / 38.1 MB）、生成脚本 `.py`（70 个 / 0.7 MB）、说明 `.md`（11 个）、
部件 `.json`（2 个）。

## 3. 保留但**不在**仓库（仅原工作区可访问）

| 内容 | 为什么没入库 | 恢复方式 |
| --- | --- | --- |
| `art-source/editable/**/*.blend` | 体积 + LFS | 原路径直接打开 |
| `game/previews/**` | 独立工程 | 原路径直接打开 |
| `builds/**` | 构建产物 | 用 `export_presets.cfg` 重新导出 |
| `work/**`（含全部候选、日志、回滚工具） | 候选与证据 | 原路径只读使用 |
| `tools/**` | 引擎二进制 | 自行下载 Godot 4.7.2 |

## 4. 核验方法（可复现）

1. 枚举全树 `project.godot`（193 份）→ 解析 `config/name`、`run/main_scene`；
2. 逐文件 SHA-256 建基线（`evidence/input_hash_manifest.json`）；
3. 白名单复制 → `evidence/build_manifest.json` 记录每个 copied 文件（src→dst、大小、哈希）；
4. 对每条排除规则重新遍历原目录，统计 `files/bytes`（本文件数字即由此得来）；
5. 副本侧自检：无 `.godot/`、无 `*.exe/*.pck/*.zip`、无 `previews/`、无 `work/`；
6. 收工复算全部输入树 → `evidence/input_protection_final.json`（`INPUTS_UNCHANGED`）。

## 5. 取回单个被排除文件的路径对照

| 想取回 | 原工作区路径 |
| --- | --- |
| 五幕 2 人 RC | `work/deepseek-resonance-r12-unified-candidate-r3-mp03/candidate/` |
| 五幕 4 人身份候选 | `work/deepseek-resonance-r12-mp-identity-r1/candidate/` |
| ACT01 多人候选 | `work/deepseek-resonance-act01-multiplayer-r1/candidate/project/` |
| Blender 原稿 | `art-source/editable/<资产名>/` |
| 预览工程 | `game/previews/<name>/` |
| 导出包 | `builds/<name>/` |
| 引擎二进制 | `tools/` |

> 再次强调：以上路径**全部未被本任务修改**。
