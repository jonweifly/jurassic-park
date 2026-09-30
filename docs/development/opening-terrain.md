# 出生区湖湾与浅滩

出生点原地面约 6 米，四周四片水体约 0 米，局部平滑仍保留了高台、直角水沟和环状落差。现在 `opening_terrain.gd` 为出生区提供独立连续地形：营地约 1.8 米，西、南侧旧水沟填为缓起伏草地，东侧保留一片有弯曲岸线的湖湾，水位 0.7 米。改造核心半径 34 米，外围在 35–46 米间平滑接回原地图。

湖湾按连续函数在 1 米网格采样，水面与实际地面交线裁切，不沿旧水格轮廓。湖床、岸线、物理拾取、水深纹理和角色贴地使用同一曲面。水下暴露砂土材质，南侧浅色沙洲连接两岸；深水最深约 1.45 米，浅滩约 0.26 米。旧可建造格的中心和四角均保持露出水面；新水中树簇在资源/导航注册前移除。

## 水体玩法

- 浅滩可寻路、可实际穿过，移动速度为正常的 70%。减速作用于共用角色移动层，不修改装备基础速度，也不会反复叠乘。
- 深水不可行走，水中及紧邻湿岸不可新建建筑。水体可作为局部防线，浅滩提供穿越路线。
- 指针提示浅滩减速和深水绕行；未探索地块不透露地形信息。生存指南补充说明。
- 这次实现的是涉水与路线选择，尚未加入游泳、捕鱼或取水系统。

## 兼容

存档增加 `terrain_revision=1`，原地图 ID 和存档版本不变。旧档恢复时角色和移动目标重新贴地，失效路线重新规划，处于新深水/阻挡内的角色移到可连通的近岸位置。保留资源、建筑、携带物和任务字段。新版本存档原样恢复。

合作实时协议改为 `jp-coop-3`，避免新旧地形客户端混连；本地 `jp-coop-1/2` 合作存档仍可载入，队友同样重投影到地面。

## 验证

原生 Godot 4.4.1 / GL Compatibility：

- `opening_terrain`：20 项通过，涵盖旧建筑地基、陆地连接、真实角色涉水减速和出水、旧档深水位置恢复及路线继续。
- `world`、`water_surface`、`ground_surfaces`、`save_reload`、`coop_rules`、`contact`、`motion_camera_regression`、`field_engineering`、`crowd_world` 均通过。
- 地面 37 项通过；物理拾取与渲染地面的最大误差约 0.000048 米。水面 11,499 个三角形，0 个错误水位/穿地三角形。
- 双进程真实 ENet 联机：房主 22 项、客户端 35 项全部通过，包含加入、同步、断线和重连。
- 开局湖湾冻结时间，在 77 个世界坐标点采样 48 帧往返镜头移动，平均亮度最大相邻变化 0.001239；保留单次迷雾绘制，没有共面 Overlay。
- 实际开局（含迷雾和 HUD）、全景、湖岸和浅滩角色截图在 `godot/captures/opening/`，`comparison.jpg` 左侧为原地形、右侧为新地形。

本轮是以上针对性检查，没有运行整个项目完整测试集，也没有跨显卡验证。

```sh
python3 scripts/test-core.py --only opening_terrain,world,water_surface,ground_surfaces,save_reload,coop_rules,contact,motion_camera_regression,field_engineering,crowd_world
python3 scripts/test-coop.py
sh scripts/godot.sh --render-thread safe --script res://tools/capture_opening.gd -- --tag=after
sh scripts/godot.sh --render-thread safe --script res://tools/capture_terrain.gd -- --opening
```

合成测试修改原始高度/掩码后使用 `rebuild_surface()`，不重新施加出生区配置；正式地图载入调用 `rebuild_surface(true)`，启用出生区 1 米连续曲面。
