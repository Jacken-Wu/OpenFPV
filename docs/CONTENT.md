# 群系与装备内容契约

## 内容0.24：稀疏门与随动姿态

世界4、内容0.24.0。新增:spatial，spatial_revision=1、acro_revision=3、route_revision=5。门位由曲线关键节点决定，2～64门、相邻至少8米；曲线采样密度不等于门密度。直线/缓弧保留走线空间，紧弯、转向平面变化及重要拐点保留门。

flight_ups与flight_path一一对应，gate_ups与checkpoints一一对应，均为只读生成数据。门面法线为切线，上方向来自推荐的机体姿态；可以侧倾、倒扣或绕不同轴连续转向。拉升/负俯仰按机体参照系理解，世界高度下降不自动代表负俯仰。实体开口、高亮和过门判定使用同一姿态。

geometry_retained标记狭窄地区保留旧曲线；legacy_frame_constraints表示只在原有安全门位/朝向中选择子集，不将新几何设计指标施加到旧通路。新旧ID共享一次奖励，0.23及更早活动任务原定义、阶段不迁移。地下保持原走廊算法；无新任务类别、倒计时、能源补给或飞行物理修改。

## 内容0.23：按飞行曲线布门

世界4、内容0.23.0。新增:smooth布局，acro_revision=2、route_revision=4；flight_path、gate_path_indices、manoeuvres及design_speed为只读生成数据。每条新路线7～96门、相邻至少8米，门法线取曲线切线，门面不再独立交替倾斜。回环、环绕、S弯、宽弧下降与破S按空间选用；破S描述明确先横滚倒飞再持续拉杆。直立向下弯曲采用较大参考半径，不能用突然压低下一个门代替连续下降。

新路线继承接待平台和history_id/transaction_id；旧任务原航点、门向、实体与存盘阶段不迁移，完成后重接公开布局体验新线。狭窄地点可回退基础环境路线，不强求每区具备全部动作；地下仍沿真实走廊，不套用空中特技生成。无新任务类别、倒计时、周期补给、额外奖励或飞行物理改动。

## 内容0.22：地标的地图可见性

plan.landmarks支持可选map_visible布尔值，默认true；仅控制是否派生地图目的地，不影响该建筑的生成、碰撞、预留体积和任务几何。密集风蚀蜂窝岩设为false，其他地标保持原规则。内容0.22.0、世界仍4，既有任务位置/阶段、首次奖励和玩家数据不迁移。


## 内容0.20：近距技术穿门布局

世界4、内容0.20.0。新增AcroCourses布局后缀:acro，challenge.acro_revision=1、route_revision=3仅为只读定义版本。接待平台不移动；共享原history_id、transaction_id及首次奖励，已接历史任务保留原航点/门向/实体，重新接取公开新版才体验新线。没有新增任务类别、倒计时或额外奖励。

地表/天空航线最多36门，最短航段8米、节点折角至132度，混合水平近而垂直高差明显的叠门、左右变线、升降折返和长航段。相邻门面允许较大变化，但进/出方向均与门法线点积不低于约0.342。建筑、地形、旧任务实体和门框净空均约束候选；无安全候选保留原腿或原路线。原迷宫路线继续沿实际通道，不强加地表叠门算法。三种子有限样本统计和生产实体检查见VALIDATION，不保证每个地区都具备同样密度的动作。

## 内容0.18：建筑附着任务和复杂洞网

世界仍4，内容0.18.0。precision_revision=1仅标识新布局，不承载玩家状态；history_id/transaction_id沿用原任务，兼容活动旧任务与一次奖励。修复、顺序终端半径2.3米，持续交互和速度限制不变；新终端至少110米分隔。巨构无碰撞13节点、半径2米，跨楼层/廊道/竖井；城市/废城穿门半开口2.5/2.2米，长短距离与高差混合，门向衔接前后航段，无倒计时。

未修复废城平台只显示任务要求，服务页面与传送均在三条线路完成后开放。每个适宜山地区域最多一组复杂洞网替代多条直管，主洞半径约5.2～8.8米、支洞4.2～5.6米，宽厅约8.2～10.2米。保护接待平台、任务与地下入口；几何、路线均按种子生成，候选不足时保留安全旧路线或不生成洞网。

## 内容0.17区域结构与特殊任务

