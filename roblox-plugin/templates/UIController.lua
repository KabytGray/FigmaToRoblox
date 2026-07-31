--[[
	UIController — ponto de entrada da UI gerada.

	Este é o único arquivo que você provavelmente vai querer editar. Ele recebe
	de volta todos os sistemas que o plugin ligou; a partir daqui é o seu jogo.

	Reimportar a UI NÃO sobrescreve este arquivo se ele já existir, justamente
	para o seu código não ser perdido.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FigmaUI = ReplicatedStorage:WaitForChild("FigmaUI")
local ui = require(FigmaUI.Boot).start(script.Parent)

-- ===========================================================================
-- Daqui para baixo é seu. Alguns exemplos do que já está disponível:
-- ===========================================================================

-- Barras (existem se você marcou o sistema correspondente)
-- ui.health:Set(75)
-- ui.health.Emptied:Connect(function() print("morreu") end)
-- ui.mana:Add(-10)
-- ui.xp:SetMax(200, true)

-- Inventário
-- ui.inventory:Set(1, { icon = "rbxassetid://0", amount = 3, label = "Poção" })
-- ui.inventory.SlotClicked:Connect(function(index, slot)
-- 	print("clicou no slot", index, slot.Data)
-- end)

-- Hotbar (teclas 1..9 já ligadas)
-- ui.hotbar.Activated:Connect(function(index, slot)
-- 	print("usou", index)
-- end)

-- Janelas
-- ui.shop:Open()
-- ui.settings.Closed:Connect(function() print("fechou config") end)

-- Notificações
-- ui.notify.success("Item comprado")
-- ui.notify.error("Moedas insuficientes")

-- Confirmação e aviso
-- ui.confirm.ask("Vender por 250 moedas?", function(sim)
-- 	if sim then print("vendeu") end
-- end)
-- ui.confirm.alert("Servidor reiniciando em 30s")

-- Loja: preencha a grade e escute a compra já confirmada
-- ui.shopGrid:Fill({
-- 	{ icon = "rbxassetid://0", label = "Espada", price = 250 },
-- })
-- ui.shopPurchased:Connect(function(index, item)
-- 	comprarRemote:FireServer(item)
-- end)

-- Configurações (um script de cliente não persiste sozinho: mande ao servidor)
-- ui.settingsControls.Changed:Connect(function(chave, valor)
-- 	salvarRemote:FireServer(chave, valor)
-- end)
-- ui.settingsControls:LoadAll(valoresSalvos)

-- Seleção
-- ui.selection.Changed:Connect(function(indices) print(#indices) end)

return ui
