# 01 雨林检修站美术样板

2026-09-27。独立、可运行的 Godot 3D 美术验证场景，并已提供可回退的主游戏接入模式。

## 怎么打开

- 重新启动游戏，在开始菜单点击 **01 美术样板**。
- 或双击根目录 **预览写实样板.command**。
- 样板右上角可返回主菜单。入口仅在开始菜单提供，不会从进行中的生存局跳走。

默认采用和主游戏相同的正交投影、52° 俯角、45° 方位、36 米视野参数。低机位仅用于观察模型细节。美术升级的目标仍然是俯视小人操控、采集、建造和自由探索。

## 这块样板包含什么

原创电门、柴油发电机、检修屋、阔叶树、蕨类与霸王龙 GLB，保留 Blender 源文件；原生地面、积水、围栏及草丛；黄昏 / 雨夜光照；可开关电门与供电；霸王龙呼吸观察动画；简化的原生 HUD。

它用于检查轮廓、比例、材质与俯视可读性，**尚未接入人物移动、资源采集、建筑施工、恐龙 AI 或存档**。低机位不是第一人称玩法。恐龙解剖、表面细节和动作仍是程序化样板质量，不能当作电影级成品。

## 接入主游戏

启动参数 `--cinematic-art` 会将 01 风格接到原主游戏：

```sh
sh scripts/godot.sh -- --cinematic-art
```

也可以双击根目录的 `预览写实主游戏.command`。

接入模式保留正交俯视镜头、幸存者操控、采集、建造、资源、防御、战争迷雾、恐龙 AI 和存档。适配到主游戏网格的资源位于 `godot/assets/cinematic/gameplay/`，包装场景位于 `godot/scenes/models/cinematic_*.tscn`。发电站、实验室、电门、电栅栏、树木、低模树和蕨类已接入；霸王龙暂时继续使用正式动作资源。

可用实机对照截图：

- [写实模式营地](../../godot/captures/art-direction/cinematic-camp.png)
- [写实模式近景](../../godot/captures/art-direction/cinematic-close.png)
- [写实模式阵雨](../../godot/captures/art-direction/cinematic-rain.png)
- [写实模式森林性能截图](../../godot/captures/forest-cinematic-production.png)

| 操作 | 功能 |
| --- | --- |
| 1 / Home | 与主游戏参数一致的俯视镜头 |
| 2 | 恐龙细节镜头 |
| 3 | 营地氛围镜头 |
| 中键拖动 / 滚轮 | 旋转 / 缩放 |
| WASD | 平移观察镜头，不操控人物 |
| G / P | 开关电门 / 供电；断电暂停电门移动 |
| N / M | 黄昏与雨夜 / 声音开关 |
| Tab / Esc | 隐藏 HUD / 暂停预览动作 |
| F12 | 保存截图到 godot/captures/cinematic-sample |

## 复现与验证

在项目根目录运行：

```sh
sh scripts/godot.sh res://scenes/cinematic_sample.tscn
sh scripts/godot.sh --script res://tests/cinematic_sample_test.gd
sh scripts/godot.sh --script res://tests/cinematic_entry_test.gd
sh scripts/godot.sh --script res://tools/capture_cinematic_sample.gd
```

模型重建：

```sh
.tools/Blender.app/Contents/MacOS/Blender --background --python-exit-code 1 --python art/scripts/build_cinematic_sample.py
sh scripts/godot.sh --headless --editor --import
sh scripts/godot.sh --script res://tools/build_cinematic_set.gd
```

最后的场景烘焙必须使用本机图形渲染器。Godot 4.4.1 headless 模式保存出的 MultiMesh 缺失实例矩阵；构建脚本会主动拒绝这种用法。主游戏接入模式的截图和性能数据也必须使用实际 GL Compatibility 渲染，headless 只能用于逻辑回归。

检查覆盖植被实例矩阵、地面法线、镜头参数、恐龙动画、供电与门移动联动、天气、暂停、HUD 边界、真实菜单按钮点击与返回。截图来自实际 Godot GL Compatibility 渲染，不是效果图。尚未做整局玩法或跨平台性能验收。
