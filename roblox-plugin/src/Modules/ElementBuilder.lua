-- ============================================================
-- FigmaToRoblox - Construtor de Elementos
-- src/Modules/ElementBuilder.lua
-- Converte dados do Figma em elementos nativos do Roblox
-- ============================================================

local ElementBuilder = {}

-- ============================================================
-- Constrói um elemento Roblox a partir dos dados convertidos
-- ============================================================

function ElementBuilder.build(elementData)
	if not elementData then
		return nil
	end

	local instance

	-- Cria a instância baseada na classe
	local success, result = pcall(function()
		instance = Instance.new(elementData.className)
	end)

	if not success or not instance then
		warn("FigmaToRoblox: Não foi possível criar elemento da classe " .. tostring(elementData.className))
		return nil
	end

	-- Define nome
	instance.Name = elementData.name or "Element"

	-- Aplica propriedades
	ElementBuilder.applyProperties(instance, elementData.properties or {})

	-- Constrói filhos recursivamente
	if elementData.children then
		for _, childData in ipairs(elementData.children) do
			local child = ElementBuilder.build(childData)
			if child then
				child.Parent = instance
			end
		end
	end

	-- Aplica layout se necessário (Auto Layout do Figma)
	if elementData.properties and elementData.properties.hasAutoLayout then
		ElementBuilder.applyAutoLayout(instance, elementData.properties)
	end

	-- Aplica gradientes
	if elementData.properties and elementData.properties.hasGradient then
		ElementBuilder.applyGradient(instance, elementData.properties.gradientData)
	end

	-- Aplica bordas
	if elementData.properties and elementData.properties.hasStroke then
		ElementBuilder.applyStroke(instance, elementData.properties)
	end

	-- Aplica corner radius
	if elementData.properties and elementData.properties.hasCornerRadius then
		ElementBuilder.applyCornerRadius(instance, elementData.properties)
	end

	return instance
end

-- ============================================================
-- Aplica propriedades a uma instância
-- ============================================================

function ElementBuilder.applyProperties(instance, properties)
	for propName, propValue in pairs(properties) do
		-- Pula propriedades internas (começam com letra minúscula)
		if propName:sub(1, 1) == propName:sub(1, 1):lower() then
			continue
		end

		local success, err = pcall(function()
			-- Verifica se a propriedade existe e é gravável
			if instance[propName] ~= nil then
				instance[propName] = propValue
			end
		end)

		if not success then
			-- Propriedade não aplicável, ignora silenciosamente
		end
	end
end

-- ============================================================
-- Aplica Auto Layout (UIListLayout + UIPadding)
-- ============================================================

function ElementBuilder.applyAutoLayout(instance, properties)
	local layoutDirection = properties.layoutDirection or "VERTICAL"
	local gap = properties.layoutGap or 0
	local padding = properties.layoutPadding or { top = 0, right = 0, bottom = 0, left = 0 }

	-- Cria UIListLayout para organizar os filhos
	local listLayout = Instance.new("UIListLayout")
	listLayout.Name = "AutoLayout"

	if layoutDirection == "HORIZONTAL" then
		listLayout.FillDirection = Enum.FillDirection.Horizontal
	else
		listLayout.FillDirection = Enum.FillDirection.Vertical
	end

	listLayout.Padding = UDim.new(0, gap)

	-- Alinhamento
	local mainAlign = properties.layoutMainAlign or "MIN"
	local crossAlign = properties.layoutCrossAlign or "MIN"

	listLayout.HorizontalAlignment = ElementBuilder.mapMainAlign(mainAlign, layoutDirection)
	listLayout.VerticalAlignment = ElementBuilder.mapCrossAlign(crossAlign, layoutDirection)

	listLayout.Parent = instance

	-- Cria UIPadding se necessário
	if padding.top > 0 or padding.right > 0 or padding.bottom > 0 or padding.left > 0 then
		local uiPadding = Instance.new("UIPadding")
		uiPadding.Name = "AutoLayoutPadding"
		uiPadding.PaddingTop = UDim.new(0, padding.top)
		uiPadding.PaddingRight = UDim.new(0, padding.right)
		uiPadding.PaddingBottom = UDim.new(0, padding.bottom)
		uiPadding.PaddingLeft = UDim.new(0, padding.left)
		uiPadding.Parent = instance
	end
end

