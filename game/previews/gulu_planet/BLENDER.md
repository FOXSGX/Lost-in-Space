# BLENDER — 美术制作环境与 GLB 管线验证

日期：2026-10-28
状态：已安装并验证 Blender → GLB → Godot 导入；本轮不制作正式模型、不替换奶龙。

## 0. 2026-10-29 更新（本轮）

- 管线未改动，也未新增 Blender 资产；`assets/test/blender_link_test.glb` 继续作为
  导入回归检查（F4 显示，headless 自检校验 4 个 mesh）。
- 奶龙本轮仍是**程序化占位**（`scripts/milk_dragon_visual.gd`，纯 Godot 图元），
  不是 Blender 资产；这样行为、碰撞与外观继续分离。
- 如果下一轮要做正式奶龙，导出规范不变：Blender 源文件 Z-up、脚底 z=0、
  面朝 +Y；导出 GLB 后在 Godot 验证 Y-up、脚底 y=0、面朝 −Z。
  参考高度：主角模型 1.65 m 眼高，奶龙建议 1.8~1.95 m、嘴部高度约 1.35 m，
  这样第一人称近距离能看清脸。
- 若加骨骼，只需满足：头（转头/低头）、下颌（张嘴）、四肢（走/扑）、尾（摆动）。
  不需要复杂面部系统；扑击位移继续由 `milk_dragon.gd` 控制，不做根运动。

## 0.5 2026-10-30：自建奶龙静态模型（本轮）

```powershell
$blender = "C:\Users\31798\AppData\Local\Programs\Blender Foundation\Blender 4.5\blender.exe"
$preview = "C:\Users\31798\Documents\GitHub\Lost-in-Space-gulu\game\previews\gulu_planet"

# 完整构建 + 5 张预览图（约 3-4 分钟，Cycles CPU）
& $blender --background --factory-startup --python "$preview\tools\blender\build_nailong.py" -- "$preview\tools\blender"

# 只重建资产不渲染（调试参数时用）
& $blender --background --factory-startup --python "$preview\tools\blender\build_nailong.py" -- "$preview\tools\blender" norender

# Godot 导入检查（网格数 / 三角面 / 脚底是否贴地）
$godot = "C:\Users\31798\Downloads\迷失太空\迷失太空\tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe"
& $godot --headless --import --path $preview
& $godot --headless --path $preview --script "res://tools/check_nailong_glb.gd"
```

### 几何方案（为什么不是“球拼的”）

- 骨架：30 个节点（脊柱/头/嗅/下顿/双耳/双臂/双腿/四节尾），用 **Skin 修改器** 生成管状表面，
  再叠 **Subdivision level 3** 平滑 → 一个连续、水密的曲面（18,880 三角面，0 非流形边）。
- 关节处不做布尔、不体素重网格：Skin 的交叉包络 + 细分就是连续的，不存在“球穿进另一个球”。
- 五官：先建好身体，再用 `obj.ray_cast` 从外向内找表面点，眼/嘴/腮红/鼻孔按命中点 + 法线摆放，
  所以不会浮空也不会陷进去。
- 材质分区：同一个曲面上按面中心位置/法线分配「奶油色身体 / 浅色肚皮与口鼻」，不是叠一个白色椭球。

### 自查（不是审美结论）

脚本会打印：

- `STATS`：顶点/三角面/非流形边/孤立点/包围盒；
- `VISIBLE`：从正前方逐个射线检测五官，确认每个部件都是“第一个被击中的物体”（没被头吞掉）；
- `NAILONG_GLB`（Godot 侧）：13 个网格、30400 三角面、脚底 y=0、面朝 -Z。

### 已知待确认（需要人看）

- 头是 Skin 交叉包络，横截面是“圆角方”，不像真球体那么圆；要不要再补一层 Cast/球形化，需要看图定。
- 耳朵目前是两个短锥；奶龙的耳朵形状可以是圆叶，需确认。
- 嘴目前是贴在外面的深色椭球（静态阶段），绑骨后要改成能真正张开的嘴腔/下颌。

