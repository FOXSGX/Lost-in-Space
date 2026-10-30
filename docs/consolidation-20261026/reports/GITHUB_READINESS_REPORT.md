# GITHUB_READINESS_REPORT · 上传准备与最终判定

- 日期：2026-10-26
- 整理工作区：`work/deepseek-resonance-github-consolidation-r1/`
- 整理成果：`github-ready/`（本仓库）
- 执行：单窗口独立完成；**未运行 Godot、未合并候选、未 `git add/commit/push`、未改远端**

---

## 0. 最终判定

| # | 维度 | 判定 | 依据 |
| ---: | --- | --- | --- |
| 1 | `BASELINE_INTEGRITY` | **PASS** | 基线 = 正式工程 `game/`（377 文件，space `882f3fa9…`）；`project.godot` 在仓库根；与任务书三条硬规则逐条符合（`BASELINE_SELECTION.md` §2.1） |
| 2 | `SOURCE_TREE_COMPLETENESS` | **PASS（静态）** | 26 脚本 / 9 场景 / 12 着色器 / 159 资产 / 140 测试源码 / 79 `.import` / 101 `.uid` 全部在库；150 条 `res://` 引用核验，0 条 UID 孤儿 |
| 3 | `CLEANUP_COMPLETENESS` | **PASS** | 副本内**实际不存在** `.godot/`、`previews/`、`builds/`、`tools/`、`work/`、`*.exe/pck/zip`、`.blend`；排除 208,136 文件 / 74.14 GB |
| 4 | `DOCUMENTATION_COMPLETENESS` | **PASS** | 根 README + `.gitignore` + `GITHUB_UPLOAD_GUIDE.md` + `docs/` 8 份权威文档 + 6 份整理报告 + 证据 |
| 5 | `SECURITY_AUDIT` | **PASS** | 0 凭据/私钥/`.env`；24 个文件本机路径已脱敏；0 文件 >100 MB；1 文件 ≥10 MB |
| 6 | `ASSET_LICENSE_STATUS` | **REVIEW_REQUIRED** | `art-source/licenses/` 为空；`art-source/references/` 2 张图来源不明；AI 生成条款未记录 |
| 7 | `GITHUB_UPLOAD_READINESS` | **READY_FOR_PRIVATE / PUBLIC_BLOCKED** | 见 §7：私有可直接传；公开需先关闭 §6 的 3 项 |

## 总体结论

# `PUBLIC_UPLOAD_BLOCKED`

**含义（请勿误读）**：

- **仓库整理本身已经完成**，可以立刻作为**私有仓库**上传并继续开发；
- 阻塞的只是**公开发布**，原因是**授权证据缺失**（不是代码、不是安全、不是体积）；
- 关闭 §6 的 3 项后，本判定升级为 `GITHUB_STAGING_READY_WITH_WARNINGS`（警告为 P0 玩法阻塞与运行期未验证）。

不允许的表述：**“开源”**（仓库无 `LICENSE`）、**“已完成/可通关”**、**“Windows 版稳定”**。

---

## 1. 基线完整性

| 检查 | 结果 |
| --- | --- |
| `project.godot` 位于仓库根 | ✅（`evidence/reference_check.json` → `entry.exists=true`） |
| 主场景存在 | ✅ `res://scenes/main_3d.tscn` |
| `config/name` | `迷失太空 · Lost in Space` |
| `config/features` | `"4.7", "GL Compatibility"` |
| 与源工程逐字节 | ✅ 377 个产品文件 SHA-256 全一致（`evidence/FINAL_HASH_MANIFEST.json` vs `input_hash_manifest.json`） |
| 是否混入候选代码 | ❌ **0 个文件**来自 `work/` |

## 2. 源树完整性（静态）

| 检查 | 数量 | 结果 |
| --- | ---: | --- |
| `.gd` 脚本 | 26（+26 `.uid`） | 全部在库 |
| `.tscn` 场景 | 9 | 全部在库，均为 Code-First 挂载点 |
| `.gdshader` | 12 | 全部在库 |
| 运行时资产 | 159（39 GLB / 40 PNG / 79 `.import` / 1 JSON） | 全部在库 |
| 测试源码 | 71 `.gd`（+69 `.uid`） | 全部在库（**测试源码 ≠ 测试产物**） |
| `res://` 引用核验 | 150 | 149 命中；**1 条悬空（整理前既有）**：`assets/icons/shopping-cart.svg` |
| `.import` 源文件核验 | 79 | 78 命中；**1 个孤儿**：`test_master.glb.import`（源工程即如此） |
| `.uid` 孤儿 | 101 | **0** |
| 动态路径（含 `%s`） | 3 | 无法静态判定，已在 `KNOWN_ISSUES` 记录 |

