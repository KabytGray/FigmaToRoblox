--!strict
--[[
	Toggle — interruptor ligado a um booleano.

	Funciona com o que você desenhou: um botão e um indicador. O indicador pode
	ser um "punho" que desliza (estilo switch) ou um check que aparece
	(estilo caixa) — o módulo detecta pela presença de `handle`.

		Toggle.new(botao, { handle = punho, value = true })
		Toggle.new(botao, { tick = check })

		local t = Toggle.new(botao, { handle = punho })
		t.Changed:Connect(function(on) print(on) end)
]]

local Motion = require(script.Parent.Parent.core.Motion)
local Signal = require(script.Parent.Parent.core.Signal)

local Toggle = {}
Toggle.__index = Toggle

export type Options = {
	handle: GuiObject?,     -- desliza da esquerda para a direita
	tick: GuiObject?,       -- apenas aparece/desaparece
	track: GuiObject?,      -- muda de cor; padrão é o próprio botão
	value: boolean?,
	onColor: Color3?,
	offColor: Color3?,
	label: TextLabel?,
	onText: string?,
	offText: string?,
}

function Toggle.new(button: GuiButton, options: Options?)
	assert(button and button:IsA("GuiButton"), "Toggle.new espera um GuiButton")

	local config = options or {}
	local self = setmetatable({
		button = button,
		handle = config.handle,
		tick = config.tick,
		track = config.track or button,
		label = config.label,
		onText = config.onText,
		offText = config.offText,
		onColor = config.onColor,
		offColor = config.offColor,
		value = false,
		Changed = Signal.new(),
	}, Toggle)

	-- Guarda as posições do punho antes de qualquer animação, senão a primeira
	-- troca já parte de um valor errado.
	if self.handle then
		local inset = self.handle.Position.X.Offset
		self.offPosition = self.handle.Position
		self.onPosition = UDim2.new(
			1, -(self.handle.Size.X.Offset + inset),
			self.handle.Position.Y.Scale, self.handle.Position.Y.Offset
		)
	end

	button.MouseButton1Click:Connect(function()
		self:Set(not self.value)
	end)

	self:Set(config.value == true, true)
	return self
end

function Toggle:Set(value: boolean, immediate: boolean?)
	local changed = value ~= self.value
	self.value = value

	local info = immediate and Motion.Easing.Touch or Motion.Easing.Fast

	if self.handle then
		local target = value and self.onPosition or self.offPosition
		if immediate then self.handle.Position = target
		else Motion.to(self.handle, info, { Position = target }) end
	end

	if self.tick then
		self.tick.Visible = value
	end

	if self.onColor and self.offColor then
		local color = value and self.onColor or self.offColor
		if immediate then self.track.BackgroundColor3 = color
		else Motion.to(self.track, info, { BackgroundColor3 = color }) end
	end

	if self.label and self.onText and self.offText then
		self.label.Text = value and self.onText or self.offText
	end

	if changed then self.Changed:Fire(value) end
end

function Toggle:Get(): boolean
	return self.value
end

function Toggle:Destroy()
	self.Changed:DisconnectAll()
end

return Toggle
