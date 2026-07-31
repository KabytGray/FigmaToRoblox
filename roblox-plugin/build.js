#!/usr/bin/env node
// ============================================================================
// Build do plugin do Roblox
// ============================================================================
// O Studio carrega plugins como UM arquivo .lua. Manter os templates dos
// Pre-Scripts como strings gigantes dentro do plugin seria impossivel de
// revisar, entao eles vivem em templates/ como Lua de verdade (com syntax
// highlight, diff legivel) e este script os embute na saida.
//
//   node build.js            gera dist/FigmaToRoblox.lua
//   node build.js --install  gera e copia para a pasta de plugins do Studio
// ============================================================================

"use strict";

const fs = require("fs");
const path = require("path");
const os = require("os");

const ROOT = __dirname;
const SRC = path.join(ROOT, "FigmaToRoblox.lua");
const TEMPLATE_DIR = path.join(ROOT, "templates");
const OUT_DIR = path.join(ROOT, "dist");
const OUT = path.join(OUT_DIR, "FigmaToRoblox.lua");
const MARKER = "--[[__TEMPLATES__]]";

// Nivel de long-bracket usado para embutir. Se algum template contiver o
// fechamento, o build para em vez de gerar Lua corrompido.
const OPEN = "[====[";
const CLOSE = "]====]";

function collect(dir, prefix, out) {
  if (!fs.existsSync(dir)) return out;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      collect(full, prefix + entry.name + "/", out);
    } else if (entry.name.endsWith(".lua")) {
      out.push({ key: prefix + entry.name.replace(/\.lua$/, ""), file: full });
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Orcamento de locais
// ---------------------------------------------------------------------------
// O Luau permite no maximo 200 variaveis locais VIVAS por funcao, e o plugin
// inteiro e um chunk unico. Estourar isso nao da erro de sintaxe: o plugin
// simplesmente nao carrega, com uma mensagem que so aparece no log do Studio
// ("Out of local registers"). Ja aconteceu duas vezes — por isso o build barra.
//
// ATENCAO ao remediar: um bloco `do ... end` no topo NAO resolve. Os locais
// dele somam aos de topo ate o bloco fechar, entao o pico continua o mesmo. O
// que funciona e mover o trecho para dentro de uma FUNCAO, que ganha os
// proprios 200 registradores (o de fora entra como upvalue).
//
// A contagem confia na convencao do arquivo: local de topo comeca na coluna 0,
// e corpo de funcao fica indentado.
const LOCAL_LIMIT = 200;
const LOCAL_WARN = 185;

function checkLocalBudget(source) {
  let count = 0;
  const names = [];

  for (const line of source.split("\n")) {
    const m = line.match(/^local(?: function)? ([A-Za-z_]\w*)((?:\s*,\s*[A-Za-z_]\w*)*)/);
    if (!m) continue;
    const group = [m[1]].concat((m[2] || "").split(",").map(s => s.trim()).filter(Boolean));
    count += group.length;
    names.push(...group);
  }

  if (count >= LOCAL_LIMIT) {
    console.error(
      "\nlocais de topo: " + count + " — o Luau aceita no maximo " + LOCAL_LIMIT + ".\n" +
      "O plugin NAO vai carregar. Mova um trecho autossuficiente para dentro de\n" +
      "uma funcao (local function ... end + chamada). Bloco do..end nao resolve.\n" +
      "Ultimos declarados: " + names.slice(-6).join(", ") + "\n"
    );
    process.exit(1);
  }

  const label = "locais de topo: " + count + "/" + LOCAL_LIMIT;
  console.log(count >= LOCAL_WARN ? label + "  ATENCAO: pouca folga" : label);
}

function main() {
  if (!fs.existsSync(SRC)) {
    console.error("FigmaToRoblox.lua nao encontrado em " + ROOT);
    process.exit(1);
  }

  let source = fs.readFileSync(SRC, "utf8");
  const templates = collect(TEMPLATE_DIR, "", []);

  const lines = ["local TEMPLATES = {}"];
  let totalBytes = 0;

  for (const { key, file } of templates) {
    const body = fs.readFileSync(file, "utf8").replace(/\r\n/g, "\n");
    if (body.includes(CLOSE)) {
      console.error("Template " + key + ' contem "' + CLOSE + '" e quebraria o embed.');
      process.exit(1);
    }
    totalBytes += body.length;
    lines.push("");
    lines.push("TEMPLATES[" + JSON.stringify(key) + "] = " + OPEN);
    lines.push(body.replace(/\n$/, ""));
    lines.push(CLOSE);
  }

  if (!source.includes(MARKER)) {
    console.error("Marcador " + MARKER + " ausente em FigmaToRoblox.lua.");
    process.exit(1);
  }

  checkLocalBudget(source);

  source = source.replace(MARKER, lines.join("\n"));

  fs.mkdirSync(OUT_DIR, { recursive: true });
  fs.writeFileSync(OUT, source);

  console.log(
    "dist/FigmaToRoblox.lua  " + Math.round(source.length / 1024) + " KB" +
    "  (" + templates.length + " templates, " + Math.round(totalBytes / 1024) + " KB)"
  );
  for (const { key } of templates) console.log("   " + key);

  if (process.argv.includes("--install")) {
    const dest = path.join(process.env.LOCALAPPDATA || os.homedir(), "Roblox", "Plugins", "FigmaToRoblox.lua");
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    fs.copyFileSync(OUT, dest);
    console.log("\ninstalado em " + dest);
  }
}

main();