群系parameters新增feature_profile（ruined_grid/honeycomb_rocks/megastructure/volcanic_causeway）、caves布尔值、regional_tasks数组。每条区域任务定义mode、title、description及可选portal_required，不在共享资源上写入玩家进度。

失落废城区三条repair任务各有三个分离终端，E持续1.2秒、4米内、速度不超过3m/s；全部三条曾完成才开放当地传送网络。巨构sequence使用四象终端，E持续0.35秒；clean使用十个立体节点、无时限、触碰实体重置本次路线。方向随种子旋转，模块楼层与外观随种子变化。普通/特殊任务合计最多五个；三个模式统一作为“区域解密”类型进入成就统计，原已解锁成就保持。

戈壁每区最多26块尺寸各异的多轴蜂窝岩。山地/峡谷/火山区每区最多三条穿山洞，半径6～8米，优先保证山体厚度、洞口衔接和净空，候选不足时不强行重叠。巨构52米模块带22米中庭，40米层高、连通多层平台和竖井；火山熔光、喷口和环形高架是探索景观。世界4、内容0.17.0，不增能源补给。

## 内容0.16：八种地貌、结构池与跟拍覆盖率

新增15群系中的八个资源：alpine苍脊高山（岩脊/岩门）、snow_peak银冠雪山（高峰/冰门）、snowfield寂光雪原（缓丘/冰门/贯通住宅）、ruined_city失落废城区（断壁建筑簇/管堆）、monument远古巨构遗址（巨石三重门/渡槽）、ravine赤壁深峡（深沟/落地岩门/渡槽）、gobi砾风戈壁（砾台/基站/管道）、volcano玄焰火山（环形山口/玄武岩熔光门）。使用现有canyon提供者及terrain_style、terrain_low/high参数描述差异；extension=true、min_world_version=4，外围独立抽签，原五种气候原型不增删。

新增11种结构键：construction/open_house/playground/pipe_stack/billboard/tri_billboard/mega_ruins/broken_blocks/rock_arch/ice_arch/lava_arch，合计24种。lot_pool选择外部城市地块，屋顶选择管道或三面广告架；landmark_pool.chance仍为0～1，新增count整数1～6，有限候选不满足净空则不强塞。住宅门窗/屋顶口、中庭井、管腔、三面架中心、巨构门洞均没有填充碰撞盒。所有定义只读，运行进度不写资源。

跟拍挑战revision=2：duration=30秒为最短时长，coverage=0.8分别约束visible_time/elapsed与near_time/elapsed，range=50米为三维机体距离。实际视锥并且无遮挡才可见；两项不要求同一时刻成立，不再要求5～22米/同向运动/60米连续行程。失误可继续拍摄恢复比例，旧活动跟拍只重开本次拍摄，已领信用/装备不变。当前任务ID保持，竞速、环绕、气球规则不随之改动。

新群系每个独立原创循环曲，标题与乐谱见audio/music/scores.json；旧七首不重写。事件音由GameEventAudio原创合成，复用Effects总线，没有外部音源、模型或新依赖。

## 内容0.15：环绕参数与穿门提示

内容0.15.0、世界仍4，不改变任务ID、门坐标或已接阶段。环绕challenge.radius_min/max地表与天空6/28米、地下3/7米；height_tolerance为6/3米，view_angle为55度。环绕进度是净弧度、允许偏离后接续，不再要求连续完美镜头；跟拍定义不变。target_point同时定义视觉球体和检测中心，引导圈以其为中心。

门框gate_half含义保持不变，检测使用现有实体条的真实内边缘。过门与终点提示由FlightAudio原创合成，不向共享任务资源写运行状态；中间提示跟随保存成功的阶段、终点提示跟随保存成功的完成事务，重玩仍有提示，首次奖励账本不变。

## 内容0.14：路线版本与挑战开始

世界仍4、内容0.14.0。新增的生成路线键为proc:4:<层>:<x>:<z>:<槽>:play:flow，原:play及六段任务继续解析。MissionDefinition.history_id仅描述同一任务不同路线的历史身份，transaction_id按该身份共享首次奖励；assignment.history_id保留完成计数归属，不能重复累计同一任务的成就。定义、运行状态与奖励账本保持分离。

