--!strict
--[[
	SettingsPanel — varre um painel e transforma as linhas em controles vivos.

	Cada filho do container vira um controle, detectado pelo que tem dentro:

	  tem punho ou check    -> Toggle  (booleano)
	  tem trilho + fill     -> Slider  (número)

	A chave de cada controle é o nome da linha, então "Volume" no Figma vira
	`values.Volume` aqui. Renomear a camada renomeia a configuração.

		local painel = SettingsPanel.new(container)
		painel.Changed:Connect(function(key, value)
			-- mande para o servidor; um script de cliente não persiste sozinho
			salvarRemote:FireServer(key, value)
		end)
		painel:LoadAll(valoresSalvos)
]]

local Signal = require(script.Parent.Parent.core.Signal)
local Slider = require(script.Parent.Slider)
local Toggle = require(script.Parent.Toggle)

local SettingsPanel = {}
SettingsPanel.__index = SettingsPanel

local TOGGLE_HINTS = { "handle", "punho", "knob", "tick", "check", "marca" }
local TRACK_HINTS = { "track", "trilho", "slider", "barra", "bar" }
local FILL_HINTS = { "fill", "preenchimento", "progress", "valor" }

local function normalize(text: string): string
	return (text:lower():gsub("[^%a%d]", ""))
end

--- Primeiro descendente cujo nome contém uma das dicas.
local function findHint(root: Instance, hints: { string }, className: string?): Instance?
	for _, descendant in ipairs(root:GetDescendants()) do
		if not className or descendant:IsA(className) then
			local name = normalize(descendant.Name)
			for _, hint in ipairs(hints) do
				if name:find(hint, 1, true) then return descendant end
			end
		end
	end
	return nil
end

function SettingsPanel.new(container: GuiObject)
	assert(container and container:IsA("GuiObject"), "SettingsPanel: container inválido")

	local self = setmetatable({
		controls = {} :: { [string]: any },
		kinds = {} :: { [string]: string },
		Changed = Signal.new(),
	}, SettingsPanel)

	for _, row in ipairs(container:GetChildren()) do
		if row:IsA("GuiObject") then
			self:_adopt(row)
		end
	end

	return self
end

function SettingsPanel:_adopt(row: GuiObject)
	local key = row.Name
	local label = row:FindFirstChildWhichIsA("TextLabel", true)

	-- Slider primeiro: um trilho com fill é sinal mais específico que um botão.
	local track = findHint(row, TRACK_HINTS, "GuiObject")
	local fill = track and findHint(track, FILL_HINTS, "GuiObject") or findHint(row, FILL_HINTS, "GuiObject")

	if track and fill and fill ~= track then
		local handle = findHint(row, { "handle", "punho", "knob" }, "GuiObject")
		local control = Slider.new(track, fill, { handle = handle, label = label })

		control.Changed:Connect(function(value)
			self.Changed:Fire(key, value)
		end)

		self.controls[key] = control
		self.kinds[key] = "slider"
		return
	end

	local button = row:IsA("GuiButton") and row or row:FindFirstChildWhichIsA("GuiButton", true)
	if button then
		local marker = findHint(row, TOGGLE_HINTS, "GuiObject")
		local isHandle = marker and normalize(marker.Name):find("tick") == nil
			and normalize(marker.Name):find("check") == nil

		local control = Toggle.new(button, {
			handle = isHandle and marker or nil,
			tick = (not isHandle) and marker or nil,
		})

		control.Changed:Connect(function(value)
			self.Changed:Fire(key, value)
		end)

		self.controls[key] = control
		self.kinds[key] = "toggle"
	end
end

function SettingsPanel:Get(key: string): any
	local control = self.controls[key]
	return control and control:Get() or nil
end

function SettingsPanel:Set(key: string, value: any)
	local control = self.controls[key]
	if control then control:Set(value, true) end
end

--- Snapshot para enviar ao servidor.
function SettingsPanel:GetAll(): { [string]: any }
	local values = {}
	for key, control in pairs(self.controls) do
		values[key] = control:Get()
	end
	return values
end

--- Aplica valores salvos sem disparar Changed em cascata: durante o load isso
--- geraria uma rodada de escritas desnecessária.
function SettingsPanel:LoadAll(values: { [string]: any })
	for key, value in pairs(values) do
		local control = self.controls[key]
		if control then control:Set(value, true) end
	end
end

--- Quais controles foram encontrados, para depurar nomes de camada.
function SettingsPanel:Describe(): string
	local parts = {}
	for key, kind in pairs(self.kinds) do
		table.insert(parts, key .. "=" .. kind)
	end
	table.sort(parts)
	return #parts > 0 and table.concat(parts, ", ") or "nenhum controle detectado"
end

function SettingsPanel:Destroy()
	for _, control in pairs(self.controls) do control:Destroy() end
	table.clear(self.controls)
	self.Changed:DisconnectAll()
end

return SettingsPanel
