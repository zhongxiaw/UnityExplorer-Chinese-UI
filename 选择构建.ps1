# =================== UnityExplorer 构建工具 ===================
# 工具检测函数
function Ensure-Tool($name, $check, $message, $downloadAction) {
    if (-not (& $check)) {
        Write-Host $message -ForegroundColor Red
        if ($downloadAction) { & $downloadAction }
        if (-not (& $check)) { exit 1 }
    }
}

# .NET SDK 检测及安装
Ensure-Tool `
    "dotnet" `
    { Get-Command "dotnet" -ErrorAction SilentlyContinue } `
    "[错误] 未检测到 .NET SDK，开始下载..." `
    {
        $url = "https://dotnet.microsoft.com/en-us/download/dotnet/thank-you/sdk-8.0.100-windows-x64-installer"
        $exe = "$env:TEMP\dotnet-sdk-installer.exe"
        Invoke-WebRequest $url -OutFile $exe
        Start-Process $exe "/install /quiet /norestart" -Wait
        Write-Host "[成功] .NET SDK 安装完成。" -ForegroundColor Green
    }

# 7z 检测
Ensure-Tool `
    "7z" `
    { Get-Command 7z -ErrorAction SilentlyContinue } `
    "[错误] 未检测到 7z，请安装并配置 PATH：https://www.7-zip.org/" `
    $null

# ILRepack 检测
Ensure-Tool `
    "ILRepack" `
    { Test-Path "lib/ILRepack.exe" } `
    "[错误] 缺少 lib/ILRepack.exe，请放入该文件：https://github.com/gluck/il-repack/releases" `
    $null

# 编译函数
function Build-UnityExplorer($c) { 
    Write-Host "\n=== 开始构建配置: $c ===" -ForegroundColor Cyan
    dotnet build src/UnityExplorer.sln -c $c 
}

# 合并 DLL
function Run-ILRepack($OutputDll, $InputDlls, $LibDirs) {
    & lib/ILRepack.exe /target:library /internalize ($LibDirs | ForEach-Object { "/lib:$_" }) /out:$OutputDll $InputDlls
}

# 清理 & 移动
function Clean-And-Move($Path, $RemoveDlls, $MoveMap) {
    $RemoveDlls | ForEach-Object { Remove-Item "$Path/$_" -EA 0 }
    $MoveMap.Keys | ForEach-Object {
        $dest = "$Path/$($MoveMap[$_])"
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
        Move-Item "$Path/$_" $dest -Force
    }
}

# 打包为 zip
function Create-Zip($Path, $Name) {
    Remove-Item "$Path/../$Name.zip" -EA 0
    7z a "$Path/../$Name.zip" "$Path\*" > $null
    Write-Host "✅ 已创建压缩包: $Name.zip" -ForegroundColor Green
}

# 显示构建菜单
function Show-BuildMenu {
    Write-Host "`n===== UnityExplorer 构建菜单 =====" -ForegroundColor Yellow
    Write-Host " 0. 全部构建" -ForegroundColor Cyan
    
    $index = 1
    foreach ($build in $Builds) {
        $platform = if ($build.Name -match "Mono") { "Mono" } else { "IL2CPP" }
        $loader = switch -Wildcard ($build.Name) {
            "*ML*" { "MelonLoader" }
            "*BIE*" { "BepInEx" }
            "*STANDALONE*" { "独立版" }
            default { "" }
        }
        
        Write-Host " $index. [$platform] $loader - $($build.DisplayName)" -ForegroundColor Cyan
        $index++
    }
    
    Write-Host " $index. UnityEditor 扩展包" -ForegroundColor Cyan
    $editorIndex = $index
    Write-Host "`n 输入序号 (多个用逗号分隔, 0=全部): " -NoNewline -ForegroundColor Yellow
}