> 两条异常都**不是整理引入**：源 `game/` 里同样不存在 `assets/icons/` 与 `test_master.glb`。
> 处置：保留字节、登记问题（`docs/KNOWN_ISSUES.md` A-10、A-11），不擅自删改元数据。

## 3. 清理完整性

| 目标物 | 副本内是否存在 | 核验 |
| --- | --- | --- |
| `.godot/` | ❌ | 文件枚举 |
| `game/previews/`（9 个独立工程） | ❌ | 文件枚举 |
| `builds/`（EXE/PCK/ZIP） | ❌ | 文件枚举 + 扩展名统计 |
| `tools/`（引擎/模板二进制） | ❌ | 文件枚举 |
| `work/`（候选/日志/证据） | ❌ | 文件枚举 |
| `*.blend` / `*.blend1` | ❌ | 文件枚举 |
| `*.log` / 崩溃转储 / `.env` | ❌ | 安全扫描 0 命中 |
| **总计排除** | **208,136 文件 / 74.14 GB** | `evidence/build_manifest.json` |

体积：约 74 GB → **210.8 MB（611 文件）**，降幅 **99.7%**。

## 4. 文档完整性

| 文档 | 状态 | 关键内容 |
| --- | --- | --- |
| `README.md` | ✅ 新写 | 玩法、引擎版本、打开方式、当前阶段、文档地图、**不宣称可通关** |
| `.gitignore` | ✅ 重写 | 忽略缓存/产物/凭据/`.blend`；**不忽略** `.import`/`.uid`/`tests/`/资产 |
| `GITHUB_UPLOAD_GUIDE.md` | ✅ 新写 | 两种上传方式、6 项上传前检查、禁传清单、未完成检查 |
| `docs/PROJECT_STATUS.md` | ✅ | 两条工程线边界 + 任务书 6.3 的 8 条状态（全部标 `HISTORICAL`） |
| `docs/ROADMAP.md` | ✅ | P0/P1/P2 + 所属线 + 完成判据 |
| `docs/KNOWN_ISSUES.md` | ✅ | 线 A 11 条 + 线 B 6 条 + 跨线 4 条，含"不是问题"清单 |
| `docs/TESTING.md` | ✅ | 71 探针分类、运行方式、多人验收做法、**本轮未跑** |
| `docs/ARCHITECTURE.md` | ✅ | Code-First 单场景、网络模型、输入四层、UI 层、资产组织 |
| `docs/ASSET_REGISTRY.md` | ✅ | 159 资产逐类登记 + 未入库原稿记录 |
| `docs/ASSET_LICENSE_AUDIT.md` | ✅ | 无许可证/无授权记录/2 张参考图风险/关闭路径 |
| `docs/DEVELOPMENT_HISTORY.md` | ✅ | 时间线 + 本次整理动作 + 接手须知 |

一致性检查：README 的目录表与仓库实际目录一致；文档间路径互相可达（`reports/reference_check` 之外
另做了 Markdown 链接目视核对）；`docs/PROJECT_STATUS.md` 是唯一权威入口，其他文档不与其矛盾。

## 5. 安全审计

| 项 | 结果 |
| --- | --- |
| 私钥 / AWS / GitHub / Slack / Google / OpenAI / JWT 令牌 | **0 命中** |
| `password` / `api_key` / `secret` 赋值 | **0 命中** |
| `.env` / `id_rsa` / `keystore` / `credentials.json` | **不存在** |
| 本机绝对路径 | 24 个文件已脱敏；扫描复核 **0 命中** |
| 文件大小 | 最大 12,090,772 B（`assets/ship-hub/ship_hub.glb`）；≥10 MB 仅 1 个；**>100 MB 0 个** |
| Git LFS | **当前不需要**（<100 MB/文件，总 210.8 MB） |
| 敏感文件残留 | 无 |

扫描器与原始结果：`tools/security_scan.py`、`evidence/security_scan.json`。

## 6. 资产授权（唯一阻塞项）

