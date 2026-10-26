# 太空舱 Blender 美术优化

日期：2026-10-22。范围：用户要求使用 Blender 优化太空舱美术；沿用此前已选择的精致卡通风格，不改变舱内玩法。

## 资源接入

- 原始资产保留：`assets/ship-hub/ship_hub.glb`。
- 新运行资产：`assets/ship-hub/ship_hub_blender_v2.glb`。
- 原生原稿：`art-source/editable/spaceship-cabin/blender-v2/ship_hub.blend`。
- 重建脚本与来源记录：同目录 `build_blender.py`、`README.md`。
- 运行绑定：`scripts/ship_hub_3d.gd` 的 `MODEL` 常量。

新版强化地面分区、低位导向、墙面层次、观察窗边框、星图台投影和原设施细节；主舱尺寸、相机、设施位置和碰撞保持原有规则。特殊星空窗及气闸裁切命名保留。

## 输出统计

| 项目 | 原版 | Blender 优化版 |
| --- | --- | --- |
| 运行网格数 | 634 | 109 |
| 三角面数 | 149,572 | 217,276 |
| GLB 文件大小 | 12,090,772 字节 | 4,703,104 字节 |

通过焊接顶点与按功能区/材质合并，GLB 体积减少约 61%。细节和圆角增加了三角面数；本轮没有进行帧时间基准测试，不宣称帧率提升。原生 `.blend` 保留 911 个可编辑网格，游戏用导出采用合并版本。

## 验证

- Godot 4.7.2：编辑器导入和主舱场景无头启动通过，日志未发现解析或加载错误。
- `res://tests/ship_hub_integration.gd`：39 项检查通过，覆盖跟随镜头、所有设施可达性、碰撞、存取、维修、补给、登陆和返航。
- 实际 OpenGL Compatibility 渲染：核对中央星图、维修区、储物区、舰桥和整舱视图；未出现错误日志。窗口输出设置为 1440×900，实际 viewport 截图为 1440×810。
- 星空窗的 `panorama_glass` 仍被程序星空 Shader 正确替换，近侧气闸仍按原规则隐藏。
- 未执行新试玩包导出，也未进行四人性能验收。

实机截图保存于原稿目录：`godot-center.png`、`godot-workshop.png`、`godot-bridge.png`、`godot-overview.png`。`blender-overview.png` 为摄影棚渲染，光照与实机不同。

本地原始日志与验证凭据：`work/ship-art-20261022/`。本轮只修改主舱模型绑定、增加新版资产与说明；已有未提交的其他导入设置、`project.godot` 变化和测试 UID 保留。
