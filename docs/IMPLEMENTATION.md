# P1 当前实现与扩展入口

## 内容0.24实现补充

- AcroCourses在完整重建0.23定义后调用SpatialCourses。新ID追加:spatial，spatial_revision=1、acro_revision=3、route_revision=5；旧定义/实体进入legacy集合，共享history_id和接待点。解析器同时支持基础、acro、smooth及spatial组合。
- SpatialCourses从未整平的基础环境路线建立曲线，原节点以8/15/32米半径混合圆整，半径不按世界Y分类。各段在倾斜平面生成回环、半回环，或让横向位移平面沿曲线连续旋转形成螺旋/空间S弯；端点切线匹配。候选统一抬升仅用于避让实体，不会把整段高度重写成同一值。
- 布门使用三维折线简化、约80度累计转向和紧弯顶点，再合并重复选择；形状误差参考5米，门距至少8米、最多64门，没有固定弧长布门或最少7门要求。180米直线只保留两个门，缓弧不再因内部细采样产生密集门。自交允许，但会移除挡住另一分支的非必要框。
- 姿态采用相邻切线四元数平行传输，以曲率向量选择拉杆上方向，再解包并平滑滚转角；不在竖直处切换世界up。新设计参考负俯仰曲率<=1/40m、沿弧长滚转<=30度/m，正向拉杆可朝任意世界方向。此为几何/推荐姿态筛选，不更改飞控、重力或真实玩家输入。
- challenge.flight_ups为细采样机体上方向，gate_ups与checkpoints一一对应。FlightChallengeRules.gate_basis_for统一生成实体框、开口局部坐标、高亮与数字位置；RaceRouteGuide的箭头十字翼也沿同一上方向。门的滚转只给姿态提示，不要求机体姿态必须与框一致才计分。
- 原曲线在狭窄区可仅稀疏化：geometry_retained标记几何完全保留；必要时legacy_frame_constraints只取既有门的子集并保留其原朝向，沿关键门平滑传递姿态，不将新设计曲率指标追认给历史通路。实际实体净空仍逐段检查。新框还要避开其他竞速任务的整条曲线，避免处理顺序使后一个任务的框堵住前一个任务。
- 新路线检查完整曲线、进场、旋转后的框边、其他框、地形、浮岛、建筑与气球区域；稀疏门之间的直线弦不再作为必须飞行的路线。天空仍不得越出原地区范围。refinement/gameplay验证实际曲线和旋转后的真实开口，保留历史路线原直线断言。

## 内容0.23实现补充

- AcroCourses先精确生成原v1供历史活动任务解析，再调用ContinuousCourses发布:smooth布局；解析器兼容有无:acro/precision的前缀。acro_revision=2、route_revision=4仅属于定义，ProgressStore仍独立保存玩家状态。
- ContinuousCourses从基础环境路线选取连续段，消除小幅高度抖动，以相切Bezier圆弧圆整折点。水平/拉升参考半径10/12米，直立向下弯曲40米；候选空间不足就缩短或恢复基础布局。S弯端点横向导数为零，幅度按曲率限制；回环以正弦/余弦加前向漂移分开进出门，半径至少22米，破S先直飞离开浮岛，再倒飞拉杆下降并反向水平出弯。
- 曲线采样步长约1.25米，门沿弧长约12米布置、门距至少8米、最多96门；法线直接取解析切线，进/出门连线与法线点积均不低于0.70。challenge.flight_path与gate_path_indices保存只读曲线和门采样索引，manoeuvres记录实际入选动作。不是飞行速度限制或任意速度的动态可飞保证。
- 检查整条曲线、门间弦线、14米进场、全部门框边和其他门框的净空；城市不得越过已检查建筑范围/地区，天空航线保留在原地区包围体内，为浮岛网格分区加入保守实体包围盒，并检查下方真实地形。失败不删除实体来强行通路，基础环境回退也保留旧acro定义和实体。
- RaceRouteGuide按同一采样曲线构造每段无碰撞ArrayMesh管线和沿切线的箭头，仍按门分段着色、提交进度后移除、保留遮挡/菜单/拍照/浮动原点行为。旧路线无曲线数据时沿用原直线显示。

## 内容0.22实现补充

