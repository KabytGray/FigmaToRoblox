-- ============================================================
-- FigmaToRoblox - Plugin Roblox Studio
-- src/init.lua
-- Plugin principal que adiciona o botão "Importar do Figma"
-- ============================================================

local Plugin = plugin or script
assert(Plugin, "Este script deve rodar como um Plugin do Roblox Studio")

-- Carrega os módulos auxiliares
local HttpService = game:GetService("HttpService")
local StudioService = game:GetService("StudioService")

local HttpClient = require(script.Modules.HttpClient)
local ElementBuilder = require(script.Modules.ElementBuilder)

-- ============================================================
-- CRIA A BARRA DE FERRAMENTAS DO PLUGIN
-- ============================================================

local toolbar = Plugin:CreateToolbar("FigmaToRoblox")

-- Botão principal: Importar
local importButton = toolbar:CreateButton(
	"Importar do Figma",
	"Importa a interface exportada do Figma",
	"rbxassetid://4458901886" -- Ícone placeholder
)

-- Botão: Selecionar export por ID
local selectButton = toolbar:CreateButton(
	"Buscar por ID",
	"Importa usando um ID específico de export",
	"rbxassetid://4458901886"
)

-- ============================================================
-- WIDGET (PAINEL LATERAL DO PLUGIN)
-- ============================================================

local widgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Float,  -- Começa flutuando
	false,  -- Não é inicialmente ativo
	false,  -- Não sobrescreve estado anterior
	400,    -- Largura
	500,    -- Altura
	200,    -- Largura mínima
	200     -- Altura mínima
)

local widget = Plugin:CreateDockWidgetPluginGui(
	"FigmaToRoblox_Panel",
	widgetInfo
)

widget.Title = "FigmaToRoblox"
widget.Name = "FigmaToRoblox_Panel"

-- Conteúdo do widget
local gui = Instance.new("ScreenGui")
gui.Name = "WidgetContent"
gui.Parent = widget

local mainFrame = Instance.new("Frame")
mainFrame.Name = "Main"
mainFrame.Size = UDim2.new(1, 0, 1, 0)
mainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
mainFrame.BorderSizePixel = 0
mainFrame.Parent = gui

-- Título
local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(1, 0, 0, 40)
title.BackgroundTransparency = 1
title.Text = "FigmaToRoblox"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextSize = 20
title.Font = Enum.Font.GothamBold
title.Parent = mainFrame

-- Campo de URL do Worker
local urlLabel = Instance.new("TextLabel")
urlLabel.Name = "UrlLabel"
urlLabel.Size = UDim2.new(1, -20, 0, 20)
urlLabel.Position = UDim2.new(0, 10, 0, 50)
urlLabel.BackgroundTransparency = 1
urlLabel.Text = "URL do Worker:"
urlLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
urlLabel.TextSize = 12
urlLabel.Font = Enum.Font.Gotham
urlLabel.TextXAlignment = Enum.TextXAlignment.Left
urlLabel.Parent = mainFrame

local urlInput = Instance.new("TextBox")
urlInput.Name = "UrlInput"
urlInput.Size = UDim2.new(1, -20, 0, 30)
urlInput.Position = UDim2.new(0, 10, 0, 72)
urlInput.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
urlInput.TextColor3 = Color3.fromRGB(255, 255, 255)
urlInput.PlaceholderText = "https://seu-worker.workers.dev"
urlInput.PlaceholderColor3 = Color3.fromRGB(120, 120, 120)
urlInput.Text = ""
urlInput.TextSize = 12
urlInput.Font = Enum.Font.Gotham
urlInput.BorderSizePixel = 0
urlInput.Parent = mainFrame

-- Campo de ID do Export
local idLabel = Instance.new("TextLabel")
idLabel.Name = "IdLabel"
idLabel.Size = UDim2.new(1, -20, 0, 20)
idLabel.Position = UDim2.new(0, 10, 0, 115)
idLabel.BackgroundTransparency = 1
idLabel.Text = "ID do Export:"
idLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
idLabel.TextSize = 12
idLabel.Font = Enum.Font.Gotham
idLabel.TextXAlignment = Enum.TextXAlignment.Left
idLabel.Parent = mainFrame

