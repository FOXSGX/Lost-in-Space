# HANDOFF — 奶龙星预览

> 多日任务续点。新会话先读本文件，再读 `STATUS.md` / `TESTING.md`。
> 每次推进后更新「当前状态 / 下一步 / 恢复命令」，不要只依赖聊天记录。

最后更新：2026-11-10 00:5x（GMT+8）

## 快照

- 仓库：`C:\Users\31798\Documents\GitHub\Lost-in-Space-gulu`
- 分支：`main`（本轮**本地提交，不推送**）
- 最新提交：以 `git log -1 --oneline` 为准（本文件不绑定具体哈希）
- 预览目录：`game/previews/gulu_planet`
- 当前阶段：**抢货→引诱→扑空→借力装货** 已经是一段完整、可读、带喜剧反馈的循环
- 最新自测：`GULU SELFTEST SUMMARY passes=81 failures=0`
- 交付：`docs/shots/` 10 张、`docs/record/gulu_snatch_loop.mp4`（脚本驱动录制）

## 本轮（2026-11-10 凌晨）：抢货读感 + 借力反馈

用户方向：不新建工程、不加系统，把现有四拍（抢货—引诱—扑空—借力）做清楚、有挑战、有喜剧感。

**先核对的旧进度（避免重复实现）**：两条路线在 `nailong_environment.gd::_build_yard()` 里早就有了，
但原来只是两条发光色块条，**不影响碰撞、不影响视线、也不改变奶龙的路径选择**——
所以它们只是画了“两条路”，实际安不安全只取决于几何和奶龙的追人逻辑。
本轮没有重建路线，只把颜色箭头换成可读的地面痕迹，并给绕行线加了一处**真实遮挡**。

- 抢货：新增视线要求（`_last_los`）、预兆信号 `snatch_warning`（0.45 进度触发）、
  捡起保护 `snatch_pickup_grace=1.1 s`、预兆时长 0.75→0.95 s。
  依据：玩家步速 5.8 m/s，后退不到 1 m 就能在 0.95 s 内脱离 2.1 m 抢货半径。
- 表现：预兆时前倾/伸脖子/张嘴 + 低吼音 + HUD 进度条；扑空后 0.85 s 呆滞，
  头一歪盯着装货口（`set_dazed`），**不延长 1.25 s 恢复窗口**。
- 投货：飞行中地面光环放大高亮、灯提亮，落地恢复（`fuel_prop.gd`）。
- 入仓：机械夹臂 + 门框灯带 + `loaded` 音效 + 计数跳字，四件套同步。
- 环境：删掉两条彩色箭头，换成车辙/钢钉/拖痕；绕行线加货箱垤（有限遮挡）；
  窝里加 3 个压瘪燃料罐；舱口加内嵌底板。
- 音效：`make_sfx.py` 新增 `snatch_warn` / `stunned`，5→7 个。

## ⚠ 能力限制

**我无法在当前环境查看图片**（图像查看控件缺依赖）。角色好不好看只能由用户看
`docs/model/nailong_*.png` 判断；我只能给几何指标和屏幕坐标类证据。
不要再用亮度/色块统计冒充审美结论。

## 这一轮（2026-10-30 晚）：场景美术第一步

用户调整方向：**人物制作暂停**（正式模型他之后自己提供；本轮不动比例/五官/骨骼/动画），
本轮只做环境，先交「布局 + 主要形体 + 基础配色 + 光照」，不铺满小装饰。

- 新增 `scripts/nailong_environment.gd`（`NailongEnvironment`，220 个 MeshInstance）：
  - **装货口**：0.7 m 厚门框立柱 + 上沿横梁 + 收起卷帘 + 橡胶缓冲块 + 防滑坡道与侧导轨
    + 外露液压夹臂（装货成功时向内一夹再复位，`on_loaded`）。
  - **三格装货指示灯**移到门框上沿（`collector.gd::_build_pips`），远处靠「亮了几格」读数。
  - **搬运场地**：压深停机坪 + 两条路线（青＝绕远、琥珀＝穿地盘）+ 边缘货箱堆 + 两盏工作灯。
  - **生物窝**：深色凹盘 + 抬起的边缘石、4 个被压扁的货箱、4 条拖拽痕迹、
    14 片散落包装、后侧挡板。
  - **地形**：四面隐形碰撞墙保持原坐标（边界不变），视觉换成土坡 + 12 组大轮廓岩脊 + 远景岩层。
  - **燃料罐**重做：罐体 / 加强筋 / 提手 / 阀轮 / 接口 / 双面能量窗 / 底座脚，
    地面、手持、嘴挂三种距离都可读。
- 光照：舱口暖色工作灯（装货时闪一下）+ 窝区冷补光 + 两盏场地灯。
  过曝：01/03/04/07/08 ≤2.5%，02 6.8%，05 5.3%，06 10.0%
  （上一轮同类舱口图本来就是 7.5%，属同一量级）。
- 顺手修：`fuel_prop.gd` 的 `get_meta("intake_tween", null)` 每次复位都报错 → 改用 `has_meta`。
- 自测：`passes=68 failures=0`（新增 2 条场景检查：环境网格数、夹臂数量）。
- 截图 8 张在 `docs/shots/`；上一轮的 8 张移到 `docs/shots/round1_character_pass/`。

## 这一轮（2026-10-30 深夜）：换成正式奶龙模型

