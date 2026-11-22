# HANDOFF — 奶龙星预览

> 多日任务续点。新会话先读本文件，再读 `STATUS.md` / `TESTING.md` / `BRIEF.md`。
> 每次推进后更新「当前状态 / 下一步 / 恢复命令」，不要只依赖聊天记录。

最后更新：2026-11-23（复用其他星球模型的美术升级）

## 2026-11-23 · 复用其他星球成品模型（当前）

- 用户要求：建模做不精，就直接复用同仓库其他星球的成品模型把美术拉起来。
- 新增 `scripts/gulu_asset_dressing.gd` + `assets/props/`（6 个自建 GLB，复制自
  `game/assets/resonance/models/`），挂到 `nailong_environment.gd`。
- 内容：四周边界外崖壁 ×4、尖石 ×5、西侧场站大门、6 组自发光矿石晶簇、
  东墙外无人机坪、远处 30 m 反应堆塔；原程序化岩脊 4.6→3.4 m 退为前景碎石。
- 约束：装饰零碰撞（只给大门两根立柱加碰撞）；球的物理、AI、边界墙碰撞均未改。
- 验收：自测 **45/0**；`tools/probe_dressing.gd` 18 个节点贴地且不侵入球路/出生点；
  性能 **352.8 FPS / 1,153 DC / 120,852 prims**；截图 14 张（新增 12/13/14），
  改前 11 张备份在 `docs/art_baseline_2026_11_23/`。
- **待爸看图确认**：崖壁砂岩色是否统一、大门是否偏黑、远处反应堆塔是否抢眼。
- 详见 `docs/ART_PASS_2026-11-23.md` 与 `ASSETS.md` 第 12 节。

## 2026-11-18 · 奶龙回退与表现层

- 按用户要求恢复经典模型 `assets/characters/nailong_dl.glb`；保留 Icosphere 运行时清理；
  **不做任何骨骼旋转**，只用整体节点 bob/前倾/横摆 + 接地阴影。
- 事件驱动反应：`save_made`（实际拦下）、`intercept_missed`（实际扑空）、
  `goal_conceded`（实际进球）；动作不阻塞行为状态机，新拦截会打断旧反应。
- 三段调试录像：`dragon_01_track_slow.mp4` / `dragon_02_save_proud.mp4` /
  `dragon_03_miss_goal.mp4`；实际游玩 `gulu_kick_loop.mp4`（scored=false，未伪造）。
- 自测 45/0；物理回归 inst_slip=0.000、撞奶龙无额外冲量。
- 自审 Qwen2-VL：经典黄色奶龙、脖子无变形；save 挺胸、whiff 前倾回头、goal 低头。
## 2026-11-18 · 第三轮：奶龙定住 + 地面减法 + 球物理

- 奶龙：静态模型去掉上下 bob，加接地阴影；`--motion` 确认观察→拦截→恢复→观察，
  无骨骼变形；不改碰撞/守门逻辑。
- 地面：删除通道边线/板缝/停机坪细节/箭头/轮廓线/场边门架货柜等杂物；
  只保留暖色球场 vs 深色装货平台的大色差 + 舱口 3 段短标线。
- 物理：`--physics` 固定条件复现；滚动稳定后 inst_slip=0.000；
  撞奶龙不再额外加拨球冲量（接触只发 blocked 反馈），避免双重推球。
- 自测 `passes=45 failures=0`；截图 11 张；录像 758 帧（scored=true）。
- 性能 481 FPS / 934 draw calls / 93,061 primitives。
- 同机位对照 `docs/round3_compare/`（01/10）；改造前 `docs/round3_before/`。
## 2026-11-18 · 环境美术升级（15:xx 二次修正）

- **奶龙换成本仓库自建 `assets/characters/nailong.glb`**：静态网格、14 个网格、
  18,880 tris；不再做任何骨骼旋转。旧 `nailong_dl.glb` 的 225 根 Rigify 骨被按世界轴硬拧，
  导致四肢/脖子变形，已弃用（文件保留在仓库中，不再引用）。
