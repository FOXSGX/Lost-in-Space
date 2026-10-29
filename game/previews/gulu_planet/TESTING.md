# TESTING — 奶龙星第一人称试玩预览

最后更新：2026-10-29 15:10（GMT+8）

## 0. 启动

```powershell
$godot = "C:\Users\31798\Downloads\迷失太空\迷失太空\tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe"
$preview = "C:\Users\31798\Documents\GitHub\Lost-in-Space-gulu\game\previews\gulu_planet"

# 正常试玩（会开窗口，由使用者主动运行）
& $godot --path $preview

# 自动验证（无窗口）
& $godot --headless --path $preview -- --selftest

# 窗口截图（会开窗口，跑完自动退出）
& $godot --path $preview -- --shots
```

入口：`gulu_planet.tscn`。默认第一人称，鼠标捕获。

## 1. 自动检查（headless）

```
GULU SELFTEST SUMMARY passes=58 failures=0
```

2026-10-29 实测，退出码 0。覆盖项：

| 分组 | 项目 |
| --- | --- |
| 视角 | 默认第一人称 / 眼高 1.600 m / FOV 74.0 / near 0.05 / 玩家模型缩放 1.0 |
| 模型 | 首屏可见奶龙 / 主角由共享皮肤构建 / 67 个 mesh |
| 管线 | Blender GLB 默认隐藏 / F4 显示 4 个 mesh / F4 再隐藏 |
| 移动 | WASD 前进 5.32 m / 外墙碰撞停在 x=10.84 |
| 视角切换 | Tab 进退、第三人称 FOV 62、可见身体、回到第一人称恢复 74 |
| 起始状态 | 奶龙叼着第一罐 / 燃料 mode=dragon / 燃料在嘴部挂点 0.4 m 内 |
| 挑衅 | 注意 / 靠近 / 距离缩短 / 叼货时仍可挑衅 / 隔石堆拒绝 / 冷却不叠加 |
| 蓄势 | 第三次挑衅进入蓄势 |
| 躲避 | 侧移后未被命中 / 已离开锁定点 |
| **借力送货** | **扑击释放的燃料入仓 loaded=1** |
| 计数 | 手动入仓计一次 / 同一罐重复 consume 不重复计数 |
| 搬运 | 拾取 / 携带关闭碰撞 / 跟随 / 放下 / 恢复碰撞 / 抱进装货口自动入仓 |
| 被扑 | 静止玩家可被命中 / 被扑掉手上的燃料 |
| 找燃料 | 放下嘴里的货后，会自己去叼附近的散装燃料 |
| 完成 | 三罐装满 / 完成条显示 |
| 重开 | 回出生点 / 第一人称 / 奶龙待机 / 清空进度 / 重新叼起第一罐 / 散装燃料回原位 |
| 调试 | F3 面板渲染 / 状态环仅调试模式出现 |

已知无害告警：退出时 Godot 报 `2 ObjectDB instances were leaked` 与
`1 resources still in use at exit`（疑似退出瞬间仍在播放的 AudioStreamPlayer / Tween），
不影响运行，未定位。

## 2. 窗口验证（真实渲染）

`& $godot --path $preview -- --shots` 输出 9 张 1280×800 截图到
`user://gulu_shots`，本轮已复制到 `docs/shots/`。

脚本会为每张图打印 `SHOTMETA`，记录奶龙/玩家是否在屏幕内、燃料状态、装货计数：

```
01_opening_pad             dragon (645,456) 在屏内   fuels=dragon,free,free
02_windup                  dragon (640,465) 在屏内   蓄势
03_pounce_release          fuels=thrown              已张嘴（燃料在空中）
04_bay_after_release       loaded=1                 入仓成功
05_carry_first_person      fuels=...,player         第一人称抱货
06_third_person_player     player (640,429) 在屏内   第三人称看模型
07_dragon_face_with_fuel   dragon (640,518) 在屏内   叼货正面
08_dragon_miss_faceplant   dragon (640,502) 在屏内   恢复/脸着地
09_loading_bay_wide        （奶龙故意不在画面）        装货口全景
```

亮度体检（`python tools/inspect_shot.py docs/shots/xx.png`）：

| 图 | mean | 过曝>0.94 |
| --- | --- | --- |
| 01 开场 | 0.48 | 0.8% |
| 02 蓄势 | 0.48 | 0.8% |
| 03 扑击释放 | 0.56 | 10.4% |
| 04 入仓后 | 0.55 | 1.3% |
| 05 抱货 | 0.35 | 1.0% |
| 06 第三人称 | 0.47 | 1.1% |

03 偏高是船体正面受光 + 近景，属于可接受范围；下一轮如果想压，调
`gulu_app._build_environment()` 的 `tonemap_exposure`。

## 3. 未验证

- **真人手动操作**：没有真人完整玩过；所有手感结论均为自动/截图推断。
- 鼠标观察的实际灵敏度：headless 跳过；窗口模式只验证参数与构图。
- 音效听感：只验证文件存在与播放调用，没有听过。
- 多人：无联网代码，不声称已验证。
- 长时间运行、内存、多次重开后的资源泄漏：未做。

## 4. 真人试玩脚本（约 5 分钟）

1. **0:00 开场**：先别动，看看前面。能认出「一只奶龙嘴里叼着一罐燃料」吗？
   能看出右边那条是飞船装货口吗？
2. **0:30 自己搬**：按 E 抱起最近的一罐，沿青色地面导引条绕到船头，走进装货口。
   计数变成 1/3 了吗？路上奶龙有来抢吗？
3. **1:30 挑衅**：对着奶龙按 Q 三次。它有没有明显「注意到 → 靠近 → 压低身体」？
   预警出来时你知道要躲吗？往哪躲？
4. **2:00 骗它送货**：让它叼着货，站到装货口正前方约 6~7 m，按 Q 到它蓄势，
   **蓄势时侧移一步**。燃料飞进仓了吗？没进的话知道自己哪一步错了吗？
5. **3:00 失误补救**：故意站太远或太偏，让燃料落在外面，捡回来再试一次。
   这一步烦不烦？
6. **4:00 被扑**：手上抱着货站在原地被扑一次。知道自己掉了什么、还有多久能捡吗？
7. **4:30 收尾**：把 3 罐装满，看完成提示，按 R。重开后有没有残留
   （燃料没归位、奶龙不叼货、计数不清零）？

### 试玩后要回答的四个问题

1. 你理解**为什么要挑衅它**吗？（它是障碍，也是工具）
2. **自己搬**和**骗它送**，两种都有使用价值吗？还是有一种是废的？
3. 失误之后，你**知道原因**吗？愿意再试一次吗？
4. 哪个**角色反应**最有趣？哪一段**等待**最无聊？

## 5. 已踩过的坑（避免重复）

- PowerShell `Get-Content/Set-Content` 会把 UTF-8 中文注释写坏（换行被吞），
  导致 GDScript 解析失败。**改脚本一律用编辑器/写入工具，不要用 PS 往返。**
- Jolt 不支持非均匀缩放的 SphereShape 碰撞体，会打警告并当成球形处理；
  岩石改用 BoxShape。
- 燃料入仓 Tween 不会随 `reset_to_home()` 自动停止，会把复位的燃料又拉回仓里；
  已在 `FuelProp.reset_to_home()` 里 kill。
- `_teleport(pos, _yaw_to(target))` 会在传送**前**算朝向，导致朝向错位；
  已改为 `_place_player(pos, target)`。
