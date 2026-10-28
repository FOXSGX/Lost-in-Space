# ASSETS — 奶龙 3D 素材查找记录

查找日期：2026-10-28。只记录公开可访问的候选，**没有下载或导入任何第三方模型**。

## 方法

- 通用搜索接口本次多次超时；Bing 返回无关结果。
- 使用 Sketchfab 公开搜索 API：`https://api.sketchfab.com/v3/search?type=models&q=nailong` 与 `q=奶龙`。
- 逐个读取模型页的 license 标签与 API 元数据；未登录、未绕过付费/访问限制。

## 候选

| 名称 | 作者 | 页面 | 格式/大小 | 动画 | 授权 |
| --- | --- | --- | --- | --- | --- |
| Nailong | The Boy Phase 5 (@okstepanova2012) | https://sketchfab.com/3d-models/nailong-d4617facf9574b45bc57c64e44497242 | GLB / glTF，GLB 约 1.83 MB，9,998 面，3 张 2048 贴图 | 0 | CC Attribution (CC BY 4.0) |
| 奶龙模型 | 78红米 | https://sketchfab.com/3d-models/d7a3f20de4e4486182806c40699d26d4 | GLB，约 256 KB，8,334 面 | 0 | Sketchfab “Free Standard” |
| 奶龙女孩 nailong lady | KDZBF | https://sketchfab.com/3d-models/nailong-lady-42e34ee1f457477caf871cab902d6952 | GLB，约 21.8 MB，509,654 面 | 1 | CC Attribution (CC BY 4.0) |

另有三条 Sketchfab 结果不可下载（`奶龙_爱给网_aigei_com`、`奶龙新年版`、
`Cute cartoon奶龙 dinosaur`），未列入可用候选。

## 结论

- 有可下载的 GLB/glTF 候选，但**没有一个同时满足**“带骨骼 + 足够行为动画 + 明确可公开发布”。
- CC BY / Free Standard 是上传者给模型的授权，**不当然包含奶龙 IP 本身的公开商用/发行权**；
  不能把“可下载”当作“允许公开发布”。
- 因此本轮继续使用**程序化占位奶龙**，行为与外观分离；没有把第三方模型放入仓库。
- 若团队决定采用某个模型，需要先确认 IP/发行授权与动画方案，再导入并记录来源。