- 行走/拦截只动整体节点（bob/前倾/横摆），不改变网格；`set_block` 仍驱动前倾。
- 自审 Qwen2-VL：脖子特写 10/10、全身近景 9/10；场景 7–8/10（地面偏空）。
- 场景：暖色中央通道 + 深色门前区 + 冷色外围；装货口加高光柱/横梁/门楣牌/
  门内沿灯圈/中央箭头；冷色轮廓光 + 单侧工作灯阴影；两个边线货柜。
- 自测 `passes=44 failures=0`；截图 11 张（新增脖子特写）、基线 10 张、对照 4 组；
  录像 444 帧（scored=true）。
- 性能：386 FPS / 1,235 draw calls / 120,818 primitives（仍远高于 60 Hz）。
- 详见 `docs/ART_PASS_2026-11-18.md`。

## 快照（2026-11-10 玩法）

- 仓库：`C:\Users\31798\Documents\GitHub\Lost-in-Space-gulu`
- 分支：`main`（本轮**本地提交，不推送**）
- 最新提交：以 `git log -1 --oneline` 为准
- 预览目录：`game/previews/gulu_planet`
- 当前玩法：**足球式地面踢球**（一球、一门、一只守门奶龙）
- 最新自测：`GULU SELFTEST SUMMARY passes=44 failures=0`
- 交付：`docs/shots/` 11 张、`docs/record/gulu_kick_loop.mp4`（30 fps，脚本演示）

## 本轮（2026-11-10 第二次）：从「伪物理」换成真刚体，AI 从「门线跟球」换成四状态

用户指出上一版的两个硬伤：球不是刚体、奶龙不像主动拦截者。本轮只解决这两件事。

### 球：RigidBody3D

- 球形碰撞体 r=0.34，mass 1.2，线性阻尼 0.45 / 角阻尼 0.55，friction 0.7 / bounce 0.5，
  `continuous_cd = true`（高速不穿门柱），`can_sleep = true`。
- 踢球 = 一次性 `apply_central_impulse`（16 → 19 N·s，约 13→16 m/s）；
  **不再**每帧写 `rotation`、**不再**在低速时把速度归零、**不再**手算法线反射。
- 关键实现细节：冲量必须在 `_physics_process` 里施加。直接对休眠体调用
  `apply_central_impulse()` 会被吞掉（本轮实测：球速一直是 0.03）。
  现在 `kick()` 只记 `_pending_impulse`，下一物理帧统一发出。
- 出界只在「真的掉出世界」（y<-8 或 |x|>28 或 |z|>22）时复位到发球点；
  正常停球、门边停球一律不动（上一版「停 3.5 s 就传送」已删）。

### 奶龙：四状态主动拦截者

- 状态：`观察` → `拦截` → `恢复` → `回防`。
- 站位：离门线约 1.3 m（x≈11.1）；球远时守中路，球近了才向近角偏移
  （`closeness = (ball.x - 9) / 3`）。这样远射的远角是真空当。
- 出击条件：球朝球门来（vx>2）、预计到达 <1.5 s、落点在门洞 ±3.4 内、
  且速度方向与「球→门」夹角 < 70°。**不看玩家输入**，只延迟采样球位置与速度。
- 出击后目标锁定 0.5 s（不能改向），冷却 2.2 s —— 玩家可以利用扑空。
- 拦球：物理胶囊接触由引擎处理；额外的「拨球冲量」只在 `拦截` 状态、距离 <0.95、
  球朝门来、冷却 0.8 s 满足时施加一次。**不会同一次接触既反射又加冲量**。
- 速度：走 1.6 / 冲 2.4 m/s，加速度 14，转向角速度上限 5 rad/s（按 delta 积分）。

### 动作

