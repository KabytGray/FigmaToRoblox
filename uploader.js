#!/usr/bin/env node
// ============================================================================
// FigmaToRoblox — Uploader local
// ============================================================================
// Ponte obrigatoria entre o Worker e a Open Cloud do Roblox: nem o Cloudflare
// Workers nem o sandbox do Figma conseguem montar o multipart/binario que a
// API de assets exige. Node monta.
//
//   node uploader.js            roda em loop, processa o que aparecer
//   node uploader.js --once     processa a fila atual e sai
//
// Configuracao: config.json (opcional) ou apikey.txt ao lado deste arquivo.
// ============================================================================

"use strict";

const fs = require("fs");
const path = require("path");

const HERE = __dirname;
const ASSETS_URL = "https://apis.roblox.com/assets/v1/assets";
const OPERATIONS_URL = "https://apis.roblox.com/assets/v1/operations/";

// ---------------------------------------------------------------------------
// Configuracao
// ---------------------------------------------------------------------------
function loadConfig() {
  // Padroes vazios de proposito: se alguem baixa e roda sem preencher, e
  // melhor falhar cedo do que subir imagens para a conta errada. O INSTALAR.bat
  // grava config.json com a URL e o userId do proprio usuario.
  const defaults = {
    workerUrl: "",
    userId: "",
    authToken: "",
    pollSeconds: 4,
    concurrency: 3
  };

  const configPath = path.join(HERE, "config.json");
  if (fs.existsSync(configPath)) {
    try {
      // replace(/^﻿/) porque o Set-Content do PowerShell 5.1 grava UTF-8
      // COM BOM, e o JSON.parse morre no primeiro caractere. Sem isto o
      // uploader recusa um config.json que esta perfeitamente correto.
      const bruto = fs.readFileSync(configPath, "utf8").replace(/^﻿/, "");
      Object.assign(defaults, JSON.parse(bruto));
    } catch (e) {
      fail("config.json invalido: " + e.message);
    }
  }

  // --server=URL e --user=ID: trocar de servidor sem reinstalar nem editar JSON
  // na mao. O valor fica gravado, entao vale para as proximas vezes tambem.
  let alterou = false;
  for (const arg of process.argv.slice(2)) {
    const serv = arg.match(/^--server=(.+)$/);
    const usu = arg.match(/^--user=(.+)$/);
    if (serv) {
      defaults.workerUrl = serv[1].trim().replace(/\/+$/, "");
      alterou = true;
    } else if (usu) {
      const num = usu[1].match(/(\d{4,})/);
      if (!num) fail("--user precisa de um ID numerico. Ex: --user=4024894937");
      defaults.userId = num[1];
      alterou = true;
    }
  }

  if (alterou) {
    const guardar = {
      workerUrl: defaults.workerUrl, userId: defaults.userId,
      pollSeconds: defaults.pollSeconds, concurrency: defaults.concurrency
    };
    if (defaults.authToken) guardar.authToken = defaults.authToken;
    fs.writeFileSync(configPath, JSON.stringify(guardar, null, 2), "utf8");
    console.log("  config.json atualizado.");
  }

  if (!defaults.apiKey) {
    const keyPath = path.join(HERE, "apikey.txt");
    if (!fs.existsSync(keyPath)) {
      fail("apikey.txt nao encontrado em " + HERE + "\n" +
           "Crie o arquivo com a API Key do Roblox (escopo asset:read + asset:write).");
    }
    defaults.apiKey = fs.readFileSync(keyPath, "utf8").trim();
  }

  if (!defaults.apiKey) fail("apikey.txt esta vazio.");

  if (!defaults.workerUrl) {
    // Mostrar a PASTA e essencial: quando existe mais de uma copia do projeto,
    // o erro vem da que nao tem config.json, e sem o caminho a pessoa fica
    // procurando defeito na instalacao que esta correta.
    fail("sem servidor configurado.\n" +
         "  Lendo de: " + HERE + "\n\n" +
         "  Para apontar para o seu servidor, rode:\n" +
         "    node uploader.js --server=https://seu-worker.workers.dev");
  }
  if (!defaults.userId) {
    fail("sem userId configurado.\n" +
         "  Lendo de: " + HERE + "\n\n" +
         "  Para preencher, rode:\n" +
         "    node uploader.js --user=SEU_ID_DO_ROBLOX");
  }

  defaults.workerUrl = defaults.workerUrl.replace(/\/+$/, "");
  return defaults;
}

function fail(message) {
  console.error("\n  ERRO  " + message + "\n");
  process.exit(1);
}

// ---------------------------------------------------------------------------
// Console
// ---------------------------------------------------------------------------
const C = {
  reset: "\x1b[0m", dim: "\x1b[2m", bold: "\x1b[1m",
  green: "\x1b[32m", red: "\x1b[31m", yellow: "\x1b[33m",
  cyan: "\x1b[36m", magenta: "\x1b[35m"
};

