# STATUS — 奶龙星 · 射门试玩

最后更新：2026-11-10
分支：`main`（本轮本地提交，**不推送**）
目录：`game/previews/gulu_planet/`

## 当前阶段

**足球式地面踢球**：一颗能源球 → 左键踢向装货口 → 奶龙守门拦截 → 打空当进球 → 一球完成 → R 重开。

- 自测：`GULU SELFTEST SUMMARY passes=35 failures=0`
- 截图：`docs/shots/` 7 张（球 / 近球 / 踢出 / 被拦 / 进球 / 全景 / 奶龙近景）
- 录像：`docs/record/gulu_kick_loop.mp4`（93 帧 @8fps，**脚本驱动，不是真人**）
- 角色仍是 `assets/characters/nailong_dl.glb`（CC-BY-4.0），未重新建模

## 本轮改动

| 文件 | 改动 |
| --- | --- |
| `scripts/energy_ball.gd` | **新增**。球形能源球：贴地滚动（按位移滚转角）、指数减速、墙/门框/奶龙反弹、飞行时高亮、静止太久且卡在角落时自救 |
| `scripts/milk_dragon.gd` | **重写**为守门员：只跟球、守门区、反应延迟 0.24 s、速度 2.9 m/s、射门瞬间「扑向当前方向」0.32 s、拦球弹回、防压球 |
| `scripts/milk_dragon_model.gd` | **重写表演层**：脚踩地、按速度迈步（大腿/小腿/脚掌骨骼）、平滑转身、拦球张手；**去掉整体挤压缩放** |
| `scripts/gulu_app.gd` | **重写**：左键踢球（鼠标未锁定时第一次点击只锁鼠标）、HUD 只留一句提示、进球横幅、R 重开、自测/截图/录制 |
| `scripts/collector.gd` | 入口门槛从 0.22 m 实心改成贴地标线（球能滚进去）；接货斜面外移到 z ±2.95（不再把射门弹出来）；新增 `intake_point()` |
| `scripts/nailong_environment.gd` | 中央障碍全部移到边线外；加中圈/门前弧；货箱垛挪到场边 |
| `scripts/sfx.gd` + `tools/audio/make_sfx.py` | 只留 3 个音：`ball_kick` / `dragon_block` / `fuel_loaded`（本地合成） |
| 删除 | `scripts/fuel_prop.gd`、`scripts/milk_dragon_visual.gd`（旧玩法专用；历史在 git 里） |

## 功能真实状态（自测证据）

| 功能 | 状态 | 证据 |
| --- | --- | --- |
| 近距离可踢、远距离不可踢 | ✅ | `cannot kick from far away` / `kick works up close` |
| 踢球方向跟镜头、固定力度 | ✅ | `kick direction follows the camera` / `kick gives a fixed strong impulse (15.0 m/s)` |
| 球减速、停止、可再次踢动 | ✅ | `ball decelerates (12.0 -> 4.4)` / `ball comes to rest` / `resting ball can be kicked again` |
| 墙/边界反弹 | ✅ | `ball bounces off the boundary wall (vz=-2.93)` |
| 奶龙拦直线射门 | ✅ | `keeper blocks a straight shot` / `blocked ball never reaches the bay` |
| 奶龙不会连击球、不会压死球 | ✅ | `keeper blocks but does not machine-gun (1 hits)` / `ball is not trapped under the keeper` |
| 打空当能进球 | ✅ | `an angled shot into the open side scores (loaded=1)` |
| 门框外侧不计分、不重复计分 | ✅ | `outside the frame does not count` / `the same ball cannot score twice` |
| 卡球自救 | ✅ | `stuck ball is put back in play` |
| 完成与本局重开、连续重置 | ✅ | `goal completes the round` / `R resets ball and score` / `repeated reset is safe` |
| 第一人称控制器未被破坏 | ✅ | 眼高 1.6 / FOV 74 / near 0.05 / WASD 位移 |
| 旧玩法已移除 | ✅ | `old provoke action removed` / 无需 Q、E |

## 未验证 / 风险

- **真人手感**：仍然没有真人完整试玩；结论来自自动检查 + 脚本录像 + 屏幕坐标。
- **我看不到图片**：构图只能给坐标（见 TESTING 第 2 节），需要用户看图确认。
- 球与奶龙身体的物理接触是「引擎碰撞 + 手动反弹」两层叠加，极端角度下偶有轻微抖动可能。
- 进球判定仍是固定 AABB（沿用旧装货口），球贴地滚入才稳；高空球进来后需要重做判定。

## 历史（只留摘要，细节看 git 提交与 DECISIONS）

| 提交 | 内容 |
| --- | --- |
| `94958b0` | 旧玩法最后一版：抢货预兆、扑空呆滞、借力装货、环境去箭头 |
| `891b4ea` | 换成 Sketchfab 正式奶龙模型（CC-BY-4.0） |
| `d7fb6e2` / `caa5ef3` | 场景美术第一步：装货口、搬运场地、生物窝、地形光照 |
| `73e59d9` | 自建静态奶龙模型（已不再使用） |
| `58cbaf9` / `ee6cdd2` | 第一人称装货闭环、开场三分构图 |

2026-11-10 凌晨的「抢货预兆 / 扑空呆滞 / 借力装货」玩法已退出当前流程，
细节留档在 `HANDOFF.md` 历史段与 `DECISIONS.md` D-38~D-42。