local idInput = Instance.new("TextBox")
idInput.Name = "IdInput"
idInput.Size = UDim2.new(1, -20, 0, 30)
idInput.Position = UDim2.new(0, 10, 0, 137)
idInput.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
idInput.TextColor3 = Color3.fromRGB(255, 255, 255)
idInput.PlaceholderText = "cole o ID aqui"
idInput.PlaceholderColor3 = Color3.fromRGB(120, 120, 120)
idInput.Text = ""
idInput.TextSize = 12
idInput.Font = Enum.Font.Gotham
idInput.BorderSizePixel = 0
idInput.Parent = mainFrame

-- Botão Importar
local importWidgetButton = Instance.new("TextButton")
importWidgetButton.Name = "ImportButton"
importWidgetButton.Size = UDim2.new(1, -20, 0, 40)
importWidgetButton.Position = UDim2.new(0, 10, 0, 185)
importWidgetButton.BackgroundColor3 = Color3.fromRGB(124, 92, 252)
importWidgetButton.TextColor3 = Color3.fromRGB(255, 255, 255)
importWidgetButton.Text = "Importar"
importWidgetButton.TextSize = 14
importWidgetButton.Font = Enum.Font.GothamBold
importWidgetButton.BorderSizePixel = 0
importWidgetButton.Parent = mainFrame

-- Área de Status
local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "StatusLabel"
statusLabel.Size = UDim2.new(1, -20, 0, 40)
statusLabel.Position = UDim2.new(0, 10, 0, 240)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = ""
statusLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
statusLabel.TextSize = 11
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextWrapped = true
statusLabel.Parent = mainFrame

-- ============================================================
-- FUNÇÕES DO PLUGIN
-- ============================================================

local function setStatus(message, isError)
	statusLabel.Text = message
	if isError then
		statusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
	else
		statusLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
	end
end

local function importFromFigma(exportId)
	local workerUrl = urlInput.Text

	if workerUrl == "" then
		setStatus("Erro: Insira a URL do Worker", true)
		return
	end

	if exportId == "" then
		setStatus("Erro: Insira o ID do Export", true)
		return
	end

	setStatus("Conectando ao servidor...", false)

	-- Busca os dados do Cloudflare Worker
	local success, result = pcall(function()
		return HttpClient.getExport(workerUrl, exportId)
	end)

	if not success then
		setStatus("Erro ao conectar: " .. tostring(result), true)
		return
	end

	if not result or not result.elements then
		setStatus("Erro: Dados inválidos recebidos", true)
		return
	end

	setStatus("Construindo elementos...", false)

	-- Procura um ScreenGui ou StarterGui para colocar os elementos
	local targetParent = nil

	-- Tenta encontrar o StarterGui
	local starterGui = game:GetService("StarterGui")
	if starterGui then
		-- Cria um novo ScreenGui com o nome do documento
		local screenGui = Instance.new("ScreenGui")
		screenGui.Name = "Figma_" .. (result.documentName or "Import")
		screenGui.Parent = starterGui
		targetParent = screenGui
	else
		-- Fallback: coloca no workspace (não ideal, mas funcional)
		targetParent = workspace
	end

	-- Constrói os elementos
	local buildSuccess, buildResult = pcall(function()
		local builtElements = {}
		for _, element in ipairs(result.elements) do
			local built = ElementBuilder.build(element)
			if built then
				built.Parent = targetParent
				table.insert(builtElements, built)
			end
		end
		return builtElements
	end)

	if not buildSuccess then
		setStatus("Erro ao construir: " .. tostring(buildResult), true)
		return
	end

	local count = #(buildSuccess and buildResult or {})
	setStatus("Sucesso! " .. count .. " elementos importados.", false)

	-- Seleciona o ScreenGui no Explorer
	if targetParent and targetParent:IsA("ScreenGui") then
		StudioService:SetSelectedAsync({targetParent})
	end
end

-- ============================================================
-- CONEXÃO DOS BOTÕES
-- ============================================================

importButton.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)

selectButton.Click:Connect(function()
	widget.Enabled = true
	idInput:CaptureFocus()
end)

importWidgetButton.MouseButton1Click:Connect(function()
	importFromFigma(idInput.Text)
end)

-- ============================================================
-- INICIALIZAÇÃO
-- ============================================================

print("✅ FigmaToRoblox Plugin carregado!")
