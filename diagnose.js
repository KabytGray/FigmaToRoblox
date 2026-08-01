#!/usr/bin/env node
// ============================================================================
// FigmaToRoblox — Diagnostico (schema v2)
// ============================================================================
//   node diagnose.js              estado geral do worker + ultimos exports
//   node diagnose.js <exportId>   inspeciona um export especifico
//
// Serve para reproduzir problemas ANTES de mexer no codigo: mostra exatamente
// o que o plugin do Roblox vai receber.
// ============================================================================

"use strict";

const fs = require("fs");
const path = require("path");

const C = { reset: "\x1b[0m", dim: "\x1b[2m", bold: "\x1b[1m",
            green: "\x1b[32m", red: "\x1b[31m", yellow: "\x1b[33m", magenta: "\x1b[35m" };

function workerUrl() {
  const configPath = path.join(__dirname, "config.json");
  if (fs.existsSync(configPath)) {
    try {
      // Sem o BOM: o Set-Content do PowerShell 5.1 grava UTF-8 com marca, e o
      // JSON.parse quebra no primeiro caractere.
      const bruto = fs.readFileSync(configPath, "utf8").replace(/^﻿/, "");
      const cfg = JSON.parse(bruto);
      if (cfg.workerUrl) return cfg.workerUrl.replace(/\/+$/, "");
    } catch (e) { /* cai no aviso abaixo */ }
  }
  // Sem padrao de proposito: ja teve o servidor do autor aqui, e diagnosticar
  // contra o servidor de outra pessoa nao diz nada sobre a instalacao local.
  console.error("\n  Nao achei config.json. Rode a instalacao antes.\n");
  process.exit(1);
}

const BASE = workerUrl();

async function get(route) {
  const response = await fetch(BASE + route);
  const text = await response.text();
  let data;
  try { data = JSON.parse(text); } catch (e) { data = { raw: text.slice(0, 200) }; }
  return { status: response.status, data };
}

// --- estatisticas da arvore ------------------------------------------------
function walk(nodes, stats, depth) {
  for (const node of nodes) {
    stats.total++;
    stats.byClass[node.cls] = (stats.byClass[node.cls] || 0) + 1;
    stats.maxDepth = Math.max(stats.maxDepth, depth);

    if (node.image) {
      stats.images++;
      if (!node.image.id) stats.missingImages.push(node.name + " (" + node.image.key + ")");
    }
    if (node.text) stats.texts++;
    if (node.gradient) stats.gradients++;
    if (node.stroke) stats.strokes++;
    if (node.corner) stats.corners++;
    if (node.layout) stats.layouts++;
    if (node.shadow) stats.shadows++;
    if (node.rot) stats.rotated++;
    if (node.w <= 1 || node.h <= 1) stats.zeroSize.push(node.name);

    if (node.kids && node.kids.length) walk(node.kids, stats, depth + 1);
  }
}

function row(label, value, warn) {
  console.log("  " + label.padEnd(22) + (warn ? C.yellow : "") + value + C.reset);
}

async function inspect(exportId) {
  console.log("\n" + C.bold + C.magenta + "Export " + exportId + C.reset);

  const { status, data } = await get("/api/export/" + exportId);
  if (status !== 200) {
    console.log("  " + C.red + "erro " + status + ": " + (data.error || "") + C.reset + "\n");
    return;
  }

  if (data.schemaVersion !== 2) {
    console.log("  " + C.red + "schema v" + data.schemaVersion + " — o plugin do Roblox espera v2." + C.reset);
    console.log("  " + C.dim + "Re-exporte do Figma com o plugin atualizado." + C.reset + "\n");
    return;
  }

  const stats = { total: 0, images: 0, texts: 0, gradients: 0, strokes: 0, corners: 0,
                  layouts: 0, shadows: 0, rotated: 0, maxDepth: 1, byClass: {},
                  missingImages: [], zeroSize: [] };
  walk(data.roots, stats, 1);

  console.log(C.dim + "  " + data.documentName + " / " + data.pageName + C.reset);
  row("raizes", data.roots.length);
  row("elementos", stats.total);
  row("profundidade", stats.maxDepth);
  row("canvas", data.canvasWidth + " x " + data.canvasHeight);

  console.log();
  for (const cls of Object.keys(stats.byClass).sort()) row(cls, stats.byClass[cls]);

  console.log();
  row("imagens", stats.images);
  row("textos", stats.texts);
  row("gradientes", stats.gradients);
  row("bordas", stats.strokes);
  row("cantos", stats.corners);
  row("auto layout", stats.layouts);
  row("sombras", stats.shadows);
  row("rotacionados", stats.rotated);

  console.log();
  if (data.ready) {
    console.log("  " + C.green + "PRONTO para importar" + C.reset);
  } else {
    console.log("  " + C.yellow + "AGUARDANDO " + stats.missingImages.length + " imagem(ns)" + C.reset);
    console.log("  " + C.dim + "rode: node uploader.js" + C.reset);
    for (const name of stats.missingImages.slice(0, 8)) console.log("    - " + name);
  }

  if (stats.zeroSize.length) {
    console.log("\n  " + C.yellow + stats.zeroSize.length + " elemento(s) com tamanho ~zero:" + C.reset);
    for (const name of stats.zeroSize.slice(0, 8)) console.log("    - " + name);
  }
  console.log();
}

async function overview() {
  console.log("\n" + C.bold + C.magenta + "FigmaToRoblox — diagnostico" + C.reset);
  console.log(C.dim + "  " + BASE + C.reset + "\n");

  const health = await get("/api/health");
  if (health.status !== 200) {
    console.log("  " + C.red + "worker offline (HTTP " + health.status + ")" + C.reset + "\n");
    return;
  }
  row("worker", C.green + "online" + C.reset);
  row("schema", "v" + health.data.schemaVersion);
  row("autenticacao", health.data.auth ? "ativa" : "desligada");

  const pending = await get("/api/pending");
  const queued = Array.isArray(pending.data)
    ? pending.data.reduce((sum, e) => sum + Object.keys(e.images || {}).length, 0) : 0;
  row("fila de upload", queued === 0 ? "vazia" : queued + " imagem(ns)", queued > 0);

  const exports = await get("/api/exports");
  if (!Array.isArray(exports.data) || exports.data.length === 0) {
    console.log("\n  " + C.dim + "nenhum export ainda" + C.reset + "\n");
    return;
  }

  console.log("\n" + C.bold + "  Ultimos exports" + C.reset);
  for (const entry of exports.data.slice(0, 10)) {
    const flag = entry.pendingCount > 0
      ? C.yellow + entry.pendingCount + " pend" + C.reset
      : C.green + "pronto" + C.reset;
    console.log("  " + String(entry.id).padEnd(10) +
                String(entry.elementCount || "?").padStart(4) + " el   " +
                flag.padEnd(20) + C.dim + (entry.rootName || entry.documentName) + C.reset);
  }
  console.log("\n" + C.dim + "  detalhes: node diagnose.js <exportId>" + C.reset + "\n");
}

const arg = process.argv[2];
(arg ? inspect(arg) : overview()).catch((e) => {
  console.error("\n  " + C.red + e.message + C.reset + "\n");
  process.exit(1);
});