const log = {
  title: (t) => console.log("\n" + C.magenta + C.bold + t + C.reset),
  info: (t) => console.log("  " + t),
  dim: (t) => console.log("  " + C.dim + t + C.reset),
  ok: (t) => console.log("  " + C.green + "OK" + C.reset + "    " + t),
  err: (t) => console.log("  " + C.red + "FALHA" + C.reset + " " + t),
  warn: (t) => console.log("  " + C.yellow + "AVISO" + C.reset + " " + t)
};

// ---------------------------------------------------------------------------
// Upload de uma imagem para a Open Cloud
// ---------------------------------------------------------------------------
function buildMultipart(bytes, requestJson, filename, mime) {
  const boundary = "----FigmaToRoblox" + Date.now().toString(16) + Math.random().toString(16).slice(2);
  const CRLF = "\r\n";

  const head = Buffer.from(
    "--" + boundary + CRLF +
    'Content-Disposition: form-data; name="request"' + CRLF +
    "Content-Type: application/json" + CRLF + CRLF +
    requestJson + CRLF +
    "--" + boundary + CRLF +
    'Content-Disposition: form-data; name="fileContent"; filename="' + filename + '"' + CRLF +
    "Content-Type: " + mime + CRLF + CRLF
  );
  const tail = Buffer.from(CRLF + "--" + boundary + "--" + CRLF);

  return { body: Buffer.concat([head, bytes, tail]), boundary };
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function pollOperation(operationId, config) {
  // A Open Cloud responde 200 com a operacao ainda em andamento; so `done`
  // significa que o asset existe.
  let delay = 600;
  for (let attempt = 0; attempt < 14; attempt++) {
    await sleep(delay);
    delay = Math.min(Math.round(delay * 1.6), 5000);

    const response = await fetch(OPERATIONS_URL + operationId, {
      headers: { "x-api-key": config.apiKey }
    });

    if (response.status === 429) { delay = 6000; continue; }
    if (!response.ok) continue;

    const data = await response.json();
    if (data.error) throw new Error(data.error.message || JSON.stringify(data.error));
    if (data.done && data.response && data.response.assetId) {
      return "rbxassetid://" + data.response.assetId;
    }
  }
  throw new Error("timeout aguardando a operacao concluir");
}

async function uploadImage(key, base64, displayName, config) {
  const bytes = Buffer.from(base64, "base64");
  const isPng = bytes[0] === 0x89 && bytes[1] === 0x50;
  const mime = isPng ? "image/png" : "image/jpeg";
  const safeName = (displayName || key).replace(/[^a-zA-Z0-9_-]/g, "_").substring(0, 50) || "figma";

  const requestJson = JSON.stringify({
    assetType: "Decal",
    displayName: safeName,
    description: "Importado do Figma via FigmaToRoblox",
    creationContext: { creator: { userId: String(config.userId) } }
  });

  const { body, boundary } = buildMultipart(bytes, requestJson, safeName + (isPng ? ".png" : ".jpg"), mime);

  for (let attempt = 1; attempt <= 3; attempt++) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 45000);

    try {
      const response = await fetch(ASSETS_URL, {
        method: "POST",
        headers: {
          "x-api-key": config.apiKey,
          "Content-Type": "multipart/form-data; boundary=" + boundary
        },
        body,
        signal: controller.signal
      });
      clearTimeout(timer);

      if (response.status === 429) {
        const wait = 5000 * attempt;
        log.warn("limite de taxa atingido, aguardando " + wait / 1000 + "s");
        await sleep(wait);
        continue;
      }

      const text = await response.text();
      if (!response.ok) {
        throw new Error("HTTP " + response.status + " " + text.substring(0, 160));
      }

      const result = JSON.parse(text);
      if (result.done && result.response && result.response.assetId) {
        return "rbxassetid://" + result.response.assetId;
      }
      if (result.path) {
        return await pollOperation(result.path.split("/").pop(), config);
      }
      throw new Error("resposta inesperada: " + text.substring(0, 160));
    } catch (e) {
      clearTimeout(timer);
      const reason = e.name === "AbortError" ? "timeout de 45s" : e.message;
      if (attempt === 3) throw new Error(reason);
      log.dim("tentativa " + attempt + " falhou (" + reason + "), repetindo...");
      await sleep(1500 * attempt);
    }
  }
  throw new Error("esgotadas as tentativas");
}

// ---------------------------------------------------------------------------
// Processamento da fila
// ---------------------------------------------------------------------------
async function mapLimit(items, limit, worker) {
  const results = [];
  let cursor = 0;

  async function run() {
    while (cursor < items.length) {
      const index = cursor++;
      results[index] = await worker(items[index], index);
    }
  }

  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, run));
  return results;
}