# 构建配置
$Builds = @(
    @{ 
        Name = "ML_IL2CPP_net6"; 
        DisplayName = "MelonLoader (net6)";
        Config = "Release_ML_Cpp_net6"; 
        Path = "Release/UnityExplorer.MelonLoader.IL2CPP.net6preview"; 
        OutputDll = "UnityExplorer.ML.IL2CPP.net6preview.dll";
        ILRepackInput = @("UnityExplorer.ML.IL2CPP.net6preview.dll", "mcs.dll"); 
        Libs = @("lib/net6", "lib/unhollowed");
        Remove = @("UnityExplorer.ML.IL2CPP.net6preview.deps.json", "Tomlet.dll", "mcs.dll", "Iced.dll", "UnhollowerBaseLib.dll");
        Move = @{"UnityExplorer.ML.IL2CPP.net6preview.dll" = "Mods"; "UniverseLib.IL2CPP.Unhollower.dll" = "UserLibs"}; 
        Zip = "UnityExplorer.MelonLoader.IL2CPP.net6preview" 
    },

    @{ 
        Name = "ML_IL2CPP_net472"; 
        DisplayName = "MelonLoader (net472)";
        Config = "Release_ML_Cpp_net472"; 
        Path = "Release/UnityExplorer.MelonLoader.IL2CPP"; 
        OutputDll = "UnityExplorer.ML.IL2CPP.dll";
        ILRepackInput = @("UnityExplorer.ML.IL2CPP.dll", "mcs.dll"); 
        Libs = @("lib/net472", "lib/net35", "lib/unhollowed");
        Remove = @("Tomlet.dll", "mcs.dll", "Iced.dll", "UnhollowerBaseLib.dll");
        Move = @{"UnityExplorer.ML.IL2CPP.dll" = "Mods"; "UniverseLib.IL2CPP.Unhollower.dll" = "UserLibs"}; 
        Zip = "UnityExplorer.MelonLoader.IL2CPP" 
    },

    @{ 
        Name = "ML_Mono"; 
        DisplayName = "MelonLoader Mono";
        Config = "Release_ML_Mono"; 
        Path = "Release/UnityExplorer.MelonLoader.Mono"; 
        OutputDll = "UnityExplorer.ML.Mono.dll";
        ILRepackInput = @("UnityExplorer.ML.Mono.dll", "mcs.dll"); 
        Libs = @("lib/net35");
        Remove = @("Tomlet.dll", "mcs.dll");
        Move = @{"UnityExplorer.ML.Mono.dll" = "Mods"; "UniverseLib.Mono.dll" = "UserLibs"}; 
        Zip = "UnityExplorer.MelonLoader.Mono" 
    },

    @{ 
        Name = "BIE_IL2CPP"; 
        DisplayName = "BepInEx IL2CPP";
        Config = "Release_BIE_Cpp"; 
        Path = "Release/UnityExplorer.BepInEx.IL2CPP"; 
        OutputDll = "UnityExplorer.BIE.IL2CPP.dll";
        ILRepackInput = @("UnityExplorer.BIE.IL2CPP.dll", "mcs.dll", "Tomlet.dll"); 
        Libs = @("lib/net472", "lib/unhollowed");
        Remove = @("Tomlet.dll", "mcs.dll", "Iced.dll", "UnhollowerBaseLib.dll");
        Move = @{"UnityExplorer.BIE.IL2CPP.dll" = "plugins/sinai-dev-UnityExplorer"; "UniverseLib.IL2CPP.Unhollower.dll" = "plugins/sinai-dev-UnityExplorer"}; 
        Zip = "UnityExplorer.BepInEx.IL2CPP" 
    },

    @{ 
        Name = "BIE_CoreCLR"; 
        DisplayName = "BepInEx CoreCLR";
        Config = "Release_BIE_CoreCLR"; 
        Path = "Release/UnityExplorer.BepInEx.IL2CPP.CoreCLR"; 
        OutputDll = "UnityExplorer.BIE.IL2CPP.CoreCLR.dll";
        ILRepackInput = @("UnityExplorer.BIE.IL2CPP.CoreCLR.dll", "mcs.dll", "Tomlet.dll"); 
        Libs = @("lib/net472", "lib/net6", "lib/interop");
        Remove = @("Tomlet.dll", "mcs.dll", "Iced.dll", "Il2CppInterop.Common.dll", "Il2CppInterop.Runtime.dll", "Microsoft.Extensions.Logging.Abstractions.dll", "UnityExplorer.BIE.IL2CPP.CoreCLR.deps.json");
        Move = @{"UnityExplorer.BIE.IL2CPP.CoreCLR.dll" = "plugins/sinai-dev-UnityExplorer"; "UniverseLib.IL2CPP.Interop.dll" = "plugins/sinai-dev-UnityExplorer"}; 
        Zip = "UnityExplorer.BepInEx.IL2CPP.CoreCLR" 
    },

    @{ 
        Name = "BIE5_Mono"; 
        DisplayName = "BepInEx 5 Mono";
        Config = "Release_BIE5_Mono"; 
        Path = "Release/UnityExplorer.BepInEx5.Mono"; 
        OutputDll = "UnityExplorer.BIE5.Mono.dll";
        ILRepackInput = @("UnityExplorer.BIE5.Mono.dll", "mcs.dll", "Tomlet.dll"); 
        Libs = @("lib/net35");
        Remove = @("Tomlet.dll", "mcs.dll");
        Move = @{"UnityExplorer.BIE5.Mono.dll" = "plugins/sinai-dev-UnityExplorer"; "UniverseLib.Mono.dll" = "plugins/sinai-dev-UnityExplorer"}; 
        Zip = "UnityExplorer.BepInEx5.Mono" 
    },

    @{ 
        Name = "BIE6_Mono"; 
        DisplayName = "BepInEx 6 Mono";
        Config = "Release_BIE6_Mono"; 
        Path = "Release/UnityExplorer.BepInEx6.Mono"; 
        OutputDll = "UnityExplorer.BIE6.Mono.dll";
        ILRepackInput = @("UnityExplorer.BIE6.Mono.dll", "mcs.dll", "Tomlet.dll"); 
        Libs = @("lib/net35");
        Remove = @("Tomlet.dll", "mcs.dll");
        Move = @{"UnityExplorer.BIE6.Mono.dll" = "plugins/sinai-dev-UnityExplorer"; "UniverseLib.Mono.dll" = "plugins/sinai-dev-UnityExplorer"}; 
        Zip = "UnityExplorer.BepInEx6.Mono" 
    },

    @{ 
        Name = "STANDALONE_Mono"; 
        DisplayName = "独立版 Mono";
        Config = "Release_STANDALONE_Mono"; 
        Path = "Release/UnityExplorer.Standalone.Mono"; 
        OutputDll = "UnityExplorer.Standalone.Mono.dll";
        ILRepackInput = @("UnityExplorer.Standalone.Mono.dll", "mcs.dll", "Tomlet.dll"); 
        Libs = @("lib/net35");
        Remove = @("Tomlet.dll", "mcs.dll"); 
        Move = @{}; 
        Zip = "UnityExplorer.Standalone.Mono" 
    },

    @{ 
        Name = "STANDALONE_IL2CPP"; 
        DisplayName = "独立版 IL2CPP";
        Config = "Release_STANDALONE_Cpp"; 
        Path = "Release/UnityExplorer.Standalone.IL2CPP"; 
        OutputDll = "UnityExplorer.Standalone.IL2CPP.dll";
        ILRepackInput = @("UnityExplorer.Standalone.IL2CPP.dll", "mcs.dll", "Tomlet.dll"); 
        Libs = @("lib/net472", "lib/unhollowed");
        Remove = @("Tomlet.dll", "mcs.dll", "Iced.dll", "UnhollowerBaseLib.dll"); 
        Move = @{}; 
        Zip = "UnityExplorer.Standalone.IL2CPP" 
    }
)

