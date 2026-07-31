--!strict
--[[
	Draggable — arrastar painéis e arrastar-e-soltar entre slots.

	Dois usos distintos:

	  Draggable.panel(janela, barraDeTitulo)   -- mover a janela pela barra
	  Draggable.items(grid, { onDrop = ... })  -- trocar itens entre slots

	No modo `items` o item não sai do lugar: um fantasma segue o mouse e o slot
	de origem continua visível. Isso evita o buraco na grade que faz a UI
	parecer quebrada no meio do arraste.
]]

local UserInputService = game:GetService("UserInputService")

local Motion = require(script.Parent.Parent.core.Motion)
local Signal = require(script.Parent.Parent.core.Signal)

local Draggable = {}

-- ---------------------------------------------------------------- painéis ---

--- Torna `frame` arrastável pelo `handle` (ou por ele mesmo).
--- Devolve uma função de limpeza.
function Draggable.panel(frame: GuiObject, handle: GuiObject?): () -> ()
	local grip = handle or frame
	local connections: { RBXScriptConnection } = {}
	local dragging = false
	local startInput: Vector3
	local startPosition: UDim2

	table.insert(connections, grip.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then return end

		dragging = true
		startInput = input.Position
		startPosition = frame.Position

		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then dragging = false end
		end)
	end))

	table.insert(connections, UserInputService.InputChanged:Connect(function(input)
		if not dragging then return end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch then return end

		local delta = input.Position - startInput
		frame.Position = UDim2.new(
			startPosition.X.Scale, startPosition.X.Offset + delta.X,
			startPosition.Y.Scale, startPosition.Y.Offset + delta.Y
		)
	end))

	return function()
		for _, connection in ipairs(connections) do connection:Disconnect() end
	end
end

-- ------------------------------------------------------------------ itens ---

export type ItemOptions = {
	--- Chamado ao soltar. Devolva false para recusar a troca.
	onDrop: ((fromIndex: number, toIndex: number) -> boolean?)?,
	ghostTransparency: number?,
}

--- Habilita arrastar-e-soltar sobre um SlotGrid. Devolve um objeto com
--- `.Dropped` e `:Destroy()`.
function Draggable.items(grid: any, options: ItemOptions?)
	local config = options or {}
	local api = { Dropped = Signal.new(), _connections = {} :: { RBXScriptConnection } }

	local dragging: number? = nil
	local ghost: GuiObject? = nil

	local function clearGhost()
		if ghost then ghost:Destroy() end
		ghost = nil
		dragging = nil
	end

	--- Slot sob o cursor, comparando com o retângulo absoluto de cada um.
	local function slotUnderCursor(position: Vector2): number?
		for index = 1, grid:Count() do
			local slot = grid:Get(index)
			if slot then
				local topLeft = slot.Instance.AbsolutePosition
				local size = slot.Instance.AbsoluteSize
				if position.X >= topLeft.X and position.X <= topLeft.X + size.X
					and position.Y >= topLeft.Y and position.Y <= topLeft.Y + size.Y then
					return index
				end
			end
		end
		return nil
	end

	for index = 1, grid:Count() do
		local slot = grid:Get(index)
		if slot and slot.Instance:IsA("GuiButton") then
			table.insert(api._connections, slot.Instance.MouseButton1Down:Connect(function()
				if slot.Data == nil then return end -- slot vazio não arrasta

				dragging = index
				ghost = slot.Instance:Clone()
				local clone = ghost :: GuiObject
				clone.Name = "DragGhost"
				clone.Active = false
				clone.ZIndex = 500
				clone.AnchorPoint = Vector2.new(0.5, 0.5)
				clone.Parent = slot.Instance:FindFirstAncestorWhichIsA("ScreenGui") or grid.container

				for _, descendant in ipairs(clone:GetDescendants()) do
					if descendant:IsA("GuiObject") then descendant.Active = false end
				end

				local alpha = config.ghostTransparency or 0.25
				if clone:IsA("GuiObject") then clone.BackgroundTransparency = alpha end
			end))
		end
	end

	table.insert(api._connections, UserInputService.InputChanged:Connect(function(input)
		if not ghost then return end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch then return end

		local screen = ghost:FindFirstAncestorWhichIsA("ScreenGui")
		local inset = screen and screen.IgnoreGuiInset and 0 or 36
		ghost.Position = UDim2.fromOffset(input.Position.X, input.Position.Y - inset)
	end))

	table.insert(api._connections, UserInputService.InputEnded:Connect(function(input)
		if not dragging or input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end

		local from = dragging :: number
		local to = slotUnderCursor(Vector2.new(input.Position.X, input.Position.Y))

		if to and to ~= from then
			local accepted = true
			if config.onDrop then accepted = config.onDrop(from, to) ~= false end

			if accepted then
				local a, b = grid:Get(from), grid:Get(to)
				if a and b then
					local carried = a.Data
					grid:Set(from, b.Data)
					grid:Set(to, carried)
					api.Dropped:Fire(from, to)
				end
			end
		end

		if ghost then
			-- Fantasma some no lugar em vez de piscar: fecha o gesto visualmente.
			Motion.to(ghost, Motion.Easing.Fast, { Size = UDim2.fromOffset(0, 0) }).Completed:Once(clearGhost)
			dragging = nil
		else
			clearGhost()
		end
	end))

	function api:Destroy()
		for _, connection in ipairs(self._connections) do connection:Disconnect() end
		clearGhost()
		self.Dropped:DisconnectAll()
	end

	return api
end

return Draggable
