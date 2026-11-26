# TESTING — 奶龙星 · 射门试玩

最后更新：2026-11-10

## 0. 启动

```powershell
$godot = "C:\Users\31798\Downloads\迷失太空\迷失太空\tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe"
$preview = "C:\Users\31798\Documents\GitHub\Lost-in-Space-gulu\game\previews\gulu_planet"

& $godot --headless --path $preview -- --selftest   # 自动检查
& $godot --path $preview                            # 试玩
& $godot --path $preview -- --shots                 # 截图 → user://gulu_shots
& $godot --path $preview -- --record                # 只跑演示，不录像
& $godot --headless --path $preview -- --fx-test    # 表现层冒烟（抖动/顿帧/尘土/挤压）
& $godot --headless --path $preview -- --order-test # 装货订单（分层 ×2 / 30 s 换单 / 复位）
& $godot --headless --path $preview -- --pad-test   # 手柄（摇杆/RT/Start 的映射与实机路径）
& $godot --headless --path $preview -- --result-test # 结算目标（3 条目标的判定与面板数据）
& $godot --headless --path $preview -- --audio-test  # BGM（加载 / 循环 / 静音联动）
& $godot --headless --path $preview -- --super-test  # 必杀槽 / 超载射门 / 被扑加速
& $godot --headless --path $preview -- --progress-test # 挑战清单 / 三档难度 / 分档最高分 / 存档
& $godot --headless --path $preview -- --practice-test # 三个练习关（目标计数 / 完成 / 回标题）
& $godot --headless --path $preview -- --steal-test  # 奶龙偷球（叼走 / E 抢回 / 冷却 / 上限）
& $godot --headless --path $preview -- --tod-test    # 时段预设（光照/雾变化 + 玩法不受影响）
& $godot --headless --path $preview -- --records-test # 记录板（分档最高分 / 挑战 / 开关）
& $godot --headless --path $preview -- --campaign-test # 通关结构（3 关推进 / 高台刷球 / 通关 / 重试）
& $godot --headless --path $preview -- --counter-test # 反击（扑出后开回场地 / 3 秒窗口 / ×1.5）
& $godot --headless --path $preview -- --touch-test   # 接球抽射（滚球更远可踢 / 球速加成）
& $godot --headless --path $preview -- --hud-test     # HUD 分辨率自适应（1280/1600x900/1920x1080）
& $godot --headless --path $preview -- --stage-boot-test # --stage=N 直达关卡
```

**录演示片**（23 秒，含 BGM/音效；需要开窗口，不能 headless）：

```powershell
$frames = "$env:TEMP\gulu_demo_frames"
& $godot --path $preview --write-movie "$frames\k.png" --fixed-fps 30 -- --demo
& 'C:\Users\31798\AppData\Local\Programs\Python\Python312\python.exe' `
  $preview\tools\record_video.py $frames "$preview\docs\record\gulu_demo_2026-11-25.mp4" 30
# 需要声音时再用 imageio-ffmpeg 提供的 ffmpeg 把 "$frames\k.wav" 混进去
```

**重新生成 BGM**（改了 `make_bgm.py` 之后）：

```powershell
& 'C:\Users\31798\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe' `
  tools\audio\make_bgm.py assets\audio
& $godot --headless --path $preview --import
```

**30 fps 录像**（Movie Maker，必须开窗口，不能 headless）：

```powershell
$raw = "$preview\docs\record\raw"
Remove-Item $raw -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $raw | Out-Null
& $godot --path $preview --write-movie "$raw\k.png" --fixed-fps 30 -- --record
python game\previews\gulu_planet\tools\record_video.py $raw "$preview\docs\record\gulu_kick_loop.mp4" 30
```

入口 `gulu_planet.tscn`，默认第一人称。
新增音效/贴图后先跑一次 `& $godot --headless --path $preview --import`。

## 1. 自动检查（headless）

```
GULU SELFTEST SUMMARY passes=43 failures=0      ← 2026-11-10，退出码 0
```

覆盖（按功能分组）：

