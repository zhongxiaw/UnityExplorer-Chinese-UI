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
function Build-UnityExplorer($c) { Write-Host "\n=== 开始构建配置: $c ==="; dotnet build src/UnityExplorer.sln -c $c }

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
}

# 构建配置
$Builds = @(
    @{ Config="Release_ML_Cpp_net6"; Path="Release/UnityExplorer.MelonLoader.IL2CPP.net6preview"; OutputDll="UnityExplorer.ML.IL2CPP.net6preview.dll";
       ILRepackInput=@("UnityExplorer.ML.IL2CPP.net6preview.dll", "mcs.dll"); Libs=@("lib/net6", "lib/unhollowed");
       Remove=@("UnityExplorer.ML.IL2CPP.net6preview.deps.json", "Tomlet.dll", "mcs.dll", "Iced.dll", "UnhollowerBaseLib.dll");
       Move=@{"UnityExplorer.ML.IL2CPP.net6preview.dll"="Mods"; "UniverseLib.IL2CPP.Unhollower.dll"="UserLibs"}; Zip="UnityExplorer.MelonLoader.IL2CPP.net6preview" },

    @{ Config="Release_ML_Cpp_net472"; Path="Release/UnityExplorer.MelonLoader.IL2CPP"; OutputDll="UnityExplorer.ML.IL2CPP.dll";
       ILRepackInput=@("UnityExplorer.ML.IL2CPP.dll", "mcs.dll"); Libs=@("lib/net472", "lib/net35", "lib/unhollowed");
       Remove=@("Tomlet.dll", "mcs.dll", "Iced.dll", "UnhollowerBaseLib.dll");
       Move=@{"UnityExplorer.ML.IL2CPP.dll"="Mods"; "UniverseLib.IL2CPP.Unhollower.dll"="UserLibs"}; Zip="UnityExplorer.MelonLoader.IL2CPP" },

    @{ Config="Release_ML_Mono"; Path="Release/UnityExplorer.MelonLoader.Mono"; OutputDll="UnityExplorer.ML.Mono.dll";
       ILRepackInput=@("UnityExplorer.ML.Mono.dll", "mcs.dll"); Libs=@("lib/net35");
       Remove=@("Tomlet.dll", "mcs.dll");
       Move=@{"UnityExplorer.ML.Mono.dll"="Mods"; "UniverseLib.Mono.dll"="UserLibs"}; Zip="UnityExplorer.MelonLoader.Mono" },

    @{ Config="Release_BIE_Cpp"; Path="Release/UnityExplorer.BepInEx.IL2CPP"; OutputDll="UnityExplorer.BIE.IL2CPP.dll";
       ILRepackInput=@("UnityExplorer.BIE.IL2CPP.dll", "mcs.dll", "Tomlet.dll"); Libs=@("lib/net472", "lib/unhollowed");
       Remove=@("Tomlet.dll", "mcs.dll", "Iced.dll", "UnhollowerBaseLib.dll");
       Move=@{"UnityExplorer.BIE.IL2CPP.dll"="plugins/sinai-dev-UnityExplorer"; "UniverseLib.IL2CPP.Unhollower.dll"="plugins/sinai-dev-UnityExplorer"}; Zip="UnityExplorer.BepInEx.IL2CPP" },

    @{ Config="Release_BIE_CoreCLR"; Path="Release/UnityExplorer.BepInEx.IL2CPP.CoreCLR"; OutputDll="UnityExplorer.BIE.IL2CPP.CoreCLR.dll";
       ILRepackInput=@("UnityExplorer.BIE.IL2CPP.CoreCLR.dll", "mcs.dll", "Tomlet.dll"); Libs=@("lib/net472", "lib/net6", "lib/interop");
       Remove=@("Tomlet.dll", "mcs.dll", "Iced.dll", "Il2CppInterop.Common.dll", "Il2CppInterop.Runtime.dll", "Microsoft.Extensions.Logging.Abstractions.dll", "UnityExplorer.BIE.IL2CPP.CoreCLR.deps.json");
       Move=@{"UnityExplorer.BIE.IL2CPP.CoreCLR.dll"="plugins/sinai-dev-UnityExplorer"; "UniverseLib.IL2CPP.Interop.dll"="plugins/sinai-dev-UnityExplorer"}; Zip="UnityExplorer.BepInEx.IL2CPP.CoreCLR" },

    @{ Config="Release_BIE5_Mono"; Path="Release/UnityExplorer.BepInEx5.Mono"; OutputDll="UnityExplorer.BIE5.Mono.dll";
       ILRepackInput=@("UnityExplorer.BIE5.Mono.dll", "mcs.dll", "Tomlet.dll"); Libs=@("lib/net35");
       Remove=@("Tomlet.dll", "mcs.dll");
       Move=@{"UnityExplorer.BIE5.Mono.dll"="plugins/sinai-dev-UnityExplorer"; "UniverseLib.Mono.dll"="plugins/sinai-dev-UnityExplorer"}; Zip="UnityExplorer.BepInEx5.Mono" },

    @{ Config="Release_BIE6_Mono"; Path="Release/UnityExplorer.BepInEx6.Mono"; OutputDll="UnityExplorer.BIE6.Mono.dll";
       ILRepackInput=@("UnityExplorer.BIE6.Mono.dll", "mcs.dll", "Tomlet.dll"); Libs=@("lib/net35");
       Remove=@("Tomlet.dll", "mcs.dll");
       Move=@{"UnityExplorer.BIE6.Mono.dll"="plugins/sinai-dev-UnityExplorer"; "UniverseLib.Mono.dll"="plugins/sinai-dev-UnityExplorer"}; Zip="UnityExplorer.BepInEx6.Mono" },

    @{ Config="Release_STANDALONE_Mono"; Path="Release/UnityExplorer.Standalone.Mono"; OutputDll="UnityExplorer.Standalone.Mono.dll";
       ILRepackInput=@("UnityExplorer.Standalone.Mono.dll", "mcs.dll", "Tomlet.dll"); Libs=@("lib/net35");
       Remove=@("Tomlet.dll", "mcs.dll"); Move=@{}; Zip="UnityExplorer.Standalone.Mono" },

    @{ Config="Release_STANDALONE_Cpp"; Path="Release/UnityExplorer.Standalone.IL2CPP"; OutputDll="UnityExplorer.Standalone.IL2CPP.dll";
       ILRepackInput=@("UnityExplorer.Standalone.IL2CPP.dll", "mcs.dll", "Tomlet.dll"); Libs=@("lib/net472", "lib/unhollowed");
       Remove=@("Tomlet.dll", "mcs.dll", "Iced.dll", "UnhollowerBaseLib.dll"); Move=@{}; Zip="UnityExplorer.Standalone.IL2CPP" }
)

# 执行构建
foreach ($b in $Builds) {
    Build-UnityExplorer $b.Config
    Run-ILRepack "$($b.Path)/$($b.OutputDll)" ($b.ILRepackInput | % {"$($b.Path)/$_"}) ($b.Libs + $b.Path)
    Clean-And-Move $b.Path $b.Remove $b.Move
    Create-Zip $b.Path $b.Zip
}

# ----------- UnityEditor 特殊打包 -----------
$src = "Release/UnityExplorer.Standalone.Mono"
$dst = "UnityEditorPackage/Runtime"
Copy-Item "$src/UnityExplorer.STANDALONE.Mono.dll" $dst -Force
Copy-Item "$src/UniverseLib.Mono.dll" $dst -Force
Remove-Item Release/UnityExplorer.Editor.zip -EA 0
7z a Release/UnityExplorer.Editor.zip .\UnityEditorPackage\* > $null
Write-Host "✅ UnityEditor 扩展包已构建完成。" -ForegroundColor Green
