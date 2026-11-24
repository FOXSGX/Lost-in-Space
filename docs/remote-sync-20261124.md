# 2026-11-24 GitHub 同步记录

## 来源

- 仓库：`FOXSGX/Lost-in-Space`
- 远端 `main`：`b119d864`（`docs(gulu): note round-7 commit and push`，2026-11-23）
- 本地基线：`42519ff`（2026-10-26）
- 远端比本地基线多 36 个提交；本次新增内容集中在：
  - `game/act1/`：共振星第一幕完整工程
  - `game/act23/`：共振星第二、三幕完整工程
  - `docs/resonance/`：共振星上线前审计、修复记录、美术制作指南
  - `art-source/editable/nailong/`：Nailong 的 Blender 源文件
  - `game/scripts/`、`game/assets/`、`game/shaders/`：Act1/Act23 依赖的共享核心

## 同步方式

GitHub 的 `github.com:443` 与 `git fetch` 在当前网络下会被重置；`ghproxy.net` 镜像可以 `ls-remote`，但完整 pack 仍在末尾断流。最终采用：

1. GitHub API 读取远端 tree；
2. 通过 GitHub raw / jsDelivr / ghproxy 按文件下载；
3. 按路径清单逐文件校验大小；
4. 只复制远端新增路径，不覆盖本地腐墟星文件。

## 本地保护

- 腐墟星改动先提交为 `da51d62`，并建立备份分支：
  `backup/ruin-pre-github-sync`
- 远端新增内容中不包含 `game/scripts/ruin_*`、`game/tests/ruin_*`、医院/学校/超市/能源站/图书馆脚本；
  腐墟星文件保持不变。
- 仅对 `game/project.godot` 增加远端共振星所需的 `SessionHub` autoload，保留本地 Jolt、60 Hz、碰撞层和 LIS Physics 设置。

## 同步结果

- `game/act1/`：242 个文件
- `game/act23/`：303 个文件
- 共享核心/资源/文档：442 个文件
- `docs/resonance/`：新增 4 个文档（原有 `REFERENCE_INDEX.md` 不变）
- `art-source/editable/nailong/`：2 个 `.blend`
- 全部按远端 tree 校验，大小无缺失。

未导入：

- `game/previews/gulu_planet/`：Gulu 预览工程，独立于本次共振星主流程；
- `backups/` 下的历史快照；
- 仅用于远端测试的历史脚本。

## 验证

- `godot --headless --path game --import`：通过
- `res://act1/act01.tscn`：headless 启动通过
- `res://act23/act23_entry.tscn`：headless 启动通过
- 腐墟星完整测试套件：全部通过
- 腐墟星真实双进程联机：主机 11 / 客户端 7 通过
