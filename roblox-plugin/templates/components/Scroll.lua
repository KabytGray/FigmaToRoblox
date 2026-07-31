--!strict
--[[
	Scroll — configura um ScrollingFrame para realmente rolar.

	Um ScrollingFrame recém-criado tem CanvasSize zero e não rola nada. Este
	módulo resolve isso e cuida dos detalhes que costumam ficar de fora: a barra
	só aparece quando há o que rolar, e a direção segue o layout.

		Scroll.setup(lista)                          -- vertical
		Scroll.setup(carrossel, { horizontal = true })
		Scroll.setup(lista, { padding = 8, autoLayout = true })
]]

local Scroll = {}

export type Options = {
	horizontal: boolean?,
	padding: number?,        -- espaço entre itens quando autoLayout está ligado
	autoLayout: boolean?,    -- cria UIListLayout na direção da rolagem
	barThickness: number?,
	hideBarWhenIdle: boolean?, -- padrão true
	inset: number?,          -- respiro interno
}

--- Prepara o frame. Devolve o próprio frame, para encadear.
function Scroll.setup(frame: ScrollingFrame, options: Options?): ScrollingFrame
	assert(frame and frame:IsA("ScrollingFrame"), "Scroll.setup espera um ScrollingFrame")

	local config = options or {}
	local horizontal = config.horizontal == true

	-- AutomaticCanvasSize é reativo: acompanha filhos entrando e saindo.
	frame.CanvasSize = UDim2.new()
	frame.AutomaticCanvasSize = horizontal and Enum.AutomaticSize.X or Enum.AutomaticSize.Y
	frame.ScrollingDirection = horizontal and Enum.ScrollingDirection.X or Enum.ScrollingDirection.Y
	frame.ScrollBarThickness = config.barThickness or 6
	frame.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
	frame.BorderSizePixel = 0

	if config.autoLayout then
		local existing = frame:FindFirstChildOfClass("UIListLayout")
		local layout = existing or Instance.new("UIListLayout")
		layout.Name = "ScrollLayout"
		layout.FillDirection = horizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical
		layout.Padding = UDim.new(0, config.padding or 6)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = frame
	end

	if config.inset then
		local existing = frame:FindFirstChildOfClass("UIPadding")
		local pad = existing or Instance.new("UIPadding")
		pad.Name = "ScrollPadding"
		pad.PaddingTop = UDim.new(0, config.inset)
		pad.PaddingBottom = UDim.new(0, config.inset)
		pad.PaddingLeft = UDim.new(0, config.inset)
		pad.PaddingRight = UDim.new(0, config.inset)
		pad.Parent = frame
	end

	if config.hideBarWhenIdle ~= false then
		Scroll._autoHideBar(frame, horizontal)
	end

	return frame
end

--- Some com a barra quando o conteúdo cabe na área visível. Uma barra parada
--- num painel que não rola só ocupa espaço.
function Scroll._autoHideBar(frame: ScrollingFrame, horizontal: boolean)
	local thickness = frame.ScrollBarThickness

	local function update()
		local canvas = frame.AbsoluteCanvasSize
		local window = frame.AbsoluteWindowSize
		local overflows = horizontal and (canvas.X > window.X + 1) or (canvas.Y > window.Y + 1)
		frame.ScrollBarThickness = overflows and thickness or 0
	end

	frame:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(update)
	frame:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(update)
	update()
end

--- Rola até um descendente ficar visível.
function Scroll.toObject(frame: ScrollingFrame, target: GuiObject)
	local offset = target.AbsolutePosition - frame.AbsolutePosition
	frame.CanvasPosition = Vector2.new(
		frame.CanvasPosition.X + offset.X,
		frame.CanvasPosition.Y + offset.Y
	)
end

function Scroll.toTop(frame: ScrollingFrame)
	frame.CanvasPosition = Vector2.zero
end

function Scroll.toBottom(frame: ScrollingFrame)
	frame.CanvasPosition = Vector2.new(0, math.max(0, frame.AbsoluteCanvasSize.Y - frame.AbsoluteWindowSize.Y))
end

return Scroll
