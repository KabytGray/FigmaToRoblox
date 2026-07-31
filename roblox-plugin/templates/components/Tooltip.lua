--!strict
--[[
	Tooltip — texto que aparece ao passar o mouse, seguindo o cursor.

	Usa um modelo que você desenhou. O posicionamento se vira sozinho perto das
	bordas: sem isso o tooltip sai da tela justamente nos cantos, que é onde a
	maior parte da HUD fica.

		Tooltip.setup(modeloTooltip)
		Tooltip.bind(botao, "Espada de ferro\nDano 12")
		Tooltip.bind(slot, function() return slot.Data.description end)
]]

local UserInputService = game:GetService("UserInputService")

local Motion = require(script.Parent.Parent.core.Motion)

local Tooltip = {}

local card: GuiObject? = nil
local label: TextLabel? = nil
local moveConnection: RBXScriptConnection? = nil

Tooltip.Offset = Vector2.new(14, 14)
Tooltip.Delay = 0.35

--- Registra o modelo. Ele é reutilizado, não clonado: um tooltip por vez.
function Tooltip.setup(model: GuiObject, textName: string?)
	card = model
	label = (textName and model:FindFirstChild(textName, true) or model:FindFirstChildWhichIsA("TextLabel", true)) :: TextLabel?
	model.Visible = false
	-- Precisa ficar acima de tudo e não roubar o hover de quem está embaixo.
	model.ZIndex = 1000
	if model:IsA("GuiObject") then model.Active = false end
end

local function place()
	if not card then return end

	local screen = card:FindFirstAncestorWhichIsA("ScreenGui")
	local bounds = screen and screen.AbsoluteSize or Vector2.new(1920, 1080)
	local size = card.AbsoluteSize
	local mouse = UserInputService:GetMouseLocation()

	local x = mouse.X + Tooltip.Offset.X
	local y = mouse.Y + Tooltip.Offset.Y

	-- Vira para o outro lado quando não cabe, em vez de sair da tela.
	if x + size.X > bounds.X then x = mouse.X - size.X - Tooltip.Offset.X end
	if y + size.Y > bounds.Y then y = mouse.Y - size.Y - Tooltip.Offset.Y end

	local inset = (screen and screen.IgnoreGuiInset) and 0 or 36
	card.Position = UDim2.fromOffset(x, y - inset)
end

function Tooltip.show(text: string)
	if not card then
		warn("[Tooltip] chame Tooltip.setup(modelo) antes")
		return
	end
	if label then label.Text = text end

	place()
	card.Visible = true
	Motion.to(card, Motion.Easing.Fast, { BackgroundTransparency = 0 })

	if not moveConnection then
		moveConnection = UserInputService.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement then place() end
		end)
	end
end

function Tooltip.hide()
	if not card then return end
	card.Visible = false
	if moveConnection then
		moveConnection:Disconnect()
		moveConnection = nil
	end
end

--- Liga um alvo ao tooltip. `content` pode ser texto fixo ou uma função
--- avaliada no hover (para conteúdo que muda, como o item de um slot).
--- Devolve a limpeza.
function Tooltip.bind(target: GuiObject, content: string | (() -> string?)): () -> ()
	local connections: { RBXScriptConnection } = {}
	local token = 0

	table.insert(connections, target.MouseEnter:Connect(function()
		token += 1
		local mine = token

		task.delay(Tooltip.Delay, function()
			-- Saiu antes do delay acabar: não mostra.
			if mine ~= token then return end

			local text = type(content) == "function" and content() or content
			if text and text ~= "" then Tooltip.show(text) end
		end)
	end))

	table.insert(connections, target.MouseLeave:Connect(function()
		token += 1
		Tooltip.hide()
	end))

	return function()
		for _, connection in ipairs(connections) do connection:Disconnect() end
	end
end

return Tooltip
