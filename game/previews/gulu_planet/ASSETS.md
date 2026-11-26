# ASSETS — 奶龙星素材来源与许可记录

更新：2026-10-29。
原则：**未确认授权的素材不进公开仓库、不用于发布**；本轮所有新增资产均为本仓库自制。

## 1. 本轮新增（全部自制，可随仓库发布）

| 资产 | 路径 | 来源 | 许可 |
| --- | --- | --- | --- |
| **奶龙静态模型（本轮）** | `assets/characters/nailong.glb`、`tools/blender/nailong.blend` | 本仓库 `tools/blender/build_nailong.py` 程序化建模（Blender 4.5.15） | 随项目；未使用任何第三方模型/贴图 |
| 模型预览图 | `docs/model/nailong_{front,side,back,three_quarter,first_person}.png` | 同脚本 Cycles 渲染 | 随项目 |
| 3 个短音效 | `assets/audio/*.wav` | 本仓库脚本 `tools/audio/make_sfx.py` 用 Python 标准库合成（正弦/噪声 + 包络） | 随项目；无第三方素材 |
| 能源球 | `scripts/energy_ball.gd` | 程序化几何（球壳 + 发光核心 + 经线框 + 赤道灯带） | 随项目 |
| 装货口与飞船 | `scripts/collector.gd` | 程序化方块/圆柱拼装，配色参考本作飞船内部 | 随项目 |
| 场地、岩石、燃料、货箱 | `scripts/gulu_app.gd` | 程序化几何 | 随项目 |
| 截图 | `docs/shots/*.png` | 本机 Godot 4.7.2 窗口渲染 | 随项目（含占位角色） |

音效清单：

| 文件 | 用途 | 时长 |
| --- | --- | --- |
| `ball_kick.wav` | 踢球（低频咚 + 摩擦） | 0.16 s |
| `dragon_block.wav` | 奶龙拦球（闷响） | 0.24 s |
| `fuel_loaded.wav` | 入仓确认（两声上行） | 0.45 s |

重新生成：

```powershell
python tools\audio\make_sfx.py assets\audio
```

（Godot 需要重新导入：`--headless --editor --quit` 一次即可。）

## 2. 主角模型（复用，不新造）

- `scenes/protagonist_visual.tscn` + `scripts/protagonist_visual.gd`
  + `assets/characters/protagonist_model.json` + `assets/characters/skins/skin_ranger.glb`
- 来源：本作正式项目（GitHub `42519ff`）同一套资源。
- 本轮改动只有**缩放 0.78 → 1.0**，使其与飞船内部和其他星球一致
  （0.78 是共振星洞穴那一关的特例）。
- 因此玩家外观与其他星球、飞船里完全同源，不存在第二套角色模型。

## 3. 官方奶龙来源（仅记录，未使用）

- 第七印象文化传媒（深圳）有限公司是官方 IP 方，官网 https://www.nailoong.com/ ，
  角色页 https://www.nailoong.com/ipStar/NaiLong/
- 官网只提供 IP 介绍、影视、出版物、品牌授权信息；**没有找到官方公开 3D 模型下载**。
- 官方「角色形象授权」与「模型文件许可」是两件事，即使拿到某个模型的
  CC BY / Free Standard，也不等于取得奶龙角色形象的公开发布授权。
- GitHub `Nailong-Studio/NaiLong-Universe` 是粉丝/艺术项目，不是第七印象官方；
  不称其为官方模型。

## 4. 公开可直接下载候选（已下载检查，未导入、未提交）

- `scnuLwz/ai_work_proflie`：GitHub Release `v1/nailong.glb`，
  75,285,180 bytes，SHA256 `7853405f...f4cff4a`。
  README 称其为 AI 生成模型；仓库**没有 LICENSE 文件**。
  已下载到仓库外 `C:\Users\31798\Documents\NailongAssets\scnuLwz_ai_work_proflie\`。
  Blender 4.5.15 检查：1 个 mesh、846,783 顶点 / 1,499,676 三角面；
  **无骨骼、无 vertex group、无动画**；1 材质 + 3 张 4096 PBR 贴图；
  高 1.089 m，脚底 z≈0。属静态 AI 网格，需要重拓扑/减面/绑骨。
  仅内部参考，**不入库、不发布、不替换角色**。
- `scnuLwz/talk-nailong-3d` 用的是「奶蛙 GLB」，不是奶龙；不列入。

## 5. 第三方同人模型（需登录，未取得文件）

| 名称 | 作者 | 格式/大小 | 动画 | 授权 |
| --- | --- | --- | --- | --- |
| Nailong | The Boy Phase 5 | GLB 约 1.83 MB，7,998 面 | 0 | CC BY 4.0 |
| 奶龙模型 | 78红米 | GLB 约 256 KB，1,334 面 | 0 | Sketchfab Free Standard |
| 奶龙女孩 nailong lady | KDZBF | GLB 约 21.8 MB，109,654 面 | 1 | CC BY 4.0 |

- 三个页面都标 `isDownloadable=true`，但匿名请求
  `https://api.sketchfab.com/v3/models/<uid>/download` 返回 **HTTP 401**；
  实际下载需要登录，**未绕过**，也没有取得文件。
