--!strict
--[[
	Window — abrir e fechar qualquer painel com animação, ESC e backdrop.

	Resolve o que todo jogo reescreve: o painel some sem piscar, o ESC fecha,
	o clique fora fecha, e abrir um painel modal fecha os outros.

		local loja = Window.new(painelLoja, {
			openButton = botaoAbrirLoja,
			closeButton = botaoFechar,
			modal = true,
		})
		loja:Open()
		loja.Opened:Connect(function() print("abriu") end)
]]

local ContextActionService = game:GetService("ContextActionService")

local Motion = require(script.Parent.Parent.core.Motion)
local Signal = require(script.Parent.Parent.core.Signal)

local Window = {}
Window.__index = Window

--- Todas as janelas modais abertas, para uma fechar as outras.
local openModals: { any } = {}
local escapeBound = false

export type Options = {
	openButton: GuiButton?,
	closeButton: GuiButton?,
	modal: boolean?,        -- fecha outras modais ao abrir
	backdrop: boolean?,     -- escurece o fundo e fecha ao clicar fora
	startOpen: boolean?,
	escapeToClose: boolean?, -- padrão true
}

local function buildBackdrop(window: GuiObject): TextButton
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 1
	backdrop.BorderSizePixel = 0
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Visible = false
	-- Um abaixo da janela: escurece o resto sem cobrir o conteúdo.
	backdrop.ZIndex = window.ZIndex - 1
	backdrop.Parent = window.Parent
	return backdrop
end

function Window.new(frame: GuiObject, options: Options?)
	assert(frame and frame:IsA("GuiObject"), "Window.new espera um GuiObject")

	local config = options or {}
	local self = setmetatable({
		frame = frame,
		modal = config.modal == true,
		isOpen = false,
		connections = {},
		scale = frame:FindFirstChildOfClass("UIScale") or Instance.new("UIScale"),

		Opened = Signal.new(),
		Closed = Signal.new(),
	}, Window)

	self.scale.Name = "WindowScale"
	self.scale.Parent = frame

	if config.backdrop then
		self.backdrop = buildBackdrop(frame)
		table.insert(self.connections, self.backdrop.MouseButton1Click:Connect(function()
			self:Close()
		end))
	end

	if config.openButton then
		table.insert(self.connections, config.openButton.MouseButton1Click:Connect(function()
			self:Toggle()
		end))
	end

	if config.closeButton then
		table.insert(self.connections, config.closeButton.MouseButton1Click:Connect(function()
			self:Close()
		end))
	end

	frame.Visible = false
	if config.escapeToClose ~= false then Window._bindEscape() end
	if config.startOpen then self:Open() end

	return self
end

--- ESC fecha a última janela aberta. Bind único e global: uma janela por vez.
function Window._bindEscape()
	if escapeBound then return end
	escapeBound = true

	ContextActionService:BindAction("FigmaUI_CloseWindow", function(_, state)
		if state ~= Enum.UserInputState.Begin then return end
		local top = openModals[#openModals]
		if top then top:Close() end
	end, false, Enum.KeyCode.Escape)
end

function Window:Open()
	if self.isOpen then return end

	if self.modal then
		for _, other in ipairs(table.clone(openModals)) do
			if other ~= self then other:Close() end
		end
	end

	self.isOpen = true
	table.insert(openModals, self)

	self.frame.Visible = true
	self.scale.Scale = 0.94
	Motion.to(self.scale, Motion.Easing.Pop, { Scale = 1 })

	if self.backdrop then
		self.backdrop.Visible = true
		self.backdrop.BackgroundTransparency = 1
		Motion.to(self.backdrop, Motion.Easing.Out, { BackgroundTransparency = 0.5 })
	end

	self.Opened:Fire()
end

function Window:Close()
	if not self.isOpen then return end
	self.isOpen = false

	local index = table.find(openModals, self)
	if index then table.remove(openModals, index) end

	-- Esconde só no fim, senão o painel pisca fora antes de animar.
	Motion.to(self.scale, Motion.Easing.Fast, { Scale = 0.94 }).Completed:Once(function()
		if not self.isOpen then self.frame.Visible = false end
	end)

	if self.backdrop then
		Motion.to(self.backdrop, Motion.Easing.Fast, { BackgroundTransparency = 1 }).Completed:Once(function()
			if not self.isOpen and self.backdrop then self.backdrop.Visible = false end
		end)
	end

	self.Closed:Fire()
end

function Window:Toggle()
	if self.isOpen then self:Close() else self:Open() end
end

function Window:Destroy()
	self:Close()
	for _, connection in ipairs(self.connections) do connection:Disconnect() end
	if self.backdrop then self.backdrop:Destroy() end
	self.Opened:DisconnectAll()
	self.Closed:DisconnectAll()
end

return Window
