# 游戏发布平台调研

本文保留调研时的项目状态快照。当前品牌、原创地图和本机候选包进展以 [发行前素材与权利审计](../release/asset-license-audit.md) 为准。

日期：2026-09-30

## 项目适配判断

当前仓库同时包含：

- `dist/`：Vite 网页原型，构建命令为 `npm run build`，本轮构建通过。
- `godot/`：README 明确列为当前主项目，Godot 4 客户端，单机生存、基地防守、恐龙遭遇，并支持双人合作。

因此应把发布拆成网页试玩版和下载客户端两条路线。

## 优先级建议

| 优先级 | 平台 | 适合的版本 | 结论 |
| --- | --- | --- | --- |
| 1 | itch.io | 网页版、Windows/macOS/Linux Demo、源码或测试包 | 最适合作为第一站。上传门槛低，支持 HTML5 和下载包，适合收集试玩反馈、截图和开发日志。 |
| 2 | Steam | Godot 导出的正式 PC Demo/抢先体验/正式版 | 最适合长期商业化和愿望单。需要 Steam Direct、商店页、构建审核、年龄/内容资料和客服准备。 |
| 3 | TapTap | Demo、测试服、移动或 PC 版本的社区页 | 国内玩家反馈和曝光较强，适合做预约、测试招募和中文社区运营；具体发行形态和合规要求要按目标平台确认。 |
| 4 | indienova | Demo、开发日志、找发行或联合发行 | 更适合作为中文独立游戏曝光和发行合作入口，不应当当作自动分发渠道。 |
| 5 | CrazyGames / Newgrounds | 浏览器原型 | 适合网页即时试玩和快速验证留存；通常需要按平台 SDK、广告或页面规范接入，需先看其审核和商业条款。 |
| 6 | Epic Games Store | 已验证的 PC 正式版 | 可作为 Steam 之后的补充渠道。商店审核、产品资料、支付和地区发行准备的成本高于 itch.io。 |
| 7 | GOG | 完成度高、可离线运行的正式 PC 版 | DRM-free 和精选制更适合成熟版本，当前不应作为首发渠道。 |

## 海外平台

### itch.io

官方创作者文档：<https://itch.io/docs/creators/getting-started>

适合上传 `dist/` 网页包和 Godot 导出的桌面包。建议先放免费 Demo 或“免费/自愿付费”，页面中提供操作说明、已知问题、截图、短视频和反馈入口。它适合验证题材、首局完成率和设备兼容性，不适合作为唯一的长期商业渠道。

### Steam

官方 Steamworks 入门：<https://partner.steamgames.com/doc/gettingstarted>

适合完整 Godot PC 客户端。建议先建立 Coming Soon 页面并上传 Demo，再根据愿望单、试玩反馈和崩溃数据决定抢先体验或正式发售。Steam 的费用、等待期、内容审核和税务资料可能调整，提交前以当前 Steamworks 页面为准。

### CrazyGames、Newgrounds、Poki

- CrazyGames：<https://developer.crazygames.com/>
- Newgrounds：<https://www.newgrounds.com/>
- Poki：<https://developers.poki.com/>

这些平台主要面向浏览器即玩。当前网页原型比完整 3D Godot 客户端更适合测试；若接入平台 SDK，需要处理暂停、全屏、存档、广告和输入焦点。Poki 选择性更强，不应作为首个投递目标。

### Epic Games Store、GOG

- Epic 开发者文档：<https://dev.epicgames.com/docs/epic-games-store>
- GOG 开发者入口：<https://www.gog.com/indie>

两者都更适合已有稳定构建、商店素材、客服和发行计划的版本。对当前项目来说，先做 Steam/itch.io 数据验证再投递更稳妥。

## 国内平台

### TapTap

开发者文档：<https://developer.taptap.cn/docs/>

TapTap 适合做中文页面、预约、测试招募和玩家反馈。若发行移动端，需要处理包体、登录、支付、隐私政策、实名认证和应用市场要求；若发布 PC 版本，仍应确认当前的产品形态和审核路径。它更适合“社区加测试”阶段。

### indienova

官网：<https://indienova.com/>

适合中文独立游戏曝光、媒体联系和寻找发行合作。投稿前准备一页中文简介、英文简介、30 秒预告、5 至 8 张截图、可下载 Demo 和开发者联系方式。

### WeGame、哔哩哔哩游戏、4399/7K7K

- WeGame：<https://www.wegame.com.cn/>
- 哔哩哔哩游戏：<https://game.bilibili.com/>
- 4399：<https://www.4399.com/>

这些渠道更依赖精选、发行合作或平台运营。4399/7K7K 的用户和产品形态更偏网页休闲/运营游戏，当前 3D 生存客户端不应优先投递。WeGame 和哔哩哔哩游戏可以在产品成熟、中文发行资料齐全并找到对接入口后再评估。

## 发布前必须处理的风险

1. 当前项目名为“Jurassic Park”，README 还多次提到《魔兽争霸 III》《侏罗纪公园》6.5。公开上架前应改成原创名称，清理商店文案中对受保护作品的暗示，并逐项核对模型、纹理、音频、地图数据、字体和参考素材的授权。
2. 公开页面不应宣称“原版 6.5 一比一还原”；仓库 README 已说明当前是原创资源和独立设计，商店描述也应保持一致。
3. 先确认 Godot 导出的 Windows/macOS/Linux 包能在干净机器启动、存档可写、分辨率和输入可用；当前仓库只有 `godot/builds/JurassicCamp-Coop-Source.zip`，还没有可直接提交的商店发行包或 `export_presets.cfg`。
4. 国内商业发行还要单独评估版号、实名/防沉迷、隐私政策、支付、客服、备案和发行主体要求。平台页面能否创建不等于可以面向中国大陆商业运营。

## 推荐执行顺序

1. 先完成原创品牌和素材授权审计。
2. 把当前网页原型发到 itch.io，必要时再申请 CrazyGames 或 Newgrounds，观察首次进入、完成一局和设备兼容性。
3. 从 Godot 导出 Windows 试玩包，先发 itch.io；同时准备 Steam Coming Soon 页面和 Demo。
4. 用 TapTap 做中文社区页、测试招募和反馈收集；用 indienova 联系媒体或发行合作。
5. 有稳定留存、崩溃率和玩家反馈后，再考虑 Steam 正式发售、Epic 或 GOG，以及国内商业发行。

## 参考入口汇总

- itch.io 创作者文档：<https://itch.io/docs/creators/getting-started>
- Steamworks：<https://partner.steamgames.com/doc/gettingstarted>
- Epic Games Store：<https://dev.epicgames.com/docs/epic-games-store>
- CrazyGames 开发者：<https://developer.crazygames.com/>
- Poki 开发者：<https://developers.poki.com/>
- TapTap 开发者文档：<https://developer.taptap.cn/docs/>
