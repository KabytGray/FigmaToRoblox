--!strict
--[[
	SlotGrid — clona um slot modelo N vezes e devolve controle sobre cada um.

	É a base de inventário, hotbar e loja. O modelo é um slot que você desenhou
	no Figma: o grid clona, numera e some com o original, então o que você vê no
	Studio é o que o jogador vê.

		local grid = SlotGrid.new(container, modelo, { count = 20, columns = 5 })
		grid:Get(3).Instance.Visible = false
		grid:Set(3, { icon = "rbxassetid://123", amount = 5 })
		grid.SlotClicked:Connect(function(index, slot) print(index) end)
]]

local Signal = require(script.Parent.Parent.core.Signal)
local ButtonFx = require(script.Parent.ButtonFx)

local SlotGrid = {}
SlotGrid.__index = SlotGrid

export type Options = {
	count: number?,
	columns: number?,      -- se ausente, mantém o layout já existente
	padding: number?,
	buttonFx: boolean?,    -- padrão true
	iconName: string?,     -- nome do ImageLabel dentro do slot
	amountName: string?,   -- nome do TextLabel de quantidade
	labelName: string?,    -- nome do TextLabel de nome
}

export type Slot = {
	Index: number,
	Instance: GuiObject,
	Icon: ImageLabel?,
	Amount: TextLabel?,
	Label: TextLabel?,
	Data: any,
}

--- Procura por nome exato e, se não achar, pelo primeiro filho da classe. Isso
--- deixa o grid funcionar com nomes de camada quaisquer vindos do Figma.
local function findPart(slot: GuiObject, name: string?, className: string): Instance?
	if name then
		local exact = slot:FindFirstChild(name, true)
		if exact then return exact end
	end
	for _, descendant in ipairs(slot:GetDescendants()) do
		if descendant:IsA(className) then return descendant end
	end
	return nil
end

function SlotGrid.new(container: GuiObject, template: GuiObject, options: Options?)
	assert(container and container:IsA("GuiObject"), "SlotGrid: container inválido")
	assert(template and template:IsA("GuiObject"), "SlotGrid: template inválido")

	local config = options or {}
	local self = setmetatable({
		container = container,
		template = template,
		slots = {} :: { Slot },
		config = config,
		SlotClicked = Signal.new(),
		SlotHovered = Signal.new(),
	}, SlotGrid)

	-- O modelo fica no projeto para você continuar editando, mas fora da vista.
	template.Visible = false

	if config.columns then
		self:_ensureGridLayout(config.columns, config.padding or 6)
	end

	self:SetCount(config.count or 1)
	return self
end

function SlotGrid:_ensureGridLayout(columns: number, padding: number)
	local existing = self.container:FindFirstChildOfClass("UIGridLayout")
	local layout = existing or Instance.new("UIGridLayout")
	layout.Name = "SlotLayout"
	layout.CellPadding = UDim2.fromOffset(padding, padding)

	-- Célula derivada do modelo. Prefere Size.Offset a AbsoluteSize: no modo de
	-- edição o Absolute pode ser 0 até a GUI ser renderizada, e o import sempre
	-- escreve o tamanho em offset.
	local width = self.template.Size.X.Offset
	local height = self.template.Size.Y.Offset
	if width <= 0 then width = self.template.AbsoluteSize.X end
	if height <= 0 then height = self.template.AbsoluteSize.Y end
	layout.CellSize = UDim2.fromOffset(math.max(1, width), math.max(1, height))
	layout.FillDirectionMaxCells = columns
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = self.container

	-- UIListLayout e UIGridLayout no mesmo pai brigam pelo posicionamento.
	local list = self.container:FindFirstChildOfClass("UIListLayout")
	if list then list:Destroy() end
end

function SlotGrid:_build(index: number): Slot
	local instance = self.template:Clone()
	instance.Name = string.format("Slot%02d", index)
	instance.Visible = true
	instance.LayoutOrder = index
	instance.Parent = self.container

	local slot: Slot = {
		Index = index,
		Instance = instance,
		Icon = findPart(instance, self.config.iconName, "ImageLabel") :: ImageLabel?,
		Amount = self.config.amountName and instance:FindFirstChild(self.config.amountName, true) :: TextLabel? or nil,
		Label = self.config.labelName and instance:FindFirstChild(self.config.labelName, true) :: TextLabel? or nil,
		Data = nil,
	}

	if instance:IsA("GuiButton") then
		if self.config.buttonFx ~= false then ButtonFx.apply(instance) end
		instance.MouseButton1Click:Connect(function()
			self.SlotClicked:Fire(index, slot)
		end)
		instance.MouseEnter:Connect(function()
			self.SlotHovered:Fire(index, slot)
		end)
	end

	return slot
end

--- Cresce ou encolhe até `count`. Chamável a qualquer momento (ex: mochila
--- expandida por upgrade) sem recriar os slots que já existem.
function SlotGrid:SetCount(count: number)
	count = math.max(0, math.floor(count))

	for index = #self.slots + 1, count do
		self.slots[index] = self:_build(index)
	end
	for index = #self.slots, count + 1, -1 do
		self.slots[index].Instance:Destroy()
		self.slots[index] = nil
	end
end

function SlotGrid:Get(index: number): Slot?
	return self.slots[index]
end

function SlotGrid:Count(): number
	return #self.slots
end

--- Preenche um slot. Passe nil para esvaziar.
function SlotGrid:Set(index: number, data: { icon: string?, amount: number?, label: string? }?)
	local slot = self.slots[index]
	if not slot then return end

	slot.Data = data

	if slot.Icon then
		slot.Icon.Image = data and data.icon or ""
		slot.Icon.Visible = data ~= nil and data.icon ~= nil
	end
	if slot.Amount then
		local amount = data and data.amount
		-- Quantidade 1 poluiria a tela: só mostra quando empilhado.
		slot.Amount.Text = (amount and amount > 1) and tostring(amount) or ""
	end
	if slot.Label then
		slot.Label.Text = data and data.label or ""
	end
end

--- Substitui todo o conteúdo de uma vez. Índices sem dado ficam vazios.
function SlotGrid:Fill(items: { any })
	for index = 1, #self.slots do
		self:Set(index, items[index])
	end
end

function SlotGrid:Clear()
	self:Fill({})
end

--- Primeiro índice livre, ou nil se está cheio.
function SlotGrid:FirstEmpty(): number?
	for index, slot in ipairs(self.slots) do
		if slot.Data == nil then return index end
	end
	return nil
end

function SlotGrid:Destroy()
	for _, slot in ipairs(self.slots) do slot.Instance:Destroy() end
	table.clear(self.slots)
	self.SlotClicked:DisconnectAll()
	self.SlotHovered:DisconnectAll()
end

return SlotGrid
