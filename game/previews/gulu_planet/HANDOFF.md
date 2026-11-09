# HANDOFF — 奶龙星预览

> 多日任务续点。新会话先读本文件，再读 `STATUS.md` / `TESTING.md` / `BRIEF.md`。
> 每次推进后更新「当前状态 / 下一步 / 恢复命令」，不要只依赖聊天记录。

最后更新：2026-11-10

## 快照

- 仓库：`C:\Users\31798\Documents\GitHub\Lost-in-Space-gulu`
- 分支：`main`（本轮**本地提交，不推送**）
- 最新提交：以 `git log -1 --oneline` 为准
- 预览目录：`game/previews/gulu_planet`
- 当前玩法：**足球式地面踢球**（一球、一门、一只守门奶龙）
- 最新自测：`GULU SELFTEST SUMMARY passes=35 failures=0`
- 交付：`docs/shots/` 7 张、`docs/record/gulu_kick_loop.mp4`（脚本驱动）

## 本轮（2026-11-10）：玩法换轨到「踢球进门」

用户要求以这一版为准，**覆盖**此前的搬运 / 挑衅 / 怒气 / 诱导扑击设计。

- 旧玩法相关脚本删除：`fuel_prop.gd`、`milk_dragon_visual.gd`；
  旧规则（provoke/interact 动作）在 `gulu_app.gd` 里主动清掉，避免两套混跑。
- 新增 `energy_ball.gd`：地面球（无重力、无弹跳、无旋转球），
  指数减速 1.0/s、墙反弹 0.72、按位移滚转、飞行高亮、卡角落自救。
- `milk_dragon.gd` 重写为守门员：
  - 只在 `x 8.5..11.6, |z| ≤ 2.7` 活动，目标点 = 球与球门中心之间；
  - 反应延迟 0.24 s、最大速度 2.9 m/s、加速度 14；
  - **射门瞬间（球速 > 9）冻结目标 0.32 s**，所以打反方向能过（这是「可被击败」的关键）；
  - 拦球半径 0.95，拦到就弹回场内，冷却 0.55 s（不会连击）；
  - 球贴住且很慢时轻推离身（不会压死球）。
- `milk_dragon_model.gd` 重写表演：
  - 脚踩地（模型垫 0.072，身体起伏 ≤ 0.01 m）；
  - 大腿/小腿/脚掌骨骼按速度迈步，手臂反摆；
  - 转身由行为层 `lerp_angle`（6 rad/s）平滑，模型只负责姿势；
  - **删掉整体挤压缩放**，保留原模型轮廓；拦球时张开手臂 + 前倾。
- `gulu_app.gd` 重写：
  - 左键踢球；**鼠标未锁定时第一次点击只锁鼠标，不踢**（`_input` + `set_input_as_handled`）；
  - 踢球判定：距离 ≤ 2.7 m 且镜头前方与「指向球」夹角 ≤ ~69°；
  - HUD 只有一句「靠近球，左键踢进装货口。」+ 比分 + 完成横幅；
  - 新增 `--record`，用脚本跑「踢→被拦→换位置→进球」。
- `collector.gd`：入口 0.22 m 门槛改成贴地标线（否则球滚不进去）；
  接货斜面从 z ±2.45 外移到 ±2.95（旧位置会把必进球弹出来）。
- `nailong_environment.gd`：中央障碍清除，道具全部移到边线外；加中圈与门前弧。
- 音效精简为 3 个：`ball_kick` / `dragon_block` / `fuel_loaded`。

## 下一步（按优先级）

1. **用户看图**：`docs/shots/` 7 张 —— 球是否够显眼、球门是否够宽、奶龙迈步是否自然。
2. **真人试玩 5 分钟**（`TESTING.md` 第 4 节）：手感、拦球是否太强/太软、踢球距离是否够宽容。
3. 若奶龙太强：先降 `block_radius`（0.95 → 0.85）或 `commit_time` 提到 0.4；
   若太软：升 `max_speed` 或 `react_delay` 降到 0.16。
4. 若球滚太远/太滑：调 `energy_ball.gd` 的 `FRICTION`（1.0；越大越短）与 `KICK_SPEED`（15）。

## 已知问题 / 阻塞

1. **真人手感未验证**：全部结论来自自动检查与脚本录像。
2. **我看不到图片**：构图/美观由用户判断，我只给屏幕坐标与亮度统计。
3. 球与奶龙同时有引擎碰撞与手动反弹，极端角度可能有一次轻微二次弹跳。
4. 进球判定仍是固定 AABB（`CATCH_MIN/MAX`）；将来做高空球需要重做。
5. 退出时 Godot 仍报 2 个 ObjectDB 泄漏 + 1 个资源未释放（老问题，不影响运行）。

## 历史（已退出当前流程）

- `94958b0`：抢货预兆（伸脖/低吼/HUD 条）+ 刚捡回保护 + 扑空呆滞 + 借力投货。
- 更早：搬运 / 挑衅 / 怒气 / 扑击闭环、环境美术、正式 GLB 模型接入。
- 代码都在 git 里；**不要**再把两套规则混回当前流程。

## 恢复命令

```powershell
cd "C:\Users\31798\Documents\GitHub\Lost-in-Space-gulu"
git status --short
git log --oneline -3

$godot = "C:\Users\31798\Downloads\迷失太空\迷失太空\tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe"
$preview = "C:\Users\31798\Documents\GitHub\Lost-in-Space-gulu\game\previews\gulu_planet"

& $godot --headless --path $preview -- --selftest
& $godot --path $preview                    # 试玩
& $godot --path $preview -- --shots         # 截图 → user://gulu_shots
& $godot --path $preview -- --record        # 录像帧 → user://gulu_record
python game\previews\gulu_planet\tools\record_video.py "<帧目录>" docs\record\x.mp4
```

新增音效/贴图后先 `& $godot --headless --path $preview --import`，
否则 `ResourceLoader.exists()` 会给旧值（本轮踩过：音效只认到 5 个）。

## 不要做

- 不 push / 不 merge，除非用户明确要求（本轮明确只本地提交）。
- 不改 `station_player.gd` 的移动/碰撞/镜头手感；只允许外层补 `clamp_cave_camera_position`。
- 不重新生成角色外形；只能用现有 225 根骨做动作。
- 不把高空球/旋转/重力提前塞进本轮（接口留着，别实现）。
- 不用 `Get-Content`/`Set-Content` 在未指定 UTF8 的情况下往返改中文脚本。

## 更新规则

每次会话结束前至少写清：完成（文件/提交/测试结果）、下一步（一个具体动作）、
阻塞（需要用户决定的事项）、恢复（准确路径与命令）。