- 控制器：默认第一人称、眼高 1.600、FOV 74、near 0.05、WASD 位移
- 首屏：球 / 奶龙 / 装货口三个屏幕坐标都在视野内
- 旧玩法已移除：`provoke` 动作不存在、HUD 只有一句踢球提示
- **踢球**：6 m 外踢不到；隔墙踢不到；近距可踢且初速 > 8 m/s；方向与镜头一致
- **物理**：减速（13→<10.5 m/s）、最终静止、落地后**弹起**（y 从 <0.42 再升到 >0.62）
- **碰撞**：撞边界墙反弹；22 m/s 射门柱不穿透、不计分
- **奶龙**：直线射门被拦（球从未越过 12.45）；每次接触只拨球一次；接触不增加能量；
  横穿球场的球不会触发出击；出击后能回到观察/回防
- **空当**：侧面打远角能进球
- **门洞规则**：从上方越过、从柱外侧越过、从门里往回退都不计分；从场内越线计一次
- **不打扰**：正常停球 8 s 内位置不变（不会被传送）
- 完成横幅、R 重置球/奶龙/比分、连续重置安全
- 资源：3 个音效、骨架存在、模型缩放 1.0 且身体不离地

## 2. 窗口验证（真实渲染）

`--shots` 会打印 `SHOTMETA`（奶龙/球的屏幕坐标、状态、球速、球高），截图在
`user://gulu_shots`，本次复制到 `docs/shots/`（11 张，1280×800）。

```
01_spawn_ball_dragon_goal   出生点：球 / 奶龙 / 装货口同屏
02_near_ball                近球：球面、发光核心、灯带可读
03_kick_moment              刚踢出：球在滚，脚边有冲击环
04_keeper_block             奶龙拦截瞬间（状态=拦截）
05_goal_loaded              进球后：已装载 1/1 + 横幅
06_yard_wide                场地全景（中央是空的，道具在边线）
07_keeper_closeup           奶龙近景（静态模型，四肢清楚，无骨骼变形）
08_bay_closeup              装货口近景（门拱/厚度/材质/状态灯）
09_yard_side                场地侧面（环境与可玩区关系）
10_shot_lane                正常射门线（球路与门口）
11_dragon_neck_closeup      奶龙头颈特写（本轮用户反馈的失真检查点）
```

美术升级基线：`docs/art_baseline/`（同机位，改造前）；
同机位对照：`docs/art_compare/`（01/04/08/10 + 总览；09 号机位在基线后调整过，不参与对照）。

亮度/过曝抽查仍用 `tools/inspect_shot.py`，本轮最终 11 张：
mean 0.41–0.52，p95 0.73–0.89，clipped 0.0–3.3%。

## 2b. 性能采样（同一命令前后对比）

```powershell
& $godot --path $preview -- --perf
```

固定机位、关垂直同步、采 6 秒，输出：
`GULU PERF samples=12 fps_avg=... fps_min=... draw_calls_avg=... primitives_avg=...`

本轮（RTX 5060 Laptop / 1280×800 / GL Compatibility）：

- 修改前：793.2 FPS / 550 draw calls / 53,398 primitives
- 第一版美术：622.3 FPS / 868 / 108,426
- 二次修正（静态奶龙 + 单侧工作灯阴影）：386.3 FPS / 1,235 / 120,818

仍远高于 60 Hz；draw call 主要来自单侧工作灯阴影与细节件。
**这不是目标最低配置的验收，也不是手感验收。**

## 3. 未验证

- **真人手动试玩**：手感、难度、乐趣都没被真人确认。
- **图像人工审阅**：本环境看不到图片；构图与「迈步是否自然」只能由用户看录像判断。
- 声音听感（只验证流已加载、播放调用发生）。

## 4. 五分钟试玩脚本

请先不看代码、不听规则讲解，按标题屏提示自己开始。第一轮尽量自然玩，不要为了测试故意撞墙或寻找边界情况。

1. **开局 10 秒**：你能否自己说出唯一目标？是否知道鼠标用来瞄准、左键按住再松手射门？
2. **前 3 次射门**：能否靠近球就完成操作？蓄力是否容易理解？球的方向、力度和你的输入是否相符？
3. **奶龙第一次拦截**：你是否看懂它为什么拦住球？动作有没有反应、压迫感和一点角色个性？有没有觉得它作弊或像木桩？
4. **被拦后下一球**：你会不会自然地尝试换角度、调整站位或力度？是否清楚上一脚为什么没进？
5. **一轮结束**：你是否注意到进球、加时、连击和结算反馈？结束后是否想马上再开一局？

试玩时优先记具体行为和原话，不要只打“好玩/不好玩”分数：哪一刻停住了、哪次射门令人满意、失误后是否知道原因、是否主动重开。

### 试玩后回答

