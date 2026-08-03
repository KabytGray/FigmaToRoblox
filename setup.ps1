# =============================================================================
# FigmaToRoblox - instalacao em um comando
# =============================================================================
# Faz tudo que antes era manual: instala dependencias, publica o seu Worker na
# Cloudflare, cria o banco KV, guarda a sua API Key do Roblox e instala o plugin
# no Studio.
#
# Rode com:  powershell -ExecutionPolicy Bypass -File setup.ps1
#
# Cada usuario usa a PROPRIA chave e o PROPRIO Worker. Nada passa por servidor
# de terceiros, e a cota da Cloudflare e do Roblox e sua.
#
# Rodar de novo e seguro: o que ja esta feito e detectado e pulado. Nada de
# refazer login, recriar banco ou pedir a chave outra vez.
# =============================================================================

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$voltarPara = (Get-Location).Path
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

# -----------------------------------------------------------------------------
# Roda um programa externo e devolve TUDO que ele imprimiu, como texto.
#
# Existe por causa de um comportamento do PowerShell 5.1 que ja quebrou esta
# instalacao: quando um .exe escreve em stderr, o PowerShell embrulha cada linha
# num ErrorRecord - e com $ErrorActionPreference = "Stop" isso vira erro
# TERMINANTE. Resultado: um aviso inofensivo do wrangler ("sua versao esta
# desatualizada") abortava a instalacao inteira no meio.
#
# Passar por "cmd /c ... 2>&1" junta os dois fluxos ANTES do PowerShell ver,
# entao aviso continua sendo aviso. O codigo de saida real vem em $LASTEXITCODE.
# -----------------------------------------------------------------------------
function Rodar($comando) {
    $saida = & cmd /c "$comando 2>&1"
    return ($saida | Out-String)
}

# -----------------------------------------------------------------------------
# Grava texto em UTF-8 SEM BOM.
#
# "Set-Content -Encoding utf8" no PowerShell 5.1 escreve UTF-8 COM BOM, e o BOM
# quebra quem le o arquivo depois: JSON.parse morre no primeiro caractere (o
# uploader recusava um config.json perfeitamente valido) e o parser de TOML do
# wrangler tambem se perde.
# -----------------------------------------------------------------------------
function GravarTexto($caminho, $texto) {
    [System.IO.File]::WriteAllText($caminho, $texto, (New-Object System.Text.UTF8Encoding($false)))
}

Write-Host ""
Write-Host "  FigmaToRoblox" -ForegroundColor Magenta -NoNewline
Write-Host "  instalacao" -ForegroundColor DarkGray

try {

# --------------------------------------------------------------- 1. Node -----
Titulo "1. Node.js"

$node = Get-Command node -ErrorAction SilentlyContinue

if (-not $node) {
    # Instala sozinho pelo winget, que ja vem no Windows 10/11. Antes daqui a
    # pessoa era mandada para o nodejs.org e tinha que voltar e rodar tudo de
    # novo - o ponto onde a maioria desistia, logo no primeiro passo.
    Info "Node.js nao encontrado - instalando automaticamente"

    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        Rodar "winget install OpenJS.NodeJS.LTS --silent --accept-source-agreements --accept-package-agreements" | Out-Null

        # O winget mexe no PATH do sistema, mas a janela atual ficou com o PATH
        # antigo. Sem reler, o "node" continua sumido mesmo apos instalar.
        $pathMaquina = [Environment]::GetEnvironmentVariable("Path", "Machine")
        $pathUsuario = [Environment]::GetEnvironmentVariable("Path", "User")
        $env:Path = "$pathMaquina;$pathUsuario"
        $node = Get-Command node -ErrorAction SilentlyContinue
    }

    if (-not $node) {
        Erro "nao consegui instalar o Node.js sozinho."
        Write-Host ""
        Write-Host "  Baixe a versao LTS em https://nodejs.org (o instalador padrao serve),"
        Write-Host "  feche esta janela, abra o PowerShell de novo e cole o mesmo comando."
        Write-Host ""
        Start-Process "https://nodejs.org"
        return
    }
    Ok "Node.js instalado"
}

