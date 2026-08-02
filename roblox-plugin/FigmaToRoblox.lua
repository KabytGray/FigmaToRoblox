--!nonstrict
-- ============================================================================
-- FigmaToRoblox — Plugin do Roblox Studio (schema v2)
-- ============================================================================
-- Consome a arvore ja traduzida pelo plugin do Figma e monta a GUI nativa:
-- Frame / TextLabel / ImageLabel + UICorner, UIStroke, UIGradient, UIListLayout,
-- UIPadding e aproximacao de sombra.
--
-- INSTALACAO
--   Copie este arquivo para %LOCALAPPDATA%\Roblox\Plugins\ e reinicie o Studio.
--
-- IMPORTANTE
--   Requer HTTP habilitado: Game Settings > Security > Allow HTTP Requests.
-- ============================================================================

local Plugin = plugin
assert(Plugin, "Este arquivo precisa rodar como Plugin do Roblox Studio")

local HttpService = game:GetService("HttpService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Selection = game:GetService("Selection")
local StarterGui = game:GetService("StarterGui")
local InsertService = game:GetService("InsertService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local StudioService = game:GetService("StudioService")

--- Conexoes vivas fora da GUI. Sinal de servico (Selection, por exemplo) nao
--- morre quando o widget e destruido: sem desconectar, recarregar o plugin
--- deixa o handler antigo rodando sobre instancias que ja nao existem.
local pluginConnections = {}

--- Icone oficial de uma classe, na variante que da para ver neste painel.
---
--- GetClassIcon devolve o caminho do tema Light mesmo com o Studio no escuro, e
--- icone de tema claro e escuro: TextLabel sai com luminancia 60 sobre um fundo
--- de 33, ou seja, invisivel. Trocar /Light/ por /Dark/ resolve. Se o caminho
--- nao casar (Studio antigo, que usava o atlas ClassImages), fica o original.
local function classIcon(className)
	local ok, data = pcall(function() return StudioService:GetClassIcon(className) end)
	if not ok or not data or not data.Image then return nil end

	local image = data.Image
	if type(image) == "string" and image:find("/Light/", 1, true) then
		image = image:gsub("/Light/", "/Dark/")
	end

	return {
		Image = image,
		RectOffset = data.ImageRectOffset,
		RectSize = data.ImageRectSize,
	}
end

local SCHEMA_VERSION = 2

-- Vazio de proposito. Ja teve o servidor do autor aqui, e isso significava que
-- qualquer pessoa que instalasse o plugin mandava os proprios designs para a
-- conta dele: cota, custo e conteudo alheio no lugar errado. Sem padrao, quem
-- nao configurou ve um aviso claro em vez de "funcionar" no servidor errado.
local DEFAULT_URL = ""
local SYNC_INTERVAL = 3

-- ---------------------------------------------------------------------------
-- Autor e links (troque as URLs aqui, num lugar so)
-- ---------------------------------------------------------------------------
local AUTHOR_USER_ID = 4024894937
local AUTHOR_NAME = "KabytGray"
local PROFILE_URL = "https://www.roblox.com/users/4024894937/profile"
local YOUTUBE_URL = "https://www.youtube.com/results?search_query=FigmaToRoblox+KabytGray"
local REVIEW_URL = PROFILE_URL
-- Place com Developer Products. Plugin nao cobra Robux: PromptProductPurchase
-- exige um Player, que so existe dentro de uma experiencia.
-- Preencha quando publicar o plugin do Figma na comunidade. Ate la, aponta
-- para o seu perfil de criador no Figma.
local FIGMA_PLUGIN_URL = "https://www.figma.com/@kabytgray"

-- Repositorio publico com o INSTALAR.bat, o uploader e o Worker. Sem isto o
-- Passo 1 do checklist nao tem como acontecer.
local PROJECT_REPO_URL = "https://github.com/KabytGray/FigmaToRoblox"
local PROJECT_ZIP_URL = PROJECT_REPO_URL .. "/archive/refs/heads/main.zip"
local DONATE_URL = "https://www.roblox.com/users/4024894937/profile"
local REVIEW_EVERY = 5 -- pede avaliacao a cada N importacoes bem-sucedidas

-- Instalacao inteira em uma linha: baixa o projeto, extrai e roda o setup.
-- Existe porque a reacao natural de quem le "rode o INSTALAR.bat" e colar o
-- CONTEUDO do .bat no PowerShell — que quebra em "@echo off". Colar isto aqui
-- funciona, que e o que a pessoa ja estava tentando fazer.
local INSTALL_CMD =
	"irm https://raw.githubusercontent.com/KabytGray/FigmaToRoblox/main/instalar.ps1 | iex"

-- String longa: barras invertidas ficam literais, sem escape.
--
-- GetFolderPath('MyDocuments') em vez de "$env:USERPROFILE\Documents": quem usa
-- OneDrive tem a pasta Documentos redirecionada para dentro do OneDrive, e o
-- caminho fixo aponta para uma pasta que nao existe. Esta e a MESMA chamada que
-- o instalador usa para escolher onde extrair, entao os dois sempre combinam.
local DEFAULT_CMD =
	[[node "$([Environment]::GetFolderPath('MyDocuments'))\FigmaToRoblox\uploader.js"]]
local DEFAULT_HINT = "Mais facil: de dois cliques no atalho 'FigmaToRoblox uploader'\nna area de trabalho. Ou cole este comando no PowerShell."

-- ============================================================================
-- TEMA
-- ============================================================================
-- Linguagem de inspetor de propriedades: superficies em camadas, hierarquia por
-- peso e valor (nao por cor), e UM azul dessaturado reservado para acao
-- primaria, foco e aba ativa. Raio pequeno (3px) le como ferramenta.
local T = {
	bg       = Color3.fromRGB(26, 26, 28),
	raised   = Color3.fromRGB(33, 33, 36),
	hover    = Color3.fromRGB(41, 42, 45),
	active   = Color3.fromRGB(49, 50, 54),
	-- Quase invisiveis de proposito. Divisorias cinzas visiveis entre cada linha
	-- sao o que fazia o painel parecer uma planilha: separacao aqui vem de
	-- espacamento e de blocos arredondados, nao de tracos.
	line     = Color3.fromRGB(34, 34, 37),
	line2    = Color3.fromRGB(46, 47, 51),

	txt      = Color3.fromRGB(232, 232, 234),
	dim      = Color3.fromRGB(154, 154, 162),
	faint    = Color3.fromRGB(107, 108, 116),

	accent   = Color3.fromRGB(58, 127, 200),
	accentHi = Color3.fromRGB(74, 143, 216),
	accentLo = Color3.fromRGB(43, 92, 145),
	onAccent = Color3.fromRGB(255, 255, 255),

	ok       = Color3.fromRGB(95, 158, 106),
	warn     = Color3.fromRGB(184, 137, 63),
	err      = Color3.fromRGB(192, 85, 79),
}

-- Compatibilidade com trechos que ainda citam os nomes antigos.
T.panel = T.raised
T.panel2 = T.hover
T.panel3 = T.active
T.solid = T.accent
T.solidTxt = T.onAccent

-- ============================================================================
-- HELPERS DE UI
-- ============================================================================
local function mk(class, props, parent)
	local inst = Instance.new(class)
	for key, value in pairs(props) do
		inst[key] = value
	end
	if parent then inst.Parent = parent end
	return inst
end

local function round(inst, radius)
	mk("UICorner", { CornerRadius = UDim.new(0, radius or 6) }, inst)
	return inst
end

--- Devolve o UIStroke, nao o pai: quem chama costuma querer mudar a cor depois
--- (anel de foco em azul, caixa de marcar marcada).
local function stroke(inst, color, thickness)
	return mk("UIStroke", { Color = color or T.line, Thickness = thickness or 1 }, inst)
end

-- ============================================================================
-- HTTP
-- ============================================================================
local Api = {}

local function trimUrl(url)
	return (url:gsub("/+$", ""))
end

function Api.get(baseUrl, route)
	local response = HttpService:RequestAsync({
		Url = trimUrl(baseUrl) .. route,
		Method = "GET",
		Headers = { ["Accept"] = "application/json" },
	})

	if not response.Success then
		error("HTTP " .. tostring(response.StatusCode) .. " " .. tostring(response.StatusMessage))
	end

	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(response.Body)
	end)
	if not ok then error("Resposta invalida do servidor") end
	if decoded.error then error(decoded.error) end

	return decoded
end

-- ============================================================================
-- DECAL -> IMAGE
-- ============================================================================
-- A Open Cloud so cria assets do tipo Decal. `ImageLabel.Image` precisa do ID
-- da Image que o Decal embrulha — apontar para o Decal renderiza NADA, e a UI
-- inteira fica invisivel. InsertService:LoadAsset e o caminho suportado para
-- descobrir esse ID, e so funciona dentro do Studio (por isso a conversao mora
-- aqui, e nao no uploader).
-- ============================================================================
local decalCache = {}

local function loadDecalCache()
	local raw = Plugin:GetSetting("decalCache")
	if type(raw) ~= "string" then return end
	local ok, decoded = pcall(function() return HttpService:JSONDecode(raw) end)
	if ok and type(decoded) == "table" then decalCache = decoded end
end

local function saveDecalCache()
	pcall(function()
		Plugin:SetSetting("decalCache", HttpService:JSONEncode(decalCache))
	end)
end

--- Devolve (imageId, resolvido). Em caso de falha devolve o ID original, que
--- ainda funciona para assets que ja sejam Image.
local function resolveImageId(assetId)
	local decalId = tostring(assetId):match("(%d+)")
	if not decalId then return assetId, false end

	local cached = decalCache[decalId]
	if cached then return cached, true end

	local ok, container = pcall(function()
		return InsertService:LoadAsset(tonumber(decalId))
	end)
	if not ok or not container then return assetId, false end

	local decal = container:FindFirstChildWhichIsA("Decal", true)
	local texture = decal and decal.Texture or nil
	container:Destroy()

	if texture and texture ~= "" then
		local imageId = texture:match("(%d+)")
		local resolved = imageId and ("rbxassetid://" .. imageId) or texture

		-- Teto no cache: ele vive em plugin settings e, sem poda, cresceria para
		-- sempre. Ao encher, esvazia e recomeca — reresolver custa uma chamada,
		-- carregar um settings gigante custa em todo boot do Studio.
		local count = 0
		for _ in pairs(decalCache) do count += 1 end
		if count >= 400 then table.clear(decalCache) end

		decalCache[decalId] = resolved
		return resolved, true
	end

	return assetId, false
end

local function collectImageIds(nodes, out)
	for _, node in ipairs(nodes) do
		if node.image and node.image.id and node.image.id ~= "" then
			out[node.image.id] = true
		end
		if node.kids then collectImageIds(node.kids, out) end
	end
end

-- ============================================================================
-- BUILDER — traduz o schema v2 para instancias do Roblox
-- ============================================================================
local Builder = {}
local report

local function toColor(rgbArray)
	if type(rgbArray) ~= "table" then return Color3.new(1, 1, 1) end
	return Color3.fromRGB(rgbArray[1] or 0, rgbArray[2] or 0, rgbArray[3] or 0)
end

--- Roblox exige keypoints em ordem estritamente crescente, comecando em 0 e
--- terminando em 1, com no maximo 20 entradas.
local function normalizeStops(stops)
	local list = {}
	for index, stop in ipairs(stops) do
		if index > 20 then break end
		table.insert(list, { t = math.clamp(stop.t or 0, 0, 1), data = stop })
	end
	if #list == 0 then return nil end
	if #list == 1 then
		table.insert(list, { t = 1, data = list[1].data })
	end

	table.sort(list, function(a, b) return a.t < b.t end)

	list[1].t = 0
	list[#list].t = 1

	-- desempata tempos repetidos sem estourar 1.0
	for index = 2, #list - 1 do
		if list[index].t <= list[index - 1].t then
			list[index].t = math.min(0.999, list[index - 1].t + 0.001)
		end
	end
	if #list > 1 and list[#list - 1].t >= 1 then
		list[#list - 1].t = 0.999
	end

	return list
end

function Builder.applyGradient(inst, gradient)
	local colorStops = normalizeStops(gradient.stops or {})
	if not colorStops then return end

	local colorKeys = {}
	for _, entry in ipairs(colorStops) do
		table.insert(colorKeys, ColorSequenceKeypoint.new(entry.t, toColor(entry.data.c)))
	end

	local uiGradient = Instance.new("UIGradient")
	uiGradient.Name = "FigmaGradient"
	uiGradient.Color = ColorSequence.new(colorKeys)
	uiGradient.Rotation = gradient.rot or 0

	local alphaStops = normalizeStops(gradient.alpha or {})
	if alphaStops then
		local alphaKeys = {}
		for _, entry in ipairs(alphaStops) do
			table.insert(alphaKeys, NumberSequenceKeypoint.new(entry.t, math.clamp(entry.data.a or 0, 0, 1)))
		end
		pcall(function() uiGradient.Transparency = NumberSequence.new(alphaKeys) end)
	end

	uiGradient.Parent = inst
end

function Builder.applyStroke(inst, data)
	local uiStroke = Instance.new("UIStroke")
	uiStroke.Name = "FigmaStroke"
	uiStroke.Color = toColor(data.c)
	uiStroke.Thickness = math.max(1, data.th or 1)
	uiStroke.Transparency = math.clamp(data.t or 0, 0, 1)
	uiStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	uiStroke.LineJoinMode = Enum.LineJoinMode.Round
	uiStroke.Parent = inst
end

function Builder.applyCorner(inst, radius)
	local uiCorner = Instance.new("UICorner")
	uiCorner.Name = "FigmaCorner"
	-- -1 significa "circulo" (vem de ELLIPSE no Figma)
	uiCorner.CornerRadius = (radius == -1) and UDim.new(0.5, 0) or UDim.new(0, radius)
	uiCorner.Parent = inst
end

function Builder.applyText(inst, text)
	-- RichText preserva negrito, itálico e cor por trecho. Sem ele, um TextLabel
	-- só tem um estilo e a palavra em negrito no meio da frase se perde.
	if text.rich and text.rich ~= "" then
		inst.RichText = true
		inst.Text = text.rich
	else
		inst.RichText = false
		inst.Text = text.content or ""
	end

	inst.TextSize = math.max(1, text.size or 14)
	inst.TextColor3 = toColor(text.color)
	inst.TextTransparency = math.clamp(text.transparency or 0, 0, 1)
	inst.TextWrapped = text.wrapped == true
	inst.TextScaled = false

	local okFont = pcall(function()
		inst.FontFace = Font.fromEnum(Enum.Font[text.font])
	end)
	if not okFont then
		pcall(function() inst.Font = Enum.Font[text.font] end)
	end

	pcall(function() inst.TextXAlignment = Enum.TextXAlignment[text.alignX or "Left"] end)
	pcall(function() inst.TextYAlignment = Enum.TextYAlignment[text.alignY or "Top"] end)

	if text.lineHeight then
		pcall(function() inst.LineHeight = math.clamp(text.lineHeight, 1, 3) end)
	end
	if text.autoSize then
		pcall(function() inst.AutomaticSize = Enum.AutomaticSize[text.autoSize] end)
	end
end

function Builder.applyLayout(inst, layout)
	-- Auto Layout com wrap: UIListLayout não quebra linha, então grade.
	if layout.grid then
		local grid = Instance.new("UIGridLayout")
		grid.Name = "FigmaGrid"
		grid.CellSize = UDim2.fromOffset(layout.grid.cellW, layout.grid.cellH)
		grid.CellPadding = UDim2.fromOffset(layout.grid.gapX, layout.grid.gapY)
		grid.SortOrder = Enum.SortOrder.LayoutOrder
		pcall(function() grid.HorizontalAlignment = Enum.HorizontalAlignment[layout.alignX or "Left"] end)
		pcall(function() grid.VerticalAlignment = Enum.VerticalAlignment[layout.alignY or "Top"] end)
		grid.Parent = inst

		local pad = layout.pad
		if pad and (pad.t ~= 0 or pad.r ~= 0 or pad.b ~= 0 or pad.l ~= 0) then
			mk("UIPadding", {
				Name = "FigmaPadding",
				PaddingTop = UDim.new(0, pad.t or 0),
				PaddingRight = UDim.new(0, pad.r or 0),
				PaddingBottom = UDim.new(0, pad.b or 0),
				PaddingLeft = UDim.new(0, pad.l or 0),
			}, inst)
		end
		return
	end

	local list = Instance.new("UIListLayout")
	list.Name = "FigmaLayout"
	list.FillDirection = (layout.dir == "Horizontal") and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical
	list.Padding = UDim.new(0, layout.gap or 0)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	pcall(function() list.HorizontalAlignment = Enum.HorizontalAlignment[layout.alignX or "Left"] end)
	pcall(function() list.VerticalAlignment = Enum.VerticalAlignment[layout.alignY or "Top"] end)
	list.Parent = inst

	local pad = layout.pad
	if pad and (pad.t ~= 0 or pad.r ~= 0 or pad.b ~= 0 or pad.l ~= 0) then
		mk("UIPadding", {
			Name = "FigmaPadding",
			PaddingTop = UDim.new(0, pad.t or 0),
			PaddingRight = UDim.new(0, pad.r or 0),
			PaddingBottom = UDim.new(0, pad.b or 0),
			PaddingLeft = UDim.new(0, pad.l or 0),
		}, inst)
	end
end

--- Sombra: usa UIShadow quando disponivel (beta de UI primitives) e cai para
--- uma aproximacao em camadas quando nao existe.
--- `inst` recebe a versao nativa (e filha do elemento); a aproximacao vira um
--- irmao em `parent` com ZIndex menor.
function Builder.applyShadow(node, inst, parent, zIndex)
	local shadow = node.shadow

	local nativeOk = pcall(function()
		local uiShadow = Instance.new("UIShadow")
		uiShadow.Name = "FigmaShadow"
		uiShadow.Color = toColor(shadow.c)
		uiShadow.Offset = Vector2.new(shadow.ox or 0, shadow.oy or 0)
		uiShadow.Blur = shadow.blur or 0
		uiShadow.Spread = shadow.spread or 0
		uiShadow.Transparency = math.clamp(shadow.t or 0.5, 0, 1)
		uiShadow.Parent = inst
	end)
	if nativeOk then return end

	local holder = mk("Frame", {
		Name = node.name .. "_Shadow",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(node.w, node.h),
		Position = UDim2.fromOffset(node.x + (shadow.ox or 0), node.y + (shadow.oy or 0)),
		ZIndex = zIndex,
		BorderSizePixel = 0,
	}, parent)

	if node.anchor then
		holder.AnchorPoint = Vector2.new(node.anchor[1], node.anchor[2])
	end

	local layers = 3
	local baseAlpha = (1 - math.clamp(shadow.t or 0.5, 0, 1)) / layers
	local blur = math.max(0, shadow.blur or 0)

	for index = 1, layers do
		local grow = (blur * 0.5) * (index / layers) + (shadow.spread or 0)
		local layer = mk("Frame", {
			Name = "L" .. index,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, grow * 2, 1, grow * 2),
			BackgroundColor3 = toColor(shadow.c),
			BackgroundTransparency = math.clamp(1 - baseAlpha, 0, 1),
			BorderSizePixel = 0,
			ZIndex = zIndex,
		}, holder)

		if node.corner then
			Builder.applyCorner(layer, (node.corner == -1) and -1 or (node.corner + grow))
		end
	end
end

--- Constroi um no e toda a sua descendencia.
function Builder.build(node, parent)
	local class = node.cls or "Frame"

	local inst
	local created = pcall(function() inst = Instance.new(class) end)
	if not created or not inst then
		report.errors += 1
		table.insert(report.messages, "Classe invalida: " .. tostring(class))
		inst = Instance.new("Frame")
	end

	inst.Name = node.name or "Element"
	inst.BorderSizePixel = 0

	-- ZIndex dobrado deixa o slot impar livre para a sombra ficar atras.
	local zIndex = (node.z or 1) * 2
	inst.ZIndex = zIndex
	inst.LayoutOrder = node.z or 1

	-- Geometria. `fit` vem das constraints do Figma e traz Position/Size em
	-- (scale, offset), o que faz o elemento acompanhar o pai. Sem ele, offsets
	-- crus — que é o comportamento fixo de sempre.
	local fit = node.fit
	if fit then
		local px, py = fit.px or { 0, node.x or 0 }, fit.py or { 0, node.y or 0 }
		local sx, sy = fit.sx or { 0, node.w or 1 }, fit.sy or { 0, node.h or 1 }
		inst.Position = UDim2.new(px[1], px[2], py[1], py[2])
		inst.Size = UDim2.new(sx[1], sx[2], sy[1], sy[2])
		if fit.anchor then
			inst.AnchorPoint = Vector2.new(fit.anchor[1], fit.anchor[2])
		end
	else
		inst.Size = UDim2.fromOffset(math.max(1, node.w or 1), math.max(1, node.h or 1))
		inst.Position = UDim2.fromOffset(node.x or 0, node.y or 0)
	end

	-- Nó rotacionado ancora no centro; sobrescreve a âncora do fit.
	if node.anchor then
		inst.AnchorPoint = Vector2.new(node.anchor[1], node.anchor[2])
	end

	-- Opacidade de grupo: achata os filhos e só então esmaece.
	if node.groupT and inst:IsA("CanvasGroup") then
		inst.GroupTransparency = math.clamp(node.groupT, 0, 1)
	end
	if node.rot then
		inst.Rotation = node.rot
	end
	if node.visible == false then
		inst.Visible = false
	end
	if node.clip then
		pcall(function() inst.ClipsDescendants = true end)
	end

	-- Preenchimento (nunca usar truthiness: transparencia 0 e valor valido)
	if node.bg then
		inst.BackgroundColor3 = toColor(node.bg.c)
		inst.BackgroundTransparency = math.clamp(node.bg.t or 0, 0, 1)
	else
		inst.BackgroundTransparency = 1
	end

	-- Imagem. A guarda de classe e obrigatoria: se o usuario forcou a classe no
	-- conversor (TextLabel, CanvasGroup...), o no ainda traz `image`, e atribuir
	-- .Image num objeto que nao tem essa propriedade lanca — derrubando a
	-- importacao inteira com "Falha ao montar".
	local canShowImage = inst:IsA("ImageLabel") or inst:IsA("ImageButton")

	if node.image and not canShowImage then
		report.errors += 1
		table.insert(report.messages, node.name .. ": classe " .. class .. " nao exibe imagem")
	end

	if node.image and canShowImage then
		local assetId = node.image.id
		if assetId and assetId ~= "" then
			-- cache ja aquecido pelo pre-resolve em importExport
			local imageId, resolved = resolveImageId(assetId)
			inst.Image = imageId
			inst.ImageTransparency = math.clamp(node.image.t or 0, 0, 1)
			inst.BackgroundTransparency = 1

			-- 9-slice preserva a borda e estica so o meio; Stretch deforma o
			-- canto arredondado quando o painel muda de tamanho.
			local slice = node.image.slice
			if node.image.scale == "Slice" and slice then
				inst.ScaleType = Enum.ScaleType.Slice
				pcall(function()
					inst.SliceCenter = Rect.new(slice.l, slice.t, slice.r, slice.b)
				end)
			else
				inst.ScaleType = Enum.ScaleType.Stretch
			end
			report.images += 1

			if not resolved then
				-- Sem conversao a imagem nao renderiza. Um retangulo visivel e
				-- melhor do que o elemento sumir sem explicacao.
				inst.BackgroundTransparency = 0.6
				inst.BackgroundColor3 = T.warn
			end
		else
			report.missing += 1
			inst.BackgroundTransparency = 0.75
			inst.BackgroundColor3 = T.err
		end
	end

	-- ScrollingFrame sem CanvasSize nao rola. AutomaticCanvasSize e reativo:
	-- recalcula conforme os filhos entram, inclusive com posicao absoluta.
	if inst:IsA("ScrollingFrame") then
		local horizontal = node.layout and node.layout.dir == "Horizontal"
		inst.CanvasSize = UDim2.new()
		inst.AutomaticCanvasSize = horizontal and Enum.AutomaticSize.X or Enum.AutomaticSize.Y
		inst.ScrollingDirection = horizontal and Enum.ScrollingDirection.X or Enum.ScrollingDirection.Y
		inst.ScrollBarThickness = 6
		inst.ScrollBarImageColor3 = Color3.new(0, 0, 0)
		inst.ScrollBarImageTransparency = 0.55
		inst.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
	end

	if node.gradient then pcall(function() Builder.applyGradient(inst, node.gradient) end) end
	if node.stroke then pcall(function() Builder.applyStroke(inst, node.stroke) end) end
	if node.corner then pcall(function() Builder.applyCorner(inst, node.corner) end) end
	if node.text then pcall(function() Builder.applyText(inst, node.text) end) end
	if node.layout then pcall(function() Builder.applyLayout(inst, node.layout) end) end

	inst.Parent = parent
	report.nodes += 1

	-- Depois de parentado: o ZIndex menor ja garante que a sombra fique atras.
	if node.shadow then
		pcall(function() Builder.applyShadow(node, inst, parent, zIndex - 1) end)
	end

	-- Filhos ja vem do Figma na ordem de tras para frente.
	if node.kids then
		for _, child in ipairs(node.kids) do
			Builder.build(child, inst)
		end
	end

	return inst
end

-- ============================================================================
-- PRE-SCRIPTS — templates embutidos
-- ============================================================================
-- A tabela abaixo e gerada por build.js a partir de templates/*.lua. Nao edite
-- aqui: edite os arquivos e rode `node build.js`.
--[[__TEMPLATES__]]

-- ============================================================================
-- PRE-SCRIPTS — catalogo e geracao
-- ============================================================================
local PreScripts = {}

--- Cada sistema declara o que precisa achar na UI. `paths` mapeia a chave do
--- Config para as palavras que identificam a camada — em ingles e portugues,
--- porque designer nomeia camada no idioma que quiser.
PreScripts.SYSTEMS = {
	{ key = "buttonFx", label = "Sistema de Botoes", hint = "Hover, clique e som em tudo que e clicavel", paths = {} },
	{ key = "healthBar", label = "Barra de Vida", hint = "Anima o preenchimento e avisa ao zerar", paths = {
		healthFill = { "health", "vida", "hp", "life" },
		healthLabel = { "healthtext", "vidatexto", "hptext" },
	} },
	{ key = "manaBar", label = "Barra de Mana", hint = "Igual a de vida, alvo diferente", paths = {
		manaFill = { "mana", "energia", "mp" },
		manaLabel = { "manatext", "manatexto" },
	} },
	{ key = "xpBar", label = "Barra de XP", hint = "Com SetMax para subir de nivel", paths = {
		xpFill = { "xp", "exp", "experien" },
		xpLabel = { "xptext", "xptexto", "level", "nivel" },
	} },
	{ key = "inventory", label = "Sistema de Inventario", hint = "Slots clonados do seu modelo, com tooltip", paths = {
		inventoryPanel = { "inventor", "mochila", "bag", "backpack" },
		inventoryContainer = { "slots", "grid", "itens", "items", "conteudo", "lista", "list", "group" },
		inventorySlot = { "slot", "cell", "celula", "item", "espaco", "quadrado" },
		inventoryOpenButton = { "openinventor", "abririnventor", "btninventor" },
		inventoryCloseButton = { "close", "fechar" },
	} },
	{ key = "hotbar", label = "Hotbar", hint = "Teclas 1..9 e destaque do slot ativo", paths = {
		hotbarContainer = { "hotbar", "atalho", "quickbar" },
		hotbarSlot = { "slot", "cell", "celula" },
	} },
	{ key = "shop", label = "Sistema de Loja", hint = "Grade de produtos, abas de categoria e confirmacao", paths = {
		shopPanel = { "shop", "loja", "store", "mercado" },
		shopContainer = { "products", "produtos", "grid", "itens", "items", "lista", "group" },
		shopSlot = { "slot", "produto", "product", "card", "item", "comprar", "buy" },
		shopTabBar = { "categor", "tabs", "abas" },
		shopPages = { "pages", "paginas", "conteudo" },
		shopOpenButton = { "openshop", "abrirloja", "btnloja" },
		shopCloseButton = { "close", "fechar" },
	} },
	{ key = "settings", label = "Sistema de Configuracoes", hint = "Painel com abrir/fechar", paths = {
		settingsPanel = { "setting", "config", "opcoes", "options", "ajuste" },
		settingsOpenButton = { "opensetting", "abrirconfig", "btnconfig" },
		settingsCloseButton = { "close", "fechar" },
	} },
	{ key = "tabs", label = "Sistema de Abas", hint = "Casa botoes de aba com paginas pelo nome", paths = {
		tabBar = { "tabbar", "abas", "tabs", "categor" },
		tabPages = { "pages", "paginas", "conteudo", "content" },
	} },
	{ key = "confirm", label = "Janela de Confirmacao", hint = "Pergunta sim/nao com callback", paths = {
		confirmPanel = { "confirm", "confirma" },
		confirmMessage = { "message", "mensagem", "texto" },
		confirmTitle = { "title", "titulo" },
		confirmYes = { "yes", "sim", "confirmar", "ok" },
		confirmNo = { "no", "nao", "cancel", "cancelar" },
	} },
	{ key = "notify", label = "Notificacao", hint = "Pilha de avisos a partir de um modelo", paths = {
		notifyContainer = { "notifi", "notific", "toast", "aviso", "alert" },
		notifyTemplate = { "notifitem", "toastitem", "avisoitem", "template", "modelo" },
	} },
	{ key = "tooltip", label = "Tooltip", hint = "Segue o cursor e vira nas bordas da tela", paths = {
		tooltipTemplate = { "tooltip", "dica", "hint" },
	} },
	{ key = "settingsControls", label = "Controles de Config", hint = "Vira toggles e sliders do painel em controles vivos", paths = {
		settingsContainer = { "settingslist", "opcoeslista", "configlista", "options", "opcoes", "content" },
	} },
	{ key = "selection", label = "Sistema de Selecao", hint = "Escolha unica ou multipla sobre um grupo de botoes", paths = {
		selectionContainer = { "selection", "selecao", "escolha", "choices", "opcoes", "group", "grupo" },
	} },
	{ key = "scroll", label = "Scroll (todos)", hint = "Configura CanvasSize em todo ScrollingFrame da UI", paths = {} },
	{ key = "dragAndDrop", label = "Drag and Drop", hint = "Troca itens entre slots do inventario", paths = {} },
	{ key = "dragPanels", label = "Arrastar Paineis", hint = "Mover janelas pela barra de titulo", paths = {} },
}

--- Nome legivel de cada alvo, para a lista de vinculos. Sem isso o painel
--- mostraria "inventorySlot", que nao diz nada para quem nao programa.
PreScripts.PATH_LABELS = {
	healthFill = "Barra de vida — preenchimento",
	healthLabel = "Barra de vida — texto",
	manaFill = "Barra de mana — preenchimento",
	manaLabel = "Barra de mana — texto",
	xpFill = "Barra de XP — preenchimento",
	xpLabel = "Barra de XP — texto",

	inventoryPanel = "Inventario — painel",
	inventoryContainer = "Inventario — area dos slots",
	inventorySlot = "Inventario — modelo de slot",
	inventoryOpenButton = "Inventario — botao abrir",
	inventoryCloseButton = "Inventario — botao fechar",

	hotbarContainer = "Hotbar — area dos slots",
	hotbarSlot = "Hotbar — modelo de slot",

	shopPanel = "Loja — painel",
	shopContainer = "Loja — area dos produtos",
	shopSlot = "Loja — modelo de produto",
	shopTabBar = "Loja — barra de categorias",
	shopPages = "Loja — paginas das categorias",
	shopOpenButton = "Loja — botao abrir",
	shopCloseButton = "Loja — botao fechar",

	settingsPanel = "Configuracoes — painel",
	settingsOpenButton = "Configuracoes — botao abrir",
	settingsCloseButton = "Configuracoes — botao fechar",
	settingsContainer = "Configuracoes — lista de opcoes",

	tabBar = "Abas — barra de botoes",
	tabPages = "Abas — paginas",

	confirmPanel = "Confirmacao — painel",
	confirmMessage = "Confirmacao — mensagem",
	confirmTitle = "Confirmacao — titulo",
	confirmYes = "Confirmacao — botao sim",
	confirmNo = "Confirmacao — botao nao",

	notifyContainer = "Notificacao — area da pilha",
	notifyTemplate = "Notificacao — modelo",

	tooltipTemplate = "Tooltip — modelo",

	selectionContainer = "Selecao — grupo de botoes",
}

function PreScripts.pathLabel(key)
	return PreScripts.PATH_LABELS[key] or key
end

--- Perguntas numericas. Ficam num lugar so para a UI montar os campos sem
--- precisar saber de cada sistema.
PreScripts.QUESTIONS = {
	{ key = "inventorySlots", label = "Slots do inventario", default = 20, requires = "inventory" },
	{ key = "inventoryColumns", label = "Colunas do inventario", default = 5, requires = "inventory" },
	{ key = "hotbarSlots", label = "Slots da hotbar", default = 6, requires = "hotbar" },
	{ key = "shopSlots", label = "Produtos na loja", default = 12, requires = "shop" },
	{ key = "shopColumns", label = "Colunas da loja", default = 4, requires = "shop" },
	{ key = "healthMax", label = "Vida maxima", default = 100, requires = "healthBar" },
	{ key = "manaMax", label = "Mana maxima", default = 100, requires = "manaBar" },
	{ key = "xpMax", label = "XP por nivel", default = 100, requires = "xpBar" },
	{ key = "selectionMax", label = "Selecao maxima (0 = livre)", default = 0, requires = "selection" },
}

local function normalize(text)
	return (tostring(text):lower():gsub("[^%a%d]", ""))
end

--- Caminho pontilhado de `node` relativo a `root`. Exposto porque o painel de
--- vinculos precisa dele ao capturar a selecao do Explorer.
function PreScripts.pathOf(node, root)
	local parts = {}
	local current = node
	while current and current ~= root do
		table.insert(parts, 1, current.Name)
		current = current.Parent
	end
	return table.concat(parts, ".")
end

--- Caminho pontilhado de `node` relativo a `root`.
local function pathOf(node, root)
	local parts = {}
	local current = node
	while current and current ~= root do
		table.insert(parts, 1, current.Name)
		current = current.Parent
	end
	return table.concat(parts, ".")
end

--- Melhor candidato para um conjunto de palavras. Pontua por: nome comeca com
--- a palavra (forte), contem a palavra (medio), e desempata pelo mais raso —
--- um "Fill" dentro de "BarraVida" ganha de um "Fill" perdido em outro canto.
local function findByKeywords(root, keywords, classFilter)
	local best, bestScore = nil, 0

	for _, descendant in ipairs(root:GetDescendants()) do
		local ok = true
		if classFilter and not descendant:IsA(classFilter) then ok = false end

		if ok then
			local name = normalize(descendant.Name)
			for _, word in ipairs(keywords) do
				local needle = normalize(word)
				local score = 0
				if name == needle then score = 100
				elseif name:sub(1, #needle) == needle then score = 60
				elseif name:find(needle, 1, true) then score = 30 end

				if score > 0 then
					local depth = 0
					local walker = descendant
					while walker and walker ~= root do depth += 1; walker = walker.Parent end
					score = score - depth

					if score > bestScore then best, bestScore = descendant, score end
				end
			end
		end
	end

	return best
end

--- Grupos de irmaos repetidos: 3+ filhos do mesmo pai, mesma classe e tamanho
--- semelhante.
---
--- Detectar por nome falha no mundo real: designer nomeia "item 1", "Group 2",
--- "comprar 1" — nada disso tem "slot" ou "produto" dentro. Mas trinta pixels
--- repetidos tres vezes em linha SAO uma grade, e isso a estrutura revela sem
--- depender de vocabulario.
---
--- Devolve { container, template, count } do maior grupo encontrado.
function PreScripts.findRepeatedGroup(root, minCount)
	minCount = minCount or 3
	local best, bestScore = nil, 0

	local function consider(parent)
		local buckets = {}

		for _, child in ipairs(parent:GetChildren()) do
			if child:IsA("GuiObject") then
				-- Tolerancia de 4px: slots desenhados a mao raramente sao exatos.
				local w = math.floor(math.max(child.Size.X.Offset, child.AbsoluteSize.X) / 4)
				local h = math.floor(math.max(child.Size.Y.Offset, child.AbsoluteSize.Y) / 4)
				local key = child.ClassName .. ":" .. w .. "x" .. h
				buckets[key] = buckets[key] or {}
				table.insert(buckets[key], child)
			end
		end

		for _, list in pairs(buckets) do
			if #list >= minCount then
				-- Mais repeticoes ganha; empate vai para o grupo mais raso, que
				-- costuma ser o container principal e nao um detalhe interno.
				local depth, walker = 0, parent
				while walker and walker ~= root do depth += 1; walker = walker.Parent end
				local score = #list * 10 - depth

				if score > bestScore then
					table.sort(list, function(a, b) return a.Name < b.Name end)
					best = { container = parent, template = list[1], count = #list }
					bestScore = score
				end
			end
		end
	end

	consider(root)
	for _, node in ipairs(root:GetDescendants()) do
		if node:IsA("GuiObject") then consider(node) end
	end

	return best
end

--- Todas as chaves de alvo dos sistemas marcados, em ordem estavel. A lista de
--- vinculos no painel se monta a partir disso.
function PreScripts.requiredPaths(selected)
	local list = {}

	for _, system in ipairs(PreScripts.SYSTEMS) do
		if selected[system.key] then
			local keys = {}
			for pathKey in pairs(system.paths) do table.insert(keys, pathKey) end
			table.sort(keys)
			for _, pathKey in ipairs(keys) do
				table.insert(list, { key = pathKey, system = system.key })
			end
		end
	end

	return list
end

--- Varre a UI e adivinha os caminhos dos sistemas escolhidos. `overrides`
--- (vinculos feitos a mao no painel) tem prioridade sobre a adivinhacao: se a
--- pessoa apontou o elemento, nao cabe ao plugin discordar.
function PreScripts.detect(root, selected, overrides)
	local paths = {}
	local found, missing = 0, {}
	overrides = overrides or {}

	for _, system in ipairs(PreScripts.SYSTEMS) do
		if selected[system.key] then
			for pathKey, keywords in pairs(system.paths) do
				local manual = overrides[pathKey]
				if manual and manual ~= "" then
					paths[pathKey] = manual
					found += 1
					continue
				end

				-- Fill de barra e Frame; botao e GuiButton; texto e TextLabel.
				local class = nil
				if pathKey:find("Button") then class = "GuiButton"
				elseif pathKey:find("Label") or pathKey:find("Message") or pathKey:find("Title") then class = "TextLabel"
				end

				local node = findByKeywords(root, keywords, class)

				-- Barras: o alvo e o preenchimento interno, nao o trilho.
				if node and pathKey:find("Fill") then
					local inner = findByKeywords(node, { "fill", "preenchimento", "bar", "barra", "progress" }, "GuiObject")
					if inner and inner ~= node then node = inner end
				end

				if node then
					paths[pathKey] = pathOf(node, root)
					found += 1
				else
					table.insert(missing, pathKey)
				end
			end
		end
	end

	-- Segunda passada: o que o nome nao achou, a estrutura talvez ache. Grades
	-- de slots sao o caso mais comum e o mais facil de reconhecer pela forma.
	local grid = nil
	local function repeatedGroup()
		if grid == nil then grid = PreScripts.findRepeatedGroup(root) or false end
		return grid or nil
	end

	local STRUCTURAL = {
		{ container = "inventoryContainer", template = "inventorySlot", system = "inventory" },
		{ container = "shopContainer", template = "shopSlot", system = "shop" },
		{ container = "hotbarContainer", template = "hotbarSlot", system = "hotbar" },
		{ container = "selectionContainer", system = "selection" },
	}

	for _, spec in ipairs(STRUCTURAL) do
		if selected[spec.system] then
			local needsContainer = paths[spec.container] == nil
			local needsTemplate = spec.template ~= nil and paths[spec.template] == nil

			if needsContainer or needsTemplate then
				local group = repeatedGroup()
				if group then
					if needsContainer then
						paths[spec.container] = pathOf(group.container, root)
						found += 1
					end
					if needsTemplate then
						paths[spec.template] = pathOf(group.template, root)
						found += 1
					end
				end
			end
		end
	end

	-- Recalcula o que continua faltando depois da passada estrutural.
	local stillMissing = {}
	for _, key in ipairs(missing) do
		if paths[key] == nil then table.insert(stillMissing, key) end
	end
	missing = stillMissing

	return paths, found, missing
end

--- Serializa uma tabela Lua legivel — o Config e feito para ser editado a mao.
local function serialize(value, indent)
	indent = indent or "\t"

	if type(value) == "table" then
		local isArray = #value > 0
		local parts = {}

		if isArray then
			for _, item in ipairs(value) do
				table.insert(parts, indent .. "\t" .. serialize(item, indent .. "\t") .. ",")
			end
		else
			local keys = {}
			for key in pairs(value) do table.insert(keys, key) end
			table.sort(keys)
			for _, key in ipairs(keys) do
				table.insert(parts, indent .. "\t" .. key .. " = " .. serialize(value[key], indent .. "\t") .. ",")
			end
		end

		if #parts == 0 then return "{}" end
		return "{\n" .. table.concat(parts, "\n") .. "\n" .. indent .. "}"
	end

	if type(value) == "string" then return string.format("%q", value) end
	return tostring(value)
end

local function buildConfigSource(systems, paths, options)
	return table.concat({
		"--!strict",
		"--[[",
		"\tConfig — GERADO pelo plugin FigmaToRoblox.",
		"",
		"\tOs caminhos foram adivinhados pelos nomes das camadas. Se algum sistema",
		"\tnao achou o alvo, corrija a string aqui: e um caminho pontilhado a",
		"\tpartir da ScreenGui (ex: \"HUD.BarraVida.Fill\").",
		"",
		"\tReimportar a UI regenera este arquivo. Boot.lua e UIController nao.",
		"]]",
		"",
		"return {",
		"\tsystems = " .. serialize(systems) .. ",",
		"",
		"\tpaths = " .. serialize(paths) .. ",",
		"",
		"\toptions = " .. serialize(options) .. ",",
		"",
		"\t--- Paineis arrastaveis: { panel = \"caminho\", handle = \"caminho\" }",
		"\tdragPanels = " .. serialize({}) .. ",",
		"}",
		"",
	}, "\n")
end

--- Cria (ou reaproveita) a pasta de um caminho como "components/Bar".
local function folderFor(parent, key)
	local current = parent
	local segments = {}
	for segment in string.gmatch(key, "[^/]+") do table.insert(segments, segment) end

	for index = 1, #segments - 1 do
		local existing = current:FindFirstChild(segments[index])
		if not existing then
			existing = Instance.new("Folder")
			existing.Name = segments[index]
			existing.Parent = current
		end
		current = existing
	end

	return current, segments[#segments]
end

--- Gera a arvore em ReplicatedStorage.FigmaUI e o UIController na ScreenGui.
--- Devolve (ok, mensagem).
function PreScripts.generate(screenGui, selected, options, overrides)
	-- A raiz TEM de ser a ScreenGui: o UIController chama Boot.start(script.Parent),
	-- que é a ScreenGui. Detectar a partir do Frame interno geraria caminhos
	-- deslocados um nível, e nada resolveria em tempo de jogo.
	local paths, found, missing = PreScripts.detect(screenGui, selected, overrides)

	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local library = ReplicatedStorage:FindFirstChild("FigmaUI")
	if not library then
		library = Instance.new("Folder")
		library.Name = "FigmaUI"
		library.Parent = ReplicatedStorage
	end

	local written = 0
	for key, source in pairs(TEMPLATES) do
		if key ~= "UIController" then
			local parent, name = folderFor(library, key)
			local existing = parent:FindFirstChild(name)

			-- Config e sempre regenerado; os modulos so entram se faltarem, para
			-- nao apagar ajuste manual de quem mexeu neles.
			if name == "Config" and existing then existing:Destroy(); existing = nil end

			if not existing then
				local module = Instance.new("ModuleScript")
				module.Name = name
				module.Source = source
				module.Parent = parent
				written += 1
			end
		end
	end

	local config = Instance.new("ModuleScript")
	config.Name = "Config"
	config.Source = buildConfigSource(selected, paths, options)
	config.Parent = library

	-- UIController pertence ao usuario: nunca sobrescreve.
	local controller = screenGui:FindFirstChild("UIController")
	if not controller then
		controller = Instance.new("LocalScript")
		controller.Name = "UIController"
		controller.Source = TEMPLATES["UIController"] or "-- template ausente"
		controller.Parent = screenGui
		written += 1
	end

	local message = string.format("%d modulo(s), %d caminho(s) detectado(s)", written, found)
	if #missing > 0 then
		message = message .. ", " .. #missing .. " a conferir no Config"
	end
	return true, message, missing
end

-- ============================================================================
-- ESCALA RESPONSIVA
-- ============================================================================
-- O import sai em pixels absolutos, que nao acompanham telas diferentes: uma
-- loja desenhada em 1420px estoura num celular. Um UIScale no container
-- resolve, mas precisa de um script para seguir o viewport em tempo de jogo.
-- Por isso e opcional: injetar script no projeto do usuario deve ser escolha
-- dele, nunca efeito colateral.
-- ============================================================================
local SCALE_SCRIPT = [[
-- Gerado pelo FigmaToRoblox. Mantem a UI proporcional em qualquer resolucao.
local BASE_X, BASE_Y = %d, %d

local uiScale = script.Parent:FindFirstChildOfClass("UIScale")
if not uiScale then return end

local camera = workspace.CurrentCamera
if not camera then return end

local function update()
	local viewport = camera.ViewportSize
	if viewport.X <= 0 or viewport.Y <= 0 then return end
	uiScale.Scale = math.min(viewport.X / BASE_X, viewport.Y / BASE_Y)
end

camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
update()
]]

local function applyResponsiveScale(container, width, height)
	local uiScale = Instance.new("UIScale")
	uiScale.Name = "FigmaScale"
	uiScale.Parent = container

	local autoScale = Instance.new("LocalScript")
	autoScale.Name = "FigmaAutoScale"
	autoScale.Source = string.format(SCALE_SCRIPT, math.max(1, math.floor(width)), math.max(1, math.floor(height)))
	autoScale.Parent = container
end

-- ============================================================================
-- IMPORTACAO
-- ============================================================================
local responsiveScale = false

local function resolveParent()
	local selected = Selection:Get()[1]
	if selected and (selected:IsA("GuiObject") or selected:IsA("ScreenGui") or selected:IsA("SurfaceGui") or selected:IsA("BillboardGui")) then
		return selected, selected.Name
	end
	return nil, "StarterGui"
end

--- `useSelection` so vale para importacao manual. No auto-sync ele fica falso,
--- senao cada import cairia dentro do ScreenGui criado pelo import anterior
--- (que continua selecionado no Explorer).
local function importExport(baseUrl, exportId, statusFn, useSelection)
	report = { nodes = 0, images = 0, missing = 0, unresolved = 0, errors = 0, messages = {} }

	statusFn("Buscando export " .. exportId .. "...", "info")

	local ok, data = pcall(function()
		return Api.get(baseUrl, "/api/export/" .. exportId)
	end)
	if not ok then
		statusFn("Erro: " .. tostring(data), "err")
		return nil
	end

	if data.schemaVersion ~= SCHEMA_VERSION then
		statusFn("Schema v" .. tostring(data.schemaVersion) .. " incompativel. Re-exporte do Figma.", "err")
		return nil
	end
	if not data.roots or #data.roots == 0 then
		statusFn("Export vazio.", "err")
		return nil
	end

	-- Converte Decal -> Image antes de abrir a gravacao: LoadAsset cede a thread
	-- e nao deve rodar no meio de um passo de undo.
	local ids = {}
	collectImageIds(data.roots, ids)

	local pendingIds = 0
	for _ in pairs(ids) do pendingIds += 1 end

	if pendingIds > 0 then
		statusFn("Resolvendo " .. pendingIds .. " imagem(ns)...", "info")
		for assetId in pairs(ids) do
			local _, ok = resolveImageId(assetId)
			if not ok then report.unresolved += 1 end
		end
		saveDecalCache()
	end

	statusFn("Montando " .. #data.roots .. " raiz(es)...", "info")

	local recording = ChangeHistoryService:TryBeginRecording("FigmaImport", "Importar do Figma")

	local container, targetName
	if useSelection then
		container, targetName = resolveParent()
	else
		targetName = "StarterGui"
	end
	local screenGui

	if not container then
		screenGui = mk("ScreenGui", {
			Name = "Figma_" .. (data.rootName or "Import"),
			ResetOnSpawn = false,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			IgnoreGuiInset = true,
		}, StarterGui)
		container = mk("Frame", {
			Name = data.rootName or "Root",
			Size = UDim2.fromOffset(math.max(1, data.canvasWidth or 100), math.max(1, data.canvasHeight or 100)),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
		}, screenGui)
	end

	local buildOk, buildErr = pcall(function()
		for _, root in ipairs(data.roots) do
			Builder.build(root, container)
		end
	end)

	if recording then
		ChangeHistoryService:FinishRecording(
			recording,
			buildOk and Enum.FinishRecordingOperation.Commit or Enum.FinishRecordingOperation.Cancel
		)
	end

	if not buildOk then
		statusFn("Falha ao montar: " .. tostring(buildErr), "err")
		return nil
	end

	-- Só quando criamos a hierarquia: aplicar UIScale num container do usuario
	-- mexeria em algo que nao e nosso.
	if screenGui and responsiveScale then
		pcall(function()
			applyResponsiveScale(container, data.canvasWidth or 1, data.canvasHeight or 1)
		end)
	end

	if useSelection then
		Selection:Set({ screenGui or container })
	end

	local summary = string.format("%d elementos · %d imagens", report.nodes, report.images)
	if report.missing > 0 then
		statusFn(summary .. " · " .. report.missing .. " imagem(ns) sem upload — rode o uploader (comando abaixo)", "warn")
	elseif report.unresolved > 0 then
		statusFn(summary .. " · " .. report.unresolved .. " imagem(ns) nao converteram de Decal para Image", "warn")
	elseif report.errors > 0 then
		statusFn(summary .. " · " .. report.errors .. " aviso(s)", "warn")
	else
		statusFn(summary .. " · importado em " .. targetName, "ok")
	end

	return data.exportId, screenGui
end

-- ============================================================================
-- INTERFACE
-- ============================================================================
-- Inspetor de propriedades: uma coluna de rotulos a esquerda, uma coluna de
-- controles a direita, fio de 1px separando linhas. Grupos sao anunciados por
-- cabecalho discreto, nunca por caixa — cartao em volta de cada item e o que
-- faz uma interface parecer gerada.
--
-- Linha de 28px em vez de 50px: com 17 sistemas e ate 30 vinculos, a densidade
-- e o problema real. Barra de status de 22px no rodape substitui o cartao de
-- status, que comia altura para dizer uma linha.
-- ============================================================================
local toolbar = Plugin:CreateToolbar("FigmaToRoblox")
local toggleButton = toolbar:CreateButton("Figma Import", "Abre o painel do FigmaToRoblox", "rbxassetid://5996486202")

local widget = Plugin:CreateDockWidgetPluginGui(
	"FigmaToRoblox_v2",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, false, 400, 620, 340, 440)
)
widget.Title = "FigmaToRoblox"
widget.Name = "FigmaToRoblox"

local root = mk("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = T.bg,
	BorderSizePixel = 0,
}, widget)

local HEADER_H = 40
local TABS_H = 34 -- pilulas precisam de mais folga que rotulos soltos
local STATUS_H = 22
local GUTTER = 12
local ROW_H = 28

--- Fio horizontal de 1px. Divisor e o que substitui caixa neste desenho.
local function hairline(parent, atBottom)
	return mk("Frame", {
		Size = UDim2.new(1, 0, 0, 1),
		Position = atBottom and UDim2.new(0, 0, 1, -1) or UDim2.new(),
		BackgroundColor3 = T.line,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, parent)
end

-- ---------------------------------------------------------------- cabecalho
local header = mk("Frame", {
	Size = UDim2.new(1, 0, 0, HEADER_H),
	BackgroundColor3 = T.raised,
	BorderSizePixel = 0,
}, root)
hairline(header, true)

local mark = mk("Frame", {
	Size = UDim2.fromOffset(18, 18),
	Position = UDim2.fromOffset(GUTTER, 11),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
}, header)
round(mark, 3)
stroke(mark, T.line2)
mk("TextLabel", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Text = "F",
	TextColor3 = T.dim,
	TextSize = 10,
	Font = Enum.Font.GothamBold,
}, mark)

mk("TextLabel", {
	Size = UDim2.fromOffset(110, 16),
	Position = UDim2.fromOffset(GUTTER + 26, 12),
	BackgroundTransparency = 1,
	Text = "FigmaToRoblox",
	TextColor3 = T.txt,
	TextSize = 12,
	Font = Enum.Font.GothamMedium,
	TextXAlignment = Enum.TextXAlignment.Left,
}, header)

local syncPill = mk("TextLabel", {
	Size = UDim2.fromOffset(96, 14),
	Position = UDim2.new(1, -158, 0, 13),
	BackgroundTransparency = 1,
	Text = "sync desligado",
	TextColor3 = T.faint,
	TextSize = 10,
	Font = Enum.Font.Gotham,
	TextXAlignment = Enum.TextXAlignment.Right,
}, header)

-- cartao de hover dos icones
local hoverCard = mk("Frame", {
	Size = UDim2.fromOffset(212, 54),
	Position = UDim2.new(1, -220, 0, HEADER_H + 4),
	BackgroundColor3 = T.raised,
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 60,
}, root)
round(hoverCard, 3)
stroke(hoverCard, T.line2)

local cardIcon = mk("ImageLabel", {
	Size = UDim2.fromOffset(32, 32),
	Position = UDim2.fromOffset(10, 11),
	BackgroundColor3 = T.active,
	BorderSizePixel = 0,
	ZIndex = 61,
}, hoverCard)
round(cardIcon, 16)

local cardTitle = mk("TextLabel", {
	Size = UDim2.new(1, -56, 0, 13),
	Position = UDim2.fromOffset(50, 11),
	BackgroundTransparency = 1,
	TextColor3 = T.txt,
	TextSize = 11,
	Font = Enum.Font.GothamMedium,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 61,
}, hoverCard)

local cardSub = mk("TextLabel", {
	Size = UDim2.new(1, -58, 0, 26),
	Position = UDim2.fromOffset(50, 24),
	BackgroundTransparency = 1,
	TextColor3 = T.dim,
	TextSize = 10,
	Font = Enum.Font.Gotham,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	TextWrapped = true,
	ZIndex = 61,
}, hoverCard)

local function showCard(title, sub, image)
	cardTitle.Text = title
	cardSub.Text = sub
	cardIcon.Image = image or ""
	hoverCard.Position = UDim2.new(1, -220, 0, HEADER_H + 1)
	hoverCard.Visible = true
	TweenService:Create(hoverCard, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(1, -220, 0, HEADER_H + 4),
	}):Play()
end

local function hideCard()
	hoverCard.Visible = false
end

local function openUrl(url)
	local ok = pcall(function() GuiService:OpenBrowserWindow(url) end)
	if not ok then warn("[FigmaToRoblox] Nao consegui abrir: " .. url) end
end

--- Botao de icone 24x24 no cabecalho. Sem SVG: o glifo/forma vai por dentro.
local function headerIcon(fromRight, title, sub, url, getImage)
	local button = mk("TextButton", {
		Size = UDim2.fromOffset(24, 24),
		Position = UDim2.new(1, -fromRight, 0, 8),
		BackgroundTransparency = 1,
		Text = "",
		BorderSizePixel = 0,
		AutoButtonColor = false,
	}, header)
	round(button, 3)

	button.MouseEnter:Connect(function()
		button.BackgroundTransparency = 0
		button.BackgroundColor3 = T.hover
		showCard(title, sub, getImage and getImage() or "")
	end)
	button.MouseLeave:Connect(function()
		button.BackgroundTransparency = 1
		hideCard()
	end)
	button.MouseButton1Click:Connect(function() openUrl(url) end)
	return button
end

-- YouTube: retangulo arredondado com um triangulo de play dentro
local ytButton = headerIcon(62, "Tutorial", "Como usar o plugin, do Figma ao Studio.", YOUTUBE_URL)
local ytShape = mk("Frame", {
	Size = UDim2.fromOffset(15, 11),
	Position = UDim2.fromOffset(4, 6),
	BackgroundColor3 = T.dim,
	BorderSizePixel = 0,
}, ytButton)
round(ytShape, 3)
mk("TextLabel", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Text = "\226\150\182",
	TextColor3 = T.raised,
	TextSize = 7,
	Font = Enum.Font.GothamBold,
}, ytShape)

-- Roblox: quadrado inclinado 14 graus, contorno, miolo vazado
local rbxButton = headerIcon(34, AUTHOR_NAME, "Criador do plugin. Clique para ver o perfil.", PROFILE_URL,
	function() return Plugin:GetSetting("avatarUrl") or "" end)
local rbxOuter = mk("Frame", {
	Size = UDim2.fromOffset(13, 13),
	Position = UDim2.fromOffset(5, 5),
	BackgroundTransparency = 1,
	Rotation = 14,
	BorderSizePixel = 0,
}, rbxButton)
round(rbxOuter, 2)
stroke(rbxOuter, T.dim, 1.5)
mk("Frame", {
	Size = UDim2.fromOffset(4, 4),
	Position = UDim2.fromOffset(4.5, 4.5),
	BackgroundColor3 = T.dim,
	BorderSizePixel = 0,
}, rbxOuter)

task.spawn(function()
	if Plugin:GetSetting("avatarUrl") then return end
	local ok, url = pcall(function()
		return Players:GetUserThumbnailAsync(
			AUTHOR_USER_ID, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
	end)
	if ok and url then Plugin:SetSetting("avatarUrl", url) end
end)

-- -------------------------------------------------------------------- abas
-- Pilulas com icone, sem sublinhado e sem fio embaixo: a aba ativa se distingue
-- pelo proprio fundo arredondado, que e mais legivel que um traco de 2px e nao
-- deixa a barra com cara de tabela.
local tabBar = mk("Frame", {
	Size = UDim2.new(1, 0, 0, TABS_H),
	Position = UDim2.fromOffset(0, HEADER_H),
	BackgroundColor3 = T.bg,
	BorderSizePixel = 0,
}, root)
mk("UIPadding", {
	PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6),
	PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 4),
}, tabBar)
mk("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 3),
	VerticalAlignment = Enum.VerticalAlignment.Center,
}, tabBar)

local pagesHolder = mk("Frame", {
	Size = UDim2.new(1, 0, 1, -(HEADER_H + TABS_H + STATUS_H)),
	Position = UDim2.fromOffset(0, HEADER_H + TABS_H),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
}, root)

local TAB_DEFS = {
	{ id = "import",  label = "Importar", icon = "rbxassetid://9405930424" },
	{ id = "pre",     label = "Scripts",  icon = "rbxassetid://9405930424" },
	{ id = "adjust",  label = "Ajustes",  icon = "rbxassetid://13300915301" },
	{ id = "exports", label = "Exports",  icon = "rbxassetid://92120094205063" },
	{ id = "config",  label = "Config",   icon = "rbxassetid://87350324375899" },
}

local pages, tabButtons, activeTab = {}, {}, nil

local function makePage(id)
	local page = mk("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = T.line2,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Visible = false,
	}, pagesHolder)

	mk("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, page)

	local order = 0
	local api = { frame = page, next = function() order += 1; return order end }
	pages[id] = api
	return api
end

for _, def in ipairs(TAB_DEFS) do makePage(def.id) end

-- Guarda as partes de cada pilula para pintar sem procurar filhos na hora.
local tabParts = {}

local function selectTab(index)
	if activeTab == index then return end
	activeTab = index

	for position, def in ipairs(TAB_DEFS) do
		local on = position == index
		pages[def.id].frame.Visible = on

		local part = tabParts[position]
		TweenService:Create(part.pill, TweenInfo.new(0.14, Enum.EasingStyle.Quad), {
			BackgroundColor3 = on and T.accent or T.raised,
			BackgroundTransparency = on and 0 or 1,
		}):Play()
		TweenService:Create(part.label, TweenInfo.new(0.14), {
			TextColor3 = on and T.onAccent or T.faint,
		}):Play()
		TweenService:Create(part.icon, TweenInfo.new(0.14), {
			ImageColor3 = on and T.onAccent or T.faint,
		}):Play()
		part.label.Font = on and Enum.Font.GothamMedium or Enum.Font.Gotham
	end
end

for position, def in ipairs(TAB_DEFS) do
	-- Divide o espaco igualmente; a pilula ocupa a celula inteira menos o gap.
	local pill = mk("TextButton", {
		Size = UDim2.new(1 / #TAB_DEFS, -3, 1, 0),
		BackgroundColor3 = T.raised,
		BackgroundTransparency = 1,
		Text = "",
		BorderSizePixel = 0,
		AutoButtonColor = false,
		LayoutOrder = position,
	}, tabBar)
	round(pill, 999) -- raio alto = pilula, independente da altura

	-- Icone e rotulo entram juntos e centralizados: com 5 abas num painel
	-- estreito, alinhar a esquerda deixaria o conjunto torto.
	mk("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 4),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	}, pill)

	local icon = mk("ImageLabel", {
		Size = UDim2.fromOffset(12, 12),
		BackgroundTransparency = 1,
		Image = def.icon,
		ImageColor3 = T.faint,
		ScaleType = Enum.ScaleType.Fit,
		LayoutOrder = 1,
	}, pill)

	local label = mk("TextLabel", {
		Size = UDim2.fromOffset(0, 14),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Text = def.label,
		TextColor3 = T.faint,
		TextSize = 10,
		Font = Enum.Font.Gotham,
		LayoutOrder = 2,
	}, pill)

	tabParts[position] = { pill = pill, icon = icon, label = label }
	tabButtons[position] = pill

	pill.MouseButton1Click:Connect(function() selectTab(position) end)
	pill.MouseEnter:Connect(function()
		if activeTab == position then return end
		pill.BackgroundTransparency = 0
		pill.BackgroundColor3 = T.hover
		label.TextColor3 = T.dim
		icon.ImageColor3 = T.dim
	end)
	pill.MouseLeave:Connect(function()
		if activeTab == position then return end
		pill.BackgroundTransparency = 1
		label.TextColor3 = T.faint
		icon.ImageColor3 = T.faint
	end)
end

-- ------------------------------------------------------ primitivas de linha
--- Cabecalho de grupo: 26px, texto discreto, fio embaixo. `trailing` mostra
--- contagem a direita (ex: "2 ativos").
local function groupHead(page, text)
	local frame = mk("Frame", {
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundColor3 = T.bg,
		BorderSizePixel = 0,
		LayoutOrder = page.next(),
	}, page.frame)
	hairline(frame, true)

	mk("TextLabel", {
		Size = UDim2.new(1, -GUTTER * 2 - 70, 1, 0),
		Position = UDim2.fromOffset(GUTTER, 0),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = T.dim,
		TextSize = 10,
		Font = Enum.Font.GothamMedium,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, frame)

	local trailing = mk("TextLabel", {
		Size = UDim2.new(0, 70, 1, 0),
		Position = UDim2.new(1, -GUTTER - 70, 0, 0),
		BackgroundTransparency = 1,
		Text = "",
		TextColor3 = T.faint,
		TextSize = 10,
		Font = Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, frame)

	return frame, trailing
end

--- A primitiva. Devolve (row, ctl) — `ctl` e a area a direita onde o controle
--- entra, alinhada numa coluna consistente.
local function propRow(page, label, sub, height)
	local h = height or ROW_H
	local row = mk("Frame", {
		Size = UDim2.new(1, 0, 0, h),
		BackgroundColor3 = T.bg,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = page and page.next() or 1,
	}, page and page.frame or nil)
	hairline(row, true)

	if label then
		mk("TextLabel", {
			Size = UDim2.new(1, -GUTTER * 2 - 110, 0, sub and 13 or h),
			Position = UDim2.fromOffset(GUTTER, sub and 4 or 0),
			BackgroundTransparency = 1,
			Text = label,
			TextColor3 = T.txt,
			TextSize = 11,
			Font = Enum.Font.Gotham,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, row)
	end

	if sub then
		mk("TextLabel", {
			Size = UDim2.new(1, -GUTTER * 2 - 110, 0, 12),
			Position = UDim2.fromOffset(GUTTER, 15),
			BackgroundTransparency = 1,
			Text = sub,
			TextColor3 = T.faint,
			TextSize = 10,
			Font = Enum.Font.Gotham,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, row)
	end

	local ctl = mk("Frame", {
		Size = UDim2.fromOffset(104, h),
		Position = UDim2.new(1, -GUTTER - 104, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, row)

	return row, ctl
end

--- Linha inteira clicavel, com realce no hover. Usada por interruptor e
--- caixa de marcar: o alvo e a linha, nao um quadradinho de 13px.
local function clickableRow(row)
	local hit = mk("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		BorderSizePixel = 0,
		AutoButtonColor = false,
		ZIndex = 5,
	}, row)

	hit.MouseEnter:Connect(function()
		row.BackgroundTransparency = 0
		row.BackgroundColor3 = T.hover
	end)
	hit.MouseLeave:Connect(function()
		row.BackgroundTransparency = 1
	end)

	return hit
end

--- Interruptor 26x14 dentro da coluna de controle.
local function switchIn(ctl)
	local track = mk("Frame", {
		Size = UDim2.fromOffset(26, 14),
		Position = UDim2.new(1, -26, 0.5, -7),
		BackgroundColor3 = T.active,
		BorderSizePixel = 0,
	}, ctl)
	round(track, 7)

	local knob = mk("Frame", {
		Size = UDim2.fromOffset(10, 10),
		Position = UDim2.fromOffset(2, 2),
		BackgroundColor3 = T.faint,
		BorderSizePixel = 0,
	}, track)
	round(knob, 5)

	return track, knob
end

--- Campo de texto na coluna de controle (ou largura cheia se `full`).
local function fieldIn(parent, placeholder, initial, mono, full)
	local input = mk("TextBox", {
		Size = full and UDim2.new(1, -GUTTER * 2, 0, 22) or UDim2.new(1, 0, 0, 22),
		Position = full and UDim2.fromOffset(GUTTER, 0) or UDim2.new(0, 0, 0.5, -11),
		BackgroundColor3 = T.raised,
		Text = initial or "",
		PlaceholderText = placeholder or "",
		PlaceholderColor3 = T.faint,
		TextColor3 = T.txt,
		TextSize = mono and 10 or 11,
		Font = mono and Enum.Font.Code or Enum.Font.Gotham,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, parent)
	round(input, 3)
	stroke(input, T.line2)
	mk("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, input)

	-- Foco em azul: o unico feedback de foco desta interface.
	local ring = input:FindFirstChildOfClass("UIStroke")
	input.Focused:Connect(function() if ring then ring.Color = T.accent end end)
	input.FocusLost:Connect(function() if ring then ring.Color = T.line2 end end)

	return input
end

--- Botao pequeno de 22px, estilo "mini" — para acoes dentro de linha.
local function miniButton(parent, text, width)
	local button = mk("TextButton", {
		Size = UDim2.fromOffset(width or 62, 22),
		Position = UDim2.new(1, -(width or 62), 0.5, -11),
		BackgroundColor3 = T.raised,
		Text = text,
		TextColor3 = T.dim,
		TextSize = 10,
		Font = Enum.Font.Gotham,
		BorderSizePixel = 0,
		AutoButtonColor = false,
	}, parent)
	round(button, 3)
	stroke(button, T.line2)

	button.MouseEnter:Connect(function()
		button.BackgroundColor3 = T.hover
		button.TextColor3 = T.txt
	end)
	button.MouseLeave:Connect(function()
		button.BackgroundColor3 = T.raised
		button.TextColor3 = T.dim
	end)

	return button
end

--- Acao primaria: 28px, azul cheio, largura total menos as goteiras.
local function primaryButton(page, text)
	local wrap = mk("Frame", {
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = page.next(),
	}, page.frame)

	local button = mk("TextButton", {
		Size = UDim2.new(1, -GUTTER * 2, 0, 28),
		Position = UDim2.fromOffset(GUTTER, 8),
		BackgroundColor3 = T.accent,
		Text = text,
		TextColor3 = T.onAccent,
		TextSize = 11,
		Font = Enum.Font.GothamBold,
		BorderSizePixel = 0,
		AutoButtonColor = false,
	}, wrap)
	round(button, 3)

	return button
end

--- Texto de ajuda em largura cheia, fora da grade de linhas.
local function noteRow(page, text, height)
	local frame = mk("Frame", {
		Size = UDim2.new(1, 0, 0, height or 34),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = page.next(),
	}, page.frame)
	hairline(frame, true)

	local label = mk("TextLabel", {
		Size = UDim2.new(1, -GUTTER * 2, 1, -10),
		Position = UDim2.fromOffset(GUTTER, 5),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = T.faint,
		TextSize = 10,
		Font = Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
	}, frame)

	return label, frame
end

-- ========================================================== ABA: IMPORTAR ==
local importPage = pages.import

groupHead(importPage, "Importar do servidor")

local _, idCtl = propRow(importPage, "ID do export", nil, 34)
local idInput = fieldIn(idCtl, "cole o ID do Figma", "", true)

local importBtn = primaryButton(importPage, "Importar")

groupHead(importPage, "Comportamento")

local syncRow, syncCtl = propRow(importPage, "Sincronizacao automatica", "Importa ao exportar no Figma", 40)
local switchTrack, switchKnob = switchIn(syncCtl)
local syncHit = clickableRow(syncRow)

local scaleRow, scaleCtl = propRow(importPage, "Escala responsiva", "Adiciona UIScale + script", 40)
local scaleTrack, scaleKnob = switchIn(scaleCtl)
local scaleHit = clickableRow(scaleRow)

-- ======================================================= ABA: PRE-SCRIPTS ==
local prePage = pages.pre

local _, preHeadCount = groupHead(prePage, "Sistemas")

local preSelected = {}
local preRows = {}

--- Linha de 28px com caixa de marcar de 13px na coluna de controle. A linha
--- inteira e o alvo do clique.
local function checkRow(page, key, label, hint)
	local row, ctl = propRow(page, label, hint, 34)

	local box = mk("Frame", {
		Size = UDim2.fromOffset(13, 13),
		Position = UDim2.new(1, -13, 0.5, -6),
		BackgroundColor3 = T.raised,
		BorderSizePixel = 0,
	}, ctl)
	round(box, 2)
	local boxStroke = stroke(box, T.line2)

	local tick = mk("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "\226\156\147",
		TextColor3 = T.onAccent,
		TextSize = 9,
		Font = Enum.Font.GothamBold,
		Visible = false,
	}, box)

	local hit = clickableRow(row)
	preRows[key] = { row = row, box = box, tick = tick, stroke = boxStroke, hit = hit }
	return row
end

for _, system in ipairs(PreScripts.SYSTEMS) do
	checkRow(prePage, system.key, system.label, system.hint)
end

local _, paramHead = groupHead(prePage, "Parametros")

local questionRows = {}

for _, question in ipairs(PreScripts.QUESTIONS) do
	local row, ctl = propRow(prePage, question.label, nil, ROW_H)
	row.Visible = false

	local input = mk("TextBox", {
		Size = UDim2.fromOffset(52, 20),
		Position = UDim2.new(1, -52, 0.5, -10),
		BackgroundColor3 = T.raised,
		Text = tostring(question.default),
		TextColor3 = T.txt,
		TextSize = 10,
		Font = Enum.Font.Code,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Center,
	}, ctl)
	round(input, 3)
	local ring = stroke(input, T.line2)
	input.Focused:Connect(function() ring.Color = T.accent end)
	input.FocusLost:Connect(function() ring.Color = T.line2 end)

	questionRows[question.key] = {
		row = row, input = input,
		requires = question.requires, default = question.default,
	}
end

-- O frame, nao o label: esconder so o texto deixaria a faixa de 26px vazia.
local _, noParams = noteRow(prePage, "Nenhum sistema marcado — nada sera gerado.", 26)

local _, bindHead = groupHead(prePage, "Vinculos")

noteRow(prePage,
	"O que o plugin achou na sua UI. Onde faltar, selecione o elemento no " ..
	"Explorer e clique em apontar.", 36)

local _, detectCtl = propRow(prePage, "Referencia", nil, 34)
local bindTarget = miniButton(detectCtl, "detectar", 76)

local bindHolder = mk("Frame", {
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	LayoutOrder = prePage.next(),
}, prePage.frame)
mk("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, bindHolder)

local _, bindEmpty = noteRow(prePage, "Marque um sistema e clique em detectar.", 26)

local generateBtn = primaryButton(prePage, "Gerar Pre-Scripts")

-- Funcao propria, nao bloco do..end: o Luau limita a 200 locais VIVOS por
-- funcao, e um bloco no topo NAO ajuda, porque os locais dele somam aos de
-- topo ate o bloco fechar. Uma funcao ganha os proprios 200 registradores;
-- o que vem de fora entra como upvalue.
local function buildAdjustPanel()
	-- =========================================================== ABA: AJUSTES ==
	-- Painel de transformacao. Age sobre o que esta selecionado no Explorer, em
	-- tempo real e com Ctrl+Z. Fica aqui, e nao no plugin do Figma, porque so aqui
	-- existe o Instance de verdade — no Figma o efeito seria invisivel ate exportar.
	--
	-- Este bloco e autossuficiente de proposito: nao usa setStatus nem nada da
	-- secao de comportamento, entao nao depende da ordem de declaracao do arquivo.
	-- ============================================================================
	local adjustPage = pages.adjust

	local selected = {}        -- GuiObjects atualmente selecionados
	local stepValue = 1        -- incremento de mover/redimensionar
	local expandBoth = false   -- redimensionar cresce dos dois lados
	local suppress = false     -- evita que preencher os campos dispare aplicacao
	local refreshFields        -- declarado aqui: os pads chamam antes da definicao

	--- Propriedades copiadas ao trocar de classe. pcall por item: o que a classe
	--- de destino nao tiver e simplesmente ignorado.
	local CARRY_PROPS = {
		"Size", "Position", "AnchorPoint", "Rotation", "ZIndex", "LayoutOrder",
		"Visible", "BackgroundColor3", "BackgroundTransparency", "BorderSizePixel",
		"BorderColor3", "ClipsDescendants", "AutomaticSize", "Active", "Selectable",
		"Text", "TextSize", "TextColor3", "TextTransparency", "TextWrapped",
		"TextXAlignment", "TextYAlignment", "RichText", "FontFace",
		"Image", "ImageColor3", "ImageTransparency", "ScaleType", "SliceCenter",
	}

	local CONVERT_CLASSES = {
		"Frame", "ScrollingFrame", "CanvasGroup",
		"TextLabel", "TextButton", "TextBox",
		"ImageLabel", "ImageButton", "ViewportFrame", "VideoFrame",
	}

	local MODIFIER_CLASSES = {
		"UICorner", "UIStroke", "UIGradient", "UIPadding",
		"UIListLayout", "UIGridLayout", "UITableLayout",
		"UIScale", "UIAspectRatioConstraint", "UISizeConstraint", "UIFlexItem",
	}

	-- ---------------------------------------------------------------- log ------
	local logLines = {}
	local logHolder

	local function logLine(text, kind)
		if not logHolder then return end

		local stamp = os.date("%H:%M:%S")
		local entry = mk("TextLabel", {
			Size = UDim2.new(1, -GUTTER * 2, 0, 13),
			Position = UDim2.fromOffset(GUTTER, 0),
			BackgroundTransparency = 1,
			Text = stamp .. "  " .. text,
			TextColor3 = (kind == "err" and T.err) or (kind == "ok" and T.ok) or T.faint,
			TextSize = 9,
			Font = Enum.Font.Code,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			LayoutOrder = #logLines + 1,
		}, logHolder)

		table.insert(logLines, entry)

		-- Teto de 40 linhas: um log que cresce sem limite vira vazamento.
		while #logLines > 40 do
			logLines[1]:Destroy()
			table.remove(logLines, 1)
		end
	end

	--- Envolve uma mutacao num passo de undo. Sem isso, Ctrl+Z nao desfaz nada do
	--- que o painel faz — e o usuario perde confianca em mexer.
	local function withUndo(label, fn)
		local recording = ChangeHistoryService:TryBeginRecording("FigmaAdjust", label)
		local ok, err = pcall(fn)
		if recording then
			ChangeHistoryService:FinishRecording(
				recording,
				ok and Enum.FinishRecordingOperation.Commit or Enum.FinishRecordingOperation.Cancel
			)
		end
		if not ok then logLine(label .. ": " .. tostring(err), "err") end
		return ok
	end

	-- ------------------------------------------------------ grupos recolhiveis --
	--- Cabecalho clicavel que mostra/esconde o proprio conteudo. Devolve o frame
	--- de conteudo, onde as linhas do grupo entram.
	local function collapsible(page, title, startOpen)
		local header = mk("TextButton", {
			Size = UDim2.new(1, 0, 0, 26),
			BackgroundColor3 = T.bg,
			Text = "",
			BorderSizePixel = 0,
			AutoButtonColor = false,
			LayoutOrder = page.next(),
		}, page.frame)
		hairline(header, true)

		local chevron = mk("TextLabel", {
			Size = UDim2.fromOffset(12, 26),
			Position = UDim2.fromOffset(GUTTER, 0),
			BackgroundTransparency = 1,
			Text = "\226\150\184",
			TextColor3 = T.faint,
			TextSize = 8,
			Font = Enum.Font.Gotham,
			Rotation = startOpen ~= false and 90 or 0,
		}, header)

		mk("TextLabel", {
			Size = UDim2.new(1, -GUTTER * 2 - 18, 1, 0),
			Position = UDim2.fromOffset(GUTTER + 16, 0),
			BackgroundTransparency = 1,
			Text = title,
			TextColor3 = T.dim,
			TextSize = 10,
			Font = Enum.Font.GothamMedium,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, header)

		local content = mk("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Visible = startOpen ~= false,
			LayoutOrder = page.next(),
		}, page.frame)
		mk("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, content)

		local open = startOpen ~= false
		header.MouseButton1Click:Connect(function()
			open = not open
			content.Visible = open
			TweenService:Create(chevron, TweenInfo.new(0.12, Enum.EasingStyle.Quad), {
				Rotation = open and 90 or 0,
			}):Play()
		end)
		header.MouseEnter:Connect(function() header.BackgroundColor3 = T.hover end)
		header.MouseLeave:Connect(function() header.BackgroundColor3 = T.bg end)

		local order = 0
		return { frame = content, header = header, next = function() order += 1; return order end }
	end

	-- -------------------------------------------------------------- campos -----
	--- Campo numerico. `apply(instancia, numero)` roda para cada selecionado.
	local function numberField(parent, label, offsetX, width, apply)
		if label then
			mk("TextLabel", {
				Size = UDim2.fromOffset(13, 22),
				Position = UDim2.fromOffset(offsetX, 0),
				BackgroundTransparency = 1,
				Text = label,
				TextColor3 = T.faint,
				TextSize = 10,
				Font = Enum.Font.Gotham,
			}, parent)
		end

		local input = mk("TextBox", {
			Size = UDim2.fromOffset(width, 22),
			Position = UDim2.fromOffset(offsetX + (label and 14 or 0), 0),
			BackgroundColor3 = T.raised,
			Text = "",
			PlaceholderText = "—",
			PlaceholderColor3 = T.faint,
			TextColor3 = T.txt,
			TextSize = 10,
			Font = Enum.Font.Code,
			BorderSizePixel = 0,
			ClearTextOnFocus = false,
			TextXAlignment = Enum.TextXAlignment.Center,
		}, parent)
		round(input, 3)
		local ring = stroke(input, T.line2)

		input.Focused:Connect(function() ring.Color = T.accent end)
		input.FocusLost:Connect(function()
			ring.Color = T.line2
			if suppress then return end

			local value = tonumber(input.Text)
			if not value then return end

			withUndo("Editar " .. (label or "valor"), function()
				for _, inst in ipairs(selected) do apply(inst, value) end
			end)
		end)

		return input
	end

	--- Interruptor numa linha de propriedade, ligado a uma propriedade booleana.
	local function boolField(page, title, apply, read)
		local row, ctl = propRow(page, title, nil, ROW_H)
		local track, knob = switchIn(ctl)
		local hit = clickableRow(row)
		local value = false

		local function paint(on)
			value = on
			TweenService:Create(track, TweenInfo.new(0.13), {
				BackgroundColor3 = on and T.accent or T.active,
			}):Play()
			TweenService:Create(knob, TweenInfo.new(0.13), {
				Position = on and UDim2.fromOffset(14, 2) or UDim2.fromOffset(2, 2),
				BackgroundColor3 = on and T.onAccent or T.faint,
			}):Play()
		end

		hit.MouseButton1Click:Connect(function()
			if #selected == 0 then return end
			paint(not value)
			withUndo(title, function()
				for _, inst in ipairs(selected) do apply(inst, value) end
			end)
		end)

		return { paint = paint, read = read }
	end

	--- Cor em R/G/B com amostra ao lado. Nao existe seletor de cor para plugins,
	--- entao campos numericos sao o controle preciso disponivel.
	local function colorField(page, title, get, set)
		local row = mk("Frame", {
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			LayoutOrder = page.next(),
		}, page.frame)
		hairline(row, true)

		mk("TextLabel", {
			Size = UDim2.fromOffset(100, 30),
			Position = UDim2.fromOffset(GUTTER, 0),
			BackgroundTransparency = 1,
			Text = title,
			TextColor3 = T.txt,
			TextSize = 11,
			Font = Enum.Font.Gotham,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, row)

		local swatch = mk("Frame", {
			Size = UDim2.fromOffset(18, 18),
			Position = UDim2.new(1, -GUTTER - 138, 0, 6),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
		}, row)
		round(swatch, 3)
		stroke(swatch, T.line2)

		local wrap = mk("Frame", {
			Size = UDim2.fromOffset(114, 22),
			Position = UDim2.new(1, -GUTTER - 114, 0, 4),
			BackgroundTransparency = 1,
		}, row)

		local inputs = {}
		local function applyChannel()
			if suppress or #selected == 0 then return end
			local r = math.clamp(tonumber(inputs[1].Text) or 0, 0, 255)
			local g = math.clamp(tonumber(inputs[2].Text) or 0, 0, 255)
			local b = math.clamp(tonumber(inputs[3].Text) or 0, 0, 255)
			local color = Color3.fromRGB(r, g, b)
			swatch.BackgroundColor3 = color

			withUndo(title, function()
				for _, inst in ipairs(selected) do set(inst, color) end
			end)
		end

		for i = 1, 3 do
			local input = mk("TextBox", {
				Size = UDim2.fromOffset(34, 22),
				Position = UDim2.fromOffset((i - 1) * 40, 0),
				BackgroundColor3 = T.raised,
				Text = "",
				PlaceholderText = "—",
				PlaceholderColor3 = T.faint,
				TextColor3 = T.txt,
				TextSize = 10,
				Font = Enum.Font.Code,
				BorderSizePixel = 0,
				ClearTextOnFocus = false,
				TextXAlignment = Enum.TextXAlignment.Center,
			}, wrap)
			round(input, 3)
			local ring = stroke(input, T.line2)
			input.Focused:Connect(function() ring.Color = T.accent end)
			input.FocusLost:Connect(function() ring.Color = T.line2; applyChannel() end)
			inputs[i] = input
		end

		return {
			row = row,
			paint = function(color)
				if not color then
					inputs[1].Text = ""; inputs[2].Text = ""; inputs[3].Text = ""
					return
				end
				swatch.BackgroundColor3 = color
				inputs[1].Text = tostring(math.floor(color.R * 255 + 0.5))
				inputs[2].Text = tostring(math.floor(color.G * 255 + 0.5))
				inputs[3].Text = tostring(math.floor(color.B * 255 + 0.5))
			end,
			get = get,
		}
	end

	-- =========================================================== construcao =====
	local adjustHint = noteRow(adjustPage, "Selecione um elemento de UI no Explorer.", 26)

	-- ------------------------------------------------------------ transformar --
	local gTransform = collapsible(adjustPage, "Transformar", true)

	local geomRow = mk("Frame", {
		Size = UDim2.new(1, 0, 0, 60),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = gTransform.next(),
	}, gTransform.frame)
	hairline(geomRow, true)

	local xyWrap = mk("Frame", {
		Size = UDim2.new(1, -GUTTER * 2, 0, 22),
		Position = UDim2.fromOffset(GUTTER, 6),
		BackgroundTransparency = 1,
	}, geomRow)
	local fieldX = numberField(xyWrap, "X", 0, 54, function(i, v)
		i.Position = UDim2.new(i.Position.X.Scale, v, i.Position.Y.Scale, i.Position.Y.Offset)
	end)
	local fieldY = numberField(xyWrap, "Y", 82, 54, function(i, v)
		i.Position = UDim2.new(i.Position.X.Scale, i.Position.X.Offset, i.Position.Y.Scale, v)
	end)

	local whWrap = mk("Frame", {
		Size = UDim2.new(1, -GUTTER * 2, 0, 22),
		Position = UDim2.fromOffset(GUTTER, 32),
		BackgroundTransparency = 1,
	}, geomRow)
	local fieldW = numberField(whWrap, "L", 0, 54, function(i, v)
		i.Size = UDim2.new(i.Size.X.Scale, math.max(0, v), i.Size.Y.Scale, i.Size.Y.Offset)
	end)
	local fieldH = numberField(whWrap, "A", 82, 54, function(i, v)
		i.Size = UDim2.new(i.Size.X.Scale, i.Size.X.Offset, i.Size.Y.Scale, math.max(0, v))
	end)

	local rotRow = mk("Frame", {
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = gTransform.next(),
	}, gTransform.frame)
	hairline(rotRow, true)

	local rotWrap = mk("Frame", {
		Size = UDim2.new(1, -GUTTER * 2, 0, 22),
		Position = UDim2.fromOffset(GUTTER, 6),
		BackgroundTransparency = 1,
	}, rotRow)
	local fieldRot = numberField(rotWrap, "\194\176", 0, 54, function(i, v) i.Rotation = v end)
	local fieldZ = numberField(rotWrap, "Z", 82, 54, function(i, v) i.ZIndex = math.floor(v) end)

	local anchorRow = mk("Frame", {
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = gTransform.next(),
	}, gTransform.frame)
	hairline(anchorRow, true)

	mk("TextLabel", {
		Size = UDim2.fromOffset(90, 22),
		Position = UDim2.fromOffset(GUTTER, 6),
		BackgroundTransparency = 1,
		Text = "AnchorPoint",
		TextColor3 = T.txt,
		TextSize = 11,
		Font = Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, anchorRow)

	local anchorWrap = mk("Frame", {
		Size = UDim2.fromOffset(114, 22),
		Position = UDim2.new(1, -GUTTER - 114, 0, 6),
		BackgroundTransparency = 1,
	}, anchorRow)
	local fieldAX = numberField(anchorWrap, nil, 0, 54, function(i, v)
		i.AnchorPoint = Vector2.new(math.clamp(v, 0, 1), i.AnchorPoint.Y)
	end)
	local fieldAY = numberField(anchorWrap, nil, 60, 54, function(i, v)
		i.AnchorPoint = Vector2.new(i.AnchorPoint.X, math.clamp(v, 0, 1))
	end)

	-- --------------------------------------------------------------- aparencia --
	local gLook = collapsible(adjustPage, "Aparencia", true)

	local ctlVisible = boolField(gLook, "Visible",
		function(i, v) i.Visible = v end,
		nil)

	local ctlAuto = boolField(gLook, "AutomaticSize (XY)",
		function(i, v) i.AutomaticSize = v and Enum.AutomaticSize.XY or Enum.AutomaticSize.None end,
		nil)

	local bgTransRow = mk("Frame", {
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = gLook.next(),
	}, gLook.frame)
	hairline(bgTransRow, true)
	mk("TextLabel", {
		Size = UDim2.fromOffset(150, 30),
		Position = UDim2.fromOffset(GUTTER, 0),
		BackgroundTransparency = 1,
		Text = "BackgroundTransparency",
		TextColor3 = T.txt,
		TextSize = 11,
		Font = Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, bgTransRow)
	local bgTransWrap = mk("Frame", {
		Size = UDim2.fromOffset(54, 22),
		Position = UDim2.new(1, -GUTTER - 54, 0, 4),
		BackgroundTransparency = 1,
	}, bgTransRow)
	local fieldBgT = numberField(bgTransWrap, nil, 0, 54, function(i, v)
		i.BackgroundTransparency = math.clamp(v, 0, 1)
	end)

	local ctlBgColor = colorField(gLook, "BackgroundColor3",
		nil,
		function(i, c) i.BackgroundColor3 = c end)

	-- ------------------------------------------------------------------ texto ---
	local gText = collapsible(adjustPage, "Texto", false)

	local textSizeRow = mk("Frame", {
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = gText.next(),
	}, gText.frame)
	hairline(textSizeRow, true)
	mk("TextLabel", {
		Size = UDim2.fromOffset(100, 30),
		Position = UDim2.fromOffset(GUTTER, 0),
		BackgroundTransparency = 1,
		Text = "TextSize",
		TextColor3 = T.txt,
		TextSize = 11,
		Font = Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, textSizeRow)
	local textSizeWrap = mk("Frame", {
		Size = UDim2.fromOffset(54, 22),
		Position = UDim2.new(1, -GUTTER - 54, 0, 4),
		BackgroundTransparency = 1,
	}, textSizeRow)
	local fieldTextSize = numberField(textSizeWrap, nil, 0, 54, function(i, v)
		if i:IsA("TextLabel") or i:IsA("TextButton") or i:IsA("TextBox") then
			i.TextSize = math.max(1, math.floor(v))
		end
	end)

	local ctlTextColor = colorField(gText, "TextColor3",
		nil,
		function(i, c)
			if i:IsA("TextLabel") or i:IsA("TextButton") or i:IsA("TextBox") then i.TextColor3 = c end
		end)

	-- ----------------------------------------------------------------- imagem ---
	local gImage = collapsible(adjustPage, "Imagem", false)

	local imgTransRow = mk("Frame", {
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = gImage.next(),
	}, gImage.frame)
	hairline(imgTransRow, true)
	mk("TextLabel", {
		Size = UDim2.fromOffset(140, 30),
		Position = UDim2.fromOffset(GUTTER, 0),
		BackgroundTransparency = 1,
		Text = "ImageTransparency",
		TextColor3 = T.txt,
		TextSize = 11,
		Font = Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, imgTransRow)
	local imgTransWrap = mk("Frame", {
		Size = UDim2.fromOffset(54, 22),
		Position = UDim2.new(1, -GUTTER - 54, 0, 4),
		BackgroundTransparency = 1,
	}, imgTransRow)
	local fieldImgT = numberField(imgTransWrap, nil, 0, 54, function(i, v)
		if i:IsA("ImageLabel") or i:IsA("ImageButton") then
			i.ImageTransparency = math.clamp(v, 0, 1)
		end
	end)

	local ctlImgColor = colorField(gImage, "ImageColor3",
		nil,
		function(i, c)
			if i:IsA("ImageLabel") or i:IsA("ImageButton") then i.ImageColor3 = c end
		end)

	-- -------------------------------------------------- passo, mover, tamanho ---
	local gNudge = collapsible(adjustPage, "Mover e redimensionar", true)

	local stepRow, stepCtl = propRow(gNudge, "Passo", nil, ROW_H)
	local stepButtons = {}
	local stepWrap = mk("Frame", {
		Size = UDim2.fromOffset(130, 20),
		Position = UDim2.new(1, -130, 0.5, -10),
		BackgroundTransparency = 1,
	}, stepCtl)

	local function paintStep()
		for _, entry in ipairs(stepButtons) do
			local on = entry.value == stepValue
			entry.button.BackgroundColor3 = on and T.accent or T.raised
			entry.button.TextColor3 = on and T.onAccent or T.dim
		end
	end

	for index, value in ipairs({ 1, 2, 4, 8, 16 }) do
		local button = mk("TextButton", {
			Size = UDim2.fromOffset(24, 20),
			Position = UDim2.fromOffset((index - 1) * 26, 0),
			BackgroundColor3 = T.raised,
			Text = tostring(value),
			TextColor3 = T.dim,
			TextSize = 10,
			Font = Enum.Font.Code,
			BorderSizePixel = 0,
			AutoButtonColor = false,
		}, stepWrap)
		round(button, 3)
		stroke(button, T.line2)

		button.MouseButton1Click:Connect(function()
			stepValue = value
			paintStep()
			logLine("passo " .. value .. " px")
		end)

		table.insert(stepButtons, { button = button, value = value })
	end
	paintStep()

	local padsRow = mk("Frame", {
		Size = UDim2.new(1, 0, 0, 106),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = gNudge.next(),
	}, gNudge.frame)
	hairline(padsRow, true)

	--- Pad 3x3. O centro nao e seta: no Mover ele centraliza no pai, no
	--- Redimensionar ele ajusta ao conteudo.
	local DIRS = {
		{ -1, -1 }, { 0, -1 }, { 1, -1 },
		{ -1,  0 }, { 0,  0 }, { 1,  0 },
		{ -1,  1 }, { 0,  1 }, { 1,  1 },
	}
	local GLYPHS = {
		"\226\134\150", "\226\134\145", "\226\134\151",
		"\226\134\144", "\226\151\139", "\226\134\146",
		"\226\134\153", "\226\134\147", "\226\134\152",
	}

	local function directionPad(parent, title, offsetX, onDir, onCenter)
		mk("TextLabel", {
			Size = UDim2.fromOffset(86, 12),
			Position = UDim2.fromOffset(offsetX, 2),
			BackgroundTransparency = 1,
			Text = title,
			TextColor3 = T.faint,
			TextSize = 9,
			Font = Enum.Font.Gotham,
			TextXAlignment = Enum.TextXAlignment.Center,
		}, parent)

		for index, dir in ipairs(DIRS) do
			local col = (index - 1) % 3
			local row = math.floor((index - 1) / 3)
			local isCenter = dir[1] == 0 and dir[2] == 0

			local button = mk("TextButton", {
				Size = UDim2.fromOffset(26, 22),
				Position = UDim2.fromOffset(offsetX + 4 + col * 28, 18 + row * 24),
				BackgroundColor3 = T.raised,
				Text = GLYPHS[index],
				TextColor3 = isCenter and T.faint or T.dim,
				TextSize = 11,
				Font = Enum.Font.Gotham,
				BorderSizePixel = 0,
				AutoButtonColor = false,
			}, parent)
			round(button, 3)
			stroke(button, T.line2)

			button.MouseEnter:Connect(function()
				button.BackgroundColor3 = T.hover
				button.TextColor3 = T.txt
			end)
			button.MouseLeave:Connect(function()
				button.BackgroundColor3 = T.raised
				button.TextColor3 = isCenter and T.faint or T.dim
			end)

			button.MouseButton1Click:Connect(function()
				if #selected == 0 then logLine("nada selecionado", "err") return end
				if isCenter then onCenter() else onDir(dir[1], dir[2]) end
			end)
		end
	end

	directionPad(padsRow, "Mover", GUTTER,
		function(dx, dy)
			withUndo("Mover", function()
				for _, inst in ipairs(selected) do
					inst.Position = UDim2.new(
						inst.Position.X.Scale, inst.Position.X.Offset + dx * stepValue,
						inst.Position.Y.Scale, inst.Position.Y.Offset + dy * stepValue
					)
				end
			end)
			refreshFields()
		end,
		function()
			withUndo("Centralizar", function()
				for _, inst in ipairs(selected) do
					inst.AnchorPoint = Vector2.new(0.5, 0.5)
					inst.Position = UDim2.fromScale(0.5, 0.5)
				end
			end)
			refreshFields()
			logLine("centralizado no pai", "ok")
		end)

	directionPad(padsRow, "Redimensionar", GUTTER + 98,
		function(dx, dy)
			withUndo("Redimensionar", function()
				for _, inst in ipairs(selected) do
					local growX = dx * stepValue
					local growY = dy * stepValue
					local size = inst.Size
					local pos = inst.Position

					-- Crescer para a esquerda/cima significa mover a origem tambem,
					-- senao o elemento cresce sempre para o mesmo lado.
					local newW = math.max(0, size.X.Offset + math.abs(growX) * (growX ~= 0 and 1 or 0))
					local newH = math.max(0, size.Y.Offset + math.abs(growY) * (growY ~= 0 and 1 or 0))

					local shiftX = 0
					local shiftY = 0
					if expandBoth then
						shiftX = -math.abs(growX) / 2
						shiftY = -math.abs(growY) / 2
					elseif growX < 0 then
						shiftX = -math.abs(growX)
					elseif growY < 0 then
						shiftY = -math.abs(growY)
					end

					inst.Size = UDim2.new(size.X.Scale, newW, size.Y.Scale, newH)
					inst.Position = UDim2.new(
						pos.X.Scale, pos.X.Offset + shiftX,
						pos.Y.Scale, pos.Y.Offset + shiftY
					)
				end
			end)
			refreshFields()
		end,
		function()
			withUndo("Ajustar ao conteudo", function()
				for _, inst in ipairs(selected) do
					inst.AutomaticSize = Enum.AutomaticSize.XY
				end
			end)
			refreshFields()
			logLine("AutomaticSize = XY", "ok")
		end)

	local expandRow, expandCtl = propRow(gNudge, "Expandir dos dois lados", nil, ROW_H)
	local expandTrack, expandKnob = switchIn(expandCtl)
	local expandHit = clickableRow(expandRow)

	expandHit.MouseButton1Click:Connect(function()
		expandBoth = not expandBoth
		TweenService:Create(expandTrack, TweenInfo.new(0.13), {
			BackgroundColor3 = expandBoth and T.accent or T.active,
		}):Play()
		TweenService:Create(expandKnob, TweenInfo.new(0.13), {
			Position = expandBoth and UDim2.fromOffset(14, 2) or UDim2.fromOffset(2, 2),
			BackgroundColor3 = expandBoth and T.onAccent or T.faint,
		}):Play()
	end)

	local resetBtn = mk("TextButton", {
		Size = UDim2.new(1, -GUTTER * 2, 0, 26),
		Position = UDim2.fromOffset(GUTTER, 5),
		BackgroundColor3 = T.raised,
		Text = "Redefinir posicao, tamanho, rotacao e ancora",
		TextColor3 = T.dim,
		TextSize = 10,
		Font = Enum.Font.Gotham,
		BorderSizePixel = 0,
		AutoButtonColor = false,
	}, mk("Frame", {
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = gNudge.next(),
	}, gNudge.frame))
	round(resetBtn, 3)
	stroke(resetBtn, T.line2)

	resetBtn.MouseEnter:Connect(function()
		resetBtn.BackgroundColor3 = T.hover
		resetBtn.TextColor3 = T.txt
	end)
	resetBtn.MouseLeave:Connect(function()
		resetBtn.BackgroundColor3 = T.raised
		resetBtn.TextColor3 = T.dim
	end)

	-- ------------------------------------------------------ conversor de classe -
	local gConvert = collapsible(adjustPage, "Converter classe", true)

	local convHint = mk("TextLabel", {
		Size = UDim2.new(1, -GUTTER * 2, 0, 24),
		Position = UDim2.fromOffset(GUTTER, 2),
		BackgroundTransparency = 1,
		Text = "Nenhum GUI selecionado",
		TextColor3 = T.faint,
		TextSize = 9,
		Font = Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
	}, mk("Frame", {
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = gConvert.next(),
	}, gConvert.frame))

	--- Grade de botoes de classe com o icone oficial do Studio.
	local function classGrid(parent, page, list, onPick)
		local wrap = mk("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			LayoutOrder = page.next(),
		}, parent)
		mk("UIPadding", {
			PaddingBottom = UDim.new(0, 8),
			PaddingLeft = UDim.new(0, GUTTER),
			PaddingRight = UDim.new(0, GUTTER),
		}, wrap)
		mk("UIGridLayout", {
			CellSize = UDim2.new(0.5, -3, 0, 24),
			CellPadding = UDim2.fromOffset(6, 4),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, wrap)

		local buttons = {}
		for index, className in ipairs(list) do
			local button = mk("TextButton", {
				BackgroundColor3 = T.raised,
				Text = "",
				BorderSizePixel = 0,
				AutoButtonColor = false,
				LayoutOrder = index,
			}, wrap)
			round(button, 3)
			stroke(button, T.line2)

			local icon = mk("ImageLabel", {
				Size = UDim2.fromOffset(16, 16),
				Position = UDim2.fromOffset(5, 4),
				BackgroundTransparency = 1,
				ImageTransparency = 0.35,
			}, button)
			local art = classIcon(className)
			if art then
				icon.Image = art.Image
				if art.RectOffset then icon.ImageRectOffset = art.RectOffset end
				if art.RectSize and art.RectSize.X > 0 then icon.ImageRectSize = art.RectSize end
			end

			local label = mk("TextLabel", {
				Size = UDim2.new(1, -27, 1, 0),
				Position = UDim2.fromOffset(25, 0),
				BackgroundTransparency = 1,
				Text = className,
				TextColor3 = T.faint,
				TextSize = 10,
				Font = Enum.Font.Gotham,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}, button)

			button.MouseEnter:Connect(function()
				if #selected == 0 then return end
				button.BackgroundColor3 = T.hover
			end)
			button.MouseLeave:Connect(function() button.BackgroundColor3 = T.raised end)
			button.MouseButton1Click:Connect(function() onPick(className) end)

			table.insert(buttons, { button = button, icon = icon, label = label })
		end
		return buttons
	end

	--- Troca a classe preservando o que couber. Propriedades incompativeis caem no
	--- pcall e sao ignoradas, em vez de abortar a conversao inteira.
	local function convertClass(inst, className)
		local new = Instance.new(className)

		for _, prop in ipairs(CARRY_PROPS) do
			pcall(function() new[prop] = inst[prop] end)
		end

		for _, child in ipairs(inst:GetChildren()) do
			child.Parent = new
		end

		new.Name = inst.Name
		new.Parent = inst.Parent
		inst:Destroy()
		return new
	end

	local convertButtons = classGrid(gConvert.frame, gConvert, CONVERT_CLASSES, function(className)
		if #selected == 0 then logLine("nada selecionado", "err") return end

	    local made = {}
		local ok = withUndo("Converter para " .. className, function()
			for _, inst in ipairs(selected) do
				if inst.ClassName ~= className then
					table.insert(made, convertClass(inst, className))
				else
					table.insert(made, inst)
				end
			end
		end)

		if ok and #made > 0 then
			Selection:Set(made)
			logLine(#made .. " -> " .. className, "ok")
		end
	end)

	-- --------------------------------------------------- adicionar modificador --
	local gModifier = collapsible(adjustPage, "Adicionar modificador", false)

	noteRow(gModifier, "Modificadores nao substituem o elemento: entram como filhos dele.", 28)

	local modifierButtons = classGrid(gModifier.frame, gModifier, MODIFIER_CLASSES, function(className)
		if #selected == 0 then logLine("nada selecionado", "err") return end

		local added = 0
		withUndo("Adicionar " .. className, function()
			for _, inst in ipairs(selected) do
				-- Um so de cada tipo: dois UICorner no mesmo Frame nao faz sentido.
				if not inst:FindFirstChildOfClass(className) then
					local modifier = Instance.new(className)
					modifier.Parent = inst
					added += 1
				end
			end
		end)

		logLine(added > 0 and (added .. "x " .. className .. " adicionado") or (className .. " ja existia"),
			added > 0 and "ok" or nil)
	end)

	-- -------------------------------------------------------------------- log ---
	local gLog = collapsible(adjustPage, "Log", false)

	logHolder = mk("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = gLog.next(),
	}, gLog.frame)
	mk("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, logHolder)
	mk("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 8) }, logHolder)

	local logClear = mk("TextButton", {
		Size = UDim2.new(1, -GUTTER * 2, 0, 22),
		Position = UDim2.fromOffset(GUTTER, 2),
		BackgroundColor3 = T.raised,
		Text = "Limpar log",
		TextColor3 = T.dim,
		TextSize = 10,
		Font = Enum.Font.Gotham,
		BorderSizePixel = 0,
		AutoButtonColor = false,
	}, mk("Frame", {
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = gLog.next(),
	}, gLog.frame))
	round(logClear, 3)
	stroke(logClear, T.line2)

	logClear.MouseButton1Click:Connect(function()
		for _, line in ipairs(logLines) do line:Destroy() end
		table.clear(logLines)
	end)

	-- ============================================ sincronizacao com a selecao ===
	--- Preenche os campos a partir do primeiro selecionado. `suppress` impede que
	--- escrever nos campos dispare a aplicacao de volta no Instance.
	refreshFields = function()
		suppress = true

		local first = selected[1]
		local count = #selected

		adjustHint.Text = count == 0 and "Selecione um elemento de UI no Explorer."
			or (count == 1 and (first.ClassName .. "  ·  " .. first.Name)
			or (count .. " elementos selecionados"))
		adjustHint.TextColor3 = count == 0 and T.faint or T.dim

		convHint.Text = count == 0 and "Nenhum GUI selecionado"
			or ("Converte " .. count .. " elemento(s). Filhos e propriedades compativeis sao preservados.")

		-- Botoes so ficam legiveis quando ha algo para agir sobre.
		for _, entry in ipairs(convertButtons) do
			entry.label.TextColor3 = count > 0 and T.txt or T.faint
			entry.icon.ImageTransparency = count > 0 and 0 or 0.55
		end
		for _, entry in ipairs(modifierButtons) do
			entry.label.TextColor3 = count > 0 and T.txt or T.faint
			entry.icon.ImageTransparency = count > 0 and 0 or 0.55
		end

		if not first then
			for _, field in ipairs({ fieldX, fieldY, fieldW, fieldH, fieldRot, fieldZ,
			                        fieldAX, fieldAY, fieldBgT, fieldTextSize, fieldImgT }) do
				field.Text = ""
			end
			ctlBgColor.paint(nil)
			ctlTextColor.paint(nil)
			ctlImgColor.paint(nil)
			suppress = false
			return
		end

		fieldX.Text = tostring(math.floor(first.Position.X.Offset))
		fieldY.Text = tostring(math.floor(first.Position.Y.Offset))
		fieldW.Text = tostring(math.floor(first.Size.X.Offset))
		fieldH.Text = tostring(math.floor(first.Size.Y.Offset))
		fieldRot.Text = string.format("%.4g", first.Rotation)
		fieldZ.Text = tostring(first.ZIndex)
		fieldAX.Text = string.format("%.4g", first.AnchorPoint.X)
		fieldAY.Text = string.format("%.4g", first.AnchorPoint.Y)
		fieldBgT.Text = string.format("%.4g", first.BackgroundTransparency)

		ctlVisible.paint(first.Visible)
		ctlAuto.paint(first.AutomaticSize ~= Enum.AutomaticSize.None)
		ctlBgColor.paint(first.BackgroundColor3)

		local isText = first:IsA("TextLabel") or first:IsA("TextButton") or first:IsA("TextBox")
		gText.frame.Visible = isText and gText.headerOpen ~= false
		gText.header.Visible = isText
		if isText then
			fieldTextSize.Text = tostring(first.TextSize)
			ctlTextColor.paint(first.TextColor3)
		else
			fieldTextSize.Text = ""
			ctlTextColor.paint(nil)
		end

		local isImage = first:IsA("ImageLabel") or first:IsA("ImageButton")
		gImage.frame.Visible = isImage and gImage.headerOpen ~= false
		gImage.header.Visible = isImage
		if isImage then
			fieldImgT.Text = string.format("%.4g", first.ImageTransparency)
			ctlImgColor.paint(first.ImageColor3)
		else
			fieldImgT.Text = ""
			ctlImgColor.paint(nil)
		end

		suppress = false
	end

	resetBtn.MouseButton1Click:Connect(function()
		if #selected == 0 then logLine("nada selecionado", "err") return end
		withUndo("Redefinir transformacao", function()
			for _, inst in ipairs(selected) do
				inst.Position = UDim2.fromOffset(0, 0)
				inst.Size = UDim2.fromOffset(100, 100)
				inst.Rotation = 0
				inst.AnchorPoint = Vector2.zero
			end
		end)
		refreshFields()
		logLine(#selected .. " elemento(s) redefinido(s)", "ok")
	end)

	--- Guarda so GuiObjects: as ferramentas nao fazem sentido em Part ou Script.
	local function captureSelection()
		table.clear(selected)
		for _, inst in ipairs(Selection:Get()) do
			if inst:IsA("GuiObject") then table.insert(selected, inst) end
		end
		refreshFields()
	end

	table.insert(pluginConnections, Selection.SelectionChanged:Connect(captureSelection))
	captureSelection()
	logLine("painel de ajustes pronto")


end

buildAdjustPanel()


-- ========================================================== ABA: EXPORTS ==
local exportsPage = pages.exports

local _, refreshCtl = propRow(exportsPage, "Exports recentes", nil, 34)
local refreshBtn = miniButton(refreshCtl, "atualizar", 76)

local listHolder = mk("Frame", {
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	LayoutOrder = exportsPage.next(),
}, exportsPage.frame)
mk("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, listHolder)

-- =========================================================== ABA: CONFIG ==
local configPage = pages.config

groupHead(configPage, "Servidor")
local urlWrap = mk("Frame", {
	Size = UDim2.new(1, 0, 0, 34),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	LayoutOrder = configPage.next(),
}, configPage.frame)
hairline(urlWrap, true)
local urlInput = fieldIn(urlWrap, "https://seu-worker.workers.dev",
	Plugin:GetSetting("workerUrl") or DEFAULT_URL, true, true)
urlInput.Position = UDim2.fromOffset(GUTTER, 6)

groupHead(configPage, "Uploader local")
local cmdWrap = mk("Frame", {
	Size = UDim2.new(1, 0, 0, 34),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	LayoutOrder = configPage.next(),
}, configPage.frame)
hairline(cmdWrap, true)
local cmdBox = fieldIn(cmdWrap, "", Plugin:GetSetting("uploaderCmd") or DEFAULT_CMD, true, true)
cmdBox.Position = UDim2.fromOffset(GUTTER, 6)

local queueLabel = noteRow(configPage, DEFAULT_HINT, 38)

groupHead(configPage, "Sobre")
noteRow(configPage,
	"FigmaToRoblox — gratuito, por " .. AUTHOR_NAME .. ".\n" ..
	"Use os icones no topo para o tutorial e o perfil.", 36)

-- ------------------------------------------------------------ primeiros passos
-- Checklist que se verifica sozinho. Cada passo sabe dizer se ja esta feito, e
-- os que falham trazem o link ou o comando — em vez de mandar a pessoa procurar
-- num README que ela nao vai abrir.
--
-- Em funcao propria pelo orcamento de 200 registradores por funcao do Luau.
local function buildOnboarding()
	local page = pages.config

	-- Criado depois de urlInput/cmdBox (precisa deles), mas exibido primeiro:
	-- UIListLayout ordena por LayoutOrder, e negativo vem antes de tudo.
	local head = groupHead(page, "Primeiros passos")
	head.LayoutOrder = -101

	local steps = {}

	--- Uma linha de passo: bolinha de estado, titulo, explicacao e uma acao.
	local function stepRow(number, title, hint, actionLabel, action)
		local row = mk("Frame", {
			Size = UDim2.new(1, 0, 0, 46),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			LayoutOrder = -100 + number,
		}, page.frame)
		hairline(row, true)

		local bullet = mk("Frame", {
			Size = UDim2.fromOffset(16, 16),
			Position = UDim2.fromOffset(GUTTER, 9),
			BackgroundColor3 = T.raised,
			BorderSizePixel = 0,
		}, row)
		round(bullet, 8)
		local bulletRing = stroke(bullet, T.line2)

		local mark = mk("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = tostring(number),
			TextColor3 = T.faint,
			TextSize = 9,
			Font = Enum.Font.Code,
		}, bullet)

		mk("TextLabel", {
			Size = UDim2.new(1, -GUTTER * 2 - 110, 0, 14),
			Position = UDim2.fromOffset(GUTTER + 24, 7),
			BackgroundTransparency = 1,
			Text = title,
			TextColor3 = T.txt,
			TextSize = 11,
			Font = Enum.Font.Gotham,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, row)

		local hintLabel = mk("TextLabel", {
			Size = UDim2.new(1, -GUTTER * 2 - 110, 0, 22),
			Position = UDim2.fromOffset(GUTTER + 24, 21),
			BackgroundTransparency = 1,
			Text = hint,
			TextColor3 = T.faint,
			TextSize = 9,
			Font = Enum.Font.Gotham,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextWrapped = true,
		}, row)

		local button = miniButton(row, actionLabel, 84)
		button.MouseButton1Click:Connect(action)

		local entry = {
			row = row, bullet = bullet, ring = bulletRing,
			mark = mark, hint = hintLabel, button = button, done = false,
		}

		function entry.setDone(done, newHint)
			entry.done = done
			entry.mark.Text = done and "\226\156\147" or tostring(number)
			entry.mark.TextColor3 = done and T.onAccent or T.faint
			entry.bullet.BackgroundColor3 = done and T.ok or T.raised
			entry.ring.Color = done and T.ok or T.line2
			entry.button.Visible = not done
			if newHint then entry.hint.Text = newHint end
		end

		table.insert(steps, entry)
		return entry
	end

	-- Passo 0 — instalar. Antes eram dois passos (baixar o ZIP, depois achar e
	-- rodar o .bat); virou um so porque cada passo a mais e uma chance a mais de
	-- travar. O botao copia o comando: nao ha o que digitar errado.
	local stepFiles = stepRow(1,
		"Instalar (uma linha)",
		"Abra o PowerShell (tecla Windows, digite PowerShell) e cole o comando. " ..
		"Ele baixa tudo, publica o seu Worker e instala sozinho.",
		"copiar",
		function()
			cmdBox.Text = INSTALL_CMD
			cmdBox:CaptureFocus()
			cmdBox.SelectionStart = 1
			cmdBox.CursorPosition = #cmdBox.Text + 1
		end)

	-- Passo 1 — o servidor. E o unico que da para checar de dentro do Studio.
	local stepWorker = stepRow(2,
		"Servidor publicado",
		"Assim que o comando acima terminar, ele mostra a URL do seu Worker.",
		"verificar",
		function() end)

	-- Passo 2 — a URL colada aqui.
	local stepUrl = stepRow(3,
		"URL no plugin",
		"Cole a URL que o instalador mostrou no campo do servidor, logo abaixo.",
		"verificar",
		function() end)

	-- Passo 3 — o uploader rodando.
	local stepUploader = stepRow(4,
		"Uploader aberto",
		"De dois cliques no atalho 'FigmaToRoblox uploader' na area de trabalho e " ..
		"deixe a janela minimizada enquanto trabalha.",
		"copiar",
		function() end)

	-- Passo 4 — o plugin do Figma.
	local stepFigma = stepRow(5,
		"Plugin do Figma",
		"Abra o plugin do Figma pela pagina da comunidade e deixe instalado.",
		"abrir",
		function() openUrl(FIGMA_PLUGIN_URL) end)

	-- Passo 0 nao tem como verificar do Studio (arquivo esta no PC do usuario).
	-- Fica marcado ok quando o servidor responde — se responde, o projeto ta la.
	stepFiles.setDone(false)

	stepFigma.setDone(false)

	--- Checa o que da para checar e pinta o checklist. Roda ao abrir e ao clicar
	--- em qualquer "verificar".
	local function refresh()
		task.spawn(function()
			local url = urlInput.Text
			if url == "" then url = Plugin:GetSetting("workerUrl") or "" end

			-- Servidor de pe?
			local okWorker = false
			if url ~= "" then
				okWorker = pcall(function() return Api.get(url, "/api/health") end)
			end
			-- Se o Worker responde, o projeto obviamente foi baixado.
			stepFiles.setDone(okWorker,
				okWorker and "Projeto instalado."
				or "Abra o PowerShell e cole o comando. Ele faz o resto sozinho.")

			stepWorker.setDone(okWorker,
				okWorker and "Servidor respondendo." or
				"Rode INSTALAR.bat na pasta extraida. Ele cria a conta, publica e devolve a URL.")

			-- URL preenchida?
			stepUrl.setDone(url ~= "" and okWorker,
				(url ~= "" and okWorker) and ("Apontando para " .. url) or
				"Cole a URL que o instalador mostrou no campo do servidor, logo abaixo.")

			-- Uploader rodando? Sem fila pendente ha sinal de que ele esta dando conta.
			local okQueue, pending = pcall(function() return Api.get(url, "/api/pending") end)
			if okWorker and okQueue and type(pending) == "table" then
				local queued = 0
				for _, item in ipairs(pending) do
					for _ in pairs(item.images or {}) do queued += 1 end
				end
				stepUploader.setDone(queued == 0,
					queued == 0 and "Nada parado na fila."
					or (queued .. " imagem(ns) esperando — abra o uploader."))
			end
		end)
	end

	stepWorker.button.MouseButton1Click:Connect(refresh)
	stepUrl.button.MouseButton1Click:Connect(refresh)
	stepUploader.button.MouseButton1Click:Connect(function()
		-- Devolve o comando do uploader: o Passo 1 pode ter deixado o de instalacao
		-- no campo, e copiar aquilo de novo so reinstalaria o projeto.
		cmdBox.Text = Plugin:GetSetting("uploaderCmd") or DEFAULT_CMD
		cmdBox:CaptureFocus()
		cmdBox.SelectionStart = 1
		cmdBox.CursorPosition = #cmdBox.Text + 1
		refresh()
	end)

	refresh()
end

buildOnboarding()


-- ------------------------------------------------------------- apoiar -----
-- Um plugin NAO consegue cobrar Robux: PromptProductPurchase exige um Player,
-- que so existe dentro de uma experiencia. O caminho e uma place de doacao com
-- Developer Products; aqui a gente leva ate la e mostra quem ja apoiou.
--
-- Em funcao propria pelo orcamento de registradores do Luau (200 por funcao).
local function buildSupportSection()
	local page = pages.config

	groupHead(page, "Apoiar o plugin")

	noteRow(page,
		"O FigmaToRoblox e gratuito e continua gratuito. Se ele te poupou tempo, " ..
		"qualquer quantia ajuda a manter os consertos e os recursos novos vindo. " ..
		"Nenhuma funcao fica atras de pagamento.", 46)

	-- Faixas: valores redondos e um campo livre, porque limitar a escolha e a
	-- forma mais rapida de perder uma doacao maior.
	local TIERS = { 10, 25, 50, 100, 500, 1000 }

	local tierWrap = mk("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = page.next(),
	}, page.frame)
	mk("UIPadding", {
		PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 8),
		PaddingLeft = UDim.new(0, GUTTER), PaddingRight = UDim.new(0, GUTTER),
	}, tierWrap)
	mk("UIGridLayout", {
		CellSize = UDim2.new(1 / 3, -4, 0, 26),
		CellPadding = UDim2.fromOffset(6, 5),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, tierWrap)

	for index, amount in ipairs(TIERS) do
		local button = mk("TextButton", {
			BackgroundColor3 = T.raised,
			Text = "R$ " .. amount,
			TextColor3 = T.dim,
			TextSize = 10,
			Font = Enum.Font.Code,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			LayoutOrder = index,
		}, tierWrap)
		round(button, 3)
		stroke(button, T.line2)

		button.MouseEnter:Connect(function()
			button.BackgroundColor3 = T.hover
			button.TextColor3 = T.txt
		end)
		button.MouseLeave:Connect(function()
			button.BackgroundColor3 = T.raised
			button.TextColor3 = T.dim
		end)
		button.MouseButton1Click:Connect(function()
			openUrl(DONATE_URL)
		end)
	end

	local openBtn = mk("TextButton", {
		Size = UDim2.new(1, -GUTTER * 2, 0, 28),
		Position = UDim2.fromOffset(GUTTER, 2),
		BackgroundColor3 = T.accent,
		Text = "Abrir pagina de apoio",
		TextColor3 = T.onAccent,
		TextSize = 11,
		Font = Enum.Font.GothamBold,
		BorderSizePixel = 0,
		AutoButtonColor = false,
	}, mk("Frame", {
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = page.next(),
	}, page.frame))
	round(openBtn, 3)

	openBtn.MouseEnter:Connect(function() openBtn.BackgroundColor3 = T.accentHi end)
	openBtn.MouseLeave:Connect(function() openBtn.BackgroundColor3 = T.accent end)
	openBtn.MouseButton1Click:Connect(function() openUrl(DONATE_URL) end)

	-- ------------------------------------------------------ quadro de apoio
	local boardHead, boardCount = groupHead(page, "Apoiadores")

	local podium = mk("Frame", {
		Size = UDim2.new(1, 0, 0, 92),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		LayoutOrder = page.next(),
	}, page.frame)

	local listHolder = mk("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = page.next(),
	}, page.frame)
	mk("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, listHolder)

	local _, emptyRow = noteRow(page,
		"Ninguem apoiou ainda. Voce pode ser o primeiro.", 26)

	--- Foto do usuario. Assincrona de proposito: o quadro aparece na hora e as
	--- fotos entram conforme chegam, em vez de travar tudo esperando a rede.
	local function loadAvatar(image, userId)
		task.spawn(function()
			local ok, url = pcall(function()
				return Players:GetUserThumbnailAsync(
					userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
			end)
			if ok and url and image.Parent then image.Image = url end
		end)
	end

	-- Cores do podio: ouro, prata, bronze — dessaturadas para nao brigar com a
	-- paleta neutra do resto do painel.
	local MEDALS = {
		Color3.fromRGB(186, 152, 74),
		Color3.fromRGB(150, 152, 158),
		Color3.fromRGB(160, 112, 74),
	}

	local function buildPodium(top)
		for _, child in ipairs(podium:GetChildren()) do child:Destroy() end
		podium.Visible = #top > 0
		if #top == 0 then return end

		-- Ordem visual 2-1-3, com o primeiro maior e ao centro.
		local slots = { { 2, 0.18, 30, 18 }, { 1, 0.5, 38, 4 }, { 3, 0.82, 30, 18 } }

		for _, slot in ipairs(slots) do
			local rank, x, size, top_ = slot[1], slot[2], slot[3], slot[4]
			local person = top[rank]
			if person then
				local avatar = mk("ImageLabel", {
					Size = UDim2.fromOffset(size, size),
					Position = UDim2.new(x, -size / 2, 0, top_),
					BackgroundColor3 = T.active,
					BorderSizePixel = 0,
				}, podium)
				round(avatar, size / 2)
				stroke(avatar, MEDALS[rank], 2)
				loadAvatar(avatar, person.userId)

				mk("TextLabel", {
					Size = UDim2.fromOffset(84, 12),
					Position = UDim2.new(x, -42, 0, top_ + size + 3),
					BackgroundTransparency = 1,
					Text = person.name,
					TextColor3 = T.txt,
					TextSize = 10,
					Font = Enum.Font.GothamMedium,
					TextTruncate = Enum.TextTruncate.AtEnd,
				}, podium)

				mk("TextLabel", {
					Size = UDim2.fromOffset(84, 11),
					Position = UDim2.new(x, -42, 0, top_ + size + 15),
					BackgroundTransparency = 1,
					Text = "R$ " .. person.robux,
					TextColor3 = MEDALS[rank],
					TextSize = 9,
					Font = Enum.Font.Code,
				}, podium)
			end
		end
	end

	local function buildList(rest)
		for _, child in ipairs(listHolder:GetChildren()) do
			if not child:IsA("UIListLayout") then child:Destroy() end
		end

		for index, person in ipairs(rest) do
			local row = mk("Frame", {
				Size = UDim2.new(1, 0, 0, 28),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				LayoutOrder = index,
			}, listHolder)
			hairline(row, true)

			mk("TextLabel", {
				Size = UDim2.fromOffset(20, 28),
				Position = UDim2.fromOffset(GUTTER, 0),
				BackgroundTransparency = 1,
				Text = tostring(person.rank),
				TextColor3 = T.faint,
				TextSize = 9,
				Font = Enum.Font.Code,
				TextXAlignment = Enum.TextXAlignment.Right,
			}, row)

			local avatar = mk("ImageLabel", {
				Size = UDim2.fromOffset(18, 18),
				Position = UDim2.fromOffset(GUTTER + 28, 5),
				BackgroundColor3 = T.active,
				BorderSizePixel = 0,
			}, row)
			round(avatar, 9)
			loadAvatar(avatar, person.userId)

			mk("TextLabel", {
				Size = UDim2.new(1, -GUTTER * 2 - 110, 1, 0),
				Position = UDim2.fromOffset(GUTTER + 52, 0),
				BackgroundTransparency = 1,
				Text = person.name,
				TextColor3 = T.txt,
				TextSize = 10,
				Font = Enum.Font.Gotham,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}, row)

			mk("TextLabel", {
				Size = UDim2.fromOffset(58, 28),
				Position = UDim2.new(1, -GUTTER - 58, 0, 0),
				BackgroundTransparency = 1,
				Text = "R$ " .. person.robux,
				TextColor3 = T.dim,
				TextSize = 10,
				Font = Enum.Font.Code,
				TextXAlignment = Enum.TextXAlignment.Right,
			}, row)
		end
	end

	--- Busca o quadro. Falha em silencio de proposito: apoiador offline nao e
	--- motivo para poluir a barra de status de quem so quer importar UI.
	local function refreshBoard()
		task.spawn(function()
			local ok, data = pcall(function()
				return Api.get(Plugin:GetSetting("workerUrl") or DEFAULT_URL, "/api/supporters")
			end)
			if not ok or type(data) ~= "table" or not data.supporters then return end

			local all = data.supporters
			boardCount.Text = data.count > 0
				and (data.count .. " · R$ " .. data.total)
				or ""

			emptyRow.Visible = #all == 0

			local top, rest = {}, {}
			for index, person in ipairs(all) do
				if index <= 3 then top[index] = person else table.insert(rest, person) end
			end

			buildPodium(top)
			buildList(rest)
		end)
	end

	refreshBoard()
end

buildSupportSection()


-- ------------------------------------------------------- barra de status ---
local statusBar = mk("Frame", {
	Size = UDim2.new(1, 0, 0, STATUS_H),
	Position = UDim2.new(0, 0, 1, -STATUS_H),
	BackgroundColor3 = T.raised,
	BorderSizePixel = 0,
	ZIndex = 10,
}, root)
hairline(statusBar, false)

local statusDot = mk("Frame", {
	Size = UDim2.fromOffset(5, 5),
	Position = UDim2.fromOffset(GUTTER, 9),
	BackgroundColor3 = T.faint,
	BorderSizePixel = 0,
	ZIndex = 11,
}, statusBar)
round(statusDot, 3)

local statusText = mk("TextLabel", {
	Size = UDim2.new(1, -GUTTER * 2 - 12, 1, 0),
	Position = UDim2.fromOffset(GUTTER + 12, 0),
	BackgroundTransparency = 1,
	Text = "Pronto",
	TextColor3 = T.faint,
	TextSize = 10,
	Font = Enum.Font.Gotham,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	ZIndex = 11,
}, statusBar)

-- ------------------------------------------------------- pedido de avaliacao
local reviewBar = mk("Frame", {
	Size = UDim2.new(1, 0, 0, 40),
	Position = UDim2.new(0, 0, 1, -STATUS_H - 40),
	BackgroundColor3 = T.raised,
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 40,
}, root)
hairline(reviewBar, false)

mk("TextLabel", {
	Size = UDim2.new(1, -150, 0, 13),
	Position = UDim2.fromOffset(GUTTER, 7),
	BackgroundTransparency = 1,
	Text = "Curtindo o plugin?",
	TextColor3 = T.txt,
	TextSize = 11,
	Font = Enum.Font.GothamMedium,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 41,
}, reviewBar)

mk("TextLabel", {
	Size = UDim2.new(1, -150, 0, 12),
	Position = UDim2.fromOffset(GUTTER, 21),
	BackgroundTransparency = 1,
	Text = "Uma avaliacao ajuda mais gente a achar ele",
	TextColor3 = T.dim,
	TextSize = 9,
	Font = Enum.Font.Gotham,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 41,
}, reviewBar)

local reviewBtn = mk("TextButton", {
	Size = UDim2.fromOffset(58, 22),
	Position = UDim2.new(1, -92, 0.5, -11),
	BackgroundColor3 = T.accent,
	Text = "Avaliar",
	TextColor3 = T.onAccent,
	TextSize = 10,
	Font = Enum.Font.GothamBold,
	BorderSizePixel = 0,
	AutoButtonColor = false,
	ZIndex = 41,
}, reviewBar)
round(reviewBtn, 3)

local reviewLater = mk("TextButton", {
	Size = UDim2.fromOffset(24, 22),
	Position = UDim2.new(1, -30, 0.5, -11),
	BackgroundTransparency = 1,
	Text = "\195\151",
	TextColor3 = T.faint,
	TextSize = 13,
	Font = Enum.Font.Gotham,
	AutoButtonColor = false,
	ZIndex = 41,
}, reviewBar)

selectTab(1)


-- ============================================================================
-- COMPORTAMENTO
-- ============================================================================
local busy = false
local syncEnabled = false
local lastImportedId = Plugin:GetSetting("lastImportedId")

--- Barra de status: o ponto carrega a cor, o texto acompanha. Um ponto de 5px
--- comunica estado sem tingir a frase inteira.
local function setStatus(message, kind)
	statusText.Text = message

	local color = T.dim
	if kind == "ok" then color = T.ok
	elseif kind == "err" then color = T.err
	elseif kind == "warn" then color = T.warn
	end

	statusText.TextColor3 = (kind == nil or kind == "info") and T.faint or color
	statusDot.BackgroundColor3 = color
end

-- ------------------------------------------------------ interruptores
local SWITCH_TWEEN = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function animateSwitch(track, knob, on)
	TweenService:Create(track, SWITCH_TWEEN, {
		BackgroundColor3 = on and T.solid or T.panel3,
	}):Play()
	TweenService:Create(knob, SWITCH_TWEEN, {
		-- Casa com switchIn: trilho 26x14, knob 10x10 partindo de (2,2).
		-- Ligado = 26 - 10 - 2. Numeros soltos aqui jogavam o knob para fora.
		Position = on and UDim2.fromOffset(14, 2) or UDim2.fromOffset(2, 2),
		BackgroundColor3 = on and T.solidTxt or T.faint,
	}):Play()
end

local function setSyncVisual(on)
	animateSwitch(switchTrack, switchKnob, on)
	syncPill.Text = on and "sync ligado" or "sync desligado"
	syncPill.TextColor3 = on and T.ok or T.faint
end

local function setScaleVisual(on)
	animateSwitch(scaleTrack, scaleKnob, on)
end

-- --------------------------------------------------- pedido de avaliacao
--- Aparece a cada REVIEW_EVERY importacoes. Se dispensado, nao volta nunca.
local function maybeAskReview()
	if Plugin:GetSetting("reviewDone") == true then return end

	local count = (Plugin:GetSetting("importCount") or 0) + 1
	Plugin:SetSetting("importCount", count)
	if count % REVIEW_EVERY ~= 0 then return end

	reviewBar.Position = UDim2.new(0, 10, 1, -76)
	reviewBar.Visible = true
	TweenService:Create(reviewBar, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0, 10, 1, -84),
	}):Play()
end

reviewBtn.MouseButton1Click:Connect(function()
	Plugin:SetSetting("reviewDone", true)
	reviewBar.Visible = false
	openUrl(REVIEW_URL)
end)

reviewLater.MouseButton1Click:Connect(function()
	Plugin:SetSetting("reviewDone", true)
	reviewBar.Visible = false
end)

reviewBtn.MouseEnter:Connect(function() reviewBtn.BackgroundColor3 = Color3.new(1, 1, 1) end)
reviewBtn.MouseLeave:Connect(function() reviewBtn.BackgroundColor3 = T.solid end)
reviewLater.MouseEnter:Connect(function() reviewLater.TextColor3 = T.txt end)
reviewLater.MouseLeave:Connect(function() reviewLater.TextColor3 = T.faint end)

--- A dica vira alerta quando sobrou imagem sem asset: e o sinal de que o
--- uploader nao esta rodando.
local function setQueueHint(missing)
	if missing and missing > 0 then
		queueLabel.Text = missing .. " imagem(ns) esperando upload. Copie o comando acima e rode no PowerShell."
		queueLabel.TextColor3 = T.warn
	else
		queueLabel.Text = DEFAULT_HINT
		queueLabel.TextColor3 = T.faint
	end
end

-- --------------------------------------------------------- pre-scripts (UI)
local function setPreChecked(key, on)
	preSelected[key] = on or nil
	local row = preRows[key]
	if not row then return end

	-- Sem tween: 17 linhas animando juntas vira ruído, não feedback.
	row.tick.Visible = on == true
	row.box.BackgroundColor3 = on and T.accent or T.raised
	row.stroke.Color = on and T.accent or T.line2
end

--- Mostra so as perguntas cujo sistema esta marcado. Quando nenhuma aparece,
--- troca por um aviso: secao vazia sem explicacao parece bug.
local function refreshQuestions()
	local anyVisible = false
	for _, entry in pairs(questionRows) do
		local visible = preSelected[entry.requires] == true
		entry.row.Visible = visible
		if visible then anyVisible = true end
	end
	noParams.Visible = not anyVisible
end

local function savePreSelection()
	local keys = {}
	for key in pairs(preSelected) do table.insert(keys, key) end
	pcall(function() Plugin:SetSetting("preScripts", HttpService:JSONEncode(keys)) end)
end

local function loadPreSelection()
	local raw = Plugin:GetSetting("preScripts")
	if type(raw) ~= "string" then return end
	local ok, keys = pcall(function() return HttpService:JSONDecode(raw) end)
	if not ok or type(keys) ~= "table" then return end
	for _, key in ipairs(keys) do setPreChecked(key, true) end
	refreshQuestions()
end

local function anyPreSelected()
	for _ in pairs(preSelected) do return true end
	return false
end

-- ----------------------------------------------------------- vinculos (UI)
--- ScreenGui usada como referencia dos caminhos. Precisa ser a mesma raiz que o
--- Boot usa em tempo de jogo, senao os caminhos nao resolvem.
local bindRoot = nil
local overrides = {}

local function saveOverrides()
	pcall(function() Plugin:SetSetting("pathOverrides", HttpService:JSONEncode(overrides)) end)
end

local function loadOverrides()
	local raw = Plugin:GetSetting("pathOverrides")
	if type(raw) ~= "string" then return end
	local ok, decoded = pcall(function() return HttpService:JSONDecode(raw) end)
	if ok and type(decoded) == "table" then overrides = decoded end
end

--- Monta a lista de alvos dos sistemas marcados, mostrando o que foi achado.
--- Recria as linhas a cada mudanca: sao poucas dezenas, e reaproveitar
--- instancias aqui daria mais bug do que ganho.
local function rebuildBindings()
	for _, child in ipairs(bindHolder:GetChildren()) do
		if not child:IsA("UIListLayout") then child:Destroy() end
	end

	local required = PreScripts.requiredPaths(preSelected)
	bindEmpty.Visible = #required == 0

	if #required == 0 then return end

	-- Sem raiz ainda nao ha o que resolver; mostra os alvos como pendentes.
	local detected = {}
	if bindRoot then
		detected = PreScripts.detect(bindRoot, preSelected, overrides)
	end

	for index, entry in ipairs(required) do
		local key = entry.key
		local value = detected[key]
		local manual = overrides[key] ~= nil and overrides[key] ~= ""

		local row = mk("Frame", {
			Size = UDim2.new(1, 0, 0, 42),
			BackgroundColor3 = T.panel,
			BorderSizePixel = 0,
			LayoutOrder = index,
		}, bindHolder)
		round(row, 5)

		mk("TextLabel", {
			Size = UDim2.new(1, -84, 0, 13),
			Position = UDim2.fromOffset(10, 6),
			BackgroundTransparency = 1,
			Text = PreScripts.pathLabel(key),
			TextColor3 = T.txt,
			TextSize = 10,
			Font = Enum.Font.GothamMedium,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, row)

		mk("TextLabel", {
			Size = UDim2.new(1, -84, 0, 12),
			Position = UDim2.fromOffset(10, 21),
			BackgroundTransparency = 1,
			Text = value and ((manual and "apontado: " or "") .. value)
				or (bindRoot and "nao encontrado" or "aguardando deteccao"),
			TextColor3 = value and (manual and T.ok or T.dim) or T.warn,
			TextSize = 9,
			Font = Enum.Font.Code,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, row)

		local pick = mk("TextButton", {
			Size = UDim2.fromOffset(66, 24),
			Position = UDim2.new(1, -76, 0.5, -12),
			BackgroundColor3 = T.panel3,
			Text = manual and "limpar" or "apontar",
			TextColor3 = T.txt,
			TextSize = 10,
			Font = Enum.Font.GothamMedium,
			BorderSizePixel = 0,
			AutoButtonColor = false,
		}, row)
		round(pick, 5)

		pick.MouseEnter:Connect(function() pick.BackgroundColor3 = T.line2 end)
		pick.MouseLeave:Connect(function() pick.BackgroundColor3 = T.panel3 end)

		pick.MouseButton1Click:Connect(function()
			if manual then
				overrides[key] = nil
				saveOverrides()
				rebuildBindings()
				return
			end

			local picked = Selection:Get()[1]
			if not picked then
				setStatus("Selecione o elemento no Explorer e clique em apontar.", "err")
				return
			end

			local gui = picked:IsA("ScreenGui") and picked or picked:FindFirstAncestorWhichIsA("ScreenGui")
			if not gui then
				setStatus("O elemento precisa estar dentro de uma ScreenGui.", "err")
				return
			end

			bindRoot = gui
			overrides[key] = PreScripts.pathOf(picked, gui)
			saveOverrides()
			rebuildBindings()
			setStatus(PreScripts.pathLabel(key) .. " -> " .. overrides[key], "ok")
		end)
	end
end

--- Le os campos numericos, caindo no padrao quando o texto nao e numero.
local function collectOptions()
	local options = { slotPadding = 6, modalWindows = true }
	for key, entry in pairs(questionRows) do
		local value = tonumber(entry.input.Text)
		options[key] = (value and value > 0) and math.floor(value) or entry.default
	end
	return options
end

--- generate devolve (ok, mensagem, faltando); com pcall na frente isso vira
--- (pcallOk, ok, mensagem, faltando).
local function runGenerate(screenGui, statusFn)
	if not anyPreSelected() then return end

	local pcallOk, first, second =
		pcall(PreScripts.generate, screenGui, preSelected, collectOptions(), overrides)
	if not pcallOk then
		statusFn("Pre-Scripts falharam: " .. tostring(first), "err")
		return
	end

	statusFn("Pre-Scripts: " .. tostring(second), "ok")
end

local function setBusy(on)
	busy = on
	importBtn.Text = on and "Importando..." or "Importar"
	importBtn.BackgroundColor3 = on and T.panel2 or T.solid
	importBtn.TextColor3 = on and T.faint or T.solidTxt
end

local function baseUrl()
	return trimUrl(urlInput.Text ~= "" and urlInput.Text or DEFAULT_URL)
end

local function checkHttp()
	local ok = pcall(function()
		HttpService:RequestAsync({ Url = baseUrl() .. "/api/health", Method = "GET" })
	end)
	if not ok then
		setStatus("HTTP bloqueado. Ative em Game Settings > Security > Allow HTTP Requests.", "err")
		return false
	end
	return true
end

--- ScreenGui criado pela ultima importacao automatica. O auto-sync substitui
--- essa GUI a cada ciclo, em vez de empilhar uma nova a cada export.
local lastAutoGui = nil

local function doImport(exportId, useSelection)
	if busy then return end

	-- Sem servidor configurado nao ha o que tentar. Dizer isso aqui evita um
	-- "falha ao importar" generico, que manda a pessoa procurar problema no
	-- design quando o que falta e o Passo 1 do checklist.
	if baseUrl() == "" then
		setStatus("Configure o servidor na aba Config (Passo 1).", "err")
		return
	end

	exportId = (exportId or ""):gsub("%s+", ""):gsub("[^%w%-_]", "")
	if exportId == "" then
		setStatus("Informe o ID do export.", "err")
		return
	end

	local manual = useSelection ~= false

	if not manual and lastAutoGui and lastAutoGui.Parent then
		pcall(function() lastAutoGui:Destroy() end)
		lastAutoGui = nil
	end

	setBusy(true)
	local imported, createdGui = importExport(baseUrl(), exportId, setStatus, manual)
	if imported then
		lastImportedId = imported
		Plugin:SetSetting("lastImportedId", imported)
		if not manual then lastAutoGui = createdGui end

		-- Gera os Pre-Scripts sobre a hierarquia recém-criada. Só quando fomos
		-- nós que criamos a ScreenGui: mexer na do usuário é escolha dele,
		-- feita pelo botão "Gerar nos selecionados".
		-- A UI recém-criada passa a ser a referência dos vínculos, para a lista
		-- refletir o que acabou de entrar sem precisar clicar em Detectar.
		if createdGui then
			bindRoot = createdGui
			rebuildBindings()
		end

		if createdGui and anyPreSelected() then
			runGenerate(createdGui, setStatus)
		end

		maybeAskReview()
	end
	setQueueHint(report and report.missing or 0)
	setBusy(false)
end

-- ------------------------------------------------------------ botoes basicos
local function hoverable(button, base, hover)
	button.MouseEnter:Connect(function()
		if not busy then button.BackgroundColor3 = hover end
	end)
	button.MouseLeave:Connect(function()
		if not busy then button.BackgroundColor3 = base end
	end)
end

-- As linhas e os botoes "mini" ja tratam o proprio hover no momento em que sao
-- construidos. Aqui sobram so as acoes primarias.
hoverable(importBtn, T.accent, T.accentHi)
hoverable(generateBtn, T.accent, T.accentHi)

for key, entry in pairs(preRows) do
	local target = key
	entry.hit.MouseButton1Click:Connect(function()
		setPreChecked(target, not preSelected[target])
		refreshQuestions()
		rebuildBindings()
		savePreSelection()
	end)
end


--- Fixa a UI de referencia a partir do Explorer e roda a deteccao.
bindTarget.MouseButton1Click:Connect(function()
	local picked = Selection:Get()[1]
	local gui = picked and (picked:IsA("ScreenGui") and picked or picked:FindFirstAncestorWhichIsA("ScreenGui"))

	if not gui then
		setStatus("Selecione a UI (ou algo dentro dela) no Explorer.", "err")
		return
	end

	bindRoot = gui
	rebuildBindings()

	local required = PreScripts.requiredPaths(preSelected)
	local paths = PreScripts.detect(gui, preSelected, overrides)
	local found = 0
	for _ in pairs(paths) do found += 1 end

	setStatus(found .. "/" .. #required .. " alvo(s) encontrado(s) em " .. gui.Name, found == #required and "ok" or "warn")
end)

--- Gera sobre o que estiver selecionado no Explorer, para reaplicar sem
--- precisar reimportar a UI inteira.
generateBtn.MouseButton1Click:Connect(function()
	if not anyPreSelected() then
		setStatus("Marque ao menos um sistema em Pre-Scripts.", "err")
		return
	end

	local target = Selection:Get()[1]
	if target then
		target = target:IsA("ScreenGui") and target or target:FindFirstAncestorWhichIsA("ScreenGui")
	end
	if not target then
		setStatus("Selecione a ScreenGui da UI no Explorer.", "err")
		return
	end

	local recording = ChangeHistoryService:TryBeginRecording("FigmaPreScripts", "Gerar Pre-Scripts")
	runGenerate(target, setStatus)
	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end
end)

scaleHit.MouseButton1Click:Connect(function()
	responsiveScale = not responsiveScale
	setScaleVisual(responsiveScale)
	Plugin:SetSetting("responsiveScale", responsiveScale)
	if responsiveScale then
		setStatus("Proximos imports ganham UIScale + script de ajuste.", nil)
	else
		setStatus("Imports voltam a usar pixels fixos.", nil)
	end
end)

importBtn.MouseButton1Click:Connect(function()
	doImport(idInput.Text)
end)

idInput.FocusLost:Connect(function(enterPressed)
	if enterPressed then doImport(idInput.Text) end
end)

urlInput.FocusLost:Connect(function()
	Plugin:SetSetting("workerUrl", trimUrl(urlInput.Text))
end)

-- ------------------------------------------------- descoberta automatica ----
-- O uploader roda na maquina e ja sabe a URL do servidor. Em vez de exigir que
-- a pessoa cole a mesma coisa aqui e no Figma (errar um dos dois produzia um
-- erro que parecia bug do plugin), perguntamos a ele.
--
-- So preenche quando o campo esta vazio: uma URL digitada a mao nunca e
-- sobrescrita.
task.spawn(function()
	if trimUrl(urlInput.Text) ~= "" then return end

	local ok, resposta = pcall(function()
		return HttpService:RequestAsync({
			Url = "http://127.0.0.1:34567/",
			Method = "GET",
		})
	end)
	if not ok or not resposta or not resposta.Success then return end

	local lido, dados = pcall(function() return HttpService:JSONDecode(resposta.Body) end)
	if not lido or type(dados) ~= "table" then return end
	if dados.source ~= "FigmaToRoblox-uploader" then return end
	if type(dados.workerUrl) ~= "string" or dados.workerUrl == "" then return end

	urlInput.Text = dados.workerUrl
	Plugin:SetSetting("workerUrl", trimUrl(dados.workerUrl))
	setStatus("Servidor detectado pelo uploader.", "ok")
end)

cmdBox.FocusLost:Connect(function()
	-- O Passo 1 empresta este campo para oferecer o comando de instalacao. Salvar
	-- aquilo como "comando do uploader" deixaria o campo errado para sempre, e a
	-- pessoa reinstalaria o projeto toda vez que fosse subir imagem.
	if cmdBox.Text:sub(1, 4) == "irm " then return end
	Plugin:SetSetting("uploaderCmd", cmdBox.Text)
end)

-- ----------------------------------------------------------------- lista
local function clearList()
	for _, child in ipairs(listHolder:GetChildren()) do
		if child:IsA("TextButton") then child:Destroy() end
	end
end

local function refreshList()
	clearList()
	setStatus("Buscando exports...", "info")

	local ok, exports = pcall(function()
		return Api.get(baseUrl(), "/api/exports")
	end)
	if not ok then
		setStatus("Erro ao listar: " .. tostring(exports), "err")
		return
	end
	if not exports or #exports == 0 then
		setStatus("Nenhum export no servidor ainda.", nil)
		return
	end

	for index, entry in ipairs(exports) do
		if index > 8 then break end

		local pendingSuffix = (entry.pendingCount and entry.pendingCount > 0)
			and ("  ·  " .. entry.pendingCount .. " img pendente")
			or ""

		local item = mk("TextButton", {
			Size = UDim2.new(1, 0, 0, 44),
			BackgroundColor3 = T.panel,
			Text = "",
			BorderSizePixel = 0,
			AutoButtonColor = false,
			LayoutOrder = index,
		}, listHolder)
		round(item, 6)
		stroke(item)

		mk("TextLabel", {
			Size = UDim2.new(1, -20, 0, 14),
			Position = UDim2.fromOffset(10, 8),
			BackgroundTransparency = 1,
			Text = entry.rootName or entry.documentName or "Export",
			TextColor3 = T.txt,
			TextSize = 11,
			Font = Enum.Font.GothamMedium,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, item)

		mk("TextLabel", {
			Size = UDim2.new(1, -20, 0, 12),
			Position = UDim2.fromOffset(10, 23),
			BackgroundTransparency = 1,
			Text = entry.id .. "  ·  " .. (entry.elementCount or "?") .. " elementos" .. pendingSuffix,
			TextColor3 = T.dim,
			TextSize = 9,
			Font = Enum.Font.Code,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, item)

		hoverable(item, T.panel, T.panel2)
		item.MouseButton1Click:Connect(function()
			idInput.Text = entry.id
			doImport(entry.id)
		end)
	end

	setStatus(#exports .. " export(s) encontrado(s).", nil)
end

refreshBtn.MouseButton1Click:Connect(refreshList)

-- -------------------------------------------------------------- auto sync
local syncThread

local function syncLoop()
	while syncEnabled do
		if not busy then
			local ok, latest = pcall(function()
				return Api.get(baseUrl(), "/api/latest")
			end)

			if ok and latest and latest.exportId then
				if latest.exportId ~= lastImportedId and latest.ready then
					idInput.Text = latest.exportId
					doImport(latest.exportId, false)
				elseif latest.exportId ~= lastImportedId and not latest.ready then
					setStatus("Aguardando upload de " .. (latest.pendingImages or 0) .. " imagem(ns)...", "warn")
					setQueueHint(latest.pendingImages or 0)
				end
			end
		end
		task.wait(SYNC_INTERVAL)
	end
end

syncHit.MouseButton1Click:Connect(function()
	syncEnabled = not syncEnabled
	setSyncVisual(syncEnabled)
	Plugin:SetSetting("syncEnabled", syncEnabled)

	if syncEnabled then
		if not checkHttp() then
			syncEnabled = false
			setSyncVisual(false)
			return
		end
		setStatus("Sincronizacao ligada. Exporte no Figma.", "ok")
		syncThread = task.spawn(syncLoop)
	else
		setStatus("Sincronizacao desligada.", nil)
	end
end)

-- ------------------------------------------------------------ inicializacao
loadDecalCache()
loadOverrides()
loadPreSelection()
rebuildBindings()
responsiveScale = Plugin:GetSetting("responsiveScale") == true
setSyncVisual(false)
setScaleVisual(responsiveScale)

toggleButton.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)

widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	toggleButton:SetActive(widget.Enabled)
end)

Plugin.Unloading:Connect(function()
	syncEnabled = false
	for _, connection in ipairs(pluginConnections) do
		pcall(function() connection:Disconnect() end)
	end
	table.clear(pluginConnections)
end)

print("[FigmaToRoblox] v2 carregado. Abra pela barra de plugins.")
