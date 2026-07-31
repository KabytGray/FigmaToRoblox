--!strict
--[[
	Boot — liga os Pré-Scripts à UI importada.

	O plugin gera apenas `Config.lua` (dados). Este arquivo é sempre igual, o
	que significa que você pode editá-lo à vontade: reimportar a UI regenera o
	Config, não o Boot.

	Uso, a partir do LocalScript dentro da ScreenGui:

		local FigmaUI = game:GetService("ReplicatedStorage"):WaitForChild("FigmaUI")
		local ui = require(FigmaUI.Boot).start(script.Parent)

		ui.health:Set(50)
		ui.inventory:Set(1, { icon = "rbxassetid://123", amount = 3 })
		ui.shop.Opened:Connect(print)
]]

local Config = require(script.Parent.Config)

local Components = script.Parent.components
local Bar = require(Components.Bar)
local ButtonFx = require(Components.ButtonFx)
local Confirm = require(Components.Confirm)
local Draggable = require(Components.Draggable)
local Hotbar = require(Components.Hotbar)
local Notify = require(Components.Notify)
local Scroll = require(Components.Scroll)
local Selection = require(Components.Selection)
local SettingsPanel = require(Components.SettingsPanel)
local SlotGrid = require(Components.SlotGrid)
local Tabs = require(Components.Tabs)
local Tooltip = require(Components.Tooltip)
local Window = require(Components.Window)

local Signal = require(script.Parent.core.Signal)

local Boot = {}

--- Resolve "HUD.Vida.Fill" a partir da raiz. Devolve nil em vez de estourar:
--- uma camada renomeada no Figma não deve derrubar a UI inteira.
local function resolve(root: Instance, path: string?): Instance?
	if not path or path == "" then return nil end

	local current: Instance? = root
	for segment in string.gmatch(path, "[^%.]+") do
		if not current then return nil end
		current = current:FindFirstChild(segment)
	end
	return current
end

--- Igual ao resolve, mas avisa quando não encontra. Usado para o que é
--- obrigatório para um sistema funcionar.
local function require_(root: Instance, path: string?, label: string): Instance?
	local found = resolve(root, path)
	if not found then
		warn(string.format("[FigmaUI] %s não encontrado (Config.paths = %q)", label, tostring(path)))
	end
	return found
end