| 项 | 状态 | 关闭方式 |
| --- | --- | --- |
| 仓库无 `LICENSE` | 刻意（未获批准不加） | 若要开源：制作人选定许可证后添加 |
| `art-source/licenses/` 为空 | **REVIEW_REQUIRED** | 补授权记录，或确认“全部自制”并落一份声明 |
| `art-source/references/` 2 张外部图（约 2.3 MB） | **REVIEW_REQUIRED** | 确认来源与再分发许可；不确认则公开前移除 |
| AI 生成物条款未记录 | **REVIEW_REQUIRED** | 补 `AI_GENERATION_RECORD.md`（工具/条款快照） |
| 运行时含第三方字体/音频 | 无 | 无需处理 |
| 核心资产完整性 | 保留 | 未删除任何核心资产 |

详细见 `docs/ASSET_LICENSE_AUDIT.md`。

## 7. 上传准备度

| 场景 | 可行性 | 说明 |
| --- | --- | --- |
| 私有仓库 | ✅ 立即可传 | 授权问题在私有范围内不构成再分发 |
| 公开仓库 | ⚠️ 暂停 | 关闭 §6 三项后即可 |
| 声明“开源” | ❌ | 需先选许可证 |
| 作为参赛提交 | ⚠️ | 还需 P0 玩法阻塞关闭（§8），与仓库整理无关 |

上传步骤与禁传清单：`GITHUB_UPLOAD_GUIDE.md`。

## 8. 游戏可玩性 P0 阻塞（与仓库整理无关，但必须报告）

| # | 阻塞 | 所属线 | 状态 |
| ---: | --- | --- | --- |
| 1 | Act23 断轨点下车进维修场失败 → 3/4 人无法进入 Act04/05/Finale | 线 B | `OPEN` |
| 2 | Act04 客户端本地抓握 attachment 缺失；拒绝操作仍可能记账 | 线 B | `OPEN` |
| 3 | MP-04 中断残留 | 线 B | `BLOCKED` |
| 4 | Windows 窗口化 GPU/驱动挂起，根因未定（headless 通过不算） | 跨线 | `PENDING` |
| 5 | 导出包含 250 个 tests 条目，发布内容裁剪与门禁未做 | 线 B | `OPEN` |
| 6 | F8 材质/锚点/维修厅三项决策未裁定；层理 PENDING | 线 A | `BLOCKED` |
| 7 | 线 A 无整局通关验收；本轮未运行 Godot | 线 A | `PENDING` |
| 8 | 3–4 人完整五幕、弱网、恶意客户端、真人手感、长时内存 | 线 B | `PENDING` |

> **仓库整理通过 ≠ 游戏可玩性通过 ≠ Windows 正式发布通过。**

## 9. 需要制作人做的事（按顺序）

1. **决定仓库可见性**：先私有上传，或先关闭授权三项再公开。
2. **关闭授权三项**（§6）：`references/` 两张图、AI 条款记录、`licenses/` 声明。
3. **决定是否加许可证**（开源与否）；不加也能公开，但不能称“开源”。
4. **确认基线选择**：本报告按“正式工程 `game/`”整理（`BASELINE_SELECTION.md`）。
   若希望把共振星五幕候选线作为主线，请先做 `D-4` 决策并走 P1–P6 移植，**不要**整目录覆盖。
5. **跑一次真实导入**：`godot --headless --path . --import`，把 SCRIPT ERROR 归档（本轮未做）。
6. **按 `docs/ROADMAP.md` P0 推进玩法阻塞**，不要用仓库整理结果替代玩法验收。

## 10. 证据索引

| 文件 | 内容 |
| --- | --- |
| `evidence/FINAL_HASH_MANIFEST.json` | 611 个仓库文件逐文件 SHA-256 + 聚合（space / path-NUL 两个 aggregate 字段） |
| `evidence/input_hash_manifest.json` | 开工时 10 棵树的逐文件哈希基线 |
| `evidence/input_protection_final.json` | 收工复核：`INPUTS_UNCHANGED`，10/10 树 0 变化 |
| `evidence/build_manifest.json` | 每个复制文件的 src→dst + 每条排除规则实测统计 |
| `evidence/project_inventory.json` | 193 个 `project.godot`、目录体积、扩展名统计 |
| `evidence/reference_check.json` | 入口/引用/UID 静态核验 |
| `evidence/security_scan.json` | 凭据/路径/大文件扫描 |
| `reports/_generated/*.md` | 193 行工程表、123 行工作区表、同哈希副本分组 |

## 11. 本轮没做的事（再次声明）

- 没有运行 Godot / 没有启动游戏 / 没有跑联机 / 没有导出；
- 没有合并任何候选、没有修改原始工作区、没有删除原始证据；
- 没有 `git add` / `commit` / `push`，没有改远端可见性；
- 没有修复任何已知缺陷（包括 Section 8 的 8 条 P0）。
