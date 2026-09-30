# 湖面稳定性、岸线与地表细节

本文保留首轮水面闪烁定位与局部地形细化记录。出生区已进一步重做为低缓营地、单侧湖湾和可涉水浅滩；当前开局实现与验证见 [出生区湖湾与浅滩](opening-terrain.md)。

## 问题与修复

水面闪烁的主因是两个透明渲染通道的排序冲突：水面本身使用 Alpha 混合，同时又叠加与水面共面的 `Vision.overlay`。镜头平移时，水面和整块地形的透明层排序发生切换，湖面会整体忽明忽暗。

现在水体在自己的着色器中采样同一份可见性纹理，移除水面独立的迷雾 Overlay，并在地面迷雾之后绘制。波纹改用世界坐标法线，降低高频高光，在远处淡出细法线。可见性规则和迷雾数据没有改变。

`terrain_surface.gd` 生成 1 米采样的连续曲面，使用有界平滑与缓慢坐标扰动细化不可通行的坡岸。可通行区域、建造格及已有树木/岩石的落点固定在原高度，导航掩码继续来自原地图。最大地形高度调整为 0.72 米。新网格、物理拾取、CPU 高度采样、水深和雨滴落点使用同一份曲面数据。

水面先按连续湖盆场裁出弯曲边界，再按实际地形深度裁切；边缘顶点携带连续的淡出权重，消除原来水格标记结束处的硬直角。不同湖泊保留各自水位。

四张地表纹理继续由固定种子的原创生成器生成，补充砂砾、孔隙、叶脉、根须和枯枝，并保留无缝边界与 Mipmap。草土、落叶和岩面增加粗糙度差异及受距离控制的微起伏。

## 验证

本机原生 Godot 4.4.1 / GL Compatibility，固定时间、54 个湖内世界坐标采样点、48 帧往返平移：

| 指标 | 原实现 | 移除旧 Overlay 的隔离实验 | 最终实现 |
| --- | ---: | ---: | ---: |
| 任一点相邻采样帧亮度跳变超过 0.05 的次数 | 13 | 0 | 0 |
| 所有采样点平均亮度的最大相邻变化 | 0.124482 | 0.000713 | 0.000403 |
| 相同镜头位置往返采样的最大亮度差 | 0.184749 | 0 | 0 |

原始前后对照在 `godot/captures/terrain-review/temporal.json`，汇总在 `temporal-summary.json`，截图对照在 `comparison.jpg`。这是该固定场景的验证，不代表所有显卡与视角的结果。

地形回归：9,505 个坡岸采样点发生超过 0.02 米的调整；可通行/建造区域最大高度误差约 0.0000004 米；物理拾取与地表高度的最大误差约 0.000048 米。37 项地面检查通过。水面有 12,719 个三角形、4,942 个非整数边界顶点，没有放错水位或穿入地表的三角形。

`water_surface`、`ground_surfaces`、`world`、`contact`、`core_focus`、`expedition`、`environment`、`save_reload`、`display_input`、`motion_camera_regression` 通过；原生渲染覆盖平移、晴天、雨天和低画质远景。`dinosaur_ai` 中的“采集产生六米噪声并保留携带流程”断言失败，用原版 `TerrainData` 替换测试场地后仍以同一断言失败，属于已有采集行为与测试场景的问题。本次没有改动采集逻辑，也没有运行完整测试套件。

## 重现

```sh
sh scripts/godot.sh --render-thread safe --script res://tools/capture_terrain.gd
sh scripts/godot.sh --headless --script res://tests/water_surface_test.gd
sh scripts/godot.sh --headless --script res://tests/ground_surfaces_test.gd
```

渲染工具默认验证最终实现，湖内平均亮度突跳超过 0.025 时失败；`-- --probe-overlay` 可额外在当前网格上恢复旧叠层排序用于定位。它将回放结果写到 `replay.json`，不覆盖原始前后对照记录、不读取或写入玩家存档。

重新生成纹理：`.tools/art-venv/bin/python art/scripts/build_ground_surfaces.py`，随后执行 Godot 资源导入。测试若直接修改 `TerrainData.heights/walk/build`，需调用 `rebuild_surface()` 同步派生曲面；运行中的原始地图数组不作动态编辑。
