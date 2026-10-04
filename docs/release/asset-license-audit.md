# 发行前素材与权利审计

状态：**仅限内部试玩，尚不可公开上架或商用发行**。本清单是仓库来源审计，不是法律意见，也不替代素材作者和平台要求的最终核验。

| 范围 | 当前来源证据 | 商用判断 / 待办 |
| --- | --- | --- |
| 游戏名称、界面文案与宣传入口 | 主入口、Godot 项目名、运行时 HUD、原生样板 HUD、风格板和短视频口播稿已改为“失落岛屿：生存营地”；网页图标已移除旧 IP 缩写 | 新名称尚需商标检索；商店图文和预告片发布前再逐项核查 |
| 运行时地图与布置 | `godot/tools/generate_organic_island.py` 生成 `godot/data/maps/organic_island_v3.json`，基础场景为 `godot/scenes/original_island.tscn`；`godot/scripts/map_catalog.gd` 只暴露 `organic-island-v3` | 候选图和运行数据已进入导出过滤；发行前仍需逐包确认没有参考地图和研究资料 |
| 玩法参数与叙事 | `godot/scripts/catalog.gd` 等保留历史参考研究中的部分数值；现有生存、科技和救援循环又有项目原创扩展 | 公开商店文案不得称为第三方作品复刻；发布前逐项确认任务文案、独特角色/地点/故事与第三方作品无实质相似，数值平衡继续以本游戏试玩结果调整 |
| 角色、恐龙、树木、建筑模型 | `art/source/*.blend`、`art/scripts/build_assets.py`、`art/scripts/build_dinosaur_roster.py` 和 `art/asset-manifest.json`；运行时为 `godot/assets/models/*.glb` | 仓库记录为项目内生成；逐个确认所有模型、动作和参考图由项目作者制作或有商用授权，保留作者声明。不能仅凭脚本存在推定权利完整 |
| 材质与纹理 | `art/textures/`、`art/scripts/build_assets.py`、`art/scripts/build_dinosaur_surface.py`、`art/scripts/generate_environment_media.py`；运行时在 `godot/assets/materials/` | 生成链路为本地程序化制作；对新加入的贴图逐项比对来源，记录外部输入或素材包许可证 |
| 恐龙叫声 | `art/audio/CREDITS.md`、`art/audio/sources/licenses.json`、`art/scripts/build_dinosaur_audio.py` | 两份 CaveboyTup 源音频页面在 2026-10-03 仍标注 CC0，仓库 MP3 哈希与授权清单一致；随包附来源信息。后续新增音效须单独登记 |
| 其他音效和环境声 | `godot/tools/generate_audio.py`、`art/scripts/generate_environment_media.py`；运行时 `godot/assets/audio/*.wav` | 项目内合成；`godot/assets/audio/README.md` 已区分它们与 CC0 叫声；新音效须登记来源 |
| UI 图标与网页原型 SVG | `godot/assets/ui/`、`godot/assets/cursors/`、`godot/assets/interaction_icons/`、`assets/*.svg` | 需逐图确认作者、生成过程和是否借用了第三方图标/角色造型；网页原型不进入 Godot 导出包 |
| 字体 | Godot HUD 使用 `SystemFont` 系统回退（苹方、微软雅黑、Noto Sans CJK）；没有打包字体文件 | 无字体再分发；跨平台中文缺字和商店图所用字体仍须在目标系统上核查 |
| 引擎与第三方工具 | Godot 4.4.1、Blender、Vite；仅 Godot 运行时随正式包分发 | 发布时附引擎许可证及第三方 notices；确认所用导出模板版本与引擎版本一致 |

2026-10-04 本机验证基线：Godot 4.4.1 官方模板可导出 macOS、Windows x86_64、Linux x86_64；当前版本包含 `organic-island-v3` 和合作协议 `jp-coop-4`。62 组核心回归、双进程合作回归、导出烟测和三平台 ZIP/PCK CRC 已通过；逐包核对确认仅保留两份运行时地图 JSON，未包含 `builds/`、`captures/`、测试、工具、研究资料和旧地图预览素材。地图、合作、存档、输入和环境回归需以本日期重新运行结果为准；本机不代替 Windows/Linux 目标设备实测。macOS 包可做临时签名和启动烟测，但 Apple Developer 签名、公证、Gatekeeper 干净机器验证仍未完成。

发行完成条件：所有素材逐项留下作者和许可证证据；清理商店文案与媒体中的第三方 IP 暗示；在目标 Windows/macOS/Linux 设备验证启动、输入、分辨率、保存/读取及合作网络；按平台要求完成签名、公证与平台元数据。逐项责任人、凭证编号和目标设备记录见 [素材权利签署表](asset-ownership-attestation.md) 与 [平台提交清单](store-submission-checklist.md)。`reference/` 与 `docs/research/` 是内部研究资料，不进入游戏导出或商店资料。
