# HANDOFF — 奶龙星预览

> 多日任务续点。新会话先读本文件，再读 `STATUS.md` / `TESTING.md`。
> 每次推进后更新「当前状态 / 下一步 / 恢复命令」，不要只依赖聊天记录。

最后更新：2026-10-30 00:20（GMT+8）

## 快照

- 仓库：`C:\Users\31798\Documents\GitHub\Lost-in-Space-gulu`
- 分支：`feature/gulu-planet-preview`
- 最新提交：以 `git log -1 --oneline` 为准（本文件不绑定具体哈希）
- 预览目录：`game/previews/gulu_planet`
- 当前阶段：**角色静态模型已完成，等用户看 `docs/model/` 的图确认外观后再绑骨**
- 最新自测：`GULU SELFTEST SUMMARY passes=66 failures=0`（玩法未改）
- 未 push、未 merge

## ⚠ 能力限制

**我无法在当前环境查看图片**（图像查看控件缺依赖）。角色好不好看只能由用户看
`docs/model/nailong_*.png` 判断；我只能给几何指标和屏幕坐标类证据。
不要再用亮度/色块统计冒充审美结论。

## 这一轮（角色静态）

- 第三方 `nailong.glb`（仓库外 71.8 MB）无骨骼、**无 LICENSE** → 不能用；无其他可用授权模型。
- 自建：`tools/blender/build_nailong.py`
  - 身体/头/四肢/尾巴/耳朵 = 骨架 + Skin + Subdivision → 一个连续水密曲面
    （18,880 tri、0 非流形边），不是球体拼接；
  - 五官用射线检测贴合表面（眼/瞳/高光/嘴/舌/腮红/鼻孔）；
  - 曲面内分「奶油色 / 浅色肚皮口鼻」两个材质区；
  - 面朝 Blender +Y、脚底 z=0、高 1.728 m。
- 产物：`assets/characters/nailong.glb`（632 KB）、`tools/blender/nailong.blend`、
  预览图 `docs/model/nailong_{front,side,back,three_quarter,first_person}.png`。
- 检查：Godot 导入 13 网格 / 30,400 tri / 脚底 y=0 / 面朝 -Z；
  正前方射线逐个命中五官。
- **未做**：骨骼、动画、游戏内替换。

## 下一步（按优先级）

1. **用户看 `docs/model/` 四视图 + 第一人称图**，确认：轮廓/头身比例/脸/嘴/四肢连接/材质。
   要改的地方直接说（例如“头再圆一点/耳朵换圆叶/嘴再大一点/腿再短”）。
2. 改完静态后再进入绑定：`Armature` 至少包含 root / hips / spine / head / jaw / 四肢 / tail，
   权重用自动权重 + 手动微调嘴周；动作只做 5 段（注视、张嘴叼货、蓄势、扑击、恢复）。
3. 绑定完成后再替换 `milk_dragon_visual.gd` 的外观（行为与碰撞不动），
   并检查：嘴部挂点、舋料穿透、脚底接地、第一人称可读性。

## 建模需要改的候选（我看不到图，以下是从几何指标推测的）

1. 头部横截面是“圆角方”（Skin 交叉包络所致），可能不够圆——可加 Cast/球形化或直接用球体起手。
2. 耳朵是两个短锥，奶龙更常见的是圆叶状耳朵。
3. 嘴目前是贴在外面的深色椭球（静态占位），绑骨后必须换成可张开的下顿/嘴腔。

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