- 因此无法确认它们是否包含骨骼、权重、动画轨道，或能否在 Blender 直接编辑。
- 「动画=0」不等于「不能用」：可能没有动画但有骨架，或有网格但需要重新绑定。
- 结论：本轮仍不导入第三方模型。

## 7. 奶龙模型（2026-10-30 自建，静态阶段）

- 结论：**没有可用的授权模型**。仓库外那个第三方 `nailong.glb`（71.8 MB，846k 顶点）无骨骼、无动画、**无 LICENSE**，
  且不属于官方发布素材，不能用于公开原型。Sketchfab 候选需登录，未取得。
- 因此本轮用 Blender **自建**：`tools/blender/build_nailong.py`
  - 身体/头/四肢/尾巴/耳朵 = 一条骨架曲线 + Skin 修改器 + Subdivision，**一个连续曲面**
    （18,880 三角面、0 条非流形边、无孤立顶点），不是互相穿插的球体。
  - 眼、嘴、舌、腮红、鼻孔是独立小件，位置由**射线检测贴合曲面**，不是手填坐标。
  - 面朝 Blender +Y（Godot 导入后 → -Z），脚底 z=0，高 1.728 m。
- 导出：`assets/characters/nailong.glb`（632 KB，13 个网格、30,400 三角面、9 种材质）。
- 可编辑源文件：`tools/blender/nailong.blend`（含影棚灯光/相机，可直接重渲）。
- 使用限制：这是本项目自制的“奶龙形象方向”角色，**不是**官方素材，也不能对外声称是官方奶龙。
- **当前状态（2026-10-30 深夜起）**：游戏内已改用 Sketchfab 的 `nailong_dl.glb`（CC-BY-4.0），
  本节的自建静态模型保留但不再使用；未绑骨骼、未接动画这两条仍然成立。
  若后续要发布，仍需解决角色 IP 授权（见第 3、4 节）。

## 8. 结论与下一轮建议

- 本轮所有可见内容都是本仓库自制或本作既有资源，可以随预览分支提交。
- 图内角色为 Sketchfab `nailong`（CC-BY-4.0，需署名）；**没有**把「可下载」当成「有 IP 授权」，
  发布前仍需确认奶龙角色本身的 IP（见 D-35）。
- 下一轮二选一：
  1. 团队自建模：Blender 做低模 + 少量骨骼 + 5 段动作（注意/靠近/蓄势/叼货/扑空），
     导出 GLB（Blender Z-up、脚底 z=0；Godot 验证 Y-up、面朝 −Z）；
  2. 使用已确认 IP 与发布授权的模型：下载后在 Blender 检查网格/骨架 →
     重定向动作 → 统一比例 → 先进独立测试场景。
- 无论哪种，模型与碰撞体必须分离，扑击位移继续由行为控制。

## 9. 环境美术升级素材（2026-11-18）

| 资产 | 路径 | 来源 | 许可/状态 |
| --- | --- | --- | --- |
| 分层金属/涂装/混凝土 shader | `shaders/aqs2_metal.gdshader` | `ART-SAMPLE-002_TEAM_KIT/04_MATERIAL_LIBRARY/shaders/`，团队素材包 | 随本仓库/团队包；**未复制任何贴图、GLB、场景或工程配置** |
| 层理岩石 shader | `shaders/aqs2_rock.gdshader` | 同上 | 同上 |
| 倒角盒/门拱/低多边形岩体 | `scripts/gulu_art_kit.gd` | 本仓库运行时程序化生成 | 随项目 |
| 地面/门框/货箱/灯光 | `scripts/nailong_environment.gd`、`collector.gd` | 本仓库程序化几何 + 上述 shader | 随项目 |
| 球外观 | `scripts/energy_ball.gd` | 本仓库程序化几何（只改材质与发光强度） | 随项目 |

