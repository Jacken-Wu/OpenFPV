# 素材与依赖来源

## 内容0.22：内嵌许可

未引入新素材、运行依赖或许可证选择。根MIT版权文本由Build同步到game/legal/openfpv-license.txt；game/legal/godot-notices.txt由当前4.7.2引擎Engine.get_license_text/get_copyright_info/get_license_info生成，保留完整第三方条目。这两份文本内嵌PCK，可从游戏Esc“关于与许可”离线阅读；Release输出目录不再复制任何外部声明/README/docs。

这一做法采用Godot官方列出的游戏内许可页面方式，参见[Godot许可说明](https://docs.godotengine.org/en/stable/about/complying_with_licenses.html)。渲染器仍属于同一官方Standard引擎，改用其原生Mobile/Vulkan实现；没有新增原生插件、ANGLE DLL或第三方下载。


## 内容0.21：原创游戏图标

game/assets/openfpv.svg为原创矢量源稿，使用现有界面的深蓝、青绿与金色，四旋翼、前向箭头和门形轮廓；PNG为预览，ICO包含16/24/32/48/64/128/256七尺寸。tools/render_icon.gd调用Godot自身SVG栅格化生成，未使用外部图标、模型、字形或图像采样，沿用项目MIT。

构建辅助windows_icon.cs由PowerShell Add-Type在构建进程调用系统Windows资源API，编辑官方模板私有副本并检查成品资源；没有增加游戏运行依赖、Godot.NET、原生插件或rcedit。官方模板代码不作修改，也未自编译引擎；发行许可规则仍与0.20一致。

## 内容0.20：原生导出模板与发行声明

新增构建输入为Godot4.7.2 Standard官方Windows x64 Debug/Release导出模板，仅缓存于.local，不进入源码；未引入自建引擎、原生插件或新的游戏素材。模板归档来源为[Godot官方4.7.2归档](https://godotengine.org/download/archive/4.7.2-stable/)，版本文本与实际运行引擎均验证4.7.2。Setup脚本仅在显式-Download时下载约1.28GB全平台归档，再提取两类Windows模板。

项目MIT选择沿用用户原先授权。Release随附LICENSE、README和从当前引擎提取的GODOT-NOTICES.txt；单exe可运行不代表分发可以省略许可。Debug不用于发布，按用户要求不携带这些分发文档。上节0.19“构建同时携带”及旧便携方案仅为历史记录，以本节/README的新渠道规则为准。

## 当前许可证（内容0.19，2026-10-25）

用户已明确选择MIT。项目原创代码、文档、生成几何、程序纹理与原创合成音乐/音效采用根目录`LICENSE`中的MIT许可证；此前章节中的“尚未选择”仅记录当时状态。Godot与其附带组件的独立许可继续保留在构建生成的`GODOT-NOTICES.txt`中。构建同时携带项目LICENSE和中文README，没有引入新的第三方素材或依赖。

## 内容0.16资源来源

八首新增原创8bit风格曲目由tools/ComposeMusic.py的独立乐谱生成：苍脊《越过苍脊》98BPM、雪山《银冠之上》88、雪原《寂光漫游》82、废城《残墙间的风》94、巨构《巨门回响》78、深峡《赤壁穿风》106、戈壁《砾石疾行》116、火山《玄焰跃动》122。每首16小节，原生循环PCM，合计15首；本轮只生成新增八首，旧七首文件保持。scores.json保存全部原创音符与和声，不使用外部旋律/采样。

九种事件耳标由GameEventAudio.CUES和synthesize使用正弦/弱谐波/短包络原创合成；新增结构、管道曲面和三面架均由项目代码与Godot基础网格构建，无下载贴图/模型/字体。雪、玄武岩和熔光复用原有程序纹理方式。未新增运行依赖、在线服务或作最终许可证选择。

## 内容0.15资源来源

过门0.13秒单音、终点0.58秒四音旋律由FlightAudio.race_stream以正弦及弱二次谐波原创合成，原生PCM与短包络，无外部采样。电机同一合成器调亮音色，环绕球和引导圈继续用既有基础网格。无新增依赖/音源/模型/许可证选择；captures/audio/rotor-0.15-preview.wav来自最终包原生录音，仅首尾20ms淡入淡出，非运行素材。

## 内容0.14资源来源

新环境航线、落地门架和提示配色均用既有Godot网格与项目代码实现；没有新增外部模型/纹理/音源或依赖。电机8秒PCM仍由FlightAudio原创数学合成，独立气流与有界相位纹理消除旧短周期积分相位拍频，保持桨叶嗡鸣；破裂声和七首背景曲不改。captures/audio/rotor-0.14-preview.wav为原生输出录音预览（首尾淡入淡出），不作为运行时素材。

内容0.13的任务落地平台、立体路标与六色碎纸均由项目代码和Godot基础网格生成；破裂声由FlightAudio.balloon_stream以固定随机种子、滤波噪声和衰减低音原创合成，不使用外部采样。电机音源为原合成器修订。无新外部素材、字体、依赖、在线服务或许可证变更。

内容0.12的挑战塔楼/旋转门框、气球、观测球与移动观测机均由项目代码和Godot基础网格生成；三套新整机及配件、动力数据、商品说明和八项成就为本项目原创数据定义。没有下载模型、贴图、音效或字体，没有新增运行依赖、在线服务或更改许可证。

内容0.10新增七首原创8bit风格音乐，由tools/ComposeMusic.py中的原创音符/和声表和标准数学合成生成：工业区《齿轮与晨光》、园区《绿庭的像素风》、旧城《赤陶巷弄》、峡谷《峡谷回声》、松谷《松针间的溪流》、浮岛《云端轻航》、迷宫《深层寻路》。源WAV及scores.json在game/audio/music，无外部旋律、采样、音源库或在线服务；素材最终许可证与项目其余原创内容一致，仍待用户选定。16位PCM用于低底噪，8bit指配器风格。Python仅用于离线重建素材，游戏运行仅用Godot原生音频能力。

P1 未接入数字地球、在线地图、Minecraft 数据、商业模型或体素插件。

| 内容 | 来源 |
| --- | --- |
| 世界、车辆、终端 | 项目 GDScript 生成基础几何 |
| 分类表面纹理 | WorldMaterials 生成128×128纹理和mipmap，砖缝/板缝/岩层/草地等分别构造，无外部贴图 |
| 连续地形、旧城、松林 | TerrainSampler / WorldProvider 原生网格与基础几何，包含实际碰撞 |
| 天空 | Godot ProceduralSkyMaterial 与项目配色 |
| 机体、桨叶 | FPVDrone 使用 BoxMesh / CylinderMesh |
| UI、标记与地图 | Godot 控件与项目绘制代码 |
| 四电机声音与快门声 | FlightAudio原生生成22050Hz/16位PCM，循环谐波/空气纹理与双脉冲快门，无外部音效 |
| 字体 | Godot 默认字体及系统回退，未打包 Windows 字体 |
| 引擎 | 用户本机 Godot 4.7.2 Standard |

构建从运行时提取引擎及所带组件许可，写入 GODOT-NOTICES.txt。原创代码和内容的最终开源许可证尚未确定，未对外发布。后续外部素材逐项记录作者、链接、版本、许可、修改和署名方式。

内容0.9的公园、亭、候车站、古院、双塔、通信塔、金字塔、遗迹、基站、渡槽、云端环廊、开放机库和涡轮厅由Architecture原生盒体/柱体/旋转梁组合生成，继续使用WorldMaterials分类纹理；没有下载模型、贴图或新增插件依赖。