- 步态由**实际位移**推进（`_gait += speed * dt * 2.6`），停下时腿回到中立位；
- 膝盖只在摆动相弯曲，脚掌在支撑相反向回正（不再跟着大腿翻）；
- 转向由行为层 `max_turn_rate * delta` 截断，不是 `lerp` 系数；
- 拦球姿势由 `set_block` 权重驱动（0.42 s 衰减），与拨球时机同步；
- 仍然不做整体挤压，模型轮廓不变。

### 录制

- `--record` 现在**纯输入驱动**：只按 W / 改变朝向 / 调 `_try_kick()`，
  不传送玩家、不移动球、不改 AI 状态。
- 用 Godot Movie Maker 出 30 fps PNG 序列，再 `tools/record_video.py` 转 MP4：
  ```
  & $godot --path $preview --write-movie "$preview\docs\record\raw\k.png" --fixed-fps 30 -- --record
  python tools\record_video.py "$preview\docs\record\raw" "$preview\docs\record\gulu_kick_loop.mp4" 30
  ```

## 下一步（按优先级）

1. **用户看录像** `docs/record/gulu_kick_loop.mp4`（30 fps）：滚动手感、弹跳、迈步是否自然。
2. **真人试玩**（`TESTING.md` 第 4 节）：踢球距离 1.9 m 是否顺手、奶龙是否太难/太软。
3. 调参入口：
   - 球太飘/太沉：`energy_ball.gd` 的 `linear_damp`、`angular_damp`、物理材质 `friction/bounce`；
   - 射门力度：`KICK_IMPULSE`（19）；
   - 守门强度：`milk_dragon.gd` 的 `charge_speed`(2.4) / `react_delay`(0.24) / `block_radius`；
   - 出击频率：`intercept_cooldown`(2.2) / `intercept_time`(0.5)。
4. 若要做高空球：`energy_ball.gd` 的踢球方向加 `y` 分量即可，输入与判定不用改
   （判定用的是球心越线，高空球需要额外加「必须低于横梁」的条件，已有 y 上限）。

## 已知问题 / 阻塞

1. **真人手感未验证**，难度只由脚本回放确认。
2. **我看不到画面**：迈步/拦截姿态是否自然、构图是否好，只能由用户判断。
3. 球与奶龙同时接触时，物理接触 + 拨球冲量是两套力，极端角度可能有一次轻微二次弹跳。
4. 进球判定是「球心越线」：贴柱擦边的球可能判得比视觉稍严。
5. 退出时 Godot 仍报 2 个 ObjectDB 泄漏 + 1 个资源未释放（老问题，不影响运行）。
6. Movie Maker 模式需要真实渲染窗口（不能 `--headless`），录制约 30% 实时速度。

## 历史（已退出当前流程）

- `474f41e`：第一版踢球（手写球运动、门线横向跟球、2.7 m 踢球距离、低速归零）。
- `94958b0`：抢货预兆 / 扑空呆滞 / 借力装货（更早的玩法，已删除脚本）。
- 更早：搬运 / 挑衅 / 怒气 / 扑击闭环、环境美术、正式 GLB 模型接入。

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
& $godot --path $preview -- --record        # 只跑演示（不录像）
```

新增音效/贴图后先 `& $godot --headless --path $preview --import`。

## 不要做

- 不 push / 不 merge，除非用户明确要求（本轮明确只本地提交）。
- 不改 `station_player.gd` 的移动/碰撞/镜头手感；只允许外层补 `clamp_cave_camera_position`。
- 不重新生成角色外形；只能用现有 225 根骨做动作。
- 不在演示脚本里传送球、强制计分或改 AI 状态来「制造成功」。
- 不用 `Get-Content`/`Set-Content` 在未指定 UTF8 的情况下往返改中文脚本。

## 更新规则

每次会话结束前至少写清：完成（文件/提交/测试结果）、下一步（一个具体动作）、
阻塞（需要用户决定的事项）、恢复（准确路径与命令）。


