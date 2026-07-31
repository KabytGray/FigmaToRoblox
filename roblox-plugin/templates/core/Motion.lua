--!strict
--[[
	Motion — curvas e durações num só lugar.

	Todo componente anima através daqui, então mudar o "feel" da UI inteira é
	editar este arquivo. Números espalhados por dez módulos é o que faz uma UI
	parecer remendada.
]]

local TweenService = game:GetService("TweenService")

local Motion = {}

--- Durações em segundos. Curto para feedback de toque, longo para transições
--- que o olho precisa acompanhar.
Motion.Duration = {
	Instant = 0.08,
	Fast = 0.14,
	Normal = 0.22,
	Slow = 0.36,
}

Motion.Easing = {
	--- Padrão para quase tudo: sai rápido, desacelera no fim.
	Out = TweenInfo.new(Motion.Duration.Normal, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Fast = TweenInfo.new(Motion.Duration.Fast, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Touch = TweenInfo.new(Motion.Duration.Instant, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	--- Com overshoot: bom para algo que aparece, ruim para algo que sai.
	Pop = TweenInfo.new(Motion.Duration.Normal, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	Smooth = TweenInfo.new(Motion.Duration.Slow, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
}

--- Anima e devolve o tween (já rodando), para quem precisar de .Completed.
function Motion.to(instance: Instance, info: TweenInfo, properties: { [string]: any }): Tween
	local tween = TweenService:Create(instance, info, properties)
	tween:Play()
	return tween
end

--- Igual ao `to`, mas espera terminar. Use em sequências.
function Motion.toAndWait(instance: Instance, info: TweenInfo, properties: { [string]: any })
	Motion.to(instance, info, properties).Completed:Wait()
end

--- Aparece: fade + leve subida. Espera um GuiObject com UIScale opcional.
function Motion.enter(object: GuiObject, offset: number?)
	local rise = offset or 8
	local target = object.Position

	object.Visible = true
	object.Position = target + UDim2.fromOffset(0, rise)
	Motion.to(object, Motion.Easing.Out, { Position = target })
end

--- Desaparece e só então esconde, senão o objeto pisca fora antes de animar.
function Motion.exit(object: GuiObject, offset: number?)
	local drop = offset or 6
	local origin = object.Position

	local tween = Motion.to(object, Motion.Easing.Fast, {
		Position = origin + UDim2.fromOffset(0, drop),
	})
	tween.Completed:Once(function()
		object.Visible = false
		object.Position = origin
	end)
end

return Motion
