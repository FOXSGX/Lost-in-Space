# HANDOFF — 奶龙星预览

> 多日任务续点。新会话先读本文件，再读 `STATUS.md` / `TESTING.md`。
> 每次推进后更新「当前状态 / 下一步 / 恢复命令」，不要只依赖聊天记录。

最后更新：2026-10-29 23:35（GMT+8）

## 快照

- 仓库：`C:\Users\31798\Documents\GitHub\Lost-in-Space-gulu`
- 分支：`feature/gulu-planet-preview`
- 最新提交：以 `git log -1 --oneline` 为准（本文件不绑定具体哈希）
- 预览目录：`game/previews/gulu_planet`
- 当前阶段：**第二轮打磨完成**——第一次游玩能自己看懂、机械重复与等待已压掉
- 最新自测：`GULU SELFTEST SUMMARY passes=66 failures=0`（退出码 0）
- 截图：`docs/shots/01..08*.png`（8 张，1280×800，本轮重拍）
- 未 push、未 merge

## 这一轮做了什么

1. **开场三分构图**：出生点同时看到教学罐、奶龙、装货口；教学罐在奶龙注意范围外，
   先学会拾取和送货。
2. **去掉机械循环**：上头增量按情境（叼货 0.50 → 两次就扑），冷却 0.65；
   蓄势前先确认在扑击射程内（≈4.2 m），不再“够不到也扑”。
3. **锁定可视化**：蓄势瞬间地面红圈（`PounceLockMarker`），圈=要扑的地方。
4. **舱口不是掩体**：站在 x>11.2 挑衅被拒绝。
5. **安全搬运有代价**：奶龙看见你抱货会凑近，贴太近 0.75 s 抢走（有预警、冷却 4 s、不掉血）。
6. **接货容错**：盒扩到 x 12.45–15.90 / z ±2.40，进入舱口范围有横向引导。
7. **多人接口**：`setup_actors` + 最近目标选择；燃料/交付带 `credit_peer`。
8. **美术**：ProceduralSky 替换被雾染白的天空；修正三处竖着的地面环；
   手持燃料不再挡视野；奶龙视线会跟着你手里的罐子。

## 关键文件

| 文件 | 作用 |
| --- | --- |
| `scripts/gulu_app.gd` | 关卡/场地/HUD/输入/标记/自检/截图 |
| `scripts/milk_dragon.gd` | 状态机、找燃料、抢货、射程判定、锁定、释放 |
| `scripts/milk_dragon_visual.gd` | 奶龙外观与表演（`MouthAnchor`、`set_look_point`、`set_snatch`） |
| `scripts/fuel_prop.gd` | free/player/dragon/thrown/loaded 五态 + 归属字段 |
| `scripts/collector.gd` | 装货口、AABB 判定、指示灯、`last_credit_peer` |
| `scripts/sfx.gd` | 5 个本地合成音效 + 节流 |
| `scripts/station_player.gd` | 复用控制器（第一人称仍与飞船逐值一致，D-15） |
| `tools/inspect_shot.py` | 亮度/色块体检 |
| `tools/shot_map.py` | 截图类别图（K/D/F/S/G），看不见图时判断构图 |
| `docs/shots/` | 本轮窗口截图 |

## 下一步（按优先级）

1. **真人试玩**（`TESTING.md` 第 4 节，5 分钟）：重点判断“抢货是不是太凶”。
   - 太凶 → `snatch_delay` 0.75→1.1，或 `snatch_distance` 2.1→1.7。
   - 太温柔 → 让它在 6 m 内小跑（approach_speed ×1.3）。
2. 借力送货的站位窗口约 3.6 m（x 7.6–11.2），想更有变化可让“空嘴时也会被燃料吸引”，
   形成双向博弈；但要小心别把教学罐也变成争抢目标。
3. 第三人称只够看轮廓；要做正式角色展示再调相机。
4. 正式奶龙模型/IP 授权仍未解决（见 `ASSETS.md`）。

## 已知问题

1. 抢货强度只在数值上验证过，没体验过。
2. 借力送货几乎总是“舱口前 4 m → 侧移”，变化少。
3. 奶龙脸是球体拼的，<2 m 能看出接缝。
4. 退出时 Godot 报 2 个 ObjectDB 泄漏 + 1 个资源未释放（不影响运行）。

## 恢复命令

```powershell
cd "C:\Users\31798\Documents\GitHub\Lost-in-Space-gulu"
git status --short
git log --oneline -5

$godot = "C:\Users\31798\Downloads\迷失太空\迷失太空\tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe"
$preview = "C:\Users\31798\Documents\GitHub\Lost-in-Space-gulu\game\previews\gulu_planet"

& $godot --headless --path $preview -- --selftest
& $godot --path $preview                 # 试玩
& $godot --path $preview -- --shots      # 截图到 user://gulu_shots

# 截图体检（看不见图片时用）
python tools\inspect_shot.py "<png>"
python tools\shot_map.py "<png>"
```

截图目录：
`C:\Users\31798\AppData\Roaming\Godot\app_userdata\Lost in Space - Nailong Planet Preview\gulu_shots`

## 不要做

- 不把第三方奶龙模型放进公开仓库或可发布构建；不把「可下载」当成「有 IP 授权」。
- 不改其他星球、正式航线、公共系统。
- 不 push/merge，除非用户明确要求。
- 不误提交工作区里预存的 `.gitignore`、`docs/design/...`、`game/docs/week1-member1.md` 修改。
- 不用 `Get-Content`/`Set-Content` 在**未显式指定 UTF8** 的情况下往返改脚本（会写坏中文）；
  中文脚本优先用编辑器工具改。

## 更新规则

每次会话结束前至少写清：

- 完成：文件/提交/测试结果；
- 下一步：一个具体动作；
- 阻塞：需要用户决定的事项；
- 恢复：准确路径与命令。
