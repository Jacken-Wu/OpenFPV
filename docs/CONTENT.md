# 群系与装备内容契约

版本 0.2，2026-10-21。P1 已有内置 Resource 与 `.tres` 管线。实际字段与新增步骤以 [IMPLEMENTATION.md](IMPLEMENTATION.md) 和 `game/content/base/` 为准。下文 JSON 为完整目标示意，不能原样作为 P1 可加载资源。

## 0 P1 对应关系

实际为 ContentManifest、PartDefinition、DronePresetDefinition、PropulsionMapDefinition、BiomeDefinition、RewardDefinition、OfferDefinition；所有配件共用 PartDefinition，而非分别建立 Frame/Motor/Propeller 类。版本集中在 manifest；来源许可集中记录于 ASSETS.md，尚无每个条目的 schema_version 与 license 字段。

TuningSpec 当前为带 min/max/default/step/unit 的 Dictionary，作用由装配器的三个已实现参数绑定。获取规则当前是任务标签和城市标签的 AND，加独立商店；尚无通用 OR 条件图、条件循环校验、任务池或结构池编辑器。WorldProvider 输出三维盒描述，未实现独立 RegionPlan 类。不要根据后文目标字段假设功能已存在。

## 1 统一内容规则

- ID 使用带命名空间的稳定小写标识，例如 `base.biome.rustworks`；显示名称与 ID 分离。
- 资源包含 `schema_version`、`id`、显示名称或翻译键、标签、来源与许可引用。
- 内容包由显式 `manifest.tres` 列出资源与依赖，不依赖目录扫描顺序。
- 注册时按 ID 排序，检查重复、悬空引用、非法范围、条件循环和不支持的规则类型。校验错误指向内容 ID 与字段。
- 默认不允许后加载的同 ID 内容覆盖前者。覆盖和替换需单独的版本迁移设计。
- 内容包在一轮生成与装配中保持只读。玩家配置、调参和取得状态分开保存。
- 新 ID 不使用文件绝对路径或显示名称。移动资源位置或翻译名称不应丢失玩家进度。

## 2 群系结构

### 2.1 定义与提供者

| 类型 | 关键字段 | 职责 |
| --- | --- | --- |
| BiomeDefinition | provider_id、分布规则、三维高度带、优先级、材质与结构池、任务与商店池 | 声明一个地区如何选择和表现 |
| GenerationProvider | provider_id、版本、支持的结构参数、地区规划与块描述 | 执行具体几何规则 |
| StructureDefinition | 三维 bounds、连接口、碰撞输入、语义锚点 | 表达桥、塔、楼、洞室和平台 |
| RegionPlan | 地区键、生效层、结构列表、owner 与跨区连接 | 固定本地区的宏观布局 |
| ChunkDescriptor | 三维块键、几何贡献、碰撞输入、实例与锚点 | 为加载器提供与风格无关的结果 |

风格与地形分别组合。例如两种城市使用同一个 `base.generator.modular_city`，但配色、楼体池、街道参数和任务池不同。空岛和地下引用不同提供者，均输出三维 bounds，不改变加载器接口。

### 2.2 群系样例

字段名为初始契约，`vertical_band_m` 的两个值依次为世界 Y 下界和上界，不是相机高度或加载半径。范围只参与分布选择，最终几何仍需经过相交与入口校验。

```json
{
  "schema_version": 1,
  "id": "base.biome.rustworks",
  "provider_id": "base.generator.modular_city",
  "provider_version": 1,
  "dimension_id": "world.main",
  "tags": ["city", "industrial", "surface"],
  "vertical_band_m": [-32.0, 192.0],
  "priority": 10,
  "palette_id": "base.palette.rust",
  "structure_pool_ids": ["base.structures.industrial"],
  "mission_pool_ids": ["base.missions.maintenance"],
  "shop_pool_ids": ["base.shops.workshop"],
  "generation_parameters": {
    "street_width_m": 12.0,
    "building_height_min_m": 12.0,
    "building_height_max_m": 48.0
  }
}
```

### 2.3 三种扩展的正确方式

| 扩展 | 增加什么 | 不应修改什么 |
| --- | --- | --- |
| 新城市风格 | 群系资源、色板、建筑池、任务和商店池，并登记清单 | 飞行核心、分块调度、任务状态机 |
| 空岛或空中城市 | 岛体提供者或组合规则、浮空结构、上下表面碰撞、空中分布和连接口 | 世界地址仍是三维键，不另写一套加载器 |
| 地下世界 | 洞室通道提供者、入口预留、内部光照与结构池 | 不能通过“把地表高度调低”冒充地下 |

