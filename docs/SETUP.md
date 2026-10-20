# 环境与启动

2026-10-21 验证引擎位于 D:/Tools/Godot，控制台为 Godot_v4.7.2-stable_win64_console.exe，实际版本 **4.7.2.stable.official.ed1daf0bf**。本机 i5-12600K、32 GB、RTX 4060 Ti，Compatibility / OpenGL 3.3，驱动 610.47。本地 Git main 已建立，未推送。

## 运行

双击根目录 Play.cmd 或 builds/OpenFPV-P1/Play.cmd。F2 校准，P 恢复，最低油门下空格解锁。F1 查看说明。本机 .local/godot-path.txt 已配置，不提交。

```powershell
$env:GODOT_EXE = 'D:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe'
./tools/Run.ps1
./tools/Run.ps1 -Editor
./tools/Test.ps1 -Window
./tools/Build.ps1
```

也可传 -GodotPath 参数。无需 .NET、C++、Blender、地图 API 或联网服务。

## i6x 校准

加密狗切至模拟器模式并接好遥控器。F2 选择设备，三轴回中、油门最低开始。逐轴完整移动，横滚停右端，俯仰停前端，偏航停右端，油门停最低，然后记录。

按实际 USB 数据校准，不假定通道顺序或开关数量。当前使用固定键盘解锁、重置和交互，尚无改键界面。四轴独立，油门全行程为 0 至 1。

配置按 GUID 加用户名称保存。同类加密狗可能共享 GUID，换遥控器后主动选择正确配置或重校准。匹配配置可以载入，但启动仍暂停和锁定。断连后 F2 重新选择，再 P 恢复；键盘回退也要明确点击。

## 构建

日志和截图在 .local/test-results，测试存档使用 user://tests 隔离。便携包在 builds/OpenFPV-P1，构建对比包与源工程内容指纹并提取引擎及组件许可。

便携包包含约 173 MiB 的完整 Godot 程序。匹配导出模板尚未安装，安装后可用 Windows 导出预设生成标准精简版。

当前固定 editor/export/convert_text_resources_to_binary=false。本项目在 4.7.2 的二进制资源转换打包路径中出现色板丢失，保留文本资源后通过；升级必须重跑包内检查。
