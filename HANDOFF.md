# FigmaToRoblox — v2

Importa interfaces desenhadas no Figma direto para o Roblox Studio.
Com a sincronização automática ligada, exportar no Figma faz a UI aparecer
no Studio sozinha — sem copiar ID, sem colar nada.

---

## 0. Instalação

**Quem for usar o plugin roda um arquivo só:**

```
INSTALAR.bat
```

Ele instala as dependências, faz login na Cloudflare, cria o banco KV, publica o
Worker, pede a API Key do Roblox, grava `apikey.txt` e `config.json`, compila e
instala os dois plugins. No fim mostra a URL do Worker para colar no painel.

**Cada usuário usa a própria chave e o próprio Worker.** Nada passa por servidor
de terceiros — a cota da Cloudflare e do Roblox é de quem instalou, e o autor
não responde pela moderação do que os outros sobem.

> Por que não existe um modo "sem chave": subir imagem para o Roblox exige a
> Open Cloud, e não há API para recuperar os IDs depois de um bulk import pelo
> Asset Manager — é pedido antigo no DevForum e continua sem resposta. Sem
> chave, o usuário teria que copiar cada ID à mão.

O plugin do Studio tem um **checklist na aba Config** que se verifica sozinho:
detecta se o servidor responde, se a URL está preenchida e se a fila de upload
está parada, e mostra só o que ainda falta.

---

## 1. Arquitetura

```
FIGMA                      CLOUDFLARE                LOCAL                 ROBLOX STUDIO
plugin ──── JSON v2 ────►  Worker (KV)  ◄──────────  uploader.js           plugin
                              │                      (Open Cloud)             │
                              └──────── /api/export/:id ──────────────────────┘
```

**A tradução Figma → Roblox acontece toda no plugin do Figma.** O Worker é um
armazém: guarda a árvore como recebeu, resolve IDs de imagem e serve. Essa foi
a mudança estrutural do v2 — na v1 o Worker reescrevia os nós num formato que o
plugin do Roblox não lia, e por isso **cores de fundo e textos nunca apareciam**.

### Por que o uploader local existe

Nem o Cloudflare Workers nem o sandbox do Figma conseguem montar o
`multipart/form-data` binário que a Open Cloud exige (dá 400). Node consegue.
É a única peça que precisa rodar na máquina.

---

## 2. Schema v2

Um nó, exatamente como sai do Figma e entra no Roblox:

```jsonc
{
  "cls": "Frame",              // Frame | TextLabel | TextButton | ImageLabel | ImageButton | ScrollingFrame
  "name": "Painel",
  "x": 0, "y": 0, "w": 400, "h": 300,
  "z": 1,                      // vira ZIndex (dobrado; o ímpar fica para a sombra)
  "rot": -15,                  // opcional, já invertido para a convenção do Roblox
  "anchor": [0.5, 0.5],        // só em nós rotacionados
  "visible": true,
  "clip": true,                // ClipsDescendants

  "bg":       { "c": [30,30,40], "t": 0 },              // t = transparência Roblox (0 = opaco)
  "gradient": { "stops": [...], "alpha": [...], "rot": 90 },
  "stroke":   { "c": [124,92,252], "th": 2, "t": 0 },
  "corner":   12,                                        // -1 = círculo (ELLIPSE)
  "shadow":   { "c": [0,0,0], "ox": 0, "oy": 4, "blur": 12, "spread": 0, "t": 0.7 },
  "text":     { "content": "JOGAR", "size": 24, "color": [255,255,255],
                "font": "BuilderSansBold", "alignX": "Left", "alignY": "Center",
                "wrapped": false, "lineHeight": 1.2, "autoSize": "Y" },
  "image":    { "key": "iab12cd34", "scale": "Stretch", "t": 0,
                "id": "rbxassetid://123" },              // `id` é preenchido pelo Worker
  "layout":   { "dir": "Vertical", "gap": 8,
                "pad": {"t":16,"r":16,"b":16,"l":16},
                "alignX": "Center", "alignY": "Top" },

  "kids": [ /* recursivo, já na ordem de trás para frente */ ]
}
```