## 1. 安装

- 机器原先没有 Blender（`where blender`、`winget list` 均无）。
- 从官方下载页安装 **Blender 4.5.15 LTS**（官方 Windows x64 ZIP，未使用第三方整合包）：
  - 来源：`https://download.blender.org/release/Blender4.5/blender-4.5.15-windows-x64.zip`
  - 官方 SHA256：`52dd02fd74877fa08e74b67d7854cf32468a232c02aaa19b6844c91285574f8d`
  - 本地校验：一致（`Get-FileHash`）
  - 压缩包：398,649,826 bytes
- 解压位置：
  `C:\Users\31798\AppData\Local\Programs\Blender Foundation\Blender 4.5\blender.exe`
- 版本/接口实测：
  - `Blender 4.5.15 LTS`（build 2026-10-22）
  - 自带 Python **3.11.15**
- 未安装 MCP 插件、未安装第三方 add-on；本流程不需要。

## 2. 测试资产

独立测试资源，不替换当前奶龙角色：

| 文件 | 作用 |
| --- | --- |
| `tools/blender/make_test_link.py` | Blender 无界面脚本：0.8 m 立方体 + 前/上/后标记 + 4 个材质，导出 GLB/.blend |
| `tools/blender/verify_test_link.py` | 把 GLB 重新导入 Blender，检查对象、尺寸、材质 |
| `tools/blender/blender_link_test.blend` | 可编辑 Blender 源文件（Godot 通过 `.gdignore` 忽略此目录） |
| `assets/test/blender_link_test.glb` | 导出的 GLB（约 151 KB），供 Godot 导入 |
| `assets/test/blender_link_test.json` | 导出元数据（Blender 版本、米制、对象包围盒、材质） |

生成命令：

```powershell
$blender = "C:\Users\31798\AppData\Local\Programs\Blender Foundation\Blender 4.5\blender.exe"
$script  = "<repo>\game\previews\gulu_planet\tools\blender\make_test_link.py"
& $blender --background --factory-startup --python $script
```

脚本结果：

- 对象：`Body`、`ForwardMarker`、`TopMarker`、`BackMarker`
- 材质：`BodyMat`、`ForwardMat`、`TopMat`、`BackMat`
- Blender 中主体尺寸 0.8 × 0.8 × 0.8 m，主体中心 z=0.4，**脚底 z=0**
- GLB 使用 Y-up；Blender +Y → Godot **−Z**，Blender +Z → Godot **+Y**

## 2.1 坐标规范（不要混用）

- **Blender 源文件：Z-up、米制。** 测试体在 Blender 中脚底位于 z=0，前向标记放在 +Y；
  这是美术源文件的坐标，不要把 Godot 的“面朝 −Z”直接当作 Blender 源坐标。
- **导出：glTF 2.0 / Y-up。** Blender 导出器做 Z-up → Y-up 转换。
- **Godot：Y-up。** 导入后 `Body` 中心 y=0.4、AABB 0.8，脚底 y=0；
  `ForwardMarker` 位于 z=−0.65，`TopMarker` 位于 y=0.92。
- **最终角色的验收顺序：** 先在 Blender 里按 Z-up 建好并让脚底 z=0；导出 GLB 后，
  在 Godot 里验证 Y-up、脚底 y=0、角色面向 −Z。不要在 Blender 源文件里硬套 Godot 轴向。

## 3. Godot 导入验证

预览入口脚本把 `assets/test/blender_link_test.glb` 实例化到 `(-4, 0, 2.5)`，
命名为 `BlenderLinkTest`，无碰撞、与奶龙分离；**默认隐藏，按 F4 才显示**。

headless 自测（`--headless -- --selftest`）实际检查：

