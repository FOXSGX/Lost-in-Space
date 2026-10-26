# 共振星矿车停靠站：独立技术预览 01

这是与正式关卡隔离的 Godot 4.7.2 工程。上一级 `.gdignore` 防止正式项目扫描预览内容。没有自动挂入共振星，也没有修改正式场景或共享角色。

打开本目录 `project.godot` 并运行，按 **1 / 2 / 3 / 4** 切换入口、车侧、矿脉、回望四个机位。机位来自最终 Blender 场景，临时眼高为脚下表面上方 1.65m。当前是相机审阅器，不是角色移动、攀爬、停靠交互或多人玩法实现。

## 资源来源与用途

- 原始美术均来自本项目：已验收 V2.3 A 矿车、环境样板 02 岩壁 / 晶簇 / 轨道，以及本轮原创洞壳、地面、站台和少量工业设施。没有新增外部素材。
- 可编辑源：`art-source/editable/resonance/codex_mining_station_prototype_01/mining_station_01.blend`。
- 运行资源：`assets/mining_station_01.glb`，包含 71 个按材质 / 区域合并的网格、36 个材质、两张内嵌 1024² 颜色贴图。
- 两张共享颜色贴图同时保留在 `assets/textures/`，通过真实 Blender Cycles emission bake 生成；它们是临时可复用表面色块，不是最终全套 PBR 烘焙。
- 坐标使用标准 glTF Y-up 转换：Blender `(x,y,z)` → Godot `(x,z,-y)`。没有再追加一次旧管线的 90° 补偿。

## 材质边界

GLB 保存了基础贴图、几何法线和矿物 `COLOR_0`。本机导入后晶体材质的 `vertex_color_use_as_albedo` 默认为 false，且 glTF 不能表示“顶点色连接到发光输入”。因此 `station.gd` 显式开启顶点色并赋予青蓝 / 紫色发光颜色，驱动四个矿物材质做缓慢脉冲。岩石使用原生三向投影修正逐面 UV 接缝。

Compatibility 下的点光源近似 Blender 的宽面光。当前未实现 Eevee 等价的间接光、软阴影、金属微表面和程序凹凸。不要把技术预览当作已经通过最终运行时美术验收。

## 验证

最终 `capture.gd` 实际运行 OpenGL Compatibility，回放四个视角输入，检查切换结果，保存六张真实 framebuffer PNG（四个机位 + 脉冲低 / 高）。输出目录由命令行 `--` 后的参数提供。

静态检查 4 个文件、0 加载失败、0 节点配置警告；linter 为 0 错误 / 0 警告。图形运行退出码为 0。沙箱不能写用户目录中的 Godot 编辑器配置和 shader cache，通用验证器因此记录 fail；原始失败记录保留，没有改写成 pass。实际项目资源导入、图形截图和输入回放另有独立日志。

