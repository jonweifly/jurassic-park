# 架构与新增功能指南

## 当前运行链路

```text
main.tscn → world.gd → Session / Board / Worker / DinosaurAI / HUD / Coop
                    └→ Scenery / Weather / Sound / SaveStore
```

`world.gd` 仍是运行时门面。第一阶段优化保持它作为兼容入口，同时把新功能的规则、事件和表现连接逐步移出。

## 模块职责

| 领域 | 主要入口 | 负责内容 |
|---|---|---|
| 规则状态 | `scripts/session.gd` | 资源、建筑、科技、时间、存档字段 |
| 地图导航 | `scripts/board.gd` | 网格、通行、路径、建筑占位 |
| 建造预览 | `scripts/build_access.gd` | 建造后通路风险评估，不修改实时地图 |
| 单位行为 | `scripts/worker.gd`, `scripts/pawn.gd` | 采集、施工、移动和交互 |
| 恐龙行为 | `scripts/dinosaur_ai.gd` | 感知、巡游、追击、攻击和回归 |
| 表现 | `scripts/scenery.gd`, `scripts/hud.gd`, `scripts/sound.gd` | 模型、界面、音频和反馈 |
| 持久化 | `scripts/save_store.gd` | 版本化数据存档和迁移 |
| 合作 | `scripts/coop_session.gd`, `scripts/coop_replication.gd` | 房间、命令确认和状态同步 |
| 事件 | `scripts/game_event_bus.gd` | 规则结果向 UI、声音和联机广播 |

## 新功能落点

新增功能按以下顺序实现：

1. 在 `catalog.gd` 或独立 `*_catalog.gd` 定义数据。
2. 在 `session.gd` 或独立 `*_rules.gd` 实现可测试的规则。
3. 由 `world.gd` 或领域控制器调用规则并创建实体。
4. 通过 `GameEventBus` 发布结果，让 HUD、声音和统计分别响应。
5. 在 `save_store.gd` 增加必要的纯数据字段和迁移逻辑。
6. 在 `coop_replication.gd` 增加需要房主确认的命令。
7. 新增一个规则测试，再补一个真实场景流程测试。

推荐事件名：`building_created`、`building_demolished`、`research_completed`、`resource_deposited`、`dinosaur_defeated`。事件 payload 只放数据，不传 Node 引用。

## 修改前检查

- 先确认功能是否已经存在于 `godot/README.md` 的当前功能区。
- 先检查是否需要存档版本迁移。
- 先检查合作模式是否需要同步。
- 地图/模型生成工具会覆盖派生数据，运行前确认输出路径。
- 修改后优先运行单项测试，再运行完整回归。