- GLB 导入出 **4 个 MeshInstance3D**
- `Body` 局部 AABB = **0.8 × 0.8 × 0.8 m**，脚底 y=0
- `ForwardMarker` 在 Godot 的 **z = −0.65**（+Y 前向映射正确）
- `TopMarker` 在 Godot 的 **y = 0.92**（+Z 上方映射正确）
- `BodyMat` 材质导入，基色偏红/橙（`r > b`）
- 默认隐藏；F4 显示/隐藏；整体自测 `passes=38 failures=0`

说明：按“不强制打开窗口”，没有做窗口像素截图；以上是 Godot headless 实际导入/实例化/
节点与材质检查。

## 4. 奶龙模型复核

### 官方来源

- 官方 IP 方：第七印象文化传媒（深圳）有限公司，官网 https://www.nailoong.com/ ，
  角色页 https://www.nailoong.com/ipStar/NaiLong/ 。
- 官网只有 IP 介绍、影视、出版物、品牌授权；**没有找到公开的 3D 模型下载**。
- 官方“角色形象授权”与“模型文件许可”是两件事，不能互相替代。

### 已下载检查：scnuLwz / ai_work_proflie

- 来源：https://github.com/scnuLwz/ai_work_proflie/releases/tag/v1
- 文件：`nailong.glb`，75,285,180 bytes；SHA256 校验一致：
  `7853405f8e2c9271a99ca1dab48b6cb22dc8d0826a9ae2bd8f69008e9f4cff4a`
- 本地独立目录：`C:\Users\31798\Documents\NailongAssets\scnuLwz_ai_work_proflie\`
  （未进入游戏工程、未提交、未替换角色）。
- Blender 4.5.15 检查：
  - 1 个 mesh（`node_0`），846,783 顶点 / 1,499,676 三角面；
  - **无 armature、无 vertex group、无 action（0 骨骼 / 0 动画）**；
  - 1 个材质，3 张 4096×4096 PBR 贴图；
  - 世界包围盒：高约 **1.089 m**、宽 0.500 m、深 0.518 m，脚底 z≈0；
  - 静态 AI 生成网格；需要重拓扑/减面/绑骨才能用于行为动画。
- 渲染预览（Blender，非 Godot）：`nailong_preview.png` 在同目录。
- 授权：仓库**没有 LICENSE**，README 称 AI 生成模型；角色 IP 未授权。
  只做内部检查，不作为可发布素材。

### Sketchfab 候选

- 页面标 `isDownloadable=true`，但匿名下载 API 返回 **401**；实际下载需要登录，不绕过。
- 未取得文件，骨骼/可编辑性/动画质量未验证；`Nailong`、`奶龙女孩` 为 CC BY 4.0，
  `奶龙模型` 为 Sketchfab Free Standard。
- “没有动画”不等于“不能用”：可在 Blender 中绑骨/补动画；但没有合法文件与授权前不导入。

## 5. 推荐方案

1. 本轮继续用程序化占位奶龙，先验证玩法；不把第三方模型放进可发布构建。
2. 下一轮二选一：
   - 团队自制奶龙模型：Blender 中建低模、绑定骨骼、做 4 段动画（注意/靠近/蓄势/扑击/恢复），
     以 1 m ≈ 1 Godot 单位导出 GLB；或
   - 使用已确认 IP 与发行授权的模型：下载后在 Blender 检查网格/骨架、重定向动画、统一比例，
     记录作者、来源、许可证与修改。
3. 导出规范：Blender 源文件用 Z-up、脚底 z=0；导出 GLB 后在 **Godot** 中验证 Y-up、
   角色面向 **−Z**、脚底 y=0、材质使用 Principled BSDF；不要把这些 Godot 轴向要求
   直接写进 Blender 源文件。
   在 Godot 中用独立测试场景/调试开关验证 AABB、材质、朝向后再替换占位。
4. 不要把“可下载”当作“可公开发布”；IP 未明确前只在内部检查目录使用。

## 6. 本轮未做

- 未制作正式奶龙模型或动画。
- 未替换当前角色行为/第一人称控制器。
- 未安装 MCP 或第三方插件。
- 未强制打开窗口，因此没有新截图。
