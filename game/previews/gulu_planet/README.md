# 奶龙星 · 第一人称射门试玩

《迷失太空 / Lost in Space》第四颗星球「奶龙星」的**独立试玩预览**。
本轮玩法：**把球形燃料踢进飞船，奶龙会来抢球**。

> 目录名与分支名沿用上一轮（`gulu_planet` / `feature/gulu-planet-preview`），
> 只是兼容性命名，不代表正式星球接入。**未推送、未合并、未改正式航线与其他星球。**

## 这一关在玩什么

场地里只有一颗能源球，球门前站着一只奶龙。

1. 走近球（< 2.7 m）、大致朝向它，**左键踢出去**；
2. 球贴地滚动、逐渐减速，撞墙/门框/奶龙会反弹；
3. 奶龙看到球靠近就横移拦截，拦到就把球弹回场内；
4. 它只能在球门前来回，而且**射门瞬间会先扑出去、短暂不再修正** —— 打反方向就能过；
5. 球进了装货口内侧 → 「燃料已装载」，一球完成；
6. 按 R 再来一局。

它不会追你、不会伤害你、不会把球叼走。

上一版的「搬运燃料 + Q 挑衅 + 怒气 + 诱导扑击」已经退出当前流程，
代码留在 git 历史里（见 `BRIEF.md` 末尾的存档段）。

## 启动

```powershell
$godot = "C:\Users\31798\Downloads\迷失太空\迷失太空\tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe"
$preview = "C:\Users\31798\Documents\GitHub\Lost-in-Space-gulu\game\previews\gulu_planet"

& $godot --path $preview            # 正常试玩
& $godot --headless --path $preview -- --selftest   # 自动检查
& $godot --path $preview -- --shots # 生成截图到 user://gulu_shots
```

引擎：Godot 4.7.2。入口：`gulu_planet.tscn`，默认第一人称。

## 操作

| 按键 | 作用 |
| --- | --- |
| WASD | 移动 |
| Shift | 加速 |
| 鼠标 | 环视（**与飞船第一人称一致**：眼高 1.6 m、FOV 74°、俯仰 ±71.6°） |
| **左键** | 踢球（距离 ≤ 2.7 m、大致朝向球）；鼠标未锁定时第一下只锁鼠标，不出脚 |
| Tab | 切换第一/第三人称（第三人称只用于看角色模型） |
| R | 重开本局（玩家、球、奶龙、比分全部复位） |
| Esc | 释放鼠标（再点一下左键收回，不踢球） |
| F1 | 隐藏/显示左上说明 |
| F3 | 调试面板（球速、奶龙状态、装载数） |
| F4 | 显示/隐藏 Blender GLB 测试方块 |

## 与游戏其他部分的一致性

- **第一人称镜头逐值对齐飞船**（`game/scripts/space_player_3d.gd` @ `42519ff`）：
  `SHIP_EYE_HEIGHT 1.6`、`SHIP_FIRST_PERSON_FOV 74`、`SHIP_LOOK_SENSITIVITY 0.0020`、
  `SHIP_PITCH_LIMIT 1.25`、`near 0.05`，纵向旋转符号也一致（鼠标向下=低头）。
  这也顺手修掉了上一轮「低头看不见地面燃料」的问题。
- **玩家模型与飞船/其他星球同一套资源**：`scenes/protagonist_visual.tscn` +
  `assets/characters/skin_ranger.glb` + `protagonist_model.json`，缩放 1.0
  （共振星洞穴用的 0.78 是那一关的特例）。
- **场景配色对齐飞船内部**：暖灰壳体 `#9aa9a6`、深蓝绿结构 `#375967`、
  冷白环境光、琥珀 `#ffb347` 燃料、青色 `#3fd8ff` 提示光。

## 角色模型（2026-10-30 起）

- 游戏内当前用的是**正式模型** `assets/characters/nailong_dl.glb`（Sketchfab "nailong"，CC-BY-4.0，
  见 `assets/characters/nailong_dl_LICENSE.txt`）；程序化占位只在 GLB 缺失时回退。
- 自建资产（保留但不再使用）：`assets/characters/nailong.glb`（13 网格 / 30,400 三角面 / 9 材质）、
  可编辑源文件 `tools/blender/nailong.blend`，由 `tools/blender/build_nailong.py` 生成。
- 预览图（正交正/侧/背 + 3/4 + 游戏同参数第一人称）：`docs/model/`。
- 构建与校验命令见 `BLENDER.md` 第 0.5 节；来源与许可见 `ASSETS.md` 第 7 节。

## 目录

```
gulu_planet.tscn            入口
scripts/gulu_app.gd         关卡、踢球输入、HUD、自测/截图/录制
scripts/energy_ball.gd      能源球（滚动/减速/反弹/卡球自救）
scripts/milk_dragon.gd      守门员：跟球、拦截、弹回（不追玩家）
scripts/milk_dragon_model.gd  奶龙外观与迈步/拦球表演
scripts/collector.gd        飞船装货口（固定判定 + 指示灯 + 夹臂）
scripts/sfx.gd              3 个短音效（踢球/拦球/入仓）
scripts/station_player.gd   复用共振星独立预览控制器（第一人称镜头已对齐飞船）
assets/audio/*.wav          本地合成音效（见 ASSETS.md）
assets/characters/nailong_dl.glb 正式奶龙模型（当前使用，CC-BY-4.0）
assets/characters/nailong.glb   自建奶龙静态模型（保留，不再使用）
docs/shots/*.png            本轮窗口截图（7 张）
docs/record/*.mp4           脚本驱动的流程录像（非真人操作）
docs/model/*.png            角色四视图 + 第一人称预览
tools/blender/build_nailong.py  奶龙模型生成脚本（Blender 4.5）
tools/blender/nailong.blend     可编辑源文件
tools/record_video.py       帧序列 → MP4/GIF
tools/check_nailong_glb.gd      GLB 导入检查
```

## 验证

```
GULU SELFTEST SUMMARY passes=35 failures=0
```

自动检查覆盖：镜头参数与 WASD 位移、首屏三要素同屏、
**远距离踢不到 / 近距离可踢 / 方向跟镜头**、**减速与停球后再踢**、
**边界反弹**、**奶龙拦直线射门**、**不会连击 / 不会压死球**、
**打空当能进球**、**门框外侧不计分 / 不重复计分**、
**卡球自救**、完成横幅与 R 重开、旧玩法动作已移除。

窗口验证：`docs/shots/01..07*.png`；
流程录像：`docs/record/gulu_kick_loop.mp4`（**脚本驱动，不是真人**）。
真人试玩脚本：`TESTING.md` 第 4 节（约 5 分钟）。

## 明确没做

高空球 / 旋转球 / 重力弹跳、蓄力与特殊射门、体力、伤害与死亡、
多人联网、看台与计分赛、正式航线接入、其他星球改动。
