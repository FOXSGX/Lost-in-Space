# SOURCE_PROVENANCE · 来源追溯

- 生成时间：2026-10-26
- 目的：证明 `github-ready/` 里每个文件都能追溯到项目内的原始路径，且原始路径未被修改。
- 机器可读版：`evidence/build_manifest.json`（逐文件 src→dst）、`evidence/FINAL_HASH_MANIFEST.json`
  （仓库侧逐文件 SHA-256）、`evidence/input_protection_final.json`（输入前后一致）

---

## 1. 基线来源

| 项 | 值 |
| --- | --- |
| 原始项目根 | `<PROJECT_ROOT>` |
| 仓库基线 | 正式工程 `game/`（提升为仓库根） |
| 基线产品口径 | 377 个文件 / 145.2 MB（排除 `game/.godot/` 215 文件与 `game/previews/` 4,232 文件） |
| 基线聚合（space，377 文件） | `882f3fa96003d45f92f85a40fed499d6d0d102d322e1fafa120e79e4596a40c4` |
| 基线 `project.godot` SHA-256 | `7AF5D603645FCA32C8F55EF82DD22FC607703BE400227CC4CAA11978AC686593` |
| 主场景 | `res://scenes/main_3d.tscn`（174 B 单节点桩） |
| 裁定依据 | `reports/BASELINE_SELECTION.md` |

## 2. 逐目录来源

| 仓库路径 | 原始路径 | 复制方式 | 文件数 |
| --- | --- | --- | ---: |
| `project.godot`、`export_presets.cfg` | `game/同名文件` | 逐字节 | 2 |
| `assets/` | `game/assets/` | 逐字节（含 `.import`） | 159 |
| `scenes/` | `game/scenes/` | 逐字节 | 9 |
| `scripts/` | `game/scripts/` | 逐字节（含 `.uid`） | 52 |
| `shaders/` | `game/shaders/` | 逐字节 | 12 |
| `tests/` | `game/tests/` | 逐字节（含 `.uid`） | 140 |
| `docs/game/` | `game/docs/` + `game/反馈系统*.md` | 逐字节（链接重写） | 12 |
| `docs/`（其余） | `docs/` | 逐字节（链接重写） | 31 |
| `art-source/ai-generated/`、`generated/`、`references/`、`licenses/` | 同名路径 | 逐字节 | 17 |
| `art-source/editable/`（轻量部分） | `art-source/editable/` | 选择性（PNG/MD/PY/JSON） | 156 |
| `submission/` | `submission/` | 逐字节 | 3 |
| `AGENTS.md` | 根 `AGENTS.md` | 复制后改「文件组织」段 | 1 |
| `.gitattributes` | 根 `.gitattributes` | 逐字节 | 1 |
| `README.md`、`.gitignore`、`GITHUB_UPLOAD_GUIDE.md`、`docs/*.md`（8 份） | — | **本轮新写** | 11 |
| `reports/`、`evidence/` | — | **本轮新写** | 见 §5 |

合计：579 个文件由原始工作区复制（含路径重写后的内容），其余为本轮新写文档与证据。

## 3. 路径迁移表（机械替换，仅 Markdown）

整理把 `game/` 提升为仓库根，所有指向工程的 Markdown 链接必须改。共 **73 处**：

| 原字面 | 替换为 | 次数 |
| --- | --- | ---: |
| `../../game/docs/` | `../game/` | 2 |
| `../game/docs/` | `game/` | 1 |
| `../../game/assets/` | `../../assets/` | 7 |
| `../game/assets/` | `../assets/` | 13 |
| `game/project.godot` | `project.godot` | 2 |
| `game/scripts/` | `scripts/` | 30 |
| `game/assets/` | `assets/` | 17 |
| `game/docs/` | `docs/game/` | 3 |

只改**链接目标与路径字面**，不改任何句子语义、不改代码逻辑。
替换顺序按“最长匹配优先”，避免 `../game/assets/` 先被 `game/assets/` 吃掉。
未做替换的语义性提及（例如说明文字里的“game/ 目录”）保留原样，见 `reports/CLEANUP_MANIFEST.md` §4。

## 4. 原始 `.gitignore`（被替换，原文留档）

```gitignore
# Local credentials
.env
.env.*
!.env.example

# OS temporary files
Thumbs.db
Desktop.ini
.DS_Store
*.tmp
*.bak

# Exported playable packages (keep the directory placeholder)
/builds/*
!/builds/.gitkeep

# Add engine-specific cache rules after choosing the engine.

# Godot 4 editor/import cache
**/.godot/


# 本地迭代产物与引擎缓存
/work/
/game/.godot/
*.log

# 本地引擎/工具二进制（不进仓库）
/tools/
```

