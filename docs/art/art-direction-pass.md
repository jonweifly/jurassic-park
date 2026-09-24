# 营地与地表视觉优化（2026-09-22）

本轮以克制的自然配色、明确的材质区分和可读的策略视角为方向。处理统一绿色地面、尖片草丛、建筑缺乏使用细节和高光过塑的问题；不增加外围玩法。

## 实现内容

- 新制作四套独立 Blender / GLB 营地装饰：帐篷木箱、铺盖、绑带、提灯和门垫；塔台护栏、备弹箱；发电站油桶、电池和电缆；基础建筑/实验室窗檐、百叶、落水管、门阶和标识。总计 7,540 个源网格顶点，材质按木材、金属、帆布、橡胶区分。它们是新增实体网格，没有重做整个建筑主体。
- 新增三张 1024² 原创纹理：营地泥土、林下落叶、带木纹/织物纹理的共用模型图集。保留已有 UV、骨骼和法线贴图。
- 256² 地表分布图跟随实际建筑与树木生成泥土和落叶层；建造、拆除、采树后更新，加载存档时重建。纹理只参与渲染，不修改地形高度、可建造区、碰撞、导航或游戏随机数。
- 草丛改为细长、弯曲、分段的叶片，增加根部到尖端的颜色变化及疏密分布。保留分块 MultiMesh、距离裁剪和森林 LOD。树叶增加细微色差及近景叶脉，沿用已有低幅风动。
- 调整日光、天空补光与地面色调；降低白天火光，夜晚单独保留照明。建筑不再整栋统一金属化；装饰金属单独使用金属材质。
- 低画质隐藏新装饰及地表草丛，在暂停设置面板中立即生效；施工未完成时不显示完工装饰。

## 原始资源与重建

源文件：`art/source/{tent,tower,generator,lab}_dressing.blend`；模型：`godot/assets/models/*_dressing.glb`；统计：`art/camp-dressing-manifest.json`。

```sh
python3 art/scripts/build_surface_detail.py # 需要 Pillow、numpy
.tools/Blender.app/Contents/MacOS/Blender --background --python-exit-code 1 --python art/scripts/build_camp_dressing.py
sh scripts/godot.sh --headless --editor --import --quit
```

两个脚本只重建本轮对应资源，不要为此重新生成整套角色和建筑。Godot 的 headless dummy 渲染器在 GLB 缩略图导入时出现过 `Parameter t is null`，实际原生运行及截图无此错误。

## 验证与实机对比

Godot 4.4.1 / macOS Apple M5 / GL Compatibility / 1280×800。

最终 10 组回归通过，共 895 项检查：art_direction 31、environment 578、polish 26、visual_pipeline 18、production_assets 55、preferences 54、save_reload 10、demolition 54、core_focus 43、core_focus_input 26。包含实际鼠标选择、塔楼改造和修理操作。新增回归验证表面分布、拆除清理、采树更新、暂停画质切换、装饰无碰撞以及存档恢复后外观一致。

```sh
python3 scripts/test-core.py --only art_direction,environment,polish,visual_pipeline,production_assets,preferences,save_reload,demolition,core_focus,core_focus_input
sh scripts/godot.sh --script res://tools/capture_art_direction.gd -- --tag=after
```

截图位于 `godot/captures/art-direction/`（本地生成，不纳入 Git）：

- `comparison.png`：同机位近景，左侧优化前、右侧优化后。
- `before-*.png` / `after-*.png`：营地全景、近景、夜间、阵雨；另有 `after-low.png`。
- `before-performance.json` / `after-performance.json`：固定场景的绘制工作量及短时采样。

营地全景绘制调用从 808 到 847（+4.8%），提交图元从 935,642 到 986,630（+5.4%）。本轮最终采样中位 7.045ms、P95 12.408ms，但窗口遮挡、同步及系统调度影响很大，**不能用这次前后耗时宣称性能提升，也不是全图稳定帧率证明**。功能测试、截图检查与真人长局体验是不同层次的证据。

## 当前限制与下一步

这是场景美术质量的一轮提升，不是完整商业游戏美术替换。人物和恐龙沿用已有骨骼模型与动作；面部、解剖轮廓、皮肤材质、转身与受击动作仍偏简化。树冠形体、岩壁轮廓和区域地标也需要进一步雕琢，新增小配件无法替代这些主体资产的提升。

下一轮优先制作一套更成熟的幸存者/迅猛龙视觉样板（比例、轮廓、材质与动作共同验收），再推进树冠和岩壁，最后制作有辨识度的基地周边地标。仍维持当前克制天气，不以浓雾、景深或强烈树摇掩盖资产不足。本轮未做跨平台性能验收及整局平衡重测。
