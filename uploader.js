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
    fail("config.json sem workerUrl.\nRode INSTALAR.bat na pasta do projeto — ele publica o seu Worker e grava a URL aqui.");
  }
  if (!defaults.userId) {
    fail("config.json sem userId.\nRode INSTALAR.bat de novo para preencher, ou edite o arquivo a mao.");
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
async function main() {
  const config = loadConfig();
  const once = process.argv.includes("--once");

  console.log("");
  console.log(C.magenta + C.bold + "  FigmaToRoblox " + C.reset + C.dim + "uploader" + C.reset);
  console.log(C.dim + "  " + config.workerUrl + C.reset);

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