function Boot.start(root: Instance)
	local paths = Config.paths or {}
	local options = Config.options or {}
	local systems = Config.systems or {}

	local ui: { [string]: any } = { root = root }

	-- Efeito de hover/press em tudo que é clicável. É o item de maior retorno
	-- por linha escrita: uma UI estática já parece viva.
	if systems.buttonFx then
		ui.buttonFx = ButtonFx.applyAll(root, {
			hover = options.buttonHover,
			press = options.buttonPress,
			sound = options.buttonSound,
		})
	end

	-- Infraestrutura primeiro: notificação e tooltip são usadas pelos outros.
	if systems.notify then
		local container = require_(root, paths.notifyContainer, "container de notificações")
		local template = require_(root, paths.notifyTemplate, "modelo de notificação")
		if container and template then
			Notify.setup(container :: GuiObject, template :: GuiObject)
			ui.notify = Notify
		end
	end

	if systems.tooltip then
		local template = require_(root, paths.tooltipTemplate, "modelo de tooltip")
		if template then
			Tooltip.setup(template :: GuiObject, options.tooltipTextName)
			ui.tooltip = Tooltip
		end
	end

	if systems.confirm then
		local panel = require_(root, paths.confirmPanel, "painel de confirmação")
		if panel then
			Confirm.setup(panel :: GuiObject, {
				message = resolve(root, paths.confirmMessage) :: TextLabel?,
				title = resolve(root, paths.confirmTitle) :: TextLabel?,
				yes = resolve(root, paths.confirmYes) :: GuiButton?,
				no = resolve(root, paths.confirmNo) :: GuiButton?,
			})
			ui.confirm = Confirm
		end
	end

	-- Barras: mesma classe para vida, mana e XP; só mudam os alvos.
	for _, spec in ipairs({
		{ key = "health", flag = "healthBar", fill = "healthFill", label = "healthLabel", max = "healthMax" },
		{ key = "mana", flag = "manaBar", fill = "manaFill", label = "manaLabel", max = "manaMax" },
		{ key = "xp", flag = "xpBar", fill = "xpFill", label = "xpLabel", max = "xpMax" },
	}) do
		if systems[spec.flag] then
			local fill = require_(root, paths[spec.fill], "preenchimento da barra de " .. spec.key)
			if fill then
				ui[spec.key] = Bar.new(fill :: GuiObject, {
					max = options[spec.max] or 100,
					label = resolve(root, paths[spec.label]) :: TextLabel?,
					lowColor = spec.key == "health" and options.healthLowColor or nil,
				})
			end
		end
	end

	-- Janelas genéricas (loja, config, qualquer painel com abrir/fechar).
	for _, spec in ipairs({
		{ key = "shop", flag = "shop", panel = "shopPanel", open = "shopOpenButton", close = "shopCloseButton" },
		{ key = "settings", flag = "settings", panel = "settingsPanel", open = "settingsOpenButton", close = "settingsCloseButton" },
		{ key = "inventoryWindow", flag = "inventory", panel = "inventoryPanel", open = "inventoryOpenButton", close = "inventoryCloseButton" },
	}) do
		if systems[spec.flag] then
			local panel = resolve(root, paths[spec.panel])
			if panel then
				ui[spec.key] = Window.new(panel :: GuiObject, {
					openButton = resolve(root, paths[spec.open]) :: GuiButton?,
					closeButton = resolve(root, paths[spec.close]) :: GuiButton?,
					modal = options.modalWindows ~= false,
					backdrop = options.windowBackdrop == true,
				})
			end
		end
	end

	if systems.inventory then
		local container = require_(root, paths.inventoryContainer, "container do inventário")
		local template = require_(root, paths.inventorySlot, "modelo de slot do inventário")
		if container and template then
			ui.inventory = SlotGrid.new(container :: GuiObject, template :: GuiObject, {
				count = options.inventorySlots or 20,
				columns = options.inventoryColumns or 5,
				padding = options.slotPadding or 6,
				iconName = options.slotIconName,
				amountName = options.slotAmountName,
			})

			if systems.dragAndDrop then
				ui.inventoryDrag = Draggable.items(ui.inventory)
			end

			-- Tooltip do item usa o Data do slot, então precisa do grid pronto.
			if ui.tooltip and options.inventoryTooltips ~= false then
				for index = 1, ui.inventory:Count() do
					local slot = ui.inventory:Get(index)
					if slot then
						Tooltip.bind(slot.Instance, function()
							local data = slot.Data
							return data and (data.label or data.name) or nil
						end)
					end
				end
			end
		end
	end

	if systems.shop then
		local container = resolve(root, paths.shopContainer)
		local template = resolve(root, paths.shopSlot)
		if container and template then
			ui.shopGrid = SlotGrid.new(container :: GuiObject, template :: GuiObject, {
				count = options.shopSlots or 12,
				columns = options.shopColumns or 4,
				padding = options.slotPadding or 6,
				iconName = options.slotIconName,
			})
		end

		local tabBar = resolve(root, paths.shopTabBar)
		local pages = resolve(root, paths.shopPages)
		if tabBar and pages then
			ui.shopTabs = Tabs.fromContainers(tabBar :: GuiObject, pages :: GuiObject)
		end

		-- Fluxo de compra: o clique não compra direto. Passa pela confirmação
		-- quando ela existe, e só então avisa o jogo. Assim o seu código escuta
		-- um único ponto (`Purchased`) em vez de replicar a checagem.
		ui.shopPurchased = Signal.new()

		if ui.shopGrid then
			ui.shopGrid.SlotClicked:Connect(function(index, slot)
				local item = slot.Data
				if item == nil then return end

				local function complete()
					ui.shopPurchased:Fire(index, item)
					if ui.notify then
						ui.notify.success((item.label or "Item") .. " comprado")
					end
				end

				if ui.confirm and options.confirmPurchases ~= false then
					local price = item.price and (" por " .. tostring(item.price)) or ""
					ui.confirm.ask("Comprar " .. (item.label or "este item") .. price .. "?", function(yes)
						if yes then complete() end
					end)
				else
					complete()
				end
			end)
		end
	end

	if systems.hotbar then
		local container = require_(root, paths.hotbarContainer, "container da hotbar")
		local template = require_(root, paths.hotbarSlot, "modelo de slot da hotbar")
		if container and template then
			ui.hotbar = Hotbar.new(container :: GuiObject, template :: GuiObject, {
				count = options.hotbarSlots or 6,
				horizontal = options.hotbarHorizontal ~= false,
				padding = options.slotPadding or 6,
				iconName = options.slotIconName,
				amountName = options.slotAmountName,
			})
		end
	end

	if systems.tabs and not ui.shopTabs then
		local tabBar = require_(root, paths.tabBar, "barra de abas")
		local pages = require_(root, paths.tabPages, "container de páginas")
		if tabBar and pages then
			ui.tabs = Tabs.fromContainers(tabBar :: GuiObject, pages :: GuiObject)
		end
	end

	-- Controles do painel de configurações, detectados pela estrutura das linhas.
	if systems.settingsControls then
		local container = require_(root, paths.settingsContainer, "container de configurações")
		if container then
			ui.settingsControls = SettingsPanel.new(container :: GuiObject)
			if options.logSettings then
				print("[FigmaUI] configurações: " .. ui.settingsControls:Describe())
			end
		end
	end

	-- Todo ScrollingFrame ganha CanvasSize automático. Um recém-criado tem
	-- canvas zero e simplesmente não rola.
	if systems.scroll then
		ui.scrolls = {}
		for _, descendant in ipairs(root:GetDescendants()) do
			if descendant:IsA("ScrollingFrame") then
				local layout = descendant:FindFirstChildOfClass("UIListLayout")
				table.insert(ui.scrolls, Scroll.setup(descendant, {
					horizontal = layout ~= nil and layout.FillDirection == Enum.FillDirection.Horizontal,
					hideBarWhenIdle = options.hideScrollBars ~= false,
				}))
			end
		end
	end

	if systems.selection then
		local container = require_(root, paths.selectionContainer, "container de seleção")
		if container then
			-- 0 no painel significa "sem limite"; passar max = 0 travaria tudo.
			local limit = options.selectionMax
			if not limit or limit <= 0 then limit = nil end

			ui.selection = Selection.fromContainer(container :: GuiObject, {
				multiple = options.selectionMultiple == true,
				max = limit,
				selectedScale = 1.04,
			})
		end
	end

	if systems.dragPanels then
		for _, entry in ipairs(Config.dragPanels or {}) do
			local panel = resolve(root, entry.panel)
			if panel then
				Draggable.panel(panel :: GuiObject, resolve(root, entry.handle) :: GuiObject?)
			end
		end
	end

	return ui
end

return Boot