async function processExport(entry, config) {
  const keys = Object.keys(entry.images || {});
  if (keys.length === 0) return 0;

  log.title(entry.documentName + "  " + C.dim + "(" + entry.id + ")" + C.reset);
  log.dim(keys.length + " imagem(ns) na fila");

  const resolved = {};
  let done = 0;
  let failed = 0;

  await mapLimit(keys, config.concurrency, async (key) => {
    try {
      const assetId = await uploadImage(key, entry.images[key], (entry.names || {})[key], config);
      resolved[key] = assetId;
      done++;
      log.ok(((entry.names || {})[key] || key) + "  " + C.dim + assetId + C.reset);
    } catch (e) {
      failed++;
      log.err(((entry.names || {})[key] || key) + "  " + e.message);
    }
  });

  if (Object.keys(resolved).length > 0) {
    const headers = { "Content-Type": "application/json" };
    if (config.authToken) headers["Authorization"] = "Bearer " + config.authToken;

    const response = await fetch(config.workerUrl + "/api/resolve-images", {
      method: "POST",
      headers,
      body: JSON.stringify({ exportId: entry.id, resolved })
    });
    const result = await response.json();

    if (result.ready) log.info(C.green + "Export pronto para importar no Studio." + C.reset);
    else log.warn((result.remaining || 0) + " imagem(ns) ainda pendente(s)");
  }

  if (failed > 0) log.warn(failed + " falha(s) neste export");
  return done;
}

async function drainQueue(config) {
  const headers = {};
  if (config.authToken) headers["Authorization"] = "Bearer " + config.authToken;

  const response = await fetch(config.workerUrl + "/api/pending", { headers });
  if (!response.ok) throw new Error("Worker respondeu " + response.status);

  const pending = await response.json();
  if (!Array.isArray(pending) || pending.length === 0) return 0;

  let total = 0;
  for (const entry of pending) total += await processExport(entry, config);
  return total;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
// Porta fixa e alta, escolhida para nao colidir com nada comum. O plugin do
// Studio procura exatamente aqui.
const PORTA_LOCAL = 34567;

/**
 * Anuncia a URL do servidor num endereco local, para o plugin do Roblox se
 * configurar sozinho.
 *
 * Existe porque a pessoa tinha que colar a mesma URL em DOIS lugares (Figma e
 * Studio), e errar um deles gerava um erro que parecia bug do plugin. O
 * uploader ja precisa estar aberto para as imagens subirem, entao ele e o
 * unico ponto que sabe a configuracao certa e esta sempre rodando.
 *
 * So escuta em 127.0.0.1: nada disto fica exposto na rede.
 */
function anunciarLocalmente(config) {
  let servidor;
  try {
    servidor = require("http").createServer((req, res) => {
      res.setHeader("Access-Control-Allow-Origin", "*");
      res.setHeader("Content-Type", "application/json");
      res.end(JSON.stringify({
        workerUrl: config.workerUrl,
        userId: config.userId,
        source: "FigmaToRoblox-uploader"
      }));
    });
  } catch (e) {
    return; // sem http disponivel: o resto do uploader continua funcionando
  }

  servidor.on("error", () => {
    // Porta ocupada (outro uploader aberto) nao e motivo para abortar o upload.
  });
  servidor.listen(PORTA_LOCAL, "127.0.0.1");
}

async function main() {
  const config = loadConfig();
  const once = process.argv.includes("--once");
  if (!once) anunciarLocalmente(config);

  console.log("");
  console.log(C.magenta + C.bold + "  FigmaToRoblox " + C.reset + C.dim + "uploader" + C.reset);
  console.log(C.dim + "  servidor: " + C.reset + config.workerUrl);
  // A pasta importa quando existe mais de uma copia do projeto: e a unica forma
  // de saber qual config.json esta valendo sem ficar adivinhando.
  console.log(C.dim + "  pasta:    " + HERE + C.reset);
  console.log(C.dim + "  (trocar: node uploader.js --server=URL)" + C.reset);

  try {
    const health = await fetch(config.workerUrl + "/api/health");
    const data = await health.json();
    if (data.status !== "ok") throw new Error("resposta inesperada");
    console.log(C.dim + "  worker online · schema v" + data.schemaVersion + C.reset);
  } catch (e) {
    fail("Nao consegui falar com o Worker: " + e.message);
  }

  if (once) {
    const count = await drainQueue(config);
    console.log("\n  " + (count > 0 ? C.green + count + " imagem(ns) enviada(s)." : C.dim + "Fila vazia.") + C.reset + "\n");
    return;
  }

  console.log(C.dim + "  aguardando exports · Ctrl+C para sair" + C.reset + "\n");

  let idleTicks = 0;
  for (;;) {
    try {
      const count = await drainQueue(config);
      if (count > 0) {
        idleTicks = 0;
        process.stdout.write("\n" + C.dim + "  aguardando..." + C.reset);
      } else {
        idleTicks++;
        if (idleTicks % 15 === 0) process.stdout.write(C.dim + "." + C.reset);
      }
    } catch (e) {
      log.err(e.message);
    }
    await sleep(config.pollSeconds * 1000);
  }
}

process.on("SIGINT", () => {
  console.log("\n" + C.dim + "  encerrado." + C.reset + "\n");
  process.exit(0);
});

main().catch((e) => fail(e.stack || e.message));