首版夹具应同时检查同一 X/Z 下两个不同高度的可飞空间，以及穿越地表入口进入地下。空岛须能看见和碰到下表面，地表不能把地下通道填死。

## 3 配件定义

### 3.1 原型目录

所有名称与数值为虚构原型内容，不对应真实品牌或实测商品。

| 内容 ID | 类型 | 初始用途 |
| --- | --- | --- |
| base.frame.f5 | 机架 | 5 寸探索套机 |
| base.frame.f35 | 机架 | 3.5 寸轻型套机 |
| base.motor.m5 | 四电机组 | 与两款 5 寸桨叶组配对 |
| base.motor.m35 | 四电机组 | 与 3.5 寸桨叶组配对 |
| base.prop.p5_general | 匹配旋向的四桨组 | 初始通用桨叶 |
| base.prop.p5_smooth | 匹配旋向的四桨组 | 商店取得，响应取向不同 |
| base.prop.p35_general | 匹配旋向的四桨组 | 轻型套机使用 |

分别提供 `m5+p5_general`、`m5+p5_smooth`、`m35+p35_general` 三条动力映射。未提供映射的组合不得默认视为可用。

### 3.2 配件字段

| 类型 | 固定规格 | 可调项的初始设计 |
| --- | --- | --- |
| FrameDefinition | 单机架质量、四受力点、安装孔、最大桨径、结构阻力与碰撞参考 | 相机安装角；确需时增加小范围设备位置微调 |
| MotorDefinition | 单电机质量、安装孔与轴径、动力映射引用、响应参考值 | 有限响应整定，必要时增加 0.95 至 1.0 的推力上限 |
| PropellerDefinition | 单片质量、桨径、桨距、叶片数、轴孔与匹配映射 | 小范围气动校准，明确属于仿真整定 |
| PropulsionMap | 电机与桨叶 ID、推力和反扭矩曲线、响应与参考条件 | 按组件调参规则生成派生映射，保留基准上限 |

套机之间的差异由质量、惯性、尺寸、动力与阻力共同形成，不能只把最高速度乘一个系数。设计时要说明每种配件的取向与代价，不追求“所有最大滑块就是唯一最好配置”。

### 3.3 参数边界

`TuningSpec` 至少包括 `key`、`unit`、`default`、`min`、`max`、`step`、`effect_id`。每件具体配件单独声明，不使用一个覆盖所有同类配件的无限调节页。

```json
{
  "schema_version": 1,
  "id": "base.motor.m5",
  "kind": "motor_set",
  "component_count": 4,
  "mass_per_component_kg": 0.027,
  "tuning": [
    {
      "key": "response_trim",
      "unit": "ratio",
      "default": 1.0,
      "min": 0.95,
      "max": 1.05,
      "step": 0.01,
      "effect_id": "motor.response_time_scale"
    }
  ]
}
```

上例只说明通用字段；实际 MotorDefinition 还需要兼容与动力引用。`response_trim` 明确按响应时间乘数处理，数值增大表示响应更慢，不以含糊的“性能增加”解释。

初始其他建议范围：机架相机安装角 10 至 45 度，默认 20 度、步长 1 度；桨叶气动校准 0.98 至 1.02，默认 1.0、步长 0.005。不同配件可以有不同边界。

`aero_trim` 用于对已匹配动力曲线作一次小范围推力系数标定，同时按映射约定更新反扭矩；不能在飞行器和电机层再次叠加同一标定。相机安装角影响视角，电机响应整定影响动态响应，二者不直接增加最大推力。

有效值必须有限、在闭区间内并对齐步长，考虑浮点误差容许。加载老存档发现越界时通过迁移或恢复默认并提示；普通 UI 请求越界时拒绝并保留旧值，不静默产生非法物理参数。

### 3.4 装配计算与验证

1. 从玩家使用权检查可安装内容。调试模式与正常模式分开。
2. 检查四旋翼、孔距、轴径、桨径净空和旋向配置。
3. 检查电机与桨叶的动力映射存在，映射单位正确且曲线范围有效。
4. 计算整机质量、重心、惯性和四个受力位置，拒绝零或负惯性等非法结果。
5. 应用各组件局部调参，再校验组合上限，避免多个微调叠加绕过安全范围。
6. 检查至少可悬停并有合理推力余量。原型推重比阈值暂以 2.0 为设计起点，由试飞调整。
7. 返回 `ResolvedDroneSpec` 或结构化错误；UI 只展示该结果，控制器只消费该结果。

基础性能映射尚未校准，不能把初始数值宣传为真实硬件训练精度。自由飞行没有电池槽位、剩余电量、续航时间、充电站或消耗库存。

