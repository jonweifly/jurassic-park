# 风雨表现收敛

2026-09-20。针对大风时满屏树冠摇晃、雨线过长遮挡视野的试玩反馈。

## 本轮修改

- 叶片风场取消按树高无限放大的位移，世界空间偏移上限低于 3 cm。树干保持原有静态模型，树梢缓慢轻摆、叶片局部颤动；各实例按位置错开节奏。风力只改变幅度，避免风力过渡乘以累计时间造成相位跳变。
- 可见叶片与迷雾覆盖共用同一变形函数。草丛、蕨类沿用受限风场，不再依赖大面积摆动表达天气。
- 雨粒由 0.75 m 长盒体改为 0.24 m 短薄片，实例缩放 0.65–1.15。薄片面向镜头并按风向倾斜，边缘和头尾渐隐，大小、速度和透明度略有差异。
- 保留原有地形、树冠及屋顶高度剔除，320/600/900 的画质粒子预算，以及雨声、雷声、湿地、云量和照明反馈。天气循环、暂停、存档和玩法数值未修改。

## 验证与预览

- 环境专项 578 项、模型专项 55 项通过。
- 原生天气音频专项 29 项通过，覆盖混音、暂停、晴雨切换及低画质粒子数量。该测试须有原生渲染和音频驱动；headless 模式不创建天气粒子，不能用于这项测试。
- Godot 4.4.1 / Apple M5 / GL Compatibility 原生前后捕获：大风、阵雨、雷雨各 40 帧；另拍摄近远缩放、四个朝向与低画质视角。未发现新增脚本或 shader 编译错误。
- 40 帧样本的全画面平均相邻帧绝对差：大风旧版 0.229、新版 0.024；阵雨 0.239/0.025；雷雨 0.400/0.043（0–255 色值，缩至 320×200）。数值只表明该固定机位的整体变化减少，包含水面、树影和叶片，不是雨滴覆盖率，更不能证明任何人的眩晕感已消除。
- 同机压力场景：42 只恐龙、900 雨粒、1280×800，180 次采样；模拟中位数/P95 为 0.620/1.637 ms，含绘制和等待的迭代中位数/P95 为 24.159/27.417 ms。不能将它换算为普通游玩 FPS，也不作跨机器性能保证。

动态预览左旧右新：

- [大风](../../godot/captures/weather-refinement/gale-comparison.gif)
- [阵雨](../../godot/captures/weather-refinement/rain-comparison.gif)
- [雷雨](../../godot/captures/weather-refinement/storm-comparison.gif)
- [不同镜头与低画质](../../godot/captures/weather-refinement/angle-contact.png)

捕获冻结玩法，风场每帧前进 0.1 秒，雨粒按实际运行时间推进（包含截图开销），所以 GIF 是动态对比预览，不是精确时序录像。雨粒随机分布未逐粒匹配；循环回绕也不代表游戏内发生跳动。对比材质只用于工具，不接入正常游戏。

复现：

```sh
python3 scripts/test-core.py --only environment,production_assets
sh scripts/godot.sh --script res://tests/environment_audio_test.gd
sh scripts/godot.sh --script res://tools/capture_weather_refinement.gd
# 使用安装有 numpy、Pillow 的 Python：
python3 art/scripts/summarize_weather_capture.py
sh scripts/godot.sh --script res://tools/profile_environment.gd -- --weather-refinement
```

## 边界

远景的雨滴刻意很轻，仍靠雨声、湿润地面和天气光照表达雨势；本轮没有制作地面积水、水花模拟或独立树枝骨骼。屋顶/树冠遮挡仍是近似高度格网。压力采样仍出现一次此前已有的 macOS OpenGL `GLD_TEXTURE_INDEX_2D` 纹理诊断，此项未宣称解决。主观舒适度仍应以实际试玩反馈为准。
