# CLEANUP_MANIFEST · 清理与保留清单

- 作用域：**仅 `work/deepseek-resonance-github-consolidation-r1/github-ready/`**（整理副本）
- 原始工作区：**零删除、零移动、零重写**（见 `evidence/input_protection_final.json`）
- 清理方式：构建时按白名单复制 + 黑名单排除；副本内不存在被排除的文件（**不是只写 .gitignore**）
- 数据来源：`evidence/build_manifest.json`（逐文件 copied 记录 + 每条排除规则的实测文件数/字节数）

---

## 1. 前后对比

| 指标 | 原项目根 | 整理副本 | 变化 |
| --- | ---: | ---: | --- |
| 文件数 | 约 207,365 | **611** | −206,754 |
| 体积 | 约 74 GB（77,397 MB） | **210.8 MB** | 约 −77.2 GB（−99.7%） |
| `project.godot` | 193 份 | **1 份**（仓库根） | 归一 |
| 独立工程目录 | 193 个 | 1 个 | 归一 |
| `.godot/` 缓存 | 215 文件 / 82.6 MB | 0 | 排除 |

> 副本实际由三部分构成：`game/` 产品文件（377）+ `docs/`（31）+ `art-source/` 轻量部分（156）
> + `submission/`（3）+ 根文件 + 本次新增文档/报告/证据。

## 2. 排除清单（实测）

| 类 | 路径 | 文件 | 体积 | 理由 | 核验依据 |
| --- | --- | ---: | ---: | --- | --- |
| `EXCLUDE_WORKSPACE` | `work/`（123 个工作区，含本任务工作区） | 193,056 | 66,695.4 MB | 候选/实验/审计工程与运行日志；任务书明确“候选工程不进入游戏仓库” | 逐个 `project.godot` 解析 + 血缘审计；本仓库 0 个文件来自 `work/` |
| `EXCLUDE_GENERATED` | `builds/` | 2,239 | 5,501.3 MB | 导出的 EXE/PCK/ZIP 试玩包（可再生产物） | 目录内 `.exe/.pck/.zip` 占比 >99% |
| `EXCLUDE_WORKSPACE` | `game/previews/` | 4,232 | 1,671.4 MB | 9 个**独立**预览工程（各自带 `project.godot`），非产品工程 | 每个子目录都有独立 `project.godot`；不在主场景/资源引用链中 |
| `EXCLUDE_GENERATED` | `tools/` | 7,237 | 1,089.8 MB | Godot 编辑器/控制台二进制、导出模板 | 文件名为 `Godot_v4*` / `*.tpz` / blender 便携版 |
| `REVIEW_REQUIRED` | `art-source/editable/`（`.blend` 54、`.blend1` 43、`.pyc` 3、与游戏重复的 `.glb` 4 等） | 105 | 610.3 MB | 可编辑原稿与自动备份；游戏运行只用 GLB；普通 Git 不适合 45 MB 级二进制 | 4 个 `.glb` 与 `assets/` 内同哈希；`.blend1` 为 Blender 自动备份 |
| `EXCLUDE_WORKSPACE` | `backups/` | 855 | 262.5 MB | 历史引擎备份 / 迁移基线工程 | 目录名与 `project.godot` 版本（1721 B / 5499 B / 5516 B） |
| `EXCLUDE_GENERATED` | `game/.godot/` | 215 | 82.6 MB | Godot 导入缓存（打开工程自动重建） | 含 `imported/`、`uid_cache.bin`、`global_script_class_cache.cfg` |
| `EXCLUDE_WORKSPACE` | `.agents/` | 190 | 2.6 MB | AI 助手 skill 参考包（Godot 手册），非游戏工程内容 | 文件均为 `SKILL.md` / `references/*.md` |
| `EXCLUDE_GENERATED` | `_r2_patchcheck_tmp/`、`_r2_patchcheck_tmp2/`、`$ws/` | 4 | 0.2 MB | 临时补丁核对目录（`$ws` 为空） | 目录名与内容（2 个 txt） |
| `EXCLUDE_DOCS` | `OPENCODE-CAPABILITY-REPORT.md` | 1 | 26 KB | 外部工具能力评估报告，与游戏工程无关 | 全文为首个标题 + 工具矩阵 |
| `EXCLUDE_GENERATED` | `R12_MP_IDENTITY_REPORT.md` | 1 | **0 B** | 0 字节空文件（疑似误创建） | 大小 0 |
| `REPLACED` | `.gitignore` | 1 | 432 B | 由整理副本重写（原规则全文保留在 `reports/SOURCE_PROVENANCE.md` §4） | 见 §4 |

合计排除 **208,136 个文件 / 74.14 GB**（含 `.git` 之外的全部冗余）。

## 3. 保留清单（有据可查）

