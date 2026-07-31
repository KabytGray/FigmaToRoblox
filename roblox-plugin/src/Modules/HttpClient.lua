-- ============================================================
-- FigmaToRoblox - Módulo HTTP
-- src/Modules/HttpClient.lua
-- Responsável por toda comunicação com o Cloudflare Worker
-- ============================================================

local HttpService = game:GetService("HttpService")

local HttpClient = {}

-- ============================================================
-- Busca um export específico pelo ID
-- ============================================================

function HttpClient.getExport(workerUrl, exportId)
	-- Remove barra no final da URL se existir
	if workerUrl:sub(-1) == "/" then
		workerUrl = workerUrl:sub(1, -2)
	end

	local url = workerUrl .. "/api/export/" .. exportId

	local response = HttpService:RequestAsync({
		Url = url,
		Method = "GET",
		Headers = {
			["Content-Type"] = "application/json"
		}
	})

	if not response.Success then
		error("Falha na requisição: " .. (response.StatusMessage or "Erro desconhecido"))
	end

	local data = HttpService:JSONDecode(response.Body)

	if not data.success and data.error then
		error("Erro do servidor: " .. data.error)
	end

	-- Se veio com success: true, os dados estão no próprio objeto
	-- Se veio direto (sem wrapper), retorna como está
	if data.success then
		-- O worker retorna success:true e o exportId, mas os dados estão no KV
		-- Precisamos de uma segunda chamada? Não - o worker já retorna tudo
		return data.elements and data or nil
	end

	return data
end

-- ============================================================
-- Envia dados do Figma para o Worker
-- ============================================================

function HttpClient.uploadExport(workerUrl, exportData)
	if workerUrl:sub(-1) == "/" then
		workerUrl = workerUrl:sub(1, -2)
	end

	local url = workerUrl .. "/api/upload"

	local body = HttpService:JSONEncode(exportData)

	local response = HttpService:RequestAsync({
		Url = url,
		Method = "POST",
		Headers = {
			["Content-Type"] = "application/json"
		},
		Body = body
	})

	if not response.Success then
		error("Falha ao enviar: " .. (response.StatusMessage or "Erro desconhecido"))
	end

	return HttpService:JSONDecode(response.Body)
end

-- ============================================================
-- Lista todos os exports disponíveis
-- ============================================================

function HttpClient.listExports(workerUrl)
	if workerUrl:sub(-1) == "/" then
		workerUrl = workerUrl:sub(1, -2)
	end

	local url = workerUrl .. "/api/exports"

	local response = HttpService:RequestAsync({
		Url = url,
		Method = "GET",
		Headers = {
			["Content-Type"] = "application/json"
		}
	})

	if not response.Success then
		error("Falha na requisição: " .. (response.StatusMessage or "Erro desconhecido"))
	end

	return HttpService:JSONDecode(response.Body)
end

-- ============================================================
-- Verifica se o Worker está online
-- ============================================================

function HttpClient.healthCheck(workerUrl)
	if workerUrl:sub(-1) == "/" then
		workerUrl = workerUrl:sub(1, -2)
	end

	local url = workerUrl .. "/api/health"

	local success, result = pcall(function()
		local response = HttpService:RequestAsync({
			Url = url,
			Method = "GET"
		})
		return response.Success
	end)

	return success and result == true
end

return HttpClient
