--!strict
--[[
	Slider — controle de 0 a 1 (ou qualquer faixa) arrastável.

	Espera dois objetos que você desenhou: o trilho e o preenchimento. O punho
	é opcional; sem ele o preenchimento é a única indicação, que já basta para
	volume e sensibilidade.

		local volume = Slider.new(trilho, fill, { handle = punho, value = 0.8 })
		volume.Changed:Connect(function(v) print(v) end)
		volume:Set(0.5)

		-- faixa própria
		local fov = Slider.new(trilho, fill, { min = 60, max = 120, step = 5 })
]]

local UserInputService = game:GetService("UserInputService")

local Motion = require(script.Parent.Parent.core.Motion)
local Signal = require(script.Parent.Parent.core.Signal)

local Slider = {}
Slider.__index = Slider

export type Options = {
	handle: GuiObject?,
	label: TextLabel?,
	min: number?,
	max: number?,
	step: number?,
	value: number?,
	format: ((number) -> string)?,
}

function Slider.new(track: GuiObject, fill: GuiObject, options: Options?)
	assert(track and track:IsA("GuiObject"), "Slider: trilho inválido")
	assert(fill and fill:IsA("GuiObject"), "Slider: preenchimento inválido")

	local config = options or {}
	local self = setmetatable({
		track = track,
		fill = fill,
		handle = config.handle,
		label = config.label,
		min = config.min or 0,
		max = config.max or 1,
		step = config.step,
		format = config.format,
		dragging = false,
		connections = {} :: { RBXScriptConnection },
		Changed = Signal.new(),
		Released = Signal.new(),
	}, Slider)

	-- Preenchimento cresce da esquerda, como na Bar.
	fill.AnchorPoint = Vector2.new(0, fill.AnchorPoint.Y)
	fill.Position = UDim2.new(0, 0, fill.Position.Y.Scale, fill.Position.Y.Offset)

	self:_bind()
	self:Set(config.value or self.min, true)
	return self
end

function Slider:_fractionFromInput(x: number): number
	local left = self.track.AbsolutePosition.X
	local width = math.max(1, self.track.AbsoluteSize.X)
	return math.clamp((x - left) / width, 0, 1)
end

function Slider:_bind()
	-- O trilho inteiro é a área de arraste: mirar num punho de 12px é ruim.
	local function begin(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then return end

		self.dragging = true
		self:_applyFraction(self:_fractionFromInput(input.Position.X), true)
	end

	table.insert(self.connections, self.track.InputBegan:Connect(begin))
	if self.handle then
		table.insert(self.connections, self.handle.InputBegan:Connect(begin))
	end

	table.insert(self.connections, UserInputService.InputChanged:Connect(function(input)
		if not self.dragging then return end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch then return end

		self:_applyFraction(self:_fractionFromInput(input.Position.X), true)
	end))

	table.insert(self.connections, UserInputService.InputEnded:Connect(function(input)
		if not self.dragging then return end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then return end

		self.dragging = false
		self.Released:Fire(self.value)
	end))
end

function Slider:_applyFraction(fraction: number, immediate: boolean?)
	local raw = self.min + fraction * (self.max - self.min)
	self:Set(raw, immediate)
end

--- Define o valor na faixa configurada. `immediate` pula a animação (usado
--- durante o arraste, senão o preenchimento fica atrás do cursor).
function Slider:Set(value: number, immediate: boolean?)
	if self.step and self.step > 0 then
		value = math.floor((value - self.min) / self.step + 0.5) * self.step + self.min
	end
	value = math.clamp(value, self.min, self.max)

	local changed = value ~= self.value
	self.value = value

	local span = self.max - self.min
	local fraction = span > 0 and ((value - self.min) / span) or 0

	local size = UDim2.new(fraction, 0, self.fill.Size.Y.Scale, self.fill.Size.Y.Offset)
	if immediate then
		self.fill.Size = size
	else
		Motion.to(self.fill, Motion.Easing.Fast, { Size = size })
	end

	if self.handle then
		local position = UDim2.new(fraction, 0, self.handle.Position.Y.Scale, self.handle.Position.Y.Offset)
		if immediate then
			self.handle.Position = position
		else
			Motion.to(self.handle, Motion.Easing.Fast, { Position = position })
		end
	end

	if self.label then
		self.label.Text = self.format and self.format(value)
			or (span == 1 and string.format("%d%%", math.floor(fraction * 100 + 0.5)) or tostring(math.floor(value + 0.5)))
	end

	if changed then self.Changed:Fire(value, fraction) end
end

function Slider:Get(): number
	return self.value
end

function Slider:Destroy()
	for _, connection in ipairs(self.connections) do connection:Disconnect() end
	self.Changed:DisconnectAll()
	self.Released:DisconnectAll()
end

return Slider