**Cores em 0-255** (direto para `Color3.fromRGB`). **Transparência na convenção
do Roblox** (0 = opaco), nunca alpha do Figma. Essa normalização é o que
elimina a classe de bugs da v1.

### Decisões que valem lembrar

| Assunto | Como é resolvido |
|---|---|
| Posição | `absoluteTransform`, nunca `node.x`/`node.y` — filhos de GROUP têm x/y relativo ao pai do grupo, não ao grupo |
| Rotação | Figma gira anti-horário e em torno do centro; Roblox gira horário em torno do AnchorPoint. Nós rotacionados usam AnchorPoint (0.5, 0.5) + centro |
| Ordem das camadas | `children[0]` no Figma é o mais ao fundo → ZIndex crescente. A gambiarra de ordem reversa da v1 não existe mais |
| Gradiente | Rotação derivada do `gradientTransform` (a direção é a inversa aplicada a (1,0) → `atan2(-d, e)`) |
| Dedup de imagem | Hash FNV-1a do PNG. O Worker mantém `img:<hash> → assetId` global: a mesma imagem nunca sobe duas vezes, nem entre exports diferentes |
| Sombra | Tenta `UIShadow` (beta). Se a classe não existir, cai para 3 frames sobrepostos |

---

## 3. Uso diário

### O painel do Studio

Quatro abas, porque um scroll único com os Pré-Scripts passava de mil pixels:

| Aba | Conteúdo |
|---|---|
| **Importar** | ID, botão importar, sync automático, escala responsiva, status |
| **Pré-Scripts** | os 17 sistemas + os parâmetros de quem estiver marcado |
| **Exports** | lista dos últimos exports do servidor |
| **Config** | URL do Worker, comando do uploader, sobre |

Os parâmetros aparecem só quando o sistema que os usa está marcado. Nenhum
marcado, a seção diz isso em vez de ficar vazia.

### Modo automático (recomendado)

1. `start-uploader.bat` (deixe a janela aberta)
2. No Studio: painel **FigmaToRoblox** → ligar **Sincronização automática**
3. No Figma: selecionar o frame → **Exportar para Roblox**

A UI aparece no Studio em ~3 s. Cada export substitui o anterior, em vez de
empilhar ScreenGuis.

### Modo manual

Exportar no Figma → copiar o ID → colar no painel do Studio → **Importar**.
Se houver algo selecionado no Explorer, a UI entra ali dentro; senão, cria um
`ScreenGui` novo em `StarterGui`.

### Marcações nas camadas (Figma)

| Tag | Efeito |
|---|---|
| `[IMG]` | Força virar PNG |
| `[NATIVE]` | Nunca vira PNG |
| `[BTN]` | Vira `TextButton` / `ImageButton` |
| `[SCROLL]` | Vira `ScrollingFrame` com `AutomaticCanvasSize` |
| `[SLICE]` | PNG que estica sem deformar cantos (9-slice) |
| `[FRONT]` | Sobe ao topo dos irmãos (ZIndex 999) |
| `[BACK]` | Vai para o fundo (ZIndex 0) |

A UI marca quais tags já estão nas camadas selecionadas, então dá para conferir
sem abrir o painel de layers.

### Escala responsiva (opcional, no plugin do Studio)

O import sai em pixels absolutos — uma loja desenhada em 1420px estoura num
celular. Ligando **Escala responsiva**, o import ganha um `UIScale` no container
mais um `LocalScript` que acompanha o `ViewportSize`. É opt-in porque injetar
script no projeto de alguém deve ser escolha, não efeito colateral.

---

## 3.5. Pré-Scripts

Marque sistemas no painel do Studio e a importação gera, além da UI, o código
que a faz funcionar. É o que nenhum concorrente (pago ou grátis) faz.

### Como o vínculo acontece

O plugin **não** faz cirurgia em string de código. Ele gera apenas um
`Config.lua` com dados; todo o resto são módulos estáticos.

