# 防线朝向与地表材质

## 建造操作

- 选择电栅栏或电门后，按 R 或点击营地命令栏的“旋转”，每次旋转 90°。快捷键沿用设置中的升级键，按钮和提示同步显示改键结果；只在这两种建筑的建造预览中替换升级行为。
- 预览显示实际模型朝向，绿色表示可建，红色表示不可建，橙色表示可能封堵通路。确认封路风险时保留选择的朝向。
- Shift 连续建造保留朝向；重新选择建筑恢复默认方向。右键或 Esc 取消建造。
- 朝向随存档保存，旧存档默认原来的方向。加固和开关门不覆盖朝向；门扇在自身局部坐标中转动。
- 沿用一格建筑占地及网格寻路，旋转不增加占地、不改变费用、电力、防御或通行规则。本轮支持放置前旋转，已建建筑不提供原地旋转。

## 地面制作

`art/scripts/build_ground_surfaces.py` 以固定随机种子生成四张原创 1024×1024 RGBA 无缝纹理：草土、裸土、落叶、碎石。RGB 保存颜色，Alpha 保存微小起伏高度。运行方式：

```sh
.tools/art-venv/bin/python art/scripts/build_ground_surfaces.py
sh scripts/godot.sh --headless --editor --import --quit
```

生成器依赖 NumPy 和 Pillow。对应 `.png.import` 文件必须保留多级纹理生成设置，并关闭透明边缘修补，避免高度通道被当成透明度修补。

地面着色器结合营地、树木与坡度遮罩混合这些表面：建筑周围裸土、林下落叶、开阔地草土、坡面碎石。岩石采用三轴投影避免拉伸，其余表面交错采样减少重复。雨天改变湿润颜色与粗糙度。微法线随距离衰减，并配合 mipmap 与各向异性过滤控制远处颗粒闪烁。此实现增加材质细节，不修改地形几何、碰撞、可建造区域或玩法随机数。

## 验证

```sh
python3 scripts/test-core.py --only barrier_rotation,barrier_rotation_input,ground_surfaces
sh scripts/godot.sh --render-thread safe --script res://tools/capture_art_direction.gd -- --tag=ground-after
```

旋转检查覆盖四方向、原生键鼠操作、连续建造、取消、开关门通行、加固、存档恢复及旧存档兼容。地面检查覆盖实际导入纹理及高度通道、运行时绑定、多级纹理、不同画质下的天气响应和玩法状态隔离。截图输出位于 `godot/captures/barrier-rotation/` 和 `godot/captures/art-direction/ground-after-*.png`。
