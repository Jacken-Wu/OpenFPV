# 原型开发准备

核查时间为 2026-10-21。这里区分开始编码、运行试飞与导出程序需要的准备。

## 1 已检查的环境

| 项目 | 检查结果 | 对开发的影响 |
| --- | --- | --- |
| 项目目录 | `D:/files/projects/codex/OpenFPV` | 可继续在此创建工程与文档 |
| Godot | `D:/Tools/Godot/Godot_v4.3-stable_win64_console.exe --version` 返回 `4.3.stable.official.77dcf97d8` | 保留旧版，另准备新基线 |
| 最新稳定版 | Godot 4.7.2，官方发布日期 2026-08-18 | 采用 Standard Windows x86_64 |
| 最新预览版 | Godot 4.8 beta1，官方发布日期 2026-10-15 | 不作为本原型基线 |
| 导出模板 | 标准用户目录未发现已安装的模板版本 | 不影响编辑器内运行，导出前再准备 |
| Git | `D:/Tools/Git/cmd/git.exe` 可用 | 无需重新安装；M0 时初始化本地仓库 |
| 电脑 | i5-12600K、约 32 GB 内存、RTX 4060 Ti | 可以开始原型验证，实际帧率仍需测量 |
| 控制设备 | 用户使用富斯 i6x 航模遥控器，通过加密狗转换为 USB 连接 | 作为 M1 主要试飞设备；具体 USB 设备名、轴与开关尚未实测 |

Godot 不在当前 PATH 中不构成问题，开发脚本可以使用明确的可执行文件路径。未发现 4.7.2 是本次对已知位置的检查结果，不代表已经搜索所有磁盘。

## 2 用户需要准备的事项

### 现在需要

1. 从 [Godot 官方 Windows 下载页](https://godotengine.org/download/windows/)下载 **Godot Engine 4.7.2 Standard Windows x86_64**。GDScript 路线选择普通版即可，无需 .NET 版。
2. 建议解压至 `D:/Tools/Godot/4.7.2/`，保留 GUI 程序和 `_console.exe` 程序在同一目录，不覆盖现有 4.3。
3. 将实际解压目录告诉 Codex。无需手动新建 Godot 项目，工程、目录、输入动作和调试场景由后续开发建立。

如果已经下载到其他位置，直接提供路径即可。编辑器先正常启动一次，确认可打开窗口；若系统弹出访问或图形驱动错误，保留原始报错内容用于诊断。

### 试飞前补充

- 已确认用户设备为富斯 i6x 加 USB 加密狗。试飞时将这套设备接入电脑并保持可用，在原型校准页确认油门、横滚、俯仰、偏航四个轴、中点、方向、行程与可见开关。
- 加密狗未必传递遥控器所有通道，实际通道数量和顺序以设备读数为准。如果只有四轴，电机解锁、重置和交互使用可重绑的键盘按键，不因此阻塞飞行。
- 用户无需事先提供 AETR/TAER 顺序或摇杆手型；校准向导通过逐轴操作确定，并保存独立设备配置。
- 普通手柄：提供型号，采用单独的回中油门输入方案。
- 暂时没有控制器：可用键盘进行场景与交互体验，飞行器也可接受脚本化输入做逻辑测试；精细 Acro 手感暂不能以键盘验收。

不要求为了开始原型立即购买设备。实际遥控器映射以本机读取结果为准，不按产品名称硬编码。

### 导出时再准备

在编辑器的导出模板管理器中安装与引擎匹配的 **4.7.2 Standard 导出模板**。首个目标为 Windows x86_64；导出中文界面时检查相应字体和 Unicode 支持。模板不是创建工程和编辑器内试飞的前置条件。

## 3 不需要预先安装或准备

- Visual Studio、C++ 编译环境、.NET SDK 与 Android SDK。
- Blender、体素插件、数字地球数据或商业素材包。
- 在线地图账号、模型 API 密钥或后端服务。
- GitHub 远程仓库、商店账号或发布手续。

Git 与本地工作流已具备，M0 中由开发端配置 `.gitignore` 和本地版本管理。最终开源许可证在公开发布前确定，不阻塞本地原型。

## 4 开发端会做的环境验证

先以用户提供的实际路径执行以下检查。这里的路径是建议位置，尚未验证存在。

```powershell
$GodotExe = 'D:/Tools/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe'
& $GodotExe --version
```

进入 M0 并创建 `game/project.godot` 后，再执行：

```powershell
& $GodotExe --headless --path 'D:/files/projects/codex/OpenFPV/game' --editor --import
& $GodotExe --path 'D:/files/projects/codex/OpenFPV/game' --editor
```

记录实际版本、渲染后端、启动结果和设备信息。未来启动脚本从本地配置或环境变量读取引擎路径，不把开发者个人磁盘路径写死到游戏代码或提交的通用脚本里。

若 Godot 之后推出新稳定版，也先沿用 4.7.2 完成当前阶段，单独测试升级后再变更基线。不要用 4.3 的通过结果代替 4.7.2 的验收。

## 5 官方依据

- [Windows 下载页](https://godotengine.org/download/windows/)
- [4.7.2 稳定版归档](https://godotengine.org/download/archive/4.7.2-stable/)
- [4.8 beta1 预览版归档](https://godotengine.org/download/archive/4.8-beta1/)
- [命令行教程](https://docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html)
- [项目导出](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_projects.html)
- [控制器与摇杆](https://docs.godotengine.org/en/4.7/tutorials/inputs/controllers_gamepads_joysticks.html)