### 3.1 游戏源与资产（必须保留，不可省）

| 内容 | 文件 | 体积 | 为什么保留 |
| --- | ---: | ---: | --- |
| `project.godot`、`export_presets.cfg` | 2 | 10.6 KB | 工程入口与导出预设 |
| `scripts/*.gd` + `.uid` | 52 | 0.9 MB | 26 个脚本 / 19,619 行；主控 5,447 行 |
| `scenes/*.tscn` | 9 | 1.8 KB | 9 个挂载点（Code-First，不能省） |
| `shaders/*.gdshader` | 12 | <1 MB | 运行时着色器 |
| `assets/**` | 159 | 145.8 MB | 39 GLB + 40 PNG + 79 `.import` + 1 JSON |
| `tests/*.gd` + `.uid` | 140 | 0.3 MB | 71 个自动探针（**测试源码 ≠ 测试产物**） |

### 3.2 文档与来源（长期维护必需）

| 内容 | 文件 | 说明 |
| --- | ---: | --- |
| `docs/`（设计/会议/规划/比赛/工作流/交接/归档） | 31 | 团队权威设计记录 |
| `docs/game/`（引擎实现说明 + 反馈系统） | 12 | 由 `game/docs/` 与游戏根 3 份文档迁入 |
| 新增权威文档 | 8 | `PROJECT_STATUS` / `ROADMAP` / `KNOWN_ISSUES` / `TESTING` / `ARCHITECTURE` / `ASSET_REGISTRY` / `ASSET_LICENSE_AUDIT` / `DEVELOPMENT_HISTORY` |
| `art-source/ai-generated/` | 13 | AI 原图与提示词（来源记录） |
| `art-source/generated/` | 1 | 共振星形体参考图 |
| `art-source/references/` | 2 | 风格参考（授权 `REVIEW_REQUIRED`） |
| `art-source/editable/` 轻量部分 | 156 | 预览 PNG、生成脚本 `.py`、说明 `.md`、部件 JSON |
| `art-source/licenses/` | 1（`.gitkeep`） | 授权记录目录（空，本身即证据） |
| `submission/` | 3 | 参赛说明 |

### 3.3 本次新增的 provenance

`reports/`（7 份）、`evidence/`（逐文件清单、输入保护、扫描结果）、根 `README.md` / `.gitignore` /
`GITHUB_UPLOAD_GUIDE.md`、各目录 `.gdignore`。

## 4. 副本内实际做的改动（非删除类）

| 动作 | 规模 | 说明 |
| --- | ---: | --- |
| 层级提升 | 全部 | `game/*` → 仓库根；`game/docs/*` → `docs/game/*`；3 份反馈系统文档 → `docs/game/` |
| Markdown 链接迁移 | 73 处 | 9 类字面替换（`../game/assets/`→`../assets/`、`game/scripts/`→`scripts/` 等），**只改链接目标，不改语义** |
| 本机路径脱敏 | 24 个文件 / 24 处 | 本机用户目录下的项目根绝对路径（正/反斜杠两种写法） → `<PROJECT_ROOT>`；**原值未写入任何报告** |
| `.gdignore` | 5 个目录 | `docs/`、`reports/`、`evidence/`、`art-source/`、`submission/` |
| 重写文件 | 4 | `README.md`、`.gitignore`、`GITHUB_UPLOAD_GUIDE.md`、`AGENTS.md`（仅“文件组织”段） |

## 5. 未确定项（`REVIEW_REQUIRED`）

| 项 | 为什么要保留 | 需要谁决定 |
| --- | --- | --- |
| `art-source/editable/**/*.blend`（仅原工作区） | 可编辑原稿，删了就无法复现资产 | 制作人：是否启用 Git LFS 后入库 |
| `art-source/references/` 2 张图 | 风格依据，但来源不明 | 制作人：确认来源或公开前移除 |
| `art-source/ai-generated/` | AI 生成记录，缺工具条款 | 制作人：补记工具与条款快照 |
| F8 `res2_*` 四件资产 | 未裁定就接入会造成“按岩石渲染”的错误 | 制作人：D-1/D-2/D-3 |

## 6. 自检（副本侧）

| 检查 | 结果 |
| --- | --- |
| 根目录存在 `project.godot` | ✅ |
| 副本内存在 `.godot/` | ❌（已排除） |
| 副本内存在 `*.exe` / `*.pck` / `*.zip` | ❌ |
| 副本内存在 `game/previews/` | ❌ |
| 副本内存在 `work/` 候选 | ❌ |
| `*.import` / `*.uid` 是否完整 | ✅ 79 个 `.import`、101 个 `.uid`（与源一致） |
| 可编辑 `.blend` | ❌（仅原工作区） |
| 单文件 >100 MB | ❌（最大 12.09 MB） |
