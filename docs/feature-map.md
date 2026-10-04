# 功能到代码索引

| 功能 | 规则/状态 | 世界协调 | 表现/UI | 存档 | 测试 |
|---|---|---|---|---|---|
| 建造 | `session.gd` | `world.gd:select_build/place_building` | `scenery.gd`, `hud.gd` | `save_store.gd` | `rules_test.gd`, `camp_flow_test.gd` |
| 拆除 | `session.gd:demolish` | `world.gd:demolish_building` | `scenery.gd`, `hud.gd` | `save_store.gd` | `demolition_test.gd` |
| 施工与采集 | `session.gd`, `catalog.gd` | `worker.gd`, `world.gd` | `pawn_visual.gd`, `sound.gd` | `save_store.gd` | `survival_test.gd`, `camp_flow_test.gd` |
| 恐龙 AI | `dinosaur_ai.gd`, `dinosaur_tactics.gd` | `world.gd` | `encounter_presentation.gd`, `sound.gd` | `save_store.gd` | `dinosaur_ai_test.gd`, `encounter_test.gd` |
| 科技与升级 | `session.gd` | `world.gd` | `hud.gd` | `save_store.gd` | `core_experience_test.gd`, `tower_upgrade_test.gd` |
| 探索与装备 | `expedition.gd`, `outfitting.gd` | `world.gd` | `expedition_panel.gd`, `hud.gd` | `save_store.gd` | `expedition_flow_test.gd`, `outfitting_test.gd` |
| 合作 | `coop_session.gd`, `coop_replication.gd` | `world.gd` | `coop_panel.gd` | `save_store.gd` | `coop_rules_test.gd`, `scripts/test-coop.py` |
| 设置 | `preferences.gd`, `feature_policy.gd` | `world.gd` | `preferences_panel.gd` | `save_store.gd` | `preferences_test.gd` |

行号会随重构变化；表中的函数名和文件名是稳定定位点。