FlowCourses根据现有道路、建筑、地形、岛群和迷宫图生成路线，checkpoints/gate_normals继续是只读定义；challenge.route_revision=1，gate_half地表/天空3米、地下2.5米。相邻方向不逆折，门朝向连接进出方向；实体及气球升空柱预留净空，随机过程确定且有界。历史实体legacy_objects只在旧任务活动时实例化，不在普通新路线旁堆放同样的塔和框。

气球balloon_revision仍2，新增运行started=false等待现场启动，不依靠远程接取的坐标猜测是否到场。准备3秒；release_interval地表/天空2.5、地下1.5，rise_speed分别1.8、0.7。地表/天空height_limit为最高发射点+45米且≤295，地下为实际顶棚下2.5米。旧无started的活动气球恢复为等待，不追回奖励或重置账户；等待状态不可保存命中/计时/失败。

## 内容0.13：平台与气球规则

pickup_platform包含point/top/half，仅定义接取几何；玩家状态继续位于assignments。平台在三维上至少间隔48米，不改变旧任务ID或已存巡检阶段；旧巡检框不再是悬停接取入口。未接任务的地图位置指向平台，领取后导航指向实际目标。

气球challenge包含balloon_revision=2、release_delay=3、release_interval=3、rise_speed、height_limit；checkpoints为间隔开的发射位置，放出高度由本轮elapsed推导。地表/天空0.65m/s、地下0.3m/s；限高最高发射点+28米且≤295米，地下改为顶棚下2.5米。上升柱为气球半径/摆动预留净空，后续特色建筑/植被避让。未接取无气球，全部命中成功，任一越限则failed；重新接取清本轮数据，只有首次成功发奖。failed状态与布尔字段通过存档校验；旧缺revision的活动气球只重开本轮，不重置其他进度。内容0.13.0、世界仍4；碎纸和空间破裂声均原生代码生成。

## 内容0.12.1：可重复任务

定义与生成布局不变，世界保持4。运行assignments新增completion_count，缺字段按旧completed/奖励事务/已解锁设施判定首次已完成；本轮active/completed与历史奖励资格独立。首次奖励之外，重复挑战不额外授予信用或装备。首次条件和成就不因重新接取回退；成就按完成过的不同任务计数。三态入口标签及地图明确标注重复无奖励，不引入内容ID分支。

## 内容0.12：任务池、商品和成就

旧mission_templates五项的顺序/数量和生成随机序列保留；新challenge_templates独立列出race、balloons、orbit、follow四项。MissionCourses使用独立随机流替换公开任务槽，数量仍2～5；旧六段proc:4键保留解析/几何，新布局键追加`:play`。后续改动该布局或随机池时必须再版本化，不能让已存阶段对应另一个任务。地下原地图解锁任务不替换，高于250米的岛节点保留原任务，给新门框及航线留出300米保护线下的空间。

新增任务字段gate_normals、challenge、pickup_points只描述内容；stage、hits、elapsed、orbit、direction、distance等玩家状态仅在assignments中。Balloon_radius/门宽/运镜距离与角度由生成定义给出；无任务截止时间。旧巡检门和被替换任务实体可以接取对应新挑战，老已接任务仍可在原实体完成。

| 套机 | 定位 | 整机价格 | 机架 / 电机 / 桨叶价格 |
| --- | --- | ---: | --- |
| 花飞5 | 快响应、高推重比、穿门花飞 | 390 | 150 / 180 / 90 |
| 远景6 | 较大机臂与6寸桨，沉稳运镜探索 | 480 | 190 / 220 / 110 |
| 影航3.5 | 紧凑机架、平顺近景运镜 | 580 | 240 / 260 / 130 |

新九件PartDefinition、三件DronePresetDefinition和十一条PropulsionMapDefinition（含新旧电机/桨叶的交叉匹配）显式登记。保留原两套机及商店两项，共五套机、十六配件、十四商品；所有拓扑仍四旋翼/四同型电机/四匹配桨。商品说明写定位、桨径与安装规格；分类根据目标资源类型产生，不在飞行或购买系统按具体ID分支。购买套机授予全部三类部件，既有永久所有权不回收。

普通生成任务奖励100→30信用点；新穿门/气球45、运镜55。旧固定中继奖励200→60（原装备授予保留）、固定摄影150→45；不追溯减少已有余额。完整新套机相当于约9～13个45点挑战或13～20个30点普通任务，单件允许更早取得；实际节奏仍待玩家体验调节。

