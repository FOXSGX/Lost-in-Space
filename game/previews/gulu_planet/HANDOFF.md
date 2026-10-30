# HANDOFF — 奶龙星预览

> 多日任务续点。新会话先读本文件，再读 `STATUS.md` / `TESTING.md`。
> 每次推进后更新「当前状态 / 下一步 / 恢复命令」，不要只依赖聊天记录。

最后更新：2026-10-30 22:10（GMT+8）

## 快照

- 仓库：`C:\Users\31798\Documents\GitHub\Lost-in-Space-gulu`
- 分支：`feature/gulu-planet-preview`
- 最新提交：以 `git log -1 --oneline` 为准（本文件不绑定具体哈希）
- 预览目录：`game/previews/gulu_planet`
- 当前阶段：**环境美术第一步已完成，等用户看 `docs/shots/` 确认方向**（角色制作暂停）
- 最新自测：`GULU SELFTEST SUMMARY passes=68 failures=0`（玩法规则未改）
- 未 push、未 merge

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

## 角色制作（暂停）

- `assets/characters/nailong.glb` + `tools/blender/nailong.blend` 保留，不再改比例/五官/骨骼/动画。
- 游戏内继续用程序化占位外观（`milk_dragon_visual.gd`），保证玩法可测。
- 正式模型由用户之后提供；**不要把它当成本轮环境制作的阻碍**。

## 下一步（按优先级）

1. **用户看 `docs/shots/` 的 8 张图**，确认整体方向（配色 / 形体 / 构图 / 装货口辨识度）。
2. 只改他点出来的地方，仍不铺满小装饰。
3. 方向确认后第二阶段：材质细化、装货反馈动画、窝区细节、燃料罐近景。
4. 真人试玩：抢货是否恼人（`snatch_delay` / `snatch_distance`）。

## 已知问题（玩法层）

1. 抢货强度只在数值上验证过（2.1 m / 0.75 s），未体验是否恼人。
2. 借力送货几乎总是“舱口前 4 m → 侧移”。
3. 退出时 Godot 报 2 个 ObjectDB 泄漏 + 1 个资源未释放（不影响运行）。

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
