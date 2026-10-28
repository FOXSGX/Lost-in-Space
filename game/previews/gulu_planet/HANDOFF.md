# HANDOFF — 奶龙星预览

> 多日任务续点。新会话先读本文件，再读 `STATUS.md` / `TESTING.md`。
> 每次推进后更新“当前状态 / 下一步 / 恢复命令”，不要只依赖聊天记录。

最后更新：2026-10-29 00:16（GMT+8）

## 快照

- 仓库：`C:\Users\31798\Documents\GitHub\Lost-in-Space-gulu`
- 分支：`feature/gulu-planet-preview`
- 最新提交：以 `git log -1 --oneline` 为准（本文件不绑定具体哈希）
- 预览目录：`game/previews/gulu_planet`
- 当前阶段：占位角色 + 行为完成；**等待用户选择建模方案 A/B/C**
- 最新自测：`GULU SELFTEST SUMMARY passes=38 failures=0`
- 未 push、未 merge。

## 当前状态

- 第一人称逐字复用 `game/previews/resonance_coop_playtest_01_1/scripts/station_player.gd`，未改控制器。
- 奶龙行为：待机 → 注意 → 靠近 → 蓄势 → 扑击 → 恢复；Q 挑衅、R 重置、F3 调试。
- Blender 4.5.15 LTS；测试 GLB 为 4 mesh、Body 0.8 m、脚底 Godot y=0；
  测试方块默认隐藏，`F4` 显示。
- 坐标规范：Blender 源文件 Z-up；Godot Y-up、角色面朝 −Z、脚底 y=0。
- 官方没有公开 3D 下载；第三方 `scnuLwz/ai_work_proflie` 的 `nailong.glb` 已下载到
  `C:\Users\31798\Documents\NailongAssets\scnuLwz_ai_work_proflie\` 并检查：
  846,783 顶点、无 armature/action、3 张 4K PBR、约 1.09 m 高、无 LICENSE。
  **只做内部参考，不入库、不发布、不替换角色。**

## 待决定

- **A（推荐）**：先做低模 blockout + 骨架 + 六段临时动作，默认仍显示占位，调试开关切换；
  正式模型到了再替换 mesh。
- **B**：等官方/明确授权模型或最终美术设定，再一次性做正式模型。
- **C**：继续纯程序化占位，不做建模。

用户未明确选择前，不启动 A 的建模工作。

## 若选 A：下一步

1. `tools/blender/make_nailong_blockout.py`：
   - 3k–8k 三角面；暂按 1.8 m 身高；Blender Z-up、脚底 z=0、前向 +Y；
   - 骨架命名稳定：`root`、`hips`、`spine`、`head`、`arm.L/R`、`leg.L/R`、`tail`；
   - 六段动作：`idle`、`alert`、`approach`、`windup`、`pounce`、`recover`。
2. 导出 `assets/test/nailong_blockout.glb`，用 `inspect_glb.py` 回读。
3. Godot 侧加调试开关/独立测试场景；默认仍用现有占位，不替换正式角色。
4. headless 自测；更新 `TESTING.md`、`STATUS.md`、本文件；提交，不 push。

## 恢复命令

```powershell
cd "C:\Users\31798\Documents\GitHub\Lost-in-Space-gulu"
git status --short
git log --oneline -5

$godot = "C:\Users\31798\Downloads\迷失太空\迷失太空\tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe"
& $godot --headless --path "game\previews\gulu_planet" -- --selftest
```

## 不要做

- 不把第三方模型放进公开仓库或可发布构建。
- 不把“可下载”当作“有奶龙角色 IP 授权”。
- 不改其他星球、正式航线、公共系统、第一人称控制器。
- 不 push/merge，除非用户明确要求。
- 不误提交工作区预存在的 `.gitignore`、`docs/design/...`、`game/docs/week1-member1.md` 修改。

## 更新规则

每次会话结束前至少写清：

- 完成：文件/提交/测试结果；
- 下一步：一个具体动作；
- 阻塞：需要用户决定的事项；
- 恢复：准确路径与命令。