```
ReplicatedStorage/FigmaUI/
  Boot        ← estático: lê o Config e liga os sistemas
  Config      ← GERADO: caminhos + opções (regenerado a cada import)
  core/       Signal, Motion
  components/ Bar, ButtonFx, Confirm, Draggable, Hotbar, Notify,
              Scroll, Selection, SettingsPanel, Slider, SlotGrid,
              Tabs, Toggle, Tooltip, Window

ScreenGui/
  UIController  ← seu ponto de entrada (nunca sobrescrito)
```

17 módulos, ~75 KB de Lua. Composição em vez de duplicação: `Hotbar` é
`SlotGrid` + teclas; `Confirm.alert` é a mesma janela com o "não" escondido;
`SettingsPanel` detecta `Toggle` e `Slider` pela estrutura das linhas.

Os caminhos são **detectados pelos nomes das camadas**, com pontuação por
prefixo/substring e desempate pelo mais raso — um `Fill` dentro de `BarraVida`
vence um `Fill` perdido em outro canto. Palavras em inglês e português, porque
designer nomeia camada no idioma que quiser.

### Vínculos: quando o nome não ajuda

A aba **Pré-Scripts** tem uma lista mostrando cada alvo e o que foi encontrado:

```
Barra de vida — preenchimento   HUD.Vida.Fill          [ apontar ]
Loja — painel                   nao encontrado         [ apontar ]
Inventario — modelo de slot     apontado: Bag.Slot     [ limpar  ]
```

Onde faltar, seleciona-se o elemento no Explorer e clica em **apontar**. O
vínculo manual **tem prioridade** sobre a adivinhação e persiste em plugin
settings — reimportar não o perde. Ninguém precisa abrir arquivo de código.

A raiz dos caminhos é sempre a **ScreenGui**, porque é o que o `UIController`
passa para `Boot.start`. Detectar a partir do Frame interno geraria caminhos
deslocados um nível e nada resolveria em tempo de jogo.

### O que é preservado ao reimportar

| Arquivo | Reimportar |
|---|---|
| `Config` | regenerado |
| `Boot`, `core/`, `components/` | só criados se faltarem — ajuste manual sobrevive |
| `UIController` | nunca tocado |

### Editar os módulos

Os templates vivem em `roblox-plugin/templates/*.lua` como Lua de verdade —
com syntax highlight e diff legível. `build.js` os embute no plugin. Nunca edite
as strings dentro do plugin gerado.

---

## 4. Comandos

```bash
# compilar o plugin do Figma (depois: reabrir o plugin no Figma)
cd figma-plugin && npm run build

# publicar o Worker
cd cloudflare-worker && npx wrangler deploy

# uploader em loop
node uploader.js

# uploader: processa a fila e sai
node uploader.js --once

# diagnóstico geral
node diagnose.js

# inspecionar um export
node diagnose.js <exportId>

# compilar o plugin do Studio (embute os templates dos Pré-Scripts)
cd roblox-plugin && node build.js

# compilar e instalar de uma vez
cd roblox-plugin && node build.js --install
```

**Atenção:** `roblox-plugin/FigmaToRoblox.lua` é o **fonte**. O que se instala é
`roblox-plugin/dist/FigmaToRoblox.lua`, gerado pelo build. Copiar o fonte direto
para a pasta de plugins instala uma versão sem os templates.

---

## 5. Configuração

| Item | Valor |
|---|---|
| Worker | `https://figma-to-roblox-worker.kabytgray.workers.dev` |
| Autor | `KabytGray` — user ID `4024894937` |
| API Key | `apikey.txt` (escopos `asset:read` + `asset:write`) |
| KV binding | `FIGMA_DATA` — `<gerado pelo INSTALAR.bat>` |

**Links dos ícones do rodapé/cabeçalho** ficam num lugar só em cada plugin:
`YOUTUBE_URL` / `PROFILE_URL` / `REVIEW_URL` no topo do `FigmaToRoblox.lua`, e
as mesmas constantes no início do `<script>` de `src/ui.html`. O YouTube está
apontando para uma busca até existir a URL do vídeo.

