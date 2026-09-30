# 交互目标反馈（2026-09-30）

树木此前只按鼠标射线落地后的格子识别；建筑则有单独的模型拾取优先级。点击树干上半部可能选到后方树木或建筑，斧头图标也不能说明究竟命中了哪棵树。

现在悬停和左键共用模型拾取：树木按空间分块筛选，再检测网格三角面，与建筑、设施、恐龙比较命中深度；地面保留原有格子/建筑基座容错。恐龙使用动画模型包围盒。右键仍只移动。

目标仅显示贴地细圈：悬停淡色，点击后古铜金色圆圈在 0.24 秒内收紧一次，工作及选中期间保持稳定。不可达时红色提示，同一对象不叠加悬停圈和工作圈。圆圈中心透明，沿地形高度绘制，树木圈半径 0.85 米，建筑按基座的世界空间占地适配。圆心取树干底部或建筑 Foundation 基座的实际中心（包含子节点偏移、旋转和缩放），不再直接使用逻辑节点原点；没有基座的物体回退到模型包围盒，恐龙仍跟随身体锚点。物体维持原材质，不复制高亮网格。鼠标移到界面清除悬停，操作目标继续显示；停止、树木清除、恐龙离开视野时清除，暂停/放置隐藏。

实现：`godot/scripts/interaction_targets.gd`，由 `world.gd` 和 `pointer_feedback.gd` 接入。点击计时由帧间隔驱动，悬停切换不会重启动画。

## 本次圆圈反馈验证

- `movement_feedback` 42 项、`interaction_target` 30 项、`pointer_input` 11 项通过，共 83 项。
- 覆盖点击收紧、工作稳定、悬停去重、鼠标移开后不重播、停止/删除清理与建筑/恐龙目标。
- 已查看本次原生渲染的树木工作圈及挖掘场工作圈截图；没有运行整局测试。

## 圆圈对齐修正验证

- `interaction_target` 34 项通过，新增隐藏合批树干、嵌套偏移/旋转/缩放、实际圆圈顶点中心、移动跟随和建筑基座检查。
- `movement_feedback` 42 项通过，点击收紧及工作稳定反馈未回归。
- 原生渲染截图已检查建筑基座对齐；树木截图有遮挡，对齐以底部几何及圆圈顶点断言为准。

## 早期模型拾取验证记录

- `interaction_target` 30 项：真实树干表面投影、同一树的点击派单、森林合批高亮、八种建筑、工作保持/停止、不可达色、未知树、放置/暂停、删除、恐龙隐藏。
- `movement_feedback` 35 项、`pointer_input` 11 项、`harvest_approach` 161 项、`save_reload` 10 项通过；合计 247 项。
- 原生 Godot 4.4.1 / OpenGL 截图已检查：`godot/captures/interaction-targets/`，包括采木、挖掘场悬停/采金、恐龙目标。
- 真实树干附近 60 次模型拾取原生采样平均约 0.30 ms；仅该场景采样，不代表整局帧率。
- 额外运行 `tower_upgrade_input`：80 项中 7 条 `Compact HUD` 高度断言失败，其余 73 项（含高处武器点击）通过。底栏布局未在本轮修改。未进行整局长时间试玩。

复跑：

```sh
python3 scripts/test-core.py --only interaction_target,movement_feedback,pointer_input,harvest_approach,save_reload
sh scripts/godot.sh --script res://tests/interaction_target_test.gd -- --capture-targets
```

注意统一测试入口会合并已有 verification.json；即使本次五组全部 PASS，历史失败项仍可能使入口返回 1，应同时查看各组日志。
