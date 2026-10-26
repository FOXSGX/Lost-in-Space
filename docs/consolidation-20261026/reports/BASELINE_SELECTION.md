# BASELINE_SELECTION · 仓库基线裁定

- 裁定时间：2026-10-26
- 裁定对象：本任务要整理进 `github-ready/` 的那一份代码
- 裁定结论：**基线 = 正式工程 `game/`（线 A，产品工程）**，整理时提升为仓库根
- 裁定方式：逐文件 SHA-256 复算 + 路径集合比对 + 静态架构比对 + 任务书规则逐条套用
- **本轮未运行 Godot**，因此“更完整”只用**文件与源码事实**判定，不用运行结果判定

---

## 0. 一句话

`game/` 是仓库里唯一被 Git 跟踪、被设计文档/美术/参赛材料指向的正式工程；共振星五幕候选线
（R12-03 / R12-MP-IDENTITY）证据链最完整，但它是**另一个 Godot 工程**（604 个生产文件里 599 个
在本仓库没有路径），按任务书“不得把未合并候选拼进主工程”和“候选工程不进入游戏仓库”的规则，
**不能**作为本仓库的代码基线，只能作为未合并工作线登记。

## 1. 候选清单（本轮实测）

| 代号 | 路径 | 生产文件 | 本轮复算哈希 | 结论（历史，未复跑） |
| --- | --- | ---: | --- | --- |
| **基线** | `game/`（原样，另含 `previews/` 与 `.godot/`） | 377（产品口径） | `space = 882f3fa9…`（377 文件） | 产品工程；无整局通关验收 |
| A | `work/deepseek-resonance-r12-unified-candidate-r3-mp03/candidate/` | 604 | `path-NUL = b402c2111c53f77bcdb7f247faf8cf0f902929dd339cd435d8618b199a872c4b` ✅ 与任务书一致 | 2 人五幕 ×3 PASS；3–4 人 FAIL/BLOCKED |
| B | `work/deepseek-resonance-r12-mp-identity-r1/candidate/` | 604 | `path-NUL = 218cdb26ca18ad4e47bb2f0c5b294b80ab2b66f82c7b186c6f6d3a749d71edbf` ✅ 一致 | 1–4 人身份/晚加入 PASS；3–4 人五幕 PENDING |
| C | `work/deepseek-resonance-act01-multiplayer-r1/candidate/project/`（供 ACT01-全链路验证） | 606 | `space = 2c87af37…` ✅ 与血缘审计一致 | 3/4 人 Act23 下车 BLOCKED |
| D | `work/deepseek-resonance-rc2p-windowed-stability-r1/` | 报告型 | — | 窗口化 4/4 挂起，根因 PENDING |
| E | `work/deepseek-resonance-rc2p-windows-export-template-recovery-r1/` | 报告型 | — | 导出+冒烟 PASS，含 250 个 tests 条目 |
| F | `work/deepseek-resonance-f8-r5-final-art-selection/candidate/p_r5` 等 | 212（美术工程） | — | 6 项 PENDING；目标 `res2_*` 不在任一游戏工程内 |

### 1.1 聚合哈希不能跨口径比较（重要）

`work/` 里至少出现过三种互不兼容的聚合公式：

| 公式 | 定义 | 使用者 |
| --- | --- | --- |
| `space` | `sha256(concat(f"{sha} {size} {rel}\n"))` | R12-U1、LAYOUT-R2 审计、本轮统一口径 |
| `path-NUL` | `sha256(concat(f"{rel}\0{sha}\n"))` | R12-02、R12-03、R12-MP-IDENTITY |
| `tab` | `sha256(concat(f"{sha}\t{size}\t{rel}\n"))` | R12-01 |

例如 R12-03：`path-NUL = b402c211…`，`space = e06a9f75…`。**两个数都“对”，但不能互相比较。**
本轮全部数字都写明了公式；跨报告只以逐文件 SHA-256 为准。

## 2. 为什么基线是 `game/`（线 A）

### 2.1 规则套用（任务书 3.3）

| 规则 | 套用结果 |
| --- | --- |
| ①“正式 `game/` 是默认权威源” | 满足：`game/` 是 Git 跟踪的引擎工程（`.gitignore` 里只有 `game/.godot/` 被忽略；`git ls-files` 847 条） |
| ②“更完整的集成候选可作为基线，但须解释” | **前提不成立**：线 B 不是 `game/` 的“更完整版本”，而是另一套工程。604 个生产文件里 **599 个**在 `game/` 无对应路径，`project.godot` 无任何相同段落 |
| ③“不得仅因更新时间晚就认为更可靠” | 线 B 的最新候选时间更晚（10-26），但这不构成基线理由 |
| ④“不得比较不同文件集合/不同聚合算法的哈希” | 已按 §1.1 处理：只比同集合逐文件哈希 |
| ⑤“不得将未合并候选悄悄拼进主工程” | 线 B 的任何文件都**没有**进入本仓库；只在文档里登记为未合并工作 |
| ⑥“不得把局部通过写成整体通过” | `docs/PROJECT_STATUS.md` 为每条 PASS 标注了线归属与适用边界 |

### 2.2 事实证据

