# TESTING — 奶龙星 · 射门试玩

最后更新：2026-11-10

## 0. 启动

```powershell
$godot = "C:\Users\31798\Downloads\迷失太空\迷失太空\tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe"
$preview = "C:\Users\31798\Documents\GitHub\Lost-in-Space-gulu\game\previews\gulu_planet"

& $godot --headless --path $preview -- --selftest   # 自动检查
& $godot --path $preview                            # 试玩
& $godot --path $preview -- --shots                 # 截图 → user://gulu_shots
& $godot --path $preview -- --record                # 录像帧 → user://gulu_record
python tools\record_video.py "<帧目录>" docs\record\gulu_kick_loop.mp4
```

入口 `gulu_planet.tscn`，默认第一人称。
**新增音效/贴图后先跑一次** `& $godot --headless --path $preview --import`。

## 1. 自动检查（headless）

```
GULU SELFTEST SUMMARY passes=35 failures=0      ← 2026-11-10，退出码 0
```

覆盖：

- 控制器：默认第一人称、眼高 1.600、FOV 74、near 0.05、WASD 位移 > 2 m
- 首屏：球 / 奶龙 / 装货口 三个 `unproject_position` 都在 1280×800 内
- 旧玩法已移除：`provoke` 动作不存在、HUD 只有一句踢球提示
- **远距离踢不到**（6 m 外 `_try_kick()` 返回 false，球速 0）
- **近距离可踢**：初速 15 m/s，方向与镜头夹角 < 25°
- **减速**（12.0 → 4.4 m/s）、**停止**、**停球后可再踢**
- **边界反弹**：朝墙踢，`velocity.z` 由正变负
- **奶龙拦直线射门**：球被弹回，且从未到达 `x ≥ 12.4`
- **不会连击**（1.6 s 内 1 次拦球）、**不会压死球**（球心距离 > 0.75 或仍在动）
- **打空当能进球**（`loaded=1`）
- **门框外侧不计分**、**同一颗球不会计两次**
- **卡球自救**（装货口侧袋停 3.5 s 后被放回场内）
- **完成横幅**、**R 重置球/奶龙/比分**、**连续重置安全**
- 资源：3 个音效已导入、奶龙骨架存在、模型保持 1.0 缩放且身体不离地

## 2. 窗口验证（真实渲染）

`--shots` 打印 `SHOTMETA`（奶龙/球的屏幕坐标、状态、球速），截图在 `user://gulu_shots`，
本次复制到 `docs/shots/`（7 张，1280×800）。

```
01_spawn_ball_dragon_goal  dragon(515,416) ball(341,499)  state=待机
02_near_ball               dragon(710,420) ball(617,663)
03_kick_moment             dragon(604,421) ball(589,582)  ball_speed=13.1
04_keeper_block            dragon(643,518) ball(393,752)  state=拦球
05_goal_loaded             dragon(274,474) ball(660,505)  loaded=1
06_yard_wide               dragon(697,418) ball(734,412)  loaded=1
07_keeper_closeup          dragon(426,539) ball(20,770)
```

亮度（`tools/inspect_shot.py`）：以实际输出为准；本轮未做色调改动，沿用上一轮参数
（mean 约 0.42–0.52，过曝 < 6%）。

录像：`--record` → 93 帧 @8fps → `docs/record/gulu_kick_loop.mp4`（约 530 KB）。
流程是「走到球边 → 第一脚被拦 → 换到侧面 → 第二脚进球 → 重开」，
**脚本驱动（`Input.action_press` + 精确站位），不是真人操作**。

## 3. 未验证

- **真人手动试玩**：手感、难度、乐趣都没被真人确认。
- **图像人工审阅**：本环境看不到图片；构图结论来自屏幕坐标与像素统计。
- 声音听感（只验证流已加载、播放调用发生）。
- 球在极端角度下的多次反弹是否会有肉眼可见抖动。

## 4. 五分钟试玩脚本

1. **0:00** 出生点：能同时看到球、奶龙、装货口吗？球够不够显眼？
2. **0:20** 走近球，左键踢一脚。踢得动吗？方向跟你瞄的一致吗？
3. **0:50** 正面再踢一脚，看奶龙横移拦截。它拦得「像活的」还是「瞬移」？
4. **1:30** 绕到侧面，对着空当踢。进得去吗？进不去是太远、太偏还是被拦？
5. **2:30** 故意踢到墙上：反弹自然吗？球会不会卡在角落？
6. **3:10** 进一球：看到「燃料已装载」和夹臂/灯带了吗？
7. **3:40** 按 R：球、奶龙、比分都回来了吗？连按几次 R 会不会残留？
8. **4:20** 用 Tab 切第三人称再切回来，确认镜头没被本轮改动弄坏。

### 试玩后回答

1. 你第一次踢球时，知不知道要瞄哪儿？
2. 奶龙拦球的成功率大概几成？太难还是太软？
3. 输了/被拦了，你知道下一步该怎么做吗（换边、靠近、等它移开）？
4. 进球那一下的反馈（声音/灯/横幅）够不够明确？

## 5. 已踩过的坑

- PowerShell `Get-Content/Set-Content` 会把 UTF-8 中文源码写坏（换行被吞 → 解析失败）。
  改脚本一律用编辑器/写入工具；必须用 PowerShell 时显式 `-Encoding UTF8`。
- Jolt 不支持非均匀缩放的 SphereShape（岩石改 BoxShape）。
- 装货口入口原来有 0.22 m 门槛：**球滚不进去**（旧玩法需要它挡燃料）。本轮改成贴地标线。
- 装货口两侧接货斜面原来在 z ±2.45（正在球门口内），会把必进球弹回来 → 外移到 ±2.95。
- 新增 wav 后未 `--import`：`ResourceLoader.exists()` 返回假，音效只认到 5 个。
- 第一人称相机是**全局旋转**（`camera.global_rotation = (-pitch, yaw, 0)`），
  改玩家身体朝向不影响它；脚本里要改视线必须写 `_camera_yaw` / `_camera_yaw_target`。
  但只改镜头不改身体时，控制器会在移动中把镜头拉回身体朝向 —— 自动化里两者一起写。
- `unproject_position` 对位于相机背后的点会报错并返回 (0,0)：先 `is_position_behind` 再取坐标。
- GDScript 的 lambda 对局部变量是**值捕获**；要跨 lambda 回传结果用 `[false]` 数组。
- 编辑工具里 `oldText` 带尾部换行、`newText` 不带，会把下一行拼到上一行（本轮踩到 3 次）。
