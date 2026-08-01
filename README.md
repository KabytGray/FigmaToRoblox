# FigmaToRoblox

Plugin gratuito que importa designs do Figma para o Roblox Studio, feito por
**[KabytGray](https://www.roblox.com/users/4024894937/profile)**.

---

## Instalação

**1. Instale o plugin do Studio** — clique em "Install" no [meu perfil de criador](https://create.roblox.com/store/user/4024894937).

**2. Abra o PowerShell** (tecla Windows, digite `PowerShell`) e cole esta linha:

```powershell
irm https://raw.githubusercontent.com/KabytGray/FigmaToRoblox/main/instalar.ps1 | iex
```

Ele faz o resto: baixa o projeto em `Documentos\FigmaToRoblox`, instala o Node.js
se faltar, cria a conta na Cloudflare, publica o Worker, pede a API Key do Roblox
e explica onde criar (com os escopos certos), e instala os plugins. No fim mostra
a URL do Worker para colar no plugin.

> Se preferir baixar na mão: **Code → Download ZIP**, extraia, e dê **dois
> cliques** no `INSTALAR.bat`. Não copie o conteúdo do `.bat` para o PowerShell —
> são linguagens diferentes, e dá erro em `@echo off`.

**3. Reinicie o Roblox Studio.** O plugin **FigmaToRoblox** aparece na barra de
plugins. Abra a aba **Config**, cole a URL no campo do servidor, e o checklist
do topo se acende sozinho.

**4. No Figma:** instale o plugin **FigmaToRoblox** pela página da comunidade e
cole a mesma URL do servidor na aba de configuração dele.

**5. Deixe o `start-uploader.bat` aberto** enquanto trabalha. É ele que sobe as
imagens exportadas — sem ele, a fila enche e o Studio não consegue exibir.

---

## Por que precisa de tanta coisa

Subir imagem para o Roblox exige a Open Cloud, que precisa de uma API Key. Cada
usuário usa a **própria chave** — nada passa por servidor de terceiros, e a
cota do Roblox e da Cloudflare fica com quem instalou. O `INSTALAR.bat`
automatiza o processo inteiro; sem ele, seria uma tarde de configuração.

## O que fica salvo no seu PC

Só dois arquivos, os dois no gitignore: `apikey.txt` (sua chave do Roblox) e
`config.json` (sua URL do Worker e seu userId). Nada mais.

## Ajuda / bugs

Abra uma issue neste repositório, ou fale comigo pelo perfil.

## Apoiar

O plugin é grátis e continua grátis — **nenhuma função fica atrás de
pagamento**. Se ele te ajudou, o botão de apoio dentro do plugin leva a uma
página de doação em Robux (10 a 1000), e quem doa aparece no quadro de
apoiadores. Uma avaliação no perfil também ajuda outras pessoas a acharem.
