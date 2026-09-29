# 后期恐龙密集时的寻路卡顿

## 复现与定位（2026-09-29）

在 macOS / Apple M5 / Godot 4.4.1 上，用本地自动存档的只读副本回放：困难模式约 1499 秒，46 只恐龙、19 座建筑。模拟频率沿用项目的 30 Hz，连续推进 180 次，即 6 秒游戏时间。没有修改玩家原始存档。

开放区域的 72 只恐龙合成场景没有充分复现问题；实际存档中，封闭防线和地形隔断才是关键。

- `Board.route()` 为建筑周边多个接近格分别执行 AStar；无法到达的目标会反复搜索整个连通区域。
- 大体型的候选格更多，困难 AI 还会继续尝试其他路线。实际 6 秒回放发生 1508 次寻路。
- 加计时后的寻路总耗时由 **3274.6 ms 降为 45.6 ms**，请求数仍为 1508；原先约 27 ms 的体型网格生成不是主要瓶颈。

## 修复

`godot/scripts/board.gd` 为每个体型网格与 `board.revision` 缓存连通分区。先过滤无法到达的候选格，再执行原来的 AStar 和候选评分。

- 使用四邻域标记连通性，与现有“禁止切过障碍物对角”的网格规则相容。
- 建筑建造、拆除、门开关、树木清理都会改变 revision，旧连通标签随之失效。
- 不改变恐龙数量、伤害、感知距离、寻路频率或移动速度。
- 读档后角色恰好站在堵塞格时仍可离开；暂时允许离开不会把门两侧永久标为互通。
- 同时修复旧存档的探索点初始化：角色被关在营地内时，改从原始岛屿入口校验新增探索点，不移动角色或开启防线。

## 测量结果

原生窗口为 1280 × 800，使用 `--cinematic-art`。渲染先预热 30 帧，再以 `RenderingServer.frame_post_draw` 为结束点采样；未调用额外的 `force_draw`。旧版对照仅替换导航脚本，场景及其他玩法代码一致。

| 指标 | 修改前 | 修改后 |
| --- | ---: | ---: |
| 原生回放：逻辑平均耗时 | 19.86 ms | 2.66 ms |
| 原生回放：逻辑 P95 | 93.42 ms | 10.33 ms |
| 原生回放：帧平均耗时 | 44.55 ms | 19.24 ms |
| 原生回放：帧 P95 | 117.77 ms | 31.46 ms |
| 无窗口计时回放：逻辑 P95 | 91.32 ms | 10.42 ms |
| 56 次重复不可达请求，半径 0.48 | 699 ms | 0.31 ms |
| 56 次重复不可达请求，半径 1.12 | 1823 ms | 0.61 ms |
| 56 次重复不可达请求，半径 1.28 | 1792 ms | 0.60 ms |

P95 用于观察较慢的帧。以上是指定存档的短回放，不是全程帧率承诺。后台游戏实例数在排查期间从 3 个变为 1 个，原生渲染数据也受系统负载影响；核心证据是相同请求数的寻路计时、独立不可达场景，以及保持一致的路径结果。没有主动关闭用户的游戏。

原始数据位于被 Git 忽略的 `godot/captures/performance/`：`saved-navigation-before.json`、`saved-navigation-after.json`、`replay-native-before.json`、`replay-native-after.json`。

## 回归与复跑

```sh
python3 scripts/test-core.py --only navigation_budget,outfitting,expedition,expedition_flow
```

- `navigation_budget`：185 项检查；复现大区域隔断，56 次暖缓存请求须在 100 ms 内完成。旧代码在三个体型上均失败，修改后均通过。还覆盖开关门、拆除、清除地形、堵塞起点离开以及不能斜穿墙角。
- `outfitting`：67 项检查，包含封闭营地旧存档的初始化、完整防线保留与再次保存。
- 本轮还通过 `dinosaur_ai`、`dinosaur_roster`、`hard_difficulty`、`world`、`core_focus`、`barrier_rotation`、`camp_flow`、`save_reload`。
- 使用真实地形、500 个障碍和固定随机种子对比了 300 条新旧路线，逐点结果全部一致。这个一次性对照脚本保留在忽略目录的 `debug/` 中。

可复用的存档回放工具（先将待测存档复制为 `godot/captures/performance/repro.jps`）：

```sh
sh scripts/godot.sh --headless --script res://tools/profile_saved_crowd.gd -- --save-dir=res://captures/performance --slot=repro --instrument --out=res://captures/performance/profile.json
sh scripts/godot.sh --script res://tools/profile_saved_crowd.gd -- --cinematic-art --save-dir=res://captures/performance --slot=repro --out=res://captures/performance/native.json
```

工具关闭自动持久化并隔离偏好设置，只输出测量 JSON。默认 180 次模拟，可用 `--frames=` 改变长度；逻辑 P95 超过 33.3 ms 时退出码为 1。`profile_board.gd` 与 `profile_world.gd` 只由该工具加载，不进入正常游戏。

需要原导航对照时，把基线版本 `e9b9773` 的 `godot/scripts/board.gd` 放到 `godot/captures/performance/reference_board.gd`，再添加 `--reference-board`；不能与 `--instrument` 同用。存档副本、截图、JSON 与临时脚本均不入仓库。

## 验收范围

### 活动单位碰撞复测（2026-09-29）

增加空间桶与按躯干半径的移动避让后，使用同一份 46 龙、19 建筑存档副本回放 180 帧：无窗口逻辑 P95 为 14.97 ms；原生 1280 × 800 窗口逻辑 P95 为 11.77 ms、整帧平均 20.52 ms、整帧 P95 为 34.81 ms。后者含渲染开销，存在 119 ms 的偶发慢帧；这次改动没有消除所有渲染抖动。

`crowd_collision`、`crowd_world`、`encounter`、`dinosaur_ai`、`coop_rules`、`save_reload`、`outfitting`、`navigation_budget` 均通过。48 个旧档重叠单位分离后无躯干重叠，分离处理 P95 为 5.84 ms。原生对照图在忽略目录 `godot/captures/crowd/`。碰撞只近似躯干足迹，头尾动画仍可能局部交叠。

已复现并修复该存档的主要 CPU 卡顿来源，保留玩法行为。尚未覆盖整局长时间运行、所有分辨率和其他机型；读档、着色器编译与缓存首次重建仍可能产生单次耗时。试玩需要重新启动游戏加载新代码，运行中的旧实例不会自动更新。
