--!strict
--[[
	Bar — barra de vida, mana, XP, stamina, progresso.

	Anima o preenchimento por Size.X.Scale, que é o único jeito que funciona
	igual em qualquer resolução. O `fill` precisa estar dentro de um pai que
	defina a largura total (o trilho) e ter AnchorPoint à esquerda.

		local vida = Bar.new(fill, { max = 100, label = texto })
		vida:Set(75)          -- anima
		vida:Set(75, true)    -- sem animação (ex: ao entrar no jogo)
		vida.Emptied:Connect(function() print("morreu") end)
]]

local Motion = require(script.Parent.Parent.core.Motion)
local Signal = require(script.Parent.Parent.core.Signal)

local Bar = {}
Bar.__index = Bar

export type Options = {
	max: number?,
	value: number?,
	label: TextLabel?,       -- opcional: recebe "75/100"
	format: ((number, number) -> string)?,
	lowColor: Color3?,       -- se definido, o fill tinge quando abaixo de lowAt
	lowAt: number?,          -- fração 0-1, padrão 0.25
}

function Bar.new(fill: GuiObject, options: Options?)
	assert(fill and fill:IsA("GuiObject"), "Bar.new espera o GuiObject de preenchimento")

	local config = options or {}
	local self = setmetatable({
		fill = fill,
		label = config.label,
		format = config.format or function(value, max)
			return string.format("%d/%d", math.floor(value + 0.5), math.floor(max + 0.5))
		end,
		max = config.max or 100,
		value = config.value or config.max or 100,
		lowColor = config.lowColor,
		lowAt = config.lowAt or 0.25,
		baseColor = fill.BackgroundColor3,

		Changed = Signal.new(),
		Emptied = Signal.new(),
		Filled = Signal.new(),
	}, Bar)

	-- Preenchimento cresce da esquerda: sem isso a barra encolhe pelo centro.
	fill.AnchorPoint = Vector2.new(0, fill.AnchorPoint.Y)
	fill.Position = UDim2.new(0, 0, fill.Position.Y.Scale, fill.Position.Y.Offset)

	self:Set(self.value, true)
	return self
end

--- Define o valor. `immediate` pula a animação.
function Bar:Set(value: number, immediate: boolean?)
	local previous = self.value
	self.value = math.clamp(value, 0, self.max)

	local fraction = self.max > 0 and (self.value / self.max) or 0
	local target = UDim2.new(fraction, 0, self.fill.Size.Y.Scale, self.fill.Size.Y.Offset)

	if immediate then
		self.fill.Size = target
	else
		Motion.to(self.fill, Motion.Easing.Out, { Size = target })
	end

	if self.lowColor then
		local color = fraction <= self.lowAt and self.lowColor or self.baseColor
		if immediate then
			self.fill.BackgroundColor3 = color
		else
			Motion.to(self.fill, Motion.Easing.Out, { BackgroundColor3 = color })
		end
	end

	if self.label then
		self.label.Text = self.format(self.value, self.max)
	end

	if self.value ~= previous then
		self.Changed:Fire(self.value, self.max)
		if self.value <= 0 and previous > 0 then self.Emptied:Fire() end
		if self.value >= self.max and previous < self.max then self.Filled:Fire() end
	end
end

function Bar:Add(delta: number)
	self:Set(self.value + delta)
end

--- Troca o máximo mantendo a proporção visual coerente (ex: subiu de nível).
function Bar:SetMax(max: number, keepFraction: boolean?)
	local fraction = self.max > 0 and (self.value / self.max) or 1
	self.max = math.max(1, max)
	self:Set(keepFraction and (fraction * self.max) or self.value)
end

function Bar:GetFraction(): number
	return self.max > 0 and (self.value / self.max) or 0
end

function Bar:Destroy()
	self.Changed:DisconnectAll()
	self.Emptied:DisconnectAll()
	self.Filled:DisconnectAll()
end

return Bar
