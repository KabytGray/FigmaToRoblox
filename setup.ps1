# =============================================================================
# FigmaToRoblox — instalacao em um comando
# =============================================================================
# Faz tudo que antes era manual: instala dependencias, publica o seu Worker na
# Cloudflare, cria o banco KV, guarda a sua API Key do Roblox e instala o plugin
# no Studio.
#
# Rode com:  powershell -ExecutionPolicy Bypass -File setup.ps1
#
# Cada usuario usa a PROPRIA chave e o PROPRIO Worker. Nada passa por servidor
# de terceiros, e a cota da Cloudflare e do Roblox e sua.
# =============================================================================

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

function Titulo($texto) {
    Write-Host ""
    Write-Host "  $texto" -ForegroundColor Magenta
    Write-Host ("  " + ("-" * $texto.Length)) -ForegroundColor DarkGray
}
function Ok($texto)   { Write-Host "  [ok]   $texto" -ForegroundColor Green }
function Info($texto) { Write-Host "  ...    $texto" -ForegroundColor Gray }
function Aviso($texto){ Write-Host "  [!]    $texto" -ForegroundColor Yellow }
function Erro($texto) { Write-Host "  [erro] $texto" -ForegroundColor Red }

Write-Host ""
Write-Host "  FigmaToRoblox" -ForegroundColor Magenta -NoNewline
Write-Host "  instalacao" -ForegroundColor DarkGray

# --------------------------------------------------------------- 1. Node -----
Titulo "1. Node.js"

$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) {
    Erro "Node.js nao encontrado."
    Write-Host ""
    Write-Host "  Baixe a versao LTS em https://nodejs.org e rode este script de novo."
    Write-Host "  (o instalador padrao serve; nao precisa mudar nada)"
    Write-Host ""
    Start-Process "https://nodejs.org"
    exit 1
}

$versao = (& node --version)
Ok "Node $versao"

# ------------------------------------------------------- 2. dependencias -----
Titulo "2. Dependencias"

foreach ($pasta in @("cloudflare-worker", "figma-plugin")) {
    if (Test-Path "$root\$pasta\package.json") {
        Info "instalando em $pasta (pode demorar na primeira vez)"
        Push-Location "$root\$pasta"
        & npm install --silent 2>&1 | Out-Null
        Pop-Location
        Ok "$pasta pronto"
    }
}

# ---------------------------------------------------------- 3. Cloudflare ----
Titulo "3. Servidor na Cloudflare"

Push-Location "$root\cloudflare-worker"

# Primeiro uso: copia o template. wrangler.toml e gitignorado porque cada
# usuario preenche o proprio id de KV.
if (-not (Test-Path "wrangler.toml") -and (Test-Path "wrangler.example.toml")) {
    Copy-Item "wrangler.example.toml" "wrangler.toml"
    Ok "wrangler.toml criado a partir do template"
}

# A conta e gratuita e o login abre no navegador.
$conta = & npx wrangler whoami 2>&1 | Out-String
if ($conta -match "not authenticated|You are not") {
    Info "abrindo o login da Cloudflare no navegador"
    Write-Host "  (crie a conta gratuita se ainda nao tiver, e autorize)" -ForegroundColor DarkGray
    & npx wrangler login
} else {
    Ok "ja autenticado na Cloudflare"
}

# O KV guarda os exports. Se wrangler.toml ainda tem o id de exemplo, cria um
# banco novo e grava o id — e o passo que mais gerava erro quando era manual.
$toml = Get-Content "wrangler.toml" -Raw

# Reaproveita o KV existente da conta se ja houver — evita encher a Cloudflare
# de bancos ao reinstalar. Cria um novo so na primeira vez.
$idAtual = if ($toml -match 'id\s*=\s*"([a-f0-9]{32})"') { $Matches[1] } else { "" }
$listaKv = & npx wrangler kv namespace list 2>&1 | Out-String
$precisaKv = -not ($idAtual -and $listaKv -match $idAtual)

if (-not $precisaKv) {
    Ok "banco KV existente ($idAtual)"
} elseif ($listaKv -match '"id":\s*"([a-f0-9]{32})"[^}]*"title":\s*"[^"]*FIGMA_DATA') {
    # Ja existe um KV com o nome certo em outra pasta/reinstalacao — reusa.
    $reuseId = $Matches[1]
    $toml = $toml -replace 'id\s*=\s*""', ('id = "' + $reuseId + '"')
    Set-Content "wrangler.toml" $toml -Encoding utf8
    Ok "banco KV FIGMA_DATA reaproveitado ($reuseId)"
} else {
    Info "criando o banco KV"
    $saida = & npx wrangler kv namespace create FIGMA_DATA 2>&1 | Out-String
    if ($saida -match '([a-f0-9]{32})') {
        $novoId = $Matches[1]
        # Aceita tanto o id vazio quanto um id antigo, para funcionar em quem
        # baixou do repo (vazio) e em quem ja tinha (velho).
        $toml = $toml -replace 'id\s*=\s*"[a-f0-9]*"', ('id = "' + $novoId + '"')
        Set-Content "wrangler.toml" $toml -Encoding utf8
        Ok "banco KV criado ($novoId)"
    } else {
        Erro "nao consegui criar o KV. Saida:"
        Write-Host $saida
        Pop-Location
        exit 1
    }
}