O avatar do autor é embutido como data URI: `assets/avatar.b64` é injetado em
`dist/ui.html` por `build.js`. Assim não depende de rede nem do CSP do Figma. No
Studio ele vem de `Players:GetUserThumbnailAsync`, cacheado em plugin settings.

`config.json` (opcional, ao lado do `uploader.js`) sobrescreve os padrões:

```json
{ "workerUrl": "...", "userId": "...", "authToken": "", "pollSeconds": 4, "concurrency": 3 }
```

Para proteger o Worker: `npx wrangler secret put AUTH_TOKEN`. Com o segredo
definido, `/api/upload` e `/api/resolve-images` passam a exigir
`Authorization: Bearer <token>` — preencha o mesmo token no plugin do Figma e
no `config.json`.

**No Studio, HTTP precisa estar ligado:** Game Settings → Security → Allow HTTP Requests.

---

## 6. Endpoints

| Rota | Uso |
|---|---|
| `POST /api/upload` | Figma envia a árvore v2 |
| `GET /api/export/:id` | Roblox busca a árvore com os `rbxassetid` embutidos |
| `GET /api/latest` | Sincronização automática |
| `GET /api/status/:id` | Já subiu tudo? |
| `GET /api/exports` | Lista os últimos 50 |
| `GET /api/pending` | Fila do uploader |
| `POST /api/resolve-images` | Uploader devolve os IDs |
| `GET /api/health` | Versão do schema + se há auth |

---

## 7. Estado atual

**Funciona:** posição/tamanho, rotação, cor sólida, gradiente (com rotação),
borda, cantos, texto completo (fonte/peso/cor/alinhamento/quebra/entrelinha),
**RichText** (negrito/itálico/cor/tamanho por trecho), Auto Layout →
`UIListLayout` + `UIPadding`, **Auto Layout com wrap → `UIGridLayout`**,
**constraints → `AnchorPoint`/Scale** (opt-in), **`CanvasGroup`** para opacidade
de grupo, **9-slice**, imagens com dedup, ordem de camadas, sombra,
`ClipsDescendants`, sincronização automática, Ctrl+Z.

### Constraints (opt-in)

Ligue **Usar constraints do Figma** no plugin do Figma. Cada eixo converte
independente:

| Figma | Roblox |
|---|---|
| `MIN` | posição fixa a partir do início |
| `MAX` | `Position` com scale 1 e offset negativo — fica preso na borda oposta |
| `CENTER` | `AnchorPoint` 0.5 + posição relativa ao centro |
| `STRETCH` | `Size` com scale 1 menos as duas margens |
| `SCALE` | posição e tamanho em fração |

É opt-in porque ligar por padrão mudaria o posicionamento de qualquer UI já
importada.

**Não implementado:** 9-slice (`ScaleType.Slice` + `SliceCenter`) para painéis
que precisam esticar sem deformar os cantos — próximo item mais valioso para UI
de loja; constraints do Figma → `UIAspectRatioConstraint`; componentes/variantes
do Figma como estados de botão; blur de fundo; blend modes; per-corner radius (o
`UICorner` do Roblox só aceita raio uniforme — usamos o maior); exportação
`.rbxmx` offline; e as ferramentas de edição que os plugins pagos vendem (nudge,
conversor de classe, gerenciador de constraints, scale↔offset).

**Persistência das configurações:** `SettingsPanel` mantém valores em memória e
expõe `GetAll`/`LoadAll`. Um script de cliente não persiste sozinho — quem usa
manda para o servidor via RemoteEvent. Está documentado no `UIController`.

**Aviso:** exports gerados pela v1 não abrem na v2 (chaves de KV e schema
diferentes). É só re-exportar do Figma.

---

## 8. Regras que continuam valendo

1. Uma variável por vez ao depurar.
2. Reproduzir antes de corrigir — `diagnose.js` existe para isso.
3. Em Lua **0 é truthy**. Nunca `if props.X then` quando X pode ser 0.
   O builder atribui transparência direto, sem checar verdade.
4. A Open Cloud responde 200 com a operação em andamento. Só `done` significa
   que o asset existe — o uploader faz polling com backoff.
5. `BackgroundTransparency = 1` em `ImageLabel`, sempre.
