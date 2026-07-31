#!/usr/bin/env node
// ============================================================================
// Extrai os icones de classe do Roblox Studio instalado
// ============================================================================
// O Studio moderno nao usa mais o atlas ClassImages.png: `GetClassIcon` devolve
// um PNG por classe em
//   content/studio_svg_textures/Shared/InsertableObjects/<tema>/Standard/
//
// Este script acha a versao mais recente instalada e grava
// assets/classicons.json com um data URI por classe. Rode de novo quando
// atualizar o Studio — os icones mudam entre versoes.
//
//   node tools/extract-icons.js            tema Dark (padrao)
//   node tools/extract-icons.js Light
// ============================================================================

"use strict";

const fs = require("fs");
const path = require("path");
const os = require("os");

const THEME = process.argv[2] || "Dark";
const ROOT = path.join(__dirname, "..");

const CLASSES = [
  "Frame", "ScrollingFrame", "CanvasGroup",
  "TextLabel", "TextButton", "TextBox",
  "ImageLabel", "ImageButton", "ViewportFrame",
  "ScreenGui", "UICorner", "UIStroke", "UIGradient",
  "UIListLayout", "UIGridLayout", "UIPadding"
];

function findIconDir() {
  const versions = path.join(process.env.LOCALAPPDATA || os.homedir(), "Roblox", "Versions");
  if (!fs.existsSync(versions)) return null;

  const candidates = fs.readdirSync(versions)
    .map(name => path.join(versions, name, "content", "studio_svg_textures",
                           "Shared", "InsertableObjects", THEME, "Standard"))
    .filter(dir => fs.existsSync(dir))
    .map(dir => ({ dir, mtime: fs.statSync(dir).mtimeMs }));

  if (candidates.length === 0) return null;
  candidates.sort((a, b) => b.mtime - a.mtime);
  return candidates[0].dir;
}

const dir = findIconDir();
if (!dir) {
  console.error("Nao achei os icones do Studio. O Studio esta instalado?");
  process.exit(1);
}

console.log("tema " + THEME + "\n" + dir + "\n");

const out = {};
const missing = [];
let bytes = 0;

for (const cls of CLASSES) {
  const file = path.join(dir, cls + ".png");
  if (!fs.existsSync(file)) { missing.push(cls); continue; }

  const buffer = fs.readFileSync(file);
  out[cls] = "data:image/png;base64," + buffer.toString("base64");
  bytes += buffer.length;
}

fs.mkdirSync(path.join(ROOT, "assets"), { recursive: true });
const target = path.join(ROOT, "assets", "classicons.json");
fs.writeFileSync(target, JSON.stringify(out));

console.log(Object.keys(out).length + " icones · " + Math.round(bytes / 1024) + " KB brutos · " +
            Math.round(fs.statSync(target).size / 1024) + " KB em base64");
if (missing.length > 0) console.log("ausentes nesta versao: " + missing.join(", "));