function ElementBuilder.mapMainAlign(align, direction)
	if direction == "HORIZONTAL" then
		local map = {
			MIN = Enum.HorizontalAlignment.Left,
			CENTER = Enum.HorizontalAlignment.Center,
			MAX = Enum.HorizontalAlignment.Right,
			SPACE_BETWEEN = Enum.HorizontalAlignment.Center
		}
		return map[align] or Enum.HorizontalAlignment.Left
	else
		local map = {
			MIN = Enum.VerticalAlignment.Top,
			CENTER = Enum.VerticalAlignment.Center,
			MAX = Enum.VerticalAlignment.Bottom,
			SPACE_BETWEEN = Enum.VerticalAlignment.Center
		}
		return map[align] or Enum.VerticalAlignment.Top
	end
end

function ElementBuilder.mapCrossAlign(align, direction)
	if direction == "HORIZONTAL" then
		local map = {
			MIN = Enum.VerticalAlignment.Top,
			CENTER = Enum.VerticalAlignment.Center,
			MAX = Enum.VerticalAlignment.Bottom
		}
		return map[align] or Enum.VerticalAlignment.Center
	else
		local map = {
			MIN = Enum.HorizontalAlignment.Left,
			CENTER = Enum.HorizontalAlignment.Center,
			MAX = Enum.HorizontalAlignment.Right
		}
		return map[align] or Enum.HorizontalAlignment.Center
	end
end

-- ============================================================
-- Aplica Gradientes
-- ============================================================

function ElementBuilder.applyGradient(instance, gradientData)
	if not gradientData or not gradientData.gradientStops then
		return
	end

	local uiGradient = Instance.new("UIGradient")
	uiGradient.Name = "FigmaGradient"

	-- Cria a sequência de cores do gradiente
	local colorSequence = {}
	for _, stop in ipairs(gradientData.gradientStops) do
		local time = stop.position
		local color = stop.color
		if color then
			table.insert(colorSequence, ColorSequenceKeypoint.new(
				time,
				Color3.fromRGB(
					math.floor(color.r * 255),
					math.floor(color.g * 255),
					math.floor(color.b * 255)
				)
			))
		end
	end

	if #colorSequence > 0 then
		uiGradient.Color = ColorSequence.new(colorSequence)

		-- Determina rotação baseada no gradiente
		-- A rotação padrão do Figma é de cima para baixo
		if gradientData.gradientTransform then
			-- Calcula o ângulo a partir da matriz de transformação
			local angle = ElementBuilder.gradientTransformToAngle(gradientData.gradientTransform)
			uiGradient.Rotation = angle
		else
			uiGradient.Rotation = 90 -- Padrão
		end

		uiGradient.Parent = instance
	end
end

function ElementBuilder.gradientTransformToAngle(transform)
	-- Converte a matriz de transformação do Figma em um ângulo
	if not transform or #transform < 2 then
		return 90
	end

	local a = transform[1] and transform[1][1] or 0
	local b = transform[1] and transform[1][2] or 0

	-- Ângulo em radianos, converte para graus
	local angle = math.atan2(b, a) * (180 / math.pi)
	return angle
end

-- ============================================================
-- Aplica Bordas (UIStroke)
-- ============================================================

function ElementBuilder.applyStroke(instance, properties)
	local stroke = Instance.new("UIStroke")
	stroke.Name = "FigmaStroke"
	stroke.Color = properties.strokeColor or Color3.fromRGB(0, 0, 0)
	stroke.Thickness = properties.strokeThickness or 1
	stroke.Transparency = properties.strokeTransparency or 0
	stroke.Parent = instance
end

-- ============================================================
-- Aplica Corner Radius (UICorner)
-- ============================================================

function ElementBuilder.applyCornerRadius(instance, properties)
	local corner = Instance.new("UICorner")
	corner.Name = "FigmaCorner"

	if properties.cornerRadiusValue then
		corner.CornerRadius = UDim.new(0, properties.cornerRadiusValue)
	elseif properties.cornerRadii then
		-- Se cantos diferentes, usa o maior para o UICorner padrão
		local radii = properties.cornerRadii
		local maxRadius = math.max(radii.tl or 0, radii.tr or 0, radii.br or 0, radii.bl or 0)
		corner.CornerRadius = UDim.new(0, maxRadius)
	end

	corner.Parent = instance
end

return ElementBuilder
