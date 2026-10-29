# HANDOFF — 奶龙星预览

> 多日任务续点。新会话先读本文件，再读 `STATUS.md` / `TESTING.md`。
> 每次推进后更新「当前状态 / 下一步 / 恢复命令」，不要只依赖聊天记录。

最后更新：2026-10-29 15:10（GMT+8）

## 快照

- 仓库：`C:\Users\31798\Documents\GitHub\Lost-in-Space-gulu`
- 分支：`feature/gulu-planet-preview`
- 最新提交：以 `git log -1 --oneline` 为准（本文件不绑定具体哈希）
- 预览目录：`game/previews/gulu_planet`
- 当前阶段：**阶段 A–F 一轮闭环完成**（可完整试玩的小关：3 罐燃料 → 装货 → 完成 → R 重开）
- 最新自测：`GULU SELFTEST SUMMARY passes=58 failures=0`（退出码 0）
- 截图：`docs/shots/01..09*.png`（9 张，1280×800）
- 未 push、未 merge

## 本轮完成的东西

- 视角：第一人称**逐值对齐飞船**（眼高 1.6 / FOV 74 / 俯仰 ±1.25 / 灵敏度 0.0020 /
  near 0.05 / 纵向符号一致）；玩家模型缩放改 1.0，与飞船与其他星球同一套资源。
- 玩法：拾取/放下/掉落/捡回、奶龙叼货（嘴部挂点）、找燃料、
  蓄势开始即锁定目标、直线扑击不追尾、扑空张嘴抛出燃料、
  装货口 AABB 容错判定、入仓只计一次、三罐完成、R 干净重开。
- 场地：40×30 m，3 罐燃料、2 条导引路线、5 处石堆、3 处货箱、船头装货口与停机坪。
- 美术：奶龙程序化模型重做（可动下颌、眉毛、腮红、翅、三段尾）；
  场景配色对齐飞船内部；地砖、远景岩层、船体侧鳍与尾部引擎。
- 声音：5 个本地合成短音（`tools/audio/make_sfx.py`），有最短播放间隔。
- 工具：`tools/inspect_shot.py`（截图亮度/色块体检）、`--shots` 自动截图 + `SHOTMETA` 日志。

## 关键文件

| 文件 | 作用 |
| --- | --- |
| `scripts/gulu_app.gd` | 关卡/场地/HUD/输入/自动化检查/截图脚本 |
| `scripts/milk_dragon.gd` | 状态机、找燃料、叼货、扑击锁定与释放、卡住恢复 |
| `scripts/milk_dragon_visual.gd` | 奶龙外观与表演（含 `MouthAnchor`） |
| `scripts/fuel_prop.gd` | 燃料罐四种模式：free/player/dragon/thrown(+loaded) |
| `scripts/collector.gd` | 飞船装货口、AABB 判定、指示灯、入仓动画 |
| `scripts/sfx.gd` | 音效播放与节流 |
| `scripts/station_player.gd` | 复用控制器；**第一人称镜头已改（D-15）** |
| `docs/shots/` | 本轮窗口截图 |

## 下一步（按优先级）

1. **真人试玩**：按 `TESTING.md` 第 4 节走一遍，回答四个问题。
2. **补「仓内无风险」漏洞**（STATUS 已知问题 1）：站在装货口里挑衅，
   奶龙被门槛挡住，等于免费送货。可选方案：
   - 仓内禁止挑衅（HUD 提示「先出来」）；或
   - 扑击锁定点必须落在仓口外（`_begin_windup` 时把目标投影到 x < 11.2）；或
   - 仓内挑衅时它不进蓄势，改为「护食」原地吼。
3. 根据反馈调 `milk_dragon.gd` 顶部参数（蓄势 1.0 s / 扑击 11 m/s / 抛出 7.2 m/s）。
4. 再决定是否投入正式奶龙模型（IP 授权未解决，见 `ASSETS.md`）。

## 已知问题

1. 仓内挑衅无风险（见上）。
2. 叼货转身 10.0 略快，远看像原地甩头。
3. 退出时 Godot 报 2 个 ObjectDB 泄漏 + 1 个资源未释放（不影响运行，未定位）。
4. 第三人称固定 15 m，只够看轮廓。

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
```

截图目录：
`C:\Users\31798\AppData\Roaming\Godot\app_userdata\Lost in Space - Nailong Planet Preview\gulu_shots`

## 不要做

- 不把第三方奶龙模型放进公开仓库或可发布构建。
- 不把「可下载」当成「有奶龙角色 IP 授权」。
- 不改其他星球、正式航线、公共系统。
- 不用 PowerShell 的 `Get-Content/Set-Content` 改带中文的脚本（会写坏编码）。
- 不 push/merge，除非用户明确要求。
- 不误提交工作区里预存的 `.gitignore`、`docs/design/...`、`game/docs/week1-member1.md` 修改。

## 更新规则

每次会话结束前至少写清：

- 完成：文件/提交/测试结果；
- 下一步：一个具体动作；
- 阻塞：需要用户决定的事项；
- 恢复：准确路径与命令。
