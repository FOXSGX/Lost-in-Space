# 奶龙星 · 第一人称装货试玩

《迷失太空 / Lost in Space》第四颗星球「奶龙星」的**独立试玩预览**。
本轮做成了可以由真人完整打完的一小关：**3 罐燃料 → 装进飞船 → 装货完成 → 按 R 重来**。

> 目录名与分支名沿用上一轮（`gulu_planet` / `feature/gulu-planet-preview`），
> 只是兼容性命名，不代表正式星球接入。**未推送、未合并、未改正式航线与其他星球。**

## 这一关在玩什么

奶龙贪恋燃料，也容易被挑衅。你有两种送货方法：

1. **安全搬运**：先把奶龙引开，自己抱起燃料走进船头装货口。
   路远、要绕石头；抱到它面前会被它一口抢走。
2. **冒险借力**：奶龙嘴里叼着燃料时，站到装货口前挑衅它 →
   它压低身体蓄势（**脚下会出现红圈**）→ 朝锁定的位置扑过来 → **你侧移出圈** →
   它一张嘴，燃料顺势飞进装货口。

奶龙不会帮你，它只是被你利用。

第一次玩的顺序（不用看说明书）：

- 出生点前方就有一罐：**先按 E 抱起、沿青色地标送到装货口**（这一罐奶龙不会来抢）。
- 第二罐在奶龙窝边：抱起它就会被看见、跟过来，**贴太近会被抢**。
- 第三罐开场就在奶龙嘴里：只能骗它扑，让它在舱口前张嘴。

- 蓄势开始时目标就已锁定，之后不追尾、不转弯；红圈就是“它要扑的地”。
- 没接住时燃料落地，**可以捡回来再试**，不会销毁。
- 被扑中不掉血、不死亡，只掉手上的燃料（有 1.25 s 恢复窗口去捡）。
- 装货口有漏斗斜面 + 固定容错判定 + 横向引导，不是像素级瞄准。

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
| **Q** | 挑衅奶龙（9 m 内、面向它、中间不能有遮挡；0.7 s 冷却） |
| **E** | 拾取 / 放下燃料 |
| Tab | 切换第一/第三人称（第三人称只用于看角色模型） |
| R | 重开本关（玩家、奶龙、燃料、计数全部复位） |
| Esc / 左键 | 释放 / 收回鼠标 |
| F1 | 隐藏/显示左上说明 |
| F3 | 调试面板（含奶龙状态与地面状态环） |
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

- 游戏内目前**仍是程序化占位**；新的自建静态模型已入库但未替换（等外观确认）。
- 自建资产：`assets/characters/nailong.glb`（13 网格 / 30,400 三角面 / 9 材质）、
  可编辑源文件 `tools/blender/nailong.blend`，由 `tools/blender/build_nailong.py` 生成。
- 预览图（正交正/侧/背 + 3/4 + 游戏同参数第一人称）：`docs/model/`。
- 构建与校验命令见 `BLENDER.md` 第 0.5 节；来源与许可见 `ASSETS.md` 第 7 节。

## 目录

```
gulu_planet.tscn            入口
scripts/gulu_app.gd         关卡、场地、HUD、自动化检查
scripts/milk_dragon.gd      奶龙状态机（含找燃料 / 叼货 / 扑击释放 / 卡住恢复）
scripts/milk_dragon_visual.gd  奶龙程序化外观与表演（当前仍在用）
scripts/fuel_prop.gd        燃料罐（拾取/携带/抛出/入仓）
scripts/collector.gd        飞船装货口（漏斗 + 容错判定 + 计数指示灯）
scripts/sfx.gd              5 个短音效
scripts/station_player.gd   复用共振星独立预览控制器（第一人称镜头已对齐飞船）
assets/audio/*.wav          本地合成音效（见 ASSETS.md）
assets/characters/nailong.glb   自建奶龙静态模型（尚未替换游戏外观）
docs/shots/*.png            本轮窗口截图
docs/model/*.png            角色四视图 + 第一人称预览
tools/blender/build_nailong.py  奶龙模型生成脚本（Blender 4.5）
tools/blender/nailong.blend     可编辑源文件
tools/check_nailong_glb.gd      GLB 导入检查
```

## 验证

```
GULU SELFTEST SUMMARY passes=66 failures=0
```

自动检查覆盖：镜头参数、玩家模型复用、移动与墙体碰撞、视角切换、
挑衅的距离/视线/朝向/冷却、**先靠近再蓄势**、**锁定红圈**、侧移躲开、
**借力投货入仓**、重复计数保护、自己抱货入仓、拾取/放下/掉落、
**看见你抱货 / 抢走燃料**、**舱内挑衅被拒绝**、奶龙找燃料、完成与重开。

窗口验证：`docs/shots/01..08*.png`（含三张关键画面：看见燃料 / 叼货蓄势 / 扑空入仓）。
真人试玩脚本：`TESTING.md` 第 4 节（约 5 分钟）。

## 明确没做

伤害/血量/死亡、永久损失、联网与多人验证、正式奶龙模型与第三方 IP 素材、
麦克风与语音、正式航线接入、其他星球改动。
