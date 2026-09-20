# install.ps1 - Configura o Kimi Code para usar o GLM-5.3 da NVIDIA via shim local
# Uso:  powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
$ErrorActionPreference = 'Stop'
$Port = 8878

$Kit = $PSScriptRoot
$KimiHome = Join-Path $env:USERPROFILE '.kimi-code'
$ProxyDir = Join-Path $KimiHome 'proxy'
$ConfigPath = Join-Path $KimiHome 'config.toml'
$Startup = [Environment]::GetFolderPath('Startup')

Write-Host '== Kimi Code + NVIDIA GLM-5.3: instalacao =='

# 0) Corrigir/previnir EPERM no workspaces.json (lock de antivirius/indexador)
$Wspaces = Join-Path $KimiHome 'workspaces.json'
if (Test-Path $Wspaces) {
    $bak = "$Wspaces.tmp"
    try {
        Copy-Item -LiteralPath $Wspaces -Destination $bak -Force
        Remove-Item -LiteralPath $Wspaces -Force
        Move-Item -LiteralPath $bak -Destination $Wspaces -Force
        Write-Host '[ok] workspaces.json recriado (libera handles presos que causam EPERM no fs.watch)'
    } catch {
        if (Test-Path $bak) { Move-Item -LiteralPath $bak -Destination $Wspaces -Force }
        Write-Host '[aviso] nao foi possivel recriar workspaces.json (arquivo em uso?) - o EPERM pode aparecer'
    }
}

# 1) Copiar o shim
New-Item -ItemType Directory -Path $ProxyDir -Force | Out-Null
Copy-Item (Join-Path $Kit 'nvidia_shim.py') (Join-Path $ProxyDir 'nvidia_shim.py') -Force
Write-Host "[ok] shim copiado: $ProxyDir\nvidia_shim.py"

# 2) Auto-inicio com o Windows
Copy-Item (Join-Path $Kit 'kimi-nvidia-shim.cmd') (Join-Path $Startup 'kimi-nvidia-shim.cmd') -Force
Write-Host "[ok] auto-inicio:   $Startup\kimi-nvidia-shim.cmd"

# 3) config.toml
$Snippet = Get-Content (Join-Path $Kit 'config-snippet.toml') -Raw
if (Test-Path $ConfigPath) {
    $cfg = Get-Content -LiteralPath $ConfigPath -Raw
    if ($cfg -match '(?m)^\s*\[providers\.nvidia\]') {
        if ($cfg -match "base_url\s*=\s*`"http://127\.0\.0\.1:$Port/v1`"") {
            Write-Host '[ok] config.toml ja tem o provider nvidia apontando para o shim'
        } else {
            Write-Host '[aviso] config.toml tem [providers.nvidia], mas o base_url nao aponta para o shim.'
            Write-Host "        Ajuste para:  base_url = `"http://127.0.0.1:$Port/v1`""
        }
    } else {
        Add-Content -LiteralPath $ConfigPath -Value "`r`n$Snippet"
        Write-Host '[ok] bloco nvidia adicionado ao config.toml'
        Write-Host '[!!] EDITE o api_key em config.toml (cole sua chave nvapi-...) e rode: kimi doctor'
    }
} else {
    New-Item -ItemType Directory -Path $KimiHome -Force | Out-Null
    Set-Content -LiteralPath $ConfigPath -Value "default_model = `"nvidia/glm53`"`r`n$Snippet"
    Write-Host '[ok] config.toml criado com o bloco nvidia'
    Write-Host '[!!] EDITE o api_key em config.toml (cole sua chave nvapi-...) e rode: kimi doctor'
}

# 4) Localizar o Python
$Pyw = 'C:\Program Files\Python313\pythonw.exe'
if (-not (Test-Path $Pyw)) {
    $cmd = Get-Command pythonw -ErrorAction SilentlyContinue
    if ($cmd) { $Pyw = $cmd.Source } else { $Pyw = $null }
}
if (-not $Pyw) {
    Write-Host '[erro] pythonw.exe nao encontrado. Instale o Python 3: https://www.python.org/downloads/'
    exit 1
}

# 5) Iniciar o shim se nao estiver rodando
function Test-Shim {
    try {
        $r = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/health" -UseBasicParsing -TimeoutSec 2
        return ($r.StatusCode -eq 200)
    } catch { return $false }
}
if (-not (Test-Shim)) {
    Start-Process -FilePath $Pyw -ArgumentList (Join-Path $ProxyDir 'nvidia_shim.py') -WindowStyle Hidden
    foreach ($i in 1..20) { Start-Sleep -Milliseconds 500; if (Test-Shim) { break } }
}
if (Test-Shim) {
    Write-Host "[ok] shim respondendo em http://127.0.0.1:$Port"
} else {
    Write-Host "[erro] o shim nao respondeu em http://127.0.0.1:$Port - verifique o Python e a porta $Port"
    exit 1
}

Write-Host ''
Write-Host 'Dica: se o Kimi imprimir "EPERM ... watch workspaces.json" ao abrir,'
Write-Host 'trata-se de lock de antivirius (nao e fatal). Para eliminar de vez, rode'
Write-Host 'num PowerShell como Administrador:'
Write-Host '  Add-MpPreference -ExclusionPath "$env:USERPROFILE\.kimi-code"'

Write-Host ''
Write-Host 'Concluido. Teste com:'
Write-Host '  kimi doctor'
Write-Host '  kimi provider list'
Write-Host '  kimi --model nvidia/glm53 -p "Responda somente OK"'
