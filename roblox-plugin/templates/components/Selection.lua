--!strict
--[[
	Selection — seleção única ou múltipla sobre um conjunto de botões.

	Separado do SlotGrid de propósito: seleção serve para abas de categoria,
	escolha de personagem, filtros de loja — não só para slots.

		local sel = Selection.new({ btnA, btnB, btnC })
		sel:Select(2)
		sel.Changed:Connect(function(indices) print(#indices, "selecionado(s)") end)

		local multi = Selection.new(botoes, { multiple = true, max = 3 })
]]

local Motion = require(script.Parent.Parent.core.Motion)
local Signal = require(script.Parent.Parent.core.Signal)

local Selection = {}
Selection.__index = Selection

export type Options = {
	multiple: boolean?,
	max: number?,              -- limite no modo múltiplo
	allowEmpty: boolean?,      -- padrão true no múltiplo, false no único
	selectedTransparency: number?,
	idleTransparency: number?,
	selectedScale: number?,
}

function Selection.new(buttons: { GuiButton }, options: Options?)
	assert(#buttons > 0, "Selection.new precisa de ao menos um botão")

	local config = options or {}
	local self = setmetatable({
		buttons = buttons,
		multiple = config.multiple == true,
		max = config.max,
		allowEmpty = config.allowEmpty,
		selectedAlpha = config.selectedTransparency or 0,
		idleAlpha = config.idleTransparency or 0.5,
		selectedScale = config.selectedScale,
		chosen = {} :: { [number]: boolean },
		Changed = Signal.new(),
	}, Selection)

	if self.allowEmpty == nil then
		self.allowEmpty = self.multiple
	end

	for index, button in ipairs(buttons) do
		button.MouseButton1Click:Connect(function()
			self:Toggle(index)
		end)
	end

	self:_render(true)
	return self
end

--- Coleta os filhos GuiButton de um container, na ordem do layout.
function Selection.fromContainer(container: GuiObject, options: Options?)
	local buttons: { GuiButton } = {}
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("GuiButton") then table.insert(buttons, child) end
	end
	table.sort(buttons, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
	return Selection.new(buttons, options)
end

function Selection:_scaleOf(button: GuiButton): UIScale?
	if not self.selectedScale then return nil end

	local existing = button:FindFirstChild("SelectionScale")
	if existing and existing:IsA("UIScale") then return existing end

	local scale = Instance.new("UIScale")
	scale.Name = "SelectionScale"
	scale.Parent = button
	return scale
end

function Selection:_render(immediate: boolean?)
	for index, button in ipairs(self.buttons) do
		local isChosen = self.chosen[index] == true
		local alpha = isChosen and self.selectedAlpha or self.idleAlpha

		if immediate then
			button.BackgroundTransparency = alpha
		else
			Motion.to(button, Motion.Easing.Fast, { BackgroundTransparency = alpha })
		end

		local scale = self:_scaleOf(button)
		if scale then
			local target = isChosen and (self.selectedScale :: number) or 1
			if immediate then scale.Scale = target
			else Motion.to(scale, Motion.Easing.Fast, { Scale = target }) end
		end
	end
end

function Selection:Toggle(index: number)
	if not self.buttons[index] then return end

	if self.multiple then
		if self.chosen[index] then
			-- Desmarcar o último só é permitido se vazio for aceitável.
			if not self.allowEmpty and #self:Get() == 1 then return end
			self.chosen[index] = nil
		else
			if self.max and #self:Get() >= self.max then return end
			self.chosen[index] = true
		end
	else
		if self.chosen[index] then
			if not self.allowEmpty then return end
			self.chosen[index] = nil
		else
			table.clear(self.chosen)
			self.chosen[index] = true
		end
	end

	self:_render()
	self.Changed:Fire(self:Get())
end

function Selection:Select(index: number)
	if self.chosen[index] then return end
	self:Toggle(index)
end

function Selection:Clear()
	if not next(self.chosen) then return end
	table.clear(self.chosen)
	self:_render()
	self.Changed:Fire({})
end

--- Índices selecionados, em ordem crescente.
function Selection:Get(): { number }
	local indices = {}
	for index in pairs(self.chosen) do table.insert(indices, index) end
	table.sort(indices)
	return indices
end

--- Primeiro selecionado, ou nil. Atalho para o modo único.
function Selection:GetFirst(): number?
	return self:Get()[1]
end

function Selection:IsSelected(index: number): boolean
	return self.chosen[index] == true
end

function Selection:Destroy()
	self.Changed:DisconnectAll()
end

return Selection
