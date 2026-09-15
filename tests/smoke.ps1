# Run on Windows: powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File tests\smoke.ps1
$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path (Split-Path $PSScriptRoot) 'vexan_installers.ps1'
$tokens=$null; $parseErrors=$null
[System.Management.Automation.Language.Parser]::ParseFile($scriptPath,[ref]$tokens,[ref]$parseErrors) | Out-Null
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
& $scriptPath -SelfTest
& $scriptPath -SmokeTest
