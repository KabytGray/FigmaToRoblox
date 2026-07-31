--!strict
--[[
	ButtonFx — dá vida a qualquer GuiButton sem alterar seu layout.

	Anima via UIScale, nunca mexendo em Size ou Position: assim funciona igual
	dentro de UIListLayout, UIGridLayout ou posicionamento absoluto.

		ButtonFx.apply(botao)
		ButtonFx.apply(botao, { hover = 1.04, press = 0.97 })
		ButtonFx.applyAll(container) -- todos os descendentes clicáveis
]]

local Motion = require(script.Parent.Parent.core.Motion)

local ButtonFx = {}

export type Options = {
	hover: number?,   -- escala no hover (1 = sem efeito)
	press: number?,   -- escala enquanto pressionado
	sound: string?,   -- rbxassetid:// tocado no clique
}

local DEFAULTS: Options = { hover = 1.03, press = 0.96 }

local function ensureScale(button: GuiButton): UIScale
	local existing = button:FindFirstChildOfClass("UIScale")
	if existing then return existing end

	local scale = Instance.new("UIScale")
	scale.Name = "Fx"
	scale.Parent = button
	return scale
end

--- Aplica os efeitos e devolve uma função de limpeza.
function ButtonFx.apply(button: GuiButton, options: Options?): () -> ()
	local config = options or DEFAULTS
	local hover = config.hover or DEFAULTS.hover :: number
	local press = config.press or DEFAULTS.press :: number

	local scale = ensureScale(button)
	local connections: { RBXScriptConnection } = {}
	local isHovering = false

	local function animate(target: number, info: TweenInfo)
		Motion.to(scale, info, { Scale = target })
	end

	table.insert(connections, button.MouseEnter:Connect(function()
		isHovering = true
		animate(hover, Motion.Easing.Fast)
	end))

	table.insert(connections, button.MouseLeave:Connect(function()
		isHovering = false
		animate(1, Motion.Easing.Fast)
	end))

	table.insert(connections, button.MouseButton1Down:Connect(function()
		animate(press, Motion.Easing.Touch)
	end))

	-- Volta para hover (não para 1) se o mouse ainda está sobre o botão.
	table.insert(connections, button.MouseButton1Up:Connect(function()
		animate(isHovering and hover or 1, Motion.Easing.Fast)
	end))

	if config.sound then
		local sound = Instance.new("Sound")
		sound.Name = "ClickSound"
		sound.SoundId = config.sound
		sound.Parent = button
		table.insert(connections, button.MouseButton1Click:Connect(function()
			sound:Play()
		end))
	end

	return function()
		for _, connection in ipairs(connections) do connection:Disconnect() end
		scale.Scale = 1
	end
end

--- Aplica em todos os botões descendentes. Devolve a limpeza de todos juntos.
function ButtonFx.applyAll(root: Instance, options: Options?): () -> ()
	local cleanups: { () -> () } = {}

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("TextButton") or descendant:IsA("ImageButton") then
			table.insert(cleanups, ButtonFx.apply(descendant, options))
		end
	end

	return function()
		for _, cleanup in ipairs(cleanups) do cleanup() end
	end
end

return ButtonFx
