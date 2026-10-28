# TESTING — 奶龙星第一人称试玩预览

最后更新：2026-10-28 20:25（GMT+8）

## 0. 启动

```powershell
$godot = "C:\Users\31798\Downloads\迷失太空\迷失太空\tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe"
$preview = "C:\Users\31798\Documents\GitHub\Lost-in-Space-gulu\game\previews\gulu_planet"

# 正常试玩（会打开窗口，由使用者主动运行）
& $godot --path $preview

# 自动验证（无窗口；本轮按“不要强制打开”使用这一方式）
& $godot --headless --path $preview -- --selftest
```

入口：`gulu_planet.tscn`。默认第一人称，鼠标捕获。

## 1. 本轮实际结果

```
GULU SELFTEST SUMMARY passes=38 failures=0
```

（headless，2026-10-28；鼠标观察/俯仰因 headless 无真实鼠标捕获而跳过。\n\n新增 Blender GLB 检查后共 34 项，全部通过（4 个 mesh、0.8 m 主体、+Y→−Z、+Z→+Y、材质）。）

| 项目 | 实测 |
| --- | --- |
| 默认第一人称 | 通过 |
| 眼睛高度 / FOV | 1.65 m / 62° |
| 奶龙、燃料首屏可见 | 通过（屏幕坐标 406,333 / 794,339） |
| WASD 前进 0.9 s | 5.22 m |
| 内墙碰撞 | 停在 x=11.32 |
| Tab 第一/第三人称 | 双向通过；第一人称隐藏身体 |
| 待机 → Q 挑衅 → 注意 | 通过；agitation 0.34 |
| 注意 → 靠近 | 通过；距离 6.18 → 4.36 |
| 第 3 次挑衅 → 蓄势 | 通过；agitation 0.98 |
| 蓄势预兆 | 通过；1.0 s 内保持蓄势 |
| 侧移躲开 | 通过；扑击未命中 |
| 扑击后恢复 → 待机 | 通过；1.5 s 恢复 |
| 隔墙挑衅 | 拒绝；agitation 0 |
| 同瞬间连按 | 第二次被 0.7 s 冷却拒绝 |
| R 重置 | 玩家回出生点；奶龙回待机 |
| F3 调试 | 显示奶龙状态/上头/距离 |

## 2. Blender → GLB → Godot 验证

Blender 4.5.15 LTS（官方 ZIP，便携解压）自带 Python 3.11.15。

```powershell
$blender = "C:\Users\31798\AppData\Local\Programs\Blender Foundation\Blender 4.5\blender.exe"
& $blender --background --factory-startup --python "<preview>\tools\blender\make_test_link.py"
& $blender --background --factory-startup --python "<preview>\tools\blender\verify_test_link.py"
```

- Blender 回读：4 个 mesh（Body/ForwardMarker/TopMarker/BackMarker），4 个材质；
  Body 0.8×0.8×0.8 m。
- Godot headless 导入实例 `BlenderLinkTest`：4 个 MeshInstance3D，Body AABB 0.8 m、脚底 y=0；
  ForwardMarker 在 Godot z=−0.65（Blender +Y→−Z），TopMarker 在 y=0.92（+Z→+Y）；
  BodyMat 基色导入；默认隐藏，F4 显示。
- 没有开窗截图；以上是实际导入/实例化/节点/材质检查。

## 3. 未验证

- **真人手动试玩**：挑衅距离、蓄势 1.0 s、扑击 11 m/s 是否好躲、是否有趣，均未由真人判断。
- **鼠标观察（本轮代码）**：headless 跳过；此前基础版窗口运行通过（16/0），但本轮没有再次开窗。
- **声音/麦克风**：未实现。
- **真实燃料抢夺/叼走/追回/伤害/结算**：未实现。
- **联网**：无网络代码，不能宣称多人已验证。
- **正式模型/动画**：占位模型；第三方素材未导入。

## 4. 测试步骤（真人）

1. 启动后确认是第一人称，鼠标可环视，WASD/Shift 正常。
2. 走近奶龙到 9 m 内并在画面中面对它；按 Q。HUD 应从“待机”变“注意”，奶龙转向并亮起状态环。
3. 等它靠近，继续按 Q（间隔约 0.7 s）。上头条增长；第 3 次进入“蓄势”，HUD 出现红色预警。
4. 蓄势约 1 s 后它扑向锁定位置；侧移/后退躲开。HUD 显示“扑空/恢复”，1.5 s 后可再次挑衅。
5. 走到视线测试柱后面按 Q，应提示“被墙挡住了”，奶龙不追踪。
6. 按 R 重置，重复。

## 5. 已知风险

- 行为参数全部是原型值，集中写在 `scripts/milk_dragon.gd` 顶部。
- 奶龙与玩家都使用碰撞层 16；扑击撞到玩家/墙会提前结束，不会穿墙。
- 第三人称只用于检查；镜头受灰盒边界 clamp。
- 本地分支基于旧 `origin/main`；网络恢复后需要 rebase 到最新 main。