1. 不看说明，你认为这局的目标和射门操作是什么？
2. 第一次有成就感/挫败感分别发生在哪一脚？当时发生了什么？
3. 奶龙是在“读懂球路并做出反应”，还是感觉随机拦截/机械横移？
4. 你是否主动尝试了不同射门角度或蓄力？如果没有，是什么让你不想尝试？
5. 时间结束时，你想不想再玩一局？如果不想，最主要的原因是什么？

## 5. 已踩过的坑

- **对休眠刚体调用 `apply_central_impulse()` 会被吞掉**：必须先 `sleeping = false`，
  并且**在 `_physics_process` 里施加**。本轮实测球速一直停在 0.03 m/s，就是这个原因。
- 装货口旧门槛（0.22 m 实心）和接货斜面（z ±2.45）是给旧玩法做的，会把球挡在门外/弹回来。
- 第一人称相机是**全局旋转**（`camera.global_rotation = (-pitch, yaw, 0)`）；
  脚本改视线要写 `_camera_yaw`，且移动中控制器会把镜头拉回身体朝向 → 两者一起写。
- `unproject_position` 对相机背后的点会报错并返回 (0,0)：先 `is_position_behind`。
- 新增 wav 后未 `--import`：`ResourceLoader.exists()` 返回假。
- Movie Maker 会以 30% 实时速度跑，20 秒的片段要录 1 分钟；分辨率固定为窗口大小。
- GDScript lambda 对局部变量是值捕获；要回传结果用 `[false]` 数组。
- 编辑工具里 `oldText` 带尾部换行、`newText` 不带，会把下一行拼到上一行。

## 6. 演示脚本的诚实边界

`--record` 只做三件事：按住 W 走路、改朝向、调用和左键相同的 `_try_kick()`。
**不传送球、不传送玩家、不强制计分、不切换 AI 状态。**
录像里若出现进球，是球真的越过了门口平面。

## 3. 第三轮动作/物理复现（2026-11-18）

```powershell
# 动作：待机 → 横移 → 拦截 → 恢复 → 停下
& $godot --path $preview -- --motion
& $godot --path $preview --write-movie "$preview\docs\record\motion_raw\k.png" --fixed-fps 30 -- --motion

# 球物理：落地 / 直线滚停 / 撞门柱 / 撞奶龙
& $godot --headless --path $preview -- --physics
```

当前输出（摘要）：

```
drop  bounce_peak=0.766
roll  travel=7.434 angle=14.545 expected=21.864 inst_slip=0.000
post  before=0 after=0 (deflected out)
dragon guard=off post=0.22 / guard=on post=1.74, swats=0
```

说明：累计角度落后于 `distance/R` 是踢球瞬间的滑动过渡；稳定滚动时
`inst_slip=0.000`，转动与位移匹配。撞奶龙已改为接触只发反馈、不再补拨球冲量。

截图/对照：`docs/shots/` 11 张；`docs/round3_before/`（改造前 01/10）；
`docs/round3_compare/`（同机位对照）。录像 `docs/record/gulu_kick_loop.mp4`
（758 帧、25.2 s、scored=true）。性能 481 FPS / 934 draw calls / 93,061 primitives。

## 4. 奶龙表现录像（2026-11-18 晚）

```powershell
& $godot --path $preview --write-movie "$preview\docs\record\raw_track\k.png" --fixed-fps 30 -- --motion-track
& $godot --path $preview --write-movie "$preview\docs\record\raw_save\k.png" --fixed-fps 30 -- --motion-save
& $godot --path $preview --write-movie "$preview\docs\record\raw_combo\k.png" --fixed-fps 30 -- --motion-combo
```

已转成：
- `dragon_01_track_slow.mp4`：球缓慢换位，奶龙看球/侧移/停下。
- `dragon_02_save_proud.mp4`：一次成功拦截及短暂挺胸得意。
- `dragon_03_miss_goal.mp4`：先扑空（intercept_missed），再真实进球（goal_conceded）。
- `gulu_kick_loop.mp4`：实际第一人称游玩，未强制计分/拦截。

事件日志：`DRAGON EVENT save_made` / `intercept_missed` / `goal_conceded`。
每个反应 0.75–0.95 s；新拦截会打断旧反应，不阻塞回防。
自审 Qwen2-VL：经典奶龙、脖子无变形；track 脚不明显浮空；save/whiff/goal 姿势可读。
