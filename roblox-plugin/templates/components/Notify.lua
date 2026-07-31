--!strict
--[[
	Notify — notificações empilhadas a partir de um modelo que você desenhou.

	O modelo fica invisível no projeto; cada notificação é um clone que entra,
	espera e sai. A pilha se reorganiza sozinha via UIListLayout.

		Notify.setup(container, modelo)
		Notify.show("Item comprado")
		Notify.show("Sem moedas", { duration = 4, kind = "error" })
]]

local Motion = require(script.Parent.Parent.core.Motion)

local Notify = {}

local container: GuiObject? = nil
local template: GuiObject? = nil
local active: { GuiObject } = {}

--- Contador monotônico para o LayoutOrder: garante que o mais novo entre por
--- baixo do anterior, sem depender de relógio.
local order = 0

export type Options = {
	duration: number?,           -- segundos, padrão 3
	kind: string?,               -- "info" | "success" | "error" | "warn"
	titleName: string?,
	bodyName: string?,
}

--- Cores por tipo. Trocar aqui muda todas as notificações do jogo.
Notify.Colors = {
	info = Color3.fromRGB(120, 130, 150),
	success = Color3.fromRGB(107, 163, 104),
	warn = Color3.fromRGB(184, 137, 74),
	error = Color3.fromRGB(192, 91, 91),
}

Notify.MaxVisible = 4

--- Registra o container e o modelo. Chame uma vez, no boot da UI.
function Notify.setup(host: GuiObject, model: GuiObject)
	container = host
	template = model
	model.Visible = false

	-- Sem layout as notificações se sobrepõem no mesmo ponto.
	if not host:FindFirstChildOfClass("UIListLayout") then
		local layout = Instance.new("UIListLayout")
		layout.Name = "NotifyLayout"
		layout.Padding = UDim.new(0, 8)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.VerticalAlignment = Enum.VerticalAlignment.Top
		layout.Parent = host
	end
end

local function dismiss(card: GuiObject)
	local index = table.find(active, card)
	if index then table.remove(active, index) end

	Motion.to(card, Motion.Easing.Fast, {
		BackgroundTransparency = 1,
		Position = card.Position + UDim2.fromOffset(24, 0),
	}).Completed:Once(function()
		card:Destroy()
	end)
end

--- Mostra uma notificação. Devolve o clone, se precisar mexer nele.
function Notify.show(message: string, options: Options?): GuiObject?
	if not container or not template then
		warn("[Notify] chame Notify.setup(container, modelo) antes")
		return nil
	end

	local config = options or {}

	-- Acima do limite as mais antigas saem, senão a pilha cobre a tela.
	while #active >= Notify.MaxVisible do
		dismiss(active[1])
	end

	local card = template:Clone()
	card.Name = "Notification"
	card.Visible = true
	order += 1
	card.LayoutOrder = order
	card.Parent = container
	table.insert(active, card)

	local body = (config.bodyName and card:FindFirstChild(config.bodyName, true))
		or card:FindFirstChildWhichIsA("TextLabel", true)
	if body and body:IsA("TextLabel") then body.Text = message end

	if config.titleName then
		local title = card:FindFirstChild(config.titleName, true)
		if title and title:IsA("TextLabel") then title.Text = config.kind or "info" end
	end

	local accent = config.kind and Notify.Colors[config.kind]
	if accent then
		local stroke = card:FindFirstChildOfClass("UIStroke")
		if stroke then stroke.Color = accent end
	end

	local origin = card.Position
	card.Position = origin + UDim2.fromOffset(24, 0)
	Motion.to(card, Motion.Easing.Out, { Position = origin })

	task.delay(config.duration or 3, function()
		if card.Parent then dismiss(card) end
	end)

	return card
end

function Notify.success(message: string, duration: number?)
	return Notify.show(message, { kind = "success", duration = duration })
end

function Notify.error(message: string, duration: number?)
	return Notify.show(message, { kind = "error", duration = duration })
end

function Notify.clear()
	for _, card in ipairs(table.clone(active)) do dismiss(card) end
end

return Notify
