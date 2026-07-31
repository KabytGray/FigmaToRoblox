--!strict
--[[
	Confirm — janela de confirmação com callback, sem espalhar estado pelo jogo.

		Confirm.setup(painel, {
			message = painel.Mensagem,
			yes = painel.Sim,
			no = painel.Nao,
		})

		Confirm.ask("Vender a espada por 250 moedas?", function(confirmado)
			if confirmado then vender() end
		end)

	Uma confirmação por vez de propósito: duas caixas empilhadas é sempre bug,
	nunca intenção. Um pedido novo substitui o anterior recusando-o.
]]

local Window = require(script.Parent.Window)

local Confirm = {}

local window: any = nil
local parts: { message: TextLabel?, title: TextLabel?, yes: GuiButton?, no: GuiButton? } = {}
local pending: ((boolean) -> ())? = nil

export type Parts = {
	message: TextLabel?,
	title: TextLabel?,
	yes: GuiButton?,
	no: GuiButton?,
}

--- Resolve o pedido atual uma única vez e limpa o estado.
local function settle(answer: boolean)
	local callback = pending
	pending = nil
	if window then window:Close() end
	if callback then
		local ok, err = pcall(callback, answer)
		if not ok then warn("[Confirm] callback falhou: " .. tostring(err)) end
	end
end

function Confirm.setup(panel: GuiObject, elements: Parts)
	parts = elements
	window = Window.new(panel, { modal = true, backdrop = true })

	if elements.yes then
		elements.yes.MouseButton1Click:Connect(function() settle(true) end)
	end
	if elements.no then
		elements.no.MouseButton1Click:Connect(function() settle(false) end)
	end

	-- Fechar por ESC ou clique fora conta como "não".
	window.Closed:Connect(function()
		if pending then settle(false) end
	end)
end

--- Pergunta. O callback recebe true (sim) ou false (não/cancelado).
function Confirm.ask(message: string, callback: (boolean) -> (), title: string?)
	if not window then
		warn("[Confirm] chame Confirm.setup(painel, partes) antes")
		callback(false)
		return
	end

	-- Pedido anterior ainda aberto: recusa antes de sobrescrever.
	if pending then settle(false) end

	pending = callback
	if parts.message then parts.message.Text = message end
	if parts.title and title then parts.title.Text = title end

	window:Open()
end

--- Popup de aviso: mesma janela, um botão só. Reaproveita o painel de
--- confirmação escondendo o "não" — um segundo painel quase idêntico é
--- manutenção duplicada por nada.
function Confirm.alert(message: string, callback: (() -> ())?, title: string?)
	if not window then
		warn("[Confirm] chame Confirm.setup(painel, partes) antes")
		if callback then callback() end
		return
	end

	if pending then settle(false) end

	local hidden = parts.no
	if hidden then hidden.Visible = false end

	pending = function()
		if hidden then hidden.Visible = true end
		if callback then callback() end
	end

	if parts.message then parts.message.Text = message end
	if parts.title then parts.title.Text = title or "Aviso" end

	window:Open()
end

function Confirm.isOpen(): boolean
	return pending ~= nil
end

return Confirm
