--!strict
--[[
	Signal — evento leve para comunicação entre módulos.

	Existe para os componentes avisarem o jogo sem conhecê-lo: a Hotbar dispara
	`Activated`, seu código escuta. Nenhum componente precisa saber quem ouve.

		local changed = Signal.new()
		local conn = changed:Connect(function(value) print(value) end)
		changed:Fire(10)
		conn:Disconnect()
]]

local Signal = {}
Signal.__index = Signal

export type Connection = { Disconnect: (Connection) -> () }

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

--- Registra um ouvinte. Guarde o retorno e chame :Disconnect() ao descartar a UI.
function Signal:Connect(handler: (...any) -> ())
	assert(type(handler) == "function", "Signal:Connect espera uma função")

	local entry = { handler = handler }
	table.insert(self._handlers, entry)

	return {
		Disconnect = function()
			local index = table.find(self._handlers, entry)
			if index then table.remove(self._handlers, index) end
		end,
	}
end

--- Dispara uma única vez e desconecta sozinho.
function Signal:Once(handler: (...any) -> ())
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		handler(...)
	end)
	return connection
end

--- Copia a lista antes de percorrer: um handler pode desconectar durante o Fire.
function Signal:Fire(...)
	local snapshot = table.clone(self._handlers)
	for _, entry in ipairs(snapshot) do
		local ok, err = pcall(entry.handler, ...)
		if not ok then
			warn("[Signal] handler falhou: " .. tostring(err))
		end
	end
end

function Signal:DisconnectAll()
	table.clear(self._handlers)
end

return Signal