说明：

- 包内 `06_REFERENCE`、`05_ART_STYLE_GUIDE`、`04_MATERIAL_LIBRARY` 只作为**参考方法**阅读，
  没有把示例工程、机械设备或水晶复制进本游戏。
- 材质 shader 使用世界坐标噪声，不依赖 2K 贴图；因此仓库体积没有因本轮增加贴图。
- 视觉验收仍需人工看图：本环境无法查看图片；截图与对照图已放在 `docs/shots/`、
  `docs/art_baseline/`、`docs/art_compare/`。

## 10. 奶龙模型替换（2026-11-18 二次修正）

- **当前使用**：`assets/characters/nailong.glb`（本仓库 `tools/blender/build_nailong.py`
  程序化建模，18,880 tris，0.961×1.01×1.728 m，14 个网格，无骨架）。
- **已弃用**：`assets/characters/nailong_dl.glb`（Sketchfab "nailong" by RED ANGRY BIRDS，
  CC-BY-4.0）。文件与 LICENSE 保留在仓库中以便追溯，但游戏不再引用。
  弃用原因：225 根 Rigify 骨的局部轴与代码假设不一致，按世界轴旋转会造成四肢/脖子变形。
- `nailong.glb` 只做整体节点动画（bob/前倾/横摆），不做骨骼旋转；不会出现脖子/四肢被拧长。
- 本地视觉审阅模型 Qwen2-VL-2B 在仓库外 `C:\Users\31798\Models\`，
  审阅脚本在 `workspace/tools/`，**不随游戏提交**。

## 11. 奶龙模型回退（2026-11-18 晚）

- 用户指出：当前自建 `nailong.glb` 不是他原来给的形象；要求恢复经典奶龙。
- **当前使用恢复为 `assets/characters/nailong_dl.glb`**（Sketchfab "nailong" by RED ANGRY BIRDS，CC-BY-4.0）。
- 保留运行时清理：移除 GLB 内残留的 `Icosphere` 占位球；**不做任何骨骼姿态旋转**
  （头/颈/四肢全部保持 glTF 静置姿态），只做整体节点 bob/前倾/横摆。
- `nailong.glb`（本仓库自建）保留为可编辑源文件，但不再被游戏引用。
- 自审：Qwen2-VL 近景确认“像经典黄色奶龙，头身比例/四肢/脸正常，脖子无拉长/压扁/扭曲/穿模”。

## 12. 复用其他星球模型的场景装饰（2026-11-23）

按用户要求，环境美术改为**直接复用同一仓库里其他星球预览的成品模型**，
不再只靠运行时程序化几何。全部素材均为本仓库自建资产（Blender 源文件在
`art-source/editable/resonance/`），只复制、不修改；运行时只覆盖材质颜色。

| 新资产（`game/previews/gulu_planet/assets/props/`） | 来源 | 许可 | 用途 |
| --- | --- | --- | --- |
| `resonance_cave_rock_wall.glb`（150 KB） | `game/assets/resonance/models/cave_rock_wall.glb` | 本仓库自建 | 边界外崖壁 ×4 |
| `resonance_cave_stalactite.glb`（13 KB） | 同上 `cave_stalactite.glb` | 本仓库自建 | 外围尖石 ×5 |
| `resonance_cave_ore_crystal.glb`（20 KB） | 同上 `cave_ore_crystal.glb` | 本仓库自建 | 自发光矿石晶簇 ×6 |
| `resonance_support_safety_gate.glb`（3.1 MB） | 同上 `resonance_support_safety_gate.glb` | 本仓库自建 | 西侧场站大门 |
| `resonance_drone_dock.glb`（3.3 MB） | 同上 `resonance_drone_dock.glb` | 本仓库自建 | 东墙外无人机坪 |
| `resonance_reactor_tower.glb`（4.0 MB） | 同上 `resonance_reactor_tower.glb` | 本仓库自建 | 远处天际线（30 m） |

- 加载与摆位：`scripts/gulu_asset_dressing.gd`；挂载点
  `nailong_environment.gd::_build_imported_dressing()`。
- 不引入任何第三方新增素材；Kenney 的 CC0 套件（`art-source/third-party/kenney/`）本轮未使用，
  避免卡通比例与现有写实工业风冲突。
- 验证：自测 45/0；`tools/probe_dressing.gd` 确认所有装饰贴地且不侵入球路/出生点；
  详见 `docs/ART_PASS_2026-11-23.md`。