Ok "Node $(Rodar 'node --version' | ForEach-Object { $_.Trim() })"

# ------------------------------------------------------- 2. dependencias -----
Titulo "2. Dependencias"

foreach ($pasta in @("cloudflare-worker", "figma-plugin")) {
    if (Test-Path "$root\$pasta\package.json") {
        if (Test-Path "$root\$pasta\node_modules") {
            Ok "$pasta ja instalado"
        } else {
            Info "instalando em $pasta (pode demorar na primeira vez)"
            Push-Location "$root\$pasta"
            $r = Rodar "npm install --silent"
            Pop-Location
            if ($LASTEXITCODE -ne 0) {
                Erro "npm install falhou em ${pasta}:"
                Write-Host $r
                return
            }
            Ok "$pasta pronto"
        }
    }
}

# ---------------------------------------------------------- 3. Cloudflare ----
Titulo "3. Servidor na Cloudflare"

# Se ja existe um Worker que responde, nao ha o que refazer. E o caminho de quem
# so rodou o comando de novo - que deve terminar em segundos, nao repetir tudo.
$configPath = "$root\config.json"
$workerUrl = $null

if (Test-Path $configPath) {
    try {
        $jaTem = Get-Content $configPath -Raw | ConvertFrom-Json
        if ($jaTem.workerUrl) {
            $ping = try {
                Invoke-RestMethod -Uri ($jaTem.workerUrl.TrimEnd("/") + "/api/health") -TimeoutSec 8
            } catch { $null }
            if ($ping) {
                $workerUrl = $jaTem.workerUrl
                Ok "Worker ja no ar: $workerUrl"
            }
        }
    } catch {}
}

if (-not $workerUrl) {
    Push-Location "$root\cloudflare-worker"
    try {
        if (-not (Test-Path "wrangler.toml") -and (Test-Path "wrangler.example.toml")) {
            Copy-Item "wrangler.example.toml" "wrangler.toml"
            Ok "wrangler.toml criado a partir do template"
        }

        $conta = Rodar "npx wrangler whoami"
        if ($conta -match "not authenticated|You are not") {
            Info "abrindo o login da Cloudflare no navegador"
            Write-Host "  (crie a conta gratuita se ainda nao tiver, e autorize)" -ForegroundColor DarkGray
            & npx wrangler login
        } else {
            Ok "ja autenticado na Cloudflare"
        }

        $toml = Get-Content "wrangler.toml" -Raw
        $idAtual = if ($toml -match 'id\s*=\s*"([a-f0-9]{32})"') { $Matches[1] } else { "" }
        $listaKv = Rodar "npx wrangler kv namespace list"

        if ($idAtual -and $listaKv -match $idAtual) {
            Ok "banco KV existente ($idAtual)"
        } elseif ($listaKv -match '"id":\s*"([a-f0-9]{32})"[^}]*"title":\s*"[^"]*FIGMA_DATA') {
            $reuseId = $Matches[1]
            $toml = $toml -replace 'id\s*=\s*"[a-f0-9]*"', ('id = "' + $reuseId + '"')
            GravarTexto "$PWD\wrangler.toml" $toml
            Ok "banco KV FIGMA_DATA reaproveitado ($reuseId)"
        } else {
            Info "criando o banco KV"
            $saida = Rodar "npx wrangler kv namespace create FIGMA_DATA"
            if ($saida -match '([a-f0-9]{32})') {
                $novoId = $Matches[1]
                $toml = $toml -replace 'id\s*=\s*"[a-f0-9]*"', ('id = "' + $novoId + '"')
                GravarTexto "$PWD\wrangler.toml" $toml
                Ok "banco KV criado ($novoId)"
            } else {
                Erro "nao consegui criar o KV. Saida:"
                Write-Host $saida
                return
            }
        }

        Info "publicando o Worker"
        $deploy = Rodar "npx wrangler deploy"
        if ($deploy -match '(https://[a-z0-9\-\.]+\.workers\.dev)') {
            $workerUrl = $Matches[1]
            Ok "Worker no ar: $workerUrl"
        } else {
            Erro "o deploy nao devolveu uma URL. Saida:"
            Write-Host $deploy
            return
        }
    } finally {
        Pop-Location
    }
}

