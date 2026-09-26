# 箭塔升级与独立模型

## 玩家流程

基础建筑 → 选中后升级实验室 → 打开科技，研究「箭塔工程」→ 选中箭塔，点击一种专精卡片。

箭塔工程消耗 20 木、15 金，研究 25 秒，只需完成一次。研究沿用现有实验室队列：实验室未完成、被摧毁或断电时不能开始/继续研究；已经完成的科技保留。围栏和电门的加固不受这一前置影响。

选中箭塔时，底部右侧的建造网格替换为模型预览卡片，显示角色、价格和施工时长；鼠标悬停可查看完整能力和不可用原因。右上角提供科技入口与最右侧「营地建造」返回按钮。改造中显示剩余时间，完成后显示当前专精。底栏沿用原有高度；科技列表改为可滚动，避免新条目挤出窗口。

建筑选择改用模型空间包围盒射线检测并保留地面落点容错，因此点击高塔平台或旋转武器也能选中建筑。选择检测不增加物理碰撞体。

| 专精 | 外形 | 单塔费用 | 施工 | 原有战斗定位 |
| --- | --- | --- | --- | --- |
| 远射 | 加高窄塔、长弩、瞄具、青色标识 | 12 木 / 10 金 | 12 秒 | 20 米、1.35 秒；压制喷毒龙 |
| 速射 | 低平台、双弩、双弹匣、备弹箱、黄色标识 | 10 木 / 14 金 | 12 秒 | 11 米、0.6 秒；清理入口小型目标 |
| 重弩 | 宽弩臂、后部绞盘、护板、支墩、红褐色标识 | 18 木 / 22 金 | 18 秒 | 17 米、36 伤害 / 2.4 秒；破甲猎巨 |

三种改造互斥，施工期间停火。基础战斗数值、地格占用、寻路和退款规则保持原有规则。困难模式仍按实际防御输出计算压力，箭塔工程只解锁升级，不额外作为一次数值强化重复计入科技压力。

## 模型与运行时

- 三套完整独立 GLB，各 2 个网格，约 3,348–4,620 三角面，导入生成 LOD，统一复用已有 expedition 材质和纹理。
- GLB 外置共享纹理后合计约 740 KB，避免重复携带三份贴图。可编辑 `.blend` 源文件仍包含纹理。
- 稳定的 `Gun/Recoil/Muzzle` 节点负责旋转、后坐和箭矢起点，速射塔使用两个交替发射挂点。
- 完工时替换 `Model`，保留建筑外层节点、坐标、朝向及碰撞数据；每帧不会重新实例化。新模型接入现有迷雾和遮挡淡化。
- 旧存档已升级箭塔无需补研究即可继续工作，并显示新的专精模型；新研究和施工队列沿用已有存档字段。

重建资源：

```sh
.tools/Blender.app/Contents/MacOS/Blender -b --python art/scripts/build_tower_refits.py
sh scripts/godot.sh --render-thread safe --editor --import
sh scripts/godot.sh --script res://tools/capture_tower_refits.gd
```

## 验证

20 组相关回归通过；新增两组共 116 项检查通过，47 个 GLB 结构校验无错误。

新增 `tower_upgrade` 和 `tower_upgrade_input` 覆盖研究前置、实际扣费、研究中存读档、断电暂停、完成解锁、三种模型替换、双弩发射挂点、后坐复位、旧存档、塔顶鼠标选择、上下文菜单、窗口尺寸和底栏高度。

```sh
python3 scripts/test-core.py --only tower_upgrade,tower_upgrade_input,core_focus,core_focus_input,defense_tactics,defense_input,rules,world,save_reload,demolition,demolition_input,pointer_input,production_assets,art_direction,hud_layout,hard_difficulty,kill_stats,kill_stats_input,core_experience,preferences_input
python3 art/scripts/validate_glb.py --report godot/captures/tower-upgrades/glb-validation.json
```

截图在 `godot/captures/tower-upgrades/`，包括同尺度模型对比、锁定升级、研究、三种卡片、完工状态，以及 1000×800、1280×720、1920×1080 窗口检查。

这些模型采用当前营地的风格化木材/金属语言；没有加入独立破损模型或完整施工动画。此轮验收为本机 Godot 4.4.1 功能回归和原生截图检查，不代表其他硬件上的性能基准。

本机编辑器批量导入默认渲染线程退出时曾出现 `finalize` 线程告警；改用上面的 `--render-thread safe` 命令后导入正常退出。未改变游戏渲染线程配置。
