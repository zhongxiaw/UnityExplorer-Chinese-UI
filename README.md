<p align="center">
  <img align="center" src="img/icon.png">
</p>

<p align="center">
  🔍 一款用于探索、调试和修改Unity游戏的实时界面工具
</p>
<p align="center">
  ✔️ 支持Unity 5.2至2021+大多数版本（IL2CPP与Mono运行时）
</p>
<p align="center">
  ✨ 基于 <a href="https://github.com/sinai-dev/UniverseLib">UniverseLib</a> 驱动
</p>

# 版本发布 [![](https://img.shields.io/github/downloads/sinai-dev/UnityExplorer/total.svg)](../../releases)

[![](https://img.shields.io/github/release/sinai-dev/UnityExplorer.svg?label=当前版本)](../../releases/latest) [![](https://img.shields.io/github/workflow/status/sinai-dev/UnityExplorer/Build%20UnityExplorer)](https://github.com/sinai-dev/UnityExplorer/actions) [![](https://img.shields.io/github/downloads/sinai-dev/UnityExplorer/latest/total.svg)](../../releases/latest)

⚡ Thunderstore平台下载: [BepInEx Mono版](https://thunderstore.io/package/sinai-dev/UnityExplorer) | [BepInEx IL2CPP版](https://gtfo.thunderstore.io/package/sinai-dev/UnityExplorer_IL2CPP) | [MelonLoader IL2CPP版](https://boneworks.thunderstore.io/package/sinai-dev/UnityExplorer_IL2CPP_ML)

## 发布周期

每周最多发布一次新版本，通常安排在周末。

夜间构建版本可在[此处](https://github.com/sinai-dev/UnityExplorer/actions)获取。

## BepInEx 版本

| 版本类型       | IL2CPP支持 | Mono支持 |
|--------------|-----------|---------|
| BIE 6.X      | ✅ [下载](https://github.com/sinai-dev/UnityExplorer/releases/latest/download/UnityExplorer.BepInEx.IL2CPP.zip) | ✅ [下载](https://github.com/sinai-dev/UnityExplorer/releases/latest/download/UnityExplorer.BepInEx6.Mono.zip) |
| BIE 6.X (CoreCLR) | ✅ [下载](https://github.com/sinai-dev/UnityExplorer/releases/latest/download/UnityExplorer.BepInEx.IL2CPP.CoreCLR.zip) | ✖ 不支持 |
| BIE 5.X      | ✖️ 不支持 | ✅ [下载](https://github.com/sinai-dev/UnityExplorer/releases/latest/download/UnityExplorer.BepInEx5.Mono.zip) |

**安装步骤**：
1. 解压下载的压缩包
2. 将 `plugins/sinai-dev-UnityExplorer` 文件夹复制到 `BepInEx/plugins/` 目录

<i>注：BepInEx 6可通过 [builds.bepinex.dev](https://builds.bepinex.dev/projects/bepinex_be) 获取</i>

## MelonLoader 版本

| 版本类型       | IL2CPP支持 | Mono支持 |
|--------------|-----------|---------|
| ML 0.5       | ✅ [下载](https://github.com/sinai-dev/UnityExplorer/releases/latest/download/UnityExplorer.MelonLoader.IL2CPP.zip) | ✅ [下载](https://github.com/sinai-dev/UnityExplorer/releases/latest/download/UnityExplorer.MelonLoader.Mono.zip) | 
| ML 0.6       | ✅ [下载](https://github.com/sinai-dev/UnityExplorer/releases/latest/download/UnityExplorer.MelonLoader.IL2CPP.net6preview.zip) | ✖️ 不支持 |

**安装步骤**：
1. 解压下载的压缩包
2. 将 `Mods` 文件夹内的DLL文件复制到MelonLoader的 `Mods` 目录
3. 将 `UserLibs` 文件夹内所有DLL复制到MelonLoader的 `UserLibs` 目录

## 独立版

| IL2CPP支持 | Mono支持 |
|-----------|---------|
| ✅ [下载](https://github.com/sinai-dev/UnityExplorer/releases/latest/download/UnityExplorer.Standalone.IL2CPP.zip) | ✅ [下载](https://github.com/sinai-dev/UnityExplorer/releases/latest/download/UnityExplorer.Standalone.Mono.zip) | 

独立版需手动加载依赖项：
1. 确保已加载必要库文件（UniverseLib、HarmonyX和MonoMod），可从[编辑器版](https://github.com/sinai-dev/UnityExplorer/releases/latest/download/UnityExplorer.Editor.zip)获取
2. IL2CPP版本需额外加载Il2CppAssemblyUnhollower
3. 调用 `UnityExplorer.ExplorerStandalone.CreateInstance()` 初始化
4. 可选订阅 `ExplorerStandalone.OnLog` 事件处理日志

## Unity编辑器集成

1. 下载[编辑器版]([https://github.com/sinai-dev/UnityExplorer/releases/latest/download/UnityExplorer.Editor.zip](https://github.com/zhongxiaw/UnityExplorer-Chinese-UI/blob/886e67d5131fcd7e50736d67e0bb36a4ad0f0063/Release/UnityExplorer.Editor.zip))
2. 通过Package Manager导入或手动拖入Assets文件夹
3. 将`Runtime/UnityExplorer`预制体拖入场景，或添加`Explorer Editor Behaviour`脚本

# 常见问题解决方案

配置文件路径：
- BepInEx: `BepInEx\config\com.sinai.unityexplorer.cfg`
- MelonLoader: `UserData\MelonPreferences.cfg`
- 独立版: `sinai-dev-UnityExplorer\config.cfg`

建议调整参数：
- `Startup_Delay_Time`：延长至5-10秒解决启动崩溃
- `Disable_EventSystem_Override`：输入异常时设为`true`

# 功能概览

<p align="center">
  <a href="https://raw.githubusercontent.com/sinai-dev/UnityExplorer/master/img/preview.png">
    <img src="img/preview.png" />
  </a>
</p>

### 对象检查API

```csharp
// 检查对象
UnityExplorer.InspectorManager.Inspect(目标对象);

// 检查类型
UnityExplorer.InspectorManager.Inspect(typeof(某类));
```

### 对象浏览器
- **场景浏览器**：遍历活动场景及常驻对象
- **对象搜索**：支持Unity对象和C#单例的模糊搜索

### 检查器功能
- 实时编辑字段值（按Enter确认/Esc取消）
- 支持纹理查看与PNG导出
- 音频片段播放与WAV导出

### C#控制台
- 支持REPL即时执行代码
- 自动加载`Scripts/startup.cs`脚本

### 钩子管理器
- 可视化方法Hook配置
- 支持前缀/后缀/终结器/转换器多种Hook类型

### 自由相机
- WASD移动 + 鼠标控制视角
- 支持主相机/自定义相机切换

### 更多特性
- 鼠标悬停检查（支持3D物体和UI元素）
- 全局剪贴板共享
- 可自定义的界面设置

# 构建说明

1. 运行`全部构建.ps1` PowerShell脚本，全部生成打包。
2. 运行`选择构建.ps1` PowerShell脚本，选择性生成产物。
3. 构建产物位于`Release`文件夹

# 版权声明

本项目与Unity Technologies无关联。"Unity"及相关商标归Unity Technologies所有。
