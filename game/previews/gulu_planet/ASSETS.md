# ASSETS — 奶龙星素材来源与许可记录

更新：2026-10-29。
原则：**未确认授权的素材不进公开仓库、不用于发布**；本轮所有新增资产均为本仓库自制。

## 1. 本轮新增（全部自制，可随仓库发布）

| 资产 | 路径 | 来源 | 许可 |
| --- | --- | --- | --- |
| 5 个短音效 | `assets/audio/*.wav` | 本仓库脚本 `tools/audio/make_sfx.py` 用 Python 标准库合成（正弦/噪声 + 包络） | 随项目；无第三方素材 |
| 奶龙外观 | `scripts/milk_dragon_visual.gd` | 程序化生成（球体/圆柱/圆环），按奶龙形象方向手工调参 | 随项目；非官方模型 |
| 装货口与飞船 | `scripts/collector.gd` | 程序化方块/圆柱拼装，配色参考本作飞船内部 | 随项目 |
| 场地、岩石、燃料、货箱 | `scripts/gulu_app.gd` | 程序化几何 | 随项目 |
| 截图 | `docs/shots/*.png` | 本机 Godot 4.7.2 窗口渲染 | 随项目（含占位角色） |

音效清单：

| 文件 | 用途 | 时长 |
| --- | --- | --- |
| `dragon_notice.wav` | 奶龙注意到你 | 0.20 s |
| `dragon_windup.wav` | 蓄势预警 | 0.55 s |
| `fuel_release.wav` | 张嘴 / 燃料脱口 | 0.40 s |
| `fuel_loaded.wav` | 入仓确认 | 0.45 s |
| `dragon_chomp.wav` | 叼走燃料 | 0.18 s |

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

## 6. 结论与下一轮建议

- 本轮所有可见内容都是本仓库自制或本作既有资源，可以随预览分支提交。
- 奶龙形象仍是程序化占位；**没有**把「可下载」当成「有 IP 授权」。
- 下一轮二选一：
  1. 团队自建模：Blender 做低模 + 少量骨骼 + 5 段动作（注意/靠近/蓄势/叼货/扑空），
     导出 GLB（Blender Z-up、脚底 z=0；Godot 验证 Y-up、面朝 −Z）；
  2. 使用已确认 IP 与发布授权的模型：下载后在 Blender 检查网格/骨架 →
     重定向动作 → 统一比例 → 先进独立测试场景。
- 无论哪种，模型与碰撞体必须分离，扑击位移继续由行为控制。