| 维度 | `game/`（线 A） | 线 B 候选 |
| --- | --- | --- |
| Git 跟踪 | 是 | 否（`/work/` 被 `.gitignore` 忽略） |
| README / AGENTS / 设计总纲指向 | 全部指向 `game/` | 无任何设计文档 |
| 美术来源 | `art-source/` 逐资产有 `.blend`/脚本/预览 | 27 MB 生成资产，无来源记录 |
| 参赛材料 | `submission/`、`builds/`（历史） | 无 |
| 2026-10-26 的最新开发落点 | **是**：P1 资产落地工作区 `project/` 是 `game/` 的逐字节副本（`project.godot` 同哈希 `7af5d603…`）；F8-R7 改的是 `game/scripts/resonance_cave_art.gd` | 网络/导出/稳定性工作落点 |
| `project.godot` | `Lost in Space` + `main_3d.tscn`，无 autoload，Godot Physics | `Resonance 04→05` + `launcher.tscn`，`SessionHub` autoload，Jolt |
| 生产文件数 | 377 | 604 |
| 体量 | 145.2 MB 源码+资产 | 412.8 MB（含 91.9 MB `.godot` 缓存） |

### 2.3 架构结论（只读审计，`HISTORICAL` 转引 + `STATIC` 复核）

`GAME-INTEGRATION-ARCH-R1` 的结论与本轮静态复核一致：两线**逐项冲突**——

| 维度 | `game/` | 线 B | 后果 |
| --- | --- | --- | --- |
| 场景生命周期 | 零 `change_scene_to_file`，单场景状态机 | 19 次切场景 | 整工程替换会丢 100+ 状态字段 |
| 会话载体 | 代码 `new()` 的子节点 `ShipSession` | `SessionHub` autoload | 两个 peer 抢 `multiplayer.multiplayer_peer`（S1） |
| RPC 拓扑 | 46 个 `@rpc` 分散 6 文件按节点路径路由 | 72 个集中单点 | 换根 = 重写全部调用点 |
| 控制器 | 第三人称 + 生存层 | 第一人称 + 手部 | 语义不等价 |
| 物理 | Godot Physics | Jolt | 调参全部失效 |
| 资源契约 | `RES_*` 锚点 + 前缀材质族 | 无锚点 + 精确查表 | 资产互不兼容 |

因此即使选择线 B 作为“主线”，也**不是复制目录**能完成的，需要按组件移植（P1–P6）。

## 3. 被保留为“未合并工作”的候选（不进仓库）

| 线 | 代表候选 | 为什么保留 |
| --- | --- | --- |
| 线 B 2 人 RC | R12-03（`b402c211…`） | 六线 + MP-03 的 2 人范围最强候选；回滚基线 |
| 线 B 多人身份 | R12-MP-IDENTITY（`218cdb26…`） | 1–4 人身份修复；3–4 人五幕的前置 |
| 线 B 稳定回退 | R12-02（`04933b6c…` space） | 不带 MP-03 的回退 |
| ACT01 网络栈 | `act01-multiplayer-r1`（`2c87af37…`） | 独立网络栈，不能整文件套用 |
| MP-04 | `mp04-cancel-cleanup-r1` / `mp04-begin-ack-r1` | 未收口（`SNAPSHOT_UNSTABLE`） |
| 美术候选 | F8-R5 `p_r5`、R6、R7 | 资产候选，未接入产品工程；D-1/D-2/D-3 未裁定 |

以上全部仍在原工作区，**逐字节未动**（见 `evidence/input_protection_final.json`）。

## 4. 本基线的已知不足（必须一起看）

1. **没有整局通关验收**：线 A 没有一份“主舱→星球→撤离”的连续运行记录。
2. **本轮未运行 Godot**：脚本解析、资源导入、联机、导出全部 `PENDING`。
3. **线 A 也没有 4 人验收**：代码支持 4 人（`MAX_PLAYERS=4`、46 个 RPC），但无验收证据。
4. **美术三项决策未裁定**（D-1/D-2/D-3），F8 资产因此未落入本仓库。
5. **发布门禁未完成**：`export_presets.cfg` 的输出路径在仓库外；线 A 从未做过导出冒烟。

## 5. 如果制作人决定“线 B 成为主线”，应怎么做

**不要**整目录覆盖。按 `GAME-INTEGRATION-ARCH-R1` 的路线做增量（每阶段单独可发布/可回滚）：

| 阶段 | 动作 | 改动量 | 产出 |
| --- | --- | --- | --- |
| P0 | 冻结：给 `game/` 全量逐文件哈希 + 6 个核心文件哈希 | 0 行 | 门禁脚本 |
| P1 | 四件 F8 GLB + `.import` 落到 `assets/resonance/models/f8_r5/` | +8 文件，0 改 | 资产可导入 |
| P2 | 材质/锚点契约（依赖 D-1、D-2 决策） | 0–1 函数 | 正确材质 |
| P3 | 一个可走的维修厅（`main_3d.gd` +~110 行、`planet_registry.gd` +1 条） | +3 文件 | 玩家可见 |
| P4 | 快照分包旁路（`snapshot_wire.gd` + `snapshot_assembler.gd`，零类型依赖） | +2 文件 | 可选 |
| P5 | 会话模型对照实验（只在工程副本里） | 0 落码 | 决策依据 D-5 |
| P6 | 发布门禁与回滚演练 | 门禁脚本 | 可发布判定 |

**明确禁止**（会引入 S1）：引入 `change_scene_to_file` 换幕、把 `SessionHub` 设为 autoload、
把 `launcher.tscn` 设为主场景、整文件覆盖 `project.godot`、切换物理引擎、整目录复制候选。

## 6. 裁定的可推翻条件

如果出现以下任一情况，本裁定的前提变化，应重新裁定：

1. 制作人明确“线 B 就是参赛作品”，并接受 P1–P6 的移植工程量（`D-4` 决策）；
2. `game/` 被证明不可用（例如首次导入即大量 SCRIPT ERROR 且无法修复）而线 B 可运行；
3. 项目决定放弃“主舱+星球探索”玩法，改为线性五幕合作战役。

在此之前，**本仓库以 `game/` 为基线**是唯一同时满足“可追溯、可回滚、不覆盖未验收候选”的选择。
