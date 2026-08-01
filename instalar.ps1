# =============================================================================
# FigmaToRoblox - instalacao em UM comando
# =============================================================================
# Este arquivo existe para ser executado direto da internet, sem baixar nada
# antes:
#
#   irm https://raw.githubusercontent.com/KabytGray/FigmaToRoblox/main/instalar.ps1 | iex
#
# Ele baixa o projeto, extrai numa pasta e chama o setup.ps1, que faz o resto.
#
# Por que um bootstrap separado do setup.ps1: o setup precisa dos arquivos do
# projeto ao lado dele (worker, uploader, plugins). Este aqui nao precisa de
# nada - e por isso pode rodar colado no PowerShell, que e o que a pessoa
# tenta fazer naturalmente.
# =============================================================================

$ErrorActionPreference = "Stop"

$RepoZip = "https://github.com/KabytGray/FigmaToRoblox/archive/refs/heads/main.zip"
$Destino = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "FigmaToRoblox"

function Titulo($t) {
    Write-Host ""
    Write-Host "  $t" -ForegroundColor Magenta
    Write-Host ("  " + ("-" * $t.Length)) -ForegroundColor DarkGray
}
function Ok($t)    { Write-Host "  [ok]   $t" -ForegroundColor Green }
function Info($t)  { Write-Host "  ...    $t" -ForegroundColor Gray }
function Erro($t)  { Write-Host "  [erro] $t" -ForegroundColor Red }

Write-Host ""
Write-Host "  FigmaToRoblox" -ForegroundColor Magenta -NoNewline
Write-Host "  instalacao automatica" -ForegroundColor DarkGray

# ------------------------------------------------------------ 1. baixar ------
Titulo "1. Baixando o projeto"

# TLS 1.2 explicito: o Windows 10 mais antigo ainda negocia TLS 1.0 por padrao,
# e o GitHub recusa. Sem isto o download falha com um erro que nao explica nada.
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch {}

$zipTemp = Join-Path $env:TEMP "FigmaToRoblox-$(Get-Random).zip"

try {
    Info "de github.com/KabytGray/FigmaToRoblox"
    # ProgressPreference desligado: a barra de progresso do Invoke-WebRequest
    # deixa o download ate 10x mais lento no PowerShell 5.1.
    $prog = $ProgressPreference
    $ProgressPreference = "SilentlyContinue"
    Invoke-WebRequest -Uri $RepoZip -OutFile $zipTemp -UseBasicParsing
    $ProgressPreference = $prog
    $mb = [math]::Round((Get-Item $zipTemp).Length / 1MB, 1)
    Ok "baixado ($mb MB)"
} catch {
    Erro "nao consegui baixar."
    Write-Host ""
    Write-Host "  Verifique a internet e tente de novo. Se persistir, baixe manualmente:"
    Write-Host "  https://github.com/KabytGray/FigmaToRoblox" -ForegroundColor Cyan
    Write-Host ""
    return
}

# ------------------------------------------------------------ 2. extrair -----
Titulo "2. Extraindo"

# Se ja existe, o conteudo e substituido mas nada fora do projeto e tocado.
# apikey.txt e config.json sao preservados: sao os unicos arquivos que a pessoa
# nao quer perder numa atualizacao.
$guardados = @{}
foreach ($nome in @("apikey.txt", "config.json")) {
    $caminho = Join-Path $Destino $nome
    if (Test-Path $caminho) {
        $guardados[$nome] = Get-Content $caminho -Raw
        Info "preservando $nome"
    }
}

$extraiEm = Join-Path $env:TEMP "FigmaToRoblox-extract-$(Get-Random)"

try {
    Expand-Archive -Path $zipTemp -DestinationPath $extraiEm -Force

    # O ZIP do GitHub embrulha tudo numa pasta "FigmaToRoblox-main".
    $interna = Get-ChildItem $extraiEm -Directory | Select-Object -First 1
    if (-not $interna) { throw "ZIP em formato inesperado" }

    if (-not (Test-Path $Destino)) {
        New-Item -ItemType Directory -Path $Destino -Force | Out-Null
    }
    Copy-Item -Path (Join-Path $interna.FullName "*") -Destination $Destino -Recurse -Force

    foreach ($nome in $guardados.Keys) {
        Set-Content -Path (Join-Path $Destino $nome) -Value $guardados[$nome] -Encoding utf8 -NoNewline
    }

    Ok "em $Destino"
} catch {
    Erro "falha ao extrair: $($_.Exception.Message)"
    return
} finally {
    Remove-Item $zipTemp -Force -ErrorAction SilentlyContinue
    Remove-Item $extraiEm -Recurse -Force -ErrorAction SilentlyContinue
}

# ------------------------------------------------------------ 3. instalar ----
$setup = Join-Path $Destino "setup.ps1"
if (-not (Test-Path $setup)) {
    Erro "setup.ps1 nao veio no pacote."
    return
}

Write-Host ""
Info "iniciando a instalacao..."
Set-Location $Destino
& $setup
