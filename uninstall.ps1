# uninstall.ps1 - Remove o shim do NVIDIA e o auto-inicio (NAO mexe no config.toml)
# Uso:  powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1
$ErrorActionPreference = 'Continue'

$Startup = [Environment]::GetFolderPath('Startup')
$ShimCmd = Join-Path $Startup 'kimi-nvidia-shim.cmd'
if (Test-Path $ShimCmd) { Remove-Item -LiteralPath $ShimCmd -Force; Write-Host "[ok] auto-inicio removido: $ShimCmd" }

Get-CimInstance Win32_Process -Filter "Name='pythonw.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*nvidia_shim.py*' } |
    ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        Write-Host "[ok] processo do shim encerrado (pid $($_.ProcessId))"
    }

$ShimPy = Join-Path $env:USERPROFILE '.kimi-code\proxy\nvidia_shim.py'
if (Test-Path $ShimPy) { Remove-Item -LiteralPath $ShimPy -Force; Write-Host "[ok] script removido: $ShimPy" }

Write-Host ''
Write-Host 'Lembrete: o config.toml continua com  base_url = "http://127.0.0.1:8878/v1".'
Write-Host 'Para voltar direto a NVIDIA (o erro 400 voltara ate o bug do prompt_cache_key ser corrigido):'
Write-Host '  [providers.nvidia]  base_url = "https://integrate.api.nvidia.com/v1"'
