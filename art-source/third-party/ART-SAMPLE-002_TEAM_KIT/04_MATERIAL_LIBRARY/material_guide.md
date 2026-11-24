# 材质库索引（MATERIAL LIBRARY）

| 内容 | 位置 | 说明 |
|---|---|---|
| 三条 shader | `shaders/aqs2_metal|rock|crystal.gdshader` | v2：2K 多尺度 + UV 烘焙件分支 + 混凝土模式 |
| 旧版 shader（对照） | `shaders/aqs_*.gdshader` | ART-SAMPLE-001 的 v1，保留以便对比迁移 |
| 2K 贴图 | `textures_2k/` | 5 族 ×（法线 2K + 粗糙 2K + 掩膜 1K）+ 锤头烘焙图 |
| 环境预设 | `presets/aqs002_hero_environment.tres` | Compatibility 调平后的环境（ambient 1.45 / exposure 1.14） |
| 材质库代码 | `presets/hero_lib.gd` | **唯一的材质入口**：按 GLB 材质名 → ShaderMaterial |
| 参数规范 | `../05_ART_STYLE_GUIDE/材质与灯光规范.md` | 每组参数的取值与理由 |

## 最快上手

```gdscript
const LIB := preload("res://materials/hero_lib.gd")   # 或 04_MATERIAL_LIBRARY/presets/hero_lib.gd
var mats := LIB.new().build()
for mi in root.find_children("*", "MeshInstance3D", true, false):
    for s in range(mi.mesh.get_surface_count()):
        var key = mi.mesh.surface_get_material(s).resource_name
        if mats.has(key):
            mi.set_surface_override_material(s, mats[key])
```

## 导入设置（务必照做，否则显存与法线都会出问题）

| 文件 | compress/mode | compress/normal_map | mipmaps/generate |
|---|---|---|---|
| `*_normal.png` | 2 (VRAM) | 1 | true |
| `*_rough.png` / `*_mask.png` | 2 (VRAM) | 0 | true |