# ------------------------------------------------------- 3b. token de acesso -
# Passo PROPRIO, fora do bloco que publica o Worker. Ja esteve la dentro, e o
# resultado foi que quem tinha o Worker no ar (o caminho rapido) nunca ganhava
# token: a instalacao dizia "tudo pronto" com o servidor aberto para qualquer
# um. Seguranca nao pode depender do caminho que a instalacao tomou.
Titulo "3b. Token de acesso"

$authToken = ""
if (Test-Path $configPath) {
    try {
        $antigo = Get-Content $configPath -Raw | ConvertFrom-Json
        if ($antigo.authToken) { $authToken = $antigo.authToken }
    } catch {}
}

if ($authToken) {
    Ok "token ja configurado"
} else {
    Info "gerando token e trancando o servidor"
    # 32 bytes aleatorios em hex: forte, e sem caractere que atrapalhe em
    # cabecalho HTTP ou em linha de comando.
    $bytes = New-Object byte[] 32
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $authToken = ($bytes | ForEach-Object { $_.ToString("x2") }) -join ""

    Push-Location "$root\cloudflare-worker"
    try {
        # Pela entrada padrao: o segredo nao entra no historico do terminal nem
        # em nenhum arquivo do projeto.
        $r = $authToken | & cmd /c "npx wrangler secret put AUTH_TOKEN 2>&1"
        if ($LASTEXITCODE -eq 0) {
            Ok "servidor protegido"
        } else {
            Aviso "nao consegui gravar o token - o servidor segue aberto"
            Write-Host ($r | Out-String)
            $authToken = ""
        }
    } finally {
        Pop-Location
    }
}

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
        Erro "chave curta demais, parece invalida. Rode o comando de novo."
        return
    }
    Set-Content $keyPath $chave.Trim() -Encoding ascii -NoNewline
    Ok "apikey.txt salvo"
}

# --------------------------------------------------------- 5. seu userId -----
Titulo "5. Seu ID do Roblox"

$config = @{ workerUrl = $workerUrl; userId = ""; authToken = ""; pollSeconds = 4; concurrency = 3 }

# $authToken so existe quando o bloco da Cloudflare rodou. No caminho rapido
# (Worker ja no ar) ele nem e definido, e o valor tem que vir do config antigo —
# senao a reinstalacao apagaria o token e trancaria o proprio uploader para fora.
if ($authToken) { $config.authToken = $authToken }

if (Test-Path $configPath) {
    try {
        $atual = Get-Content $configPath -Raw | ConvertFrom-Json
        if ($atual.userId) { $config.userId = $atual.userId }
        if ($atual.authToken -and -not $config.authToken) { $config.authToken = $atual.authToken }
    } catch {}
}

if ($config.userId) {
    Ok "userId $($config.userId) ja salvo"
} else {
    Write-Host "  As imagens sobem para a sua conta, entao preciso do seu ID." -ForegroundColor Gray
    Write-Host "  Pode colar o link do seu perfil inteiro que eu extraio." -ForegroundColor DarkGray
    Write-Host ""

    # Aceita o link inteiro alem do numero: colar a URL do perfil e o que a
    # pessoa faz naturalmente, e exigir "so o numero" so gera erro de digitacao.
    do {
        $resposta = (Read-Host "  Seu perfil ou ID").Trim()
        if ($resposta -match '(\d{4,})') {
            $config.userId = $Matches[1]
        } else {
            Aviso "nao achei um ID ai. Exemplo: roblox.com/users/4024894937/profile"
        }
    } while (-not $config.userId)
}

