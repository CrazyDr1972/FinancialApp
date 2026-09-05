param(
  [string]$Version = '1.0.2',
  [int]$BuildNumber = 80
)

$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$exe = Join-Path $project 'build\windows\x64\runner\Release\financial_app.exe'
$icon = Join-Path $project 'assets\app_icon.ico'
$desktop = [Environment]::GetFolderPath('Desktop')

Get-Process financial_app -ErrorAction SilentlyContinue | Stop-Process -Force
Push-Location $project
try {
  flutter build windows --release --build-name=$Version --build-number=$BuildNumber
}
finally {
  Pop-Location
}

# Keep one Financial App shortcut while leaving unrelated desktop links untouched.
$shortcut = Join-Path $desktop 'Financial App.lnk'
if (-not (Test-Path -LiteralPath $shortcut)) {
  $legacy = Get-ChildItem -LiteralPath $desktop -Filter 'Financial App v*.lnk' -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($legacy) {
    Move-Item -LiteralPath $legacy.FullName -Destination $shortcut
  }
}

Get-ChildItem -LiteralPath $desktop -Filter 'Financial App v*.lnk' -File -ErrorAction SilentlyContinue |
  Remove-Item -Force

$shell = New-Object -ComObject WScript.Shell
$link = $shell.CreateShortcut($shortcut)
$link.TargetPath = $exe
$link.WorkingDirectory = $project
$link.IconLocation = "$icon,0"
$link.Description = "Financial App v$Version"
$link.Save()

Start-Process -FilePath $exe -WorkingDirectory $project
