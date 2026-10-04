# 视觉体验优化记录

本轮针对“失落岛屿：生存营地”原生 Godot 游戏完成了四类视觉优化：

- 顶部 HUD 收紧为约 260x61 的原生目标面板与约 198x36 的相机工具栏；低优先级野外信息默认折叠，保留撤离倒计时、营地警报、当前目标和紧急提示。
- 营地建筑增加倒角、金属接头、铆钉、拉绳、地钉、梯子、螺栓、筛网、木柴、长凳、通风格栅和线缆卡扣；细节会按可见距离和画质降级。
- 恐龙共用更细的鳞片、法线和粗糙度材质，补充眼睛高光、牙齿和附属几何贴合，并修正攻击动作的下颚方向、下牙、眉骨、背刺、头角和前爪根部贴合。
- 场景加入程序化昼夜天空、晴雨雷雨颜色差异、低高度远景雾和雨夜层次；建筑灯光只在实际供电时显示。

## 定向验证

- `environment_test.gd`: 582 checks, 0 failures
- `dinosaur_detail_test.gd`: 225 checks, 0 failures
- `dinosaur_roster_test.gd`: 88 checks, 0 failures
- `hud_layout_test.gd`: headless 58 checks, 0 failures; native Metal 61 checks, 0 failures. 原生目标面板为 260x61，相机工具栏为 198x36。
- `camp_detail_test.gd`: 127 checks, 0 failures
- `art_direction_test.gd`: 34 checks, 0 failures
- `visual_pipeline_test.gd`: 18 checks, 0 failures
- `preferences_test.gd`: 54 checks, 0 failures
- `save_reload_test.gd`: 10 checks, 0 failures
- `coop_input_test.gd`: 15 checks, 0 failures

生产资源检查当前仍有 2 个 raptor/trex 地面接触断言失败；本轮没有把这两项纳入材质、下颚或附属几何修复范围，也没有宣称完整测试套件通过。

## 截图

- `godot/captures/art-direction/final-visual-20261003-camp.png`
- `godot/captures/art-direction/final-visual-20261003-close.png`
- `godot/captures/art-direction/final-visual-20261003-night.png`
- `godot/captures/art-direction/final-visual-20261003-rain.png`
- `godot/captures/art-direction/final-visual-20261003-storm-night.png`
- `godot/captures/art-direction/final-visual-20261003-low.png`
- `godot/captures/visual-refinement/dinosaur-raptor-idle.png`
- `godot/captures/visual-refinement/dinosaur-raptor-attack.png`
- `godot/captures/visual-refinement/dinosaur-trex-idle.png`
- `godot/captures/visual-refinement/dinosaur-trex-attack.png`

最近一次场景采样记录在 `godot/captures/art-direction/final-visual-20261003-performance.json`：1280x800，median 17.124 ms，p95 22.856 ms，813 draw calls。它是本机一次采样，不代表所有机器的稳定 FPS。

本轮恐龙细节来自现有 GLB 导出后的可重复 Python 后处理与材质更新；没有把 Blender 源文件重新雕刻或完整高模重雕作为已完成事项。
