# Build with the .NET Framework compiler included in Windows.
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Path $dist -Force | Out-Null
$source = [IO.File]::ReadAllText((Join-Path $root 'vexan_installers.ps1'))
$source = $source.Replace('@@CATALOG@@', [IO.File]::ReadAllText((Join-Path $root 'catalog.json')))
$source = $source.Replace('@@XAML@@', [IO.File]::ReadAllText((Join-Path $root 'interface.xaml')))
$source = $source.Replace('@@ICON@@', [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $root 'src\firstinstall.ico'))))
$source = $source.Replace('@@WINDOW_HELPER@@', [IO.File]::ReadAllText((Join-Path $root 'src\window-helper.cs')))
$source = $source.Replace('@@PROFILES@@', [IO.File]::ReadAllText((Join-Path $root 'profiles.json')))
$payload = Join-Path $dist 'FirstInstall.embedded.ps1'
[IO.File]::WriteAllText($payload, $source, [Text.UTF8Encoding]::new($true))
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
& $compiler /nologo /target:winexe /platform:x64 /optimize+ /warnaserror+ /reference:System.Windows.Forms.dll "/win32manifest:$root\src\app.manifest" "/win32icon:$root\src\firstinstall.ico" "/resource:$payload,FirstInstall.Payload" "/out:$dist\FirstInstall.exe" "$root\src\launcher.cs"
if ($LASTEXITCODE -ne 0) { throw 'Build failed.' }
Write-Output "$dist\FirstInstall.exe"
