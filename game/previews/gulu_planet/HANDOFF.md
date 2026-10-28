# HANDOFF — 奶龙星预览

> 多日任务续点。新会话先读本文件，再读 `STATUS.md` / `TESTING.md`。
> 每次推进后更新“当前状态 / 下一步 / 恢复命令”，不要只依赖聊天记录。

最后更新：2026-10-29 01:25（GMT+8）

## 快照

- 仓库：`C:\Users\31798\Documents\GitHub\Lost-in-Space-gulu`
- 分支：`feature/gulu-planet-preview`
- 最新提交：以 `git log -1 --oneline` 为准（本文件不绑定具体哈希）
- 预览目录：`game/previews/gulu_planet`
- 当前阶段：**玩法骨架优先**；占位角色行为与 E 搬运/被扑掉落已完成；角色骨骼/正式模型暂缓
- 最新自测：`GULU SELFTEST SUMMARY passes=48 failures=0`
- 未 push、未 merge。

## 当前状态

- 第一人称逐字复用 `game/previews/resonance_coop_playtest_01_1/scripts/station_player.gd`，未改控制器。
- 奶龙行为：待机 → 注意 → 靠近 → 蓄势 → 扑击 → 恢复；Q 挑衅、E 拾取/放下燃料、R 重置、F3 调试。
- 燃料携带时跟随玩家、临时关闭碰撞；被扑中掉落，形成“捡回来”窗口。
- 扑击提前结束现在只响应墙/玩家等非地面碰撞，地板接触不再被误判为撞墙。
- Blender 4.5.15 LTS；测试 GLB 为 4 mesh、Body 0.8 m、脚底 Godot y=0；
  测试方块默认隐藏，`F4` 显示。
- 坐标规范：Blender 源文件 Z-up；Godot Y-up、角色面朝 −Z、脚底 y=0。
- 官方没有公开 3D 下载；第三方 `scnuLwz/ai_work_proflie` 的 `nailong.glb` 已下载到
  `C:\Users\31798\Documents\NailongAssets\scnuLwz_ai_work_proflie\` 并检查：
  846,783 顶点、无 armature/action、3 张 4K PBR、约 1.09 m 高、无 LICENSE。
  **只做内部参考，不入库、不发布、不替换角色。**

## 下一步（当前优先级）

1. 真人试玩完整闭环：挑衅 → 引开 → E 搬运 → 被扑掉落 → 捡回。
2. 根据试玩调 `milk_dragon.gd` 顶部参数、搬运距离和 HUD 提示。
3. 再决定是否给角色加“最小表演骨骼”（头/下颌/手脚/尾巴）；不启动完整高模、复杂面部或软体模拟。
4. 若加角色骨骼：外观与碰撞分离；扑击位移仍由行为控制；先做“转头看人、蓄势、扑空抬头”的可视化闭环。

## 角色骨骼（后续，非当前）

- 只做少量骨骼：身体、头、下颌、手脚、尾巴；不做手指/复杂面部。
- 复用当前行为与碰撞体；不重复建设玩法。
- 若没有可用角色网格，不单独制作脱离模型的完整骨架；先继续占位玩法验证。
- 第三方模型只做参考，不入库、不发布。

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
