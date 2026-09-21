# 正式角色模型接入与第二轮优化记录

> 更新：本文保留第二轮接口设计的历史状态。独立骨骼模型和其余资源现已交付，当前结果、实际骨骼路径和验证以 [独立 3D 交付报告](production-delivery.md) 与现有包装场景为准。

2026-09-19。本轮完成森林绘制合批、幸存者的树冠遮挡处理，以及可配置的角色视觉适配层。正式人物/恐龙模型尚未制作，以下接口已在现有原型和独立骨骼挂点测试场景中验证。

## 森林性能与遮挡

原始地图的 3,680 个树木实例包含 14,720 个独立网格部件。运行时按 16 米区域、网格、材质、迷雾材质及阴影设置分组，生成 986 个 MultiMesh 批次。源树仍保留在可编辑场景中，仅运行时隐藏其单独绘制。

采集格与渲染实例建立对应记录。树木采完时，用末尾实例替换被移除实例并更新索引，减少实际可见实例数；不使用零缩放矩阵。最后一个实例移除后整个批次停止绘制。带骨骼、形变或 AnimationPlayer 的树木保留普通渲染路径，避免把动画冻结成静态实例。

同一台 Apple M5、Godot 4.4.1 / GL Compatibility、1280×800、同一演示营地的短时对比：

| 指标 | 不合批 | 合批 |
| --- | ---: | ---: |
| 实际绘制次数，含阴影/迷雾通道 | 6,481 | 1,301 |
| 绘制图元统计，含多通道 | 998,428 | 1,502,842 |

绘制次数约减少 **80%**。分块裁剪会提交部分块内的离屏几何，因此图元统计上升；这是减少 CPU 提交开销的代价，不能只看 draw call 推断所有设备都更快。原始采样数据在 `godot/captures/forest-unbatched.json` 和 `forest-batched.json`，其中 iteration 耗时包含强制绘制及主循环等待，**不应直接换算成游戏 FPS**。尚未完成低端 GPU、全图最高缩放及整局性能验收。

当树冠挡住幸存者时，以实际相机方向和人物胸部为中心，局部使用稳定的屏幕点阵裁切。树冠与迷雾共用风动和裁切代码；不会改变视线判定、恐龙隐藏、树木阻挡或资源状态。只对主镜头裁切，保留正常树影，避免阴影也产生点阵。人物死亡后关闭该裁切。建筑和岩壁遮挡仍待处理。

检查图：`forest-unbatched.png`、`forest-batched.png`、`canopy-before.png`、`canopy-after.png`，均位于 `godot/captures/`。

## 角色视觉接口

`pawn.gd` 负责移动、生命和动作状态选择，`worker.gd` 负责工作与资源结算。`pawn_visual.gd` 单独负责朝向、动画播放/定位、工具和携带物的挂接。玩法代码不再直接访问角色的 `ArmR`、`LegL` 或 AnimationPlayer 路径。

当前人物和恐龙场景均已有名为 `Visual` 的节点，挂载该适配脚本。可以在 Godot Inspector 中配置：

| 字段 | 用途 |
| --- | --- |
| `model_path` | 需要随行走朝向旋转的可见模型根节点 |
| `animator_path` | 导入模型的 AnimationPlayer；运行时使用手动推进，避免播放两次 |
| `clips` | 逻辑动作名 → 导入动作名，例如 `walk: Locomotion/Walk` |
| `work_equipment` | 幸存者开启；恐龙关闭 |
| `hand_socket_path` | 工具挂点，可以是 BoneAttachment3D |
| `cargo_socket_path` | 携带物挂点，可以是 BoneAttachment3D 或 Marker3D |
| `rifle_path` | 可选的枪械节点；没有枪械时可指向不存在的可选节点 |
| `tool_grip` / `tool_rotation_degrees` | 工具在挂点下的位置和角度 |
| `cargo_origin` / `cargo_rotation_degrees` | 携带物在挂点下的位置和角度 |
| `axe_scene` / `pickaxe_scene` / `hammer_scene` | 正式斧、镐、锤的 PackedScene；未指定时使用当前几何占位件 |
| `wood_cargo_scene` / `ore_cargo_scene` | 木材和矿石的独立携带模型 |

示例结构，所有路径相对于 `Visual` 节点：

```text
Survivor (pawn.gd)
├─ ImportedModel
│  ├─ Skeleton3D
│  │  ├─ RightHandGrip (BoneAttachment3D)
│  │  └─ CarryGrip (BoneAttachment3D)
│  └─ AnimationPlayer
└─ Visual (pawn_visual.gd)
```

对应路径为 `../ImportedModel`、`../ImportedModel/AnimationPlayer`、`../ImportedModel/Skeleton3D/RightHandGrip` 和 `../ImportedModel/Skeleton3D/CarryGrip`。默认工具位置仍为原几何手臂的 `(0, -0.48, 0)`；若新挂点已位于掌心，应从 `tool_grip = (0, 0, 0)` 开始校正。携带挂点同理，不要重复叠加旧模型的胸部偏移。

## 导入验收流程

1. 以独立 PackedScene 包装 GLB，保留原始导入文件。模型 1 单位 = 1 米，根节点脚底原点，正前方 +Z；工具局部轴和骨骼方向在包装场景中校正。
2. 配置 Visual 路径、动作名映射和挂点，先检查待机、行走、死亡；无需改 Worker、AI 和资源规则。
3. 幸存者补齐 `chop`、`mine`、`build`、`carry`、`carry_idle`、`attack`。当前采集触点在 1.10s，收势到 1.35s；施工循环 0.90s，触点 0.65s。工作动画由逻辑定位到时间，不应再通过动画事件重复增加资源或扣血。
4. 当前走路采用原地动画，导航拥有根位移。新模型的 Root Motion 必须关闭或另行接入，不能直接与导航相加。
5. 运行下列检查，并在正常近景、旋转视角和夜间查看。通过接口测试不代表骨骼权重、脚底 IK、工具实际触点或自然步态已合格，仍需用正式资产验收。

```sh
sh scripts/godot.sh --headless --script res://tests/visual_pipeline_test.gd
sh scripts/godot.sh --headless --script res://tests/polish_test.gd
sh scripts/godot.sh --headless --script res://tests/world_test.gd
sh scripts/godot.sh --headless --script res://tests/dinosaur_ai_test.gd
sh scripts/godot.sh --headless --script res://tests/encounter_test.gd
sh scripts/godot.sh --script res://tools/capture_forest.gd -- --unbatched-forest
sh scripts/godot.sh --script res://tools/capture_forest.gd
```

新增 18 项检查覆盖动作名映射、非默认层级的 Skeleton3D / BoneAttachment3D 挂接、工具切换、木材/矿石携带物、死亡释放、批次构建、跨批次连续采集、剩余实例变换与索引、清空地图树木、相机方向和死亡后的遮挡状态。既有 26 项 polish、41 项场景、56 项 AI 检查及 7 组连续遭遇场景也通过。

正式资源仍按 [建模规格](immersion-and-asset-spec.md) 的 P0 顺序推进：先用幸存者、迅猛龙、阔叶树、帐篷建立同场景样板，再扩展完整资源集。
