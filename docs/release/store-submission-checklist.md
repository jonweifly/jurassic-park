# 平台提交清单

当前版本：**失落岛屿：生存营地**，Godot 4.4.1，地图 `organic-island-v3`，合作协议 `jp-coop-4`。

## 我已在仓库完成

- [x] Godot 项目名、运行时 HUD、网页原型和宣传草稿使用原创名称。
- [x] 导出预设覆盖 macOS、Windows x86_64、Linux x86_64。
- [x] 导出过滤包含 `data/maps/organic_island_v3.json` 和对应候选数据，并排除测试/工具目录。
- [x] 内部包附带试玩说明、发行审计、Godot MIT 许可和音效来源说明。
- [x] `scripts/package-release.py --publish` 在权利和平台条件未清除时拒绝生成公开包。
- [x] 自动化回归、存档、合作和包内烟测脚本已保留在仓库。

## 必须由发行负责人完成

| 项目 | 负责人 | 证据/结果 | 状态 |
| --- | --- | --- | --- |
| 签署 [素材权利签署表](asset-ownership-attestation.md) | 待填写 | 签名版文件路径 | 未完成 |
| 检索“失落岛屿：生存营地”及英文名的商标/平台重名 | 待填写 | 检索报告或编号 | 未完成 |
| 检查商店简介、截图、视频、图标和关键词没有第三方 IP 暗示 | 待填写 | 最终媒体目录 | 未完成 |
| Windows x86_64 干净设备启动、输入、分辨率、存档和合作 | 待填写 | 设备型号、系统版本、日志 | 未完成 |
| Linux x86_64 干净设备启动、输入、分辨率、存档和合作 | 待填写 | 发行版、桌面环境、日志 | 未完成 |
| macOS 开发者证书签名、公证、Gatekeeper 干净设备安装 | 待填写 | Team ID、notary ID、安装记录 | 未完成 |
| 平台主体、税务、收款、隐私政策、客服和内容分级资料 | 待填写 | 平台后台提交编号 | 未完成 |

## 推荐首发路线

先将网页版本作为免费 Demo 投放到 itch.io，收集首局完成率、平均时长、浏览器错误和玩家反馈；桌面客户端完成 Windows/macOS/Linux 实机验收、签名和素材签署后，再建立 Steam 或 TapTap PC 产品页。Poki、CrazyGames、微信小游戏和抖音小游戏需要单独接受平台条款或适配运行时，不能把当前桌面包直接上传。

## 提交前命令

```sh
python3 scripts/test-core.py
python3 scripts/test-coop.py --map-sync
python3 scripts/package-release.py
python3 scripts/package-release.py --publish
```

最后一条命令必须在所有外部条件满足并修改发行闸门后才允许通过；当前预期结果是明确拒绝公开发行。