- RegionalFeatures为hollow_rock元数据增加map_visible=false，BiomeWorld只跳过MapLocation创建，plan.landmarks及真实chunk几何/碰撞/预留保持。通用字段避免在UI或飞行系统按内容ID分支。
- 默认Mobile渲染器走RenderingDevice原生Vulkan路径，避开原GL Compatibility的世界/Canvas合成路径。保留Godot自身硬件回退；可用--rendering-method gl_compatibility作诊断对照。依据是用户截图黑块覆盖HUD，尚未在本机重现同样故障；不是已证实OpenGL驱动错误。
- NavigationHUD在相机平面附近不做深度除法，边缘方向由相机局部方向及投影轴比例给出；非法目标或结果不进入_draw。FlightEffects空闲时不提交透明矩形，警告等级改变和快门消退仍触发清屏重绘。
- AboutMenu由PauseMenu.about_requested进入，两个只读可滚动页展示项目MIT和Godot/第三方全文。Build导出前同步根LICENSE和当前引擎声明到game/legal，两个预设显式包含legal/*.txt。--build-info输出许可完整性/哈希，Build与本机原文逐字节校验。
- Build只清理builds/<渠道>内明确由旧脚本生成的README/许可证/docs，递归删除前校验绝对路径边界；Release不允许除OpenFPV.exe以外的输出。Test-Distribution同时断言两个渠道无外部分发文档，Release仅一个文件，仍执行四次真实进程隔离和独立exe检查。
- 新city_render_tests使用隔离seed1919810、同位置、挂载FPV相机/完整HUD与repair第三阶段，1200帧读回检测大面积近纯黑并保存异常。它会同步GPU，不可替代真实录屏故障复现。about_tests验证菜单/全文/返回，导航增加相机平面/NaN保护，regional_world验证蜂窝岩隐藏及其他建筑地图目的地保持。


## 内容0.21实现补充

- NavigationHUD保留label_anchor，只在已有锚点确实碰撞时换位；当前目标切换重置。面板用instance_id标识，避免通知数量变化导致锚点错位。bottom_panel来自真实底栏，底部箭头标签固定于其上沿外12像素；圆点/三角的真实投影不变。
- Main首次、切档与世界扩展时统一generator.regions=store.regions。BiomeWorld保留48份完整计划，并以128份不含chunks/shape的summary保存任务/地图元数据，16页合并结果供region查询；任务解析可复用summary。所有缓存仅是确定性内容，玩家运行状态仍在ProgressStore。
- WorldStreamer另有一个后台地区预热任务，按距离准备当前及相邻八页，最多保留16个预热标记。换世界/退出时等待这些任务和分块任务；线程只创建自己的数据/碰撞Resource，场景节点及共享材质只在主线程创建。
- WorldGeometry.prepare_chunk生成局部顶点、分材质索引、凸/凹碰撞资源和批次变换；begin_chunk/advance_chunk共用同步创建与流式创建路径。地形逐材质面、碰撞节点和批次按预算推进，暂存根不入树，不计入active；完成后依据当前origin_offset定位并发布。移出范围会丢弃未发布根，原点平移期间不出现旧坐标残留。
- 退役块即刻hide并将StaticBody3D层/掩码设0，随后每帧最多销毁一个块，避免一帧集中释放整排地形；活跃块和真实碰撞就绪判定不放宽。WorldMaterials启动准备固定18种纹理，避免新群系首次材质生成阻塞飞行。
- MultiMesh显式设置含旋转/缩放的保守custom_aabb，32米分组限制整个街区统一进出投影；超过32米的大盒体细分面，平面ground不自投影但仍有碰撞/受光。方向光保留480米覆盖和320米pancake，两级级联在0.18处分割并混合；没有关闭建筑/山体阴影。
- Setup-ExportTemplates额外准备openfpv_windows_*私有模板。Prepare-ExportIcon/windows_icon.cs仅供PowerShell构建时调用Windows资源API，写七尺寸RT_ICON及原有RT_GROUP_ICON；Build实际读取成品七个资源逐字节检查，另通过Windows提取关联图标实测。游戏仍是Standard/GDScript，未换.NET或自编译引擎。render_icon.gd以Godot原生SVG栅格器生成ICO/PNG。
- 新streaming_tests验证未完成块不可开放飞行、实际碰撞、取消/换世界、退役无幽灵障碍、旋转缩放批次边界、道路不自投影且楼体仍投影。Dummy RenderingServer的MultiMesh transform读回无效，headless检查准备数据，窗口检查实际GPU资源。Bench-Streaming提供独立最大化窗口连续跨区对照，不并入常规35组入口。

## 内容0.20实现补充

- NavigationHUD.marker_state使用完整有效视口和Camera3D投影，只有视口外/镜头后转为边缘箭头；label_rect独立选择避开真实Control矩形、中心准星及主圆环的文字框位置。Main使用CanvasLayer21绘制导航，准星为其高z_index子节点；照片即时隐藏，避免一帧残留。
- NavigationRoutePreview复用四条无碰撞圆管与三个Label3D，仅对corridor_route显示当前及后三段；线段110米、后续点90米内，点投影距离小于36像素则让位给当前或更近点。深度测试开启，不穿墙显示未来路线；根节点以当前航点为锚，原点平移同步，菜单/照片及到达隐藏。
- AcroCourses在PrecisionCourses后生成有界候选，保留现有建筑和接待位置；最多36门、段长至少8米、节点折角不超过132度。近距叠门与左右/上下变线按种子变化，实际地形/实体及门框探针不通过就回退安全旧腿/旧路线。门法线取进出方向平分并交替小幅倾斜，两侧点积均至少约0.342，防止急转出口撞上本门横梁。BiomeWorld解析可选:acro后缀，旧定义/实体进入legacy集合，共享历史奖励身份。
- project.godot用Godot内置release特性覆盖use_custom_user_dir：源码/Debug沿用原目录，Release独立OpenFPV/Release。不是仅换进度JSON路径，也不自动迁移开发设置。Main的--build-info只输出实际模板身份与数据目录后退出。
- export_presets分别Windows Debug/Windows Release，采用匹配原生模板；Release embed_pck=true且无控制台副本。Setup-ExportTemplates检查4.7.2版本，仅缓存Windows x64模板；可导入本机安装/归档，显式-Download才联网。Build实际运行程序、确认配置/模板/目录并校验源码与导出内容指纹，Release附分发声明，Debug无README/许可证。
- 原生模板不提供编辑器--script入口。Test-Distribution使用受限--distribution-probe入口和BuildChannelProbe，仅操作user://tests/distribution_<nonce>下的测试档/照片，不接触玩家profile；四次进程分别验证Debug/Release写入和重读，再将Release单exe复制到新目录冒烟。正常窗口专项使用源码引擎，原生Release另做实际窗口巡检，不混淆两类证据。

## 内容0.19实现补充

- FeatureGeometry.ground_fragments按与WorldProvider一致的全局4米网格、对角线和原顶点高度裁切洞壁/端面，替代平滑高度的端点插值。共用高度缓存限制重复采样；CaveNetworks为入口添加独立extension_a/b并生成所有地下端面，CavePassages的减体积平面使用同样端部扩展。
- RaceRouteGuide使用无碰撞圆管与交叉箭头显示剩余航段，当前金色、后续青色。以任务acceptance_point为局部原点，继承MissionChallengeView的浮动原点更新；提交后的阶段变化重建，停止追踪/完成移除，set_labels_visible同时隐藏菜单/照片指引。方向和判定仍来自原checkpoints/gate_normals，不更改任务进度规则。
- 项目LICENSE为用户选定的MIT；Build同步中文README、LICENSE及引用开发文档，继续独立提取Godot和第三方声明。README仅保留当前操作和已验证构建方案，版本历史在开发/验证文档中保留。

## 内容0.18实现补充

- MapNavigation.place_temporary新增track_now，RegionMap传false。已有活动临时点更名temporary.active，新预览使用temporary；所有判断按layer而非固定ID。WorldExploration刷新保留两者，明确追踪才清掉旧临时目标。
- Main._show_workshop在unlock_portal失败时立即返回；平台提示与地图详情统一说明修复要求。第三条precision修复完成时按共享transaction_id匹配原portal_requirements，保持同一事务解锁。
- PrecisionCourses在RegionalFeatures之后、CavePassages之前读取真实楼板、立面与生产城市描述生成新任务定义。repair/sequence终端间距至少110米，race按净空候选生成有界随机路线，clean沿巨构廊道、竖井和跨层路线。门朝向取相邻航段角平分；平滑转向及机体净空另行验证。无安全新布局时保留原路线，不删除建筑来强行通路。
- precision定义保存旧history_id，旧定义和实体进入legacy集合；解析同时支持原ID、flow和precision。公开列表隐藏已替代历史定义，活动历史布局仍按原阶段实例化，同一位置不重复接取。旧/新完成共享奖励身份，不增加信用点或成就重复计数。
- CaveNetworks产生16个棱柱体积（主路、回环、岔洞和厅室），FeatureGeometry.tunnel支持倾斜截面。内壁面依其他体积做多边形差集，移除交汇内墙；BiomeWorld以flattened叶体积切割真实地表。完全埋藏管段跳过重复地形裁切以控制冷生成成本，仍有加载长帧。
- FeatureGeometry.quad/triangle根据外法线统一顺时针索引，修正双面材质外侧被当背面反转法线的光照错误。城市叠片增大间隔；WorldMaterials用mipmap各向异性过滤，项目开启4倍MSAA。FPVDrone._update_camera_clearance在装备/窗口变化时包住实际倾斜近裁剪面，持续使用实体扫掠而非高度钳制。

## 内容0.17实现补充

- RegionMap.viewed_id与MapNavigation.selected_id分开；图标/列表/F3仅更新前者，详情、传送按钮与地图选中圈读取viewed_id。“追踪”对活动任务调用原控制器，对其他任务接待点、平台和地标只切换导航，不取消已领取任务；空白地图原临时路标入口保留。
- BiomeWorld管线在FollowCourses之后接RegionalSites、RegionalFeatures、CavePassages，再生成地标位置和分桶。新:regional ID独立解析，移出的普通任务保存在legacy_missions/legacy_locations，旧任务ID、阶段与首次奖励身份保留；本轮有意调整的戈壁地形继续按种子生成位置。群系参数feature_profile/caves/regional_tasks定义内容，Catalog校验参数和模式。
- RegionalChallengeRules按repair/sequence/clean处理阶段、持续交互、错误顺序及接触序号，FlightChallengeRules统一完成/存档校验；Main传入真实速度、交互与FPVDrone.contact_serial，物理接触、扫掠拦截和显式重置均递增序号，暂停不递增。MissionChallengeView显示世界坐标终端符号和编号环。
- ProgressStore.portal_repair_status按本实例portal_requirements计算首次完成数量；portal_unlocked/unlock_portal双重拦截。第三条完成的同一事务写入奖励、完成记录和全部当地门户，提交成功后通知，失败不发奖也不开放。旧门户账本不删除，重玩不重新锁定。Workshop在网络离线时仍可使用。
- RegionalFeatures通过种子BFS连通模块、残楼网格、体素风蚀岩和环形火山景观构造可飞空间；新增实体避让平台、气球柱、竞速及无碰撞路线与地下竖井。巨构替代旧孤立mega_ruins，但在旧航线定义生成后才移除旧塔，不更换历史任务ID/航点。高层块从地面也进入期望加载集。
- FeatureGeometry输出同一视觉/碰撞网格；岩体沿X/Z/Y挖通，山洞使用分段圆截面侧壁。CavePassages选厚山体、匹配坡面洞口并限制互相间距，洞壁只保留在地形内部的部分。地表三角面减去与洞壁相同的16边形棱柱，插值顶点法线/颜色，避免整三角删除造成洞口外地面缺口。unmerged保持不同天然/岩体表面独立。
- BiomeTerrain戈壁去掉离散高度台阶，法线差分与4米网格一致；雪坡用裸岩与较暗蓝灰层次。日光四级混合、480米覆盖、320米高大投影空间、32位阴影深度及关闭更紧的投影物剔除；保留原生兼容渲染器。

## 内容0.16实现补充

- FollowCourses在旧任务平台、特色建筑和竞速航线之后计算观测机轨迹，独立随机流建立12控制点的周期Catmull-Rom闭环。地表按周边地形/建筑天际线抬升，天空扩大包围体，飞行高度留在保护线下。目标方向采用路径切线，导航与显示共用follow_point。
- follow_revision=2定义duration=30、coverage=0.8、range=50、path_speed/path_length；assignment保存elapsed/visible_time/near_time，两个比例独立累计，未接近不启动、失误不清零，达到最短时长后可继续追回比例。Main传真实相机视锥与遮挡；只有视野和清晰同时成立才累计可见。所有拍摄时间每约1秒提交，包括不合格片段，不能只存好片段来刷比例；暂停/传送的运动隔离保持。校验拒绝非有限值和超过拍摄时长的覆盖时间。
- ProgressStore新增feedback事件，仅接受/非竞速完成/购买提交成功后发出；已有unlocked提供成就/门户/地区，Main三处存档切换均重新连接。GameEventAudio用单个Effects播放器、最多8项队列、同类短间隔合并，九种有限包络PCM原创合成；竞速沿用独立门/终点音，失败提交不发声音，读档补记成就不回放。
- BiomeField不把八个新原型加入旧气候竞争；在持久extension_radius外用独立种子抽选。ProgressStore为旧世界从全部探索/任务/门户及部署坐标计算核心并加三格缓冲，同参数传入逻辑世界和渲染生成器。过大的保留核心可由BiomeLocator在四边投影附近作有界搜索，提示为外围实例，不冒充全局最近证明。
- BiomeTerrain按参数提供山脊/雪峰/雪原/砾漠/深峡/火山环形山/废城缓坡/巨构台地，接近群系边界平滑回到共同基底；城市过渡和地下入口整平保留。WorldProvider/BiomeWorld允许真实地形owner位于-2～4垂直块，物理和渲染使用同一网格。新增snow/basalt/lava表面，纹理周期可与64米浮动原点整除。外围高地处的空岛提高底部净空。
- OpenStructures提供工地、贯通住宅、公园游乐设施、三根中空管、普通/三面中空广告架、断壁簇、三重巨石门及岩/冰/玄武岩拱；以复合固体实现真正的门窗、天窗、管腔和中庭。城市地块/屋顶与数据化landmark_pool选择结构，count=1～6支持废墟簇且ID后缀唯一，避开平台、任务与地下入口。
- 完整回归还发现旧地下门框顶部最高约8.525米，与原8.5米导航线重叠；导航参考统一9米，0.6米机体扫掠和真实射线验证，门与已存航点不移动。环境竞速可经过结构开口，旧大圆占用断言改为平台/普通目标间距，竞速继续由真实门框/航段碰撞专项约束。
- expansion测试覆盖新内容与迁移/覆盖率/声音，expansion_tour使用真实主场景加载八群系并录1080p帧间隔；完整逻辑回归、最终包窗口证据见VALIDATION。

## 内容0.15实现补充

- MissionChallengeView的orbit/follow目标相对根节点偏移target_point-acceptance_point；环绕引导圈挂在target下，浮动原点只作用一次。原错误是根节点已锚定平台，目标却没有局部偏移。
- MissionCourses放宽生成环绕参数与天空群系包围范围；FlightChallengeRules只对空间带内的两个端点累计净弧度，允许≤0.25秒采样和≤45度步进，遮挡/偏离不清零；跟拍仍用原0.1秒上限和连续丢失重置。objective_hint与模板说明同步。
- gate_opening_half统一门架中心偏移0.3及条宽0.45：真实半开口为gate_half+0.075，检测增加1厘米数值余量，方向/扫掠/非连续位移保护保留。门架实体尺寸不变。
- MissionController在持久保存中间stage后发race_gate_passed，完成事务成功且原状态active时发race_finished，final stage不再叠放中间短音。完成写入失败可下一帧重试且只成功响一次；三处控制器装配均接入Main。FlightAudio的0.13秒单音/0.58秒四音旋律使用原生PCM、Effects总线及短包络。
- 电机基频150→200Hz、气流滤波650→900Hz及去低频90→150Hz，气流混合1.8→1.25，适量加强上谐波；源增益-12.5dB、最高pitch2.4、8秒循环与有界相位保持。新增challenge_feedback测试覆盖实际碰撞/变换/音频事件与失败重试，加入统一测试入口；证据见VALIDATION。

## 内容0.14实现补充

- FlowCourses.populate顺序为MissionCourses→MissionSites→BiomeLandmarks→FlowCourses→bucket。先移走所有旧挑战塔/门，再生成新路线，避免未来槽位的旧塔误挡当前路线；城市按32米路网分支行走，长腿可跨64米，自然地形14～52米随机步长并采样航段地形。浮岛路线依岛面半径，迷宫路线依真实连通图并合并部分直线节点。门方向由进出航段平分，候选检查实体OBB与升空柱，最多64次，失败保留旧任务。
- 新路线:flow及challenge.route_revision=1描述新布局，MissionDefinition.history_id引用原:play任务；legacy_objects仅在活动旧任务的MissionChallengeView恢复碰撞及网格，旧ID继续由BiomeWorld解析。新接待点不移动；城市新门绕过普通18米任务清场，仅使用窄飞行廊道，避免路线把沿街建筑清空。自然门增加竖直落地支撑。
- history_id同时进入任务奖励事务键和运行assignment完成身份；mission_status在无新布局assignment时承接旧完成，mission_completed_once读取旧账本/计数。新旧顺序完成都只发一次奖励，AchievementBook按历史身份去重；WorldExploration隐藏已有新布局承接的非活动旧布局，活动旧任务保留原阶段。
- 气球assignment.started区分接取与现场启动；accept仅写false，平台验证后的start_balloons事务保存true并追踪。未启动的update与实体显示不推进，导航指回平台；启动失败可重试，旧无started的活动气球回到等待，保留历史奖励。其余任务/账户不变。新速度1.8/0.7m/s，间隔2.5/1.5秒，准备3秒；地表/天空限高+45米且≤295米。
- RegionMap提供五项筛选；颜色依据mission_completed_once，蓝灰完成优先于绿色活动重玩，未完成金色；MapCanvas和行文字共享同一颜色入口。UnlockNotifications使用CanvasLayer20，Workshop不抑制，其他菜单/曝光仍隐藏并暂停提示寿命；挂载/关闭菜单即时同步。
- FlightAudio保留四路原生PCM和实际推力映射；转速相位不再积累独立随机游走，改为有界相位纹理，8秒循环气流。保留谐波与差动响应，源增益-12.5dB补偿均方电平；输出前级、限幅器、音量百分比、设备和其他音效不改。rotor_audio用8秒真实输出、20ms响度包络及旧周期相关检查，另保留纯音占比约束。
- 障碍OBB先按16米三维格网索引，航段/门洞探测只查询覆盖格，跨格实体去重；同地区的城市实体按块缓存复用，不在每次尝试扫描全部建筑。城市规划清场与实际世界同样跳过新路线的宽清场。400个随机线段/点、旋转盒、负坐标和格边界与穷举窄相位结果对照；抽样111条路线在优化前后保持相同量化路线数据。
- 新flow_routes测试加入tools/Test.ps1，验证多种环境/种子、朝向、随机形状、兼容、共享奖励和成就；本轮只执行变更相关检查，实际证据见VALIDATION。

2026-10-23。本文描述已经存在的代码，优先于早期设计中的示意类名；产品约束仍以 DEVELOPMENT.md 为准。

## 内容0.13：接待平台、世界路标与升空气球

- MissionSites在MissionCourses之后、特色建筑之前生成接取点：地表选择群系内部并远离边界，空岛在岛体上取样，地下在实际格子取样；与其他任务至少48米、服务平台14米分隔，排除实体占用和入口井。5.5米平板、中央标识、标牌杆由流式几何生成，地形采样四角确保露出，建筑/树木避让。pickup_platform保存point/top/half，acceptance_point优先该平台；穿门目标、阶段和原ID继续保留，旧任务槽也指向对应平台。
- main._docked_task_id检查碰撞就绪、无待重置、速度≤0.6m/s、姿态与中央范围，以向下实物理射线验证平面高度；accept_nearby必须收到同一任务的落台ID。未接取信标不再按住E自动领取；已接目标的原交互条件保留，地图仍可领取。
- 路标改为Node3D中的Label3D和透明QuadMesh，共同billboard，保持世界尺寸、深度测试及70米隐藏；移除CanvasLayer屏幕投影。三态色保留，failed另用红色。标签锚定平台上方，随浮动原点更新；菜单/曝光隐藏。
- 气球发射位置通常间隔9米以上，生成时清出到限高的完整上升柱；接取前三秒准备，然后间隔3秒逐只放出，地表/空中0.65m/s、地下0.3m/s。地表/天空限高为最高发射点+28米且不高于295米；地下为实际顶棚下2.5米。新限高只用于气球，穿门和运镜规则不变。
- balloon_step处理释放时刻内插、相对运动扫掠、持续上升和越限失败，未释放命中拒绝存盘。MissionController分别缓存所有已接气球的时钟，不依赖当前追踪；每秒保存、命中/失败即时提交，暂停停钟。failed保存并清追踪，不发奖，可重新接取；旧缺revision的活动气球仅重开本轮，余额/装备/其他任务保留。
- balloon_popped仅在保存成功后发出。MissionPopEffects最多4组、每组36片六色碎纸，兼容原点平移，1.8秒清除且暂停冻结。FlightAudio六路复用AudioStreamPlayer3D播放原创0.16秒破裂PCM，送Effects总线，随距离衰减并遵守既有音量设置；无新资源依赖。
- 电机保留两秒闭环、四路独立纹理及150Hz桨叶节奏；削弱3/4次谐波、移除5/6次，增加气流/不规则转速起伏，最高pitch从2.65降至2.4。原源增益、输出前级和唯一-1dB限幅不变，数字指标不等于主观听感验收。

## 内容0.12.1：任务标签与重玩

- MissionChallengeView为附近70米内每项任务最近入口投影PanelContainer标签，三种状态用独立底色及中文文字，同时支持旧巡检入口；背后/屏幕外/远处及菜单/曝光隐藏，鼠标穿透。已完成只保留入口，不重建气球或运镜目标，重新领取后恢复全套挑战表现。
- ProgressStore.accept_mission允许completed重新进入active，保存completion_count并清空阶段/照片/挑战进度；MissionController清除运行进度、运动基线和勘测停留。active再次接取仍只切换追踪，已提交阶段不清空。历史transactions、facilities、missions、地图与装备不回退，首次判断通过mission_completed_once兼容旧缺计数档。
- _complete_mission把本轮完成和首次奖励区分：重复完成仍事务保存completed、计数并停止追踪，既有奖励事务不追加、不加信用和装备；完成失败保持原状态。恢复任务不再用历史奖励覆盖active重玩，挑战存盘强制保留计数，成就按不同任务曾完成统计，不因重玩减少或反复累计同一项。
- 现场E、地图及兼容任务板均可再次接取；详情显示首次奖励已发放、重复无奖励。地图附近可领取筛选包含已完成任务，旧已完成目标也保留地图定义，便于重玩。

## 内容0.12：现场任务、飞行挑战、经济与成就

- MissionController.available_at/accept_nearby与生产E/遥控interact动作接通，6m/s以内接取并追踪，地图仍用原accept流程。附近定义按64米块缓存，边界处查询相邻分页，仅保留200米内目标和已追踪任务；跟踪目标跨群系仍保留显示。公开任务每独立群系实例2～5，地图分页可以汇集多个实例，旧已接任务作为兼容条目额外保留。任务附近显示实体入口标签，旧巡检框也是入口；失败保存不改追踪状态。
- MissionCourses在旧计划完成后使用独立随机流扩展，不改变原平台及旧任务随机序列；保留legacy_missions/legacy_locations及旧实体，proc:4六段旧键按原任务解析，新键追加`:play`。地形清场及特色建筑避让同时保护新旧目标，地下地图解锁任务不替换。新门框共享gate_normals和实际旋转实体；地表/空中绕塔、变高侧穿与水平楼顶俯冲，地下BFS走廊门缩小至2.5米半宽、10米高度并避开旧顶部标灯。相邻俯冲门有完整实体间距，高岛保留原任务。
- FlightChallengeRules为纯目标判定：有向平面交叉及矩形开口边界（含机体余量），逐门顺序；气球上升/摆动，按机体与移动球的相对运动扫掠，不按接近半径自动完成；环绕用有符号净角度，慢速小角步也累计，回头抵消；跟拍检查实际位移、同向、后方、距离、高度和镜头。生产Camera3D给出世界位置、朝向和真实遮挡射线；不能原地转镜头完成。暂停/菜单/重置/传送清运动基线，长帧与异常跳跃不刷运镜；穿门/气球允许合理长帧扫掠。
- ProgressStore.save_challenge_state校验有限值/阶段/重复命中，完成前必须已有足够提交状态。穿门/气球命中立刻事务写盘，运镜约每秒及暂停时提交；保存失败撤回未提交的离散进度，最后目标已存但发奖失败可重试，奖励事务仍幂等。新保存带kind，旧缺字段记录回读旧定义；损坏挑战字段拒读或仅恢复该任务起点，不覆盖正式原文件。
- MissionChallengeView是有界运行时表现层：附近任务入口、编号/当前门箭头、彩色气球、观测球与移动观测机。实际门框/塔楼由流式世界负责碰撞，气球使用目标扫掠而非刚体碰撞阻挡；命中提交后消失。种子/存档切换重建表现，坐标随浮动原点更新；菜单和照片隐藏文字，实体仍存在。顶部任务文字可换行；解锁/成就通知在菜单和曝光时暂停，返回后继续提示。
- Workshop商店新增分类下拉及双列商品卡，装备套机按钮双列防横向溢出；三新套机及九单件、十一条动力数据均资源定义，包含可用的新旧交叉组合。原购买/装配/范围/轴孔和桨径校验继续，未改飞行核心或用户调参。未来任务信用奖励下降，现存余额、装备所有权不变。
- AchievementDefinition/Book/Menu接入Esc，八个收藏条件不发奖；已获时间持久、条件由同一进度事务检查，历史完成类型/地图补记，circuit和race归同一航线类型。每个世界独立，控制设置跨世界不携带成就。旧0.11.2音色与响度未修改，用户已表示满意；没有录像回放系统、续航、外部插件或网络服务。

## 内容0.11.2：有声桨叶与输出响度

- 0.11.1用户确认电流声已消除，但宽带气流占比过高导致不像穿越机。本版以150Hz轴转周期、含第三谐波的六阶带限脉冲恢复桨叶嗡鸣，混合四级滤波气流。18Hz平滑随机转速扰动积分进相位，减均值保证两秒300转闭环；四路不同固定种子避免同一PCM相锁，仍仅原生流播放、不逐帧生成PCM。满推力音高上限2.65，音量与音高平滑、真实差速、暂停/断油归零保留。
- 电机源trim从-21改-14dB；音乐源trim从-12改-6dB。GameAudioMixer在Master安装唯一AudioEffectHardLimiter，内部pre_gain_db=8、ceiling_db=-1、release=0.08秒。增益在限幅之前，Master百分比在其后；不能把+8dB放到Master总线音量上，否则会把限幅后的信号再次放大。重复场景初始化复用同名效果，避免增益叠加。旧百分比、设备名、取消回滚和跨存档偏好不改写，没有系统音量修改或外部依赖。
- rotor_audio专项隔离验证PCM周期/接缝、独立四路、增益/静音/设置事务；正常窗口用Master末端AudioEffectCapture检查满音量四电机、双音乐交叉渐变与快门叠加，并以过量测试信号实际触发-1dBFS限幅，导出油门变化试听。捕获点在Master百分比之前，响度/峰值测量时Master=100%，等价于游戏最终混音，非声卡或系统回录。测试退出等待原生音频线程处理停止命令。

## 内容0.11.1：电机纹理与紧凑底栏

- FlightAudio的主声源由130Hz多谐波纯音与25Hz调幅改为两秒固定种子噪声，经90Hz去低频及四级650Hz低通形成桨叶气流；90/180/270Hz仅保留低幅桨频。滤波器先循环预热再记录，避免拼接点击；PCM峰值0.70。满推力音高上限3.55改2.25，移除固定电机失谐，仍使用真实四路推力差。音高约83ms、音量约56ms指数平滑，暂停/高度断油立即归零。不改变快门、配乐和玩家混音设置。
- InputDisplay不再独立锚定屏幕；作为main底栏HBox右侧成员，以左分隔线与状态文字衔接。双摇杆各52像素方框，2像素抗锯齿十字防止分数缩放丢线。辅助通道GridContainer按约四行目标增加列数，宽度限制在底栏右半；超出列宽预算时增加行数、底栏按内容向上增长，无ScrollContainer。两开关仍独立，菜单/照片隐藏，辅助回差读取不改变动作状态。
- 底栏状态文字允许换行；E和R提示修正，默认探索提示与快捷键均移除F3，实际F3处理保留。hud_audio专项检查覆盖PCM/平滑/断油、原生四声部播放、多分辨率网格像素、多列状态与同框布局；标准测试入口收录此专项，本轮仅执行该项及打包启动检查。

## 内容0.11：配置管理、操作预览与飞行控制（当前）

世界仍4、内容0.11.0；不重建世界或玩家进度，不改变现有角速度曲线、Expo及装备调参。

- RadioMenu替换F2平铺按钮：配置与USB设备两个独立下拉，设备可刷新，配置可使用、编辑、新建和删除。旧同名条目显示设备名/序号区别，不擅自删改；RadioProfiles在新建和改名时按去首尾空白/不区分大小写检查名称（1～48字），旧重名允许原名编辑。稳定键与名称分离，改名和手动应用到另一个USB设备均更新原条目，不制造副本。
- 删除需要界面确认，成功事务后才更新运行状态；删除当前配置立即暂停、清除旧通道和辅助边沿，并保存radio_selection_required，明确选择设备或键盘后才能继续。radio_profiles_managed标记已主动管理的配置集合；删除全部后不再从旧事务备份复活它们，缺失旧配置的历史恢复路径仍保留。离线可编辑现有配置，连接设备前不自动激活。测试仅使用隔离档，没有替用户删除正式配置。
- Esc新增操作预览设置：双摇杆、辅助拨杆状态分别开关，默认均关闭，可选Mode2左手油门或Mode1右手油门。InputDisplay在画面底部显示校准/正反/死区后的实时输入；暂停仍读取真实遥控器，未连接显示明确状态。观察辅助值不推进档位历史、不发动作，不会误重置或恢复。长名称缩短、完整名称悬浮可见，辅助通道较多可滚动；菜单及照片曝光隐藏，屏幕录制可录到预览。settings.input_display沿用玩家设置保存/跨槽规则。
- FPVDrone继续启用原生CCD，并在单步运动超过4cm时作机体盒形状扫掠，超过10cm时增加中心/八角点射线。仅使用真实碰撞几何、当前mask且排除自身；限制本步沿碰撞法线的接近距离，保留切向速度，没有统一高度钳制或把地下填满。原生cast也会漏检的极端倾斜高速三角面由角点射线兜底。原冻结、碰撞就绪门槛及浮动原点流程保持。
- 另修正FPV相机伸出小机型碰撞盒的问题：在原机体包围盒中加入相机位置及7cm净空，保持原底部着陆面和质量中心不变。相机位置和画面方向不改；前向/上侧碰撞保护范围覆盖相机及当前FOV的近裁剪面。真实120m/s俯冲复现中原小机型相机可低于地面约5.6cm，修正后相机与四个近裁剪面角点均在地面上方。
- 原控制是固定PI：横滚/俯仰P18、偏航P12、I3，叠加电机响应延迟，没有D项。现为每轴独立P/I/D，D对实测角速度求导并低通滤波，避免目标骤变的微分冲击；混控饱和方向禁止继续积分，误差反向可解饱和，积分仍限幅。暂停、姿态重置、装配和参数改变清历史；300m断油继续直接清四电机输出。
- 默认横滚/俯仰P36/I3/D1.8，偏航P28/I3/D1.3，D滤波20Hz；范围P0～80（1/s）、I0～40（1/s²）、D0～4、滤波5～60Hz。数值属于本游戏的角加速度控制单位。FlightTuning对缺PID的旧档补默认，已有自定义PID严格校验，不覆盖旧曲线/环境值。Workshop操控曲线页下方增加PID板块、滤波和独立恢复默认；聚焦数字文本提交、草稿取消及原子保存复用原有流程。

## 内容0.10：入口地面、逐轴死区与群系音乐

世界仍4、内容0.10.0，不重建已存在的v4世界、平台/任务ID或进度。

- BiomeSurfaceProvider原先仅在key.y=-1把城市地板换成_canyon；入口整平可令minimum>=0，地形owner变0，下层查询得到空列表，上层却不生成地面。现对-1/0两层应用同一替换条件，去掉旧地板并按实际owner追加地形，保留城市其他对象。16m竖井仍按全局4m网格裁孔，网格与碰撞共用索引。
- FlightInput姿态轴保留旧缺省2.5%回中死区；油门新增低端死区，缺省缺失字段为0以兼容旧响应，有字段时按该值生效。全部轴范围0～20%，死区外重映射并保留满行程；反向先处理，油门不在中间挖空。辅助模拟/三档轴在回中处稳定，二档/回弹轴在低端；已有档位回差继续。RadioCalibration每行数字编辑实时预览，保存提交聚焦文本，RadioCapture重采保留每个角色死区。按钮源没有模拟死区。
- GameAudioMixer建立Master、Effects、Motors、Shutter、Music；电机/快门先经Effects，其余送Master。GameAudioSettings统一范围/有限值校验，ProgressStore两个设置提交入口拒绝非法声音数据。默认主音量80%、音效/电机/快门100%、音乐45%。/volume通过混音器修改本次master，不自动写盘。
- AudioMenu接入Esc暂停菜单：输出设备按名称保存，实时试听各音量；保存成功返回暂停菜单，取消/Esc退出恢复进入时全部设置，失败保留页面。缺失设备临时使用Default，每秒检查重连并保留原偏好；刷新按钮重枚举。settings.audio跟随现有设置副本、重启和跨世界读取/新建，不在共享资源存玩家参数。
- FlightAudio原先900～2047.5Hz固定气流正弦组在升调后形成约3.2～7.3kHz细尖声。现改350～957.5Hz低幅衰减频组，原有130Hz基音、谐波、四电机差速及暂停/断油静音继续。PCM循环中所有频率仍为整周期；不将该频谱修正视为用户主观听感验收。
- BiomeDefinition.music/music_title显式引用七首独立WAV；Resource复制保留共享只读流，播放状态由BiomeMusic保存。0.65s群系稳定门槛抑制边界抖动，两AudioStreamPlayer在2s内等功率交叉渐变，结束释放旧流；暂停菜单中音乐继续。没有逐帧PCM合成。群系实际三维判定继续用generator.biome_at，空岛/地下分别使用自身配乐。
- tools/ComposeMusic.py使用Python标准库从原创音符表生成16小节曲目；脉冲旋律/琶音、三角波低音、短打击乐，16位22050HzPCM录制8bit风格以避免量化底噪。WAV smpl声明完整前向循环；Godot原生导入。曲谱副本game/audio/music/scores.json。内容指纹含音频数据摘要、采样率和循环边界，源/包可一致比较。


## 运行结构

`scenes/main.tscn` 加载 `scripts/main.gd`，负责组合服务与场景。没有全局 Autoload、外部插件或在线依赖。

| 模块 | 实际入口与职责 |
| --- | --- |
| 内容 | ContentManifest / ContentCatalog：显式登记、排序索引、装备/群系/任务引用与参数校验、清单指纹 |
| 装备 | DroneAssembler：配置 ID + 调参 + 已取得列表 → 错误或唯一整机规格 Dictionary |
| 飞行 | FPVDrone：RigidBody3D、四推力点、角速度控制、混控、响应延迟、反扭矩、阻力 |
| 输入 | FlightInput：键盘、独立 RC 轴与辅助档位；RadioCapture：统一行程采集；RadioCalibration：轴分配、正反、辅助通道类型与命名配置 |
| 世界 | WorldGenerator / WorldProvider：纯数据描述；WorldStreamer：后台任务和主线程提交；WorldGeometry：MultiMesh 和简化盒碰撞 |
| 进度 | ProgressStore：权限、设施、任务、事务、余额、配置、写盘与备份 |
| 任务 | MissionDefinition：只读目标与奖励；MissionController：领取追踪和导航；PhotoObjective：距离/角度/可见性判定 |
| 界面 | Workshop / RadioCalibration / RegionMap / MissionBoard / UIStyle；主场景组织帮助、商店和交互 |

场景只使用编译后整机规格，不读取具体机架或配件 ID。当前 v4 全部使用独立群系计划与综合服务平台；固定终端、闸门和货车已退出主场景。旧版提供者与任务资源保留作回归夹具，不出现在 v4 地图或任务面板。通用交互实体/任务编辑器尚未制作。


## 内容0.9：连续导航、照片路径、特色建筑与存档管理（当前）

世界地形及群系生成仍4，内容0.9.0。新增建筑采用独立随机盐，不改变现有平台、任务坐标/稳定ID或进度；现有v4加载后应用新增内容，地形采样不变。下述规则覆盖旧中途导航容差和Esc仅切暂停的行为。

- MapNavigation中途点扫过半径由8m增为24m；沿后续最多8段的投影在段内、侧向32m/高度24m内时前进至该段终点，避免正确绕行后回头补点。迷宫仅检查下一段，侧向6.5m/高度9m；若离旧点越来越远且移动至少8m，调用既有路线解析器，从真实格子重新BFS，而不是隔墙放大半径。起始格已经占据时去掉其中心点；用运动方向点积识别远离旧点，低速帧移动也有效。超过64m不连续位移不扫过/补跳。离开地下的路线也启用窄容差。终点8m/14m回差与任务目标/奖励判定不变。
- PhotoNotice成功保存后显示完整绝对路径10秒，提供复制与打开目录。独立于任务结果文本，菜单时隐藏；曝光时隐藏旧照片提示，避免下一张拍进旧路径。失败不提示成功，原0.18s闪光/快门继续。
- Architecture原生描述13类可组合建筑，支持旋转梁的网格/碰撞同变换。种类见README；金字塔留10m宽/12m高通道，双塔连桥/格构塔/机库留可飞空间，地下管线底高于8.5m导航中心线。主体实体、薄覆面使用背衬碰撞。
- BiomeDefinition.parameters.lot_pool和landmark_pool定义城市替换与独立特色建筑概率；ContentCatalog校验类型、已支持建筑与0～1有限概率。城市约48%合格地块从各自内容池选变体，旧跨路桥按独立概率22%出现。BiomeLandmarks使用独立随机流、地表40个候选/天空岛面/地下房间布置，保护平台、任务、已有特色建筑和迷宫入口；自然地形脚座采最高地面，坡差过大拒绝；城市/树林为其预留范围，空中建筑低于限高，地下标记放通道高度。特建筑标记加入已探索地图，不可传送。选择可不命中，非每实例强制一座；冷重建与跨分块所有权保持稳定，分块查询考虑群系边界外伸。
- SaveLibrary在既有ProgressStore原子事务上管理profile/saves/slot_*.json；显示名称仅为元数据。兼容原progress.json作为legacy，active.json/备份记录当前槽，校验失败回退备份/旧档，不删除原文件。save_name/save_created/save_updated为可选字符串元数据。read_snapshot静态验证无写盘副作用；use_snapshot用于校验过的跨世界状态重建。
- 保存当前、另存副本（不切换）、新建世界、读取、改名、移入回收目录均有明确返回结果。新建/读取先保存当前；成功提交目标并保存active指针后才切换场景。读取复制当前玩家settings到目标世界，因此校准/辅助开关/操控偏好不会倒退；新世界保留设置，重新建立世界进度。当前槽禁止删除，二次确认删除将主档/备份移入trash，写入失败不切换/不退出。
- PauseMenu/SaveMenu接入既有菜单状态快照，Esc打开/关闭；编辑存档名时Esc也有效，存档页返回暂停菜单。“继续”显式恢复；Esc恢复进入前状态。保存退出失败保持窗口并显示错误。main._switch_store同步ProgressStore、生成器/流送、探索、任务、地图、装备/参数和安全部署，清旧开发定位，回到安全平台并保持暂停。F1按种子新建也创建独立存档，旧_restart_seed仅保留兼容测试入口。

## 内容0.8：高度保护、控制台与原生音效（导航/照片/菜单由0.9补充）

世界仍4，内容0.8.0；现有v4地图、任务、装备与操控配置继续。下列高度规则覆盖0.7的1500m位置钳制/1400m阻尼。

- FPVDrone.MAX_ALTITUDE=300、SOFT_ALTITUDE=280。世界Y>300设置altitude_cutoff，直到Y<=280才清除；280<Y<=300且未触发时仅预警。直接清零四电机力/积分，跳过混控及电机滞后输出，保留controls实时输入。恢复后使用当前油门，重力、惯性、被动阻力继续，取消位置/向上速度钳制。reset_drone/reset_attitude及main物理更新按世界坐标同步保护，原点平移不改变高度。
- FlightEffects原生绘制透明渐变红边，预警2Hz明暗变化，保护锁存常亮；文字说明接近限高或下降至280m恢复。菜单隐藏提示，保护仍保留。白色拍照闪光约0.18s，不拦截输入。
- DeveloperConsole复用菜单暂停/恢复流程。/打开、Enter执行、Esc关闭；LineEdit聚焦且隔离普通键盘/遥控器动作。历史100条、输出约300行有界。DeveloperCommands提供/help、/location list、/location <群系>、/tp location、/tp x y z、/pos、/seed、/volume 0..100、/clear。音量仅本次运行生效。
- BiomeLocator查询BiomeField真实站点规则，包括未探索地理；volume_site供几何计划、区域收集与定位共用，稳定ID/生成结果保持。逐圈比较生成中心水平距离，用未搜索单元边界和最大warp位移下界确认最近；最多12圈，不能确认则明确失败。仅为胜出实例构建计划，返回第一个真实平台坐标。支持完整ID/简写/中文唯一片段，不写探索/平台状态；不是最近群系边界或最近平台的全局优化。
- main._debug_teleport移动运行时机体、更新流送/路线并等待碰撞，不覆盖安全spawn_world/保存部署点、不登记平台；实际到达仍正常发现地图。/tp location要求当前种子的成功定位；数字必须有限且各轴在±10000000m。普通地图传送仍要求登记。
- FlightAudio启动生成22050Hz/16位单声道PCM：0.4s无缝谐波/空气纹理循环与0.16s双脉冲快门。四AudioStreamPlayer共享循环，以motor_forces/max_thrust的平方根映射音高/音量，混控差速自然进入声音。冻结/断油立即静音；原生播放重采样，无逐帧PCM缓冲、新依赖或外部素材。声音为合成近似，未实现实录声学或桨叶空间传播。
- _capture先保存干净画面/元数据，成功后闪光和快门；约0.20s忙状态防重复和下一张混入上次闪光。失败不触发反馈，原照片任务事务继续。
- 回归发现Workshop.submit对全部SpinBox.apply会以未聚焦控件旧文字覆盖同帧滑杆/value修改。现只提交聚焦的数字编辑器，再释放焦点并收集草稿；原参数保存与遥控器再次交互提交文本共同验证。

## 内容0.7：任务现场与连续遥控操作（限高已由0.8覆盖）

世界几何版本仍4，不清空现有任务、探索及遥控器设置。以下覆盖旧版“关闭菜单后保持暂停/失焦需手动恢复”、地图自适应默认比例及343块窗口的描述。

- BiomeWorld将courier/survey/hold_interact的目标从ground+(0,6,3)修正为ground+(0,1.2,3)，位于实体设施前方。原来的快递半径3m和勘测/校准半径4m不能覆盖地面接近位置，是现场交互失败的可复现原因。ID、奖励与阶段不变；巡检和摄影仍用各自结构中心。
- _mount_menu记录首次进入前的paused状态，页面之间替换保留同一快照；_close_menu恢复原状态及机体运动。Workshop.submit(true)由再次交互触发，成功保存才关闭；失败或离开平台保持页面。地图/任务地图动作在RegionMap内可再次关闭。普通设置页仍屏蔽遥控动作，地图和平台页仅接受相应关闭动作，辅助档位边沿不反复触发。
- 失焦保存并冻结当前状态，返回恢复失焦前的运行状态；原本暂停仍暂停。菜单还打开时继续暂停，关闭后恢复菜单入口状态；遥控器断连仍不自动恢复。启动仍默认暂停，显式重置种子仍从安全状态建立新世界。
- MapCanvas.blank_clicked经RegionMap建立id=temporary的内存路标，用放置时当前高度；只导航、不可传送，可覆盖或清除，不写存档/不解锁地图。WorldExploration及实际地区刷新保留该目标，不被旧追踪任务抢回。每次打开固定0.7逻辑像素/米，中心为无人机，自动fit关闭；全图按钮仍按已探索范围适配。
- NavigationHUD截短地点名，仅保留名称/航点号/距离/高差，两行小字；深色背景alpha0.35，避开瞄准中心。十字精确居中、z=100、描边并在菜单时隐藏。
- ProgressStore.unlocked信号只在成功事务后发出，平台登记、普通地图访问、特殊测绘任务完成各有提示；重复/失败不提示成功。UnlockNotifications居中显示最多3条、约4秒淡出，不拦截输入；初始化前的通知排队。
- FPVDrone按世界高度限制1500m，1400m起增加上升阻尼，顶端只钳制位置和向上速度，不限制横向或下降。world_origin_offset随原点平移同步，部署点也钳制上限。没有引入能源或耐久机制。
- WorldStreamer水平半径3→4块、垂直保持3块，基础567块；高空保留-1/0地表层，浮岛预取最多96块，最坏预算825块，近身碰撞就绪仍27块。相机远裁剪3200m仅为裁剪上限，不代表所有地形都加载到3.2km；高空岛群可保留其三维几何。

## 内容0.6：统一地图与探索进度（历史行为见0.7覆盖）

世界几何仍为v4，不为UI升级重置现有v4地形、任务或装备；新增状态从当前所在实例开始。以下规则覆盖旧版分页、独立MissionBoard和无条件传送描述。

- M/F3共用RegionMap。左侧可折叠列表按MissionController.objective_point的三维距离排序；默认附近1.5km可领取任务，每页8项，另有进行中/全部已发现/已完成筛选。F3每次优先最近可领取任务；M保留选中目标。选择目标后使用局部缩放，全部已解锁按钮可查看完整探索历史。
- 列表行、地图图标和右侧浮动详情共用MapNavigation.selected_id；地图点选会切换筛选/页码并滚动到对应行。地图默认仅显示当前任务页和选中任务的标记，服务平台保持显示；没有自动领取，需在详情明确领取/追踪。
- ProgressStore.exploration包含visited/mapped/portals三个ID集合，均经原子提交。BiomeWorld.instance_at按真实三维实例判定到达，WorldExploration只输出已访问实例；普通群系访问即加入mapped。全部已解锁实例保留，不再以九页窗口剔除历史；物理加载和几何计划缓存仍有界，地图历史/任务列表随探索规模增长。
- BiomeDefinition.parameters.map_unlock为visit（默认）或mission。地下迷宫作为首个特殊群系，进入后仅公布指定测绘任务目标，不显示内部边界/墙图。BiomeWorld.map_task从既有任务优先选择勘测、校准等，保持原稳定ID与几何。完成指定任务的同一奖励事务同时写入mapped；失败不解锁、不发奖。
- 平台发现与传送登记分开。真实低速落稳按E后，主场景先原子unlock_portal，再打开综合服务；首次悬停或空中暂停不登记。MapNavigation.teleport_resolver与主场景传送入口都检查登记状态，灰色未登记平台可导航；重启恢复物理部署点不需要绕过地图/传送锁。
- 导航update检查前后世界坐标线段。常规航点8m、迷宫单元内XZ各7.2m及高度9m容差，避免隔壁16m走廊误触；每次只按顺序推进。超过64m的非连续位移不扫过，重置路线清除历史。到达后14m离开回差，避免离开时重复命中起点。任务完成条件与交互距离保持独立，不因导航容差放宽奖励条件。
- 旧世界自动重建先保留settings；F1新种子也保留settings。每次成功进度提交后镜像至同目录controls.json；主profile仍是事务来源，镜像失败不影响已成功的主存档。初始化可从独立副本或有效旧profile备份找回缺失配置，先恢复再执行世界重建。新建世界清空探索、任务和传送登记，遥控器及操控设置保留。
- F2始终列出有效已保存配置，断连或GUID不匹配仍可编辑；手动应用到当前设备时复制并更新GUID，保留原配置。自动恢复仍要求GUID匹配，防止误套到不同设备。

## v4 独立群系生成与综合服务（当前实现）

生成阶段content_version=0.5.0，world_version=4（当前内容0.6.0）。用户指出 v3 每地区固定组合地表、浮岛和地下，不满足随机生成要求；生产入口已替换为 BiomeWorld。用户授权不保留旧世界或起始区，读取 v1/v2/v3 档保留操控设置并重新建立 v4 世界进度。原子保存及上一版事务备份仍保留，未知版本继续受保护。

- BiomeField 使用种子气候场选择五种地表模板，扭曲 Voronoi 形成不规则边界；温度、湿度与聚落偏好参与选择。surface_spacing=768 m、warp=110 m；512 m 地图页仅收集相交实例，与群系边界无绑定。
- 浮岛群、地下迷宫使用独立的候选网格、种子盐和出现概率。默认 sky_spacing=1536 m/chance=0.33，maze_spacing=1280 m/chance=0.42；不保证每页出现，也不使用固定三件套相对位置。
- BiomeStructures 生成多岛体、随机径向轮廓和高差的浮岛群，搭配实体拱门或观测塔。地下是 13～21 × 13～19 个 16 m 单元，深度约75～118 m；随机树形通路叠加房间及环路，保证全部单元连通，1～3 个竖井连接地表。地表网格精确裁去入口并平滑入口边缘，城市地面及楼体避开开口。
- BiomeTerrain 在各块使用相同全局气候与边界规则；4 m 网格高度、法线与碰撞一致。BiomeSurfaceProvider 按实际群系裁去越界建筑，城市边界与自然地形连续。建筑延续多风格、退台、水箱等组合并随机留空地块。
- 岛体按扇区输出封闭三角网格并按owner块合并；迷宫墙、地板、屋顶、竖井壁、入口边框及任务信标/地标/巡检门均有真实碰撞。树冠使用锥形凸碰撞，树干和岩石继续实体化；不为材质纹理细节另建碰撞。
- 每个实际群系实例1～2个平台、2～5个任务，任务模板随机无重复选取，目标依实际结构节点布置。稳定ID为 v4:surface|sky|maze:x:z:pN 和 proc:4:surface|sky|maze:x:z:slot；由种子与版本重建，不依赖加载顺序或缓存。
- mission_templates 包含 survey/circuit/courier/hold_interact/photo，统一100点一次性奖励。巡检逐点保存、快递取件返站、勘测连续低速停留、校准按住交互、摄影用实际照片与射线判定；生成任务复制模板后新建 checkpoints 数组，绝不清空或追加共享模板数组。
- WorldExploration现按已访问/已解锁实例物化全部探索历史并按稳定ID去重；物理停靠使用独立的当前地区站点集合。BiomeWorld计划缓存48项，站点和多边形缓存各256项，任务解析缓存256项。发布的计划只读，构建与缓存加锁，不让线程请求顺序改变世界。
- WorldStreamer 保留343块基础窗口；进入浮岛群时额外预取最多96个相关块，避免只看见一个岛。碰撞就绪仍要求当前27块邻域。没有以无限增加加载半径换取远景。
- 地图支持任务状态及地表/浮岛/地下层筛选，显示真实地表多边形、岛体范围及地下墙体布局。MapNavigation.route_resolver 接入 BiomeWorld.route；迷宫使用实际门图BFS规划走廊航点，进出通过竖井。地表与空中仍是参考连线，没有全局避障或自动驾驶。
- _docked_station 要求碰撞就绪、重置已同步、速度≤0.6 m/s、上向点积≥0.85、平台中央±5.2 m、机心距平台顶≤0.16 m；短射线须命中平台顶水平面。E/遥控器共用 Workshop，Tab不能直达；保存和购买再次验证原平台停靠。
- OfferDefinition.preset_id 自动授予完整套机及配套组件。150点柔和桨叶、300点Light3.5均为永久权限；装备、三轴曲线、高级环境与商店在综合服务页。
- F1 输入种子确认重建：清空取得、信用点和任务，保留遥控器与操控设置；等待旧后台工作结束后替换生成器、导航及任务。重启仍从安全平台恢复，不保存空中运动状态。

世界公共接口仍为三维几何描述，采样高度仅为地表提供者内部实现。没有任意地形破坏、跨迷宫洞网或通用结构编辑器。以下v1/v2章节保留历史实现背景，旧提供者和静态地图仅用于明确指定版本的回归夹具。

## 遥控器输入与配置

四轴统一采集，RadioCapture 以 0.4 的原始跨度门槛排除噪声；完成时必须恰好四轴且只有非回中油门靠近端点。记录三轴的当前中点与各轴端点，油门最低处自动确定其方向。其余通道初次按索引分配，已有姿态分配优先保留；设置页可交换轴分配和单独反向，不按设备品牌推断功能。

旧配置仅有 axes 时继续兼容。新增 auxiliary 数组，每项有 id、name、type、source、invert；轴源另有 axis/min/max，按钮源有 buttons 索引数组。type 为 two_position / three_position / momentary / analog。辅助源不得和飞行轴或其他辅助源重复，校验拒绝无效索引、范围、类型和非有限数值。三档按钮源支持两按钮加中位或三按钮互斥编码。类型必须匹配来源实际能提供的状态数。

FlightInput.read_auxiliary(id) 输出二档 / 回弹的 0 或 1、三档的 0/1/2、连续控制的 0～1；暂停、未启用或断连时返回 0。回弹保持实时电平，不做软件切换锁存。配置修改先保存在界面副本中，接受后通过 ProgressStore.save_settings 原子写入并激活，取消不改变现用配置。F2 的编辑入口恢复同 GUID 下的所选命名配置。

辅助项可选 bindings 字典，以从 0 开始的档位字符串为键、动作 ID 为值；旧配置缺少该字段时保持不绑定。two_position / momentary 有两档，three_position / analog 有三档；analog 使用低、中、高区间。FlightInput.ACTION_NAMES 是动作选择和校验的共同定义，支持 toggle_pause / pause / resume / reset / reset_attitude / toggle_camera / photo / map / missions / help / interact。未知动作与不存在的档位在保存或载入时拒绝。

RadioCalibration.source_label 以真实来源生成标题，轴 n 显示通道 n，与底部轴号预览一致；按钮源显示按钮索引。旧默认名称「通道 n」从识别序号归一到真实来源，自定义别名保留，动作标题始终包含真实来源。

update_auxiliary 在飞行输入 enabled=false 时仍采样，按档位变化发出 action_requested，同帧相同动作去重。二档使用 0.4/0.6 回差，三档与旋钮在 0.25/0.75 边界使用 ±0.05 回差。首次采样只同步位置；配置激活、重连、菜单与焦点变化清除边沿及按住状态，防止自动执行。actions_enabled 独立于飞行轴 enabled，主场景以菜单和焦点控制它。interact 通过 action_held 维持按住状态，主场景与键盘 E 共用维修和商店路径。

主场景 _perform_action 统一键盘与遥控器入口。FPVDrone 不再有 armed 字段；暂停与碰撞准备直接通过 freeze 控制物理。暂停清空机体 controls、电机推力与积分器，保留暂停位置和运动状态；恢复在物理步即时读取当前轴，不检查最低油门。P / 空格或动作恢复后即可飞行。重置清空机体运动、键盘油门和控制器状态，维持原来的暂停标志，碰撞就绪后继续。服务平台界面暂停物理，打开、保存与购买均要求实际停靠。

reset（R 键）返回部署点并归零完整姿态；reset_attitude 保留当前世界位置与水平朝向，仅回平横滚/俯仰并清空运动。FPVDrone.reset_drone(at, heading=0) 同步节点姿态与速度、重置插值，并在下一次 _integrate_forces 中再次原子写入 transform 与两种速度；冻结时保留待提交重置，恢复时先提交再继续控制。reset_attitude 由机头的水平投影求朝向，机头竖直时用机身右向求回退。shift_origin 同步平移尚未提交的重置位置，防止原点移动后跳回旧局部坐标。

set_simulation_paused 统一暂停及碰撞准备的冻结转换：第一次冻结保存线速度与角速度，重复冻结不覆盖；解除冻结立即恢复，并在下一物理步再次同步，避免引擎冻结同步造成零速度。显式重置同时清空缓存，防止恢复时带回旧运动。motion_velocity 给暂停 HUD 提供保存的速度。主场景在暂停且无菜单时仍更新交互；任务交互仍使用暂停前的实际速度，冻结本身不能证明停稳；装备服务还需要平台高度、范围、姿态、碰撞和速度检查。焦点和菜单屏蔽保持有效。

## 三轴曲线与高级环境

FlightTuning 为参数范围、默认值、旧设置转换、数值校验及响应函数的统一入口。settings.flight 保存 axes.roll/pitch/yaw，每轴含 max_rate_dps 与 expo，另含 gravity、air_drag、angular_drag。无新字段的旧 rates/expo 转为三轴，其中偏航取旧 rates × 0.7；新配置优先，运行控制器不再乘固定偏航系数。无效新存档参数暂回退默认，不自动改写原文件；save_settings 与 save_loadout 均拒绝无效新参数。

响应为 max_rate_dps × ((1 − expo) × x + expo × x³)，x 限于 −1～1。RateCurve 原生绘制三条曲线、坐标网格、悬停取值与三轴半杆输出；FPVDrone.target_rates 使用同一响应函数，在唯一边界映射到机体系并转 rad/s。Workshop 分装备 / 操控曲线 / 高级环境三页，编辑副本，保存才原子应用；取消保留运行与磁盘设置，恢复默认按钮先作用于草稿。

apply_tuning 设置本机体 gravity_scale；空气与转动阻力倍率同时缩放既有自定义阻力和引擎默认阻尼，并用 DAMP_MODE_REPLACE 避免环境默认阻尼再次叠加。因此 1 倍保持原有基线，0 真正关闭相应阻力；未更改全局项目重力或共享配件资源。参数范围见 DEVELOPMENT，界面与写盘共用 FlightTuning 校验。

## 世界接口

```text
WorldGenerator.key_at(world_position) -> Vector3i
WorldGenerator.generate(key) -> {key, objects, world_version}
WorldProvider.generate(key, seed, biome, reservations) -> Array[Dictionary]
object = {id, center: Vector3, size: Vector3, color: Color, solid: bool, surface?, primitive?}
```

坐标是米，X 右、Y 上、机头朝本地 -Z。单维度 world.main，64 m 立方块；全局键与本地浮动原点分离。结构以固定 owner 生成一次，可超出 owner 块；现有最大外伸控制在相邻块范围内。

当前地区规划由固定道路网格、群系 AABB 和体积预留组成，未创建独立 RegionPlan 类。世界版本2包含工业、园区、砖石旧城三种建筑风格及峡谷、松林自然地形；城市风格复用同一提供者。峡谷/林地以4m采样连续网格输出，公共接口仍为三维实体与网格，空岛有底面，地下有顶、墙、底和开放入口。世界版本1继续使用独立的 LegacyWorldProvider 柱体生成。

加载半径三块，最多 343 个键（含空块）；四个后台生成任务，活动节点和碰撞只在主线程创建，每帧最多一个非空块。飞行等待周围 27 个键就绪及两个物理步；卸载后返回的无关结果丢弃。当前没有复杂 LOD 或速度预测。

物理边界上，本地位置超过 1024 m 时移动原点，并同步机体、活动块和设施根节点；全局 ID、朝向、线速度不变。生成的随机数使用固定整数函数，不靠可变 RNG 或线程完成顺序。semantic_hash 仅用于测试比较，不参与地图生成。

## 新增群系

地图地点与导航见下方「交互地图」；地点数据不改变世界提供者和加载器契约。

1. 复制 `content/base/verdant.tres`，设置新 ID、显示名、bounds、priority、palette（三色以上）与 building_min / building_max。
2. 将资源加入 manifest.biomes。沿用 modular_city 即可增加城市风格，不修改飞行或加载器。
3. 空岛与地下样本可修改 parameters.anchor，同时移动 region_bounds。地下的 surface_reservation 由数据声明，城市和峡谷会预留相交地表。
4. 当前地下样本以完整 64 m 地表块预留，洞室固定尺寸，整体移动 anchor；任意深度入口、斜井和连续洞网需要新的提供者，不能只移动样本就宣称完成。
5. 新几何规则实现 WorldProvider 子类并覆写 generate，在 WorldGenerator 注册提供者 ID并更新 ContentCatalog 支持的提供者校验。它仍输出相同对象描述，不改加载器、无人机或奖励计算。
6. 增加负坐标、结构边界、上下表面、通道净空和加载顺序检查。修改生成算法须增加 world_version，并处理旧世界迁移；当前仅支持用户主动执行的世界1→2整体重建迁移，不是通用迁移器。

## 新增装备

实际定义统一使用 PartDefinition，kind 为 frame / motor_set / propeller_set，电机与桨叶的 component_count 为 4。

- frame.stats：arm、max_prop_inches、mount、system_mass、drag。
- motor.stats：mount、shaft_mm。
- propeller.stats：diameter_inches、shaft_mm。
- tuning：以参数名为键的 Dictionary，每项含 min、max、default、step、unit。
- 当前物理绑定：机架 camera_mount_tilt_deg；电机 response_trim；桨叶 aero_trim。新调参类型需给装配器增加明确的作用路径，不仅增加滑块。

复制配件资源后新增稳定 ID，登记 manifest.parts；为新电机/桨叶组合登记 PropulsionMapDefinition。没有动力映射的组合不能安装。新增套机登记 DronePresetDefinition，引用三个组件。不得通过修改飞行控制器中的机型分支接入。

质量包括机架、四电机、四桨叶和固定系统质量；没有电池对象。惯性为尺寸和质量的简化估计，动力数值为虚构原型标定。默认横滚/俯仰为 360 °/s，偏航 252 °/s，三轴 Expo 各 0.25；装备台允许每轴 30～1200 °/s、Expo 0～0.95，偏航完全独立。

## 获取与存档

RewardDefinition 使用 mission_tag AND city_tag，MissionDefinition 显式引用 reward_id，校验条件一致后原子授予 grants 的永久权限和 credits。新增任务登记 manifest.missions 与对应 reward；套机须同时包含必要组件。OfferDefinition 引用配件、价格与城市标签，登记 manifest.offers。

ProgressStore.accept_mission / track_mission / complete_mission 是生产任务接口。维修由 MissionController.interaction_at 查询，主场景按资源中的距离、低速和持续时间采样，直接按住 E 会先领取。complete_relay 仅保留为旧接口兼容，转入同一任务和奖励事务，不由生产维修调用。交互实体的模型与闸门仍由主场景组合，尚无通用实体编辑器。

事务键为 mission:设施ID（维修）/ mission:任务ID（拍摄）/ offer:商品ID。完整快照先写 pending、重读校验、备份、替换，再改变内存。重复任务不增发，重复购买不扣款。存档损坏读上一份备份；两份均无效时保护原文件，进入临时只读档。未测试突然断电下的磁盘持久性。

格式 schema=1，包含 seed、world_version、content_fingerprint、credits、owned、transactions、facilities、missions、settings、build、deployment、dimension，并兼容新增 assignments 与 tracked_mission。assignments[任务ID] 保存 active/completed 和完成照片路径；缺少这两个新字段的旧档在内存补齐，既有设施/完成记录/事务归一为已完成，不重发奖励。Resource 保持只读。缺失配件保留原 ID 和原装配，运行暂回退免费初始套机；用户主动保存后才替换配置，上一份保留于备份。世界版本不匹配不写旧档；内容摘要改变给出提示，现有显式v1→v2备份重建迁移，其他版本仍保护原档。

## 工具与下一次工作

先读 ROADMAP 和 VALIDATION，重跑 tools/Test.ps1；涉及包内运行再跑 Build.ps1。构建保持文本 Resource，详见 SETUP 的导出差异。测试以 SCRIPT ERROR、ERROR、FAIL、退出码和预期结束标记共同判定，不能只相信 Godot 返回 0。

本地引擎路径、导入缓存、用户存档、截图和构建包不进 Git。用户已确认遥控器、按键、暂停、调参以及交互地图与导航功能检查正常；不会把功能确认或自动巡检当作 15 分钟人工飞行验收。

## 交互地图

`content/base/map_locations.json` 是历史版本夹具的独立地点清单；v4地点由BiomeWorld生成。该JSON仍可加载，含稳定 id、name、kind、三维 point、description 和可选 approach / interior_bounds。MapLocation 表示定义，MapNavigation 保存 selected_id、航点数组、索引与到达状态；地图选择不改变定义、部署或奖励。

RegionMap 是完整地图面板；MapCanvas 负责投影、图标命中、滚轮锚点缩放、拖动、朝向箭头与参考航线。右侧列表可选择重叠或不同高度地点。地图选择即开始导航，返回或再次 M 关闭后继续保留，清除指引同时移除高亮与航线。

主场景 `_teleport_to(id)` 通过 MapNavigation.teleport_location 再次校验 kind=teleport，拒绝商店、任务及未知 ID。地图 UI 不直接调用任意坐标部署。`_deploy(point)` 保留为内部重置及开发夹具入口；生产地图只能经过类型校验。启动以三维最近距离将历史任意部署位置归一到正式传送点，R 使用当前安全部署点。

NavigationHUD 根据活动 Camera3D 投影当前航点，屏内绘制圆环，屏外或身后绘制边缘箭头，并标注距离、航点序号和高度差。以 world_point − origin_offset 转本地坐标，兼容浮动原点和两种视角，菜单期间隐藏。

历史地图航线为当前位置到目标的参考连线，地下按approach进出；v4另由route_resolver对实际迷宫门图规划走廊及竖井航点。三维半径 5 m 切换航点，6 m 标记到达；到达最终地点也结束未经过的中间指引。未使用NavMesh或全局避障，不自动驾驶。地图 JSON 显式纳入导出过滤，包内检查另行执行。

## 探索任务与拍摄

MissionBoard 通过 F3 或遥控器 missions 动作打开。任务列表包含可领取/进行中/已完成；领取与追踪先写盘成功再更新导航。地图查看可预览未领取或已完成地点，不改变奖励状态。停止追踪不放弃任务，只清除属于该任务的导航，不清除用户独立选择的目的地。重启恢复进行中与追踪状态。

PhotoObjective.evaluate 共用于实时 HUD 和截图帧判定：相机世界位置与 -Z 方向、生成目标10～45 m 三维距离（历史夹具15～65 m）、18° 中心夹角，要求相机及目标碰撞就绪。主场景从活动相机向目标发射实际物理射线，排除自身机体；首个碰撞点在目标数据体积内表示命中建筑，其他几何表示遮挡。相机与碰撞查询使用本地坐标，距离和目标使用全局坐标，兼容两视角和浮动原点。

F12 在 frame_post_draw 读取画面与同帧相机/任务条件，再保存 PNG 与 JSON；菜单或失焦阻止任务拍摄。元数据包含 camera_position、camera_forward、mission_id、photo_check 及原有复现信息。保存失败不提交完成；不合格照片可保存但不领奖。ProgressStore 还校验 PNG、配套元数据、任务身份、距离/角度范围，再原子提交完成状态、照片路径、事务与奖励。已领取而未追踪的拍摄仍可完成，优先判断追踪的拍摄任务，再取首个进行中拍摄任务；v4可有多个拍摄委托，同一张照片只结算一份合格任务。

当前生产支持五类模板及顺序阶段；没有任意条件图、艺术评分或录像回放。

## 世界v2：细地形、建筑与材质

WorldProvider 在后台输出纯数据：盒/柱描述新增 surface 与 primitive；地形描述为 primitive=terrain，包含世界顶点、法线、顶点色、三角索引、每三角表面组及 surface_names。每64m格为17×17顶点、4m间距、512三角。TerrainSampler 仅是地表提供者内部的连续采样；世界公共接口仍是三维几何，不是单一height接口。

跨块顶点取相同全局坐标，法线由相同全局采样计算，支持负坐标及跨群系接缝。城市AABB参与地形边缘平滑过渡；地下预留块不生成地表。地形以最低顶点高度的垂直块为owner，外伸小于相邻块范围。WorldGeometry创建ArrayMesh与相同三角面的ConcavePolygonShape3D，双面碰撞；静态地形不是每个小格一个物理节点。

工业区增加金属/砖墙、卷帘门、排气设备与烟囱；园区使用浅色墙面、窗带、阳台与街树；新增赤陶旧城使用砖墙、瓦顶、雨棚。松风山谷使用同一连续地形规则、随机偏移和稀疏松林、小岩石；树干碰撞，v2树冠是装饰几何；v4新增锥形整体碰撞，不模拟细枝叶。新群系由oldtown.tres与pine_valley.tres登记；清空区由parameters.clearings声明。

WorldMaterials按表面类别生成128×128纹理及mipmap，共享纹理并缓存材料。砖缝、混凝土板缝、金属肋、玻璃反光带、岩层、草地、道路等分开处理，粗糙度/金属度不同。自然纹理对比度适当降低。世界空间投影的周期选择为64m的整除尺寸，原点按分块移动时保持纹理相位。终端、货车、闸门、起降平台、浮岛与地下也采用表面类别；天空使用原生ProceduralSkyMaterial。没有新增外部资产或运行依赖。

世界v2新增地图传送点，MapNavigation按min_world_version过滤；RegionMap使用实际群系范围绘制图层并允许滚动地点列表。旧世界不显示新区域入口。新增区域未增加商店、任务、复杂道路网或导航避障。

## 历史：世界v1→v2升级

WorldGenerator显式接收版本，v1使用保留的LegacyWorldProvider和原有5个群系，v2使用新版7个群系与细网格；旧地形未升级时不悄悄改变。旧档启动保持只读，显示具体升级界面；F1可再次打开。支持的升级仅限1→2，非通用版本迁移器。

ProgressStore.upgrade_world先将有效旧档原样复制为progress.json.world-v1.backup；已有有效同种子v1备份保留不覆盖，无效备份则拒绝升级。随后使用共同pending/校验/备份/原子替换流程提交world_version=2与新指纹，仅将deployment重置安全起降点，种子、信用点、装备、任务、照片证据、追踪及设置保留。普通保存不能绕过旧档只读状态。

成功后主场景暂停，WorldStreamer.replace_generator等待旧任务结束、清空旧结果和节点，再装载新生成器；同步原点、设施、导航与任务控制器，回到锈港并等待新碰撞就绪。没有修改用户正式存档来测试升级，所有自动检查使用user://tests隔离夹具。
