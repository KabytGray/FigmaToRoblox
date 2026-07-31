# Análise dos concorrentes — Figma → Roblox

Levantamento feito em 29/07/2026 a partir de páginas oficiais, documentação e
discussões no DevForum. Nenhum código foi copiado; o que está aqui é análise de
funcionalidade e fluxo de trabalho.

Fontes: [FigBloxUI](https://figbloxui.dev/) · [FigBloxUI docs](https://figbloxui.dev/getting-started/) ·
[RoImport](https://roimport.com/) · [Bloxporter](https://www.figma.com/community/plugin/1468127003367516309/bloxporter-one-click-figma-to-roblox-importer) ·
[Quick Roblox UI Exporter](https://www.figma.com/community/plugin/1483467927580162767/quick-roblox-ui-exporter-by-solys) ·
[FigXporter](https://www.figma.com/community/plugin/1649141134308228780/figxporter-figma-to-roblox-free) ·
[Studio+](https://windspace.gumroad.com/l/studioplus) · [UI Suite](https://devforum.roblox.com/t/plugin-ui-suite-the-ultimate-ui-toolkit/3393413) ·
[GUI Editor+](https://devforum.roblox.com/t/plugin-gui-editor-the-most-advanced-ui-editor-plugin-yet/3624670)

---

## 1. Panorama

O mercado se divide em três categorias que quase não se sobrepõem:

| Categoria | Quem | O que vende |
|---|---|---|
| **Importadores** | FigBloxUI, RoImport, Bloxporter, FigXporter, Quick Exporter | fidelidade visual do Figma para o Studio |
| **Editores de UI** | Studio+, UI Suite, GUI Editor+ | ajuste fino *depois* da importação |
| **Bibliotecas** | General UI Kit, TopbarPlus | componentes prontos, integração manual |

A conclusão que orienta este projeto: **ninguém liga as três.** Os importadores
entregam UI estática; os editores ajudam a mexer nela na mão; as bibliotecas
exigem que você escreva a cola. O espaço vazio é sair do Figma com uma UI que
**já funciona**.

---

## 2. Comparativo de importação

Legenda: **✓** existe · **~** parcial · **✗** ausente

| Recurso | FigBloxUI | RoImport | Outros | **Este plugin** |
|---|---|---|---|---|
| Frame / Group | ✓ | ✓ | ✓ | ✓ |
| Text → TextLabel | ✓ | ✓ | ✓ | ✓ (fonte, peso, cor, alinhamento, entrelinha, auto-size) |
| Vetores → PNG | ✓ | ✓ | ✓ | ✓ (com `absoluteRenderBounds`) |
| Upload de imagem | ✓ (modo Code) | ~ | ~ | ✓ (uploader local + dedup por hash) |
| UICorner | ✓ | ✓ | ✓ | ✓ (círculo em ELLIPSE) |
| UIStroke | ✓ | ✓ | ✓ | ✓ |
| UIGradient | ✓ | ✓ | ~ | ✓ (rotação do `gradientTransform` + transparência) |
| UIListLayout / UIPadding | ✓ | ✓ | ~ | ✓ |
| UIGridLayout | ✗ | ✓ | ✗ | ✓ (Auto Layout com wrap) |
| Sombra | ✓ (beta) | ✓ | ✗ | ✓ (UIShadow + fallback em camadas) |
| ScrollingFrame | ~ | ✓ | ✗ | ✓ (tag + `AutomaticCanvasSize`) |
| Rotação | ~ | ~ | ✗ | ✓ (converte a convenção + AnchorPoint) |
| Ordem de camadas | ✓ | ✓ | ~ | ✓ (ZIndex explícito) |
| RichText | ✗ | ✓ | ✗ | ✓ (negrito/itálico/cor/tamanho por trecho) |
| CanvasGroup | ✗ | ✗ | ✗ | ✓ (opacidade de grupo) |
| Constraints → Anchor/Scale | ~ | ~ | ✗ | ✓ (MIN/MAX/CENTER/STRETCH/SCALE) |
| Components / Variants | ~ | ~ | ✗ | ✗ |
| 9-slice | ✗ | ✗ | ✗ | ✓ (borda derivada do raio) |
| Export `.rbxmx` offline | ✓ | ✗ | ✓ | ✗ |
| Sync ao vivo | ✓ (Live) | ✗ | ✗ | ✓ |
| Cache de imagem | ~ | ✗ | ✗ | ✓ (hash de conteúdo, global entre exports) |
| **Geração de código** | ✗ | ✗ | ✗ | **✓ Pré-Scripts** |
| **Detecção estrutural** | ✗ | ✗ | ✗ | **✓** |

---

## 3. O que copiar em ideia (e melhorar)

### 3.1 Modo ZIP + Asset Manager — **vale implementar**

O FigBloxUI tem três modos: **ZIP** (sem login, você sobe as imagens pelo Asset
Manager do Studio e o plugin casa por nome de arquivo), **Code** (login, imagens
automáticas) e **Live** (sync).

O modo ZIP resolve um problema que hoje é nosso: o `uploader.js` exige Node e
uma API Key. O Asset Manager do Studio sobe imagens em lote nativamente. Um modo
"ZIP" eliminaria a dependência de Node para quem só quer testar.

**Prioridade: alta.** É o maior atrito de instalação que temos.

### 3.2 Ferramentas de ajuste fino — **vale implementar**

Studio+ e GUI Editor+ vendem: conversão scale↔offset, gerenciador de
constraints, nudge com incrementos, conversor de classe (Frame → TextButton).

São operações que o usuário faz *depois* de importar e que hoje ele faz na mão.

**Prioridade: alta**, e casa com o pedido de "controles precisos".

### 3.3 Auto-update — **vale implementar**

Distribuir pela Creator Store dá auto-update via *Manage Plugins*. Hoje o
plugin é arquivo local: cada atualização é um `build.js --install` manual.

**Prioridade: média** (depende de publicar).

### 3.4 Beta de UI primitives — **já tratado**

O FigBloxUI pede para ligar *New UI Capabilities* para usar `UIShadow` e raio
por canto. Nós tentamos `UIShadow` e caímos em aproximação por camadas quando
não existe — melhor, porque não exige configuração.

---

## 4. Onde já somos superiores

**Pré-Scripts.** Nenhum concorrente gera sistemas funcionais. Sair da
importação com inventário, loja, barras e notificações ligados é a diferença
entre "UI desenhada" e "UI pronta".

**Detecção estrutural.** Descoberta ao testar num design real: nomes de camada
não são semânticos. O design de teste tinha `Page 2`, `fundo`, `Group 2`,
`item 1..3`, `comprar 1..3`. De onze camadas, **uma** casava com vocabulário.

Reconhecer *três irmãos de mesmo tamanho* como grade de slots funciona onde o
nome não ajuda — e acertou onde o vínculo manual do próprio usuário errou
(ele apontou o container achando que era o slot).

**Cache por hash de conteúdo.** A mesma imagem nunca sobe duas vezes, nem entre
exports diferentes. Re-exportar é instantâneo.

**Painel de vínculos.** Mostra o que foi encontrado e deixa apontar clicando, em
vez de mandar editar arquivo de configuração.

---

## 5. Lacunas reais, em ordem de valor

### Fechadas

| Lacuna | Como ficou |
|---|---|
| **9-slice** | tag `[SLICE]`; a borda que não estica vem do próprio raio do canto |
| **RichText** | `getStyledTextSegments` → `<b>`, `<i>`, `<font color size>`; só emite quando há diferença real entre trechos |
| **CanvasGroup** | grupo com opacidade < 1 vira `CanvasGroup.GroupTransparency` — achata antes de esmaecer, o que corrige a sobreposição |
| **Constraints** | MIN/MAX/CENTER/STRETCH/SCALE → `Position`/`Size` em (scale, offset) + `AnchorPoint`. Opt-in por toggle |
| **UIGridLayout** | Auto Layout com `layoutWrap = WRAP` → `UIGridLayout` com célula do primeiro filho |
| **Detecção estrutural** | 3+ irmãos de mesma classe e tamanho (±4px) = grade de slots, sem depender de nome |

### Abertas, em ordem de valor

| # | Lacuna | Por quê | Esforço |
|---|---|---|---|
| 1 | **Ferramentas de ajuste** (scale↔offset, nudge, conversor de classe, âncoras) | é o que os pagos vendem; atende o pedido de precisão | médio |
| 2 | **Modo ZIP / Asset Manager** | tira a dependência de Node e API Key — maior atrito de instalação | médio |
| 3 | **Components/Variants → estados** | variante "hover" viraria `HoverImage` automático | alto |
| 4 | **Importação em lote** | várias páginas do Figma numa tacada | médio |
| 5 | **Atalhos de teclado** no painel | produtividade | baixo |
| 6 | **Export `.rbxmx`** | compartilhar UI sem servidor | médio |
| 7 | **Auto-update** | exige publicar na Creator Store | médio |

---

## 6. Notas de implementação que valem lembrar

**Constraints são opt-in.** Ligar por padrão mudaria o posicionamento de todo
mundo que já usa o plugin. O toggle preserva o comportamento fixo como padrão.

**RichText só quando há diferença.** Se todos os trechos têm o mesmo estilo, o
markup é descartado — `RichText = true` custa parse a cada mudança de texto.

**CanvasGroup em vez de transparência por filho.** Aplicar opacidade em cada
filho dá resultado errado onde eles se sobrepõem: cada camada esmaece
individualmente e a soma fica mais opaca que o esperado. `CanvasGroup` achata
o grupo primeiro.

**Detecção estrutural existe porque nomes não são semânticos.** Medido num
design real: de onze camadas (`Page 2`, `fundo`, `Group 2`, `item 1..3`,
`comprar 1..3`), **uma** casava com vocabulário. Estrutura funciona onde
palavra-chave não.
