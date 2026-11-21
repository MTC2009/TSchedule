# TSchedule 图标

| 版本 | 文件 | 尺寸与颜色 | 状态 |
| --- | --- | --- | --- |
| 默认／浅色 | [tschedule-campus-light.png](tschedule-campus-light.png) | 1024 × 1024 PNG，不透明，sRGB | iPad 系统图标与侧栏浅色 |
| 深色 | [tschedule-campus-v1.png](tschedule-campus-v1.png) | 1024 × 1024 PNG，不透明，sRGB | iPad 系统图标与侧栏深色 |
| 2（浅色） | [tschedule-campus-v2-light.png](tschedule-campus-v2-light.png) | 1024 × 1024 PNG，不透明，sRGB | 候选稿，未替换 App 资源 |

2026-11-21 · Codex · `campus-icon` · 使用用户提供的航拍图作为轮廓参考，由内置 ImageGen 重绘；导出仅调整尺寸并嵌入 sRGB 配置。图标不包含文字、地图底图或学校标志。

## App 中的使用

`Xiaobao-iPadOS/Resources/Assets.xcassets/AppIcon.appiconset/` 包含本目录两张 1024 px 原图的逐字节副本，`TScheduleMark.imageset/` 各用等比缩到 96 px 的小图，不另绘、不着色。浅色为默认项，深色使用资产目录的 Dark 项。外观设置可保留默认的「跟随系统」，也可任选同图的浅色和深色替代项（`AppIconLight` 和 `AppIconDark`）。侧栏和锁屏课表仍按各自的界面外观选 `TScheduleMark`，不因替代 App 图标而改色。主屏幕外观仍由 iPadOS 设置决定，包括系统着色／清透。普通通知标识由 iPadOS 提供，不在内容内再绘制。更新画稿时一起检查四个图标集；打包不依赖仓库外路径。

### 变更记录
2026-11-21 · Codex · `alternate-campus-icons / native-appearance-settings` · 新增两款由现有原图复制的替代图标。由用户操作时请求 UIKit 切换；无独立通知 Icon 接口。默认系统浅深变体不变。

2026-11-21 · Codex · `light-dark-icon / system-notification-brand` · 接入浅、深两套图标，分别用于系统图标与侧栏。浅色版来自提供的画稿，只缩放并转换至 sRGB；没有改校园构图。没有增加通知权限、切换提示、实时活动扩展或推送。Xcode 编译出的两个资源均含默认与 Dark 项；[iPadOS 27 同一侧栏浅／深切换实拍](../verification/student-interface/tschedule-icon-appearances.png)来自本机演示，不含学校资料。

2026-11-21 · Codex · `sidebar-brand / tschedule-campus-icon` · 将校园图标与 TSchedule 名称接入产品身份展示；沿用既有 bundle ID、钥匙串和学校服务名称。接口只涉及资源名和显示名。 [iPad 模拟器侧栏实拍](../verification/student-interface/tschedule-sidebar-brand.png)。

## 生成提示

> Redraw this supplied aerial photo as a single finished-looking, extremely simple iPad app icon for TSchedule. Use the photo as the edit target/layout reference: preserve the recognizable arrangement but replace the entire photographic rendering with a clean flat geometric mark. Return one true square 1024 × 1024 icon, full-bleed solid deep ink-blue background, no transparent pixels, no premasked rounded outside corners, no mockup.
>
> KEEP ONLY THESE SUBJECTS:
> 1. The same L-shaped connected slate-blue roof: a vertical wing down the LEFT and a horizontal wing across the BOTTOM, starting at exactly the left-bottom elbow and extending to the right. It must read as one connected L, not an enclosing frame or extra buildings. Simplify the roof into broad flat cool slate-blue faces; at most one subtle slope break per wing. The overall silhouette stays close to the reference, with a long upright wing and a long horizontal wing. Use enough lightness contrast versus the ink-blue background to see the L easily at small size.
> 2. Exactly TWO separate green ovals, each surrounded by its own continuous smooth white outline of consistent medium weight. Place them above and inside the L in the same arrangement as the image: the larger oval lies immediately to the right of the vertical roof wing, toward the upper middle, tall and slightly leaning up-right; the smaller oval is lower and to its RIGHT, wider and tilting up-right at a shallow diagonal. Leave clear negative space between both rings and the building. Flat, solid, natural deep jade-green centers. Nothing inside the ovals: remove ALL white spots, pads, buildings, inner lines, and markings. Only the white perimeter outlines remain.
> 3. Preserve the distinctive square hipped roof at the LOWER-LEFT elbow. Make it a single square integrated with the L, with a few large triangular roof faces in warm terracotta, sand and light cream converging at one point. It is the sole warm accent and is not an additional freestanding building.
>
> Remove everything else from the photograph: no courtyard, pavement, trees, shadows, tracks, grass elsewhere, other roofs, people, map imagery, floating tiles, labels or lettering. Preserve the two ovals' different sizes, orientations and asymmetric positions, rather than making identical circles. Balance the mark inside a comfortable even safe area with clear silhouette and substantial negative space. Precise edges, quiet restrained palette, instantly legible at iPad Home Screen size. Strict flat orthographic top view. Absolutely no words, monograms, brand logos, gradients, highlights, embossing, 3D perspective or photographic texture.

## 浅色版

2026-11-21 · Codex · `campus-icon-light` · 以内置 ImageGen 从深色版生成雾蓝底候选稿，导出后确认不透明、sRGB，并以 28 px 核对轮廓可辨。原图及 App 资源保持不变。

> Make a light-appearance version of the attached finished TSchedule app icon. This is a tightly constrained image edit, NOT a redesign. Recolor only the broad dark navy field (at the edges and in the gaps around the mark) into an even, flat, soft fog blue, approximately hex #D5E6EE: light, muted, slightly cool, clearly different from pure white. The new field goes right to all four canvas edges. It should look good next to black text on a pale blue iPad window, not like a heavy dark square.
>
> Preserve the icon art as exactly as possible: identical framing and margins; the upright slate-blue faceted roof along the left connects to the roof along the bottom with the same rounded right tip; the original little square orange/cream four-facet hipped roof is in the lower-left elbow; precisely two diagonal solid jade-green ovals with clean white rims at their existing sizes, positions, and angles. Keep all of their existing colors, edges, proportions and negative spaces. Keep the rims visibly white rather than tinting them blue. No text, no additional shapes, no decorative details, no gradients, no shadow, no physical surface texture, no frame, no outside corner mask, no transparency. One flat, full-bleed, square app icon, design geometry remains the same; the only change from the reference is the navy background becomes pale fog blue.
