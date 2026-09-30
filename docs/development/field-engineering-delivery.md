# 菜单、野外工程与恐龙通路（2026-09-30）

## 本轮行为

- 开始菜单独立选择 25 / 45 / 60 / 80 分钟与普通 / 困难，共 8 种组合；合作房间同样支持。统一普通模式使用标准来袭节奏，旧 classic 存档仍按旧规则运行。美术样板移至设置 → 画面。
- 确认框、下拉选项、输入框与标签页继承统一的森林绿、米色文字和金色焦点边框。
- 工坊新增便携电锯：14 木 / 20 金，制作 25 秒，必须走到工坊领取。默认开路模式，右键树木，抵达后 1.1 秒清除这一采集格并停止；不新增木材、不自动返营，已有携带物保留。L 面板可切回普通采木。开路噪声 14 米。接入持握模型与物品图标。
- 精制工具 → 机械工程（25 木 / 25 金 / 40 秒）→ 工坊维修机器人（20 木 / 30 金 / 35 秒）。制作后自动部署，最多 3 台（含制作中）。机器人沿通路移动，在所属工坊 24 米范围自动选择受损的已建成建筑；每秒 1 木恢复目标最大耐久 8%，缺电、缺木停止。机器人为悬浮维修单位，不参与地面单位挤压和恐龙索敌；工坊消失后尝试接管至其他工坊，没有工坊则待机。本轮未加入机器人自我复制、采矿、施工或战斗系统。
- 北侧 H 调整至 (-13, -45) 的平缓空地，检查完整停机范围与出生点通路，清理落点树木；标线随地表铺设。该区域 8 米范围内相对中心最大高差约 0.49 米。没有添加直升机飞行/降落模型。

## 恐龙修正

1. 转向限制为每秒 360°，普通攻击和特殊攻击不再用模拟 1 秒的朝向调用瞬间转身；绕行保持同一侧，连续 2 秒无有效进展后才换侧恢复。
2. 目标格不变且路线仍有效时，不每秒丢掉路线，避免碰撞偏移后反复折返。
3. 大型身体在 2 米网格不可达时，使用缓存的 1 米备用网格寻找通道中心。回归证明宽 4 米通道原先被判无路，修复后可通行，路线逐段仍检查完整身体。
4. 大型恐龙确实被树堵住时，可在接触处花 1.2 秒破树；山体、水域、建筑保持阻挡。缓存按地形版本更新。
5. 普通与旧长局也会在达到数量上限后重新调度闲置恐龙；不额外刷出超上限单位。外层防线与可达接近点不再仅限困难模式。

## 验证

21 组相关回归通过：route_recovery、forest_patrol、navigation_budget、crowd_collision、crowd_world、dinosaur_ai、encounter、hard_difficulty、dinosaur_roster、field_engineering、save_reload、coop_rules、extraction_feedback、preferences_input、outfitting、outfitting_input、hud_layout、core_focus_input、demolition_input、coop_input、motion_camera_regression。另通过原生 cinematic_entry 10 项检查。

新装备回归覆盖付费制作、实际领取/开路、带资源作业、维修材料扣除、缺电/缺木、科技与数量限制、旧装备存档字段缺失兼容、新状态保存恢复及合作状态包。森林测试 16 只混合体型恐龙有 14 只在 60 秒内抵达营地 10 米内；修改前 11 只，5 只成年霸王龙全部退回普通野外生成。另检查破树耗时、真实通路解除及建筑不会被当树移除。

46 龙 / 19 建筑的既有存档副本回放 900 帧（30 秒），最终逻辑平均 6.93 ms、P95 14.74 ms、最大 133.78 ms。备用网格首次构建或地形变化后的重建仍可能造成单帧停顿；这不是整局稳定帧率承诺。未完成 80 分钟真人平衡验收。

原生截图：`godot/captures/field-engineering/`（Git 忽略），包含开始菜单、下拉框、确认框、停机区及装备页。性能数据：`godot/captures/performance/field-engineering-final.json`。

```sh
python3 scripts/test-core.py --only route_recovery,forest_patrol,field_engineering,navigation_budget,crowd_collision,crowd_world,dinosaur_ai,encounter,hard_difficulty,outfitting,outfitting_input,save_reload,coop_rules,extraction_feedback
sh scripts/godot.sh --script res://tools/capture_field_engineering.gd -- --cinematic-art
```

重新启动游戏加载本轮代码。旧存档保留原难度与时长，新增装备/机器人缺省为空；旧地图存档采用新的 H 位置，旧 H 附近已有建筑不迁移。
