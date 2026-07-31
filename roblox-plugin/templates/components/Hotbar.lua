--!strict
--[[
	Hotbar — barra de atalhos com teclas 1..9 e seleção visual.

	Construída sobre SlotGrid, então herda clique, hover e preenchimento. O que
	ela adiciona é o vínculo com o teclado e o destaque do slot ativo.

		local hotbar = Hotbar.new(container, modeloSlot, { count = 6 })
		hotbar.Activated:Connect(function(index, slot)
			usarItem(slot.Data)
		end)
]]

local ContextActionService = game:GetService("ContextActionService")

local Motion = require(script.Parent.Parent.core.Motion)
local Signal = require(script.Parent.Parent.core.Signal)
local SlotGrid = require(script.Parent.SlotGrid)

local Hotbar = {}
Hotbar.__index = Hotbar

local KEYS = {
	Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three,
	Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six,
	Enum.KeyCode.Seven, Enum.KeyCode.Eight, Enum.KeyCode.Nine,
}

export type Options = {
	count: number?,
	horizontal: boolean?,     -- padrão true
	padding: number?,
	selectedScale: number?,   -- destaque do slot ativo, padrão 1.08
	bindKeys: boolean?,       -- padrão true
	iconName: string?,
	amountName: string?,
}

function Hotbar.new(container: GuiObject, template: GuiObject, options: Options?)
	local config = options or {}
	local count = math.clamp(config.count or 6, 1, 9)

	local self = setmetatable({
		selected = 0,
		selectedScale = config.selectedScale or 1.08,
		actionNames = {} :: { string },
		Activated = Signal.new(),
		SelectionChanged = Signal.new(),
	}, Hotbar)

	-- Hotbar é uma linha (ou coluna): uma "grade" de N colunas resolve os dois.
	self.grid = SlotGrid.new(container, template, {
		count = count,
		columns = (config.horizontal ~= false) and count or 1,
		padding = config.padding or 6,
		iconName = config.iconName,
		amountName = config.amountName,
	})

	self.grid.SlotClicked:Connect(function(index, slot)
		self:Select(index)
		self.Activated:Fire(index, slot)
	end)

	if config.bindKeys ~= false then self:_bindKeys(count) end

	self:Select(1)
	return self
end

function Hotbar:_bindKeys(count: number)
	for index = 1, count do
		local name = "FigmaUI_Hotbar" .. index
		table.insert(self.actionNames, name)

		ContextActionService:BindAction(name, function(_, state)
			if state ~= Enum.UserInputState.Begin then return end
			self:Select(index)
			self.Activated:Fire(index, self.grid:Get(index))
		end, false, KEYS[index])
	end
end

--- Destaca o slot ativo via UIScale, para não brigar com o layout da grade.
function Hotbar:Select(index: number)
	if index == self.selected then return end
	if not self.grid:Get(index) then return end

	local function scaleOf(slot): UIScale?
		local existing = slot.Instance:FindFirstChild("SelectScale")
		if existing and existing:IsA("UIScale") then return existing end

		local scale = Instance.new("UIScale")
		scale.Name = "SelectScale"
		scale.Parent = slot.Instance
		return scale
	end

	local previous = self.grid:Get(self.selected)
	if previous then
		local scale = scaleOf(previous)
		if scale then Motion.to(scale, Motion.Easing.Fast, { Scale = 1 }) end
	end

	self.selected = index

	local current = self.grid:Get(index)
	if current then
		local scale = scaleOf(current)
		if scale then Motion.to(scale, Motion.Easing.Pop, { Scale = self.selectedScale }) end
	end

	self.SelectionChanged:Fire(index, current)
end

function Hotbar:Set(index: number, data: any)
	self.grid:Set(index, data)
end

function Hotbar:Fill(items: { any })
	self.grid:Fill(items)
end

function Hotbar:GetSelected()
	return self.selected, self.grid:Get(self.selected)
end

function Hotbar:Destroy()
	for _, name in ipairs(self.actionNames) do
		ContextActionService:UnbindAction(name)
	end
	self.grid:Destroy()
	self.Activated:DisconnectAll()
	self.SelectionChanged:DisconnectAll()
end

return Hotbar
