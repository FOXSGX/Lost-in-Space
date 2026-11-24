# ART-SAMPLE-002 游戏运行时子集

完整团队包在 `art-source/third-party/ART-SAMPLE-002_TEAM_KIT/`。
这里只保留游戏运行需要的 GLB、2K 贴图、shader 和材质入口。

- `hero_lib.gd` 已把 `res://shaders/`、`res://assets/textures/` 改成
  `res://assets/art-sample-002/shaders/` 与 `res://assets/art-sample-002/textures/`。
- 模型通过 `game/scripts/ruin_art_sample.gd` 实例化并按材质名覆盖。
- 已用于腐墟星能源站：
  - `aqs002_bell_crystal.glb`
  - `aqs002_console.glb`
  - `aqs002_press_static.glb`
- 其余 GLB 保留，供后续腐墟星/其他星球复用。
- 不要在这里直接改 GLB；源文件在 `art-source/.../02_BLENDER_SOURCE/`。