Info "publicando o Worker"
$deploy = & npx wrangler deploy 2>&1 | Out-String
$workerUrl = $null
if ($deploy -match '(https://[a-z0-9\-\.]+\.workers\.dev)') { $workerUrl = $Matches[1] }

if ($workerUrl) {
    Ok "Worker no ar: $workerUrl"
} else {
    Erro "o deploy nao devolveu uma URL. Saida:"
    Write-Host $deploy
    Pop-Location
    exit 1
}
Pop-Location

# ------------------------------------------------------------- 4. API Key ----
Titulo "4. Chave do Roblox"

$keyPath = "$root\apikey.txt"
$temChave = (Test-Path $keyPath) -and ((Get-Content $keyPath -Raw).Trim().Length -gt 20)

if ($temChave) {
    Ok "apikey.txt ja existe"
} else {
    Write-Host "  Preciso de uma API Key do Roblox para subir as imagens." -ForegroundColor Gray
    Write-Host "  Vou abrir a pagina. Crie uma chave com estes escopos:" -ForegroundColor Gray
    Write-Host ""
    Write-Host "     Assets  ->  Read  +  Write" -ForegroundColor White
    Write-Host ""
    Write-Host "  Em 'Security', aceite qualquer IP (0.0.0.0/0) para uso local." -ForegroundColor DarkGray
    Write-Host ""
    Start-Process "https://create.roblox.com/dashboard/credentials"
    Read-Host "  Pressione Enter quando a pagina abrir"

    $chave = Read-Host "  Cole a chave aqui"
    if ($chave.Trim().Length -lt 20) {
        Erro "chave curta demais, parece invalida. Rode o script de novo."
        exit 1
    }
    Set-Content $keyPath $chave.Trim() -Encoding ascii -NoNewline
    Ok "apikey.txt salvo"
}

# --------------------------------------------------------- 5. seu userId -----
Titulo "5. Seu ID do Roblox"

$configPath = "$root\config.json"
$config = @{ workerUrl = $workerUrl; userId = ""; pollSeconds = 4; concurrency = 3 }

if (Test-Path $configPath) {
    $atual = Get-Content $configPath -Raw | ConvertFrom-Json
    if ($atual.userId) { $config.userId = $atual.userId }
}

if (-not $config.userId) {
    Write-Host "  As imagens sobem para a sua conta, entao preciso do seu userId." -ForegroundColor Gray
    Write-Host "  Esta no link do seu perfil: roblox.com/users/" -NoNewline -ForegroundColor DarkGray
    Write-Host "SEUID" -NoNewline -ForegroundColor White
    Write-Host "/profile" -ForegroundColor DarkGray
    $config.userId = (Read-Host "  Seu userId").Trim()
}

$config | ConvertTo-Json | Set-Content $configPath -Encoding utf8
Ok "config.json salvo"

# ------------------------------------------------------- 6. plugin Studio ----
Titulo "6. Plugin do Roblox Studio"

Push-Location "$root\roblox-plugin"
& node build.js --install 2>&1 | Select-String "instalado" | ForEach-Object { Ok $_.ToString().Trim() }
Pop-Location

# --------------------------------------------------------- 7. plugin Figma ---
Titulo "7. Plugin do Figma"

Push-Location "$root\figma-plugin"
& npm run build 2>&1 | Out-Null
Pop-Location
Ok "compilado em figma-plugin\dist"

# ------------------------------------------------------------------ fim ------
Write-Host ""
Write-Host "  Tudo pronto." -ForegroundColor Green
Write-Host ""
Write-Host "  Falta so isto:" -ForegroundColor White
Write-Host ""
Write-Host "   1. Reinicie o Roblox Studio (o plugin aparece na barra de plugins)"
Write-Host "   2. No Figma: Plugins > Development > Import plugin from manifest"
Write-Host "      escolha:  $root\figma-plugin\manifest.json"
Write-Host "   3. Cole esta URL na aba Config dos dois plugins:"
Write-Host ""
Write-Host "      $workerUrl" -ForegroundColor Cyan
Write-Host ""
Write-Host "   4. Deixe o uploader aberto enquanto trabalha:"
Write-Host ""
Write-Host "      start-uploader.bat" -ForegroundColor Cyan
Write-Host ""

$abrir = Read-Host "  Abrir o uploader agora? (s/n)"
if ($abrir -eq "s") {
    Start-Process "cmd.exe" -ArgumentList "/c", "`"$root\start-uploader.bat`""
    Ok "uploader aberto numa janela nova"
}

Write-Host ""
Write-Host "  FigmaToRoblox e gratuito, feito por KabytGray." -ForegroundColor DarkGray
Write-Host "  Se ele te ajudar, uma avaliacao no perfil ajuda outras pessoas a acharem." -ForegroundColor DarkGray
Write-Host ""