八个AchievementDefinition按missions/portals/biomes/mission_types/presets指标定义目标，target=0仅用于“全部群系/全部类型”。任务类型八类：交互、摄影、勘测、快递、航线（旧巡检/新穿门合并）、扎气球、环绕、跟拍。成就无资源/信用奖励；玩家achievements只存解锁时间和已完成类型/已解锁群系，属于世界存档而非控制设置。旧完成记录/地图/平台补记，不重复任务奖励。

## 内容0.10：群系配乐

BiomeDefinition新增music: AudioStream和music_title: String；七个内置群系资源显式引用game/audio/music/*.wav，不在飞行或任务系统按群系ID分支。曲目由tools/ComposeMusic.py原创生成，16小节，可用Python标准库重新生成；scores.json保留音符、和声与节拍。WAV smpl声明全长前向循环；ContentCatalog校验已绑定音乐的格式、循环及标题，指纹覆盖音频数据摘要。新增群系允许不绑音乐（进入后淡出）；绑定时必须是带标题的循环WAV。

| 群系 | 曲名 | BPM | 循环时长 |
| --- | --- | ---: | ---: |
| 锈港工业区 | 齿轮与晨光 | 112 | 34.29秒 |
| 青穹街区 | 绿庭的像素风 | 96 | 40.00秒 |
| 赤陶旧城 | 赤陶巷弄 | 104 | 36.92秒 |
| 风蚀峡谷 | 峡谷回声 | 84 | 45.71秒 |
| 松风山谷 | 松针间的溪流 | 92 | 41.74秒 |
| 浮岛群 | 云端轻航 | 108 | 35.56秒 |
| 地下迷宫 | 深层寻路 | 80 | 48.00秒 |

使用有限谐波脉冲波、三角波和短噪声打击乐塑造8bit风格；保留16位PCM以降低量化噪声，不取用外部音乐或采样。

版本 0.9，2026-10-23。P1 已有内置 Resource 与 `.tres` 管线。实际字段与新增步骤以 [IMPLEMENTATION.md](IMPLEMENTATION.md) 和 `game/content/base/` 为准。除下方第 8 节实际地图地点外，本文 JSON 为完整目标示意，不能原样作为 P1 可加载资源。

## 0 P1 对应关系

实际为 ContentManifest、PartDefinition、DronePresetDefinition、PropulsionMapDefinition、BiomeDefinition、RewardDefinition、OfferDefinition、MissionDefinition；所有配件共用 PartDefinition，而非分别建立 Frame/Motor/Propeller 类。版本集中在 manifest；来源许可集中记录于 ASSETS.md，尚无每个条目的 schema_version 与 license 字段。

TuningSpec 当前为带 min/max/default/step/unit 的 Dictionary，作用由装配器的三个已实现参数绑定。获取规则当前是任务标签和城市标签的 AND，加平台商店；已有显式任务模板池，尚无通用 OR 条件图、条件循环校验或可视化结构池编辑器。BiomeWorld 返回独立群系计划及分页收集 Dictionary，WorldProvider 输出三维盒/柱体与地形网格描述。不要根据后文目标字段假设功能已存在。

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

## 8 实际地图地点清单

`game/content/base/map_locations.json` 为已实现的地点数据，独立于装备 / 群系 manifest。每条含唯一 id、name、kind（teleport / shop / mission / landmark）、point（世界米制 X/Y/Z）与 description。只有 teleport 可传送；不得为了让商店更易到达而把商店本身标成 teleport，应另设附近传送点。

approach 是可选的三维参考航点数组，interior_bounds 为 `[x,y,z,width,height,depth]`。当前地下样本通过这两项声明竖井与内部范围，进出按顺序或反序引导；不代表经过碰撞规划的安全路径。新增地点不需在飞行、加载或任务系统里添加具体 ID 分支。定义保持只读，选中和到达状态由 MapNavigation 独立保存于运行内存。JSON 已显式纳入导出过滤；更改须运行 map 检查并验证包内数据。

## 9 实际任务资源

任务使用 MissionDefinition 与 .tres，由 manifest.missions 显式登记。已有 relay_mission.tres 和 sky_photo_mission.tres，共用领取、追踪和奖励流程。必要字段为 id、display_name、description、kind、location_id、reward_id、mission_tag、city_tag；reward_id 必须指向 RewardDefinition，并匹配任务与城市标签。location_id 必须存在于地图清单，地点类型不因任务追踪而变成传送点。

hold_interact 声明 facility_id、target_point、interaction_radius、hold_seconds、max_speed。生产交互使用这些参数，地图位置负责指引；更换任务内容无需在任务系统新增具体 ID 分支。设施模型与闸门效果仍由主场景实例化，没有通用世界实体编辑器。

photo 声明 target_point、target_bounds、min_distance、max_distance、max_angle_deg。target_bounds 用于识别物理射线的首个碰撞是否属于拍摄目标；不能把遮挡物也纳入目标体积。当前观测站要求 15～65 m、中心角不超过 18°，其目标中心与建筑体积匹配浮岛提供者；移动建筑时应同步修改任务目标。世界公共输出仍是三维几何。

校验包括任务类型、地点引用、奖励和标签、重复事务、有限三维点、交互时长/半径/速度、拍摄距离/角度/体积。任务资源不保存领取、完成、照片或追踪状态，这些存放在 ProgressStore。新增任务后运行 missions 组及正常窗口、包内验证。当前仅支持两个目标类型，无多阶段任务、条件图或任意脚本执行。

## 10 世界v2内容与视觉参数

本轮资源清单content_version=0.3.0，world_version=2。新增oldtown.tres与pine_valley.tres；原有工业、园区、峡谷、浮岛、地下定义保留。新群系parameters.min_world_version=2，旧世界只加载原有5个群系。地表范围按64m网格边界设置，避免一块横跨多个城市布局规则。

modular_city的architecture可为industrial、garden、oldtown；building_min/max为4～48m以内且有序的有限值。更换颜色或同类风格只改资源；新增提供者同时登记WorldGenerator和ContentCatalog支持清单。林地clearings为世界位置数组，用于排除起降区域附近的树木和岩石。群系校验覆盖提供者、层、三维包围盒、建筑范围与风格；尚未声称所有任意扩展参数均已校验。

表面类别在纯几何描述的surface字段声明，渲染器按类别创建材质；不用颜色猜测物体类型。当前纹理全部由项目代码生成，无外部素材。地形primitive=terrain时附加顶点/法线/颜色/索引/表面分组，三维块、浮岛和地下仍共用公共描述与加载流程。新算法必须另升版本并提供相应迁移策略，不能静默修改LegacyWorldProvider的v1规则。

## 11 v4 当前数据入口

manifest.world_version=4/content_version=0.5.0。generation_rules声明surface_spacing、warp、sky_spacing、sky_chance、maze_spacing、maze_chance，校验有限非负值、间距至少512 m、概率0～1；规则参与内容指纹。地表五类BiomeDefinition.parameters.climate为有限Vector3（温度、湿度、聚落偏好），参与气候最近模板选择。

BiomeField决定不规则地表边界及独立空中/地下实例分布；BiomeStructures输出随机岛群或连通迷宫；BiomeWorld组合平台、实体目标和任务。512 m地图页仅收集重叠计划，不强制生成三种群系。每实例1～2个平台及2～5项任务，任务按结构节点布置，不再每个平台固定两个任务。

mission_templates显式列出survey/circuit/courier/relay/photo_template.tres，统一引用exploration_reward.tres。模板类型、奖励标签和交互/摄影参数经过内容校验。生成目标独立复制，checkpoints必须赋新PackedVector3Array再追加；领取、阶段、奖励及照片状态只存在ProgressStore。

OfferDefinition二选一使用part_id或preset_id。Light3.5商品包含配套全部部件，150点柔和桨叶与300点套机均为永久权限。平台合并商店和装配，不另建可直接传送的商店地点。

MapLocation新增structure_id及layer，连接实际群系实例和高度层；地点仍按kind限制传送。地图多边形、岛体范围、迷宫墙线来自真实生成计划，玩家选中状态不写入模板。任务ID按proc:4:layer:x:z:slot重建，服务平台按v4:layer:x:z:pN重建。

第8～10节中静态JSON、两个固定任务和v2范围属于历史夹具说明；生产世界不读取静态地图地点。结构池仍由提供者代码组合，尚无通用结构资源编辑器。修改几何规则应升世界版本，本次按用户无需保留旧档的授权重建旧世界。

## 12 内容0.6探索契约

几何world_version仍4，content_version=0.6.0。BiomeDefinition.parameters.map_unlock可选visit/mission，未知值拒绝加载。地下定义使用mission，其他定义默认visit；指定解锁任务从既有实例任务稳定选取，不改变proc:4ID或目标。完成任务与地图解锁在同一原子事务提交。

ProgressStore.exploration保存visited/mapped/portals的稳定实例ID集合，内容Resource只读。地图访问解锁不等于平台传送登记；平台需真实停靠交互。既有v4档缺字段时初始化空记录，再从实际部署群系开始发现，不推断全部周边已探索。所有已解锁群系保留在地图历史，物理分块加载不因此扩大。

任务与地图共用RegionMap，显示任务按当前阶段目标的三维距离排序并分页；详情、领取与选中不改变模板。操控设置独立镜像在controls.json，世界重建保留settings，旧备份可恢复缺失配置。不可用重建地图来清空用户遥控器配置。

## 13 内容0.7现场目标修正

生成世界版本仍4，内容0.7.0。快递、勘测与校准的判定位置位于ground+(0,1.2,3)，对齐实体设施前方可接近空间；不改已有稳定ID或已保存阶段。现场奖励条件、范围、速度和时间继续由MissionDefinition定义，巡检/摄影另有实体中心目标。

临时路标仅为运行内存中的landmark，不属于内容资源、任务奖励或传送集合，不保存为已解锁地理。解锁信号只在原子提交后通知UI。0.7的1500m/1400m规则已由0.8替换；世界公共接口继续返回三维结构。

## 14 内容0.8调试入口与声音

世界生成版本仍4，群系规则/种子/稳定ID未改变。BiomeField.volume_site统一独立浮岛/迷宫站点规则，BiomeLocator通过目录取得全部群系模板，用完整ID、简写或中文唯一片段定位最近生成中心，并返回实例真实平台。定位不写玩家状态；未来新增地表模板无需向控制台添加具体内容ID分支。

300m/280m保护属于飞行规则，不按装备或群系ID分支。合成音效属于运行时生成资源，不保存在共享内容Resource中；四电机按解析后的max_thrust归一化实际输出，不写死某套机的声音分支。素材来源见ASSETS.md，具体接口见IMPLEMENTATION.md。

## 15 内容0.9建筑内容池与存档

七种群系在parameters中声明lot_pool（城市地块变体的kind字符串数组）与landmark_pool（kind/chance字典数组）。kind必须属于Architecture.TYPES；chance为有限0～1数值。地表模板直接由目录取得池，不将具体群系ID写入飞行、加载或任务状态机。

| 群系 | 主要特色池 |
| --- | --- |
| 锈港工业区 | 格构通信塔50%、开放机库55%；城市地块还可为候车站/双塔 |
| 青穹街区 | 公园65%、亭45%；地块混合公园/亭/候车站/双塔 |
| 赤陶旧城 | 古院60%、渡槽28%；地块混合古院/亭/公园/候车站 |
| 风蚀峡谷 | 金字塔28%、渡槽32%、遗迹45%、野外基站30% |
| 松风山谷 | 遗迹50%、基站38%、亭38% |
| 云海浮岛群 | 环廊60%、遗迹30%，另检查岛面范围和限高 |
| 地下迷宫 | 涡轮厅68%，只放房间并保留走廊导航高度 |

概率为每实例、每种特色建筑的候选掷骰概率；还需通过地形、净空和与服务/任务/入口的间距检查，实际出现率会更低。可以全部不出现，位置/种类不会绑定512m地图页；城市48%合格地块再从lot_pool均匀选原型，旧跨路桥独立22%出现。独立随机流不改变已生成任务、站点或地形采样。同种子/同内容版本冷重建一致；0.9刷新旧v4的建筑外观，不清进度。

大结构使用分块中心所有权及群系边界外伸查询；对实体斜梁同时应用网格和碰撞旋转。金字塔10m宽/12m高穿越通道、机库/双塔中庭/塔架内部是可飞空间；不是空心可用完整建筑室内系统，没有任意破坏、通用建筑编辑器或全局避障。

存档save_name/save_created/save_updated为玩家快照元数据，不写共享Resource。新世界和旧世界使用独立文件/事务备份，active指针只记录槽ID；跨槽加载使用当前玩家settings，装备/任务/信用点/探索仍属于各自世界。详情见IMPLEMENTATION.md。