GravarTexto $configPath ($config | ConvertTo-Json)
Ok "config.json salvo"

# ------------------------------------------------------- 6. plugin Studio ----
Titulo "6. Plugins"

Push-Location "$root\roblox-plugin"
$saidaPlugin = Rodar "node build.js --install"
Pop-Location
if ($saidaPlugin -match "instalado") {
    Ok "plugin do Studio instalado"
} else {
    Aviso "o plugin do Studio pode nao ter sido instalado. Saida:"
    Write-Host $saidaPlugin
}

Push-Location "$root\figma-plugin"
$saidaFigma = Rodar "npm run build"
Pop-Location
Ok "plugin do Figma compilado"

# --------------------------------------------------------- 7. atalho ---------
# O uploader precisa estar rodando enquanto a pessoa trabalha. Pedir para ela
# decorar um caminho e digitar um comando toda vez e onde a maioria desiste -
# um atalho na area de trabalho resolve com dois cliques, para sempre.
Titulo "7. Atalho do uploader"

try {
    $desktop = [Environment]::GetFolderPath("Desktop")
    $atalho = Join-Path $desktop "FigmaToRoblox uploader.lnk"
    $shell = New-Object -ComObject WScript.Shell
    $lnk = $shell.CreateShortcut($atalho)
    $lnk.TargetPath = "$root\start-uploader.bat"
    $lnk.WorkingDirectory = $root
    $lnk.Description = "Sobe as imagens do Figma para o Roblox. Deixe aberto enquanto trabalha."
    $lnk.Save()
    Ok "atalho criado na area de trabalho"
} catch {
    Aviso "nao consegui criar o atalho (siga por start-uploader.bat na pasta)"
}

# ------------------------------------------------------------------ fim ------
Write-Host ""
Write-Host "  Tudo pronto." -ForegroundColor Green
Write-Host ""
Write-Host "  A sua URL (ja salva, nao precisa guardar):" -ForegroundColor White
Write-Host ""
Write-Host "      $workerUrl" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Falta so isto:" -ForegroundColor White
Write-Host ""
Write-Host "   1. Deixe o uploader aberto (ele se abre no fim daqui)"
Write-Host "   2. Reinicie o Roblox Studio - o plugin acha o servidor sozinho"
Write-Host "   3. No Figma: instale o plugin FigmaToRoblox pela pagina da"
Write-Host "      comunidade. Ele tambem se configura sozinho."
Write-Host ""
Write-Host "  Nao precisa colar a URL em lugar nenhum: o uploader entrega" -ForegroundColor DarkGray
Write-Host "  o endereco e o token aos dois plugins." -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Daqui para frente, para usar o plugin basta abrir o atalho" -ForegroundColor DarkGray
Write-Host "  'FigmaToRoblox uploader' na area de trabalho. Nao precisa" -ForegroundColor DarkGray
Write-Host "  instalar de novo." -ForegroundColor DarkGray
Write-Host ""

$abrir = Read-Host "  Abrir o uploader agora? (S/n)"
if ($abrir -ne "n") {
    Start-Process "cmd.exe" -ArgumentList "/c", "`"$root\start-uploader.bat`""
    Ok "uploader aberto numa janela nova - deixe minimizado"
}

Write-Host ""
Write-Host "  FigmaToRoblox e gratuito, feito por KabytGray." -ForegroundColor DarkGray
Write-Host "  Se ele te ajudar, uma avaliacao no perfil ajuda outras pessoas a acharem." -ForegroundColor DarkGray
Write-Host ""

} finally {
    # Sem isto, um erro no meio larga a pessoa dentro de cloudflare-worker - foi
    # exatamente o que aconteceu quando o wrangler abortou a instalacao.
    Set-Location $voltarPara
}
