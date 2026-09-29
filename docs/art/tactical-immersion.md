# 主游戏战术视角与沉浸表现

2026-09-29。改动接入 `scenes/main.tscn` 使用的正式脚本；普通与 cinematic 美术模式均生效。

## 画面与动作

- 默认镜头为 48° 俯角、30° 窄视场透视。用原缩放值计算焦点距离，保持战术视野和操控习惯。F10 的“镜头与提示”可以恢复正交视角、关闭受击震动。
- 主光降低角度，增加侧面阴影与环境光的差异。地面根据实际高度生成坡面、山脊和沟底明暗；降低细碎贴图的覆盖程度。
- 陡坡添加分块合批的立体岩台。全部顶点落在原有不可通行格内，不添加碰撞或改变地面高度；低画质隐藏岩台。
- 树冠加强顶部/底部和叶片朝向的色层，平缓地面树干添加立体板根。树根与树木一起采伐移除，使用独立简模。
- 人物行走增加髋部换重、躯干反向转动、转弯侧倾和停步回正；工作增加踏步、蓄力、下击与收势。脚部沿真实地面求解，工具接触时刻继续为采集 1.1 秒、施工 0.65 秒。
- 帐篷补木架与灯，营火补吊锅与座凳，采掘场补绞架/吊桶，实验室补风机，基础箭塔补交叉支撑与后坐。施工、供电、损伤、暂停对应各自表现。

## 接敌与重击

只有视野内、正在追击角色或建筑、靠近当前镜头的恐龙参与接敌提示。大型恐龙真实命中时产生短促、有限幅度的平移震动和碎屑；同一范围攻击的多座建筑命中合并展示。战斗紧张度稍微压低环境音，保留原有音量、声道与警报冷却。

表现层不使用玩法随机数，不更改恐龙伤害、塔耐久、刷新预算或资源结算。联机通过原有效果通道传递命中，通过角色快照传递接敌状态；客机仍不执行伤害模拟。房间暂停会同时冻结新粒子和震动。

## 实机截图

以下文件由 Godot 4.4.1 的主游戏场景产生，未使用概念图代替运行结果。战斗和地形图使用隔离存档的可重复场景布置；截图目录由 Git 忽略。

- 营地与建筑：`godot/captures/art-direction/immersion-camp.png`、`immersion-close.png`。
- 夜间、雨天、低画质：同目录 `immersion-night.png`、`immersion-rain.png`、`immersion-low.png`。
- 接敌与实际伤害：`godot/captures/immersion/01-defense-windup.png`、`02-defense-impact.png`。
- 原地图岩坡：`godot/captures/immersion/03-terrain-depth.png`。
- 工作姿态：`godot/captures/contact/chop-windup.png`、`chop-contact.png`、`mine-contact.png`、`build-contact.png`。

```sh
sh scripts/godot.sh --script res://tools/capture_art_direction.gd -- --cinematic-art --tag=immersion
sh scripts/godot.sh --script res://tools/capture_immersion.gd -- --cinematic-art
sh scripts/godot.sh --script res://tools/capture_contact.gd
```

## 验证与边界

已执行动作、接触、模型资源、森林合批、地面、建筑细节、镜头拾取、设置真实点击、移动反馈、环境、存档、恐龙攻击、塔升级及真实点击、音频和合作规则/界面回归。新增专项包括 `survivor_motion`、`camp_detail`、`immersion`；森林数量检查改为核对实际源场景部件数，并保留批次少于源部件四分之一的性能门槛。

Apple M5、GL Compatibility、1280×800 演示营地的本轮渲染采样：中位迭代 17.648 ms、P95 18.732 ms、786 次绘制调用。它是这台机器与这个场景的短时测量，不能代表后期密集恐龙或其他设备的帧率。完整数据在 `godot/captures/art-direction/immersion-performance.json`。

这轮增强现有模型的空间感、结构和动作，仍沿用原地图高度网格及现有恐龙骨骼资源。未重做全岛手工地形，也未替换全部角色模型。

## 反馈修正：腿部、缩放、地表与面板

- 膝盖求解改用骨盆前方向作为弯曲参考，避免腿接近伸直时因微小偏移反向折弯。走路、待机和三种工作的逐帧回归中，最小向前偏移由 −0.1282 米改为 +0.02646 米；侧面实机序列另检查了走路和搬运。
- 缩放距离已经平滑，旧代码再次独立平滑绝对镜头高度，造成高度与水平位移不同步。现在只额外平滑地形避让高度；无遮挡测试的非预期俯仰由 12.1207° 降至约 0.00001°。移除缩放跨过 24 时自动归位，保持自由镜头焦点；重击震动仍可单独关闭。
- 重生成草、土、落叶、岩石四张 1024² 表面贴图，增大可辨认的草叶与石粒，增强裸土斑块和微表面起伏；收窄双向贴图的混合带，降低细节叠糊。保留远景 mip 过滤及细节淡出。
- 底部按选中单位、营地行动、营地建造分组，增加分隔、层级和按钮状态细节。治疗、集火、击杀统计仍可直达，声音并入“设置 → 声音”；窄窗口换行时面板向上扩展，不越出底边。

本次相关回归为 `motion_camera_regression`、`survivor_motion`、`contact`、`polish`、`movement_feedback`、`hud_layout`、`preferences_input`、`ground_surfaces`、`art_direction`、`core_focus_input`、`tower_upgrade_input`、`display_input`。原生窗口检查包含全屏、1280×800、1280×720、1280×550、1000×800，以及箭塔升级和电门维修面板。

实机截图位于 `godot/captures/art-direction/refinement-*.png`；声音页及走路/搬运帧序列位于 `godot/captures/refinement/`。生成命令：

```sh
sh scripts/godot.sh --script res://tools/capture_art_direction.gd -- --cinematic-art --tag=refinement
sh scripts/godot.sh --script res://tools/capture_refinement.gd
```
