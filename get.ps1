# get.ps1
# skills-vault universal installer for Windows
# iwr -useb https://raw.githubusercontent.com/z0team/skills-vault/main/get.ps1 | iex

$ErrorActionPreference = "Stop"

$repo = "z0team/skills-vault"
$branch = "main"
$rawUrl = "https://raw.githubusercontent.com/$repo/$branch"
$tarUrl = "https://github.com/$repo/raw/$branch/dist/dist.tar.gz"

Write-Host "🧰 skills-vault — Швидке встановлення скілів" -ForegroundColor Cyan
Write-Host "==============================================="
Write-Host ""

Write-Host "Куди ставимо скіли?"
Write-Host "  1) Глобально (для всіх проєктів у системну папку)"
Write-Host "  2) Локально (в поточну папку $($((Get-Location).Path)))"
$scopeChoice = Read-Host "Вибір [1-2]"

$scope = switch ($scopeChoice) {
    "1" { "global" }
    "2" { "local" }
    default { Write-Error "❌ Невідомий вибір"; exit 1 }
}

Write-Host ""
Write-Host "Для якого агента ставимо скіли?"
Write-Host "  1) claude-code"
Write-Host "  2) cursor"
Write-Host "  3) copilot"
Write-Host "  4) windsurf"
Write-Host "  5) opencode"
Write-Host "  6) codex"
Write-Host "  7) agy"
Write-Host "  8) Всі вище"
$agentChoices = Read-Host "Вибір (через кому, напр. 1,2 або 8)"

$agents = @()
foreach ($c in $agentChoices.Split(',')) {
    switch ($c.Trim()) {
        "1" { $agents += "claude-code" }
        "2" { $agents += "cursor" }
        "3" { $agents += "copilot" }
        "4" { $agents += "windsurf" }
        "5" { $agents += "opencode" }
        "6" { $agents += "codex" }
        "7" { $agents += "agy" }
        "8" { $agents = @("claude-code", "cursor", "copilot", "windsurf", "opencode", "codex", "agy"); break }
    }
}

if ($agents.Count -eq 0) {
    Write-Error "❌ Не обрано жодного агента."
    exit 1
}

Write-Host ""
Write-Host "⏳ Завантаження registry.json..." -ForegroundColor Cyan
$registryStr = Invoke-RestMethod -Uri "$rawUrl/registry.json"
$packIds = $registryStr.packs | Select-Object -ExpandProperty id

Write-Host ""
Write-Host "Доступні паки:"
for ($i = 0; $i -lt $packIds.Count; $i++) {
    Write-Host "  $($i + 1)) $($packIds[$i])"
}
Write-Host "  all) Всі паки"
$packChoices = Read-Host "Які паки ставимо? (через кому, або 'all')"

$selectedPacks = @()
if ($packChoices -eq "all") {
    $selectedPacks = $packIds
} else {
    foreach ($c in $packChoices.Split(',')) {
        $idx = [int]$c.Trim() - 1
        if ($idx -ge 0 -and $idx -lt $packIds.Count) {
            $selectedPacks += $packIds[$idx]
        }
    }
}

if ($selectedPacks.Count -eq 0) {
    Write-Error "❌ Не обрано жодного паку."
    exit 1
}

Write-Host ""
Write-Host "⏳ Завантаження архіву скілів..." -ForegroundColor Cyan
$tempDir = Join-Path $env:TEMP ([guid]::NewGuid().ToString())
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
$tarPath = Join-Path $tempDir "dist.tar.gz"

try {
    Invoke-WebRequest -Uri $tarUrl -OutFile $tarPath
    
    # Use native tar to extract
    Set-Location $tempDir
    tar -xzf $tarPath
    Set-Location $PSScriptRoot

    $hasMcp = $false

    foreach ($agent in $agents) {
        $destDir = ""
        if ($scope -eq "global") {
            if ($agent -eq "cursor") {
                Write-Host "⚠️ Cursor не підтримує глобальні правила. Встановлюємо локально." -ForegroundColor Yellow
                $destDir = (Get-Location).Path
            } elseif ($agent -eq "claude-code") {
                $destDir = $env:USERPROFILE
            } else {
                $destDir = $env:USERPROFILE
            }
        } else {
            $destDir = (Get-Location).Path
        }

        if (-not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Force -Path $destDir | Out-Null
        }

        Write-Host "📦 Копіюємо для $agent у $destDir ..."
        foreach ($pid in $selectedPacks) {
            $srcDir = Join-Path $tempDir "$pid\$agent"
            if (Test-Path $srcDir) {
                Get-ChildItem -Path $srcDir -Force | Copy-Item -Destination $destDir -Recurse -Force
            }

            $packInfo = $registryStr.packs | Where-Object { $_.id -eq $pid }
            if ($packInfo.mcp_servers) {
                $hasMcp = $true
            }
        }
    }

    Write-Host ""
    Write-Host "✅ Успішно встановлено!" -ForegroundColor Green

    if ($hasMcp) {
        Write-Host "⚠️ Увага: Деякі з встановлених паків потребують MCP сервер!" -ForegroundColor Yellow
        Write-Host "   Перевірте документацію паку, щоб додати потрібну команду до конфігурації вашого агента."
    }

} finally {
    if (Test-Path $tempDir) {
        Remove-Item -Path $tempDir -Recurse -Force
    }
}
