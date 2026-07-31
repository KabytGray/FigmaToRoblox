--!strict
--[[
	Tabs — liga botões de aba às páginas correspondentes.

	Casa por nome: o botão "Armas" abre a página "Armas". Se os nomes não
	baterem, passe os pares explicitamente.

		Tabs.new({
			{ button = btnArmas, page = pageArmas },
			{ button = btnPocoes, page = pagePocoes },
		})

		-- ou, por nome, de dois containers:
		Tabs.fromContainers(barraDeAbas, containerDePaginas)
]]

local Motion = require(script.Parent.Parent.core.Motion)
local Signal = require(script.Parent.Parent.core.Signal)
local ButtonFx = require(script.Parent.ButtonFx)

local Tabs = {}
Tabs.__index = Tabs

export type Entry = { button: GuiButton, page: GuiObject, name: string? }

export type Options = {
	activeTransparency: number?,   -- padrão 0
	inactiveTransparency: number?, -- padrão 0.55
	buttonFx: boolean?,
	startIndex: number?,
}

function Tabs.new(entries: { Entry }, options: Options?)
	assert(#entries > 0, "Tabs.new precisa de ao menos uma aba")

	local config = options or {}
	local self = setmetatable({
		entries = entries,
		active = 0,
		activeAlpha = config.activeTransparency or 0,
		inactiveAlpha = config.inactiveTransparency or 0.55,
		Changed = Signal.new(),
	}, Tabs)

	for index, entry in ipairs(entries) do
		if config.buttonFx ~= false then ButtonFx.apply(entry.button) end
		entry.button.MouseButton1Click:Connect(function()
			self:Select(index)
		end)
	end

	self:Select(config.startIndex or 1, true)
	return self
end

--- Monta as abas casando os nomes dos filhos dos dois containers. Ignora
--- layouts e qualquer botão sem página correspondente.
function Tabs.fromContainers(tabBar: GuiObject, pageContainer: GuiObject, options: Options?)
	local entries: { Entry } = {}

	for _, button in ipairs(tabBar:GetChildren()) do
		if button:IsA("GuiButton") then
			local page = pageContainer:FindFirstChild(button.Name)
			if page and page:IsA("GuiObject") then
				table.insert(entries, { button = button, page = page, name = button.Name })
			else
				warn("[Tabs] sem página para a aba \"" .. button.Name .. "\"")
			end
		end
	end

	table.sort(entries, function(a, b) return a.button.LayoutOrder < b.button.LayoutOrder end)
	return Tabs.new(entries, options)
end

function Tabs:Select(index: number, immediate: boolean?)
	if index == self.active or not self.entries[index] then return end
	self.active = index

	for position, entry in ipairs(self.entries) do
		local isActive = position == index
		local alpha = isActive and self.activeAlpha or self.inactiveAlpha

		if immediate then
			entry.button.BackgroundTransparency = alpha
		else
			Motion.to(entry.button, Motion.Easing.Fast, { BackgroundTransparency = alpha })
		end

		if isActive then
			if immediate then entry.page.Visible = true else Motion.enter(entry.page, 6) end
		else
			entry.page.Visible = false
		end
	end

	self.Changed:Fire(index, self.entries[index].name)
end

function Tabs:SelectByName(name: string)
	for index, entry in ipairs(self.entries) do
		if entry.name == name or entry.button.Name == name then
			self:Select(index)
			return
		end
	end
end

function Tabs:GetActive(): (number, string?)
	local entry = self.entries[self.active]
	return self.active, entry and entry.name or nil
end

function Tabs:Destroy()
	self.Changed:DisconnectAll()
end

return Tabs