替换原因：旧规则基于“`game/` 子目录 + 保留 `builds/` 占位”的布局；新布局下工程在根，
`/builds/` 占位已无意义，且需要新增 `art-source/editable/**/*.blend`、导出产物、凭据类文件的规则。
新规则见仓库根 `.gitignore`（**保留了对 `.import`/`.uid`/`tests/` 的入库要求**）。

## 5. 安全脱敏记录

| 项 | 值 |
| --- | --- |
| 命中模式 | 本机绝对路径（用户目录下的 Desktop\项目根，含正/反斜杠两种写法） |
| 影响文件 | **24 个** |
| 替换 | 完整项目根 → `<PROJECT_ROOT>`（24 处）；`<USER_HOME>` 规则 0 命中 |
| 分布 | `tests/*.gd`（19）、`art-source/editable/**/*.py`（3）、`art-source/editable/**/README.md`（1）、`docs/handoff/霜烬星开发交接文档.md`（1） |
| 是否输出原值 | **否**。本报告与所有报告均未写入被替换的原字符串 |
| 原始文件 | 未改（仅副本被改）；逐文件哈希见 `evidence/input_protection_final.json` |
| 副作用 | 19 个 capture 工装脚本需重新填入本机路径才能运行（见 `docs/KNOWN_ISSUES.md` A-3） |

## 6. 输入核验结果（本轮实测）

### 6.1 任务书给出的历史哈希 vs 本轮复算

| 候选 | 生产文件 | 公式 | 任务书/历史值 | 本轮复算 | 结论 |
| --- | ---: | --- | --- | --- | --- |
| R12-03 | 604 | path-NUL | `b402c2111c53f77bcdb7f247faf8cf0f902929dd339cd435d8618b199a872c4b` | **同值** | ✅ 一致 |
| R12-MP-IDENTITY | 604 | path-NUL | `218cdb26ca18ad4e47bb2f0c5b294b80ab2b66f82c7b186c6f6d3a749d71edbf` | **同值** | ✅ 一致 |
| ACT01-MP 候选 | 606 | space | `2c87af37…`（血缘审计） | `2c87af37aacadb43855c06b6cba4fc36609f3a70ca50dcd86e673c0df43be59d` | ✅ 一致 |
| R12-03（space 口径） | 604 | space | `e06a9f75…`（审计） | `e06a9f75d4b6cbf7c9a7a6689ca75fda4482c910084cb35fa179156ad8e7fc63` | ✅ 一致 |

> 说明：**不是**直接抄报告数字，而是按生产文件定义（排除 `tests/ evidence/ logs/ tools/ baseline/
> diff/ probe/ harness/ reports/ tests-out/`、`.godot/`、`*.uid`）重新遍历并逐文件哈希后聚合。

### 6.2 保护范围与结果

| 树 | 文件 | 开工聚合（space） | 收工 | 判定 |
| --- | ---: | --- | --- | --- |
| `game/`（全树，含 previews/.godot） | 4,834 | 见 `input_hash_manifest.json` | 见 `input_protection_final.json` | 逐文件一致 |
| `game/` 产品口径 | 377 | `882f3fa9…` | 同 | 一致 |
| `docs/` | 31 | — | 同 | 一致 |
| `art-source/` | 262 | — | 同 | 一致 |
| `submission/` | 3 | — | 同 | 一致 |
| 根文件（README/AGENTS/.gitignore/.gitattributes/2 报告） | 6 | — | 同 | 一致 |
| R12-03 候选（全树 + 生产集） | 1,628 / 604 | — | 同 | 一致 |
| R12-MP-IDENTITY 候选 | 1,637 / 604 | — | 同 | 一致 |
| ACT01-MP 候选 | 1,614 / 606 | — | 同 | 一致 |
| 引用报告（16 份） | 16 | — | 同 | 一致 |

最终判定见 `evidence/input_protection_final.json` 的 `verdict` 字段。

## 7. Git 状态

| 项 | 开工 | 收工 |
| --- | --- | --- |
| HEAD | `2f7ea3f4709e7ee73b3417930146ab06302940f5` | 未变 |
| 分支 | `main` | 未变 |
| 远端 | `origin https://github.com/FOXSGX/Lost-in-Space.git` | 未变 |
| 已跟踪文件修改 | 0 | 0 |
| 未跟踪条目 | 27 | 27（本任务工作区在 `work/` 下，被 `/work/` 忽略） |
| 本任务是否 `git add/commit/push` | 否 | 否 |
