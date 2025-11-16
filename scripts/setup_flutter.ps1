
# Instala Flutter SDK en Windows mediante git clone y configura PATH de usuario.
# Uso:
#   1) Abre PowerShell como usuario normal (no requiere admin para PATH de usuario)
#   2) Ejecuta: Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
#   3) Ejecuta: .\scripts\setup_flutter.ps1
#   4) Cierra y vuelve a abrir PowerShell, luego corre: flutter --version

$ErrorActionPreference = 'Stop'

function Ensure-GitInstalled {
  try {
    git --version | Out-Null
    Write-Host "[OK] Git detectado." -ForegroundColor Green
  }
  catch {
    Write-Warning "Git no está instalado o no está en PATH. Intentando instalar con winget..."
    try {
      winget --version | Out-Null
    }
    catch {
      throw "winget no está disponible. Instala Git manualmente desde https://git-scm.com/download/win y reintenta."
    }
    winget install -e --id Git.Git --silent
    Write-Host "[OK] Git instalado. Reinicia PowerShell si no se detecta." -ForegroundColor Green
  }
}

function Ensure-FlutterCloned {
  $FlutterRoot = 'C:\src\flutter'
  $FlutterBat  = Join-Path $FlutterRoot 'bin\flutter.bat'

  if (Test-Path $FlutterBat) {
    Write-Host "[OK] Flutter ya existe en $FlutterRoot" -ForegroundColor Green
    return $FlutterBat
  }

  Write-Host "Creando C:\src si no existe..." -ForegroundColor Cyan
  New-Item -ItemType Directory -Path 'C:\src' -Force | Out-Null

  Write-Host "Clonando Flutter (rama stable) en $FlutterRoot ..." -ForegroundColor Cyan
  git clone https://github.com/flutter/flutter.git -b stable $FlutterRoot

  if (!(Test-Path $FlutterBat)) {
    throw "No se encontró $FlutterBat tras el clon. Revisa la salida de git."
  }

  Write-Host "[OK] Flutter clonado." -ForegroundColor Green
  return $FlutterBat
}

function Ensure-PathContainsFlutter($FlutterBin) {
  $currentUserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
  if ($currentUserPath -notlike "*${FlutterBin}*") {
    Write-Host "Añadiendo $FlutterBin al PATH de usuario..." -ForegroundColor Cyan
    $newPath = $currentUserPath
    if ([string]::IsNullOrWhiteSpace($newPath)) { $newPath = $FlutterBin }
    else {
      if ($newPath.Trim().EndsWith(';')) { $newPath = $newPath + $FlutterBin }
      else { $newPath = $newPath + ';' + $FlutterBin }
    }
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    Write-Host "[OK] PATH de usuario actualizado. Abre una NUEVA ventana de PowerShell para que surta efecto." -ForegroundColor Green
  }
  else {
    Write-Host "[OK] PATH ya contiene $FlutterBin" -ForegroundColor Green
  }
}

try {
  Ensure-GitInstalled
  $flutterBat = Ensure-FlutterCloned
  $flutterBin = Split-Path -Parent $flutterBat
  Ensure-PathContainsFlutter $flutterBin

  Write-Host "Probando flutter con ruta absoluta:" -ForegroundColor Cyan
  & $flutterBat --version
  Write-Host "Listo. Cierra y abre una nueva PowerShell, y ejecuta: flutter doctor" -ForegroundColor Yellow
}
catch {
  Write-Error $_
  exit 1
}