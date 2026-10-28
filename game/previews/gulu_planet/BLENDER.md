# BLENDER — 美术制作环境与 GLB 管线验证

日期：2026-10-28
状态：已安装并验证 Blender → GLB → Godot 导入；本轮不制作正式模型、不替换奶龙。

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

详细候选与许可见 `ASSETS.md`。本轮重新确认：

- Sketchfab 页面标 `isDownloadable=true`，但匿名访问
  `https://api.sketchfab.com/v3/models/<uid>/download` 返回 **401**；
  实际下载需要登录，不能绕过。
- 因未取得文件，**骨骼是否存在、是否可在 Blender 中编辑、动画轨道质量均未验证**。
- “没有动画”不等于“不能用”：0 动画的模型仍可能在 Blender 中绑定骨骼/制作动画；
  但需要先取得合法文件并检查网格/骨架。
- 授权：`Nailong`、`奶龙女孩` 为 CC BY 4.0；`奶龙模型` 为 Sketchfab Free Standard。
  这些是上传者授权，**不当然包含奶龙 IP 的公开商用/发行权**。

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