## 4 套机与玩家配置

`DronePresetDefinition` 引用机架、电机组、桨叶组和推荐调参，不复制另一份硬件规格。套机更换可建立一份新的玩家配置，保留用户之前保存的配置。

```json
{
  "schema_version": 1,
  "id": "base.preset.explorer5",
  "frame_id": "base.frame.f5",
  "motor_set_id": "base.motor.m5",
  "propeller_set_id": "base.prop.p5_general",
  "recommended_tuning": {
    "frame": {"camera_mount_tilt_deg": 20.0},
    "motor_set": {"response_trim": 1.0},
    "propeller_set": {"aero_trim": 1.0}
  }
}
```

玩家存档保存选择的 ID 和调参，不修改套机资源本身。机型需要的所有组件权限在授予套机时一起处理；取得套机后的自由换件仍经过兼容校验。

## 5 解锁与获取

### 5.1 状态含义

- `available`：目录中存在并可显示。
- `unlocked`：满足前置条件，可以通过指定渠道取得。
- `owned`：玩家拥有永久使用权，不记录消耗数量。
- `equipped`：某份有效 DroneBuild 当前选择的内容。

部分初始和直接任务奖励可以一次从未取得进入 owned。商店则可以先通过任务解锁上架，再以信用点取得。用户界面须显示清楚“需要完成什么”和“是否还要购买”。

### 5.2 获得规则

统一支持目标类型、条件组与发放包。条件的 AND、OR 显式区分，不用混合标签数组猜测语义。

```json
{
  "schema_version": 1,
  "id": "base.acquisition.light35",
  "target_id": "base.preset.light35",
  "any_of": [
    {
      "all_of": [
        {"type": "mission_tag_completed", "value": "maintenance.relay"},
        {"type": "completion_city_tag", "value": "industrial"}
      ]
    }
  ],
  "grant_bundle_id": "base.grants.light35_complete"
}
```

这表示在 industrial 城市完成 maintenance.relay 标签任务。实际事件携带稳定任务 ID、城市 ID 和标签快照；两个条件必须指向同一次完成事件，不能用甲城市的标签和乙城市的任务拼接满足。

新增渠道时扩展已注册的条件或授予处理器，内容 ID 仍保持数据引用。M4 先实现任务奖励和商店，不提前构建通用脚本语言。

### 5.3 原型奖励流程

1. 新档免费取得 Explorer5 套机、对应三个组件和基础操控配置。
2. 在工业街区修复中继，原子授予 Light35 套机及其三个组件，并奖励 200 信用点。
3. 同一维修任务只发一次奖励，完成事件具有稳定事务键并写入存档。
4. 本地商店以 150 信用点出售 `base.prop.p5_smooth` 永久使用权；已有权利时不再次扣款。
5. 新桨叶可以装在初始 5 寸机上，与另一条动力映射产生可观察的响应区别。

信用点数量为原型平衡参数，以数据定义。目录中的商店不是电池补给点，不提供任何续航服务。

### 5.4 多渠道与未来城市

获取规则可以增加商店或探索作为替代路径。普通配件不因某个随机城市没有生成而永久无法取得；稀有内容可以保留特殊条件，但要在游戏中给出合理线索。

同一任务模板在不同城市实例化时，其完成 ID 与城市 ID 分离保存。地区卸载重载不重置任务和商店权限。套机、组件、货币和事务记录在同一进度快照中更新，保存失败时不显示已永久取得。

## 6 内容升级与缺失处理

- 定义值改变需更新内容版本；迁移已保存调参和装配结果，必要时重新校验。
- 删除或重命名 ID 时提供别名或迁移表；显示名称变化不改变 ID。
- 群系的生成版本与装备数值版本分开，修改电机参数不重新生成地图。
- 旧地图缺失内容包时保留快照和缺失标识，先返回安全部署点，不清除旧世界数据。
- 资源 ID、标签、曲线、单位、引用和获取渠道均由校验工具检查；未知字段或类型明确报错。

## 7 必须通过的内容验收

- 新城市群系仅增加资源与 manifest 条目就能显示不同结构和规则。
- 空岛与地下提供者复用加载器，支持同 X/Z 的多层碰撞与负 Y 分块。
- 新配件只需补定义、必要动力映射与获取规则，不修改飞行核心。
- 所有调参在合法边界可保存恢复；越界、错步长和非有限值被拒绝。
- 非兼容组合和未取得的配件不能通过非 UI 路径绕过检查。
- 任务奖励与购买经过重启和重复触发不会重复发奖、重复扣款或丢失套机组件。
