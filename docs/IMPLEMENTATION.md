# P1 当前实现与扩展入口

2026-10-21。本文描述已经存在的代码，优先于早期设计中的示意类名；产品约束仍以 DEVELOPMENT.md 为准。

## 运行结构

`scenes/main.tscn` 加载 `scripts/main.gd`，负责组合服务与场景。没有全局 Autoload、外部插件或在线依赖。

| 模块 | 实际入口与职责 |
| --- | --- |
| 内容 | ContentManifest / ContentCatalog：显式登记、排序索引、引用与参数校验、清单指纹 |
| 装备 | DroneAssembler：配置 ID + 调参 + 已取得列表 → 错误或唯一整机规格 Dictionary |
| 飞行 | FPVDrone：RigidBody3D、四推力点、角速度控制、混控、响应延迟、反扭矩、阻力 |
| 输入 | FlightInput：键盘与独立 RC 轴；RadioCalibration：端点、中点、方向和配置名称 |
| 世界 | WorldGenerator / WorldProvider：纯数据描述；WorldStreamer：后台任务和主线程提交；WorldGeometry：MultiMesh 和简化盒碰撞 |
| 进度 | ProgressStore：权限、设施、任务、事务、余额、配置、写盘与备份 |
| 界面 | Workshop / RadioCalibration / RegionMap / UIStyle；主场景组织帮助、商店和交互 |

场景只使用编译后整机规格，不读取具体机架或配件 ID。主场景当前包含一个维修终端和一个商店，尚无完整通用任务编辑器。

## 世界接口

```text
WorldGenerator.key_at(world_position) -> Vector3i
WorldGenerator.generate(key) -> {key, objects, world_version}
WorldProvider.generate(key, seed, biome, reservations) -> Array[Dictionary]
object = {id, center: Vector3, size: Vector3, color: Color, solid: bool}
```

坐标是米，X 右、Y 上、机头朝本地 -Z。单维度 world.main，64 m 立方块；全局键与本地浮动原点分离。结构以固定 owner 生成一次，可超出 owner 块；现有最大外伸控制在相邻块范围内。

当前地区规划由固定道路网格、群系 AABB 和体积预留组成，未创建独立 RegionPlan 类。城市两种风格复用同一提供者。峡谷内部使用柱状高度场；公共输出仍为三维实体，空岛有底面，地下有顶、墙、底和开放入口。

加载半径三块，最多 343 个键（含空块）；四个后台生成任务，活动节点和碰撞只在主线程创建，每帧最多一个非空块。飞行等待周围 27 个键就绪及两个物理步；卸载后返回的无关结果丢弃。当前没有复杂 LOD 或速度预测。

物理边界上，本地位置超过 1024 m 时移动原点，并同步机体、活动块和设施根节点；全局 ID、朝向、线速度不变。生成的随机数使用固定整数函数，不靠可变 RNG 或线程完成顺序。semantic_hash 仅用于测试比较，不参与地图生成。

## 新增群系

1. 复制 `content/base/verdant.tres`，设置新 ID、显示名、bounds、priority、palette（三色以上）与 building_min / building_max。
2. 将资源加入 manifest.biomes。沿用 modular_city 即可增加城市风格，不修改飞行或加载器。
3. 空岛与地下样本可修改 parameters.anchor，同时移动 region_bounds。地下的 surface_reservation 由数据声明，城市和峡谷会预留相交地表。
4. 当前地下样本以完整 64 m 地表块预留，洞室固定尺寸，整体移动 anchor；任意深度入口、斜井和连续洞网需要新的提供者，不能只移动样本就宣称完成。
5. 新几何规则实现 WorldProvider 子类并覆写 generate，在 WorldGenerator 注册提供者 ID。它仍输出相同对象描述，不改加载器、无人机或奖励计算。
6. 增加负坐标、结构边界、上下表面、通道净空和加载顺序检查。修改生成算法须增加 world_version，并处理旧世界迁移；当前没有自动迁移器。

## 新增装备

实际定义统一使用 PartDefinition，kind 为 frame / motor_set / propeller_set，电机与桨叶的 component_count 为 4。

- frame.stats：arm、max_prop_inches、mount、system_mass、drag。
- motor.stats：mount、shaft_mm。
- propeller.stats：diameter_inches、shaft_mm。
- tuning：以参数名为键的 Dictionary，每项含 min、max、default、step、unit。
- 当前物理绑定：机架 camera_mount_tilt_deg；电机 response_trim；桨叶 aero_trim。新调参类型需给装配器增加明确的作用路径，不仅增加滑块。

复制配件资源后新增稳定 ID，登记 manifest.parts；为新电机/桨叶组合登记 PropulsionMapDefinition。没有动力映射的组合不能安装。新增套机登记 DronePresetDefinition，引用三个组件。不得通过修改飞行控制器中的机型分支接入。

质量包括机架、四电机、四桨叶和固定系统质量；没有电池对象。惯性为尺寸和质量的简化估计，动力数值为虚构原型标定。当前基准最大 360 °/s、Expo 0.25；装备台允许 180–600 °/s、Expo 0–0.6，偏航为 70%。

## 获取与存档

RewardDefinition 使用 mission_tag AND city_tag，并原子授予 grants 的永久权限和 credits。新增任务渠道登记 reward；套机须同时包含必要组件。OfferDefinition 引用配件、价格与城市标签，登记 manifest.offers。

ProgressStore.complete_relay 接收稳定设施 ID 和两个条件标签。P1 调用来自生产主场景的距离、低速及按住两秒检查。未来应将交互实体也资源化，并把此方法重命名为通用任务入口；当前不对外开放脚本模组。

事务键为 mission:设施ID / offer:商品ID。完整快照先写 pending、重读校验、备份、替换，再改变内存。重复任务不增发，重复购买不扣款。存档损坏读上一份备份；两份均无效时保护原文件，进入临时只读档。未测试突然断电下的磁盘持久性。

格式 schema=1，包含 seed、world_version、content_fingerprint、credits、owned、transactions、facilities、missions、settings、build、deployment、dimension。Resource 保持只读。缺失配件保留原 ID 和原装配，运行暂回退免费初始套机；用户主动保存后才替换配置，上一份保留于备份。世界版本不匹配不写旧档；内容摘要改变给出提示，尚无跨版本世界迁移。

## 工具与下一次工作

先读 ROADMAP 和 VALIDATION，重跑 tools/Test.ps1；涉及包内运行再跑 Build.ps1。构建保持文本 Resource，详见 SETUP 的导出差异。测试以 SCRIPT ERROR、ERROR、FAIL、退出码和预期结束标记共同判定，不能只相信 Godot 返回 0。

本地引擎路径、导入缓存、用户存档、截图和构建包不进 Git。后续优先等待实际 i6x 操控反馈；不会把自动巡检当成人工飞行验收。
