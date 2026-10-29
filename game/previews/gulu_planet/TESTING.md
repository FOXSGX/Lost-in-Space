# TESTING — 奶龙星第一人称试玩预览

最后更新：2026-10-29 23:35（GMT+8）

## 0. 启动

```powershell
$godot = "C:\Users\31798\Downloads\迷失太空\迷失太空\tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe"
$preview = "C:\Users\31798\Documents\GitHub\Lost-in-Space-gulu\game\previews\gulu_planet"

& $godot --path $preview                            # 试玩
& $godot --headless --path $preview -- --selftest   # 自动检查
& $godot --path $preview -- --shots                 # 截图到 user://gulu_shots
```

入口 `gulu_planet.tscn`，默认第一人称。

## 1. 自动检查（headless）

```
GULU SELFTEST SUMMARY passes=66 failures=0      ← 2026-10-29 23:2x，退出码 0
```

覆盖：

- 视角四项（眼高 1.600 / FOV 74.0 / near 0.05 / 玩家缩放 1.0）、第三人称切换与 FOV 复原
- 玩家模型复用共享皮肤（67 mesh）、Blender GLB 管线（F4，4 mesh）、5 个音效流已导入
- 移动 5.22 m、外墙碰撞
- 起始状态：奶龙叼第三罐、前两罐在地面、嘴部挂点 0.4 m 内
- 挑衅：注意 / 靠近 / 距离缩短 / 叼货时仍可挑衅 / 隔岩拒绝 / 冷却不叠加
- **远距离激怒后先靠近再蓄势**（`agitated dragon closes in, then winds up`）
- **蓄势时地面出现锁定红圈**（位置误差 < 0.4 m）
- 侧移躲开 / 离开锁定点 / **借力投货入仓 loaded=1**
- 入仓只计一次（重复 consume 不叠加）
- 拾取 / 关闭碰撞 / 跟随 / 放下 / 恢复碰撞 / **抱进舱口自动入仓**
- 静止被扑命中 / 被扑掉手上的燃料
- **舱内挑衅被拒绝**（agitation 不增加，提示含“装货口”）
- **看见你抱货 → 注意**、**贴太近会抢走燃料**
- 找燃料（放下嘴里的货后会自己去叼）
- 完成 3/3 + 横幅；R 重开（位置、第一人称、奶龙、计数、燃料、挂点）
- 调试面板 + 状态环只在 F3 出现

已知无害告警：退出时 `2 ObjectDB instances were leaked`、`1 resources still in use at exit`。

## 2. 窗口验证（真实渲染）

`--shots` 会打印 `SHOTMETA`（奶龙/玩家/飞行中燃料的屏幕坐标、状态、计数），截图存
`user://gulu_shots`，本次已复制到 `docs/shots/`（8 张，1280×800）。

```
01_opening_three_way      dragon(308,424) 在屏内   fuels=free,free,dragon
02_carry_first_can        dragon(184,448)          fuels=player,free,dragon
03_dragon_sees_your_fuel  dragon(640,505) 在屏内   状态=注意
04_dragon_windup_with_fuel dragon(652,474) 在屏内  状态=蓄势 holding=true
05_miss_fuel_into_bay     dragon(447,440) + 燃料(581,427) 在屏内  状态=恢复 thrown
06_bay_feedback           dragon(447,440)          状态=待机 loaded=1
07_loading_bay_wide       装货口全景
08_third_person_player     player(640,429) 在屏内
```

亮度（`tools/inspect_shot.py`）：mean 0.41–0.55，过曝 >0.94 仅 0.5–2.1%。

**本轮实际踩到并修掉的画面问题**（靠上面的工具发现）：
- 天空被雾整片染成浅灰（`fog_sky_affect` 默认 1.0）→ 改 ProceduralSky，过曝从 10.4% 降到 0.5%
- 地面圆环全都是竖着的（TorusMesh 默认就在 XZ 平面，多余旋转）→ 去掉 `rotation.x`
- 抱着的燃料带 0.96 m 光环 + 0.35 强度灯 → 半个屏幕发琥珀色 → 光环仅在落地时显示、灯调到 0.10

## 3. 未验证

- **真人手动操作**：没有真人完整玩过；手感、抢货是否恼人、乐趣都未被真人确认。
- **图像人工审阅**：本环境无法显示图片，构图结论来自屏幕坐标断言 + 类别图 + 亮度统计。
- 声音听感（只验证流已加载与播放调用）。
- 多人（无网络代码）。

## 4. 五分钟试玩脚本

1. **0:00** 先别动：能看到脚前那罐、中间的奶龙、右边的装货口吗？三者关系清楚吗？
2. **0:20** 按 E 抱起脚前那罐，沿青色地标走到船头，走进装货口。计数变 1/3 了吗？
   奶龙来抢了吗？（这一罐应该**不会**被抢，是教学）
3. **1:20** 去拿北边那罐（奶龙窝旁）。抱起后它应该有反应：转头看你、走过来。
   站住不动 1 秒试试 —— 会被抢走吗？被抢后它嘴里的罐子还能骗回来吗？
4. **2:20** 站到装货口前约 4 米，按 Q。看它靠近、压低身体、脚边出现红圈 → **侧移出圈**。
   燃料进仓了吗？红圈出现那一刻你知道要躲吗？
5. **3:20** 故意站太远（离舱口 8 米外）再来一次，看燃料落在哪儿，捡回来重试。烦不烦？
6. **4:00** 被扑一次（站着不动）。知道自己掉了什么、还有多久能捡吗？
7. **4:30** 装满 3/3 → 看“返航准备完成” → 按 R。重开有没有残留？

### 试玩后回答

1. 你理解为什么挑衅它吗？（它是障碍，也是工具）
2. 自己搬和骗它送，两种都有用吗？哪一种更划算？
3. 失误后知道原因吗？愿意再试吗？
4. 哪个角色反应最有趣？哪段等待最无聊？

## 5. 已踩过的坑

- PowerShell `Get-Content/Set-Content` 会把 UTF-8 中文源码写坏（换行被吞 → 解析失败）。
  改脚本一律用编辑器/写入工具。**例外**：如果显式 `-Encoding UTF8` 读写，可安全往返。
- Jolt 不支持非均匀缩放的 SphereShape（岩石改 BoxShape）。
- 燃料入仓 Tween 会把已复位的燃料又拉回仓里 → `reset_to_home()` 里 kill。
- `_teleport(pos, _yaw_to(target))` 会在传送前算朝向 → 改用 `_place_player(pos, target)`。
- 注释行末尾用 Tab 接 `_check(...)` 会把检查吞进注释（本轮发现 1 处，已修）。
