# 奶龙星对标改造总览（2026-11-25）

> 这一天把「射门试玩」推到了「可以拿去上架页」的状态：P0 表现、P1 进程、P2 展示，加上玩法提案 A/B/C。
> 本文是**变更索引**，细节在 `STATUS.md`（逐轮记录）、`docs/BENCHMARK_2026_11_25.md`（对标与优先级）、
> `docs/美术制作与AI协作指南.md`（美术规范 v2.0）。

## 1. 一句话总结

改造前：四处常驻文字、装货口是个同心圆靶、踢球只有一声闷响、没有音乐、没有手柄、没有难度/挑战/练习。
改造后：**三行 HUD + 有纵深的装货口 + 顿帧/镜头/拖尾/音高四通道打击反馈 + 40 s BGM + 手柄全流程 +
三档难度 + 10 条挑战 + 记录板 + 三个练习关 + 三层订单 + 必杀槽/超载射门 + 偷球与抢回**。

## 2. P0 · 表现层（让它像一个商品）

| 项 | 做法 | 主要文件 |
|---|---|---|
| 打击反馈 | 踢球 55 ms 顿帧、镜头抖动随力度、球速 >6 m/s 拖尾、力度分档音高；扑救 90 ms 顿帧 + 尘土 + 奶龙挤压 | `gulu_app.gd` `energy_ball.gd` `station_player.gd` `milk_dragon_model.gd` |
| HUD 减法 | 删左上说明板与右上调试字；长句压成「被拦！连击断」这类 2–4 字 | `gulu_app.gd` |
| 装货口 | 去同心圆靶 → 口沿倒角 + 琥珀内唇 + 四面漏斗壁 + 舱底发光栅 + 吸力粒子 + 舱内补光 | `collector.gd` |
| 奶龙表演 | 4 套待机循环（看球 / 张望 / 跺脚 / 伸懒腰）、撞击挤压、失球晃身 | `milk_dragon_model.gd` |
| 音频 | 40 s 无缝 BGM（程序化生成，零第三方素材），静音联动 | `tools/audio/make_bgm.py` `sfx.gd` |
| 手柄 | 左摇杆移动 / 右摇杆视角 / RT 蓄力 / Start 暂停 / A 确认 / X 抢球；暂停仍可读 Start | `gulu_app.gd` `station_player.gd` `pad_pump.gd` |
| 结算目标 | 进球 ≥3 / 连击 ≥x4 / 订单命中 ≥2，结算页打勾 | `gulu_presentation.gd` |

## 3. 玩法结构（把「对准」变成「决策」，并能通关）

- **通关结构**：一局 3 关（2 球 → 3 球+高台 1 球 → 3 球+订单 1 次+超载 1 次），全过即通关；
  关卡模式进球不加时，超时重试本关。第 2 关的球只在高台/坑底重生，逼玩家用上整张地图。

- **提案 A · 装货订单**：舱口分下/中/上三层，每 30 秒换单，命中 ×2；口沿三条灯带只亮当前层。
- **必杀槽 + 超载射门**：3 脚满蓄充满，下一脚 ×1.9 冲量 + 0.4 s 慢放。
- **提案 C · 风险射门**：满蓄被扑 → 奶龙加速 5 秒，逼玩家混用轻推与抽射。
- **提案 B · 偷球**：拦截后 35% 叼走 4 秒，玩家 2.5 m 内按 E 抢回（**+1 必杀槽**）；每局 2 次、冷却 8 s。
- **进程**：三档难度（只缩放奶龙速度/反应）、分档最高分、10 条挑战、记录板、三个 60 秒练习关。

## 4. 展示层

- **时段预设**：正午 / 黄昏 / 夜班，只换天空/环境光/雾/五层灯光（`gulu_app.gd::apply_time_of_day`）。
- **记录板**：标题屏 `L`，三档最高分（▶ 当前）+ 挑战清单 + 当前时段。

## 5. 验证矩阵（17 组，229 项）

```powershell
$godot = "C:\Users\31798\Downloads\迷失太空\迷失太空\tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe"
$preview = "C:\Users\31798\Documents\GitHub\Lost-in-Space-gulu\game\previews\gulu_planet"
foreach ($t in '--selftest','--arcade-test','--flow-test','--dragon-test','--pause-test','--wind-test',
        '--fx-test','--order-test','--pad-test','--result-test','--audio-test','--super-test',
        '--progress-test','--practice-test','--steal-test','--tod-test','--records-test') {
  & $godot --headless --path $preview -- $t
}
```

| 组 | 项数 | 覆盖 |
|---|---|---|
| selftest | 46 | 控制器/首屏/物理/进球/重置/奶龙模型/音效 |
| arcade | 21 | 计分、连击、加时、重生、难度、结算、蓄力 |
| flow / pause / wind | 5 / 25 / 7 | 标题与倒计时、暂停与统计、侧风 |
| fx | 11 | 抖动衰减、尘土自释放、顿帧还原、挤压回弹 |
| order / super / steal | 12 / 14 / 13 | 订单换单与 ×2、必杀槽与超载、偷球与抢回 |
| progress / practice / result | 10 / 12 / 8 | 挑战、难度分档、存档、练习关、结算目标 |
| audio / tod / records | 7 / 9 / 7 | BGM 循环与静音、时段光照、记录板 |

## 6. 截图与视频索引（改前 / 改后）

- **演示视频**：`docs/record/gulu_demo_2026-11-25.mp4`（23.8 s，1280×800，H.264 + AAC；标题 → 正午进球 → 黄昏超载 → 夜班 → 结算 → 记录板）
- 装货口：`docs/shots_art_2026_11_25/C_interaction.png`（同心圆靶）→ `docs/shots_p0_2026_11_25/C_interaction.png`（舱口 + 订单灯带）
- 首屏 HUD：`docs/shots_art_2026_11_25/A_wide.png`（四处文字）→ `docs/shots_p0_2026_11_25/A_wide.png`（三行 HUD + 新机位）
- 结算：`docs/ui_review/22_result.png`（含本局目标与挑战）
- 练习 / 偷球 / 黄昏 / 夜班 / 记录板：`docs/ui_review/24_practice.png`、`25_carry.png`、`26_dusk.png`、`27_night.png`、`28_records.png`

## 7. 已知遗留

1. **第二个场地变体**未做（同规则换构图），属于 P2 可选项。
2. **BGM 是占位级**：结构简单、可循环、版权干净，但没有记忆点；换正式曲子只需替换同名 wav。
3. `A_wide` 构图已从「巨岩挡死」改成可用机位，但场地本身的岩体分布没有改——若要更开阔的远景，需要挪场景。
4. 未做真人试玩：手感和难度曲线仍需要外部玩家验证（`TESTING.md` 第 4 节有试玩脚本）。

## 8. 提交建议

这些改动目前**全部未提交**。建议拆成两个 commit：

```text
feat(gulu): P0 表现层 —— 打击反馈 / HUD 减法 / 装货口 / 奶龙表演 / BGM / 手柄 / 结算目标
feat(gulu): P1+P2 与玩法 A/B/C —— 订单分层 / 必杀槽 / 风险射门 / 偷球 / 难度档 / 挑战 / 练习关 / 时段 / 记录板
chore(gulu): 对标文档与回归脚本（BENCHMARK / STATUS / HANDOFF / TESTING / CHANGELOG / 截图）
```
