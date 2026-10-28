# ASSETS — 奶龙 3D 素材查找记录

查找日期：2026-10-28。第三方文件只放在独立素材目录，**未导入游戏工程、未替换角色、未提交到公开仓库**。

## 方法

- 通用搜索接口本次多次超时；Bing 返回无关结果。
- 使用 Sketchfab 公开搜索 API：`https://api.sketchfab.com/v3/search?type=models&q=nailong` 与 `q=奶龙`。
- 逐个读取模型页的 license 标签与 API 元数据；未登录、未绕过付费/访问限制。

## 官方来源

- **第七印象文化传媒（深圳）有限公司**是官方 IP 方，官网：
  https://www.nailoong.com/ ，角色页：https://www.nailoong.com/ipStar/NaiLong/
- 官网只提供 IP 介绍、影视、出版物、品牌授权信息；本轮未找到官方公开 3D 模型下载。
- 官方 IP 与“模型文件许可”是两件事：即使拿到某个模型的 CC BY/Free Standard，
  也不等于取得奶龙角色形象的公开商用/发行授权。
- GitHub `Nailong-Studio/NaiLong-Universe` 是粉丝/艺术项目，不是第七印象官方；不要称其为官方模型。

## 公开可直接下载候选

- `scnuLwz/ai_work_proflie`：GitHub Release `v1/nailong.glb`，
  75,285,180 bytes，SHA256 `7853405f8e2c9271a99ca1dab48b6cb22dc8d0826a9ae2bd8f69008e9f4cff4a`。
  README 称其为 AI 生成模型；仓库**没有 LICENSE 文件**。
  已下载到独立目录 `C:\Users\31798\Documents\NailongAssets\scnuLwz_ai_work_proflie\`，未入游戏工程。
  外观/骨骼/材质/动画检查结果见 `BLENDER.md` 与本次反馈。
- `scnuLwz/talk-nailong-3d` 使用的是“奶蛙 GLB”，不是奶龙；不列入。
- 其余 GitHub 3D 奶龙项目多为程序化/网页游戏资产，未发现可复用的官方角色 GLB。

## 第三方/同人模型（需登录）

| 名称 | 作者 | 页面 | 格式/大小 | 动画 | 授权 |
| --- | --- | --- | --- | --- | --- |
| Nailong | The Boy Phase 5 (@okstepanova2012) | https://sketchfab.com/3d-models/nailong-d4617facf9574b45bc57c64e44497242 | GLB / glTF，GLB 约 1.83 MB，9,998 面，3 张 2048 贴图 | 0 | CC Attribution (CC BY 4.0) |
| 奶龙模型 | 78红米 | https://sketchfab.com/3d-models/d7a3f20de4e4486182806c40699d26d4 | GLB，约 256 KB，8,334 面 | 0 | Sketchfab “Free Standard” |
| 奶龙女孩 nailong lady | KDZBF | https://sketchfab.com/3d-models/nailong-lady-42e34ee1f457477caf871cab902d6952 | GLB，约 21.8 MB，509,654 面 | 1 | CC Attribution (CC BY 4.0) |

另有三条 Sketchfab 结果不可下载（`奶龙_爱给网_aigei_com`、`奶龙新年版`、
`Cute cartoon奶龙 dinosaur`），未列入可用候选。

## 实际下载与骨骼复核

- 三个候选页面都标 `isDownloadable=true`，但匿名请求
  `https://api.sketchfab.com/v3/models/<uid>/download` 返回 **HTTP 401**；
  实际下载需要登录，**未绕过**，也没有取得文件。
- 因此本轮**无法确认**它们是否包含骨骼、权重、动画轨道，或在 Blender 中能否直接编辑。
- “动画 = 0”**不等于**“不能用”：模型可能没有动画但有骨架，或有网格但需要重新绑定；
  这只能下载后在 Blender 里检查。不能仅凭 API 的 animationCount 排除。
- “奶龙女孩” API 显示 1 条动画、509,654 面、约 21.8 MB；可能带动画，但未取得文件，不能当作已验证。
- 授权：CC BY 4.0 / Sketchfab Free Standard 是上传者授权；**不当然包含奶龙 IP 的公开商用/发行权**。

## 结论

- 有可下载的 GLB/glTF 候选，但没有**已验证**同时满足“骨骼/可编辑 + 足够动画 + 明确可公开发布”的模型。
- CC BY / Free Standard 是上传者给模型的授权，**不当然包含奶龙 IP 本身的公开商用/发行权**；
  不能把“可下载”当作“允许公开发布”。
- 因此本轮继续使用**程序化占位奶龙**，行为与外观分离；没有把第三方模型放入仓库。
- 下一轮若采用候选：先登录取得文件 → Blender 检查网格/骨架/动画 → 确认 IP 与发行授权 →
  统一比例/朝向 → 导入独立测试场景，再决定是否替换占位。
- 推荐优先团队自制/明确授权模型；具体方案见 `BLENDER.md`。