# 显示构建菜单
Show-BuildMenu
$selection = Read-Host

# 解析用户选择
$selectedBuilds = @()
$buildEditor = $false

if ($selection -eq "0") {
    $selectedBuilds = $Builds
    $buildEditor = $true
}
else {
    $selections = $selection -split ',' | ForEach-Object { $_.Trim() }
    
    foreach ($s in $selections) {
        $index = [int]$s - 1
        
        if ($index -eq $Builds.Count) {
            $buildEditor = $true
        }
        elseif ($index -ge 0 -and $index -lt $Builds.Count) {
            $selectedBuilds += $Builds[$index]
        }
        else {
            Write-Host "无效的选择: $s" -ForegroundColor Red
        }
    }
}

# 执行构建
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

foreach ($b in $selectedBuilds) {
    Write-Host "`n🚀 开始构建: $($b.DisplayName) [$($b.Name)]" -ForegroundColor Magenta
    
    Build-UnityExplorer $b.Config
    Run-ILRepack "$($b.Path)/$($b.OutputDll)" ($b.ILRepackInput | ForEach-Object { "$($b.Path)/$_" }) ($b.Libs + $b.Path)
    Clean-And-Move $b.Path $b.Remove $b.Move
    Create-Zip $b.Path $b.Zip
    
    Write-Host "✅ 完成构建: $($b.DisplayName)" -ForegroundColor Green
}

# UnityEditor 特殊打包
if ($buildEditor) {
    Write-Host "`n🚀 开始构建: UnityEditor 扩展包" -ForegroundColor Magenta
    
    $src = "Release/UnityExplorer.Standalone.Mono"
    $dst = "UnityEditorPackage/Runtime"
    
    if (-not (Test-Path $src)) {
        Write-Host "⚠️ 独立版 Mono 未构建，正在构建依赖项..." -ForegroundColor Yellow
        $standaloneMono = $Builds | Where-Object { $_.Name -eq "STANDALONE_Mono" } | Select-Object -First 1
        
        if ($standaloneMono) {
            Build-UnityExplorer $standaloneMono.Config
            Run-ILRepack "$($standaloneMono.Path)/$($standaloneMono.OutputDll)" ($standaloneMono.ILRepackInput | ForEach-Object { "$($standaloneMono.Path)/$_" }) ($standaloneMono.Libs + $standaloneMono.Path)
            Clean-And-Move $standaloneMono.Path $standaloneMono.Remove $standaloneMono.Move
        }
        else {
            Write-Host "❌ 找不到独立版 Mono 配置，无法构建编辑器包" -ForegroundColor Red
            exit 1
        }
    }
    
    Copy-Item "$src/UnityExplorer.STANDALONE.Mono.dll" $dst -Force
    Copy-Item "$src/UniverseLib.Mono.dll" $dst -Force
    Remove-Item Release/UnityExplorer.Editor.zip -EA 0
    7z a Release/UnityExplorer.Editor.zip ".\UnityEditorPackage\*" > $null
    Write-Host "✅ UnityEditor 扩展包已构建完成。" -ForegroundColor Green
}

$stopwatch.Stop()
$totalTime = [math]::Round($stopwatch.Elapsed.TotalMinutes, 2)
Write-Host "`n🎉 所有构建任务完成! 总耗时: $totalTime 分钟" -ForegroundColor Green