用户提供了 `Downloads/nailong.zip`（Sketchfab "nailong" by RED ANGRY BIRDS，CC-BY-4.0），
并明确「都授权，自己玩的项目」，所以直接把占位外观换成正式模型。

- 素材：9,998 tri / 6,125 vert / 1 材质 / 2048² 贴图 ×3（baseColor / normal / metallicRoughness）
  / 225 骨骼（Rigify 人形 biped）/ **0 动画** / 无下颅·尾巴·耳朵骨。
- `tools/blender/build_nailong_dl.py` 做了三件事（可重跑）：
  删掉 Sketchfab 的占位球、把 T-pose 手臂放下 50° 并 **烘成 rest pose**、7 层 UV 合 1 层，
  导出 `assets/characters/nailong_dl.glb`（1.60 MB，贴图内嵌，无动画）。
- 新外观层 `scripts/milk_dragon_model.gd`（接口与 `milk_dragon_visual.gd` 完全一致）：
  - 模型朝 +Z、脚底 y=-0.072 → 外层绕 Y 转 180°、整体抬 0.072，脸朝 -Z 并踩地；
  - 头部用 `DEF-spine.006` 骨骼做转头/低头，脖子 `DEF-spine.005` 跟一点，
    手臂 `DEF-upper_arm.*` 做小摆动；腿骨不动（避免破坏接地）；
  - 没有下颅骨，所以「张嘴」用 **头部下压 + 整体挤压** 代替，罐子仍挂 `MouthAnchor`；
  - 上头不改贴图，只叠暖色（albedo_color 相乘）。
- `gulu_app.gd` 改成 `_make_dragon_visual()`：GLB 在就用新外观，不在就回退程序化占位。
- 自测新增两条：嘴部挂点在前方（dot=1.00）、高度 1.36 m → `passes=70 failures=0`。
- 截图 8 张已按新模型重拍（`docs/shots/`）；模型四视图在 `docs/model/dl_nailong_posed_*.png`。
- 授权文本：`assets/characters/nailong_dl_LICENSE.txt`（CC-BY-4.0，需署名）。
  注意 CC-BY 只覆盖这个 3D 模型本身，不转移奶龙角色的 IP；公开发布前仍需确认。

## 角色模型

- 游戏内当前用的是**正式模型** `assets/characters/nailong_dl.glb`；
  自建的静态模型 `assets/characters/nailong.glb` 与 `tools/blender/nailong.blend` 保留但不再使用。
- 程序化占位 `milk_dragon_visual.gd` 仍保留，作为 GLB 缺失时的回退。

## 下一步（按优先级）

1. **真人走一遍 `TESTING.md` 第 4 节**：重点看抢货预兆够不够看得见、0.95 s 够不够反应、
   呆滞 0.85 s 会不会拖慢节奏。真觉得烦就把 `snatch_delay` 降到 0.8，
   或把 `snatch_pickup_grace` 降到 0.8。
2. 看 `docs/shots/09_snatch_telegraph.png`：奶龙离镜头 1.4 m，若头部被屏幕下沿切掉，
   就把 `_run_shots` 里的站位往后退 0.6 m。
3. 看 `docs/record/gulu_snatch_loop.mp4`：确认“借力送货”全程能看懂。
4. 若想让借力更有变化：可让奶龙空嘴时也被燃料位置吸引（双向博弈），本轮未做。

## 已知问题（玩法层）

1. 抢货强度仍是数值验证（0.95 s / 2.1 m / 1.1 s 保护），没有真人手感确认。
2. 借力送货的“命中姿势”仍偏单一：几乎总是“舱口前 4 m → 侧移”。
3. 绕行线的遮挡只有一处（货箱垤），奶龙会绕过来——这是有意的“有限遮挡”；
   若真人觉得太弱，可在绕行线中段再加一处矮岩。
4. 退出时 Godot 报 2 个 ObjectDB 泄漏 + 1 个资源未释放（老问题，不影响运行）。

## 恢复命令

```powershell
cd "C:\Users\31798\Documents\GitHub\Lost-in-Space-gulu"
git status --short
git log --oneline -5

$godot = "C:\Users\31798\Downloads\迷失太空\迷失太空\tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe"
$preview = "C:\Users\31798\Documents\GitHub\Lost-in-Space-gulu\game\previews\gulu_planet"

& $godot --headless --path $preview -- --selftest
& $godot --path $preview                 # 试玩
& $godot --path $preview -- --shots      # 截图到 user://gulu_shots

# 截图体检（看不见图片时用）
python tools\inspect_shot.py "<png>"
python tools\shot_map.py "<png>"
```

截图目录：
`C:\Users\31798\AppData\Roaming\Godot\app_userdata\Lost in Space - Nailong Planet Preview\gulu_shots`

## 不要做

- 不把第三方奶龙模型放进公开仓库或可发布构建；不把「可下载」当成「有 IP 授权」。
- 不改其他星球、正式航线、公共系统。
- 不 push/merge，除非用户明确要求。
- 不误提交工作区里预存的 `.gitignore`、`docs/design/...`、`game/docs/week1-member1.md` 修改。
- 不用 `Get-Content`/`Set-Content` 在**未显式指定 UTF8** 的情况下往返改脚本（会写坏中文）；
  中文脚本优先用编辑器工具改。

## 更新规则

每次会话结束前至少写清：

- 完成：文件/提交/测试结果；
- 下一步：一个具体动作；
- 阻塞：需要用户决定的事项；
- 恢复：准确路径与命令。
