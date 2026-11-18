# STATUS — 奶龙星 · 射门试玩

最后更新：2026-11-18
分支：`feature/lis-physics-rc1`（本轮本地提交，**不推送**）
目录：`game/previews/gulu_planet/`

## 2026-11-18 · 环境美术升级（本轮）

- 装货口：圆角门拱、有厚度构件、内密封条、防雨檐、两盏有灯体工作灯、
  三格状态灯槽、检修面板/螺栓、橡胶缓冲条、供电线缆；门口尺寸与碰撞未变。
- 门前地面：大块混凝土板 + 少而长的板缝 + 金属停机坪 + 宽幅磨痕/导引条；
  所有装饰无碰撞、厚度 ≤ 2 cm。
- 场边：低多边形分层岩体、工业货箱、边线装货门架；碰撞位置/尺寸不变。
- 能源球：只改外观（灯带/核心亮度/两条经线框），物理参数未动。
- 奶龙：模型/骨架/尺寸/动作未动。
- 自测：`GULU SELFTEST SUMMARY passes=43 failures=0`
- 截图：`docs/shots/` 10 张；基线 `docs/art_baseline/` 10 张；
  同机位对照 `docs/art_compare/`（01/04/08/10）；录像 `docs/record/gulu_kick_loop.mp4`
  （30 fps，444 帧，14.8 s，脚本输入，记录到 scored=true）。
- 性能（1280×800 / GL Compatibility / 关垂直同步 / 6 s / RTX 5060 Laptop）：
  修改前 **793 FPS / 550 draw calls / 53,398 primitives**；
  修改后 **622 FPS / 868 / 108,426**。仍 >600 FPS，无玩法风险；
  draw call +58% 来自装货口细节与岩体/货箱分层。
- **视觉效果待人工确认**：本环境无法查看图片；自动化只能证明几何、碰撞、
  自测、截图/录像生成和性能。

详见 `docs/ART_PASS_2026-11-18.md`。

## 当前阶段（玩法）

**足球式地面踢球 + 刚体物理 + 有限能力的守门奶龙。**

- 球：`RigidBody3D` 球形刚体，重力/碰撞/弹跳/旋转交给物理引擎；踢球只施加冲量。
- 奶龙：观察站位 → 拦截 → 恢复 → 回防，四状态；只估计拦截点，不预知、不瞬移。
- 自测：`GULU SELFTEST SUMMARY passes=43 failures=0`
- 截图：`docs/shots/` 7 张
- 录像：`docs/record/gulu_kick_loop.mp4`（1280×800 @ **30 fps**，14.8 s，脚本演示）

## 本轮改动（相对 474f41e）

| 文件 | 改动 |
| --- | --- |
| `scripts/energy_ball.gd` | **改为 RigidBody3D**：球形碰撞体、mass 1.2、线性阻尼 0.45、角阻尼 0.55、`continuous_cd` 防高速穿透、物理材质 friction 0.7 / bounce 0.5；**删除**手写滚动、手算法线反弹、低速归零；踢球走 `apply_central_impulse`（在 `_physics_process` 里施加，避免休眠体吞冲量） |
| `scripts/collector.gd` | 进球改为**球心从场内越过门口平面**（x=12.45）且高度/横向在门洞内；不再用「进入 AABB 就算」；新增 `watch_ball()` / `goal_plane_x()` |
| `scripts/milk_dragon.gd` | 重写为「观察 / 拦截 / 恢复 / 回防」四状态；站位按球远近在中路与近角之间切换；出击由**接近方向 + 预计到达时间 + 落点**共同判定（不再是「球速>9 就冻结」）；每次出击锁定目标 0.5 s；拦截冷却 2.2 s；拨球冲量独立触发 + 0.8 s 冷却 |
| `scripts/milk_dragon_model.gd` | 步态由**实际位移**驱动（停下即停步）、膝盖只在摆动相弯曲、脚掌支撑相反向回正；转向角速度在行为层按 `delta` 限制；拦球动作由 `set_block` 权重驱动；仍不做整体挤压 |
| `scripts/gulu_app.gd` | 踢球距离 2.7 → **1.9 m**、加**视线遮挡检测**、提示只在可踢时出现；删除「停 3.5 s 就传送回玩家面前」；只保留「掉出世界」时复位；`--record` 改为**纯输入驱动**（不打球、不传送、不改 AI 状态）；录制改用 Movie Maker 30 fps |
| `tools/record_video.py` | 支持 Movie Maker 的 `k00000000.png` 序列，默认 30 fps |

## 功能真实状态（自测证据）

| 功能 | 状态 | 证据 |
| --- | --- | --- |
| 近距离可踢 / 远距离不可踢 | ✅ | `cannot kick from far away` / `kick works up close` |
| 有遮挡不能踢 | ✅ | `cannot kick through an obstruction` |
| 踢球是冲量、方向跟镜头 | ✅ | `kick applies an impulse (13+ m/s)` / `kick direction follows the camera` |
| 减速、停止 | ✅ | `ball decelerates` / `ball comes to rest` |
| 重力下落与落地弹起 | ✅ | `ball falls under gravity` / `ball bounces after landing` |
| 撞墙反弹 | ✅ | `ball bounces off the boundary wall` |
| 高速不穿门柱、不误判 | ✅ | `high-speed ball does not pass through the frame` / `shot into the post does not score` |
| 奶龙拦直线、只拨一次、不加速度 | ✅ | `keeper stops a straight shot` / `keeper swats the ball once per contact` / `contact ... does not add energy` |
| 横穿球不触发出击 | ✅ | `keeper does not dive at a cross-field ball` |
| 出击后能恢复 | ✅ | `keeper recovers after a dive` |
| 换位置能创造空当 | ✅ | `an angled shot into the open side scores` |
| 门洞规则（上方/外侧/背面） | ✅ | `crossing above the mouth` / `outside the posts` / `coming back out` |
| 正常停球不被传送 | ✅ | `a normal stop is never teleported` |
| 完成 / 重开 / 连续重置 | ✅ | `goal completes the round` / `R resets ...` / `repeated reset is safe` |
| 控制器未被破坏 | ✅ | 眼高 1.6 / FOV 74 / near 0.05 / WASD |

## 未验证 / 风险

- **真人手感**：仍然没有真人试玩；难度曲线、球速是否合适未确认。
- **我无法查看画面**：移动/迈步是否自然、球门是否够宽，只能由用户看录像与截图判断。
- 球与奶龙同时接触时，物理引擎与拨球冲量是两套力，极端角度仍可能有轻微二次弹跳。
- 进球判定用「球心越线」：球贴地滚入没问题，但贴着门柱内侧的擦边球可能判得比视觉略严。

## 历史

| 提交 | 内容 |
| --- | --- |
| `474f41e` | 第一版踢球玩法（手写运动 + 门线横向跟球） |
| `94958b0` | 旧玩法：抢货预兆 / 扑空呆滞 / 借力装货（已退出流程） |
| `891b4ea` | 换成 Sketchfab 正式奶龙模型（CC-BY-4.0） |
| `d7fb6e2` / `caa5ef3` | 场景美术第一步 |
| `73e59d9` | 自建静态奶龙模型（不再使用） |
